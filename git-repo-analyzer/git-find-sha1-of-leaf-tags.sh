#!/bin/bash

set -eu -o pipefail

[[ ${debug:-} == true ]] && set -x

cd $1


declare -A leaf_sha1s
declare -A tags_by_sha1
leaf_sha1_count=0

while IFS=$'\t' read -r tag_ref tag_name; do
    sha1=$(git rev-parse "${tag_ref}^{commit}" 2>/dev/null || true)
    [[ -n "${sha1}" ]] || continue
    if [[ -n "${tags_by_sha1[${sha1}]:-}" ]]; then
        tags_by_sha1["${sha1}"]+=",${tag_name}"
    else
        tags_by_sha1["${sha1}"]="${tag_name}"
    fi
done < <(git for-each-ref --format='%(refname)%09%(refname:strip=2)' refs/tags)

mapfile -t sha1s < <(git rev-list --all --children | grep -E "^[a-f0-9]{40}$" | sort -u)
total_sha1s=${#sha1s[@]}
processed_sha1s=0
bar_width=40
show_progress=false
parent_command=$(ps -o args= -p "$PPID" 2>/dev/null || true)
if [[ ( -t 1 || -t 2 ) && "${parent_command}" != *.sh* ]]; then
    show_progress=true
fi

for sha1 in "${sha1s[@]}" ; do
    tags_of_sha1=${tags_by_sha1[${sha1}]:-}
    if [[ ${tags_of_sha1:-} != "" ]]; then
        tags_of_sha1=$(printf '%s\n' "$tags_of_sha1" | paste -sd ',' -)
        leaf_sha1s[$sha1]="${tags_of_sha1}"
        leaf_sha1_count=$((leaf_sha1_count + 1))
    fi

    if [[ ${show_progress} == true ]]; then
        processed_sha1s=$((processed_sha1s + 1))
        filled_width=$((bar_width * processed_sha1s / total_sha1s))
        bar=$(printf "%${filled_width}s" | tr ' ' '#')
        printf "\r[%-${bar_width}s] %3d%% (%d/%d)" \
            "$bar" "$((processed_sha1s * 100 / total_sha1s))" \
            "$processed_sha1s" "$total_sha1s" >&2
    fi
done
[[ ${show_progress} == true ]] && printf "\n" >&2

if [[ "${leaf_sha1_count}" -eq 0 ]]; then
    printf "No tagged leaf found\n" >&2
    exit 0
else
    printf "INFO: One or more tagged leaf-commit(s) found..\n" >&2
    {
    for sha1 in "${!leaf_sha1s[@]}"; do
        git log --abbrev=12 --oneline --format="%cs : %h : %<(50,mtrunc)%s : %d" "$sha1" -1
    done
    } | sort -h  
    exit 0
fi
