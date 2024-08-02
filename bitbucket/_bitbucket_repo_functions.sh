#!/usr/bin/env bash

curl_PUT_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X PUT"
curl_PUT_nofail_cmd="curl --insecure --netrc-file ${netrc_file} -X PUT"
curl_DELETE_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X DELETE"
curl_POST_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json "
curl_POST_nofail_cmd="curl --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json "

function generate_restriction_json {
    local _restriction_type=$1
    local _restriction_pattern=$2
    local _restriction_type=$3

    if [ "${3}x" == "x" ] ; then
        echo "{ \
            \"id\": 1,    \
            \"type\": \"$1\",    \
            \"matcher\": 	{        \
                \"id\": \"$2\",  \
                \"displayId\": \"$2\",    \
                \"type\": {         \
                    \"id\": \"PATTERN\",   \
                    \"name\": \"Pattern\"   \
                },   \
                \"active\": true \
            },   \
            \"users\": [  ], \
            \"groups\": [     ] \
        } "
    else
        echo "{ \
            \"id\": 1,    \
            \"type\": \"$1\",    \
            \"matcher\": 	{        \
                \"id\": \"$2\",  \
                \"displayId\": \"$2\",    \
                \"type\": {         \
                    \"id\": \"PATTERN\",   \
                    \"name\": \"Pattern\"   \
                },   \
                \"active\": true \
            },   \
            \"users\": [ \"$3\" ], \
            \"groups\": [     ] \
        } "
        fi
}

function generate_restriction_json_groups {
    local _restriction_type=$1
    local _restriction_pattern=$2
    local _restriction_type=$3

        echo "{ \
            \"id\": 1,    \
            \"type\": \"$1\",    \
            \"matcher\": 	{        \
                \"id\": \"$2\",  \
                \"displayId\": \"$2\",    \
                \"type\": {         \
                    \"id\": \"PATTERN\",   \
                    \"name\": \"Pattern\"   \
                },   \
                \"active\": true \
            },   \
            \"users\": [  ], \
            \"groups\": [ \"$3\"    ] \
        } "
}

function create_permission_set_restricted {
    local _branch_pattern=$1
    local _user=$2
    local _bitbucket_project=$3
    local _repo_name=$4

    generate_restriction_json read-only "${_branch_pattern}" "${_user}" > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    generate_restriction_json fast-forward-only "${_branch_pattern}" "" > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    generate_restriction_json no-deletes "${_branch_pattern}" ""  > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    rm bitbucket_branch_permissions.json
}

function create_permission_set_restricted_groups {
    local _branch_pattern=$1
    local _group=$2
    local _bitbucket_project=$3
    local _repo_name=$4

    generate_restriction_json_groups read-only "${_branch_pattern}" "${_group}" > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    generate_restriction_json fast-forward-only "${_branch_pattern}" "" > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    generate_restriction_json no-deletes "${_branch_pattern}" ""  > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    rm bitbucket_branch_permissions.json
}

function create_permission_set_rewrite_history {
    local _branch_pattern=$1
    local _user=$2
    local _bitbucket_project=$3
    local _repo_name=$4

    generate_restriction_json fast-forward-only "${_branch_pattern}" "" > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    rm bitbucket_branch_permissions.json
}

function create_permission_set_rewrite_history_deletion {
    local _branch_pattern=$1
    local _group=$2
    local _bitbucket_project=$3
    local _repo_name=$4

    generate_restriction_json fast-forward-only "${_branch_pattern}" "" > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    generate_restriction_json_groups no-deletes "${_branch_pattern}" $_group > bitbucket_branch_permissions.json
    ${curl_POST_cmd} ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    rm bitbucket_branch_permissions.json
}

function create_repo {
    if [[ -z $1 ]] ; then
        echo "Please set bitbucket_url as parameter 1"
        return 1
    fi
    local _bitbucket_url=$1

    if [[ -z $2 ]] ; then
        echo "Please set bitbucket project name as parameter 2"
        return 1
    fi
    local _bitbucket_project=$2

    if [[ -z $3 ]] ; then
        echo "Please set repo name as parameter 3"
        return 1
    fi
    local _repo_name=$3

    if [[ -z ${4:-} ]] ; then
      echo "Push type skipped Skip"
      local _push_type=""
    else
      local _push_type=$4
    fi
#-w "%{stderr}{\"status\": \"%{http_code}\", \"body\":\"%{stdout}\"}"
    reponse_json=$(${curl_POST_nofail_cmd} -sS -w ",{ \"status\": \"%{http_code}\" }" ${_bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos -d "{ \"name\":\"${_repo_name}\", \"forkable\":true }" )
    reponse_code=$(echo "[$reponse_json]" | jq -r .[1].status )
    case $reponse_code in
      201)
        echo "All good - repo created"
        ;;
      409)
        echo "Skip - repo already exists"
        echo "[$reponse_json]" | jq -r .[0].errors[]
        ;;
      *)
        echo "ERROR - something when wrong"
        echo "[$reponse_json]" | jq -r .[0].errors[]
        exit 1
        ;;
    esac

    # Fill repo
    if [ -d ${_repo_name} ]; then
        cd ${_repo_name}
        if [[ "${_push_type}" == "--mirror" ]]; then
          git push ${_bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git ${_push_type}
        else
          git push ${_bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:master
          git push ${_bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:stable || echo "Skipped"
          git push ${_bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:release || echo "Skipped"
          git push ${_bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git --tags
        fi
        cd -
    fi
}

function repo_move {
    if [[ -z $1 ]] ; then
        echo "Please set bitbucket_url as parameter 1"
        return 1
    fi
    local _bitbucket_url=$1

    if [[ -z $2 ]] ; then
        echo "Please set bitbucket project name as parameter 2"
        return 1
    fi
    local _bitbucket_project=$2

    if [[ -z $3 ]] ; then
        echo "Please set repo name (slug) as parameter 3"
        return 1
    fi
    local _repo_name=$3

    if [[ -z $4 ]] ; then
        echo "Please set bitbucket project name as parameter 2"
        return 1
    fi
    local _bitbucket_new_project=$4

#-w "%{stderr}{\"status\": \"%{http_code}\", \"body\":\"%{stdout}\"}"
    response_json=$(${curl_PUT_nofail_cmd} -H Content-Type:application/json -sS -w ",{ \"status\": \"%{http_code}\" }" ${_bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name} -d "{ \"project\": { \"key\" : \"${_bitbucket_new_project}\" }} " )
    response_code=$(echo "[$response_json]" | jq -r .[1].status 2> /dev/null ) || {
        IFS=, read  -r response_string response_status_json <<< "$response_json"
        response_code=$(jq -r .status <<< ${response_status_json} )
    }
    case $response_code in
      201)
        echo "All good - repo moved: ${_bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name} to ${_bitbucket_new_project}"
        ;;
      307)
        echo "Skip - repo source ${_bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name} already moved"
        echo "$response_string"
        ;;
      404)
        echo "Skip - repo source ${_bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name} does not exist"
        echo "[$response_json]" | jq -r .[0].errors[]
        ;;
      409)
        echo "Skip - repo already exists in project: ${_bitbucket_new_project}"
        echo "[$response_json]" | jq -r .[0].errors[]
        ;;
      *)
        echo "ERROR - something when wrong"
        echo "[$response_json]" | jq -r .[0].errors[]
        exit 1
        ;;
    esac
}


function repo_prereceive_force_push_hook_enable () {
    if [[ -z $1 ]] ; then
        echo "Please set repo name as parameter 1"
        return 1
    fi
    local _repo_name=${1}

    if [[ -z $2 ]] ; then
        echo "Please set bitbucket project as parameter 2"
        return 1
    fi
    local _bitbucket_project=${2}

    if [[ -z ${bitbucket_url} ]] ; then
        echo "Please make sure that bitbucket_url variable before calling this function "
        return 1
    fi

    cmd="${curl_PUT_cmd} ${bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name}/settings/hooks/com.atlassian.bitbucket.server.bitbucket-bundled-hooks:force-push-hook/enabled"
    printf "excecute: $cmd\n"
    $cmd
    printf "\n"
}

function repo_prereceive_force_push_hook_disable () {
    if [[ -z $1 ]] ; then
        echo "Please set repo name as parameter 1"
        return 1
    fi
    local _repo_name=${1}

    if [[ -z $2 ]] ; then
        echo "Please set bitbucket project as parameter 2"
        return 1
    fi
    local _bitbucket_project=${2}

    if [[ -z ${bitbucket_url} ]] ; then
        echo "Please make sure that bitbucket_url variable before calling this function "
        return 1
    fi
    cmd="${curl_DELETE_cmd} ${bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name}/settings/hooks/com.atlassian.bitbucket.server.bitbucket-bundled-hooks:force-push-hook/enabled"
    printf "excecute: $cmd\n"
    $cmd
    printf "\n"

}

function delete_repo () {
    if [[ -z $1 ]] ; then
        echo "Please set bitbucket_url as parameter 1"
        return 1
    fi
    if [[ -z $2 ]] ; then
        echo "Please set bitbucket project name as parameter 2"
        return 1
    fi
    if [[ -z $3 ]] ; then
        echo "Please set repo name as parameter 3"
        return 1
    fi
    if [[ -z $4 ]] ; then
        echo "Please set netrc file as parameter 4"
        return 1
    fi
    local _bitbucket_url=$1
    local _project=$2
    local _repo=$3
    local _netrc_file="$4"
    curl --fail --insecure --netrc-file ${_netrc_file} -X DELETE ${_bitbucket_url}/rest/api/1.0/projects/${_project}/repos/${_repo}
}

function repo_git_lfs_enable () {
    # https://jira.atlassian.com/browse/BSERV-8935
    #There's actually an undocumented endpoint for interacting with LFS. It's rough and clearly not polished, but it works.
    # rest/git-lfs/admin/projects/<key>/repos/<slug>/enabled
    # GET will return a 200 if its enabled, 404 if it's disabled.
    # PUT to enable
    # DELETE to disable
    if [[ -z $1 ]] ; then
        echo "Please set bitbucket_url as parameter 1"
        return 1
    fi
    if [[ -z $2 ]] ; then
        echo "Please set bitbucket project name as parameter 2"
        return 1
    fi
    if [[ -z $3 ]] ; then
        echo "Please set repo name as parameter 3"
        return 1
    fi
    if [[ -z $4 ]] ; then
        echo "Please set netrc file as parameter 4"
        return 1
    fi
    local _bitbucket_url=$1
    local _project=$2
    local _repo=$3
    local _netrc_file=$4
    curl --fail --insecure --netrc-file ${_netrc_file} -X PUT -H Content-Type:application/json -o - --url ${_bitbucket_url}/rest/git-lfs/admin/projects/${_project}/repos/${_repo}/enabled
}

function repo_branch_create () {
  if [[ -z $1 ]] ; then
      echo "Please set bitbucket_url as parameter 1"
      return 1
  fi
  if [[ -z $2 ]] ; then
      echo "Please set bitbucket project name as parameter 2"
      return 2
  fi
  if [[ -z $3 ]] ; then
      echo "Please set repo name as parameter 3"
      return 3
  fi
  if [[ -z $4 ]] ; then
      echo "Please set netrc-file as parameter 4"
      return 4
  fi
  if [[ -z $5 ]] ; then
      echo "Please set sha1 as parameter 5"
      return 5
  fi
  if [[ -z $6 ]] ; then
      echo "Please set branch as parameter 6"
      return 6
  fi
  local _bitbucket_url=$1
  local _bitbucket_project=$2
  local _repo=$3
  local _netrc_file=$4
  local _sha1=$5
  local _branch=$6

  reponse_json=$(${curl_POST_nofail_cmd} -sS -w ",{ \"status\": \"%{http_code}\" }" ${_bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo}/branches \
                    -d "{ \"name\": \"${_branch}\", \"startPoint\": \"${_sha1}\", \"message\": \"Branch creation $_branch\"} " )
  reponse_code=$(echo "[$reponse_json]" | jq -r .[1].status )
  case $reponse_code in
      200)
        echo "All good - branch created: $_branch @ $_repo @ $_bitbucket_project"
        ;;
      409)
        echo "Skip - repo already exists:  $_branch @ $_repo @ $_bitbucket_project"
        echo "[$reponse_json]" | jq -r .[0].errors[]
        ;;
      *)
        echo "ERROR - something when wrong"
        echo "[$reponse_json]" | jq -r .[0].errors[]
        exit 1
        ;;
  esac



#https://docs.atlassian.com/bitbucket-server/rest/7.6.0/bitbucket-rest.html
#  /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/branches
#METHODS
#POST
#This API can also be invoked via a user-centric URL when addressing repositories in personal projects.
#
#Creates a branch using the information provided in the {@link RestCreateBranchRequest request}
#
#The authenticated user must have REPO_WRITE permission for the context repository to call this resource.
#
#Example request representations:
#
#application/json [collapse]
#EXAMPLE
#{
#    "name": "my-branch",
#    "startPoint": "8d351a10fb428c0c1239530256e21cf24f136e73",
#    "message": "This is my branch"
#}
#Example response representations:
#
#200 - application/json (branch) [expand]
#401 - application/json (errors) [expand]
#404 - application/json (errors) [expand]
}