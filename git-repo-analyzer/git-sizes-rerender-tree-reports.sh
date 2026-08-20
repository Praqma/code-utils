#!/usr/bin/env bash
# Rebuild existing Git size tree reports without rerunning repository analysis.

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
renderer="$script_dir/git-object-sizes-tree-render.py"
totals_name="bigtosmall_sorted_size_total_final.txt"
html_name="git_sizes_tree.html"
overview_html_name="overview.html"
default_results_dir="${RESULTS_DIR:-${PWD}}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [report-directory|$totals_name]

Without an argument, rerenders existing reports below:
  $default_results_dir

With an argument, rerenders only that report directory or totals input file.
Source analysis is never rerun.
EOF
}

rerender_report() {
  local totals_file=$1
  local output_file
  output_file="$(dirname -- "$totals_file")/$html_name"

  GIT_ANALYST_SKIP_LOGS=1 python3 "$renderer" "$totals_file" "$output_file"

}

if [[ ! -f "$renderer" ]]; then
  printf 'Renderer not found: %s\n' "$renderer" >&2
  exit 1
fi

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  target=$1
  if [[ -d "$target" ]]; then
    rerender_report "$target/$totals_name"
  elif [[ -f "$target" && "$(basename -- "$target")" == "$totals_name" ]]; then
    rerender_report "$target"
  else
    printf 'Expected a report directory or %s: %s\n' "$totals_name" "$target" >&2
    exit 2
  fi
  exit 0
fi

if [[ ! -d "$default_results_dir" ]]; then
  printf 'Results directory not found: %s\n' "$default_results_dir" >&2
  exit 1
fi

processed=0
skipped=0
for report_dir in "$default_results_dir"/*; do
  [[ -d "$report_dir" ]] || continue
  totals_file="$report_dir/$totals_name"
  if [[ -f "$totals_file" ]]; then
    rerender_report "$totals_file"
    ((processed += 1))
  else
    ((skipped += 1))
  fi
done

printf 'Rerendered: %d; skipped: %d\n' "$processed" "$skipped"

if [[ $processed -gt 0 ]]; then
  overview_file="$default_results_dir/$overview_html_name"
  python3 "$renderer" "$overview_file" "$(dirname -- "$overview_file")/$overview_html_name"
fi
