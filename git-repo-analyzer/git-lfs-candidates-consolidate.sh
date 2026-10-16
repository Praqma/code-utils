#!/usr/bin/env bash

# AI skills usage:
#   Consolidate every per-repo git_lfs_candidates.txt under a results folder into one org-wide list.
#   Example:
#   ./git-lfs-candidates-consolidate.sh results/orig

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
results_dir="${1:-${RESULTS_DIR:-$(cd -- "${script_dir}/../../results/orig" && pwd)}}"

[[ -d "${results_dir}" ]] || {
  echo "ERROR: results dir not found: ${results_dir}" >&2
  exit 1
}

file_output_overview="${results_dir}/git_lfs_candidates_overview.txt"
file_output_by_repo="${results_dir}/git_lfs_candidates_by_repo.txt"

# Generated content is untrusted, so parse key='value' instead of sourcing it.
function read_candidate_var () {
  local file="$1" key="$2" line value
  line=$(grep -m 1 "^${key}=" "${file}" 2>/dev/null || true)
  [[ -n "${line}" ]] || return 0
  value="${line#*=}"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "${value}"
}

declare -A ext_state
repo_count=0
: > "${file_output_by_repo}"

for candidates_file in "${results_dir}"/*/git_lfs_candidates.txt; do
  [[ -f "${candidates_file}" ]] || continue

  repo_dir="$(dirname -- "${candidates_file}")"
  repo="$(basename -- "${repo_dir}")"

  red=$(read_candidate_var "${candidates_file}" git_lfs_candidates)
  yellow=$(read_candidate_var "${candidates_file}" git_lfs_mixed)

  repo_count=$(( repo_count + 1 ))
  printf '%s\t%s\t%s\n' "${repo}" "${red}" "${yellow}" >> "${file_output_by_repo}"

  IFS=',' read -r -a red_patterns <<< "${red}"
  for pattern in "${red_patterns[@]}"; do
    [[ -n "${pattern}" ]] || continue
    [[ -n "${ext_state[${pattern}]:-}" ]] || ext_state["${pattern}"]="red"
  done

  # An extension that is text in any repo must not be auto-migrated, so yellow always wins.
  IFS=',' read -r -a yellow_patterns <<< "${yellow}"
  for pattern in "${yellow_patterns[@]}"; do
    [[ -n "${pattern}" ]] || continue
    ext_state["${pattern}"]="yellow"
  done
done

red_list=""
yellow_list=""
if (( ${#ext_state[@]} > 0 )); then
  # Keys are globs like *.exe, so read them line-wise to keep pathname expansion out of it.
  while IFS= read -r pattern; do
    [[ -n "${pattern}" ]] || continue
    if [[ "${ext_state[${pattern}]}" == "red" ]]; then
      red_list="${red_list:+${red_list},}${pattern}"
    else
      yellow_list="${yellow_list:+${yellow_list},}${pattern}"
    fi
  done < <(printf '%s\n' "${!ext_state[@]}" | sort)
fi

cat << EOF > "${file_output_overview}"
git_lfs_candidates='${red_list}'
git_lfs_mixed='${yellow_list}'
EOF

red_count=0
yellow_count=0
if [[ -n "${red_list}" ]]; then
  red_count=$(awk -F, '{print NF}' <<< "${red_list}")
fi
if [[ -n "${yellow_list}" ]]; then
  yellow_count=$(awk -F, '{print NF}' <<< "${yellow_list}")
fi

echo "Repos with candidates: ${repo_count}"
echo "Binary (LFS candidate) extensions: ${red_count}"
echo "Mixed (needs analysis) extensions: ${yellow_count}"
echo "Overview: ${file_output_overview}"
echo "Per repo: ${file_output_by_repo}"
