#!/bin/bash

set -eu -o pipefail

[[ ${debug:-} == true ]] && set -x

[[ ${repack:-} == "" ]] && repack=true
echo "repack=$repack"

[[ ${invest_remote_branches:-} == "" ]] && invest_remote_branches=true
echo "invest_remote_branches=$invest_remote_branches"

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

if [[ $(git rev-parse --is-bare-repository) == true ]]; then
  echo "repo_type=bare  ( bare / normal )"  echo
  pack_dir="./objects"
  git_dir="."
else
  echo "repo_type=normal ( bare / normal )"
  git_dir=".git"
  pack_dir=".git/objects"
fi
echo
export pack_dir

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
echo "Analyzing git in: $(pwd) "
echo "Saving outfiles in: ${WORKSPACE}"
echo

rm -f ${WORKSPACE}/bigtosmall_*.txt
rm -f ${WORKSPACE}/bigobjects*.txt
rm -f ${WORKSPACE}/allfileshas*.txt
rm -f ${WORKSPACE}/branches_embedded.txt
rm -f ${WORKSPACE}/branches_leaves.txt


printf "Clean old temp packs(if present): \n"
find ${pack_dir} -name '.tmp*.pack' -o -name '.tmp*.idx'
find ${pack_dir} -name '.tmp*.pack' -o -name '.tmp*.idx' | xargs --no-run-if-empty rm -f
printf "Done\n\n"

pack_file=$(find ${pack_dir} -name '*.idx')
[[ ${pack_file} ==  "" ]] && { echo "No pack file available - do a repack" && repack="true" ;}

if [[ ${repack} == true ]]; then
  echo "git repo and object sizes before repack:"
  du -sh "${git_dir}"
  [[ -d "${git_dir}/${pack_dir}" ]] && du -sh "${git_dir}/${pack_dir}"
  # reference: https://stackoverflow.com/questions/28720151/git-gc-aggressive-vs-git-repack
  git reflog expire --all --expire=now
  git repack -a -d --depth=250 --window=250 # accept to use old deltas - add "-f" option to not reuse old deltas for large repos it fails often
  git gc --prune
  echo "git repo and object sizes after repack:"
  [[ -d "${git_dir}/${pack_dir}" ]] && du -sh "${git_dir}/${pack_dir}"
  du -sh "${git_dir}"
  pack_file=$(find ${pack_dir} -name '*.idx')
  [[ ${pack_file} ==  "" ]] && echo "No pack file available - exit 1" && exit 1
else
  printf "repack == false - skip\n\n"

  echo "git repo and object sizes:"
  du -sh "${git_dir}"
  [[ -d "${git_dir}/${pack_dir}" ]] && du -sh "${git_dir}/${pack_dir}"
  echo
fi
export pack_file
echo "Run verify-pack to list all objects in idx"
git verify-pack -v "${pack_file}" > "${WORKSPACE}/verify_pack.txt"
echo "Done"

[[ -d "${git_dir}/lfs" ]]     && du -sh "${git_dir}/lfs"     || echo "${git_dir}/lfs is not present"
[[ -d "${git_dir}/modules" ]] && du -sh "${git_dir}/modules" || echo "${git_dir}/modules is not present"

declare -A head_blobs_map
if [[ ${invest_remote_branches} == true ]]; then
  echo "Reading branch  blobs.."
  if [[ $(git branch -r) != "" ]] ;then
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
                                  "$( git log --oneline --format=%H $(git merge-base origin/HEAD ${branch} )..${branch} | wc -l )" \
                                  "$( git diff-tree -r $(git merge-base origin/HEAD ${branch} )..${branch} | cut -f 4- -d ' ' | wc -l )" \
                                  "$( git log --oneline --decorate -1 ${branch} )" \
                                | tee -a ${WORKSPACE}/branches_leaves.txt
      else
        printf "EMBEDDED: %s - skip : %s\n\n" "${branch}" "$( git log --oneline --decorate -1 ${branch} )" | tee -a "${WORKSPACE}/branches_embedded.txt"
        continue
      fi
      # shellcheck disable=SC2046
      while read -r head_blob_line; do
        head_blob_line_array=($head_blob_line)
        head_blob=${head_blob_line_array[0]}
        head_file=${head_blob_line_array[1]}
        head_file=${head_blob_line_array[2]}
        head_blobs_map["${head_blob}"]="${head_file}"
        [[ ${progress:-} == "true" ]] && printf "."
      done < <( git diff-tree -r $(git merge-base origin/HEAD ${branch} )..${branch} | cut -f 4- -d ' ')
      printf "\n"
    done < <( git branch -r | cut -f 3 -d ' '  | grep -v ".*/HEAD$")
    printf "\nMake tagged branches lists: "
    grep " (tag: " "${WORKSPACE}/branches_leaves.txt" > "${WORKSPACE}/branches_leaves_tagged.txt" &>2 / dev/null || echo "INFO: No leaf branches with tags"
    grep " (tag: " "${WORKSPACE}/branches_embedded.txt" > "${WORKSPACE}/branches_embedded_tagged.txt" &>2 / dev/null || echo "INFO: No embbedded branches with tags"
    printf "Done\n\n"
  else
    printf "No remote branches found - skip\n"
  fi
else
  printf "invest_remote_branches != true (%s) - skip\n" "$invest_remote_branches"
fi

echo

git rev-list --objects --all  > "${WORKSPACE}/allfileshas.txt"
cat "${WORKSPACE}/allfileshas.txt" | cut -d ' ' -f 2- | uniq > "${WORKSPACE}/allfileshas_uniq.txt"

printf "\n"
touch "${WORKSPACE}/bigtosmall_sorted_size_files.txt"
echo "Investigate blobs that are directly stored in idx file: ${pack_file}"
if [[ ! $(grep -E "^[a-f0-9]{40}[[:space:]]blob[[:space:]]+[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+$" "${WORKSPACE}/verify_pack.txt" | awk -F" " '{print $1,$2,$3,$4,$5}' > "${WORKSPACE}/bigobjects.txt") ]]; then
  printf "Amount of objects: %s\n" "$(wc -l < "${WORKSPACE}/bigobjects.txt")"
  join <(sort "${WORKSPACE}/bigobjects.txt") <(sort "${WORKSPACE}/allfileshas.txt") | sort -k 3 -n -r | cut -f 1,3,6-  -d ' ' > "${WORKSPACE}/bigtosmall_join.txt"

  touch "${WORKSPACE}/bigtosmall_join_uniq.txt"
  cat "${WORKSPACE}/bigtosmall_join.txt" |  cut -d ' ' -f 3- > "${WORKSPACE}/bigtosmall_join_all.txt"
  cat -n "${WORKSPACE}/bigtosmall_join_all.txt" | /usr/bin/sort -uk2 | /usr/bin/sort -n | cut -f2- > "${WORKSPACE}/bigtosmall_join_uniq.txt"
  amount_total_unique=$(wc -l < "${WORKSPACE}/bigtosmall_join_uniq.txt")
  printf "Amount of unique <path>/<file>: %s\n" "${amount_total_unique}"
else
  printf "Amount of unique <path>/<file>: 0 - skip\n"
fi

echo "Generate file sorted list:"
touch "${WORKSPACE}/bigtosmall_errors.txt"

progress_bar_init
while read -r file; do
  progress_bar_update
  while read -r blob size path_file; do
    [[ "$file" != "$path_file" ]] && (echo "File: ${file} and path_file: ${path_file} are different!!! - something is wrong" && exit 10 )
    prefix=" "
    if [[ "${head_blobs_map[${blob}]:-}" == "$path_file" ]]; then
      prefix="R"
    fi
    echo "$prefix $blob $size $path_file" >> "${WORKSPACE}/bigtosmall_sorted_size_files.txt"
  done < <( file="${file//'.'/\\.}" && \
            file=${file//'*'/\\*} && \
            file=${file//'+'/\\+} && \
            file=${file//'?'/\\?} && \
            file=${file//'('/\\(} && \
            file=${file//')'/\\)} && \
            grep -E " ${file}$" "${WORKSPACE}/bigtosmall_join.txt" || echo "ERROR: $file: something went wrong" >> "${WORKSPACE}/bigtosmall_errors.txt")

done < "${WORKSPACE}/bigtosmall_join_uniq.txt"
printf "\n\n"

touch "${WORKSPACE}/bigtosmall_sorted_size_files_revisions.txt"
echo "Investigate blobs that are packed in revisions in idx file: ${pack_file}"
if [[ ! $(grep -E "^[a-f0-9]{40}[[:space:]]blob[[:space:]]+[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][a-f0-9]{40}$" "${WORKSPACE}/verify_pack.txt" | awk -F" " '{print $1,$2,$3,$4,$5}' > "${WORKSPACE}/bigobjects_revisions.txt") ]]; then
  printf "Amount of objects: %s\n" $(wc -l < "${WORKSPACE}/bigobjects_revisions.txt")
  join <(sort "${WORKSPACE}/bigobjects_revisions.txt") <(sort "${WORKSPACE}/allfileshas.txt") | sort -k 3 -n -r | cut -f 1,3,6- -d ' '  > "${WORKSPACE}/bigtosmall_revisions_join.txt"
  touch "${WORKSPACE}/bigtosmall_revisions_join_uniq.txt"
  cat "${WORKSPACE}/bigtosmall_revisions_join.txt" |  cut -d ' ' -f 3- > "${WORKSPACE}/bigtosmall_revisions_join_all.txt"
  cat -n "${WORKSPACE}/bigtosmall_revisions_join_all.txt" | /usr/bin/sort -uk2 | /usr/bin/sort -n | cut -f2- > "${WORKSPACE}/bigtosmall_revisions_join_uniq.txt"
  amount_total_unique=$(wc -l < "${WORKSPACE}/bigtosmall_revisions_join_uniq.txt")
  printf "Amount of unique <path>/<file>: %s\n" "${amount_total_unique}"
else
  printf "Amount of objects: 0 - skip\n"
fi

echo "Generate file sorted list:"
touch "${WORKSPACE}/bigtosmall_errors_revision.txt"
progress_bar_init
while read -r file; do
  progress_bar_update
  while read -r blob size path_file; do
    [[ $file != "$path_file" ]] && (echo "File: ${file} and path_file: ${path_file} are different!!! - something is wrong" && exit 11 )
    prefix=" "
    if [[ "${head_blobs_map[${blob}]:-}" == "$file" ]]; then
      prefix="R"
    fi
    echo "$prefix $blob $size $path_file" >> "${WORKSPACE}/bigtosmall_sorted_size_files_revisions.txt"
  done < <(file="${file//'.'/\\.}" && file=${file//'*'/\\*} && file=${file//'+'/\\+} && file=${file//'?'/\\?}  && file=${file//'('/\\(} && file=${file//')'/\\)} && grep -E " ${file}$" "${WORKSPACE}/bigtosmall_revisions_join.txt"  || echo "ERROR: $file: something went wrong" >> "${WORKSPACE}/bigtosmall_errors_revision.txt")
done < "${WORKSPACE}/bigtosmall_revisions_join_uniq.txt"
printf "\n\n"

echo "Investigate if issues occured"
if [[ ! -s "${WORKSPACE}/bigtosmall_errors.txt"  ]]; then
  echo "There are errors during analyzing the files: ${WORKSPACE}/bigtosmall_errors.txt"
  /usr/bin/sort -u "${WORKSPACE}/bigtosmall_errors.txt"
else
  echo ".. no issues in ${WORKSPACE}/bigtosmall_errors.txt"
fi
if [[ ! -s "${WORKSPACE}/bigtosmall_errors_revision.txt" ]]; then
  echo "There are errors during analyzing the files: ${WORKSPACE}/bigtosmall_errors_revision.txt"
  /usr/bin/sort -u "${WORKSPACE}/bigtosmall_errors_revision.txt"
else
  echo ".. no issues in ${WORKSPACE}/bigtosmall_errors_revision.txt"
fi
