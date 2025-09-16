#!/bin/bash
set -xeu 

export WORKSPACE=$(pwd)

if [[ -d xml ]]; then
	cd xml
    git fetch origin -p
    git reset --hard origin/$(hostname)-master-xml || git reset --hard origin/master-xml || git reset --hard origin/master
    ls -1 | xargs rm -rf
else
	mkdir xml
    cd xml
    git init
	git remote add origin ${REPO_URL}
    git fetch origin -p
    git reset --hard origin $(hostname)-master-xml
fi

# system and plugins
echo "**/configurations/" > .gitignore
echo "**/builds/" >> .gitignore
echo "**/fingerprints/" >> .gitignore
echo "**/*_deleted_*/" >> .gitignore
echo "plugins/*" >> .gitignore
echo "users/*" >> .gitignore
echo "nodes/*" >> .gitignore
echo "config-history/*" >> .gitignore
echo "scm-sync-configuration/*" >> .gitignore
echo "workspace/*" >> .gitignore

# user path for clean up
echo "jobs/esw/jobs/bitbucket/*" >> .gitignore
echo "jobs/esw/jobs/sonarcloud/*" >> .gitignore
echo "config.bak/*" >> .gitignore

cd $jenkins_path
find . \
  	-path "*/configurations" -prune -o \
  	-path "*/builds" -prune -o \
  	-path "*/fingerprints" -prune -o \
  	-path "*/*_deleted_*" -prune -o \
  	-path "./plugins/*" -prune -o \
  	-path "./users/*" -prune -o \
  	-path "./nodes/*" -prune -o \
  	-path "./config-history/*" -prune -o \
  	-path "./scm-sync-configuration/*" -prune -o \
  	-path "./workspace/*" -prune -o \
   \
  	-path "./jobs/esw/jobs/bitbucket/*" -prune -o \
  	-path "./jobs/esw/jobs/sonarcloud/*" -prune -o \
	-name 'config.xml' -type f \
    -print
  
[[ ${dryrun:-} == true ]] && exit 

find . \
	-path "*/configurations" -prune -o \
  	-path "*/builds" -prune -o \
  	-path "*/fingerprints" -prune -o \
  	-path "*/*_deleted_*" -prune -o \
  	-path "./plugins/*" -prune -o \
  	-path "./users/*" -prune -o \
  	-path "./nodes/*" -prune -o \
  	-path "./config-history/*" -prune -o \
  	-path "./scm-sync-configuration/*" -prune -o \
  	-path "./workspace/*" -prune -o \
   \
  	-path "./jobs/esw/jobs/bitbucket/*" -prune -o \
  	-path "./jobs/esw/jobs/sonarcloud/*" -prune -o \
	-name 'config.xml' -type f \
    -exec cp --parents \{\} ${WORKSPACE}/xml \;
cd -

cd ${WORKSPACE}/xml

git add -A .
if [[ ${tag:-} == "" ]]; then 
	tag=$(date +"%Y-%m-%dT%H-%M-%S")
fi
tag_commit="$(hostname)-${jenkins_path}-${tag}"
git commit -m "${tag_commit}"
git push origin -f HEAD:$(hostname)-master-xml
if [[ ${tag:-} != "" ]]; then 
	git tag -a -m "${tag_commit}" ${tag_commit} -f
	git push origin ${tag_commit} -f
fi


cd ${WORKSPACE}/xml/jobs

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

