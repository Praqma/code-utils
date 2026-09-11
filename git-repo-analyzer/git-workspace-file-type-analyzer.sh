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

# .git contents are always skipped; this is not user-overridable.
git_exclude_pattern='\.git/|\.git$|^\.$'

# Extended-regex pattern of paths to keep in the file listing (passed to grep -E).
# Override via $2 or the FIND_INCLUDE_PATTERN env var, e.g. ".*\.mat$"; defaults to everything.
find_include_pattern="${2:-${FIND_INCLUDE_PATTERN:-.*}}"
echo "Find include pattern: ${find_include_pattern} . set as \$2 or FIND_INCLUDE_PATTERN to override"

# Select git-side binary detection mode:
# - "8kb"     : NUL character check (legacy mode name)
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
	# If the file contains a NUL byte anywhere.
  set +o pipefail
	if LC_ALL=C grep -a -q $'\x00' "$1" ; then
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

	# Treat as binary if the file contains a NUL byte anywhere.
	if LC_ALL=C grep -a -q $'\x00' "$1" ; then
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


function isFile8kbNul () {
	# If the file contains a NUL byte anywhere.
  set +o pipefail
	if LC_ALL=C grep -a -q $'\x00' "$1" ; then
    set -o pipefail
    return 0
  fi
  set -o pipefail
  return 1
}

# Processes a single file and appends its verdict to the shared result files.
# Writes are serialized via flock since this runs concurrently under xargs -P.
function process_file () {
	local filename="$1"
	local basename file_size fileext found_ext verdict result

	basename=$(basename "${filename}")
	file_size=$(du -sk "${filename}" | awk -F" " '{print $1}')
	fileext=${basename##*.}
	verdict=""

	if isFile8kbNul "$filename"; then
		verdict="${verdict}nB"
	else
		verdict="${verdict}nA"
	fi

	if isFileGitBinary "$filename"; then
		verdict="${verdict}gB"
	else
		verdict="${verdict}gA"
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

	{
		flock -x 200

		if [[ "${verdict}" == *gB* ]] ; then
			printf "%010d ${filename}\n" "$file_size" >> "${root_folder}/binary_files_size.txt"
			found_ext=$(cat "${root_folder}/binary_extension.txt" | sort -u | grep "^${fileext}$")
			if [ "${found_ext}" != "${fileext}" ] ; then
				echo "$fileext" >> "${root_folder}/binary_extension.txt"
			fi
		else
			printf "%010d ${filename}\n" "$file_size" >> "${root_folder}/ascii_files_size.txt"
			found_ext=$(cat "${root_folder}/ascii_extension.txt" | sort -u | grep "^${fileext}$")
			if [ "${found_ext}" != "${fileext}" ] ; then
				echo "$fileext" >> "${root_folder}/ascii_extension.txt"
			fi
		fi

		printf "%s : %9d : %-20s : '%s'\n" \
				"${verdict}" \
				"${file_size}" \
				"${mime_type}" \
				"${filename}" >> "${root_folder}/verdict_size.tmp"

		local done_count percent bar_width filled_width bar
		done_count=$(( $(cat "${root_folder}/verdict_progress.count") + 1 ))
		echo "${done_count}" > "${root_folder}/verdict_progress.count"
		percent=$(( done_count * 100 / total_files ))
		bar_width=40
		filled_width=$(( bar_width * done_count / total_files ))
		bar=$(printf "%${filled_width}s" | tr ' ' '#')
		printf "\r[%-${bar_width}s] %3d%% (%d/%d)" "${bar}" "${percent}" "${done_count}" "${total_files}" >&2
	} 200>>"${root_folder}/verdict_size.lock"
}

printf "Files to investigate: "
find . ! -type d | grep -vE "${git_exclude_pattern}" | grep -E "${find_include_pattern}" > "${root_folder}/files_found.txt"
total_files=$(wc -l < "${root_folder}/files_found.txt" | tr -d ' ')
echo "${total_files}"

: > "${root_folder}/verdict_size.lock"
echo 0 > "${root_folder}/verdict_progress.count"
export -f process_file isFile8kbNul isFileGitBinary isFileBinary
export root_folder git_binary_mode total_files

nproc_count=$(nproc 2>/dev/null || echo 4)
xargs -d '\n' -P "${nproc_count}" -I{} bash -c 'process_file "$1"' _ {} < "${root_folder}/files_found.txt"
echo >&2
rm -f "${root_folder}/verdict_progress.count" "${root_folder}/verdict_size.lock"

(
	echo "Combined 'file' and 'git' investigation of. Size is in Kb. Last information is 'file' tool output" \
														
	echo "nA: NUL char not found - Ascii"								
	echo "nB: NUL char found - Binary"								
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



