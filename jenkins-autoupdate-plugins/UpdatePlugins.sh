#!/usr/bin/bash

set +x

AUTH=$USERNAME:$PASSWORD
MYCLICMDLINE="java -jar ./jenkins-cli.jar -s ${JENKINS_URL} -auth $AUTH"

TOINSTALL=$(${MYCLICMDLINE} list-plugins | grep -E ')$' | awk '{print $1}' | tr '\n' ' ')

if [ -z "$TOINSTALL" ]; then
    echo "<b>No plugins to update.</b>" | tee ./description.txt
else
    echo "<b>Updating the following plugins:<br>" | tee ./description.txt
    # shellcheck disable=SC2086
    echo ${TOINSTALL} | tr -s ' ' | sed -e 's/[[:space:]]/<br>/g' | tee --append ./description.txt
    echo '</b>' | tee --append ./description.txt
    # shellcheck disable=SC2086
    $MYCLICMDLINE install-plugin ${TOINSTALL} -restart
    # $MYCLICMDLINE safe-restart -message "Plugins have been updated, must restart"
fi
