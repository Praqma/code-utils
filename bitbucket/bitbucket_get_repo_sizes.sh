#!/usr/bin/env bash

set -e
set -u
[[ "${debug:-}" == "true" ]] && set -x

[[ "${1:-}" == "" ]] && echo "Please set the server URL as param 1" && exit 1
[[ "${2:-}" == "" ]] && echo "Please set netrc file as param 3"  && exit 1

set -euo pipefail

url=${1}
netrc_file=${2}
[[ -f "${netrc_file}" ]] || { echo "Netrc file: ${netrc_file} does not exist"  && exit 1; }
limit=100000

printf "%-60s : %-20s : %-10s : %-10s : %-5s : %-5s %s\n"  "project/repo-path" "bytes" "mbytes" "gbytes" "LFS" "repo-id" "repo-URL"
IFS=$'\r\n'
for bitbucket_project in $(curl --fail --silent --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/rest/api/1.0/projects?limit=${limit} | jq -r .values[].key ); do
  for slug in $(curl --fail --silent --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/rest/api/1.0/projects/${bitbucket_project}/repos?limit=${limit} | jq -r .values[].slug ); do
    repo_id=$(curl --fail --silent --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/rest/api/1.0/projects/${bitbucket_project}/repos/${slug} | jq .id )
    repo_url=${url}/projects/${bitbucket_project}/repos/${slug}
    size_bytes=$(curl --fail --silent --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/projects/${bitbucket_project}/repos/${slug}/sizes | jq -r .repository)
    size_mb=$(awk '{printf "%d", $1/$2/$2}' <<< "$size_bytes 1024" )
    size_gb=$(awk '{printf "%d", $1/$2/$2/$2}' <<< "$size_bytes 1024" )

    _lfs_exit_code=0
    lfs_output=$(curl --fail --insecure --netrc-file ~/admin.netrc -X GET -H Content-Type:application/json -o - --url ${url}/rest/git-lfs/admin/projects/${bitbucket_project}/repos/${slug}/enabled 2>&1) ||  _lfs_exit_code=$?
    lfs_status="-"
    if [[ ${_lfs_exit_code} -eq 0 ]]; then
      lfs_status="+"
    fi
    unset _lfs_exit_code
    printf "%-60s : %-20s : %-10s : %-10s : %-5s : %-5s : %s\n"  "${bitbucket_project}/repos/$slug" "${size_bytes}" "${size_mb}" "${size_gb}" "${lfs_status}" "${repo_id}" "${repo_url}"
  done
done
