#!/usr/bin/env bash

set -euo pipefail

function end {
	powershell -Command Get-Volume || df -h
	date "+%Y-%m-%d %H:%M:%S"
}

TRAP 'end' 0 SIGINT SIGTERM SIGABRT SIGQUIT SIGHUP
 
[[ ${debug:-} == true ]] && set -x
[[ ${1:-} == "" ]] && { echo "Please specify the repos root or the bare repo directory to gc" ; exit 1 ; }

[[ ${aggressive:-} == true ]] && { echo "Running aggressive" && aggressive="--aggressive"; }

bitbucket_repo_root=$1
[[ ! -d $bitbucket_repo_root ]] && { echo "$bitbucket_repo_root does not exist" ; exit 1; }
cd $bitbucket_repo_root

date "+%Y-%m-%d %H:%M:%S" 

if [[ $(git config core.bare) == "true" ]]; then
	repos=$(basename `pwd`)
	echo "Executing single repo: $repos"
	cd ..
else
	repos=$(ls -1)
	printf "Executing server repos: %s\n"  $(ls -1 | wc -l)
fi

powershell -Command Get-Volume || df -h

IFS=$'\r\n'
for repo_id in $repos; do
	echo
	echo "BEGIN: $repo_id"
	cd $repo_id
	cat repository-config
	printf "%s - before\n" "$(du -sh . )"
	printf "\nEmpty paths in refs/:\n"
	/usr/bin/find refs/ -type d -empty
	echo
	printf "count-objects:\n" 
	git count-objects -v || { 
			echo $? 
			ls -la
			cd -
			echo "END: $repo_id"
			continue
		}
	echo
	git_gc_cmd="git gc ${aggressive:-}"
	if [[ ${dryrun:-} == true ]]; then
		echo "Dryrun: ${git_gc_cmd}"
	else
		eval ${git_gc_cmd} || {
			sleep 60
			eval ${git_gc_cmd} || {
				echo $? 
				ls -la
				cd -
				echo "END: $repo_id"
				continue
			}
		}
	fi
	echo
	echo "Branches: after"
	/usr/bin/find refs/ -type d -empty 
	printf "count-objects:\n" 
	git count-objects -v
	printf "%s - after\n" "$(du -sh . )"
	cd -
	echo "END: $repo_id"
	echo 
done

