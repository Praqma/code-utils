set -x
set -e

root_folder=`pwd`

export PATH=/cygdrive/c/Program\ Files\ \(x86\)/Git/bin:${PATH}
export PATH=/cygdrive/c/Cygwin/bin:${PATH}

git config --global core.autocrlf false
git config --global user.name "my name"
git config --global user.email "my@email"

for dir in `find . -maxdepth 1 -mindepth 1 -type d` ; do
	echo $dir 
	cd $dir
	csv_file="${root_folder}/git_size_$(basename ${dir}).csv"
	size_after_commit=`du -sm .git | awk -F" " '{ print $1 }' `
	
	if [ -e ${csv_file} ] ; then
	  size_before_commit=`cat ${csv_file}  | tail -1 | awk -F "," '{print $1}'`
	else
	  size_before_commit="${size_after_commit}"
	fi 
	
	size_delta=`echo "${size_after_commit} - ${size_before_commit}" | bc -l`
	
	if [ ! -e ${csv_file} ] ; then
	  echo "SizeInMb,Delta" > ${csv_file} 
	fi
	echo "${size_after_commit},${size_delta}" >> ${csv_file} 
	
	git status

	git log -2
	
	du -sk .git

	du -sh .git 
	
	echo "Leaving: $dir"
	cd ..
	
done
cd $root_folder
