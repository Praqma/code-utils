#!/bin/bash

set -eu -o pipefail

[[ ${debug:-} == true ]] && set -x

cd $1


declare -A leaf_sha1s

for sha1 in $(git rev-list --all --children | grep -E "^[a-f0-9]{40}$" | sort -u) ; do 
    tags_of_sha1=$( git tag --points-at $sha1 )
    if [[ ${tags_of_sha1:-} != "" ]]; then
        leaf_sha1s[$sha1]="${tags_of_sha1}"
    fi
done

if [[ "${#leaf_sha1s[@]}" -eq 1 ]]; then 
    found_sha1=${leaf_sha1s[@]}
    echo "found_sha1=${!leaf_sha1s[@]}"
    exit 0
else
    printf "More than one leaf:\n"
    {
    for sha1 in "${!leaf_sha1s[@]}"; do
        printf "%s %s\n" "$sha1" "${leaf_sha1s[$sha1]}"
    done
    } | sort -h  
    exit 1
fi
