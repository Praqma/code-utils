#!/bin/bash

set -u -o pipefail
# set -e # not ready for this yet - usage of grep and some git commands

if [[ $WORKSPACE == "" ]]; then 
	echo "WORKSPACE is not set.. output in current folder: ${PWD}"
else
	echo "WORKSPACE is set to: ${WORKSPACE} - output in WORKSPACE folder"
	cd "$WORKSPACE"
fi
root_folder=$(pwd)

if [ "${1}X" == "X" ]; then
  echo "Please specify a folder as the first parameter to analyze.. "
  exit 1
fi

[[ ${debug:-} == true ]] && { 
  set -x
  keep_tmp_files=true
}

git_folder=$1

# Select git-side binary detection mode:
# - "8kb"     : fast heuristic (NUL in first 8KB)
# - "gitdiff" : original git diff --no-index --numstat check
git_binary_mode="${GIT_BINARY_MODE:-${git_binary_mode:-gitdiff}}"
case "${git_binary_mode}" in
  8kb|gitdiff) ;;
  *)
    echo "WARNING: Unknown GIT_BINARY_MODE='${git_binary_mode}', fallback to '8kb'"
    git_binary_mode="8kb"
    ;;
esac
echo "Git binary detection mode: ${git_binary_mode} . set git_binary_mode=gitdiff to use git diff --no-index --numstat check - slower but more accurate"

export PATH=/cygdrive/c/Program\ Files\ \(x86\)/Git/bin:${PATH}
export PATH=/cygdrive/c/Cygwin/bin:${PATH}

export PATH=/c/Program\ Files\ \(x86\)/Git/bin:${PATH}

export PATH=/c/Program\ Files/Git/usr/bin/:${PATH}
export PATH=/c/Program\ Files/Git/bin/:${PATH}
export PATH=/c/Program\ Files/Git/mingw64/bin/:${PATH}

export PATH=/c/Cygwin/bin:${PATH}
export PATH=/usr/bin:${PATH}

function isFile8kbNul () {
  # if first 8KB contains a NUL byte.
  set +o pipefail
  if cat "$1" | LC_ALL=C od -An -tx1 -N 8192 | grep -qiE '(^|[[:space:]])00([[:space:]]|$)' ; then
    set -o pipefail
    return 0
  fi
  set -o pipefail
  return 1
}


function isFileGitBinary() {
	if [[ "${git_binary_mode}" == "gitdiff" ]]; then
		p=$(printf '%s\t-\t' -)
		t=$(git diff --no-index --numstat /dev/null "$1")
		case "$t" in
			"$p"*)
				return 0
				;;
		esac
		return 1
	fi

	# Fast heuristic: treat as binary if first 8KB contains a NUL byte.
	if LC_ALL=C od -An -tx1 -N 8192 "$1" 2>/dev/null | grep -qiE '(^|[[:space:]])00([[:space:]]|$)' ; then
		return 0
	fi
	return 1
}

function isFileBinary() {
	mime_type=$(file --mime-type "${1}" | awk -F": " '{print $NF}')

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

pwd
echo "Git binary mode: ${git_binary_mode}"
if [ "${debug:-}debug" == "truedebug" ] ; then
  set -x
fi

: > "${root_folder}/binary_extension.txt"
: > "${root_folder}/ascii_extension.txt"
: > "${root_folder}/binary_files_size.txt"
: > "${root_folder}/ascii_files_size.txt"
: > "${root_folder}/verdict_size_sorted.txt"
: > "${root_folder}/verdict_size.tmp"
: > "${root_folder}/binary_files_size_sorted.txt"
: > "${root_folder}/ascii_files_size_sorted.txt"

cd "${git_folder}"

git config --local core.autocrlf false


SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

function isFile8kbNul () {
  # if first 8KB contains a NUL byte.
  set +o pipefail
  if cat "$1" | LC_ALL=C od -An -tx1 -N 8192 | grep -qiE '(^|[[:space:]])00([[:space:]]|$)' ; then
    set -o pipefail
    return 0
  fi
  set -o pipefail
  return 1
}


printf "Files to investigate: "
find . ! -type d | grep -v '.git/' | grep -v '.git$' | grep -v '^.$' > "${root_folder}/files_found.txt"
cat "${root_folder}/files_found.txt" | wc -l
for filename in $(cat "${root_folder}/files_found.txt") ; do
	basename=$(basename "${filename}")
	file_size=$(du -sk "${filename}" | awk -F" " '{print $1}')
	fileext=${basename##*.}
	found_ext=$(cat "${root_folder}/binary_extension.txt" "${root_folder}/ascii_extension.txt" | sort -u | grep "^${fileext}$" || echo "")
	verdict=""

    verdict=""
    if isFile8kbNul "$filename"; then
      verdict="${verdict}nB"
    else
      verdict="${verdict}nA"
    fi

    if isFileGitBinary "$filename"; then
        verdict="${verdict}gB"
		printf "%010d ${filename}\n" "$file_size" >> "${root_folder}/binary_files_size.txt"
		found_ext=$(cat "${root_folder}/binary_extension.txt" | sort -u | grep "^${fileext}$")
		if [ "${found_ext}" != "${fileext}" ] ; then 
			echo "$fileext" >> "${root_folder}/binary_extension.txt"
		fi 
    else
        verdict="${verdict}gA"
		printf "%010d ${filename}\n" "$file_size" >> "${root_folder}/ascii_files_size.txt"
		found_ext=$(cat "${root_folder}/ascii_extension.txt" | sort -u | grep "^${fileext}$")
		if [ "${found_ext}" != "${fileext}" ] ; then 
			echo "$fileext" >> "${root_folder}/ascii_extension.txt"
		fi 
    fi

    result=0  
    isFileBinary "$filename" || result=$?
    if [ "$result" -eq "0" ] ; then
      verdict="${verdict}fB"
    elif [ "$result" -eq "2" ] ; then
      verdict="${verdict}fE"
    else
      verdict="${verdict}fA"
    fi
	
	mime_type_display="${mime_type}"
	if [ ${#mime_type_display} -gt 20 ] ; then
		mime_type_display="${mime_type_display:0:18}.."
	fi

	printf "%s : %9d : %-20s : '%s'\n" \
			"${verdict}" \
			"${file_size}" \
			"${mime_type}" \
			"${filename}" >> "${root_folder}/verdict_size.tmp"
	printf "%s : %9d : %-20s : '%s'\n" \
			"${verdict}" \
			"${file_size}" \
			"${mime_type_display}" \
			"${filename}"

done
IFS=$SAVEIFS

(
	echo "Git verdicted binary files. Size is in Kb"
	echo "---------------------------------"        
	sort -r "${root_folder}/binary_files_size.txt"

	echo "Git verdicted ascii files. Size is in Kb" 
	echo "---------------------------------"        
	sort -r "${root_folder}/ascii_files_size.txt"     

	echo "Combined 'file' and 'git' investigation of. Size is in Kb. Last information is 'file' tool output" \
														
	echo "nA: od 8kb NUL char not found - Ascii"								
	echo "nB: od 8kb NUL char not found - Binary"								
	echo "gA: Git Ascii"								
	echo "gB: Git Binary"								
	echo "fA: 'file' tool reported 'ASCII text'"		
	echo "fE: 'file' tool reported it as 'empty'"
	echo "fB: 'file' tool reported other than 'ASCII text'"
	echo "----------------------------------------------------------"
	printf "%s : %9s : %-20s : '%s'\n" "Verdict" "Size(Kb)" "Mime Type" "Filename"
	echo "----------------------------------------------------------"	
) 	>> "${root_folder}/verdict_size_sorted.txt"

# Copy the header for type sorting as well
cp "${root_folder}/verdict_size_sorted.txt" "${root_folder}/verdict_type_sorted.txt"

echo "Generate the list of ${root_folder}/verdict_size_sorted.txt"
sort -k2 -r "${root_folder}/verdict_size.tmp"  >> "${root_folder}/verdict_size_sorted.txt"

echo "Generate the list of ${root_folder}/verdict_type_sorted.txt"
sort -r "${root_folder}/verdict_size.tmp"      >> "${root_folder}/verdict_type_sorted.txt"

if [[ ${keep_tmp_files:-} == true ]]; then
	echo "Debugging mode : leave *.tmp files"
else
	echo "Removing *.tmp files"
	rm -rf "${root_folder}/verdict_size.tmp"
fi



