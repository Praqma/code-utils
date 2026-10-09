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
  BITBUCKET_AUTH_HEADER   Optional full authentication header for requests
  BITBUCKET_TOKEN          Optional HTTP access token sent as a Bearer token
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

if [[ -n "${BITBUCKET_AUTH_HEADER:-}" ]]; then
  curl_common_args+=( -H "${BITBUCKET_AUTH_HEADER}" )
elif [[ -n "${BITBUCKET_TOKEN:-}" ]]; then
  curl_common_args+=( -H "Authorization: Bearer ${BITBUCKET_TOKEN}" )
elif [[ -n "${BITBUCKET_COOKIE_HEADER:-}" ]]; then
  curl_common_args+=( -H "Cookie: ${BITBUCKET_COOKIE_HEADER}" )
elif [[ -n "${BITBUCKET_COOKIE_JAR:-}" ]]; then
  [[ -f "${BITBUCKET_COOKIE_JAR}" ]] || { echo "Cookie jar does not exist: ${BITBUCKET_COOKIE_JAR}" && exit 1; }
  curl_common_args+=( -b "${BITBUCKET_COOKIE_JAR}" )
else
  [[ -f "${netrc_file}" ]] || { echo "Netrc file does not exist: ${netrc_file}" && exit 1; }
  curl_common_args+=( --netrc-file "${netrc_file}" )
fi

submodule_tmp_dir="$(mktemp -d)"
trap 'rm -rf "${submodule_tmp_dir}"' EXIT

urlencode_path() {
  local path="$1"
  local component
  local encoded_path=""
  local separator=""
  local -a path_components

  IFS='/' read -r -a path_components <<< "${path}"
  for component in "${path_components[@]}"; do
    encoded_path+="${separator}$(jq -rn --arg value "${component}" '$value | @uri')"
    separator="/"
  done
  printf '%s' "${encoded_path}"
}

get_repo_submodules() {
  local project_key="$1"
  local repository_slug="$2"
  local at_ref="$3"
  local gitmodules_file="${submodule_tmp_dir}/gitmodules"
  local config_record
  local config_key
  local config_value
  local module_key
  local module_path
  local module_url
  local encoded_path
  local browse_url
  local browse_response="${submodule_tmp_dir}/browse"
  local root_browse_url="${url}/rest/api/1.0/projects/${project_key}/repos/${repository_slug}/browse"
  local config_records="${submodule_tmp_dir}/config-records"
  local module_type
  local http_code
  local config_status
  local separator=""
  local -a ref_args=()
  local -a module_entries=()
  local -A module_paths=()
  local -A module_urls=()

  ref_args=()
  [[ -n "${at_ref}" ]] && ref_args+=( --data-urlencode "at=${at_ref}" )
  http_code="$(curl "${curl_common_args[@]}" -H "Accept: text/plain" --get \
    "${ref_args[@]}" -o "${gitmodules_file}" -w "%{http_code}" \
    --url "${url}/rest/api/1.0/projects/${project_key}/repos/${repository_slug}/raw/.gitmodules" \
    || true)"
  if [[ "${http_code}" == "404" ]]; then
    http_code="$(curl "${curl_common_args[@]}" "${ref_args[@]}" --get \
      -o "${browse_response}" -w "%{http_code}" --url "${root_browse_url}" || true)"
    if [[ "${http_code}" == "200" ]]; then
      submodule_count=0
      submodule_list="null"
      return 0
    fi
    submodule_count="?"
    submodule_list="?"
    echo "Warning: Cannot determine submodules for ${project_key}/${repository_slug}: .gitmodules returned 404 and repository Browse access could not be confirmed (HTTP ${http_code:-unknown}); check effective REPO_READ permission and default branch." >&2
    return 0
  elif [[ "${http_code}" == "401" || "${http_code}" == "403" ]]; then
    submodule_count="?"
    submodule_list="?"
    echo "Warning: Cannot read submodules for ${project_key}/${repository_slug} (HTTP ${http_code}); check the Bearer token's effective REPO_READ permission." >&2
    return 0
  fi
  [[ "${http_code}" == "200" ]] || {
    echo "Error: Failed to fetch .gitmodules for ${project_key}/${repository_slug} (HTTP ${http_code:-unknown})" >&2
    return 1
  }

  command -v git > /dev/null || { echo "git is required to parse .gitmodules" >&2; return 1; }
  if git config --file "${gitmodules_file}" --null --get-regexp '^submodule\..*\.(path|url)$' > "${config_records}"; then
    :
  else
    config_status=$?
    if [[ "${config_status}" -ne 1 ]]; then
      echo "Error: Could not parse .gitmodules for ${project_key}/${repository_slug}" >&2
      return 1
    fi
  fi

  while IFS= read -r -d '' config_record; do
    config_key="${config_record%%$'\n'*}"
    config_value="${config_record#*$'\n'}"
    module_key="${config_key%.*}"
    case "${config_key##*.}" in
      path) module_paths["${module_key}"]="${config_value}" ;;
      url) module_urls["${module_key}"]="${config_value}" ;;
    esac
  done < "${config_records}"

  for module_key in "${!module_paths[@]}"; do
    module_path="${module_paths[${module_key}]}"
    module_url="${module_urls[${module_key}]:-}"
    [[ -n "${module_path}" && -n "${module_url}" ]] || continue

    encoded_path="$(urlencode_path "${module_path}")"
    browse_url="${url}/rest/api/1.0/projects/${project_key}/repos/${repository_slug}/browse/${encoded_path}"
    ref_args=()
    [[ -n "${at_ref}" ]] && ref_args+=( --data-urlencode "at=${at_ref}" )
    http_code="$(curl "${curl_common_args[@]}" "${ref_args[@]}" --get \
      --data-urlencode "type=true" -o "${browse_response}" -w "%{http_code}" \
      --url "${browse_url}" || true)"
    [[ "${http_code}" == "404" ]] && continue
    if [[ "${http_code}" != "200" ]]; then
      submodule_count="?"
      submodule_list="?"
      echo "Warning: Cannot verify submodule path '${module_path}' in ${project_key}/${repository_slug} (HTTP ${http_code:-unknown}); check effective REPO_READ permission." >&2
      return 0
    fi
    module_type="$(jq -r '.type // empty' "${browse_response}")"
    [[ "${module_type}" == "SUBMODULE" ]] || continue

    module_entries+=( "${module_url}" )
  done

  submodule_count="${#module_entries[@]}"
  submodule_list="null"
  if (( ${#module_entries[@]} > 0 )); then
    submodule_list=""
    for module_url in "${module_entries[@]}"; do
      submodule_list+="${separator}${module_url}"
      separator=", "
    done
  fi
}

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

printf "%-60s : %-10s : %-20s : %-10s : %-10s : %-5s : %-5s : %-10s : %s : %s\n"  "project/repo-path" "status" "bytes" "mbytes" "gbytes" "LFS" "repo-id" "submodules" "repo-URL" "submodule-urls"

server_size_mb=0
projects_count=0
projects_slugs_counts=0
size_check_enabled="true"
lfs_check_enabled="true"
mapfile -t projects < <(curl --fail "${curl_common_args[@]}" -o - --url "${url}/rest/api/1.0/projects" | jq -r '.values[].key')
for bitbucket_project in "${projects[@]}"; do
  project_size_mb=0
  projects_count=$(( ${projects_count:-0} + 1 ))
  mapfile -t slugs < <(fetch_paged_values "/rest/api/1.0/projects/${bitbucket_project}/repos" '.values[].slug')
    
  for slug in "${slugs[@]}"; do
    repo_url=${url}/projects/${bitbucket_project}/repos/${slug}
    
    slugs_count=$(( ${slugs_count:-0} + 1 ))
    projects_slugs_counts=$(( ${projects_slugs_counts:-0} + 1 ))

    repo_details="$(curl --fail "${curl_common_args[@]}" -o - --url "${url}/rest/api/1.0/projects/${bitbucket_project}/repos/${slug}")"
    repo_id="$(jq .id <<< "${repo_details}")"
    default_branch="$(jq -r 'if (.defaultBranch | type) == "object" then (.defaultBranch.id // .defaultBranch.displayId // empty) else (.defaultBranch // empty) end' <<< "${repo_details}")"
    get_repo_submodules "${bitbucket_project}" "${slug}" "${default_branch}"
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

    printf "%-60s : %-10s : %-20s : %-10s : %-10s : %-5s : %-5s : %-10s : %s : %s\n"  "${bitbucket_project}/repos/$slug" "${repo_status}" "${size_bytes:-?}" "${size_mb:-?}" "${size_gb:-?}" "${lfs_status}" "${repo_id}" "${submodule_count}" "${repo_url} / ${repo_description}" "${submodule_list}"
    printf "%-60s : %-10s : %-20s : %-10s : %-10s : %-5s : %-5s : %-10s : %s : %s\n"  "${bitbucket_project}/repos/$slug" "${repo_status}" "${size_bytes:-?}" "${size_mb:-?}" "${size_gb:-?}" "${lfs_status}" "${repo_id}" "${submodule_count}" "${repo_url} / ${repo_description}" "${submodule_list}" >> "${WORKSPACE:-.}/$(echo "${url}" | cut -d / -f 3 | cut -d : -f 1).${bitbucket_project}.repos.txt"
  done
  printf "Project count/size(MB): ${bitbucket_project} : ${slugs_count:-0} / ~${project_size_mb:-0} MB\n\n" >> ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).${bitbucket_project}.repos.txt
  server_size_mb=$(( ${server_size_mb:-0} + ${project_size_mb:-0} ))
  unset slugs_count
done
printf "Projects-count/repos-count/size(MB):: ${projects_count:-0} / ${projects_slugs_counts:-0} / ~${server_size_mb:-0} MB\n" > ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).size.mb.txt

#cat ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).size.mb.txt

#cat ${WORKSPACE:-.}/$(echo $url | cut -d / -f 3 | cut -d : -f 1).*.repos.txt

