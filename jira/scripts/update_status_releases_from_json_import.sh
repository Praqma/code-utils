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
#jq -r ".projects[0].versions[] | select(.name? | match(\"${reqex_releases}\")).name" $import_file > releases.txt
#dos2unix releases.txt

echo "Getting versions"
http_code=$(curl --fail --insecure -w '%{http_code}\n'  --netrc-file ${netrc_file} -X GET -H Content-Type:application/json --silent --url ${jira_server}/rest/api/2/project/${jira_key}/versions -o ${jira_key}-versions.json) || {
  if [[ $http_code -eq 503 ]]; then
    echo "Try again in two seconds"
    sleep 2
    curl --fail --insecure -w '%{http_code}\n'  --netrc-file ${netrc_file} -X GET -H Content-Type:application/json --silent --url ${jira_server}/rest/api/2/project/${jira_key}/versions -o ${jira_key}-versions.json
  fi
}
jira_versions=$(cat ${jira_key}-versions.json)
import_versions=$(jq -r ".projects[0].versions[]" $import_file) # > import_versions.json

function update_version {
  printf  "."
  http_code=$(curl --fail --insecure  -s -w '%{http_code}\n' --netrc-file ${netrc_file} -X PUT -H Content-Type:application/json -o tmp.json --url ${jira_server}/rest/api/2/version/${release_jira_id} --upload-file jira_release.json)
}

echo "loop them"
IFS=$'\r\n'
for release in $(jq -r ".projects[0].versions[] | select(.name? | match(\"${reqex_releases}\")).name" $import_file ) ; do
  # TODO: extract the release ones and then get the id and released from that
  version_exists=$(echo $jira_versions | jq -r ".[] |  select(.name==\"${release}\").name" )
  if [[ "${version_exists:-}" == "${release}" ]] ; then
    release_jira_id=$(echo $jira_versions | jq -r ".[] |  select(.name==\"${release}\").id" )
    released_jira_value=$(echo $jira_versions | jq -r ".[] |  select(.name==\"${release}\").released" )
    released_import_value=$(echo $import_versions |  jq -r ". | select(.name==\"${release}\").released" )
    if [[ ${released_import_value} == "false" ]]; then
      released_new_value="true"
    elif [[ ${released_import_value} == "true" ]]; then
      released_new_value="false"
    else
      echo "$version_exists - WHY here - exit 1"
      exit 1
    fi
  else
    # Skip releases if the list contains mix of upper and lower cases
    # [[ ${release} == "" ]] && { echo "${release} - WARNING: lower/Upper cap issue - skip"; continue ; }
    echo "WHY Heres - exit 2"
    exit 2
  fi
  [[ ${released_jira_value} == ${released_new_value} ]] && {
    echo "$version_exists already as it should be : ${released_jira_value} == ${released_new_value}"
    continue
  }
  printf "$version_exists to be updated: "
  echo "{ \"released\": $released_new_value }" > jira_release.json

  http_code=503
  try=0
  while [[ $http_code -eq 503 ]] ; do
    #sleep $try
    update_version || true
    try=$(( try + 1 ))
  done
  unset try
  if [[ $http_code -eq 200 ]]; then
    printf " - All good : "
  else
    printf " Failed.. for unknown reason: $http_code "
    cat jira_release.json
    exit $http_code
  fi
  printf " $http_code : Done\n"
  rm -f jira_release.json
  rm -f jira_release2.json
done

rm -f jira_project.json