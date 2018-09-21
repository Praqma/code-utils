---
maintainer: praqma-thi
---

# code-utils
Continuous Delivery utilities - small scripts and concepts used in continuous delivery setups.

Instead we all keep reinventing the same small concepts and scripts again and again we should share them.
This repository is for sharing all the small nice little scripts used on daily basis for continuous integrations, continous delivery, builds, artifact management or what-ever is needed for you to get the build and delivery pipeline up and running.

Many of the added scripts and snippets are quite old, added during a clean-up. They might serve as inspiration, rather than production useable scripts. Some of the thigns might also be done in another way today.

## Utils available

### Misc-folder

Contains different small scripts.

__[misc/checkFileSyncModified.sh](misc/checkFileSyncModified.sh)__: Bash script to check if one file in a list of files have been modified since last time, without the other being updated. And old praqmatic solution to keeping files in sync that could be reused. Used in a Jenkins job, that failed if one of the files being changed without the others being chagned as well. Don't check if the changes are relevant.

__[misc/jenkins-createUniqueArtifact.rb](misc/jenkins-createUniqueArtifact.rb)__: can create unique files with some traceability content in a Jenkins job, that can be archived and fingerprinted to create traces between Jenkins job. The created unique artifacts, could also be stored to show important information with artifacts.

__[misc/createStagingNo.rb](misc/createStagingNo.rb)__: Modulo 10 a build number from Jenkins, to create round robin deploy or staging folders.

### Set version in C/C++ files

A simple conceptual script that can stamp build version into C/C++ application. Can be re-used for other things.
Basically works on headerfiles, that needs to be included.

See the [setversion/](setversion/) folder for the script, in Bash and Ruby, and related template files.

### doCppCheck

A Ruby wraper script around running CppCheck, and some configuration files to adjust the way it analyses the code.
Wrapper script was mostly used to gather relevant files to include in analysis, and try to find header files to include for the analysis to be more correct.

See the [doCppCheck/](doCppCheck/) folder for the script.

### Pretested Integration

The well established concept of pretested integration, made available first as the [Jenkins Pretested Integration Plugin](https://wiki.jenkins-ci.org/display/JENKINS/Pretested+Integration+Plugin) is also available in several flavors not related to Jenkins.

As a groovy script: https://github.com/Praqma/pretested-integration
As a groovy demo here for binaries: https://github.com/Praqma/pretested-binary-integration-concept

### Job DSL collections

Though it is work in progress, we have started a Job DSL collection project trying to create building block for Job DSL snippets for all our common jobs.

It can serve as inpspiration for how to structure such things, our plain copy-paste of snippets you like.
You could also when the project is more mature depend on the snippets.

See these repositories:

* https://github.com/Praqma/job-dsl-collection
* https://github.com/Praqma/jobdsl-helpers

### Transform and Run

A script that can transform another script, before executing it. Usage can be scripts that can't take variables, or are used as inputs to other scripts.

This original use-case is IBM WAS configuration script, in Jython, that can't take parameters as the script itself is a parameter to a command.

For details, see [sub directory readme in transformAndRun](transformAndRun/readme.md)

### Run WebSphere xmlaccess scripts

A little Groovy script to orchestrate exection of IBM WebSphere Portal xmlaccess commands, so there can be several files executed in some order.
Using natural sort, it run all the xmlaccess script in the folder you pass it.

Rest of the details can be found reading the script - it is simple, promise ;-)

### powerping

Simple little groovy script to check DNS lookup, TCP connection and ping and curl of http(s) addresses against a list of hosts in the configuration file.

Check firewall rules, from node to node using Jenkins build slave. You can't easily do this with monitoring systems.

Read more on use-case in the [sub directory readme in powerping](powerping/README.md)


### File pattern scanner

If you are forced to use a crappy tool, that doesn't fail with non-zero exit codes, the file pattern scanner can help if the crappy tools just report the problems in for example a log file. You can scan that log file and report the error, and fail accordingly.

See https://github.com/Praqma/file-pattern-scanner

### Artifactory Handler
Simple script to interface to Artifactory's REST API. See the [README](artifactoryHandler/README.md) in the artifactoryHandler directory.

### BitBucket
Collection of scripts for interacting with BitBucket. Initially for creating repositositories (push) and configure them with branch permissions etc. Add further scripts as developed. [README](bitbucket/README.md)

### Small Git tricks
This folder contains smaller git oneliners or aliases or similar.

For now:

* Find number of commits per subfolder

## Proposed usage

I'm planning to use the code-utils as a git submodule in other projects, so I have a firm dependency management.
It could also be binary but then you would have to download the scripts, unpack and use them.

# Repository structure

Each little utility should have a foot-print with a very short description here in the repository readme, but placed in it's own folder.

Within the folder of each util, there should be a readme explaining how to use, the use-case etc.

* Please make sure scripts are anonymized - no customer, or specific user details.

Folders might later be categorized in further levels.


# Contribution criterias

Right now - not so many, except from keeping the repository structure as above described.

Let's see how this evolves.

## Testing

You should have some testing alongside your scripts.
An old idea is described in the testing-idea folder, see [testing-idea/readme.md](testing-idea/readme.md)

You chose any way to test your scripts.

# Roadmap for code-utils

Some thoughts:

* see how it evolves
* just sharing script between consultants and customers publicly (but anonymized)
* maybe implement the functionality as one gradle plugin later? One to rule the all...

## The Praqmatic CoDe Util gradle plugin

Along wrapping it all in one technology, we could consider a gradle plugin. Some ideas around that are as follows.

* "An easy to use plugin to replace all customized scripts": All the existing commonly used small scripts and solutions is wrapped into this gradle plugin as tasks. Instead of using all kinds of different scripts, technologies, cross-platform setups etc. Gradle and JVM can be utilized. Only dependency will be this plugin and implicitly the JVM and Gradle wrapper in the project.
* "The functionality support and follow the praqmatic and recommended best-practice way of working".
* "All tasks are tested": In a plugin, we could easily ensure all utils are tested.
* "All tasks have simple help on them": Make sure all usage and help text are presented in common way.
* "All tasks have thorough help available with examples"
* "All tasks explain their motivation and enforced way of working (why)."
