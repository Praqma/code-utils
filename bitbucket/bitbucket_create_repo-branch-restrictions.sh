#!/usr/bin/env bash

set -e
set -x
set -u

if [ "${1}X" == "X" ] ; then
  bitbucket_project="test_proj" # space seperated list
else
  bitbucket_project=${1} # space seperated list
fi


if [ "${2}X" == "X" ] ; then
  repo_names="test_from_curl" # space seperated list
else
  repo_names="${2}" # space seperated list
fi

if [ "${3}X" == "X" ] ; then
  netrc_file=".netrc" # space seperated list
else
  netrc_file=${3} # space seperated list
fi

bitbucket_admin_group="bitbucket-sys-admins"
bitbucket_url="https://git-unisource.md-man.biz:7990"
ci_user="c2440bm1"

curl_PUT_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X PUT"
curl_POST_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json"
#bitbucket_admin_user="admin"
#bitbucket_admin_password="password"
#curl_PUT_cmd="curl --fail -D- --insecure -u ${bitbucket_admin_user}:${bitbucket_admin_password} -X PUT"
#curl_POST_cmd="curl --fail -D- --insecure -u ${bitbucket_admin_user}:${bitbucket_admin_password} -X POST -H Content-Type:application/json"


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
    local _bitbucket_project=$1
    local _repo_name=$2
    local _push_type=$3
    ${curl_POST_cmd} ${bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos -d "{ \"name\":\"${_repo_name}\", \"forkable\":false }"

    ${curl_PUT_cmd} ${bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name}/settings/hooks/com.atlassian.bitbucket.server.bitbucket-bundled-hooks:force-push-hook/enabled

    # Fill repo with an empty
    if [ -d ${_repo_name} ]; then
        cd ${_repo_name}
        if [ "${_push_type}X" == "--mirrorX" ]; then
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


for repo_name in $(echo ${repo_names} | sed -e 's/,/ /g'); do
  set +x
  echo "#################################################################"
  echo " START: $repo_name "
  echo "#################################################################"
  set -x
  # create_repo ${bitbucket_project} ${repo_name} "--mirror"

  create_permission_set_restricted_groups "heads/*" "$bitbucket_admin_group" $bitbucket_project $repo_name   # only admin creates new 'root' branches and 'name-spaces'

  create_permission_set_restricted "heads/**/master"  ${ci_user} $bitbucket_project $repo_name
  create_permission_set_restricted "heads/**/stable"  $ci_user $bitbucket_project $repo_name
  create_permission_set_restricted "heads/**/release" $ci_user $bitbucket_project $repo_name
  create_permission_set_restricted "tags/**"          $ci_user $bitbucket_project $repo_name

  create_permission_set_rewrite_history "heads/**/ready/*" "" $bitbucket_project $repo_name
  create_permission_set_rewrite_history "heads/**/dev/*" "" $bitbucket_project $repo_name
  create_permission_set_rewrite_history_deletion "heads/**/feature/*" $bitbucket_admin_group $bitbucket_project $repo_name
  set +x
  echo "#################################################################"
  echo " DONE: $repo_name "
  echo "#################################################################"
  set -x
done
