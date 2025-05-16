#!/bin/bash

echo "git checkout master"
git checkout master

echo "git creating new local branch from timestamp"
INPUT_BRANCH_NAME=$(date +%s)
git checkout -b $INPUT_BRANCH_NAME

echo "Add new files to the staging area"
git add .

echo "Commit the new files"
git commit -m "Add new files"

echo "New files committed:"
git diff --cached --name-only

git push -u origin $INPUT_BRANCH_NAME

echo "Branch '$INPUT_BRANCH_NAME' pushed to remote."

echo "waiting for output from pipeline..."

#it will have name like refs/heads/1739360601_20250212.24_output
echo -e "\n\n\tif pipeline take longer than 60s check this page\n\t<remote processing link>\n\n"
while ! git ls-remote --exit-code --heads origin refs/heads/$INPUT_BRANCH_NAME*_output
do echo 'Hit CTRL+C to stop';sleep 5; done

if git ls-remote --exit-code --heads origin refs/heads/$INPUT_BRANCH_NAME*_output 2>&1 1>/dev/null
then
    OUTPUT_BRANCH_NAME=$(git ls-remote --exit-code --heads origin refs/heads/$INPUT_BRANCH_NAME*_output| cut -d/ -f3-)
    echo "pipeline created $OUTPUT_BRANCH_NAME branch, running git pull and checkout"
    git pull 2>&1 1>/dev/null

    git checkout $OUTPUT_BRANCH_NAME
    git checkout master
    #it has strange bug, after git pull and checkout to master, git does not see files, so im checkouting to output branch, then to master
    
    git checkout $OUTPUT_BRANCH_NAME audio_files/*.wav 2>&1 1>/dev/null
    git checkout $OUTPUT_BRANCH_NAME audio_files/*.txt 2>&1 1>/dev/null
    
    echo "removing remote input branch"
    git push origin --delete $INPUT_BRANCH_NAME

else
    echo "remote branch not found"
    exit -1
fi
