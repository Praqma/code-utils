set -x
set -e

root_folder=`pwd`
git_folder=$1
cd $git_folder

if [ "${BUILD_URL}X" == "X" ] ; then
	export BUILD_URL="Test-run"
fi

export PATH=/cygdrive/c/Program\ Files\ \(x86\)/Git/bin:${PATH}
export PATH=/cygdrive/c/Cygwin/bin:${PATH}

#git config --global core.autocrlf false
#git config --global user.name "Claus Schneider (Praqma)"
#git config --global user.email "claus.schneider-ext@praqma.net"

for dir in `find . -maxdepth 1 -mindepth 1 -type d` ; do
	echo $dir 
	cd $dir
	
	if [ "${WIPE_GIT_FOLDER}X" == "trueX" ] ; then
		rm -rf .git*
	fi 
	
	if [ -e .git ] ; then
		size_before_commit=`du -sm .git | awk -F" " '{ print $1 }' `
		git add -A 
		git status
		git commit --allow-empty -m "${BUILD_URL} "
	else
		git init
    touch .gitignore
#		echo "*.updt" > .gitignore
#		echo "view.dat" >> .gitignore
#		echo "*.csv" >> .gitignore
		git add .gitignore
		git commit -m "init: ${BUILD_URL}"
		git add -A 
		git status
		git commit --amend --no-edit
		size_before_commit=`du -sm .git | awk -F" " '{ print $1 }' `
	fi
	size_after_commit=`du -sm .git | awk -F" " '{ print $1 }' `
	size_delta=`echo "${size_after_commit} - ${size_before_commit}" | bc -l`
	git commit --allow-empty --amend --no-edit -m "${BUILD_URL}: git size in Mb: ${size_after_commit} - ${size_before_commit} = ${size_delta}"
	
	if [ ! -e git_size.csv ] ; then
	  echo "SizeInMb,Delta" > git_size.csv
	fi
	echo "${size_after_commit},${size_delta}" >> git_size.csv
	
	git status

	git log -2
	
	du -sk .git

	du -sh .git 
	
	echo "Leaving: $dir"
	cd ..
	
done
cd $root_folder
