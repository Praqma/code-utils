#!/bin/bash
set -euo pipefail
df -h
export GIT_SSL_NO_VERIFY=1

if [[ -d ./code-utils ]] ; then
  cd ./code-utils	
  git fetch -ap
  git reset --hard origin/master
  cd ..
else
  git clone https://github.com/Praqma/code-utils.git 
fi

if [[ "${debug:-}" == true ]]; then 
	export GIT_TRACE=1
    set -x
fi

project=$(echo ${projects_slug} | cut -d / -f1)
slug=$(echo ${projects_slug} | cut -d / -f 3 | cut -d : -f 1 )
lfs_statement=$(echo ${projects_slug} | cut -d : -f 2)

[[ ${lfs_statement:-} != "" ]] && [[ ${lfs_statement:-} != "${projects_slug}" ]] && eval ${lfs_statement}

if [[ -d ${slug}.git ]]; then
  cd ${slug}.git
  git fetch origin -ap
  git fetch origin --tags
  if [[ ${lfs_enabled:-true} == true ]]; then
  	git lfs fetch --all || {
      exitcode_lfs_fetch=$?
      if [[ ${lfs_accept_missing:-false} == true ]]; then
      	echo "INFO: we accept issues"
        git lfs uninstall --local
      else
      	exit $exitcode_lfs_fetch
      fi
    }
  fi
else
  mkdir  ${slug}.git
  cd ${slug}.git
  git init --bare
  git config --add remote.origin.url ${old_server_url}/${project}/${slug}.git
  git config --add remote.origin.fetch +refs/heads/*:refs/heads/*
  git config --add remote.origin.fetch +refs/tags/*:refs/tags/*
  git config -l --local
  git fetch origin -ap
  git fetch origin --tags
  if [[ ${lfs_enabled:-true} == true ]]; then
  	git lfs install --local
  	git lfs fetch --all || {
      exitcode_lfs_fetch=$?
      if [[ ${lfs_accept_missing:-false} == true ]]; then
      	echo "INFO: we accept issues"
        git lfs uninstall --local
      else
      	exit $exitcode_lfs_fetch
      fi
	}
  fi
fi
if [[ -d lfs ]] ; then 
  du -sh lfs
fi
git show-ref

if [[ ${bitbucket_server_type:-} == "bitbucketProd" ]]; then
  export bitbucket_server=$bitbucket_prod_server
fi
bitbucket_server_url=https://${bitbucket_username}:${bitbucket_password}@${bitbucket_server}
git push ${bitbucket_server_url}/scm/${project}/${slug}.git --mirror || {
  cd ${WORKSPACE}
  export netrc_file=~/.netrc
  source ./code-utils/bitbucket/_bitbucket_repo_functions.sh
  bash ./code-utils/bitbucket/bitbucket_create_repo-branch-restrictions.sh "${project}" "${slug}" ${netrc_file} "${bitbucket_server_url}" "$(whoami)" || {
    echo "machine ${bitbucket_server}" >> ./.netrc
    echo "login ${bitbucket_username}" >> ./.netrc
    echo "password ${bitbucket_password}" >> ./.netrc
    export netrc_file=$(pwd)/.netrc    
    source ./code-utils/bitbucket/_bitbucket_repo_functions.sh
    bash ./code-utils/bitbucket/bitbucket_create_repo-branch-restrictions.sh "${project}" "${slug}" ${netrc_file} "${bitbucket_server_url}" "$(whoami)" 
    rm -rf ./.netrc
  }
  cd ${slug}.git
  git push ${bitbucket_server_url}/scm/${project}/${slug}.git --mirror
}
bitbucket_server_url=https://${bitbucket_username}:${bitbucket_password}@${bitbucket_server}
if [[ ${lfs_enabled:-true} == true ]]; then
	git lfs ls-files -a -s
    git lfs push --all ${bitbucket_server_url}/scm/${project}/${slug}.git || {
      exitcode_lfs_push=$?
      if [[ ${lfs_accept_missing:-false} == true ]]; then
      	echo "INFO: we accept issues"
      else
      	exit $exitcode_lfs_push
      fi
	}
fi

git ls-remote --heads origin > ${WORKSPACE}/origin_heads.txt
git ls-remote --tags origin > ${WORKSPACE}/origin_tags.txt

git ls-remote --heads ${bitbucket_server_url}/scm/${project}/${slug}.git > ${WORKSPACE}/aws_heads.txt
git ls-remote --tags ${bitbucket_server_url}/scm/${project}/${slug}.git > ${WORKSPACE}/aws_tags.txt

cd ${WORKSPACE}

diff -y origin_heads.txt aws_heads.txt && echo "All good - heads are identical" || { 
   echo "ERROR: heads differ"
   exit_code=2
}

diff -y origin_tags.txt aws_tags.txt && echo "All good - tags are identical" || { 
   echo "ERROR: tags differ"
   exit_code=2
}


rm -rf ${slug}-test.git
git clone ${bitbucket_server_url}/scm/${project}/${slug}.git --mirror ${slug}-test.git
if [[ ${lfs_enabled:-true} == later ]]; then
  	cd ${slug}-test.git
    git lfs install --local
  	git lfs fetch --all || {
      exitcode_lfs_refetch=$?
      if [[ ${lfs_accept_missing:-false} == true ]]; then
      	echo "INFO: we accept issues"
      else
      	exit $exitcode_lfs_refetch
      fi
    }
fi


exit ${exit_code:-}
