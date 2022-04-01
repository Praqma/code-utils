#!/usr/bin/env bash

set -e
set -u

[[ ${debug:-} == true ]] && set -x

[[ ${jira_server:-} == true ]] && ( echo "jira_server is not set" && exit 1 )

jira_key="${1}"
component_name="${2}"

netrc_file=~/.netrc


component_already_exists=$(curl --fail --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --silent --url ${jira_server}/rest/api/2/project/${jira_key}/components \
                            | jq -r ".[] |  select(.name==\"${component_name}\").name" )
if [[ "${component_already_exists:-}" == "${component_name}" ]] ; then
  printf "Component: ${component_name} exists in project: ${jira_key} - delete :"
else
  printf "Component: ${component_name} in project: ${jira_key} - does not exist - exit"
  exit 0
fi

component_id=$(curl --fail --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --silent --url ${jira_server}/rest/api/2/project/${jira_key}/components \
                            | jq -r ".[] |  select(.name==\"${component_name}\").id" )

exit

if ! curl --fail --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json -o - --silent --url ${jira_server}/rest/api/2/component --upload-file jira_component2.json > /dev/null; then
  echo "Failed.. Maybe the component is already in the project.. - exit 1"
  exit 1
else
  printf "Done\n"
fi
rm jira_component2.json
