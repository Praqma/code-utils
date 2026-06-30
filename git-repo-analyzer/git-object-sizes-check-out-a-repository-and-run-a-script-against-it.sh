#!/usr/bin/env bash
# Source step: Check out a repository and run a script against it

#set -x
root=$(pwd)
exit_code=0
git_base_dir=${git_base_dir:-$(pwd)}
mkdir -p "$git_base_dir"

if [[ -z "${BITBUCKET_TOKEN:-}" ]]; then
  echo "[ERROR] BITBUCKET_TOKEN is not set"
  exit 1
fi

if [[ -z "${PROJECT_LIST:-}" ]]; then
  echo "[ERROR] PROJECT_LIST is not set"
  exit 1
fi

git lfs --version || true
git --version || true
python3 --version || true

while IFS= read -r git_repo; do
  [ -z "$git_repo" ] && continue
  repo_name=$(basename "$git_repo" .git)
  repo_full_dir="$git_base_dir/$repo_name"
  echo "Processing repository: $git_repo"

  if git -C "$repo_full_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git \
        -c http.extraHeader="Authorization: Bearer ${BITBUCKET_TOKEN}" \
         -C "$repo_full_dir" fetch origin --recurse-submodules
  else
    git \
        -c http.extraHeader="Authorization: Bearer ${BITBUCKET_TOKEN}" \
         clone --recurse-submodules "$git_repo" "$repo_full_dir"
  fi
done < <(printf '%s\n' "$PROJECT_LIST" | tr ',' '\n')
