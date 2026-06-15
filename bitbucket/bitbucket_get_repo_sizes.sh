#!/usr/bin/env bash

set -euo pipefail

[[ "${debug:-}" == "true" ]] && set -x

usage() {
  cat << EOF
Usage: $0 -u <server_url> -n <netrc_file> [-a]

Options:
  -u  Server URL (required)
  -n  Netrc file path (required)
  -a  Enable admin usage (optional, for LFS and size info)
  -h  Display this help message
EOF
  exit 1
}

admin_usage="false"

while getopts "u:n:ah" opt; do
  case $opt in
    u) url="$OPTARG" ;;
    n) netrc_file="$OPTARG" ;;
    a) admin_usage="true" ;;
    h) usage ;;
    *) usage ;;
  esac
done

[[ -z "${url:-}" ]] && echo "Error: Server URL is required (-u)" && usage
[[ -z "${netrc_file:-}" ]] && echo "Error: Netrc file is required (-n)" && usage

command -v jq > /dev/null || { echo "jq is not installed - run apt install jq" && exit 1; }

url=${1}
netrc_file=${2}
[[ -f "${netrc_file}" ]] || { echo "Netrc file: ${netrc_file} does not exist"  && exit 1; }
limit=100000

output_file_name="${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).projects.repos.txt"
output_server_size_filename="${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).projects.repos.size.txt"
echo "output_file_name : ${WORKSPACE:-.}/${output_file_name}"

rm -rf ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1)*.*

printf "%-60s : %-10s : %-20s : %-10s : %-10s : %-5s : %-5s %s\n"  "project/repo-path" "status" "bytes" "mbytes" "gbytes" "LFS" "repo-id" "repo-URL"
printf "%-60s : %-10s : %-20s : %-10s : %-10s : %-5s : %-5s %s\n"  "project/repo-path" "status" "bytes" "mbytes" "gbytes" "LFS" "repo-id" "repo-URL" > $output_file_name

server_size_mb=0
projects_count=0
projects_slugs_counts=0
mapfile -t projects < <(curl --fail --silent --insecure --netrc-file "${netrc_file}" -X GET -H "Content-Type:application/json" -o - --url "${url}/rest/api/1.0/projects" | jq -r '.values[].key')
for bitbucket_project in "${projects[@]}"; do
  echo "Processing project: ${bitbucket_project}"
  project_size_mb=0
  projects_count=$(( ${projects_count:-0} + 1 ))
  mapfile -t slugs < <(curl --fail --silent --insecure --netrc-file "${netrc_file}" -X GET -H "Content-Type:application/json" -o - --url "${url}/rest/api/1.0/projects/${bitbucket_project}/repos" | jq -r '.values[].slug')
    
  for slug in "${slugs[@]}"; do
    repo_url=${url}/projects/${bitbucket_project}/repos/${slug}
    
    slugs_count=$(( ${slugs_count:-0} + 1 ))
    projects_slugs_counts=$(( ${projects_slugs_counts:-0} + 1 ))

    repo_id=$(curl --fail --silent --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/rest/api/1.0/projects/${bitbucket_project}/repos/${slug} | jq .id )
    _lfs_exit_code=0
    if [[ "${admin_usage}" == "true" ]]; then
        lfs_output=$(curl --fail --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/rest/git-lfs/admin/projects/${bitbucket_project}/repos/${slug}/enabled 2>&1) ||  _lfs_exit_code=$?
        lfs_status="-"
        if [[ ${_lfs_exit_code} -eq 0 ]]; then
          lfs_status="+"
        fi
    else
        lfs_status="?"
    fi
    repo_description=$(curl --fail --silent --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/rest/api/1.0/projects/${bitbucket_project}/repos/${slug} | jq .description )

    repo_archived_status=$(curl --fail --silent --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/rest/api/1.0/projects/${bitbucket_project}/repos/${slug} | jq .archived  )
    if [[ "${repo_archived_status}" == "true" ]]; then
      repo_status="archived"
    else
      repo_status="active"
    fi
    if [[ "${admin_usage}" == "true" ]]; then
        size_bytes=$(curl --fail --insecure --netrc-file ${netrc_file} -X GET -H Content-Type:application/json -o - --url ${url}/projects/${bitbucket_project}/repos/${slug}/sizes | jq -r .repository)
        size_mb="$(awk '{printf "%d", $1/$2/$2}' <<< "$size_bytes 1024" )"
        size_gb="$(awk '{printf "%d", $1/$2/$2/$2}' <<< "$size_bytes 1024" )"
        project_size_mb=$(( ${project_size_mb} + ${size_mb} )) 
    else
      size_mb="?"
      size_gb="?"
      project_size_mb=$(( ${project_size_mb} + 0 ))
    fi

    printf "%-60s : %-10s : %-20s : %-10s : %-10s : %-5s : %-5s : %s\n"  "${bitbucket_project}/repos/$slug" "${repo_status}" "${size_bytes:-?}" "${size_mb:-?}" "${size_gb:-?}" "${lfs_status}" "${repo_id}" "${repo_url} / ${repo_description}"
    printf "%-60s : %-10s : %-20s : %-10s : %-10s : %-5s : %-5s : %s\n"  "${bitbucket_project}/repos/$slug" "${repo_status}" "${size_bytes:-?}" "${size_mb:-?}" "${size_gb:-?}" "${lfs_status}" "${repo_id}" "${repo_url} / ${repo_description}" >> $output_file_name
    printf "${bitbucket_project}/$slug\n" >> ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).${bitbucket_project}.repos.txt
    unset _lfs_exit_code
  done
  printf "Project count/size(MB): ${bitbucket_project} : ${slugs_count:-0} / ~${project_size_mb:-0} MB\n\n" >> ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).${bitbucket_project}.repos.txt
  server_size_mb=$(( ${server_size_mb:-0} + ${project_size_mb:-0} ))
  unset slugs_count
done
printf "Projects-count/repos-count/size(MB):: ${projects_count:-0} / ${projects_slugs_counts:-0} / ~${server_size_mb:-0} MB\n" > ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).size.mb.txt
cat ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).size.mb.txt

cat ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).*.repos.txt

