#!/usr/bin/env bash
# Source step: Run a script against repos

set -x
root=$(pwd)
exit_code=0
git_base_dir=/home/brew/runner-workspace
mkdir -p "$git_base_dir"
output_dir_base="$root/results/orig"
mkdir -p "$output_dir_base"

export GIT_FILETYPES="$root/scripts/git-workspace-file-type-analyzer.sh"
export GIT_SIZE="$root/scripts/git-object-sizes-in-repo-analyzer.sh"

while IFS= read -r git_repo; do
  [ -z "$git_repo" ] && continue
  repo_name=$(basename "$git_repo" .git)
  repo_full_dir="$git_base_dir/$repo_name"

  output_dir="$output_dir_base/$repo_name"
  mkdir -p "$output_dir"

  git -C "$repo_full_dir" log -1 > /dev/null || {
    exit_code=$?
    if [[ $exit_code -ne 128 ]]; then
      echo "[ERROR] unknown error executing 'git log' in $git_repo: git exited with code $exit_code"
    fi
    echo "[WARNING] likely empty git repo: $git_repo"
    (
      echo "git_size_total=0"
      echo "git_size_objects=0"
      echo "git_size_pack=0"
      echo "git_size_lfs=0"
      echo "git_size_modules=0"
      echo "git_verdict=empty"
    ) > "$output_dir/git_sizes.txt"
    continue;
  }
  pushd "$output_dir"
  # "$GIT_FILETYPES" "$repo_full_dir" > results_filetypes.txt
  repack=false "$GIT_SIZE" "$repo_full_dir"
  popd

done < <(printf '%s\n' "$PROJECT_LIST" | tr ',' '\n')
python3 generate_overview.py ${output_dir_base} ${output_dir_base}/overview.html
if [[ $exit_code -eq 128 ]]; then
  echo "::warning::One or more repositories failed to process. Most likely cause: empty repository. Please check the logs for details."
  exit 0
fi
exit ${exit_code}
