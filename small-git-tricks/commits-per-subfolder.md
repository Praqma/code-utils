# Find number of commits per subfolder

Just wanted to share a oneliner I whipped up, for that use case where you want to analyse a big git repo 
and find out in which folder the activity has been. 
I.e. If you are considering splitting up a repo with a couple 100k commits, then it can be good  to estimate 
the number of commits in the subfolders being split out.

`for dir in ./*; do (echo "$dir " && git rev-list --count HEAD --  "$dir"); done`

Yes, this also includes any direct files in root folder, but I didn’t bother excluding those. 
Feel free to improve and share back.
