#!/bin/bash

set -eu -o pipefail

[[ ${debug:-} == true ]] && set -x

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ ${repack:-} == "" ]] && repack=true
echo "repack=$repack"


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
fi
echo

git_dir="$(git rev-parse --git-dir)"
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

echo "Analyzing git in: $(pwd) "
echo "Saving outfiles in: ${WORKSPACE}"
echo

file_verify_pack="${WORKSPACE}/verify_pack.tmp" && rm -f "${file_verify_pack}"

rm -f ${WORKSPACE}/bigtosmall_*.txt
rm -f ${WORKSPACE}/bigobjects*.txt
rm -f ${WORKSPACE}/allfileshas*.txt

file_tmp_allfileshas="${WORKSPACE}/allfileshas.tmp" && rm -f "${file_tmp_allfileshas}"

file_tmp_bigobjects="${WORKSPACE}/bigobjects.tmp" && rm -f "${file_tmp_bigobjects}"
file_tmp_bigobjects_revisions="${WORKSPACE}/bigobjects_revisions.tmp" && rm -f "${file_tmp_bigobjects_revisions}"

file_tmp_bigtosmall_join="${WORKSPACE}/bigobjects_join.tmp" && rm -f "${file_tmp_bigtosmall_join}"

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
file_output_sorted_size_no_extension="${WORKSPACE}/bigtosmall_sorted_size_no_extension.txt" && rm -rf "${file_output_sorted_size_no_extension}"
file_output_sorted_size_extensions="${WORKSPACE}/bigtosmall_sorted_size_extensions.txt" && rm -rf "${file_output_sorted_size_extensions}"
file_output_git_size_extensions="${WORKSPACE}/git_size_extensions.txt" && rm -rf "${file_output_git_size_extensions}"

file_output_git_sizes="${WORKSPACE}/git_sizes.txt" && rm -rf "${file_output_git_sizes}"

git_sizer_file_verbose="${WORKSPACE}/git_sizer_verbose.txt" && rm -f "${git_sizer_file_verbose}"
git_sizer_file_stderr="${WORKSPACE}/git_sizer_verbose.stderr.txt" && rm -f "${git_sizer_file_stderr}"


printf "Clean old temp packs(if present): \n"
for idx in $(find ${pack_dir} -name '.tmp*.pack' -o -name '.tmp*.idx') ; do
 echo "$idx"
 rm -f $idx
done
printf "Done\n\n"

pack_file=$(find ${pack_dir} -name '*.idx')
[[ ${pack_file} ==  "" ]] && { 
  echo "No pack file available - do a git gc" 
  git gc 
  pack_file=$(find ${pack_dir} -name '*.idx')
  [[ ${pack_file} ==  "" ]] && { 
    echo "No pack file available - do a repack" 
    repack="true"
   }
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
  pack_file=$(find ${pack_dir} -name '*.idx')
  [[ ${pack_file} ==  "" ]] && echo "No pack file available - exit 1" && exit 1
else
  printf "repack == false - skip\n\n"
fi

if [[ ${skip_sizes:-} == "" ]]; then
  echo "Get git repo sizes:" 
  
  git_size_total=$(du -sb "${git_dir}" | cut -f 1)
  git_size_objects=$(du -sb "${git_dir}/objects" | cut -f 1)
  git_size_pack="0"
  [[ -d "${pack_dir}" ]] && git_size_pack=$(du -sb "${pack_dir}" | cut -f 1)

  git_size_lfs="0"
  [[ -d "${git_dir}/lfs" ]] && {
    git_size_lfs=$(du -sb "${git_dir}/lfs" | cut -f 1)
  }
  git lfs ls-files --all > "${WORKSPACE}/git_lfs_files.txt" || {
    echo "No git lfs files or error during git lfs ls-files --all - skip"
    rm -f "${WORKSPACE}/git_lfs_files.txt"
  }

  git_size_modules="0"
  [[ -d "${git_dir}/modules" ]] && git_size_modules=$(du -sb "${git_dir}/modules" | cut -f 1  )
else
  echo "git lfs and modules sizes: skipped"
fi

declare git_size_total_mega git_size_objects_mega git_size_pack_mega git_size_lfs_mega git_size_modules_mega
bytes_to_megabytes "${git_size_total}" git_size_total_mega
bytes_to_megabytes "${git_size_objects}" git_size_objects_mega
bytes_to_megabytes "${git_size_pack}" git_size_pack_mega
bytes_to_megabytes "${git_size_lfs}" git_size_lfs_mega
bytes_to_megabytes "${git_size_modules}" git_size_modules_mega

cat <<EOF > ${file_output_git_sizes}
git_size_total=${git_size_total_mega}
git_size_objects=${git_size_objects_mega}
git_size_pack=${git_size_pack_mega}
git_size_lfs=${git_size_lfs_mega}
git_size_modules=${git_size_modules_mega}
EOF

cat ${file_output_git_sizes}

export pack_file=$(find ${pack_dir} -name '*.idx')
echo "Run verify-pack to list all objects in idx"
git verify-pack -v "${pack_file}" > "${file_verify_pack}" || {
  echo "try to repack and gc --prune"
  (
    git reflog expire --all --expire=now
    git repack -a -d --depth=250 --window=250 # accept to use old deltas - add "-f" option to not reuse old deltas for large repos it fails often
    git gc --prune
  ) || git gc --prune
  export pack_file=$(find ${pack_dir} -name '*.idx')
  git verify-pack -v "${pack_file}" > "${file_verify_pack}"
}
echo "Done"

regex_lstree_list='^([a-f0-9]{40})[[:space:]]+(.*)$'
declare -A default_blobs_map
declare -A branches_blobs_map
if [[ ${invest_remote_branches} == true ]]; then
  echo "Reading blob in default branch: ${default_branch}"
  while read -r lstree_blob_line; do
    if [[ "${lstree_blob_line}" =~ $regex_lstree_list ]] ; then
        default_blob=${BASH_REMATCH[1]}
        default_file=${BASH_REMATCH[2]}
        default_blobs_map["${default_blob}"]="${default_file}"
        [[ ${progress:-} == "true" ]] && printf "."
    else
        echo "ERROR: parsing lstree list: $lstree_blob_line"
        echo "       using regex:         $regex_lstree_list"
        exit 1
    fi
  done < <( git ls-tree -r ${default_branch} | cut -f 3- -d ' ')
  [[ ${progress:-} == "true" ]] && echo
  echo "Reading branches diff blobs.."
  while read -r branch; do
    if [[ $branch == "" ]] ; then
      echo "branch variable is empty - skip"
      continue
    fi
    # shellcheck disable=SC2034
    # shellcheck disable=SC2046
    read -r first second <<< "$(git rev-list --all --children $branch | grep ^$(git log -1 --format=%H $branch))"
    if [[ ${second:-} == "" ]] ; then
      printf "LEAF: %s : ( #commits/files: %s/%s ) : %s\n" \
                                "${branch}" \
                                "$( git log --oneline --format=%H $(git merge-base ${default_branch} ${branch} )..${branch} | wc -l )" \
                                "$( git diff-tree -r $(git merge-base ${default_branch} ${branch} )..${branch} | cut -f 4- -d ' ' | wc -l )" \
                                "$( git log --oneline --format='%h,%cs%d : %s' ${branch} -1 )" \
                              | tee -a "${file_output_branch_leaves}"
    else
      printf "EMBEDDED: %s - skip : %s\n\n" "${branch}" "$( git log --oneline --format='%h,%cs%d : %s' ${branch} -1  )" | tee -a "${file_output_branch_embedded}"
      continue
    fi
    # shellcheck disable=SC2046
    while read -r head_blob_line; do
      branch_blob_line_array=($head_blob_line)
      if [[ ${branch_blob_line_array[0]} != "0000000000000000000000000000000000000000" ]]; then 
          branch_blob=${branch_blob_line_array[0]}
          branch_file=${branch_blob_line_array[2]}
          branches_blobs_map["${branch_blob}"]="${branch_file}"
          [[ ${progress:-} == "true" ]] && printf "."
      fi
    done < <( git diff-tree -r $(git merge-base ${default_branch} ${branch} )..${branch} | cut -f 4- -d ' ')
    printf "\n"
  done < <( git branch ${branch_remote_option} | grep -v '^*' | cut -f 3 -d ' ' | grep -v 'origin/HEAD$')
  printf "\nMake tagged branches lists: "
  grep " (tag: " "${file_output_branch_leaves}" > "${file_output_branch_leaves_tagged}" 2> /dev/null || echo "INFO: No leaf branches with tags"
  grep " (tag: " "${file_output_branch_embedded}" > "${file_output_branch_embedded_tagged}" 2> /dev/null || echo "INFO: No embedded branches with tags"
  printf "Done\n\n"
else
  printf "invest_remote_branches != true (%s) - skip\n" "$invest_remote_branches"
fi

echo

git rev-list --objects --all  > "${file_tmp_allfileshas}"

printf "\n"
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
touch "${WORKSPACE}/bigtosmall_errors.txt"

regex_idx_list='^([a-f0-9]{40}) ([0-9]+) (.*)$'

file_tmp_default_blobs_map="${WORKSPACE}/default_blobs_map.tmp" && rm -f "${file_tmp_default_blobs_map}" && touch "${file_tmp_default_blobs_map}"
for blob in "${!default_blobs_map[@]}"; do
  printf "%s\t%s\n" "$blob" "${default_blobs_map[$blob]}" >> "${file_tmp_default_blobs_map}"
done

file_tmp_branches_blobs_map="${WORKSPACE}/branches_blobs_map.tmp" && rm -f "${file_tmp_branches_blobs_map}" && touch "${file_tmp_branches_blobs_map}"
for blob in "${!branches_blobs_map[@]}"; do
  printf "%s\t%s\n" "$blob" "${branches_blobs_map[$blob]}" >> "${file_tmp_branches_blobs_map}"
done

: > "${file_output_sorted_size_files}"
: > "${file_tmp_bigtosmall_join_total}"
awk -v default_map="${file_tmp_default_blobs_map}" \
    -v branch_map="${file_tmp_branches_blobs_map}" \
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
      } else if (prefix == "B" && total_prefix[path_file] == " ") {
        total_prefix[path_file] = "B"
      }
    }
    END {
      for (i = 1; i <= order_count; i++) {
        path_file = order[i]
        printf "%s %s %s %s ( I )\n", total_size[path_file], total_prefix[path_file], total_count[path_file], path_file >> totals_out
      }
    }' "${file_tmp_bigtosmall_join}"
/usr/bin/sort -u -h -r "${file_tmp_bigtosmall_join_total}" > "${file_output_sorted_size_total}"
printf "\n\n"

touch "${file_output_sorted_size_files_revisions}"
echo "Investigate blobs that are packed in revisions in idx file: ${pack_file}"
if [[ ! $(grep -E "^[a-f0-9]{40}[[:space:]]blob[[:space:]]+[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][a-f0-9]{40}$" "${file_verify_pack}" | awk -F" " '{print $1,$2,$3,$4,$5}' > "${file_tmp_bigobjects_revisions}") ]]; then
  printf "Amount of objects: %s\n" $(wc -l < "${file_tmp_bigobjects_revisions}")
  join <(sort "${file_tmp_bigobjects_revisions}") <(sort "${file_tmp_allfileshas}") | sort -k 3 -n -r | cut -f 1,3,6- -d ' '  > "${WORKSPACE}/bigtosmall_revisions_join.tmp"
  amount_total_unique=$(awk '{ $1=""; $2=""; sub(/^  */, "", $0); if (!seen[$0]++) count++ } END { print count+0 }' "${WORKSPACE}/bigtosmall_revisions_join.tmp")
  printf "Amount of unique <path>/<file>: %s\n" "${amount_total_unique}"
else
  printf "Amount of objects: 0 - skip\n"
fi

echo "Generate file sorted list:"
touch "${WORKSPACE}/bigtosmall_errors_revision.txt"
: > "${file_output_sorted_size_files_revisions}"
: > "${file_tmp_bigtosmall_join_total_revisions}"
awk -v default_map="${file_tmp_default_blobs_map}" \
    -v branch_map="${file_tmp_branches_blobs_map}" \
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
      } else if (prefix == "B" && total_prefix[path_file] == " ") {
        total_prefix[path_file] = "B"
      }
    }
    END {
      for (i = 1; i <= order_count; i++) {
        path_file = order[i]
        printf "%s %s %s %s ( P )\n", total_size[path_file], total_prefix[path_file], total_count[path_file], path_file >> totals_out
      }
    }' "${WORKSPACE}/bigtosmall_revisions_join.tmp"
/usr/bin/sort -u -h -r "${file_tmp_bigtosmall_join_total_revisions}" > "${file_output_sorted_size_total_revisions}"
printf "\n\n"

cat ${file_output_sorted_size_total_revisions} ${file_output_sorted_size_total} | sort -k 1 -h -r > "${file_output_sorted_size_total_final}"
cat ${file_output_sorted_size_files_revisions} ${file_output_sorted_size_files} | sort -k 1 -h -r > "${file_output_sorted_size_files_final}"

# Collect entries whose basename has no extension from the final totals file.
awk '{
  line = $0
  path = $0
  sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", path)
  sub(/ \( [IP] \)$/, "", path)
  n = split(path, parts, "/")
  base = parts[n]
  if (base !~ /\./) print line
}' "${file_output_sorted_size_total_final}" > "${file_output_sorted_size_no_extension}"

# Aggregate total size by file extension from the final totals report.
awk 'BEGIN { OFS=" " }
{
  size = $1
  $1 = ""
  $2 = ""
  $3 = ""
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

awk 'NR > 0 {
  bytes = $1
  count = $2
  ext = $3
  mb = bytes / 1000000
  if (mb == int(mb)) size_m = sprintf("%.0fM", mb)
  else size_m = sprintf("%.1fM", mb)
  printf "%s=%s (%s)\n", ext, size_m, count
}' "${file_output_sorted_size_extensions}" > "${file_output_git_size_extensions}"

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

git_verdict="n/a"
if [[ ${git_size_largest_bytes} -gt $((1024*1024*100)) ]]; then
  git_verdict="Must LFS"
elif [[ ${git_size_largest_bytes} -gt $((1024*1024*10)) ]]; then
  git_verdict="Could LFS"
else
  git_verdict="No issues detected"
fi

cat <<EOF >> ${file_output_git_sizes}
git_size_largest=${git_size_largest}
git_size_extensions=${git_size_extensions}
git_verdict=${git_verdict}
EOF

# Enable with: run_git_sizer=true ./git-object-sizes-in-repo-analyzer.sh [repo-path]
if [[ "${run_git_sizer:-true}" == "true" ]]; then
  echo "Running git-sizer in verbose mode..."
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
  python3 "${script_dir}/git-object-sizes-tree-render.py" "${file_output_sorted_size_total_final}" "${file_output_html}" "$(pwd)"
  echo "HTML tree visualization: ${file_output_html}"
else
  echo "python3 not found - skipping HTML tree generation"
fi

echo "Investigate if issues occured"
issues_found=false
if [[ -s "${WORKSPACE}/bigtosmall_errors.txt"  ]]; then
  ls -la ${WORKSPACE}/bigtosmall_errors.txt
  echo "There are errors during analyzing the files: ${WORKSPACE}/bigtosmall_errors.txt"
  /usr/bin/sort -u "${WORKSPACE}/bigtosmall_errors.txt"
  issues_found=true
else
  echo ".. no issues in ${WORKSPACE}/bigtosmall_errors.txt"
fi
if [[ -s "${WORKSPACE}/bigtosmall_errors_revision.txt" ]]; then
  ls -la ${WORKSPACE}/bigtosmall_errors_revision.txt
  echo "There are errors during analyzing the files: ${WORKSPACE}/bigtosmall_errors_revision.txt"
  /usr/bin/sort -u "${WORKSPACE}/bigtosmall_errors_revision.txt"
  issues_found=true
else
  echo ".. no issues in ${WORKSPACE}/bigtosmall_errors_revision.txt"
fi

echo
if [[ $issues_found == true ]] ; then
  echo "Issues found : leave *.tmp for debugging"
else
  if [[ ${debug:-} == true ]]; then
    echo "Debugging mode : leave *.tmp files"
  else
    echo "Removing *.tmp files"
    rm -rf "${WORKSPACE}"/*.tmp
  fi
fi 

