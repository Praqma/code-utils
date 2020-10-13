#!/usr/bin/env bash

set -e
set -u

[[ ${debug:-} == true ]] && set -x
[[ ${jira_server:-} == true ]] && ( echo "jira_server is not set" && exit 1 )

jira_key="${1}"
component_name="${2}"
component_lead="${3}"

netrc_file=~/.netrc

echo "{ \"project\":\"$jira_key\"}" > jira_project.json
echo "$jira_key, ${component_name}, ${component_lead}"

if [[ ${component_lead:-} == "" ]]; then
  echo "{ \"name\": \"${component_name}\", \"assigneeType\": \"UNASSIGNED\" }"  > jira_component.json
else
  echo "{ \"name\": \"${component_name}\", \"leadUserName\": \"${component_lead}\", \"assigneeType\": \"COMPONENT_LEAD\" }"  > jira_component.json
fi
jq -s '.[0] * .[1]' jira_project.json jira_component.json > jira_component2.json
rm jira_component.json
rm jira_project.json

if ! curl --fail --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json -o - --url ${jira_server}/rest/api/2/component --upload-file jira_component2.json  ; then
  echo "Failed.. Maybe the component is already in the project.. - exit 1"
  exit 1
fi
rm jira_component2.json
