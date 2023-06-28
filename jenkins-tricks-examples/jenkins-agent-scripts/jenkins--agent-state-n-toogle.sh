#!/bin/bash
set -euo pipefail

[[ ${debug:-} == true ]] && set -x 

# inspiration
# https://gist.github.com/scarytom/5910362
# https://lemmster.de/check-jenkins-for-running-executors-remotely-via-curl.html
# https://stackoverflow.com/questions/37227562/how-to-know-whether-the-jenkins-build-executors-are-idle-or-not-in-jenkins-using
# https://docs.cloudbees.com/docs/cloudbees-ci-kb/latest/client-and-managed-masters/execute-groovy-with-a-rest-call
# 

[[ ${1:-} == "" ]] && {
	echo "Please specify command as 1st parameter ( offline , online, state )"
	exit 1
}
command="$1"

[[ ${2:-} == "" ]] && {
	echo "Please specify agent name as 2nd parameter"
	exit 1
}
jenkins_agent_name="$2"

sleep_sec="5"
jenkins_server="<jenkins-server>"

if [[ ${netrc_file:-} != "" ]]; then 
	echo "Using netrc file $netrc_file"
	if [[ ! -f $netrc_file ]]; then 
		echo "ERROR: $netrc_file does not exist"
		exit 1
	fi
	netrc_file_option="--netrc-file ${netrc_file}"
else
	echo "Using default netrc file option. --netrc"
	netrc_file_option="--netrc-file /cygdrive/c/builds/.netrc"
fi

jenkins_agent_url="${jenkins_server}/computer/${jenkins_agent_name}"

function set_busy_executors() {
	local -n _busy_execeutors=$1
	_busy_execeutors=$(curl -s --insecure ${netrc_file_option:-} --silent ${jenkins_agent_url}/ajaxExecutors \
			| sed -e 's/<td class="pane" align="right" style="vertical-align: top">/\n/g' \
			| grep -E '^[0-9].+' \
			| grep href \
			| wc -l \
			) || {
				 local exitcode=$?
				 if [[ $exitcode == 1 ]]; then 
				 	_busy_execeutors=0
				 else
				 	echo "ERROR: Something when wrong - exit code $exitcode"
					exit 1
				 fi
			}
}

function print_state() {
	is_offline=$( curl -s --insecure ${netrc_file_option:-} ${jenkins_agent_url}/api/json | jq .offline )
	if [[ $is_offline == false ]]; then 
		printf "offline=false\n"
	else
		printf "offline=true\n"
	fi
}

case "${command}" in
	offline)
		# Mark as offline
		is_offline=$( curl -s --insecure ${netrc_file_option:-} ${jenkins_agent_url}/api/json | jq .offline )
		if [[ ${is_offline:-} == false ]]; then 
			echo "$jenkins_agent_name is online - mark it offline"
			curl -s --insecure ${netrc_file_option:-}  ${jenkins_agent_url}/toggleOffline --request 'POST' --data 'Marked offline to be able to manage agent / server'
		elif [[ ${is_offline:-} == true ]]; then
			echo "Agent $jenkins_agent_name is already offline"
			exit
		else
			echo "ERROR: offline is: ${is_offline:-}"
			exit 1
		fi

		# Assume it has busy executors
		busy_execeutors=
		set_busy_executors busy_execeutors
		while [[ $busy_execeutors -gt 0 ]]; do
			echo "There are $busy_execeutors busy executors - Wait $sleep_sec secs and test again"
			sleep $sleep_sec
			set_busy_executors busy_execeutors
			sleep_sec=$(( sleep_sec * 2))
		done

		echo "All executors are done .. - Safe to proceed"

		is_offline=$( curl -s --insecure ${netrc_file_option:-}  ${jenkins_agent_url}/api/json | jq .offline )
		printf "Agent %s is offline: %s\n" "${jenkins_agent_name}" "$is_offline"
		;;
	online)
		is_offline=$( curl -s --insecure ${netrc_file_option:-} ${jenkins_agent_url}/api/json | jq .offline )
		printf "Agent %s offline: %s\n" "${jenkins_agent_name}" "$is_offline"
		if [[ $is_offline == true ]]; then 
			echo "Setting online"
			curl -s --insecure ${netrc_file_option:-} ${jenkins_agent_url}/toggleOffline --request 'POST' --data 'Mark online'
			sleep 1
			print_state
		elif [[ ${is_offline:-} == false ]]; then
			echo "Agent ${jenkins_agent_name} is already online"
			exit
		else
			echo "ERROR: offline is: ${is_offline:-}"
			exit 1
		fi
		;;
	state)
		print_state
		;;
	*)
		echo "Unknown command: $command"
		exit 1
		;;
esac


