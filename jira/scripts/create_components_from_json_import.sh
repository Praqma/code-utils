#!/usr/bin/env bash

set -e
set -u

[[ ${debug:-} == true ]] && set -x
[[ ${jira_server:-} == true ]] && ( echo "jira_server is not set" && exit 1 )

jira_key="${1}"
reqex_components=${2} # '.*Sprint.*|.*6.*'
import_file=${3}


netrc_file=~/.netrc


echo "{ \"project\":\"$jira_key\"}" > jira_project.json

IFS=$'\r\n'
for component in $(jq -r ".projects[0].components[] | select(.name? | match(\"${reqex_components}\")).name" $import_file ) ; do
  echo $component
  jq -r ".projects[0].components[] | select(.name == \"${component}\")"  $import_file  > jira_component.json
  jq -s '.[0] * .[1]' jira_project.json jira_component.json > jira_component2.json
  rm jira_component.json

  if ! curl --fail --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json -o - --url ${jira_server}/rest/api/2/component --upload-file jira_component2.json  ; then
    echo "Failed.. Maybe the component is already in the project.. Exit code: $?"
    exit 1
  fi
  echo
  rm -f jira_component2.json
done
rm jira_project.json
