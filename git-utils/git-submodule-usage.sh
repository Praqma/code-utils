#!/bin/bash

# Enable strict mode for better error handling 
set -euo pipefail

while getopts "s:h" opt; do
    case ${opt} in
        s )
            subm_repo_name="${OPTARG}"
            shift
            ;;
        \?|h )
            echo "Usage: $0 -s <submodule-name>"
            echo "  -s <submodule-name>   Specify the old tag to be retagged"
            exit 1
            ;;
    esac
done

if [[ -z "${subm_repo_name:-}" ]]; then
    $0 -h
    exit 1
fi

for subm_path in $(git config get -f .gitmodules  --all  --regexp ".*/${subm_repo_name}.path$"); do 
    printf "Submodule path: %s\n" "$subm_path"
    for sha1_root in $(git rev-list --all -- ${subm_path}) ; do 
        sha1_sub="$(git ls-tree $sha1_root ${subm_path} | cut -d " " -f 3 | cut -d$'\t' -f 1 )" || true

        if [ -z "${sha1_sub:-}" ]; then
            sha1_sub="(no submodule)"
        else
            git -C ${subm_path} rev-parse --verify $sha1_sub > /dev/null 2>&1 || {
                git -C ${subm_path} fetch origin $sha1_sub > /dev/null
                git artifact fetch-tags -s $sha1_sub > /dev/null
                git -C ${subm_path} rev-parse --verify $sha1_sub > /dev/null 2>&1 || {
                    sha1_sub_ls_remote="(dead sha1)"    
                }
            }

            sha1_sub_ls_remote=$(git -C ${subm_path} ls-remote --tags origin | grep $sha1_sub | cut -d / -f 3-) || true
            
            if [ -z "${sha1_sub_ls_remote:-}" ]; then
                sha1_sub_ls_remote="(no tag)"
            fi
        fi

        remote_branches_contains_count=$(git branch -r --contains $sha1_root | wc -l)
        tags_contains_count=$(git tag --contains $sha1_root | wc -l)
        
        printf "%14.14s %-60.60s %-80.80s %-20.20s\n" \
                    "$sha1_sub" \
                    "$sha1_sub_ls_remote" \
                    "$(git log --oneline -1 --decorate --format="%h %cd %s" $sha1_root | cut -c1-90)" \
                    "(ct.br:$remote_branches_contains_count ct.t:${tags_contains_count})"
        if [[ "${verbose_branches:-verbose_branches_false}" == true && "$remote_branches_contains_count" -gt 0 ]]; then
            git branch -r --contains $sha1_root | grep -e origin/master -e origin/main -e origin/products/.* || true
        fi

    done
    echo
done
