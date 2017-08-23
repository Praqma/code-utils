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

Interesting output file:
* `bigtosmall_sorted_size_files.txt` ( for file impact in repository)
* `bigtosmall_sorted_size_files_revisions.txt` ( each revision of a file in size order. NOTE: This list does not contains all files as these are only file revisions that have been pack further. This list does not show the impact to the repository directly - It should be found in `bigtosmall_sorted_size_files.txt` )

Usage: `[WORKSPACE=`<absolute-path>`] git-object-sizes-in-repo-analyzer.sh [<dir>]`

