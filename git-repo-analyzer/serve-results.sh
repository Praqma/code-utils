#!/usr/bin/env bash
# Serve the git-repo-analyzer results directory (overview.html) over HTTP.

set -euo pipefail

port="${1:-${PORT:-8000}}"
results_dir="${RESULTS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../results/orig" && pwd)}"

if [[ ! -d "$results_dir" ]]; then
  printf 'Results directory not found: %s\n' "$results_dir" >&2
  exit 1
fi

if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
  exec 3>&-
  printf 'Port %s is already in use on 127.0.0.1. Pass a different port, e.g.: %s %s\n' \
    "$port" "$(basename -- "$0")" "$((port + 1))" >&2
  exit 1
fi

cd "$results_dir"
printf 'Serving %s at http://127.0.0.1:%s/overview.html\n' "$results_dir" "$port"
exec python3 -m http.server "$port" --bind 127.0.0.1
