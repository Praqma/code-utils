# code-utils
Continuous Delivery utilities - small scripts and concepts used by in continuous delivery setups.

Instead we all keep reinventing the same small concepts and scripts again and again we should share them.
This repository is for sharing all the small nice little scripts used on daily basis for continuous integrations, continous delivery, builds, artifact management or what-ever is needed for you to get the build and delivery pipeline up and running.

## Utils available

### Export version

Get a version, from some file, and export as environment variable and into other files.

TO be shared soon!

# Repository structure

Each little util should have a foot-print with a very short description here in the repository reade, but placed in it's own folder.

Within the folder of each util, there should be a readme explaing how to use, the use-case etc.

* Please make sure scripts are anonymized - no customer, or specific user details.

Folders might later be categorized in further levels.


# Contribution criterias

Right now - not so many, except from keeping the repository structure as above described.

Let's see how this evolves.

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

