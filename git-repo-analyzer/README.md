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
 
Usage: `git-workspace-file-type-analyzer.sh <dir>`
