#!/bin/bash -e -x

set -x
set -e

set +x
export PATH=/cygdrive/c/Program\ Files\ \(x86\)/Git/bin:${PATH}
export PATH=/cygdrive/c/Cygwin/bin:${PATH}

export PATH=/c/Program\ Files\ \(x86\)/Git/bin:${PATH}

export PATH=/c/Program\ Files/Git/usr/bin/:${PATH}
export PATH=/c/Program\ Files/Git/bin/:${PATH}
export PATH=/c/Program\ Files/Git/mingw64/bin/:${PATH}

export PATH=/c/Cygwin/bin:${PATH}
export PATH=/usr/bin:${PATH}


which find
which sort

echo $PATH
if [ "${WORKSPACE}X" == "X" ]; then
  export WORKSPACE=`pwd`
fi
if [ "${1}x" != "x" ]; then
  test -e ${1} && cd ${1}
fi
echo
echo "Analyzing git in: `pwd` "
echo "Saving outfiles in: ${WORKSPACE}"
echo

set -x
set -u

rm -f ${WORKSPACE}/bigtosmall_*.txt
rm -f ${WORKSPACE}/bigobjects*.txt
rm -f ${WORKSPACE}/allfileshas*.txt

if [ -d .git ]; then
  export pack_dir=".git/objects"
else
  gitdir=`cat .git | awk -F ": " '{print $2}'`
  cd $gitdir
  export pack_dir="./objects"
fi

du -sh .git
git reflog expire --all --expire=now
git gc --prune=now --aggressive
du -sh .git

git rev-list --objects --all | sort -k 2 | sed -e 's/ /@/g' -e 's/@/ /' -e 's/(//g' -e 's/)//g'  > ${WORKSPACE}/allfileshas.txt
cat ${WORKSPACE}/allfileshas.txt| cut -f 2 -d\  | uniq > ${WORKSPACE}/allfileshas_uniq.txt

export pack_file=$(find ${pack_dir} -name '*.idx')
git verify-pack -v ${pack_file} | egrep "^\w+ blob\W+[0-9]+ [0-9]+ [0-9]+$" | awk -F" " '{print $1,$2,$3,$4,$5}' > ${WORKSPACE}/bigobjects.txt
git verify-pack -v ${pack_file} | egrep "^\w+ blob\W+[0-9]+ [0-9]+ [0-9]+ [0-9]+" | awk -F" " '{print $1,$2,$3,$4,$5}' > ${WORKSPACE}/bigobjects_revisions.txt

#cat ${WORKSPACE}/bigobjects.txt | sort -k 3 -n -r > ${WORKSPACE}/bigobjects_sorted.txt


join <(sort ${WORKSPACE}/bigobjects.txt) <(sort ${WORKSPACE}/allfileshas.txt) | sort -k 3 -n -r | cut -f 1,3,6- -d \ > ${WORKSPACE}/bigtosmall_join.txt

join <(sort ${WORKSPACE}/bigobjects_revisions.txt) <(sort ${WORKSPACE}/allfileshas.txt) | sort -k 3 -n -r | cut -f 1,3,6- -d \ > ${WORKSPACE}/bigtosmall_revisions_join.txt

touch ${WORKSPACE}/bigtosmall_join_uniq.txt
set +x
for file in `cat ${WORKSPACE}/bigtosmall_join.txt | awk -F " " '{print $3}'` ; do
  grep -e "^${file}$" ${WORKSPACE}/bigtosmall_join_uniq.txt || echo $file >> ${WORKSPACE}/bigtosmall_join_uniq.txt
done
set -x 

touch ${WORKSPACE}/bigtosmall_errors.txt
set +x
for file in `cat ${WORKSPACE}/bigtosmall_join_uniq.txt` ; do
	grep -e " ${file}$" ${WORKSPACE}/bigtosmall_join.txt >> ${WORKSPACE}/bigtosmall_sorted_size_files.txt || echo "ERROR: $file: something went wrong" >> ${WORKSPACE}/bigtosmall_errors.txt
done
set -x

touch ${WORKSPACE}/bigtosmall_revisions_join_uniq.txt
set +x
for file in `cat ${WORKSPACE}/bigtosmall_revisions_join.txt | awk -F " " '{print $3}'` ; do
  grep -e "^${file}$" ${WORKSPACE}/bigtosmall_revisions_join_uniq.txt || echo $file >> ${WORKSPACE}/bigtosmall_revisions_join_uniq.txt
done
set -x

touch ${WORKSPACE}/bigtosmall_errors_revision.txt
set +x
for file in `cat ${WORKSPACE}/bigtosmall_revisions_join_uniq.txt ` ; do
  grep -e " ${file}$" ${WORKSPACE}/bigtosmall_revisions_join.txt >> ${WORKSPACE}/bigtosmall_sorted_size_files_revisions.txt || echo "ERROR: $file: something went wrong" >> ${WORKSPACE}/bigtosmall_errors_revision.txt
done
set -x
