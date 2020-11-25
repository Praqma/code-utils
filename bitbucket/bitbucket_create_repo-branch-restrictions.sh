#!/usr/bin/env bash

set -e
[[ ${debug:-} == "true" ]] && set -x
set -u

if [[ "${1}X" == "X" ]] ; then
  echo "Please parse bitbucket_project as parameter 1"
  exit 1
else
  bitbucket_project=${1} # space seperated list
fi


if [[ "${2}X" == "X" ]] ; then
  echo "Please parse repo_names as parameter 2 as space separated list"
  exit 1
else
  repo_names="${2}" # space seperated list
fi

if [[ "${3:-}" == "" ]] ; then
  echo "Please parse netrc_file as parameter 3"
  exit 1
else
  netrc_file=${3}
fi

if [[ "${4}X" == "X" ]] ; then
  echo "Please parse bitbucket_url as parameter 4"
  exit 1
else
    bitbucket_url="${4}"
fi

if [[ "${5}X" == "X" ]] ; then
  echo "Please parse ci_user as parameter 5 for branch permissions if needed"
else
  ci_user="${5:-}"
fi

bitbucket_admin_group="bitbucket_admins"

curl_PUT_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X PUT"
curl_DELETE_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X DELETE"
curl_POST_cmd="curl --fail -D- --insecure --netrc-file ${netrc_file} -X POST -H Content-Type:application/json"
#bitbucket_admin_user="admin"
#bitbucket_admin_password="password"
#curl_PUT_cmd="curl --fail -D- --insecure -u ${bitbucket_admin_user}:${bitbucket_admin_password} -X PUT"
#curl_POST_cmd="curl --fail -D- --insecure -u ${bitbucket_admin_user}:${bitbucket_admin_password} -X POST -H Content-Type:application/json"

source ${BASH_SOURCE%/*}/_bitbucket_repo_functions.sh || source ./_bitbucket_repo_functions.sh

for repo_name in $(echo ${repo_names} | sed -e 's/,/ /g'); do
  echo "#################################################################"
  echo " START: $repo_name "
  echo "#################################################################"
  create_repo ${bitbucket_url} ${bitbucket_project} ${repo_name} "--mirror"
  repo_prereceive_force_push_hook_enable $repo_name $bitbucket_project

#  create_permission_set_restricted_groups "heads/*" "$bitbucket_admin_group" $bitbucket_project $repo_name   # only admin creates new 'root' branches and 'name-spaces'
#
#  create_permission_set_restricted "heads/**/master"  ${ci_user} $bitbucket_project $repo_name
#  create_permission_set_restricted "heads/**/stable"  $ci_user $bitbucket_project $repo_name
#  create_permission_set_restricted "heads/**/release" $ci_user $bitbucket_project $repo_name
#  create_permission_set_restricted "tags/**"          $ci_user $bitbucket_project $repo_name
#
#  create_permission_set_rewrite_history "heads/**/ready/*" "" $bitbucket_project $repo_name
#  create_permission_set_rewrite_history "heads/**/dev/*" "" $bitbucket_project $repo_name
#  create_permission_set_rewrite_history_deletion "heads/**/feature/*" $bitbucket_admin_group $bitbucket_project $repo_name
  echo "#################################################################"
  echo " DONE: $repo_name "
  echo "#################################################################"
done
