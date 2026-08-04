
set -euo pipefail

server_name="" #  used for cloning and getting credentials from ~/.git-credentials and URL extraction from bitbucket generated list .projects.repos.txt (code-utils/bitbucket/bitbucket_get_repo_sizes.sh)
run_checkout=${run_checkout:-false} #  used to control whether to checkout the repos or not

PROJECTS_LIST=" <space separated list of urls or local paths> " #  used
#PROJECTS_LIST="$(grep https ${server_name}.projects.repos.txt | cut -d ":" -f 1 | sed -e "s|^|https://${server_name}/scm/|" -e 's|/repos/|/|' )" 

run_root=$(pwd)
results_root=$run_root/results/orig
mkdir -p $results_root

function clone-fetch {
    local proj=$1
    local repo_name
    local bitbucket_project

    cd "$results_root"
    echo "Running git repo analyzer for $proj"
    repo_name=$(basename "$proj")
    bitbucket_project=$(echo "$proj" | cut -d "/" -f 5)
    mkdir -p "$results_root/$bitbucket_project--$repo_name"
    cd "$results_root/$bitbucket_project--$repo_name"

    BITBUCKET_TOKEN=$(grep ${server_name} ~/.git-credentials | cut -f 3 -d : | cut -f 1 -d @) \
        PROJECT_LIST="${proj}.git" \
        git_base_dir="$scm_root/$bitbucket_project" \
            bash "$(dirname "$0")/git-clone-fetch.sh"
    echo "Checkout: $proj : done"
}

if [[ ${run_checkout:-} == true ]] ; then 
    scm_root=$run_root/scm/orig
    mkdir -p $scm_root
    if [[ ${run_parallel:-} == true ]]; then 
        export -f clone-fetch
        export results_root scm_root
        printf '%s\n' ${PROJECTS_LIST} | xargs -n 5 -P 10 -I % bash -lc 'clone-fetch "$1"' _ %
    else
        for proj in $PROJECTS_LIST; do
            clone-fetch "$proj"
        done
    fi
else
    echo "Skipping checkout of repositories, run_checkout != true"
fi

function analyze {
    local proj=$1
    local repo_name
    local bitbucket_project

    cd "$results_root"
    echo "Running git repo analyzer for $proj"
    repo_name=$(basename "$proj")
    bitbucket_project=$(echo "$proj" | cut -d "/" -f 5)
    mkdir -p "$results_root/$bitbucket_project--$repo_name"
    cd "$results_root/$bitbucket_project--$repo_name"

    pwd
    if [[ -s $(pwd)/allfileshas.tmp ]]; then
        echo "allfileshas.tmp exists: $(pwd) - something is wrong, rerun"
    else
        if [[ -f ./git_sizes.txt ]]; then 
            echo "./git_sizes exists: $(pwd)"
            source ./git_sizes.txt
            if [[ ${git_verdict:-} != "" ]]; then 
                echo "git_sizes.txt already exists and has verdict, skipping $proj"
                return
            fi
        else
            rm -rf *.*
        fi
    fi

    PROJECT_LIST="${proj}.git" \
        WORKSPACE="$results_root/$bitbucket_project--$repo_name" \
            repack=false bash "$(dirname "$0")/git-clone.sh" "${scm_root}/${bitbucket_project}/${repo_name}"
    echo "Analyze: $proj : done"
}
export -f analyze

function analyze_local_path {
    local proj_path=$1

    cd "$results_root"
    echo "Running git repo analyzer for $proj_path"
    repo_name=$(basename "$proj_path")

    mkdir -p "$results_root/$repo_name"
    cd "$results_root/$repo_name"

    pwd
    if [[ -s $(pwd)/allfileshas.tmp ]]; then
        echo "allfileshas.tmp exists: $(pwd) - something is wrong, rerun"
    else
        if [[ -f ./git_sizes.txt ]]; then 
            echo "./git_sizes exists: $(pwd)"
            source ./git_sizes.txt
            if [[ ${git_verdict:-} != "" ]]; then 
                echo "git_sizes.txt already exists and has verdict, skipping $proj"
                return
            fi
        else
            rm -rf *.*
        fi
    fi

    PROJECT_LIST="${proj}.git" \
        WORKSPACE="$results_root/$repo_name" \
            repack=false bash "$(dirname "$0")/git-object-sizes-in-repo-analyzer.sh" "$proj_path"
    echo "Analyze: $proj_path : done"
}
export -f analyze_local_path


if [[ ${run_parallel:-} == true ]]; then 
    printf '%s\n' ${PROJECTS_LIST} | xargs -n 1 -P 5 -I % bash -lc 'analyze_local_path "$1"' _ %
else
    for proj in $PROJECTS_LIST; do
        if [[ -d "$proj" ]]; then
            results_root=${results_root:-$(pwd)/results}
            analyze_local_path "$proj"
        else
            analyze "$proj"
        fi
    done
fi

cd $results_root
pwd
ls -la 
python3 "$(dirname "$0")/generate_overview.py" "$results_root" "$results_root/overview.html"

