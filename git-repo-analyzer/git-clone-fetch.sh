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

function fetch_me {
  [[ ${repo_fetch:-} == "true" ]] || {
    echo "INFO: repo_fetch is not set to true, skipping fetch for $git_repo"
    return 0
  }
  git \
    -c http.extraHeader="Authorization: Bearer ${BITBUCKET_TOKEN}" \
      -C "$repo_full_dir" fetch origin \
        -apP \
        --force
}

while IFS= read -r git_repo; do
  [ -z "$git_repo" ] && continue
  repo_name=$(basename "$git_repo" .git)
  repo_full_dir="$git_base_dir/$repo_name"
  echo "Processing repository: $git_repo"

  if git -C "$repo_full_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fetch_me
  else
    echo "Sparse checkout of repository: $git_repo"
    rm -rf "$repo_full_dir"
    git \
        -c http.extraHeader="Authorization: Bearer ${BITBUCKET_TOKEN}" \
         clone \
          --tags \
          --sparse \
          "$git_repo" "$repo_full_dir"
  fi
done < <(printf '%s\n' "$PROJECT_LIST" | tr ',' '\n')
