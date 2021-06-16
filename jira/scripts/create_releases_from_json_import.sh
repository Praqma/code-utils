#!/usr/bin/env bash

set -e
set -u

[[ ${debug:-} == true ]] && set -x
[[ ${jira_server:-} == true ]] && ( echo "jira_server is not set" && exit 1 )

jira_key="${1}"
reqex_releases=${2} # '.*Sprint.*|.*6.*'
import_file=${3}

netrc_file=~/.netrc


echo "{ \"project\":\"$jira_key\"}" > jira_project.json

IFS=$'\r\n'
for release in $(jq -r ".projects[0].versions[] | select(.name? | match(\"${reqex_releases}\")).name" $import_file ) ; do
  version_already_exists=$(curl --fail --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --silent --url ${jira_server}/rest/api/2/project/${jira_key}/versions \
                            | jq -r ".[] |  select(.name==\"${release}\").name" )
  if [[ "${version_already_exists:-}" == "${release}" ]] ; then
    echo "Version: ${release} already exists in project: ${jira_key} - skip"
    continue
  else
    printf "Version: ${release} in project: ${jira_key} - create: "
  fi


  jq -r ".projects[0].versions[] | select(.name == \"${release}\")"  $import_file  > jira_release.json
  jq -s '.[0] * .[1]' jira_project.json jira_release.json > jira_release2.json

  if ! curl --fail --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json -o -  --silent --url ${jira_server}/rest/api/2/version --upload-file jira_release2.json > /dev/null ; then
    echo "Failed.. Maybe the release is already in the project.. Exit code: $?"
    cat jira_release2.json
    exit 1
  else
    printf " Done\n"
  fi
  rm -f jira_release.json
  rm -f jira_release2.json
done

rm -f jira_project.json