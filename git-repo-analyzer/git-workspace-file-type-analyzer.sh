

root_folder=`pwd`

if [ "${1}X" == "X" ]; then
  echo "Please specify a folder as the first parameter to analyze.. "
  exit 1
fi
git_folder=$1

export PATH=/cygdrive/c/Program\ Files\ \(x86\)/Git/bin:${PATH}
export PATH=/cygdrive/c/Cygwin/bin:${PATH}

export PATH=/c/Program\ Files\ \(x86\)/Git/bin:${PATH}

export PATH=/c/Program\ Files/Git/usr/bin/:${PATH}
export PATH=/c/Program\ Files/Git/bin/:${PATH}
export PATH=/c/Program\ Files/Git/mingw64/bin/:${PATH}

export PATH=/c/Cygwin/bin:${PATH}
export PATH=/usr/bin:${PATH}


IsGitBinary() {
#    echo "Test: $1"
	p=$(printf '%s\t-\t' -)
    t=$(git diff --no-index --numstat /dev/null "$1"  )
    case "$t" in 
		"$p"*) 
				return 0 
				;; 
	esac 
	return 1
}

IsFileBinary() {
	mime_type=`file ${1} | awk -F": " '{print $NF}'`

	if [ "${mime_type}" == "empty" ] ; then
		return 2
	fi
	if [[ ${mime_type} != *" text"* ]] ; then
		return 0
	fi
	return 1
}

echo ${PATH}
pwd
if [ "${debug}X" == "trueX" ] ; then
  set -x
fi

rm -f ${root_folder}/binary_extension.txt
rm -f ${root_folder}/ascii_extension.txt
rm -f ${root_folder}/binary_files_size.txt
rm -f ${root_folder}/ascii_files_size.txt
rm -f ${root_folder}/verdict_size_sorted.txt
rm -f ${root_folder}/verdict_size.tmp
rm -f ${root_folder}/binary_files_size_sorted.txt
rm -f ${root_folder}/ascii_files_size_sorted.txt
touch ${root_folder}/binary_extension.txt
touch ${root_folder}/ascii_extension.txt
touch ${root_folder}/binary_files_size.txt
touch ${root_folder}/ascii_files_size.txt
touch ${root_folder}/verdict_size_sorted.txt
touch ${root_folder}/verdict_size.tmp
touch ${root_folder}/binary_files_size_sorted.txt
touch ${root_folder}/ascii_files_size_sorted.txt

cd ${git_folder}

git config --local core.autocrlf false


SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

printf "Files to investigate: "
find . ! -type d | grep -v '.git/' | grep -v '.git$' | grep -v '^.$' > ${root_folder}/files_found.txt
cat ${root_folder}/files_found.txt | wc -l
for filename in `cat ${root_folder}/files_found.txt` ; do
	basename=`basename ${filename}`
	file_size=`du -sk ${filename} | awk -F" " '{print $1}'`
	fileext=${basename##*.}
	found_ext=`cat ${root_folder}/binary_extension.txt ${root_folder}/ascii_extension.txt | sort -u | grep ^${fileext}$` 
	verdict=""

	echo "${filename}: "
    printf "    Size: ${file_size}\n"
    printf "    Git: "
	IsGitBinary "$filename"
	if [ "$?" -eq "0" ] ; then
		verdict="gB"
		printf "${verdict}\n"
		printf "%010d ${filename}\n" $file_size >> ${root_folder}/binary_files_size.txt 
		found_ext=`cat ${root_folder}/binary_extension.txt | sort -u | grep ^${fileext}$` 
		if [ "${found_ext}" != "${fileext}" ] ; then 
			echo $fileext >> ${root_folder}/binary_extension.txt
		fi 
	else
		verdict="gA"
		printf "${verdict}\n"
		printf "%010d ${filename}\n" $file_size >> ${root_folder}/ascii_files_size.txt 
		found_ext=`cat ${root_folder}/ascii_extension.txt | sort -u | grep ^${fileext}$` 
		if [ "${found_ext}" != "${fileext}" ] ; then 
			echo $fileext >> ${root_folder}/ascii_extension.txt
		fi 
	fi

	printf "    File: "
	IsFileBinary "$filename"
	result=$?
	if [ "$result" -eq "0" ] ; then
		printf "fB: ${mime_type}\n"
		verdict="${verdict}fB"
	elif [ "$result" -eq "2" ] ; then
		printf "fE: ${mime_type}\n"
		verdict="${verdict}fE"
	else
		printf "fA: ${mime_type}\n"
		verdict="${verdict}fA"
	fi

	printf "${verdict}: %010d ${filename} XXX ${mime_type}\n" ${file_size} >> ${root_folder}/verdict_size.tmp

done
IFS=$SAVEIFS

echo "Git verdicted binary files. Size is in Kb" >> ${root_folder}/binary_files_size_sorted.txt
echo "---------------------------------"         >> ${root_folder}/binary_files_size_sorted.txt
sort -r ${root_folder}/binary_files_size.txt     >> ${root_folder}/binary_files_size_sorted.txt

echo "Git verdicted ascii files. Size is in Kb"  >> ${root_folder}/ascii_files_size_sorted.txt
echo "---------------------------------"         >> ${root_folder}/ascii_files_size_sorted.txt
sort -r ${root_folder}/ascii_files_size.txt      >> ${root_folder}/ascii_files_size_sorted.txt

echo "Combined 'file' and 'git' investigation of. Size is in Kb. Last information is 'file' tool output" \
															>> ${root_folder}/verdict_size_sorted.txt
echo "gA: Git ascii"										>> ${root_folder}/verdict_size_sorted.txt
echo "gB: Git binary"										>> ${root_folder}/verdict_size_sorted.txt
echo "fA: 'file' tool reported 'ASCII text'"				>> ${root_folder}/verdict_size_sorted.txt
echo "fE: 'file' tool reported it as 'empty'"	            >> ${root_folder}/verdict_size_sorted.txt
echo "fB: 'file' tool reported other than 'ASCII text'"		>> ${root_folder}/verdict_size_sorted.txt
echo "------------------------------------------------"		>> ${root_folder}/verdict_size_sorted.txt

# Copy the header for type sorting as well
cp ${root_folder}/verdict_size_sorted.txt ${root_folder}/verdict_type_sorted.txt

echo "Generate the list of ${root_folder}/verdict_size_sorted.txt"
sort -k2 -r ${root_folder}/verdict_size.tmp  >> ${root_folder}/verdict_size_sorted.txt

echo "Generate the list of ${root_folder}/verdict_type_sorted.txt"
sort -r ${root_folder}/verdict_size.tmp      >> ${root_folder}/verdict_type_sorted.txt


