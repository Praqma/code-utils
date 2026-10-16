#!/bin/bash

# AI skills usage:
#   Analyze a Git repository and generate object-size reports for downstream rendering.
#   Example:
#   WORKSPACE=/tmp/repo-report debug=true repack=false ./git-object-sizes-in-repo-analyzer.sh /path/to/repo
#
# Runtime configuration (set variables before the command):
#   WORKSPACE=/path       Output and temporary-file directory. Default: current directory.
#   repack=false           Do not repack/gc the repository. Default: true.
#   TAGGED_BLOB_PROCESSING=false
#                          Skip recursive scans of tagged leaf trees. Default: true.
#   TAGGED_BLOB_WORKERS=8 Parallel tagged-tree scans. Default: 8.
#   BRANCH_WORKERS=8      Parallel remote-branch workers. Default: nproc.
#   BLOB_WORKERS=8        Parallel binary-verdict workers. Default: nproc.
#   GIT_BINARY_MODE=8kb   Binary detection: 8kb (fast) or gitdiff (slower, accurate).
#   invest_remote_branches=false
#                          Skip remote-branch investigation. Default: true when available.
#   skip_sizes=true       Skip repository size and Git LFS size collection.
#   LARGEST_NO_EXT_MAX=50
#                          Maximum extension-less files to test. Default: 50.
#   run_git_sizer=false   Skip verbose git-sizer execution. Default: true.
#   GIT_ANALYST_SKIP_LOGS=1
#                          Show Git-log commands without executing them during HTML rendering.
#                          Default: 1. Set to 0 to execute the history queries.
#   debug=true            Enable shell tracing and retain temporary files.
#
# Examples:
#   repack=false TAGGED_BLOB_WORKERS=8 run_git_sizer=false \
#     ./git-object-sizes-in-repo-analyzer.sh /path/to/repo
#   TAGGED_BLOB_PROCESSING=false GIT_ANALYST_SKIP_LOGS=1 \
#     ./git-object-sizes-in-repo-analyzer.sh /path/to/repo

set -eu -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ ${debug:-} == true ]] && { 
  set -x
  keep_tmp_files=true
}

[[ ${repack:-} == "" ]] && repack=true
echo "repack=$repack"

tagged_blob_processing="${TAGGED_BLOB_PROCESSING:-${tagged_blob_processing:-true}}"
echo "tagged_blob_processing=$tagged_blob_processing"

# Select git-side binary detection mode:
# - "8kb"     : fast heuristic (NUL in first 8KB)
# - "gitdiff" : original git diff --no-index --numstat check
git_binary_mode="${GIT_BINARY_MODE:-${git_binary_mode:-gitdiff}}"
case "${git_binary_mode}" in
  8kb|gitdiff) ;;
  *)
    echo "WARNING: Unknown GIT_BINARY_MODE='${git_binary_mode}', valid values: 8kb|gitdiff. Fallback to 'gitdiff'."
    git_binary_mode="gitdiff"
    ;;
esac
echo "Git binary detection mode: ${git_binary_mode} . set git_binary_mode=gitdiff to use git diff --no-index --numstat check - slower but more accurate"


[[ -t 0 ]] && interactive=true || interactive=false
echo "interactive=$interactive"

export PATH=/cygdrive/c/Program\ Files\ \(x86\)/Git/bin:${PATH}
export PATH=/cygdrive/c/Cygwin/bin:${PATH}

export PATH=/c/Program\ Files\ \(x86\)/Git/bin:${PATH}

export PATH=/c/Program\ Files/Git/usr/bin/:${PATH}
export PATH=/c/Program\ Files/Git/bin/:${PATH}
export PATH=/c/Program\ Files/Git/mingw64/bin/:${PATH}

export PATH=/c/Cygwin/bin:${PATH}
export PATH=/usr/bin:${PATH}

function progress_bar_init () {
  processed_percent="0"
  processed_count="0"
  processed_percent_jump="0"
  processed_percent_last="0"
  fill=""
}

function progress_bar_update (){
  processed_count=$(( processed_count + 1 ))
  processed_percent=$(printf "%d\n" "$(( processed_count * 100 / amount_total_unique ))")
  processed_percent_short=$(printf "%d\n" "$(( processed_count * 100 / amount_total_unique /10 ))")
  if [[ ${processed_percent_short} -gt ${processed_percent_jump} ]]; then
    fill="${fill}#"
    processed_percent_jump=$(printf "%d\n" "$(( processed_count * 100 / amount_total_unique /10))")
  fi
  if [[ $processed_percent != "$processed_percent_last" ]]; then
    processed_percent_last=${processed_percent}
    if [[ $interactive == false ]] ; then
      # non-interactive
      printf "[ %-10s ] %4s - %s\n" "$fill" "${processed_percent}%" "$processed_count / $amount_total_unique"
    fi
  fi
  if [[ $interactive == true ]] ; then
    # interactive
    printf "[ %-10s ] %4s - %s\r" "$fill" "${processed_percent}%" "$processed_count / $amount_total_unique"
  fi
}

function bytes_to_megabytes () {
  local bytes="$1"
  local output_var="$2"
  local converted

  if [[ ! "${bytes}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: bytes_to_megabytes expected numeric bytes, got: '${bytes}'" >&2
    return 1
  fi

  converted=$(awk -v bytes="${bytes}" 'BEGIN {
    mb = bytes / 1000000
    if (mb == int(mb)) printf "%.0fM", mb
    else printf "%.1fM", mb
  }')

  printf -v "${output_var}" '%s' "${converted}"
}

function run_verify_pack_all () {
  local output_file="$1"
  local idx_file
  local verified_failed="false"

  printf "[Background function: %s] Verifying pack indexes\n" "${FUNCNAME[0]}"
  : > "${output_file}"
  while IFS= read -r idx_file; do
    [[ -n "${idx_file}" ]] || continue
    [[ -f "${idx_file}" ]] || continue
    if ! git verify-pack -v "${idx_file}" >> "${output_file}"; then
      echo "WARNING: verify-pack failed for idx: ${idx_file} - skip" >&2
      verified_failed="true"
    fi
  done < <(find "${pack_dir}" -name '*.idx' -type f | sort)

  if [[ "${verified_failed}" == "true" ]] ; then
    echo "ERROR: verify-pack failed for one or more idx files" >&2
    return 2
  fi  
}

if [[ ${debug:-} == true ]]; then
  command -v find
  command -v sort

  printf "PATH:\n%s\n" "${PATH}"
fi
if [[ "${WORKSPACE:-}" == "" ]]; then
  WORKSPACE=$(pwd)
  export WORKSPACE
fi
if [[ "${1:-}" != "" ]]; then
  test -e ${1} && cd ${1}
  printf "Changed working directory to: %s\n" "$(pwd)"
fi
echo
git_repo_dir=$(pwd)

git_dir="$(git rev-parse --git-dir)"
echo "git_dir=${git_dir}"
pack_dir="${git_dir}/objects"
if [[ $(git rev-parse --is-bare-repository) == true ]]; then
  echo "repo_type=bare  ( bare / normal )"
  branch_remote_option=""
  default_branch=$(git branch  | grep '^* ' | cut -f 2 -d ' ') || default_branch=""
else
  echo "repo_type=normal ( bare / normal )"
  branch_remote_option="-r"
  default_branch=$(git branch -r | grep origin/HEAD | cut -f 5 -d ' ') || default_branch=""
fi

[[ ${invest_remote_branches:-} == "" ]] && invest_remote_branches=true
if [[ ${default_branch:-} == "" ]]; then
  echo "INFO: default branch not found - do not investigate branches"
  invest_remote_branches=false
fi
echo "invest_remote_branches=$invest_remote_branches"
 
echo
export pack_dir

echo "Analyzing git in: ${git_repo_dir} "
echo "Saving outfiles in: ${WORKSPACE}"
echo

rm -rf "${WORKSPACE}"/*.tmp

file_verify_pack="${WORKSPACE}/verify_pack.tmp" && rm -f "${file_verify_pack}"

rm -f "${WORKSPACE}/bigtosmall_*.txt"
rm -f "${WORKSPACE}/bigobjects*.txt"
rm -f "${WORKSPACE}/allfileshas*.txt"

file_tmp_allfileshas="${WORKSPACE}/allfileshas.tmp" && rm -f "${file_tmp_allfileshas}"

file_tmp_bigobjects="${WORKSPACE}/bigobjects.tmp" && rm -f "${file_tmp_bigobjects}"
file_tmp_bigobjects_revisions="${WORKSPACE}/bigobjects_revisions.tmp" && rm -f "${file_tmp_bigobjects_revisions}"

file_tmp_bigtosmall_join="${WORKSPACE}/bigobjects_join.tmp" && rm -f "${file_tmp_bigtosmall_join}"
file_tmp_bigtosmall_join_revisions="${WORKSPACE}/bigtosmall_revisions_join.tmp" && rm -f "${file_tmp_bigtosmall_join_revisions}"


file_tmp_bigtosmall_join_total="${WORKSPACE}/bigobjects_join_total.tmp" && rm -f "${file_tmp_bigtosmall_join_total}" && touch "${file_tmp_bigtosmall_join_total}"
file_tmp_bigtosmall_join_total_revisions="${WORKSPACE}/bigobjects_join_total_revisions.tmp" && rm -f "${file_tmp_bigtosmall_join_total_revisions}" && touch "${file_tmp_bigtosmall_join_total_revisions}"

file_output_sorted_size_files="${WORKSPACE}/bigtosmall_sorted_size_files.txt" && rm -f "${file_output_sorted_size_files}"
file_output_sorted_size_files_revisions="${WORKSPACE}/bigtosmall_sorted_size_files_revisions.txt" && rm -f "${file_output_sorted_size_files_revisions}"
file_output_sorted_size_files_final="${WORKSPACE}/bigtosmall_sorted_size_files_final.txt" && rm -f "${file_output_sorted_size_files_final}"

file_output_branch_embedded="${WORKSPACE}/branches_embedded.txt" && rm -f "${file_output_branch_embedded}"
file_output_branch_leaves="${WORKSPACE}/branches_leaves.txt" && rm -f "${file_output_branch_leaves}"
file_output_branch_embedded_tagged="${WORKSPACE}/branches_embedded_tagged.txt" && rm -f "${file_output_branch_embedded_tagged}"
file_output_branch_leaves_tagged="${WORKSPACE}/branches_leaves_tagged.txt" && rm -f "${file_output_branch_leaves_tagged}"

file_output_sorted_size_total="${WORKSPACE}/bigtosmall_sorted_size_total.txt" && rm -rf "${file_output_sorted_size_total}"
file_output_sorted_size_total_revisions="${WORKSPACE}/bigtosmall_sorted_size_total_revisions.txt" && rm -rf "${file_output_sorted_size_total_revisions}"
file_output_sorted_size_total_final="${WORKSPACE}/bigtosmall_sorted_size_total_final.txt" && rm -rf "${file_output_sorted_size_total_final}"
file_output_sorted_size_extensions="${WORKSPACE}/bigtosmall_sorted_size_extensions.txt" && rm -rf "${file_output_sorted_size_extensions}"
file_output_largest_per_extension="${WORKSPACE}/bigtosmall_largest_per_extension.txt" && rm -rf "${file_output_largest_per_extension}"
file_output_largest_no_extension="${WORKSPACE}/bigtosmall_largest_no_extension.txt" && rm -rf "${file_output_largest_no_extension}"
file_output_git_size_extensions="${WORKSPACE}/git_size_extensions.txt" && rm -rf "${file_output_git_size_extensions}"
file_output_git_lfs_candidates="${WORKSPACE}/git_lfs_candidates.txt" && rm -rf "${file_output_git_lfs_candidates}"

# Each extension-less row costs one blob-SHA lookup plus three verdict probes, so cap the list.
largest_no_extension_max="${LARGEST_NO_EXT_MAX:-50}"

file_output_git_tags="${WORKSPACE}/git_tags.txt" && rm -f "${file_output_git_tags}"
file_output_git_tags_leaves="${WORKSPACE}/git_tags_leaves.txt" && rm -f "${file_output_git_tags_leaves}"

git for-each-ref --format='%(refname:strip=2)' refs/tags > "${file_output_git_tags}"
git_tags_count=$(wc -l < "${file_output_git_tags}")



file_output_git_sizes="${WORKSPACE}/git_sizes.txt" && rm -rf "${file_output_git_sizes}"

git_sizer_file_verbose="${WORKSPACE}/git_sizer_verbose.txt" && rm -f "${git_sizer_file_verbose}"
git_sizer_file_stderr="${WORKSPACE}/git_sizer_verbose.stderr.txt" && rm -f "${git_sizer_file_stderr}"

printf "Clean old temp packs(if present): \n"
for idx in $(find "${pack_dir}" -name '.tmp*.pack' -o -name '.tmp*.idx') ; do
 echo "$idx"
 rm -f "$idx"
done
printf "Done\n\n"

function is_repo_empty () {
  if [[ $(git rev-list --all --count) -gt 0 ]]; then
    return 1  # Not empty
  else
    return 0  # Empty
  fi
}

function is_repo_empty_and_report_n_exit () {
  if is_repo_empty; then
    echo "[WARNING] empty git repo: $git_repo_dir"
    (
      echo "git_size_total='0'"
      echo "git_size_objects='0'"
      echo "git_size_pack='0'"
      echo "git_size_lfs='0'"
      echo "git_size_modules='0'"
      echo "git_tags_count='${git_tags_count}'"
      echo "git_leaves_tagged_count='${git_leaves_tagged_count}'"
      echo "git_verdict='empty'"
    ) > "${file_output_git_sizes}"
    exit 0;
  else
    echo "git repo is not empty - continue"
  fi
}

is_repo_empty_and_report_n_exit
pack_file=$(find "${pack_dir}" -name '*.idx')
[[ ${pack_file} ==  "" ]] && { 
  echo "No pack file available - do a git gc" 
  git gc 
  pack_file=$(find "${pack_dir}" -name '*.idx')
  [[ ${pack_file} ==  "" ]] && {
    if [[ ${repack:-} != true ]]; then
      echo "ERROR: No pack file available and repack != true - fail"
      exit 1
    fi
    echo "No pack file available - do a repack"
    repack="true"
   }
}

function isFileGitBinaryBlob () {
  if [[ "${git_binary_mode}" == "gitdiff" ]]; then
    local mktmp p t
    mktmp=$(mktemp -p "${WORKSPACE}")
    trap "rm -f ${mktmp}" EXIT

    p=$(printf '%s\t-\t' -)
    git cat-file -p "$1" > "${mktmp}"
    t=$(git diff --no-index --numstat /dev/null "${mktmp}")
    case "$t" in
      "$p"*)
        return 0
        ;;
    esac
    return 1
  fi
}

function isFile8kbNulBlob () {
  # If the blob contains a NUL byte anywhere.
  set +o pipefail
  if git cat-file -p "$1" | LC_ALL=C grep -a -qP '\x00' ; then
    set -o pipefail
    return 0
  fi
  set -o pipefail
  return 1
}

function isFileBinaryBlob () {
  mime_type=$(git cat-file -p "$1" | file --mime-type - | awk -F": " '{print $NF}')

	if [ "${mime_type}" == "empty" ] ; then
		return 2
	fi
  case "${mime_type}" in
    text/*|*/xml|*+xml|*/json|*+json)
      return 1
      ;;
  esac
  return 0
}

function blobSha1For () {
  awk -v key=" $1 $2" 'index($0, key) { print $1; exit }' "${file_tmp_blob_matches}"
}

function blobVerdict () {
  local blob_sha1="$1"
  local verdict=""
  local result=0

  if isFile8kbNulBlob "${blob_sha1}"; then
    verdict="nB"
  else
    verdict="nA"
  fi

  if isFileGitBinaryBlob "${blob_sha1}"; then
    verdict="${verdict}gB"
  else
    verdict="${verdict}gA"
  fi

  isFileBinaryBlob "${blob_sha1}" || result=$?
  if [[ "${result}" -eq 0 ]]; then
    verdict="${verdict}fB"
  elif [[ "${result}" -eq 2 ]]; then
    verdict="${verdict}fE"
  else
    verdict="${verdict}fA"
  fi

  case "${verdict}" in
    nAgAfA)  ;;
    nBgBfB)  verdict="${verdict}-!LFS" ;;
    *B*)     verdict="${verdict}-?analyze" ;;
    *)       verdict="${verdict}-ok" ;;
  esac

  printf '%s' "${verdict}"
}

# Input row: "<seq>\t<want_ext>\t<want_no_ext>\t<size>\t<ext>\t<path>"; output goes to a per-row file so order survives.
function processBlobRow () {
  local seq want_ext_row want_no_ext_row size ext path blob_sha1 verdict
  IFS=$'\t' read -r seq want_ext_row want_no_ext_row size ext path <<< "$1"
  [[ -n "${size}" ]] || return 0

  blob_sha1=$(blobSha1For "${size}" "${path}")
  if [[ -z "${blob_sha1}" ]]; then
    echo "ERROR: Could not find blob SHA1 for size=${size} path=${path}" >&2
    return 1
  fi

  verdict=$(blobVerdict "${blob_sha1}")
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${want_ext_row}" "${want_no_ext_row}" "${size}" "${ext}" "${verdict}" "${path}" \
    > "${WORKSPACE}/blob-worker.${seq}.tmp"
}


if [[ ${repack} == true ]]; then
  echo "git repo and object sizes before repack:"
  du -sh "${git_dir}"
  [[ -d "${pack_dir}" ]] && du -sh "${pack_dir}"
  # reference: https://stackoverflow.com/questions/28720151/git-gc-aggressive-vs-git-repack
  git reflog expire --all --expire=now
  git repack -a -d --depth=250 --window=250 # accept to use old deltas - add "-f" option to not reuse old deltas for large repos it fails often
  git gc --prune
  if [[ ${skip_sizes:-} == "" ]]; then
    echo "git repo and object sizes after repack:"
    [[ -d "${pack_dir}" ]] && du -sh "${pack_dir}"
    du -sh "${git_dir}"
  else
    echo "git repo and object sizes after repack: skipped"
  fi
  pack_file=$(find "${pack_dir}" -name '*.idx')
  [[ ${pack_file} ==  "" ]] && echo "No pack file available - exit 1" && exit 1
else
  printf "repack == false - skip\n\n"
fi

function run_get_lfs_files () {
  printf "[Background function: %s] Running 'git lfs ls-files --all'\n" "${FUNCNAME[0]}"
  : > "${WORKSPACE}/git_lfs_files.txt"
  git lfs ls-files --all > "${WORKSPACE}/git_lfs_files.txt" 2>/dev/null
}

if [[ ${skip_sizes:-} == "" ]]; then
  echo "Get git repo size total"   
  git_size_total=$(du -sb "${git_dir}" | cut -f 1)
  echo "Get git repo size objects" 
  git_size_objects=$(du -sb "${git_dir}/objects" | cut -f 1)
  git_size_pack="0"
  [[ -d "${pack_dir}" ]] && git_size_pack=$(du -sb "${pack_dir}" | cut -f 1)

  echo "Get git modules sizes"
  git_size_modules="0"
  if [[ -d "${git_dir}/modules" ]]; then
    git_size_modules=$(du -sb "${git_dir}/modules" | cut -f 1)
  else
    echo "git modules: no .gitmodules found"
  fi

  : > "${WORKSPACE}/git_modules_urls.txt"
  git show HEAD:.gitmodules 2> /dev/null | git config --file - --get-regexp '^submodule\..*\.url$' > "${WORKSPACE}/git_modules_urls.txt" 2> /dev/null || echo "No .gitmodules found in HEAD"
  git_modules_count=$(wc -l < "${WORKSPACE}/git_modules_urls.txt")

  git_size_lfs="0"
  [[ -d "${git_dir}/lfs" ]] && {
    git_size_lfs=$(du -sb "${git_dir}/lfs" | cut -f 1)
  }

  git_lfs_started=$SECONDS
  run_get_lfs_files & pid_lfs=$!
else
  echo "git lfs and modules sizes: skipped"
  git_lfs_files_count=0
fi

printf "[Background process]: Running git-find-sha1-of-leaf-tags.sh\n"
if [[ -f "$script_dir/git-find-sha1-of-leaf-tags.sh" ]]; then
  leaf_tag_started=$SECONDS
  bash "${script_dir}/git-find-sha1-of-leaf-tags.sh" "$git_repo_dir" > "${file_output_git_tags_leaves}" & pid_git_find_leaf_tags=$!
else
  echo "WARNING: $script_dir/git-find-sha1-of-leaf-tags.sh not found" >&2
  touch "${file_output_git_tags_leaves}"
fi

verify_pack_exit_code=0
verify_pack_started=$SECONDS
run_verify_pack_all "${file_verify_pack}" & pid_verify_pack=$!

printf "[Background process]: Running 'git rev-list --objects --all'\n"
all_objects_started=$SECONDS
git rev-list --objects --all > "${file_tmp_allfileshas}" & pid_allfileshas=$!

file_tmp_leaf_commits="${WORKSPACE}/leaf_commits.tmp"
leaf_commits_started=$SECONDS
printf "[Background process]: Discovering leaf commits once\n"
git rev-list --all --children |
  awk 'NF == 1 && $1 ~ /^[a-f0-9]{40}$/ { print $1 }' |
  LC_ALL=C sort -u > "${file_tmp_leaf_commits}"
printf "[Timing] Unique leaf commit discovery: %ss (%s leaves)\n" \
  "$((SECONDS - leaf_commits_started))" "$(wc -l < "${file_tmp_leaf_commits}")"

regex_lstree_list='^([a-f0-9]{40})[[:space:]]+(.*)$'
declare -A default_blobs_map
declare -A branches_blobs_map

file_tmp_tagged_blobs="${WORKSPACE}/tagged_blobs.tmp"

function process_tagged_tree() {
  local sequence="$1"
  local leaf_sha1="$2"

  git ls-tree -r --full-tree "${leaf_sha1}" |
    awk -F $'\t' '{ split($1, fields, " "); if (fields[3] != "" && $2 != "") print fields[3] "\t" $2 }' \
      > "${WORKSPACE}/tagged_blobs_worker.${sequence}.tmp"
}

function report_temp_usage() {
  local label="$1"

  find "${WORKSPACE}" -maxdepth 1 -type f -name '*.tmp' -printf '%s\n' |
    awk -v label="${label}" '{ files++; bytes += $1 } END {
      printf "[Temp] %s: %d files, %.0f bytes (%.2f GiB)\n", label, files, bytes, bytes / 1073741824
    }'
}

function process_tagged_blobs() {
  printf "[Background function: %s] Processing tagged blobs\n" "${FUNCNAME[0]}"
  local output_file="$1"
  local leaf_list="${file_tmp_leaf_commits}"
  local tag_targets="${output_file}.tag-targets"
  local tagged_leaves="${output_file}.tagged-leaves"
  local tree_jobs="${output_file}.jobs"
  local leaf_sha1
  local sequence=0
  local tagged_blob_workers="${TAGGED_BLOB_WORKERS:-8}"

  if [[ ! "${tagged_blob_workers}" =~ ^[1-9][0-9]*$ ]]; then
    echo "WARNING: Invalid TAGGED_BLOB_WORKERS='${tagged_blob_workers}'; using 8"
    tagged_blob_workers=8
  fi

  # Reuse the shared leaf list; only build the tag-target list here.
  git for-each-ref --format='%(objecttype) %(objectname) %(*objecttype) %(*objectname)' refs/tags |
    awk '$1 == "commit" { print $2 } $3 == "commit" { print $4 }' |
    LC_ALL=C sort -u > "${tag_targets}"
  comm -12 "${leaf_list}" "${tag_targets}" > "${tagged_leaves}"

  : > "${tree_jobs}"
  while IFS= read -r leaf_sha1; do
    [[ -n "${leaf_sha1}" ]] || continue
    sequence=$((sequence + 1))
    printf '%08d %s\n' "${sequence}" "${leaf_sha1}" >> "${tree_jobs}"
  done < "${tagged_leaves}"
  printf "[Background function: %s] Tagged leaves queued=%s workers=%s\n" \
    "${FUNCNAME[0]}" "${sequence}" "${tagged_blob_workers}"

  export -f process_tagged_tree
  export WORKSPACE
  xargs -r -n 2 -P "${tagged_blob_workers}" bash -c \
    'process_tagged_tree "$1" "$2"' tagged-tree-worker < "${tree_jobs}"

  # Keep shard paths in sequence order so the downstream last-path-wins map is unchanged.
  find "${WORKSPACE}" -maxdepth 1 -type f -name 'tagged_blobs_worker.*.tmp' -print |
    LC_ALL=C sort > "${output_file}"
  find "${WORKSPACE}" -maxdepth 1 -type f -name 'tagged_blobs_worker.*.tmp' -printf '%s\n' |
    awk '{ files++; bytes += $1 } END {
      printf "[Temp] Tagged tree shards: %d files, %.0f bytes (%.2f GiB)\n", files, bytes, bytes / 1073741824
    }'
}

if [[ ${tagged_blob_processing} == true ]]; then
  tagged_blobs_started=$SECONDS
  process_tagged_blobs "${file_tmp_tagged_blobs}" & pid_tagged_blobs=$!
else
  echo "tagged_blob_processing != true - skip"
  : > "${file_tmp_tagged_blobs}"
  pid_tagged_blobs=""
fi

echo "Listing all git tags.."
git for-each-ref --format='%(refname:strip=2)' refs/tags > "${file_output_git_tags}"
git_tags_count=$(wc -l < "${file_output_git_tags}")

function process_branch() {
  local branch="$1"
  local branch_id
  local merge_base
  local first
  local second
  local branch_head
  local branch_diff_file
  local head_blob_line
  local branch_blob_line_array

  branch_id=$(printf '%s' "$branch" | sha256sum | cut -d ' ' -f 1)
  local leaf_file="${WORKSPACE}/branch-worker-leaves.${branch_id}.tmp"
  local embedded_file="${WORKSPACE}/branch-worker-embedded.${branch_id}.tmp"
  local blobs_file="${WORKSPACE}/branch-worker-blobs.${branch_id}.tmp"
  : > "$leaf_file"
  : > "$embedded_file"
  : > "$blobs_file"

  branch_diff_commit_files_to_HEAD="$(printf '%-15s' "n/a")"
  branch_head=$(git log -1 --format=%H "$branch")
  if ! grep -Fxq "${branch_head}" "${file_tmp_leaf_commits}"; then
    printf '%s\n' \
      "$(git log --abbrev=12 --oneline --format="%cs : ${branch_diff_commit_files_to_HEAD} : %h : %<(50,mtrunc)%s : %D" "$branch" -1)" \
      > "$embedded_file"
    return 0
  fi

  merge_base=$(git merge-base "$default_branch" "$branch")
  branch_commits_to_HEAD="$(git log --oneline --format=%H "${merge_base}..${branch}" | wc -l)"
  branch_diff_file="${WORKSPACE}/branch-worker-diff.${branch_id}.tmp"
  git diff-tree -r "${merge_base}..${branch}" | cut -f 4- -d ' ' > "${branch_diff_file}"
  branch_files_to_HEAD="$(wc -l < "${branch_diff_file}")"
  branch_diff_commit_files_to_HEAD="$(printf '%-15s' "$branch_commits_to_HEAD/$branch_files_to_HEAD")"
  printf '%s\n' \
    "$(git log --abbrev=12 --oneline --format="%cs : ${branch_diff_commit_files_to_HEAD} : %h : %<(50,mtrunc)%s : %D" "$branch" -1)" \
    > "$leaf_file"

  while read -r head_blob_line; do
    [[ -n "$head_blob_line" ]] || continue
    read -r -a branch_blob_line_array <<< "$head_blob_line"
    if [[ ${branch_blob_line_array[0]} != "0000000000000000000000000000000000000000" ]]; then
      printf '%s\t%s\n' "${branch_blob_line_array[0]}" "${branch_blob_line_array[2]}" >> "$blobs_file"
    fi
  done < "${branch_diff_file}"
  rm -f "${branch_diff_file}"
}

branch_investigation_started=$SECONDS
if [[ ${invest_remote_branches} == true ]]; then
  printf "[Background function: process_branch] Processing remote branch investigation\n"
  echo "Reading blob in default branch: ${default_branch}"
  while read -r lstree_blob_line; do
    if [[ "${lstree_blob_line}" =~ $regex_lstree_list ]] ; then
        default_blob=${BASH_REMATCH[1]}
        default_file=${BASH_REMATCH[2]}
        default_blobs_map["${default_blob}"]="${default_file}"
        [[ ${progress:-} == "true" ]] && printf "."
    else
        echo "ERROR: parsing lstree list: $lstree_blob_line"
        # echo "       using regex:         $regex_lstree_list"
        exit 1
    fi
  done < <( git ls-tree -r ${default_branch} | cut -f 3- -d ' ')
  [[ ${progress:-} == "true" ]] && echo
  
  echo "Reading branches diff blobs.."
  rm -f "${WORKSPACE}"/branch-worker-{leaves,embedded,blobs}.*.tmp
  export -f process_branch
  export WORKSPACE default_branch file_tmp_leaf_commits
  branch_workers="${BRANCH_WORKERS:-$(nproc 2>/dev/null || printf 1)}"
  git branch "${branch_remote_option}" | grep -v '^\*' | cut -f 3 -d ' ' | grep -v 'origin/HEAD$' | tr '\n' '\0' \
     | xargs -0 -r -n 1 -P "${branch_workers}" bash -c 'process_branch "$1"' branch-worker

  find "${WORKSPACE}" -maxdepth 1 -name 'branch-worker-leaves.*.tmp' -type f -print0 |
    xargs -0 -r cat > "${file_output_branch_leaves}.tmp"
  find "${WORKSPACE}" -maxdepth 1 -name 'branch-worker-embedded.*.tmp' -type f -print0 |
    xargs -0 -r cat > "${file_output_branch_embedded}.tmp"
  while IFS=$'\t' read -r branch_blob branch_file; do
    [[ -n "$branch_blob" ]] || continue
    branches_blobs_map["${branch_blob}"]="${branch_file}"
  done < <(
    find "${WORKSPACE}" -maxdepth 1 -name 'branch-worker-blobs.*.tmp' -type f -print0 |
      xargs -0 -r cat
  )
  rm -rf "${WORKSPACE}"/branch-worker-{leaves,embedded,blobs}.*.tmp

  printf "\nSortning branches lists in date order: "
  printf "%-10s : %-15s : %-12s : %-50s : %s\n" \
          "Updated" "commits/files" "sha1" "subject" "refs" >"${file_output_branch_leaves}"
  sort -k1,1r "${file_output_branch_leaves}.tmp"   >> "${file_output_branch_leaves}" 2> /dev/null || echo "INFO: No leaf branches"

  printf "%-10s : %-15s : %-12s : %-50s : %s\n" \
          "Updated" "commits/files" "sha1" "subject" "refs" >"${file_output_branch_embedded}"
  sort -k1,1r "${file_output_branch_embedded}.tmp" >> "${file_output_branch_embedded}" 2> /dev/null || echo "INFO: No embedded branches"
  printf "Done\n"
  
  printf "Make tagged branches lists: "
  printf "%-10s : %-15s : %-12s : %-50s : %s\n" \
          "Updated" "commits/files" "sha1" "subject" "refs" >"${file_output_branch_leaves_tagged}"
  grep -E ' : tag:' "${file_output_branch_leaves}" >> "${file_output_branch_leaves_tagged}" 2> /dev/null || echo "INFO: No leaf branches with tags"
  printf "%-10s : %-15s : %-12s : %-50s : %s\n" \
          "Updated" "commits/files" "sha1" "subject" "refs" >"${file_output_branch_embedded_tagged}"
  grep -E ' : tag:' "${file_output_branch_embedded}" >> "${file_output_branch_embedded_tagged}" 2> /dev/null || echo "INFO: No embedded branches with tags"
  printf "Done\n\n"
# else
  printf "invest_remote_branches != true (%s) - skip\n" "$invest_remote_branches"
fi

printf "Waiting: git-find-sha1-of-leaf-tags.sh to finish: "
wait $pid_git_find_leaf_tags || {
  echo "ERROR: git-find-sha1-of-leaf-tags.sh failed"
  exit 1
}
git_leaves_tagged_count=$(wc -l < "${file_output_git_tags_leaves}")
printf "[Timing] Leaf-tag discovery: %ss\n" "$((SECONDS - leaf_tag_started))"
printf "Done\n\n"

printf "Waiting: git lfs ls-files --all to finish: "
wait "$pid_lfs" || {
  echo "ERROR: git lfs ls-files failed"
  exit 1
}
if [[ ${skip_sizes:-} == "" ]]; then
  printf "[Timing] Git LFS file listing: %ss\n" "$((SECONDS - git_lfs_started))"
fi
printf "Done\n\n"
git_lfs_files_count=$(wc -l < "${WORKSPACE}/git_lfs_files.txt")

[[ ${debug:-} == true ]] && jobs
printf "Waiting: git verify-pack -v for all idx files to finish: "
wait "$pid_verify_pack" || {
  verify_pack_exit_code=$?
  if [[ ${repack:-} != true ]]; then
    echo "ERROR: The verify-pack failed and repack != true - fail"
  else
    echo "try to repack and gc --prune"
    (
      git reflog expire --all --expire=now
      git repack -a -d --depth=250 --window=250 # accept to use old deltas - add "-f" option to not reuse old deltas for large repos it fails often
      git gc --prune
    ) || git gc --prune
    export pack_file=$(find "${pack_dir}" -name '*.idx')
    run_verify_pack_all "${file_verify_pack}" || {
      verify_pack_exit_code=$?
      echo "ERROR: verify-pack failed for all idx files after repack"
    }
  fi
}
printf "[Timing] Pack verification: %ss\n" "$((SECONDS - verify_pack_started))"
printf "Done\n\n"

git_size_objects_count=$(grep -Ec '^[0-9a-f]{40} (commit|tree|blob|tag) ' "${file_verify_pack}" || true)

printf "Waiting: git rev-list --objects --all to finish: "
wait "$pid_allfileshas" || {
  echo "ERROR: git rev-list --objects --all failed"
  exit 1
}
printf "[Timing] All-ref object listing: %ss\n" "$((SECONDS - all_objects_started))"
printf "Done\n\n"

printf "Waiting: tagged blob processing to finish: "
if [[ ${tagged_blob_processing} == true ]]; then
  wait "$pid_tagged_blobs" || {
    echo "ERROR: tagged blob processing failed"
    exit 1
  }
  printf "[Timing] Tagged-blob phase: %ss\n" "$((SECONDS - tagged_blobs_started))"
fi
if [[ ${invest_remote_branches} == true ]]; then
  printf "[Timing] Branch investigation: %ss\n" "$((SECONDS - branch_investigation_started))"
fi
report_temp_usage "after tagged blob processing"
printf "Done\n\n"

declare git_size_total_mega git_size_objects_mega git_size_pack_mega git_size_lfs_mega git_size_modules_mega
bytes_to_megabytes "${git_size_total}" git_size_total_mega
bytes_to_megabytes "${git_size_objects}" git_size_objects_mega
bytes_to_megabytes "${git_size_pack}" git_size_pack_mega
bytes_to_megabytes "${git_size_lfs}" git_size_lfs_mega
bytes_to_megabytes "${git_size_modules}" git_size_modules_mega

cat <<EOF > "${file_output_git_sizes}"
git_size_total='${git_size_total_mega}'
git_size_objects='${git_size_objects_mega}'
git_size_objects_count='${git_size_objects_count}'
git_size_pack='${git_size_pack_mega}'
git_size_lfs='${git_size_lfs_mega}'
git_size_lfs_files_count='${git_lfs_files_count:-0}'
git_size_modules='${git_size_modules_mega}'
git_size_modules_url_count='${git_modules_count:-0}'
git_tags_count='${git_tags_count}'
git_leaves_tagged_count='${git_leaves_tagged_count}'
EOF

git_size_objects_verdict="ok"
if [[ ${git_size_objects:-} -gt $(( 5 * 1024 * 1024 * 1024 )) ]]; then
  git_size_objects_verdict="TOO-BIG"
elif [[ ${git_size_objects:-} -gt $(( 2 * 1024 * 1024 * 1024 )) ]]; then
  git_size_objects_verdict="big"
fi

cat "${file_output_git_sizes}"

touch "${file_output_sorted_size_files}"
echo "Investigate blobs that are directly stored in idx file: ${pack_file}"
if [[ ! $(grep -E "^[a-f0-9]{40}[[:space:]]blob[[:space:]]+[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+$" "${file_verify_pack}" | awk -F" " '{print $1,$2,$3,$4,$5}' > "${file_tmp_bigobjects}") ]]; then
  printf "Amount of objects: %s\n" "$(wc -l < "${file_tmp_bigobjects}")"
  join <(sort "${file_tmp_bigobjects}") <(sort "${file_tmp_allfileshas}") | sort -k 3 -n -r | cut -f 1,3,6-  -d ' ' > "${file_tmp_bigtosmall_join}"

  amount_total_unique=$(awk '{ $1=""; $2=""; sub(/^  */, "", $0); if (!seen[$0]++) count++ } END { print count+0 }' "${file_tmp_bigtosmall_join}")
  printf "Amount of unique <path>/<file>: %s\n" "${amount_total_unique}"
else
  printf "Amount of unique <path>/<file>: 0 - skip\n"
fi

echo "Generate file sorted list:"
file_list_started=$SECONDS
touch "${WORKSPACE}/bigtosmall_errors.txt"

file_tmp_default_blobs_map="${WORKSPACE}/default_blobs_map.tmp" && rm -f "${file_tmp_default_blobs_map}" && touch "${file_tmp_default_blobs_map}"
for blob in "${!default_blobs_map[@]}"; do
  printf "%s\t%s\n" "$blob" "${default_blobs_map[$blob]}" >> "${file_tmp_default_blobs_map}"
done

file_tmp_branches_blobs_map="${WORKSPACE}/branches_blobs_map.tmp" && rm -f "${file_tmp_branches_blobs_map}" && touch "${file_tmp_branches_blobs_map}"
for blob in "${!branches_blobs_map[@]}"; do
  printf "%s\t%s\n" "$blob" "${branches_blobs_map[$blob]}" >> "${file_tmp_branches_blobs_map}"
done

file_tmp_tagged_blobs_map="${file_tmp_tagged_blobs}"

: > "${file_output_sorted_size_files}"
: > "${file_tmp_bigtosmall_join_total}"
aggregation_started=$SECONDS
awk -v default_map="${file_tmp_default_blobs_map}" \
    -v branch_map="${file_tmp_branches_blobs_map}" \
  -v tagged_map="${file_tmp_tagged_blobs_map}" \
    -v details_out="${file_output_sorted_size_files}" \
    -v totals_out="${file_tmp_bigtosmall_join_total}" \
    'BEGIN {
      while ((getline < default_map) > 0) {
        default_path[$1] = $2
      }
      close(default_map)
      while ((getline < branch_map) > 0) {
        branch_path[$1] = $2
      }
      close(branch_map)
      while ((getline tagged_file < tagged_map) > 0) {
        while ((getline tagged_line < tagged_file) > 0) {
          separator = index(tagged_line, "\t")
          if (separator > 0) {
            blob = substr(tagged_line, 1, separator - 1)
            path = substr(tagged_line, separator + 1)
            tagged_path[blob] = path
          }
        }
        close(tagged_file)
      }
      close(tagged_map)
    }
    {
      blob = $1
      size = $2
      $1 = ""
      $2 = ""
      sub(/^  */, "", $0)
      path_file = $0

      prefix = " "
      if ((blob in default_path) && default_path[blob] == path_file) {
        prefix = "H"
      } else if ((blob in branch_path) && branch_path[blob] == path_file) {
        prefix = "B"
      } else if ((blob in tagged_path) && tagged_path[blob] == path_file) {
        prefix = "T"
      }

      print size, prefix, path_file >> details_out

      if (!(path_file in seen)) {
        seen[path_file] = 1
        order[++order_count] = path_file
        total_size[path_file] = 0
        total_count[path_file] = 0
        total_prefix[path_file] = " "
      }

      total_size[path_file] += size
      total_count[path_file] += 1

      if (prefix == "H") {
        total_prefix[path_file] = "H"
      } else if (prefix == "B" && total_prefix[path_file] != "H") {
        total_prefix[path_file] = "B"
      } else if (prefix == "T" && total_prefix[path_file] == " ") {
        total_prefix[path_file] = "T"
      }
    }
    END {
      for (i = 1; i <= order_count; i++) {
        path_file = order[i]
        printf "%s %s %s %s ( I )\n", total_size[path_file], total_prefix[path_file], total_count[path_file], path_file >> totals_out
      }
    }' "${file_tmp_bigtosmall_join}"
printf "[Timing] Direct-object list aggregation (including tag-map loading): %ss\n" "$((SECONDS - aggregation_started))"
sort_started=$SECONDS
/usr/bin/sort -u -h -r "${file_tmp_bigtosmall_join_total}" > "${file_output_sorted_size_total}"
printf "[Timing] Direct-object totals sort: %ss\n" "$((SECONDS - sort_started))"
printf "[Timing] Direct-object file-list phase: %ss\n" "$((SECONDS - file_list_started))"
printf "\n\n"

touch "${file_output_sorted_size_files_revisions}"
echo "Investigate blobs that are packed in revisions in idx file: ${pack_file}"
if [[ ! $(grep -E "^[a-f0-9]{40}[[:space:]]blob[[:space:]]+[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][a-f0-9]{40}$" "${file_verify_pack}" | awk -F" " '{print $1,$2,$3,$4,$5}' > "${file_tmp_bigobjects_revisions}") ]]; then
  printf "Amount of objects: %s\n" "$(wc -l < "${file_tmp_bigobjects_revisions}")"
  join <(sort "${file_tmp_bigobjects_revisions}") <(sort "${file_tmp_allfileshas}") | sort -k 3 -n -r | cut -f 1,3,6- -d ' '  > "${file_tmp_bigtosmall_join_revisions}"
  amount_total_unique=$(awk '{ $1=""; $2=""; sub(/^  */, "", $0); if (!seen[$0]++) count++ } END { print count+0 }' "${file_tmp_bigtosmall_join_revisions}")
  printf "Amount of unique <path>/<file>: %s\n" "${amount_total_unique}"
else
  printf "Amount of objects: 0 - skip\n"
fi

echo "Generate file sorted list:"
revision_list_started=$SECONDS
touch "${WORKSPACE}/bigtosmall_errors_revision.txt"
: > "${file_output_sorted_size_files_revisions}"
: > "${file_tmp_bigtosmall_join_total_revisions}"
revision_aggregation_started=$SECONDS
awk -v default_map="${file_tmp_default_blobs_map}" \
    -v branch_map="${file_tmp_branches_blobs_map}" \
  -v tagged_map="${file_tmp_tagged_blobs_map}" \
    -v details_out="${file_output_sorted_size_files_revisions}" \
    -v totals_out="${file_tmp_bigtosmall_join_total_revisions}" \
    'BEGIN {
      while ((getline < default_map) > 0) {
        default_path[$1] = $2
      }
      close(default_map)
      while ((getline < branch_map) > 0) {
        branch_path[$1] = $2
      }
      close(branch_map)
      while ((getline tagged_file < tagged_map) > 0) {
        while ((getline tagged_line < tagged_file) > 0) {
          separator = index(tagged_line, "\t")
          if (separator > 0) {
            blob = substr(tagged_line, 1, separator - 1)
            path = substr(tagged_line, separator + 1)
            tagged_path[blob] = path
          }
        }
        close(tagged_file)
      }
      close(tagged_map)
    }
    {
      blob = $1
      size = $2
      $1 = ""
      $2 = ""
      sub(/^  */, "", $0)
      path_file = $0

      prefix = " "
      if ((blob in default_path) && default_path[blob] == path_file) {
        prefix = "H"
      } else if ((blob in branch_path) && branch_path[blob] == path_file) {
        prefix = "B"
      } else if ((blob in tagged_path) && tagged_path[blob] == path_file) {
        prefix = "T"
      }

      print size, prefix, path_file >> details_out

      if (!(path_file in seen)) {
        seen[path_file] = 1
        order[++order_count] = path_file
        total_size[path_file] = 0
        total_count[path_file] = 0
        total_prefix[path_file] = " "
      }

      total_size[path_file] += size
      total_count[path_file] += 1

      if (prefix == "H") {
        total_prefix[path_file] = "H"
      } else if (prefix == "B" && total_prefix[path_file] != "H") {
        total_prefix[path_file] = "B"
      } else if (prefix == "T" && total_prefix[path_file] == " ") {
        total_prefix[path_file] = "T"
      }
    }
    END {
      for (i = 1; i <= order_count; i++) {
        path_file = order[i]
        printf "%s %s %s %s ( P )\n", total_size[path_file], total_prefix[path_file], total_count[path_file], path_file >> totals_out
      }
    }' "${file_tmp_bigtosmall_join_revisions}"
printf "[Timing] Revision-object list aggregation: %ss\n" "$((SECONDS - revision_aggregation_started))"
revision_sort_started=$SECONDS
/usr/bin/sort -u -h -r "${file_tmp_bigtosmall_join_total_revisions}" > "${file_output_sorted_size_total_revisions}"
printf "[Timing] Revision-object totals sort: %ss\n" "$((SECONDS - revision_sort_started))"
printf "[Timing] Revision-object file-list phase: %ss\n" "$((SECONDS - revision_list_started))"
printf "\n\n"

final_sort_started=$SECONDS
cat "${file_output_sorted_size_total_revisions}" "${file_output_sorted_size_total}" | sort -k 1 -h -r > "${file_output_sorted_size_total_final}"
cat "${file_output_sorted_size_files_revisions}" "${file_output_sorted_size_files}" | sort -k 1 -h -r > "${file_output_sorted_size_files_final}"
printf "[Timing] Combined final list sorts: %ss\n" "$((SECONDS - final_sort_started))"
report_temp_usage "after file-list generation"

# Largest single file per extension from the pre-sorted file-level report.
# Input rows are either: "<size> <path>" or "<size> <H|B> <path>".
declare -A ext_seen
no_ext_written=0
blob_wanted_count=0
: > "${file_output_largest_per_extension}"
: > "${file_output_largest_no_extension}"

file_tmp_blob_wanted="${WORKSPACE}/blob_wanted.tmp" && : > "${file_tmp_blob_wanted}"
file_tmp_blob_patterns="${WORKSPACE}/blob_patterns.tmp" && : > "${file_tmp_blob_patterns}"
file_tmp_blob_matches="${WORKSPACE}/blob_matches.tmp" && : > "${file_tmp_blob_matches}"

# Pass 1: pick the rows worth a verdict. Pure bash, no forks, so it stays cheap on huge reports.
blob_selection_started=$SECONDS
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue

  size="${line%% *}"
  rest="${line#"${size}"}"
  rest="${rest#"${rest%%[![:space:]]*}"}"

  marker="${rest%% *}"
  if [[ "${marker}" == "H" || "${marker}" == "B" || "${marker}" == "T" ]]; then
    path="${rest#?}"
    path="${path#"${path%%[![:space:]]*}"}"
  else
    path="${rest}"
  fi

  base="${path##*/}"
  ext="[no_ext]"
  if [[ "${base}" == *.* ]]; then
    ext="${base##*.}"
    [[ -n "${ext}" ]] || ext="[no_ext]"
  fi
  ext="${ext,,}"

  want_ext_row=0
  want_no_ext_row=0
  [[ -z "${ext_seen[${ext}]+x}" ]] && want_ext_row=1
  if [[ "${ext}" == "[no_ext]" && "${no_ext_written}" -lt "${largest_no_extension_max}" ]]; then
    want_no_ext_row=1
    no_ext_written=$(( no_ext_written + 1 ))
  fi

  if [[ "${want_ext_row}" -eq 1 || "${want_no_ext_row}" -eq 1 ]]; then
    ext_seen["${ext}"]=1
    blob_wanted_count=$(( blob_wanted_count + 1 ))
    printf '%06d\t%s\t%s\t%s\t%s\t%s\n' \
      "${blob_wanted_count}" "${want_ext_row}" "${want_no_ext_row}" "${size}" "${ext}" "${path}" >> "${file_tmp_blob_wanted}"
    printf ' %s %s\n' "${size}" "${path}" >> "${file_tmp_blob_patterns}"
  fi
done < "${file_output_sorted_size_files_final}"
printf "[Timing] Verdict row selection: %ss (%s candidates)\n" \
  "$((SECONDS - blob_selection_started))" "${blob_wanted_count}"

# Pass 2: resolve every blob SHA1 in one sweep of the joined object lists instead of one grep per row.
blob_lookup_started=$SECONDS
if [[ -s "${file_tmp_blob_patterns}" ]]; then
  grep -h -F -f "${file_tmp_blob_patterns}" \
      "${file_tmp_bigtosmall_join}" \
      "${file_tmp_bigtosmall_join_revisions}" \
    > "${file_tmp_blob_matches}" || true
fi
  printf "[Timing] Blob-pattern lookup: %ss\n" "$((SECONDS - blob_lookup_started))"

# Pass 3: one verdict per selected row, in parallel - each row costs three git probes over the full blob.
echo "Computing binary verdicts for ${blob_wanted_count} blobs.."
rm -f "${WORKSPACE}"/blob-worker.*.tmp
export -f processBlobRow blobSha1For blobVerdict isFile8kbNulBlob isFileGitBinaryBlob isFileBinaryBlob
export WORKSPACE file_tmp_blob_matches git_binary_mode
blob_workers="${BLOB_WORKERS:-$(nproc 2>/dev/null || printf 1)}"
tr '\n' '\0' < "${file_tmp_blob_wanted}" \
  | xargs -0 -r -n 1 -P "${blob_workers}" bash -c 'processBlobRow "$1"' blob-worker

while IFS=$'\t' read -r want_ext_row want_no_ext_row size ext verdict path; do
  [[ -n "${size}" ]] || continue

  case "${verdict}" in
    *'-!LFS'|*'-?analyze')
      printf "INFO: %s %s %s %s\n" "${size}" "${ext}" "${verdict}" "${path}"
      ;;
  esac

  if [[ "${want_ext_row}" -eq 1 ]]; then
    printf "%s %s %s %s\n" "${size}" "${ext}" "${verdict}" "${path}" >> "${file_output_largest_per_extension}"
  fi

  if [[ "${want_no_ext_row}" -eq 1 ]]; then
    printf "%s %s %s %s\n" "${size}" "${ext}" "${verdict}" "${path}" >> "${file_output_largest_no_extension}"
  fi
done < <(find "${WORKSPACE}" -maxdepth 1 -name 'blob-worker.*.tmp' -type f -print0 | sort -z | xargs -0 -r cat)
rm -f "${WORKSPACE}"/blob-worker.*.tmp
echo "Largest file per extension: ${file_output_largest_per_extension}"
echo "Largest files without extension (max ${largest_no_extension_max}): ${file_output_largest_no_extension}"

# Glob patterns for `git lfs migrate import --include=` / .gitattributes, split by confidence.
awk -v q="'" '
{
  ext = $2
  verdict = $3
  if (ext == "[no_ext]") next
  if (verdict ~ /-!LFS$/ || tolower(verdict) ~ /must-lfs/) {
    red = (red == "" ? "*." ext : red ",*." ext)
  } else if (verdict != "nAgAfA" && verdict !~ /-ok$/) {
    yellow = (yellow == "" ? "*." ext : yellow ",*." ext)
  }
}
END {
  printf "git_lfs_candidates=%s%s%s\n", q, red, q
  printf "git_lfs_mixed=%s%s%s\n", q, yellow, q
}' "${file_output_largest_per_extension}" > "${file_output_git_lfs_candidates}"
echo "Git LFS candidate extensions: ${file_output_git_lfs_candidates}"

# Aggregate total size by file extension from the final totals report.
awk 'BEGIN { OFS=" " }
{
  size = $1
  $1 = ""
  $2 = ""
  sub(/^ +/, "", $0)
  sub(/ \( [IP] \)$/, "", $0)

  file = $0
  n = split(file, parts, "/")
  name = parts[n]

  ext = "[no_ext]"
  if (name ~ /\./) {
    ext = name
    sub(/^.*\./, "", ext)
    if (ext == "") ext = "[no_ext]"
  }

  ext = tolower(ext)
  ext_total[ext] += size
  ext_count[ext] += 1
}
END {
  for (e in ext_total) {
    printf "%s %s %s\n", ext_total[e], ext_count[e], e
  }
}' "${file_output_sorted_size_total_final}" | sort -k 1 -n -r > "${file_output_sorted_size_extensions}"

awk 'NR == FNR {
  ext_verdict[$2] = $3
  next
}
NR > 0 {
  bytes = $1
  count = $2
  ext = $3
  mb = bytes / 1000000
  if (mb == int(mb)) size_m = sprintf("%.0fM", mb)
  else size_m = sprintf("%.1fM", mb)
  verdict = (ext in ext_verdict) ? ext_verdict[ext] : "n/a"
  printf "%s=%s (%s) %s\n", ext, size_m, count, verdict
}' "${file_output_largest_per_extension}" "${file_output_sorted_size_extensions}" > "${file_output_git_size_extensions}"


git_size_extensions=$(awk 'NR > 0 {
  ext = $3
  if (out == "") out = ext
  else out = out "," ext
}
END {
  if (out == "") print "[no_ext]"
  else print out
}' "${file_output_sorted_size_extensions}")

# Find the largest single file revision in size in bytes and convert it to a human-readable format
git_size_largest="0b"
if [[ -s "${file_output_sorted_size_files_final}" ]]; then
  git_size_largest_bytes=$(head -n 1 "${file_output_sorted_size_files_final}" | cut -f 1 -d ' ')
  bytes_to_megabytes "${git_size_largest_bytes}" git_size_largest
fi



git_size_lfs_verdict="n/a"
if [[ ${git_size_largest_bytes} -gt $((1024*1024*100)) ]]; then
  git_size_lfs_verdict="Must-LFS"
elif [[ ${git_size_largest_bytes} -gt $((1024*1024*10)) ]]; then
  git_size_lfs_verdict="Could-LFS"
else
  git_size_lfs_verdict="No-issues-detected"
fi

cat << EOF >> "${file_output_git_sizes}"
git_size_largest='${git_size_largest}'
git_size_extensions='${git_size_extensions}'
git_size_objects_verdict='${git_size_objects_verdict}'
git_size_lfs_verdict='${git_size_lfs_verdict}'
git_verdict='${git_size_objects_verdict}&${git_size_lfs_verdict}'
EOF
cat "${file_output_git_lfs_candidates}" >> "${file_output_git_sizes}"

# Enable with: run_git_sizer=true ./git-object-sizes-in-repo-analyzer.sh [repo-path]
if [[ "${run_git_sizer:-true}" == "true" ]]; then
  echo "Running git-sizer in verbose mode... : set run_git_sizer=false to skip"
  git_sizer_repo_dir="${script_dir}/git-sizer"
  git_sizer_bin_dir="${git_sizer_repo_dir}/bin"
  git_sizer_cmd="${git_sizer_bin_dir}/git-sizer"
  git_sizer_repo_top=""
  git_sizer_repo_rel=""

  rm -f "${git_sizer_file_verbose}" "${git_sizer_file_stderr}"

  git_sizer_repo_top=$(git -C "${script_dir}" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "${git_sizer_repo_top}" ]]; then
    git_sizer_repo_rel="${git_sizer_repo_dir#${git_sizer_repo_top}/}"
  fi

  if ! git -C "${git_sizer_repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "git-sizer submodule not found at ${git_sizer_repo_dir}; skipping git-sizer run"
    if [[ -n "${git_sizer_repo_top}" && -n "${git_sizer_repo_rel}" ]]; then
      git -C "${git_sizer_repo_top}" submodule update --init --remote --checkout --recursive -- "${git_sizer_repo_rel}" || echo "Failed to initialize git-sizer submodule; trying fallback clone"
    else
      echo "Unable to resolve git-sizer repository top-level; skipping git-sizer run"
    fi
  fi

  if [[ ! -f "${git_sizer_repo_dir}/go.mod" ]]; then
    echo "git-sizer go.mod not found at ${git_sizer_repo_dir}/go.mod"
    if command -v git >/dev/null 2>&1; then
      echo "Attempting fallback clone of git-sizer repository..."
      rm -rf "${git_sizer_repo_dir}"
      git clone --depth=1 https://github.com/github/git-sizer "${git_sizer_repo_dir}" || echo "Fallback clone failed; skipping git-sizer run"
    fi
  fi

  if [[ ! -f "${git_sizer_repo_dir}/go.mod" ]]; then
    echo "git-sizer still unavailable after fallback; skipping git-sizer run"
    echo "Contents of ${git_sizer_repo_dir}:"
    ls -la "${git_sizer_repo_dir}" 2>/dev/null || true
  elif ! command -v docker >/dev/null 2>&1; then
    echo "docker not found; skipping git-sizer run"
  elif ! docker info >/dev/null 2>&1; then
    echo "docker daemon not reachable; skipping git-sizer run"
  else
    mkdir -p "${git_sizer_bin_dir}"
    docker run --rm \
      -v "${git_sizer_repo_dir}":/src \
      -w /src \
      golang:1.21 \
      sh -c 'go build -buildvcs=false -o bin/git-sizer ./'
  fi

  if [[ -x "${git_sizer_cmd}" ]]; then
    "${git_sizer_cmd}" --verbose > "${git_sizer_file_verbose}" 2> "${git_sizer_file_stderr}" || true
    echo "git-sizer verbose output: ${git_sizer_file_verbose}"
    if [[ -s "${git_sizer_file_stderr}" ]]; then
      echo "git-sizer stderr output: ${git_sizer_file_stderr}"
    else
      rm -f "${git_sizer_file_stderr}"
    fi
  else
    echo "git-sizer binary not available after docker build; skipping git-sizer execution"
  fi
else
  echo "run_git_sizer != true - skip git-sizer"
fi

# Generate HTML tree visualization
echo "Generating HTML tree visualization..."
file_output_html="${WORKSPACE}/git_sizes_tree.html" && rm -f "${file_output_html}"
if command -v python3 &>/dev/null; then
  python3 "${script_dir}/git-object-sizes-tree-render.py" "${file_output_sorted_size_total_final}" "${file_output_html}" "${git_repo_dir}"
  echo "HTML tree visualization: ${file_output_html}"
else
  echo "python3 not found - skipping HTML tree generation"
fi

echo "Investigate if issues occured"
issues_found=false
if [[ -s "${WORKSPACE}/bigtosmall_errors.txt"  ]]; then
  ls -la "${WORKSPACE}/bigtosmall_errors.txt"
  echo "There are errors during analyzing the files: ${WORKSPACE}/bigtosmall_errors.txt"
  /usr/bin/sort -u "${WORKSPACE}/bigtosmall_errors.txt"
  issues_found=true
else
  echo ".. no issues in ${WORKSPACE}/bigtosmall_errors.txt"
fi
if [[ -s "${WORKSPACE}/bigtosmall_errors_revision.txt" ]]; then
  ls -la "${WORKSPACE}/bigtosmall_errors_revision.txt"
  echo "There are errors during analyzing the files: ${WORKSPACE}/bigtosmall_errors_revision.txt"
  /usr/bin/sort -u "${WORKSPACE}/bigtosmall_errors_revision.txt"
  issues_found=true
else
  echo ".. no issues in ${WORKSPACE}/bigtosmall_errors_revision.txt"
fi

echo
if [[ $issues_found == true ]] ; then
  echo "Issues found : leave *.tmp for debugging"
  exit 1
else
  if [[ ${keep_tmp_files:-} == true ]]; then
    echo "Debugging mode : leave *.tmp files"
  else
    echo "Removing *.tmp files"
    rm -rf "${WORKSPACE}"/*.tmp
  fi
fi 

[[ ${verify_pack_exit_code:-0} -ne 0 ]] && {
  echo "WARNING: verify-pack failed with exit code ${verify_pack_exit_code}"
  exit "${verify_pack_exit_code}"
}