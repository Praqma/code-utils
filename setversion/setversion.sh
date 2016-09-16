#!/bin/bash

echo "setverson.sh DEPRECATED - used Ruby version"
exit 1;

# Usage: setversion.sh version_info_template version_info_automated.h
# The script will copy the version header file template to the second file given
# and insert build and version info automatically.
# Script change the header file if running on Jenkins with global unique values,
# while local developer build get less unique informations.
# The automated file should be on the git ignore list, but the application should
# depende on the includes from both the default version_info.h file, and the automated
# one such the compilation will fail if the automated does not exists.


if [ $# -ne 2 ]; then
	echo "ERROR: call this script with version template information header file and the target version_info_automated.h file as arguments";
	exit 1;
fi
if [ -f "$1" ]; then
	IN_FILE=$1
	OUT_FILE=$2
	echo "Copying template version info file";
	cp -v $IN_FILE $OUT_FILE
else
	echo "ERROR; Supplied argument (file?) is not found, or a file";
	exit 1;
fi

if [ "$JENKINS_SERVER_COOKIE" = "uniquejenkinscookie-couldbecertcheckalso" ]; then
	echo "Running on our JenkinsServer - setting version info to unique values";
	echo "Writing version information to file: $OUT_FILE";

	sed -i 's/#define BUILD_NUMBER "xxxx"/#define BUILD_NUMBER "'$BUILD_NUMBER'"/g' $OUT_FILE
	sed -i 's/#define BUILD_TAG "unknown"/#define BUILD_TAG "'$BUILD_TAG'"/g' $OUT_FILE
	sed -i 's/#define BUILD_DATE_TIME "1970-01-01_00-00-00"/#define BUILD_DATE_TIME "'$BUILD_ID'"/g' $OUT_FILE
	sed -i 's/#define BUILD_SCM_INFO "not_available"/#define BUILD_SCM_INFO "'$(git rev-list -n 1 HEAD)'"/g' $OUT_FILE
	# Not checking every search and replace sed-command output for exit code. Assumes it goes well.
	exit 0;
else
	echo "Local/developer build (not Jenkins) therefore less unique version info";
	# Note that we still substitute everything just to make sure we can see a difference to an
	# unmodified version_info_template.
	sed -i 's/#define BUILD_NUMBER "xxxx"/#define BUILD_NUMBER "dev-snapshot"/g' $OUT_FILE
	sed -i 's/#define BUILD_TAG "unknown"/#define BUILD_TAG "'$USER'"/g' $OUT_FILE
	sed -i 's/#define BUILD_DATE_TIME "1970-01-01_00-00-00"/#define BUILD_DATE_TIME "'$(date +%F_%T)'"/g' $OUT_FILE
	sed -i 's/#define BUILD_SCM_INFO "not_available"/#define BUILD_SCM_INFO "unknown revision"/g' $OUT_FILE
	# Not checking every search and replace sed-command output for exit code. Assumes it goes well.
	exit 0;
fi
