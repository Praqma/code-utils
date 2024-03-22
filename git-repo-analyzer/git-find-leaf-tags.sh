#!/bin/bash

set -eu -o pipefail

[[ ${debug:-} == true ]] && set -x

cd $1


leafs=()

for sha1 in $(git rev-list --all --children | grep -E "^[a-f0-9]{40}$") ; do 
    for tag in $( git tag --points-at $sha1 ) ; do
        leafs+=("$tag")
    done
done

found_tag=""
if [[ "${#leafs[@]}" -eq 1 ]]; then 
    found_tag="${leafs[0]}"
    echo "found_tag=$found_tag"
    exit 0
else
    printf "More than one leaf: ${leafs[*]}\n"
    {
        for leaf in "${leafs[@]}"; do
            echo $leaf
        done
    } | sort -h  
    exit 1
fi
