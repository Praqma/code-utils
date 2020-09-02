#!/bin/bash
#set -x

input_file=$1

IFS=$'\r\n'
#for user in `jq .users[].name ${input_file} | sed -e 's/"//g'`
#for user in $(ccm users -l)
jira_user_group="change_synergy-import-unused-users"
for user in $(curl --silent --fail --insecure --netrc-file /z//.netrc -X GET -H "Content-Type:application/json"   --url "${jira_server}/rest/api/2/group/member?groupname=${jira_user_group}&includeInactiveUsers=true" | jq -r .values[].key)
do
	echo "Delete: ${user}"
	curl --insecure --request DELETE --netrc-file ~/.netrc --url ${jira_server}/rest/api/2/user?username=$user
	sleep 1
done
