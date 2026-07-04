#!/usr/bin/env bash

set -euo pipefail

[[ "${debug:-}" == "true" ]] && set -x

usage() {
  cat << EOF
Usage: $0 -u <server_url> [-n <netrc_file>] [-l <page_limit>] [-a]

Options:
  -u  Server URL (required)
  -n  Netrc file path (optional, default: \$HOME/.netrc)
  -l  Page limit for Bitbucket paged endpoints (optional, default: 1000)
  -a  Enable admin usage (optional, for LFS and size info)
  -h  Display this help message

Environment variables:
  BITBUCKET_COOKIE_HEADER  Optional full Cookie header value to use for requests
  BITBUCKET_COOKIE_JAR     Optional cookie jar file path to use with curl -b
  STDOUT_LOG_FILE          Optional log file path for capturing script stdout
EOF
  exit "${1:-1}"
}

admin_usage="false"
limit="1000"

while getopts "u:n:l:ah" opt; do
  case $opt in
    u) url="$OPTARG" ;;
    n) netrc_file="$OPTARG" ;;
    l) limit="$OPTARG" ;;
    a) admin_usage="true" ;;
    h) usage 0 ;;
    *) usage ;;
  esac
done

shift $((OPTIND - 1))

netrc_file="${netrc_file:-$HOME/.netrc}"

[[ -z "${url:-}" ]] && echo "Error: Server URL is required (-u)" && usage

# Accept either a full URL or a bare host.
if [[ "${url}" != http://* && "${url}" != https://* ]]; then
  url="https://${url}"
fi

command -v jq > /dev/null || { echo "jq is not installed - run apt install jq" && exit 1; }
[[ "${limit}" =~ ^[0-9]+$ ]] || { echo "Error: -l <page_limit> must be a positive integer" && exit 1; }
[[ "${limit}" -gt 0 ]] || { echo "Error: -l <page_limit> must be greater than 0" && exit 1; }

curl_common_args=(
  --silent
  --insecure
  -X GET
  -H "Content-Type:application/json"
  -H "Accept: application/json"
)

if [[ -n "${BITBUCKET_COOKIE_HEADER:-}" ]]; then
  curl_common_args+=( -H "Cookie: ${BITBUCKET_COOKIE_HEADER}" )
elif [[ -n "${BITBUCKET_COOKIE_JAR:-}" ]]; then
  [[ -f "${BITBUCKET_COOKIE_JAR}" ]] || { echo "Cookie jar does not exist: ${BITBUCKET_COOKIE_JAR}" && exit 1; }
  curl_common_args+=( -b "${BITBUCKET_COOKIE_JAR}" )
else
  [[ -f "${netrc_file}" ]] || { echo "Netrc file does not exist: ${netrc_file}" && exit 1; }
  curl_common_args+=( --netrc-file "${netrc_file}" )
fi

fetch_paged_values() {
  local endpoint="$1"
  local value_selector="$2"
  local start="0"

  while true; do
    local response
    response="$(curl --fail "${curl_common_args[@]}" -o - --url "${url}${endpoint}?limit=${limit}&start=${start}")"

    jq -r "${value_selector}" <<< "${response}"

    local is_last_page
    is_last_page="$(jq -r '.isLastPage // true' <<< "${response}")"
    [[ "${is_last_page}" == "true" ]] && break

    local next_page_start
    next_page_start="$(jq -r '.nextPageStart // empty' <<< "${response}")"
    [[ -z "${next_page_start}" ]] && break
    start="${next_page_start}"
  done
}

rm -rf ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1)*.*

stdout_log_file="${STDOUT_LOG_FILE:-${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).projects.repos.txt}"
stdout_log_dir="$(dirname "${stdout_log_file}")"

echo "stdout_log_file : ${stdout_log_file}"

mkdir -p "${stdout_log_dir}"
touch "${stdout_log_file}"

# Capture stdout in a file while still printing to terminal.
exec > >(tee -a "${stdout_log_file}")

printf "%-60s : %-10s : %-20s : %-10s : %-10s : %-5s : %-5s %s\n"  "project/repo-path" "status" "bytes" "mbytes" "gbytes" "LFS" "repo-id" "repo-URL"

server_size_mb=0
projects_count=0
projects_slugs_counts=0
size_check_enabled="true"
lfs_check_enabled="true"
mapfile -t projects < <(curl --fail "${curl_common_args[@]}" -o - --url "${url}/rest/api/1.0/projects" | jq -r '.values[].key')
for bitbucket_project in "${projects[@]}"; do
  echo "Processing project: ${bitbucket_project}"
  project_size_mb=0
  projects_count=$(( ${projects_count:-0} + 1 ))
  mapfile -t slugs < <(fetch_paged_values "/rest/api/1.0/projects/${bitbucket_project}/repos" '.values[].slug')
    
  for slug in "${slugs[@]}"; do
    repo_url=${url}/projects/${bitbucket_project}/repos/${slug}
    
    slugs_count=$(( ${slugs_count:-0} + 1 ))
    projects_slugs_counts=$(( ${projects_slugs_counts:-0} + 1 ))

    repo_details="$(curl --fail "${curl_common_args[@]}" -o - --url "${url}/rest/api/1.0/projects/${bitbucket_project}/repos/${slug}")"
    repo_id="$(jq .id <<< "${repo_details}")"
    if [[ "${admin_usage}" == "true" ]]; then
        if [[ "${lfs_check_enabled}" == "true" ]]; then
          lfs_http_code="$(curl "${curl_common_args[@]}" -o /tmp/bitbucket_lfs_enabled.$$ -w "%{http_code}" --url "${url}/rest/git-lfs/admin/projects/${bitbucket_project}/repos/${slug}/enabled" || true)"
          if [[ "${lfs_http_code}" == "401" ]]; then
            lfs_check_enabled="false"
            lfs_status="?"
            echo "Warning: Received HTTP 401 on LFS endpoint; disabling LFS checks for the rest of this run."
          elif [[ "${lfs_http_code}" == "200" ]]; then
            lfs_status="+"
          else
            lfs_status="-"
          fi
        else
          lfs_status="?"
        fi
    else
        lfs_status="?"
    fi
    repo_description="$(jq .description <<< "${repo_details}")"

    repo_archived_status="$(jq .archived <<< "${repo_details}")"
    if [[ "${repo_archived_status}" == "true" ]]; then
      repo_status="archived"
    else
      repo_status="active"
    fi
    if [[ "${admin_usage}" == "true" ]]; then
        if [[ "${size_check_enabled}" == "true" ]]; then
          size_http_code="$(curl "${curl_common_args[@]}" -o /tmp/bitbucket_repo_sizes.$$ -w "%{http_code}" --url "${url}/projects/${bitbucket_project}/repos/${slug}/sizes/" || true)"
          if [[ "${size_http_code}" == "401" ]]; then
            size_check_enabled="false"
            size_bytes=""
            echo "Warning: Received HTTP 401 on repository size endpoint; disabling size checks for the rest of this run."
          elif [[ "${size_http_code}" == "200" ]]; then
            size_bytes="$(jq -r '.repository // empty' /tmp/bitbucket_repo_sizes.$$)"
          else
            size_bytes=""
          fi
        else
          size_bytes=""
        fi
        if [[ -n "${size_bytes}" ]]; then
          size_mb="$(awk '{printf "%d", $1/$2/$2}' <<< "$size_bytes 1024" )"
          size_gb="$(awk '{printf "%d", $1/$2/$2/$2}' <<< "$size_bytes 1024" )"
          project_size_mb=$(( ${project_size_mb} + ${size_mb} ))
        else
          size_bytes="?"
          size_mb="?"
          size_gb="?"
          project_size_mb=$(( ${project_size_mb} + 0 ))
        fi
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

