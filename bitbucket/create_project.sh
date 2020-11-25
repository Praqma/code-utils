#!/usr/bin/env bash

set -e
set -x
set -u

bitbucket_admin_user=cls
bitbucket_admin_password=Start2016
bitbucket_url=http://dev.napatech.com/bitbucket
bitbucket_ssh_url=ssh://git@dev.napatech.com:7999
ci_user=jenkins_local

function generate_restriction_json {
    local _restriction_type=$1
    local _restriction_pattern=$2
    local _restriction_type=$3

    if [ "${3}x" == "x" ] ; then
        echo "{ \
            \"id\": 1,    \
            \"type\": \"$1\",    \
            \"matcher\":     {        \
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
            \"matcher\":     {        \
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

function push_masters {
    local _bitbucket_project=$1
    local _repo_name=$2
    local _branch=$3
    git push ${bitbucket_ssh_url}/${_bitbucket_project}/${_repo_name}.git ${_branch}master
sleep 3 # due to ssh / firewall restrictions
    git push ${bitbucket_ssh_url}/${_bitbucket_project}/${_repo_name}.git ${_branch}stable
sleep 3 # due to ssh / firewall restrictions
    git push ${bitbucket_ssh_url}/${_bitbucket_project}/${_repo_name}.git ${_branch}release
sleep 3 # due to ssh / firewall restrictions
}

function push_devs {
    local _bitbucket_project=$1
    local _repo_name=$2
    local _branch=$3
sleep 3 # due to ssh / firewall restrictions
    git push ${bitbucket_ssh_url}/${_bitbucket_project}/${_repo_name}.git ${_branch}
}

function create_repo {
    local _bitbucket_project=$1
    local _repo_name=$2
    curl --fail -D- -u ${bitbucket_admin_user}:${bitbucket_admin_password} -X POST -H "Content-Type: application/json" ${bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos -d "{ \"name\":\"${_repo_name}\", \"forkable\":false }"

    curl --fail -D- -u ${bitbucket_admin_user}:${bitbucket_admin_password} -X PUT   ${bitbucket_url}/rest/api/1.0/projects/${_bitbucket_project}/repos/${_repo_name}/settings/hooks/com.atlassian.bitbucket.server.bitbucket-bundled-hooks:force-push-hook/enabled

    # Fill repo with an empty
    if [ -d ${_repo_name} ]; then
        cd ${_repo_name}
        
        master_branches=" 
  origin/2.0.1:refs/heads/Pandion-v2.0.x/
  origin/QRadar-v2.0.0:refs/heads/QRadar-v2.0.x/
  origin/master:refs/heads/
  origin/AM-nt80e3-2_in_pandion_poc:refs/heads/poc_AM-nt80e3-2_in_pandion/
  origin/customer-application-poc:refs/heads/poc_customer-application/
"
#  origin/multithreaded_searcher:refs/heads/multithreaded_searcher/ # To be terminated
# gerrit/IBM-v2.0.0:refs/heads/IBM-v2.0.0/ # tag i Gerrit og nedlæg branch
# DELETE  gerrit/rmt_34688:refs/heads/dev/rmt_34688 

        for branch in `echo "${master_branches}"` ; do 
	  push_masters ${_bitbucket_project} ${_repo_name} ${branch}
	done

 dev_branches="
  origin/HMJ-facebook-poc:refs/heads/dev/HMJ-facebook-poc
  origin/HMJ-parallel-writertest:refs/heads/dev/HMJ-parallel-writertest
  origin/HMJ-pool-writers:refs/heads/dev/HMJ-pool-writers
  origin/HMJ-writer-timing-for-nsv:refs/heads/dev/HMJ-writer-timing-for-nsv
  origin/multithreaded_searcher2:refs/heads/dev/multithreaded_searcher2
  origin/pandion-facebook:refs/heads/dev/pandion-facebook
  origin/pandion-facebook-reviewed:refs/heads/dev/pandion-facebook-reviewed
"
#   origin/LJE_IBM_Licenses_in_frontend_rpm:refs/heads/dev/LJE_IBM_Licenses_in_frontend_rpm
#   origin/LJE_PandionContainer:refs/heads/dev/LJE_PandionContainer
#  origin/PAL-dpdkstats:refs/heads/dev/PAL-dpdkstats
#  origin/PAL-dpdkstats2:refs/heads/dev/PAL-dpdkstats2
#  origin/PAL-rhel7:refs/heads/dev/PAL-rhel7
#  origin/jln_rmt34719:refs/heads/dev/jln_rmt34719
#  origin/lje_rmt34719:refs/heads/dev/lje_rmt34719

        for branch in `echo "${dev_branches}"` ; do 
	  push_devs ${_bitbucket_project} ${_repo_name} ${branch}
	done

	for branch in `git branch -a | grep gerrit | sed -e 's/ remotes\/gerrit\///g' | awk -F " " '{print $1}'` ; do
	  git tag -f -a -m "Original branch head from Gerrit: $branch" gerrit_${branch} 
	done

	git push ${bitbucket_ssh_url}/${_bitbucket_project}/${_repo_name}.git --tags


        cd -
    fi
}

bitbucket_project="ASW"
repo_name="hest"

create_repo $bitbucket_project $repo_name
    create_permission_set_restricted "heads/*"   $bitbucket_admin_user $bitbucket_project $repo_name   # only admin creates new 'root' branches and 'name-spaces'

    create_permission_set_restricted "heads/**/master"  $ci_user $bitbucket_project $repo_name
    create_permission_set_restricted "heads/**/stable"  $ci_user $bitbucket_project $repo_name
    create_permission_set_restricted "heads/**/release" $ci_user $bitbucket_project $repo_name
    create_permission_set_restricted "tags/**"          $ci_user $bitbucket_project $repo_name

    create_permission_set_semi-restricted "heads/**/ready/*" "" $bitbucket_project $repo_name


