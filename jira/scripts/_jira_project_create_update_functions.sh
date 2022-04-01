function components_add_product_level_and_requests {
  local _project=$1
  local _jira_proj_category=$2
  local _jira_team_proj_pattern=$3
  ${codeutils_jira_script_lib}/create_component_from_parameters.sh ${_project} "Documentation" ""
  IFS=$'\r\n'
  team_projects=$(curl --fail --insecure --netrc-file ~/.netrc -X GET -H Content-Type:application/json -o - --silent --url ${jira_server}/rest/api/2/project \
                    | jq -r ".[] \
                      | select(.projectCategory.name==\"${_jira_proj_category}\") \
                      | select(.key | match(\"${_jira_team_proj_pattern}\") ).key ")
  for team_proj in $(echo "$team_projects"); do
      ${codeutils_jira_script_lib}/create_component_from_parameters.sh ${_project} "${team_proj}" ""
  done
  unset IFS
}


function get_jira_category_projectnames {
    local _jira_server=$1
    local _jira_proj_category=$2
    local _jira_proj_pattern=$3
    IFS=$'\r\n'
    
    jira_projects=$(curl --fail --insecure --netrc-file ~/.netrc -X GET -H Content-Type:application/json -o - --silent  --url ${_jira_server}/rest/api/2/project \
                    | jq -r ".[] \
                      | select(.projectCategory.name==\"${_jira_proj_category}\") \
                      | select(.key | match(\"${_jira_proj_pattern}\") ).key ")
    echo $jira_projects

}

function delete_jira_project {
  local _jira_server=$1
  local _jira_proj_key_to_delete=$2
  project_key_found=$(curl --fail --insecure --netrc-file ~/.netrc -X GET -H Content-Type:application/json -o - --silent --url "${_jira_server}/rest/api/2/project/${_jira_proj_key_to_delete}" | jq -r .key )

  if [[ "${project_key_found}" == "${_jira_proj_key_to_delete}" ]] ; then
    printf "Project found: $project_key_found - delete it... and it might take some time depend on the amount of issues.."
    printf " - but sleep for 10 sec to offer abort...\n"
    sleep 10
    curl --fail --insecure --netrc-file ~/.netrc -X DELETE -H Content-Type:application/json -o - --url ${_jira_server}/rest/api/2/project/${_jira_proj_key_to_delete}
    return 0
  else
    echo "Project not found: $_jira_proj_key_to_delete - skip deleting"
    return 0
  fi
}

function update_jira_proj_category_projs_w_components_of_teams_project_keys {
  local _jira_project_category=$1
  local _jira_product_proj_pattern_match=$2
  local _jira_team_proj_pattern_match=$3

  IFS=$'\r\n'
  product_projects=$(curl --fail --insecure --netrc-file ~/.netrc -X GET -H Content-Type:application/json -o - --silent --url ${jira_server}/rest/api/2/project \
                      | jq -r ".[] | select(.projectCategory.name==\"${_jira_project_category}\") \
                      | select(.key | match(\"${_jira_product_proj_pattern_match}\") ).key" )
  echo $product_projects
  for product_proj in $(echo "${product_projects}"); do
    echo "Add components for ${product_proj}"
    components_add_product_level_and_requests "${product_proj}" "${_jira_project_category}" "${_jira_team_proj_pattern_match}"
    echo "Done"
    echo
  done
  unset IFS
}

#################
#
# Team projects
#
#################
function create_team_project {
  local _project_description="$1"
  local _project_key="${test_prefix:-}$2"
  local _project_admins=$3
  ${codeutils_jira_script_lib}/create-jira-project-from-shared-config.sh "${_project_key}" "${_project_description}" "TMPLSACTEA" "${_project_admins}"
  [[ ${create_mode:-} == "delete" ]] && return
  if [[ ${jira_import_files:-} != "" ]] ; then
    local _project_fixversion_pattern=$4
    if [[ ${_project_fixversion_pattern:-} != "" ]]; then
      IFS=" "
      for jira_import_file in $jira_import_files; do
       ${codeutils_jira_script_lib}/create_releases_from_json_import.sh "${_project_key}" "${_project_fixversion_pattern}" "$jira_import_file"
      done
      unset IFS
    else
      echo "FixVersion pattern is empty - skip"
    fi
  fi
  printf "\n"
}

#################
#
# Product projects
#
#################
function create_jira_product_proj {
  if [[ ${test_prefix:-} != "" ]]; then
    local _project_description="${test_prefix} $1"
  else
    local _project_description="$1"
  fi
  local _project_key="${test_prefix:-}$2"
  local _project_admins="$3"

  ${codeutils_jira_script_lib}/create-jira-project-from-shared-config.sh "${_project_key}" "${_project_description}" "TMPLSACPRD" "${_project_admins}"
  [[ ${create_mode:-} == "delete" ]] && return
  if [[ ${jira_import_files:-} != "" ]] ; then
    local _project_fixversion_pattern="$4"
    if [[ ${_project_fixversion_pattern:-} != "" ]]; then
      IFS=" "
      for jira_import_file in $jira_import_files; do
        ${codeutils_jira_script_lib}/create_releases_from_json_import.sh "${_project_key}" "${_project_fixversion_pattern}" "$jira_import_file"
      done
      unset IFS
    else
      echo "FixVersion pattern is empty - skip"
    fi
  fi
  printf "Done\n\n"
}