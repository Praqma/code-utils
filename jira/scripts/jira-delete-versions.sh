#!/bin/bash
#set -x

jira_server=$1
input_file=$2

for id in `jq .[].id ${input_file} | sed -e 's/"//g'`
do
	curl --insecure --request DELETE --netrc-file ./.netrc --url 'https://${jira_server}/rest/api/2/version/'$id''
done


https://${jira_server}/rest/api/2/user/application?username=v7y1uvq&applicationKey=
https://${jira_server}/rest/plugins/applications/1.0/installed/jira-software/license
https://${jira_server}/rest/api/2/group/change_synergy-import-unused-users
groupname=change_synergy-import-unused-users
/rest/api/1.0/admin/groups/more-members?context=change_synergy-import-unused-users&limit=1000