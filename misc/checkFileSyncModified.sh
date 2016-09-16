#!/bin/bash

# This script monitors a list of files for changes and report (exit false)
# if one of the file changes, and not all of them.
# The use case is to keep files in edit-sync, understood as changes in one
# file imposes changes in another file (but the files are not identical, nor are
# the changes.

# Usage:
# run script with list of file as one parameter:
# ./script "file1 file2 file3"

# The script create a SHA checksum of each file first time it runs.
# Next time the script is executed, and one file is changed, the checksum does not match
# and file changed count is incremented. If it at the end does not match the file count
# not all files are changed.

# NOTE: the script is not idempotent - running it a second time after a change is detected
# there is no change (unless you changed the file between running the script)

list=$1
echo "Checking if file have been changed: $list"
echo "If one file is changed, all must be changed"

file_changed_count=0
file_count=0
changed_files_file="changed_file.lst"
rm -rf $changed_files_file

for f in $list; 
do
	if [ ! -f $f ]
	then
		echo "Did not find $f - skipping file"
	else
		file_count=$(($file_count + 1))
		echo "Monitoring file $f for changes"
		old_sha=$f.sha1
		if [ -f $old_sha ];
		then
			sha1sum -c $old_sha
			exit_value=$?
			if [ "$exit_value" -ne "0" ]
			then
				echo "Monitored file did not match old checksum"
				file_changed_count=$(($file_changed_count + 1))
				echo $f >> $changed_files_file	
			fi
		fi	
		# create new checksum for file for next time we run this script
		shasum $f > $old_sha
	fi
done

if [ "$file_changed_count" -gt 0 ] && [ "$file_count" -ne "$file_changed_count" ]
then
	echo "Some files did change - but not all. These file did change:"
	cat $changed_files_file	
else
	echo "OK - no file changed since last time"
fi
