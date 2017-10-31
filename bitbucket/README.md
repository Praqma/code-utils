# bitbucket_create_repo-branch-restrictions.sh

This script will create the following in BitBucket Server 
- a repository 
- potential push and already created git repository which is also a dir in `cwd` 
  - create remote `stable` and `release` branches based on local `master` branch
  - push all tags
  - can push mirror
- configure the repository with branches restriction (e.g. who can push to which branch and tag pattern )

Prework:
- Modify the `.netrc` file or create your own
- Modify the `bitbucket/bitbucket_create_repo-branch-restrictions.sh`
  - `bitbucket_admin_group="bitbucket-sys-admins"`
  - `bitbucket_url="https://localhost:7990"`
  - `ci_user="jenkins"`

Example call:
- `bitbucket_create_repo-branch-restrictions.sh <bitbucket-project> <repo(s)> [./.netrc|<your-own-file>]`
 
.. where `<repo(s)>` can also be identical to a subdirectory that will be pushed. More than one are then comma separated.

It demonstrates protecting of branches in the Praqma Git Phlow model and multiple master branches in the same repository

TODO:
- Parameterize the needed `Prework` modifications
