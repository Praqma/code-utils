# git-workspace-file-type-analyzer.sh

The objective is to traverse a 'dir' to figure out how all files are interpreted by the unix tool `file` and how `git` sees the file.

It is important when working with `git` ( or simular DVS ) as all files and their revisions are default distributed to everyone. It is up to you what you should or should not do with each file and/or extension.

The analyzer find all files in the `pwd` and outputs:
* a set of files list with different aspects of the analysis:
  * ascii_files_size_sorted.txt
  * binary_files_size_sorted.txt
  * verdict_size_sorted.txt
  * verdict_type_sorted.txt
  * ascii_extension.txt
  * binary_extension.txt
* Type legend:
  * gA: Git ascii
  * gB: Git binary 
  * fA: `file` tool reported 'ASCII text' or simular
  * fB: `file` tool reported other than 'ASCII text' or simular
  * fE: `file` tool reported 'empty'

Usage: `git-workspace-file-type-analyzer.sh <dir>`

# git-object-sizes-in-repo-analyzer.sh

The objective is to analyze an already existing git repo for all files in whole history. Each file is listed as its entry/entries in the internal datastructure and their impact to the disc. For this reason the amount of revisions of a file does not correspond to the amount of entries in the output list. If each revision of a file is interesting this is also available.

It is suppported that it is given a sub-dir-path in case of submodules.

It is designed to be executed from a Jenkins Freestyle or Matrix job and it stores the output files in the WORKSPACE variable dir. WORKSPACE should be absolute path. If not set, it store them in "."

Output file:
* `bigtosmall_errors.txt` ( if error occurred while parsing blobs directly stored in the .idx )
* `bigtosmall_errors_revision.txt` ( if error occurred while parsing blobs stored as revisions/deltas in the .idx )
* `bigtosmall_sorted_size_files.txt` ( path/file impact in repository which is store directly in the .idx file - usually big and binary files (*) )
* `bigtosmall_sorted_size_files_revisions.txt` ( path/file impact in repository which is store directly in the .idx file - usually big and binary files (*) )
* `bigtosmall_sorted_size_total.txt` ( the sum of each path/file and amount of revisions in `bigtosmall_sorted_size_files.txt` file (**) )
* `bigtosmall_sorted_size_total_revisions.txt` ( the sum of each path/file and amount of revisions in `bigtosmall_sorted_size_files_revisions.txt` file (**) )
* `branches_embedded.txt` ( a list of branches which are embedded hence not leaves in the history tree - hence the branches are targeted to be deleted (***) )
* `branches_embedded_tagged.txt` ( a list of branches which are embedded hence not leaves in the history tree, but also tagged - hence targeted to be deleted (***)  )
* `branches_leaves.txt`  ( a list of branches which are leaves in the history tree, but not tagged - hence likely active (****) )
* `branches_leaves_tagged.txt` ( a list of branches which are leaves in the history tree and tagged - hence they could be target to be deleted (****) )

(*) : H/B marker mean of the path/file is in current revision HEAD(H) or secondary in a branch(B); The blob check-sum to make line unique; The size in in bytes. Path/file: All files are listed sorted at their largest(first) appearance. Remember to check both files for total impack and understanding to which extended the path/file packed partially/fully.
(**) : The total size in in bytes; H/B marker mean of the path/file is in current revision HEAD(H) or secondary in a branch(B); Amount of instances found; Path/file. Remember to check both files for total impack and understanding to which extended the path/file packed partially/fully.
(***) : List the branches ; last sha1 - committer date ; refs pointing to sha1 ; git commit subject
(****) : List the branches ; amount commit/files compared to default branch; last sha1 - committer date ; refs pointing to sha1 ; git commit subject

Usage: `[debug=true] [repack=false] [invest_remote_branches=true=false] [WORKSPACE=`<absolute-path>`] git-object-sizes-in-repo-analyzer.sh [<dir>]`

# git-sizer (external tool)
In combination with the above tools for deep analysis on object level it could also be interesting to get a overview of the stats of the repository. It is also advised to read the recommandations for working with git repositories.

https://github.com/github/git-sizer


