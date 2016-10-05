# bitbucket_create_repo-branch-restrictions.sh

This script will create the following in BitBucket Server 
- a repository 
- potential push and already created git repository. The directory need to call `empty_repo` 
  - create remote `stable` and `release` branches based on local `master` branch
  - push all tags
- configure the repository with branches restriction (e.g. who can push to which branch and tag pattern )

It demonstrates protecting of branches in the Praqma Git Flow model and multiple master branches in the same repository

