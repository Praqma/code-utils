#!/bin/bash
# 
# Usage: run_tests_Linux.sh $testsuite
# E.g.:  run_tests_Linux.sh functional

TESTSUITE=$1

# Directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

for l in `cat $TESTSUITE/tests.inc`
do
	$SCRIPT_DIR/$TESTSUITE/$l.bats
	# FIXME - catch exception, and continue with next run.sh if it fails
	# run scripts are supposed to report in well know test format to jenkins
done
