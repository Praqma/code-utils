#!/usr/bin/env bash

set -e
set -x
set -u

bitbucket_admin_user=admin
bitbucket_admin_password=password
bitbucket_url=http://10.13.192.69:7990/bitbucket
ci_user=jenkins

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

function create_permission_set_restricted {
    local _branch_pattern=$1
    local _user=$2
    local _bitbucket_project=$3
    local _repo_name=$4

    generate_restriction_json read-only "${_branch_pattern}" "${_user}" > bitbucket_branch_permissions.json
    curl --fail -D- -u ${bitbucket_admin_user}:${bitbucket_admin_password} -H "Content-Type: application/json" -X POST ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    generate_restriction_json fast-forward-only "${_branch_pattern}" "" > bitbucket_branch_permissions.json
    curl --fail -D- -u ${bitbucket_admin_user}:${bitbucket_admin_password} -H "Content-Type: application/json" -X POST ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    generate_restriction_json no-deletes "${_branch_pattern}" ""  > bitbucket_branch_permissions.json
    curl --fail -D- -u ${bitbucket_admin_user}:${bitbucket_admin_password} -H "Content-Type: application/json" -X POST ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    rm bitbucket_branch_permissions.json
}

function create_permission_set_semi-restricted {
    local _branch_pattern=$1
    local _user=$2
    local _bitbucket_project=$3
    local _repo_name=$4

    generate_restriction_json fast-forward-only "${_branch_pattern}" "" > bitbucket_branch_permissions.json
    curl --fail -D- -u ${bitbucket_admin_user}:${bitbucket_admin_password} -H "Content-Type: application/json" -X POST ${bitbucket_url}/rest/branch-permissions/2.0/projects/${_bitbucket_project}/repos/${_repo_name}/restrictions --upload-file bitbucket_branch_permissions.json

    rm bitbucket_branch_permissions.json
}

function create_repo {
    local _bitbucket_project=$1
    local _repo_name=$2
    local _push_type=$3
    curl --fail -D- -u ${bitbucket_admin_user}:${bitbucket_admin_password} -X POST -H "Content-Type: application/json" ${bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos -d "{ \"name\":\"${_repo_name}\", \"forkable\":false }"

    curl --fail -D- -u ${bitbucket_admin_user}:${bitbucket_admin_password} -X PUT   ${bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name}/settings/hooks/com.atlassian.bitbucket.server.bitbucket-bundled-hooks:force-push-hook/enabled

    # Fill repo with an empty
    if [ -d ${_repo_name} ]; then
        cd ${_repo_name}
        if [ "${_push_type}X" == "--mirrorX" ]; then
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git ${_push_type}
        else
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:master
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:stable
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git master:release
          git push ${bitbucket_url}/scm/${_bitbucket_project}/${_repo_name}.git --tags
        fi
        cd -
    fi
}

bitbucket_project="TES"
if [ "${1}X" == "X" ] ; then
  repo_names="test_from_curl" # space seperated list
fi

for repo_name in "${repo_names}"; do
  create_repo ${bitbucket_project} ${repo_name} "--mirror"
    create_permission_set_restricted "heads/*" $bitbucket_admin_user $bitbucket_project $repo_name   # only admin creates new 'root' branches and 'name-spaces'

    create_permission_set_restricted "heads/**/master"  $ci_user $bitbucket_project $repo_name
    create_permission_set_restricted "heads/**/stable"  $ci_user $bitbucket_project $repo_name
    create_permission_set_restricted "heads/**/release" $ci_user $bitbucket_project $repo_name
    create_permission_set_restricted "tags/**"          $ci_user $bitbucket_project $repo_name

    create_permission_set_semi-restricted "heads/**/ready/*" "" $bitbucket_project $repo_name
done
