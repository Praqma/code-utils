#!/usr/bin/env bash
# Source step: Commit results and push tag

set -euo pipefail
set -x
trigger_sha="${GITHUB_SHA:-$(git rev-parse HEAD)}"
workflow_slug=$(printf '%s' "${GITHUB_WORKFLOW:-workflow}" | tr '[:space:]/' '--' | tr -cd '[:alnum:]_.-')

git_cmd="git -c user.name=actions-${workflow_slug} -c user.email=actions@${workflow_slug}"

tag_name="${workflow_slug}/${GITHUB_RUN_ID:-manual}"
${git_cmd} add --force results/
if ! ${git_cmd} diff --cached --quiet; then
  ${git_cmd} commit -m "results: ${tag_name}"
else
  echo "No result changes to commit; skipping commit and tag creation."
  exit 1
fi

${git_cmd} tag -a -m "${tag_name}" "${tag_name}"
${git_cmd} -c http.extraHeader="Authorization: Bearer ${BITBUCKET_TOKEN}" push origin "refs/tags/${tag_name}"

${git_cmd} tag -d "${tag_name}"
${git_cmd} reset --mixed "${trigger_sha}"
