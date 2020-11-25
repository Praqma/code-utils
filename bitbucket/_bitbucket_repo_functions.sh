#!/usr/bin/env bash

curl_PUT_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X PUT"
curl_DELETE_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X DELETE"
curl_POST_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json "

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

    ${curl_POST_cmd} ${_bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos -d "{ \"name\":\"${_repo_name}\", \"forkable\":true }"

    # Fill repo
    if [ -d ${_repo_name} ]; then
        cd ${_repo_name}
        if [[ "${_push_type}" == "--mirror" ]]; then
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git ${_push_type}
        else
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:master
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:stable || echo "Skipped"
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:release || echo "Skipped"
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git --tags
        fi
        cd -
    fi
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
    local _bitbucket_url=$1
    local _project=$2
    local _repo=$3
    curl --fail -D- --insecure --netrc-file ~/.netrc -X DELETE ${_bitbucket_url}/rest/api/1.0/projects/${_project}/repos/${_repo}

}

function repo_git_lfs_enable(){
    # Fixme: https://jira.atlassian.com/browse/BSERV-8935
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
    local _bitbucket_url=$1
    local _project=$2
    local _repo=$3
    curl --fail -D- --insecure --netrc-file ~/.netrc -X DELETE ${_bitbucket_url}/rest/api/1.0/projects/${_project}/repos/${_repo}

    rest/git-lfs/admin/projects/<key>/repos/<slug>/enabled
}