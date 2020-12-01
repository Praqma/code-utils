#!/bin/bash

set -eu -o pipefail

[[ ${debug:-} == true ]] && set -x

[[ ${repack:-} == "" ]] && repack=true

export PATH=/cygdrive/c/Program\ Files\ \(x86\)/Git/bin:${PATH}
export PATH=/cygdrive/c/Cygwin/bin:${PATH}

export PATH=/c/Program\ Files\ \(x86\)/Git/bin:${PATH}

export PATH=/c/Program\ Files/Git/usr/bin/:${PATH}
export PATH=/c/Program\ Files/Git/bin/:${PATH}
export PATH=/c/Program\ Files/Git/mingw64/bin/:${PATH}

export PATH=/c/Cygwin/bin:${PATH}
export PATH=/usr/bin:${PATH}

if [[ ${debug:-} == true ]]; then
  command -v find
  command -v sort

  printf "PATH:\n%s\n" "${PATH}"
fi
if [[ "${WORKSPACE:-}" == "" ]]; then
  export WORKSPACE=$(pwd)
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

if [ -d .git ]; then
  export pack_dir=".git/objects"
else
  gitdir=$(cat .git | awk -F ": " '{print $2}')
  cd $gitdir
  export pack_dir="./objects"
fi

if [[ ${repack} == "true" ]]; then
  echo "git repo and object sizes before repack:"
  du -sh .git
  [[ -d .git/objects ]] && du -sh .git/objects
  # reference: https://stackoverflow.com/questions/28720151/git-gc-aggressive-vs-git-repack
  git reflog expire --all --expire=now
  git repack -a -d --depth=250 --window=250 # accept to use old deltas - add "-f" option to not reuse old deltas for large repos it fails often
  git gc --prune
  echo "git repo and object sizes after repack:"
  [[ -d .git/objects ]] && du -sh .git/objects
  du -sh .git
else
  echo "git repo and object sizes:"
  du -sh .git
  [[ -d .git/objects ]] && du -sh .git/objects
fi

if [[ -d .git/lfs ]]; then
  du -sh .git/lfs
else
  echo ".git/lfs is not present"
fi
if [[ -d .git/modules ]]; then
  du -sh .git/modules
else
  echo ".git/modules is not present"
fi

echo "Reading branch  blobs.."
declare -A head_blobs_map
if [[ $(git branch -r) != "" ]] ;then
  while read -r branch; do
    if [[ $branch == "" ]] ; then
      echo "branch variable is empty - skip"
      continue
    fi
    read -r first second <<< $(git rev-list --all --children $branch | grep ^$(git log -1 --format=%H $branch))
    if [[ ${second:-} == "" ]] ; then
      printf "LEAF: %s : %s\n" "${branch}" "$( git log --oneline --decorate -1 ${branch} )" | tee -a ${WORKSPACE}/branches_leaves.txt
    else
      printf "EMBEDDED: %s - skip : %s\n" "${branch}" "$( git log --oneline --decorate -1 ${branch} )" | tee -a ${WORKSPACE}/branches_embedded.txt
      continue
    fi
    while read -r head_blob_line; do
      head_blob_line_array=($head_blob_line)
      head_blob=${head_blob_line_array[0]}
      head_file=${head_blob_line_array[1]}
      head_blobs_map["${head_blob}"]="${head_file}"
      printf "."
    done < <( git ls-tree -r $branch | cut -f 3 -d ' ')
    printf "\n"
  done < <( git branch -r | cut -f 3 -d ' '  | grep -v .*/HEAD$)
fi
echo

git rev-list --objects --all  > "${WORKSPACE}/allfileshas.txt"
cat "${WORKSPACE}/allfileshas.txt" | cut -d ' ' -f 2- | uniq > ${WORKSPACE}/allfileshas_uniq.txt

export pack_file=$(find ${pack_dir} -name '*.idx')
echo
echo "Run verify-pack to list all objects in idx"
git verify-pack -v ${pack_file} > "${WORKSPACE}/verify_pack.txt"
echo "Done"

printf "\n"
touch "${WORKSPACE}/bigtosmall_sorted_size_files.txt"
echo "Investigate blobs that are directly stored in idx file: ${pack_file}"
if [[ ! $(grep -E "^[a-f0-9]{40}[[:space:]]blob[[:space:]]+[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+$" "${WORKSPACE}/verify_pack.txt" | awk -F" " '{print $1,$2,$3,$4,$5}' > "${WORKSPACE}/bigobjects.txt") ]]; then
  printf "Amount of objects: %s\n" $(wc -l < "${WORKSPACE}/bigobjects.txt")
  join <(sort "${WORKSPACE}/bigobjects.txt") <(sort "${WORKSPACE}/allfileshas.txt") | sort -k 3 -n -r | cut -f 1,3,6-  -d ' ' > "${WORKSPACE}/bigtosmall_join.txt"

  touch "${WORKSPACE}/bigtosmall_join_uniq.txt"
  cat "${WORKSPACE}/bigtosmall_join.txt" |  cut -d ' ' -f 3- > ${WORKSPACE}/bigtosmall_join_all.txt
  cat -n ${WORKSPACE}/bigtosmall_join_all.txt | /usr/bin/sort -uk2 | /usr/bin/sort -n | cut -f2- > "${WORKSPACE}/bigtosmall_join_uniq.txt"
  printf "Amount of unique <path>/<file>: %s\n" $(wc -l < "${WORKSPACE}/bigtosmall_join_uniq.txt")
else
  printf "Amount of unique <path>/<file>: 0 - skip\n"
fi

echo "Generate file sorted list:"
touch "${WORKSPACE}/bigtosmall_errors.txt"
while read -r file; do
  printf "."
  while read -r blob size path_file; do
    [[ "$file" != "$path_file" ]] && (echo "File: ${file} and path_file: ${path_file} are different!!! - something is wrong" && exit 10 )
    prefix=" "
    if [[ "${head_blobs_map[${blob}]:-}" == "$path_file" ]]; then
      prefix="R"
    fi
    echo "$prefix $blob $size $path_file" >> "${WORKSPACE}/bigtosmall_sorted_size_files.txt"
  done < <(file="${file//'.'/\\.}" && file=${file//'*'/\\*} && file=${file//'+'/\\+} && file=${file//'?'/\\?} && file=${file//'('/\\(} && file=${file//')'/\\)} && grep -E " ${file}$" "${WORKSPACE}/bigtosmall_join.txt" || echo "ERROR: $file: something went wrong" >> "${WORKSPACE}/bigtosmall_errors.txt")

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
  printf "Amount of unique <path>/<file>: %s\n" $(wc -l < "${WORKSPACE}/bigtosmall_revisions_join_uniq.txt")
else
  printf "Amount of objects: 0 - skip\n"
fi

echo "Generate file sorted list:"
touch "${WORKSPACE}/bigtosmall_errors_revision.txt"
while read -r file; do
  printf "."
  while read -r blob size path_file; do
    [[ $file != $path_file ]] && (echo "File: ${file} and path_file: ${path_file} are different!!! - something is wrong" && exit 11 )
    prefix=" "
    if [[ "${head_blobs_map[${blob}]:-}" == "$file" ]]; then
      prefix="H"
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
