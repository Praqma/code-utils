#!/usr/bin/env bash



[[ ${debug:-} == true ]]  && set -x
set -u
set -e


[[ ${1:-} == "" ]] && echo "Please parse new project's desired key to as parameter 1"
jira_project_new_key="$1"

[[ ${2:-} == "" ]] && echo "Please parse new project's desired name to as parameter 2"
jira_project_new_name="$2"

[[ ${3:-} == "" ]] && echo "Please parse the project template to create from as parameter 3"
jira_project_template_key="$3"

[[ ${4:-} == "" ]] && echo "Please parse the project lead to create from as parameter 4"
jira_project_lead="$4"

if [[ ${create_mode:-} == "" ]]; then
  create_mode="skipOcreate" #deleteNcreate , skipNcreate(default), delete
  echo "Using default mode: create_mode=$create_mode - Options: deleteNcreate , skipOcreate(default), delete"
else
  echo "Using create_mode: $create_mode - Options: deleteNcreate , skipOcreate(default), delete"
fi

netrc_file=$(echo ~).netrc

curl_GET_cmd="curl --fail --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - "
curl_POST_cmd="curl --fail --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json  -o - "
curl_DELETE_cmd="curl --fail --insecure --netrc-file ${netrc_file} -X DELETE -H Content-Type:application/json  -o - "

project_key_found=$(${curl_GET_cmd} --silent --url "${jira_server}/rest/api/2/project/${jira_project_new_key}" | jq -r .key )

if [[ $create_mode == "delete" ]]; then
  if [[ "${project_key_found}" == "${jira_project_new_key}" ]] ; then
    printf "Project found: $project_key_found - delete it... and it might take some time depend on the amount of issues.."
    printf " - but sleep for 10 sec to offer abort...\n"
    sleep 10
    ${curl_DELETE_cmd} --url ${jira_server}/rest/api/2/project/${jira_project_new_key}
    exit 0
  else
    echo "Project not found: $jira_project_new_key - skip deleting"
    exit 0
  fi
fi

project_template_id=$(${curl_GET_cmd} --silent --url ${jira_server}/rest/api/2/project/${jira_project_template_key} | jq -r .id )
if [[ ${project_template_id} == "" ]] ; then
  echo "Template project: $jira_project_template_key NOT found on server: $jira_server"
  exit 1
fi

if [[ "${project_key_found}" == "${jira_project_new_key}" ]] ; then
  if [[ $create_mode == "deleteNcreate" ]]; then
    printf "Project found: $project_key_found - delete it first... and it might take some depend on the amount of issues.."
    if [[ ${force:-} == true ]] ; then
      printf " - run in force mode without sleeping\n"
    else
      printf " - but sleep for 10 sec to offer abort...\n"
      sleep 10
    fi
    echo ".. starting .."
    ${curl_DELETE_cmd} --url ${jira_server}/rest/api/2/project/${jira_project_new_key}
  fi
  if [[ $create_mode == "skipOcreate" ]]; then
    echo "Project found: $project_key_found - skip"
    exit 0
  fi
else
  echo "Project: $jira_project_new_key not found on server: $jira_server - create it"
fi

echo "Using project: $jira_project_template_key as template on $jira_server"

echo "Create new project key:$jira_project_new_key name:\"$jira_project_new_name\" from $jira_project_template_key"
$curl_POST_cmd  -d "{ \"key\":\"${jira_project_new_key}\", \"name\":\"${jira_project_new_name}\",\"lead\":\"$jira_project_lead\" }" \
                  --url ${jira_server}/rest/project-templates/1.0/createshared/${project_template_id}
echo

#curl -D- -u <username>:<password> -H "Content-Type:application/json" -X POST -d '{"user":["username"]}' -k https://jira-stg.example.com/rest/api/2/project/ABC/role/10002
