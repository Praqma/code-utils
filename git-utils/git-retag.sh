#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

while getopts ":o:n:dph" opt; do
    case ${opt} in
        o )
            tag_orig=$OPTARG
            ;;
        n )
            tag_new=$OPTARG
            ;;
        p )
            push_new_tag=true
            ;;
        d )
            delete_old_tag=true
            ;;
        \?|h )
            echo "Usage: $0 -o <tag_old> -n <tag_new> [-p [-d]]"
            echo "  -o <tag_old>   Specify the old tag to be retagged"
            echo "  -n <tag_new>   Specify the new tag name"
            echo "  -p             Push the new tag to remote"
            echo "  -d             Delete the old tag from remote after retagging: only if you use -p"
            echo "  -h             Show this help message"
            exit 1
            ;;
    esac
done

if [[ -z "${tag_orig:-}" ]] || [[ -z "${tag_new:-}" ]]; then
    $0 -h
    exit 1
fi

trap 'rm -f ./tag_meta_data.txt' EXIT

function get_old_tag_info() {
   
    git show refs/tags/$tag_orig > /dev/null || git fetch --force origin --no-tags refs/tags/$tag_orig:refs/tags/$tag_orig
    export GIT_AUTHOR_DATE="$(git tag -l --format="%(taggerdate:iso)" ${tag_orig})"
    git tag -l --format="%(taggerdate:raw)" ${tag_orig}
    export GIT_COMMITTER_DATE="${GIT_AUTHOR_DATE}"

    export GIT_AUTHOR_NAME=$(git tag -l --format="%(taggername)" ${tag_orig})
    export GIT_COMMITTER_NAME=${GIT_AUTHOR_NAME}
    export GIT_AUTHOR_EMAIL=$(git tag -l --format="%(taggeremail)" ${tag_orig})
    export GIT_COMMITTER_EMAIL=${GIT_AUTHOR_EMAIL}
    export GIT_TAGGER_NAME=${GIT_AUTHOR_NAME}
    export GIT_TAGGER_EMAIL=${GIT_AUTHOR_EMAIL}
    export GIT_TAGGER_DATE=${GIT_AUTHOR_DATE}
    git tag -l --format '%(contents)' ${tag_orig} > ./tag_meta_data.txt
}

function create_new_tag() {

    if [ ! -f ./tag_meta_data.txt ]; then
        echo "Error: Metadata file not found. Cannot create new tag."
        exit 1
    fi

    echo "Creating new tag ${tag_new} with data and message from ${tag_orig}"
    git tag -f -a -F ./tag_meta_data.txt ${tag_new} ${tag_orig}^{}
    git tag -l --format="%(taggerdate:iso)" ${tag_new}
    git tag -l --format="%(taggerdate:raw)" ${tag_new}

}

function delete_old_tag_remotely() {
    echo "Deleting old tag ${tag_orig} from remote"
    git push origin :refs/tags/${tag_orig}
    echo "Deleting old tag ${tag_orig} locally"
    git tag -d ${tag_orig}
}

function push_new_tag() {
    echo "Pushing new tag ${tag_new} to remote"
    git push origin refs/tags/${tag_new}
}


get_old_tag_info ${tag_orig}
create_new_tag ${tag_new}
[[ ${push_new_tag:-false} == true ]] && push_new_tag ${tag_orig} && {
    [[ ${delete_old_tag:-false} == true ]] && delete_old_tag_remotely ${tag_orig}
}
