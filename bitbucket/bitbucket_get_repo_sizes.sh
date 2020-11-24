#!/usr/bin/env bash

set -e
set -u
[[ "${debug:-}" == "true" ]] && set -x

[[ "${1:-}" == "" ]] && echo "Please set the server URL as param 1" && exit 1
[[ "${2:-}" == "" ]] && echo "Please set bitbucket_project as param 2"  && exit 1

url=${1}
bitbucket_project=${2}

printf "%-40s : %-20s : %-10s : %-5s\n"  "repository" "bytes" "mbytes" "gbytes"
IFS=$'\r\n'
for slug in $(curl --fail --silent --insecure --netrc-file ~/admin.netrc -X GET -H Content-Type:application/json -o - --url ${url}/rest/api/1.0/projects/${bitbucket_project}/repos?limit=100000 | jq -r .values[].slug ); do
  size_bytes=$(curl --fail --silent --insecure --netrc-file ~/admin.netrc -X GET -H Content-Type:application/json -o - --url ${url}/projects/${bitbucket_project}/repos/${slug}/sizes | jq -r .repository)
  size_mb=$(awk '{printf "%d", $1/$2/$2}' <<< "$size_bytes 1024" )
  size_gb=$(awk '{printf "%d", $1/$2/$2/$2}' <<< "$size_bytes 1024" )
  printf "%-40s : %-20s : %-10s : %-5s\n"  "$slug" "${size_bytes}" "${size_mb}" "${size_gb}"
done

