#!/bin/bash
set -xeu 

export WORKSPACE_CYGPATH=$(pwd)

if [[ -d xml ]]; then
	cd xml
  git reset --hard
  ls -1 | xargs rm -rf
else
	mkdir xml
  cd xml
  git init
	git remote add origin ${git_remote}
	echo "**/configurations/" > .gitignore
	echo "**/builds/" >> .gitignore
	echo "**/fingerprints/" >> .gitignore
  echo "**/*_deleted_*/" >> .gitignore
fi
cd $jenkins_path
find . -name "*.xml" -exec cp --parents \{\} ${WORKSPACE_CYGPATH}/xml \;
cd -

cd ${WORKSPACE_CYGPATH}/xml

git add -A .
git commit -m "$(date) - $jenkins_path ${tag}" || echo "never mind"
git push origin -f master:master-xml
if [[ ${tag:-} != "" ]]; then 
	git tag -a -m "${tag}" ${tag} -f
	git push origin ${tag} -f
fi

cd ${WORKSPACE_CYGPATH}/xml/jobs

if [ ${make_disabled:-} == true ]; then
  IFS=$'\n\r'
  for config_file in $( find . -maxdepth 4 -name config.xml ); do 
     echo "${config_file}"
     cat $config_file  | \
        sed -e 's/  <disabled>false<\/disabled>/  <disabled>true<\/disabled>/' \
          > "${config_file}_tmp"
      mv "${config_file}_tmp" "${config_file}"
      grep -q "^  <disabled>" "${config_file}" || echo "Likely folder"
  done
  git add -A .
  git commit -m "$(date) - disabled" || echo "never mind"
  git push origin -f master:master-disabled-xml
fi 

