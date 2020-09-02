#!/bin/bash
 
# Author: Jaime Kirch da Silveira (Atlassian Cloud Support)
# Last update: April, 17th, 2015

# This will import all attachments to JIRA issues
# Check this KB for more information:
# https://confluence.atlassian.com/display/JIRAKB/Bulk+import+attachments+to+JIRA+issues+via+REST+API

if [[ $# != 4 ]]
then

	echo "Format: $0 <username> <password> <project key> <JIRA URL>"
	echo "Please notice that the JIRA URL must include all the path to access JIRA, including anything after the '/' (like /jira) and the protocol as well (like https://)"
	exit
fi

USERNAME=$1
PASSWORD=$2
PROJECT_KEY=$3
JIRA_URL=$4

AUTH_TYPE=cookie
#AUTH_TYPE=basic

COOKIE_FILE=cookie.txt

if [ "${AUTH_TYPE}" = 'cookie' ]
then
	curl --cookie-jar ${COOKIE_FILE} -H "Content-Type: application/json" -d '{"username":"'${USERNAME}'", "password":"'${PASSWORD}'" }' -X POST ${JIRA_URL}/rest/auth/1/session 
fi


for key in ${PROJECT_KEY}-*
do
    if [ "$(ls -A ${key})" ]
    then
    	echo "Importing attachments for issue $key"
    	for file in $key/*
    	do
        	echo "Importing file: $file"
		if [ "${AUTH_TYPE}" = 'cookie' ]
		then
        		curl -D- -b ${COOKIE_FILE} -X POST --header "X-Atlassian-Token: no-check" -F "file=@${file}" ${JIRA_URL}/rest/api/2/issue/${key}/attachments 
		else
			if [ "${AUTH_TYPE}" = 'basic' ]
			then
				curl -D- -u ${USERNAME}:${PASSWORD} -X POST --header "X-Atlassian-Token: no-check" -F "file=@${file}" ${JIRA_URL}/rest/api/2/issue/${key}/attachments
			fi
		fi
		done
    fi
 
done 
