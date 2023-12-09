#!/bin/bash

set -eu -o pipefail

[[ ${debug:-} == true ]] && set -x

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

if [[ $(git rev-parse --is-bare-repository) == true ]]; then
  echo "repo_type=bare  ( bare / normal )"
  pack_dir="./objects"
  git_dir="."
  branch_remote_option=""
  default_branch=$(git branch  | grep '^* ' | cut -f 2 -d ' ') || default_branch=""
else
  echo "repo_type=normal ( bare / normal )"
  git_dir=".git"
  pack_dir=".git/objects"
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
file_tmp_bigtosmall_join_revisions="${WORKSPACE}/bigobjects_join_revisions.tmp" && rm -f "${file_tmp_bigtosmall_join_revisions}"

file_tmp_bigtosmall_join_uniq="${WORKSPACE}/bigtosmall_join_uniq.tmp" && rm -rf "${file_tmp_bigtosmall_join_uniq}"

file_tmp_bigtosmall_join_total="${WORKSPACE}/bigobjects_join_total.tmp" && rm -f "${file_tmp_bigtosmall_join_total}" && touch "${file_tmp_bigtosmall_join_total}"
file_tmp_bigtosmall_join_total_revisions="${WORKSPACE}/bigobjects_join_total_revisions.tmp" && rm -f "${file_tmp_bigtosmall_join_total_revisions}" && touch "${file_tmp_bigtosmall_join_total_revisions}"

file_output_sorted_size_files="${WORKSPACE}/bigtosmall_sorted_size_files.txt" && rm -f "${file_output_sorted_size_files}"
file_output_sorted_size_files_revisions="${WORKSPACE}/bigtosmall_sorted_size_files_revisions.txt" && rm -f "${file_output_sorted_size_files_revisions}"
file_output_branch_embedded="${WORKSPACE}/branches_embedded.txt" && rm -f "${file_output_branch_embedded}"
file_output_branch_leaves="${WORKSPACE}/branches_leaves.txt" && rm -f "${file_output_branch_leaves}"
file_output_branch_embedded_tagged="${WORKSPACE}/branches_embedded_tagged.txt" && rm -f "${file_output_branch_embedded_tagged}"
file_output_branch_leaves_tagged="${WORKSPACE}/branches_leaves_tagged.txt" && rm -f "${file_output_branch_leaves_tagged}"

file_output_sorted_size_total="${WORKSPACE}/bigtosmall_sorted_size_total.txt" && rm -rf "${file_output_sorted_size_total}"
file_output_sorted_size_total_revisions="${WORKSPACE}/bigtosmall_sorted_size_total_revisions.txt" && rm -rf "${file_output_sorted_size_total_revisions}"

file_output_git_sizes="${WORKSPACE}/git_sizes.txt" && rm -rf "${file_output_git_sizes}"

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
  
  git_size_total=$(du -sh "${git_dir}" | cut -f 1)
  git_size_objects=$(du -sh "${git_dir}/objects" | cut -f 1)
  git_size_pack=""
  [[ -d "${pack_dir}" ]] && git_size_pack=$(du -sh "${pack_dir}" | cut -f 1)

  git_size_lfs=""
  [[ -d "${git_dir}/lfs" ]] && git_size_lfs=$(du -sh "${git_dir}/lfs" | cut -f 1)

  git_size_modules=""
  [[ -d "${git_dir}/modules" ]] && git_size_modules=$(du -sh "${git_dir}/modules" | cut -f 1  )
else
  echo "git lfs and modules sizes: skipped"
fi

cat <<EOF > ${file_output_git_sizes}
git_size_total=${git_size_total}
git_size_objects=${git_size_objects}
git_size_pack=${git_size_pack}
git_size_lfs=${git_size_lfs}
git_size_modules=${git_size_modules}
EOF

cat ${file_output_git_sizes}

export pack_file
echo "Run verify-pack to list all objects in idx"
git verify-pack -v "${pack_file}" > "${file_verify_pack}" || {
  git reflog expire --all --expire=now
  git repack -a -d --depth=250 --window=250 # accept to use old deltas - add "-f" option to not reuse old deltas for large repos it fails often
  git gc --prune
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

  touch "${file_tmp_bigtosmall_join_uniq}"
  cat "${file_tmp_bigtosmall_join}" |  cut -d ' ' -f 3- > "${WORKSPACE}/bigtosmall_join_all.tmp"
  cat -n "${WORKSPACE}/bigtosmall_join_all.tmp" | /usr/bin/sort -uk2 | /usr/bin/sort -n | cut -f2- > "${file_tmp_bigtosmall_join_uniq}"
  amount_total_unique=$(wc -l < "${file_tmp_bigtosmall_join_uniq}")
  printf "Amount of unique <path>/<file>: %s\n" "${amount_total_unique}"
else
  printf "Amount of unique <path>/<file>: 0 - skip\n"
fi

echo "Generate file sorted list:"
touch "${WORKSPACE}/bigtosmall_errors.txt"

regex_idx_list='^([a-f0-9]{40}) ([0-9]+) (.*)$'

progress_bar_init
while read -r file; do
  progress_bar_update
  prefix_total=" "
  size_total=0
  count=0
  while IFS=$'\n' read -r line; do
    prefix=" "
    if [[ "${line}" =~ $regex_idx_list ]] ; then
      blob=${BASH_REMATCH[1]}
      size=${BASH_REMATCH[2]}
      size_total=$(( $size_total + $size ))
      path_file=${BASH_REMATCH[3]}
      count=$(( $count + 1 ))
    else
      echo "ERROR: Cannot parse ${file_tmp_bigtosmall_join}"
      exit 1
    fi
    [[ "${file}" != "${path_file}" ]] && (echo "File: ${file} and path_file: ${path_file} are different!!! - something is wrong" && exit 10 )
    if [[ "${default_blobs_map[${blob}]:-}" == "$path_file" ]]; then
        prefix="H"
        prefix_total="H"
    else
        if [[ "${branches_blobs_map[${blob}]:-}" == "$path_file" ]]; then
          [[ ${prefix:-} == " " ]] && prefix="B"
          [[ ${prefix_total:-} == " " ]] && prefix_total="B"
        fi
    fi
    echo "$prefix $blob $size $path_file" >> "${file_output_sorted_size_files}"
  done < <( file="${file//'.'/\\.}" && \
            file="${file//'*'/\\*}" && \
            file="${file//'+'/\\+}" && \
            file="${file//'?'/\\?}" && \
            file="${file//'('/\\(}" && \
            file="${file//')'/\\)}" && \
            file="${file//'['/\\[}" && \
            file="${file//']'/\\]}" && \
            file="${file//$/\\$}"  && \
            grep -E "^[a-f0-9]{40}[[:space:]][0-9]+[[:space:]]${file}$" "${file_tmp_bigtosmall_join}" || echo "ERROR: $file: something went wrong" >> "${WORKSPACE}/bigtosmall_errors.txt")
  printf "%s %s %s %s\n" "$size_total" "${prefix_total}" "$count" "$path_file">> "${file_tmp_bigtosmall_join_total}"
done < "${file_tmp_bigtosmall_join_uniq}"
/usr/bin/sort -u -h -r "${file_tmp_bigtosmall_join_total}" > "${file_output_sorted_size_total}"
printf "\n\n"

touch "${file_output_sorted_size_files_revisions}"
echo "Investigate blobs that are packed in revisions in idx file: ${pack_file}"
if [[ ! $(grep -E "^[a-f0-9]{40}[[:space:]]blob[[:space:]]+[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][a-f0-9]{40}$" "${file_verify_pack}" | awk -F" " '{print $1,$2,$3,$4,$5}' > "${file_tmp_bigobjects_revisions}") ]]; then
  printf "Amount of objects: %s\n" $(wc -l < "${file_tmp_bigobjects_revisions}")
  join <(sort "${file_tmp_bigobjects_revisions}") <(sort "${file_tmp_allfileshas}") | sort -k 3 -n -r | cut -f 1,3,6- -d ' '  > "${WORKSPACE}/bigtosmall_revisions_join.tmp"
  touch "${WORKSPACE}/bigtosmall_revisions_join_uniq.tmp"
  cat "${WORKSPACE}/bigtosmall_revisions_join.tmp" |  cut -d ' ' -f 3- > "${WORKSPACE}/bigtosmall_revisions_join_all.tmp"
  cat -n "${WORKSPACE}/bigtosmall_revisions_join_all.tmp" | /usr/bin/sort -uk2 | /usr/bin/sort -n | cut -f2- > "${WORKSPACE}/bigtosmall_revisions_join_uniq.tmp"
  amount_total_unique=$(wc -l < "${WORKSPACE}/bigtosmall_revisions_join_uniq.tmp")
  printf "Amount of unique <path>/<file>: %s\n" "${amount_total_unique}"
else
  printf "Amount of objects: 0 - skip\n"
fi

echo "Generate file sorted list:"
touch "${WORKSPACE}/bigtosmall_errors_revision.txt"
progress_bar_init
while read -r file; do
  progress_bar_update
  prefix_total=" "
  size_total=0
  count=0
  while IFS=$'\n' read -r line; do
    prefix=" "
    if [[ "${line}" =~ $regex_idx_list ]] ; then
      blob=${BASH_REMATCH[1]}
      size=${BASH_REMATCH[2]}
      size_total=$(( $size_total + $size ))
      path_file=${BASH_REMATCH[3]}
      count=$(( $count + 1 ))
    else
      echo "ERROR: reading : $line"
      echo "       regex :   $regex_idx_list"
      exit 1
    fi
    [[ $file != "$path_file" ]] && (echo "File: ${file} and path_file: ${path_file} are different!!! - something is wrong" && exit 11 )
    if [[ "${default_blobs_map[${blob}]:-}" == "$path_file" ]]; then
        prefix="H"
        prefix_total="H"
    else
        if [[ "${branches_blobs_map[${blob}]:-}" == "$path_file" ]]; then
          [[ ${prefix:-} == " " ]] && prefix="B"
          [[ ${prefix_total:-} == " " ]] && prefix_total="B"
        fi
    fi
    echo "$prefix $blob $size $path_file" >> "${file_output_sorted_size_files_revisions}"
  done < <( file="${file//'.'/\\.}" && \
            file="${file//'*'/\\*}" && \
            file="${file//'+'/\\+}" && \
            file="${file//'?'/\\?}" && \
            file="${file//'('/\\(}" && \
            file="${file//')'/\\)}" && \
            file="${file//'['/\\[}" && \
            file="${file//']'/\\]}" && \
            file="${file//$/\\$}"  && \
            grep -E "^[a-f0-9]{40}[[:space:]][0-9]+[[:space:]]${file}$" "${WORKSPACE}/bigtosmall_revisions_join.tmp"  || echo "ERROR: $file: something went wrong" >> "${WORKSPACE}/bigtosmall_errors_revision.txt")
  printf "%s %s %s %s\n" "$size_total" "${prefix_total}" "$count" "$path_file">> "${file_tmp_bigtosmall_join_total_revisions}"
done < "${WORKSPACE}/bigtosmall_revisions_join_uniq.tmp"
/usr/bin/sort -u -h -r "${file_tmp_bigtosmall_join_total_revisions}" > "${file_output_sorted_size_total_revisions}"
printf "\n\n"

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
    rm -rf *.tmp
  fi
fi 

