#!/usr/bin/env bash
set -e
set -u

[[ ${debug:-} == true ]] && set -x

export jira_server="https://<server>[:8080]"

echo "Using Jira server: $jira_server"

# Load functions
source ${BASH_SOURCE%/*}/_jira_project_create_update_functions.sh|| source ./_jira_project_create_update_functions.sh


if [[ ${1:-} == "" ]] ; then
  echo "Import files not in use : - skip"
else
  jira_import_files=$1
  IFS=" "
  for jira_import_file in $jira_import_files; do
    if [[ -e ${jira_import_file} ]]; then
      echo "Using $jira_import_file"
    else
      echo "file '${jira_import_file}' does not exists"
      exit 1
    fi
  done
  unset IFS
fi 


#################
#
# Team project
#
#################
export mode="skipOcreate"
#export create_mode="deleteNcreate"
#create_team_project "<Jira Project Team name>" "<Jira-key>" "<project-lead>" ["<fix-version-pattern-from-import-json>]

unset mode

#################
#
# Product/Archive/Inbox project
#
#################

export mode="skipOcreate"
#export create_mode="deleteNcreate"
#create_jira_product_proj "<Jira Project Team name>" "<Jira-key>" "<project-lead>"
unset mode

update_jira_proj_category_projs_w_components_of_teams_project_keys "SaCoS projects" "^S1.*\$|^S5K.*\$|^SACOS\$|^SMP.*\$" "^SCS.*\$"
