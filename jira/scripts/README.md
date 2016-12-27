# Overview

The scripts contained within this repository are intended to be used within Jira. There are both groovy scripts, 
which are dependent upon the [ScriptRunner](https://marketplace.atlassian.com/plugins/com.onresolve.jira.groovy.groovyrunner/server/overview)
 plugin, and other add-hoc scripts for administrative purposes. 

## Jira Scripts

These are Jira and Script Runner specific. 

They **could** be dependent upon a specific version of the ScriptRunner plugin. There is also the added complexity of the 
Jira version. As ScriptRunner provides access to Jira classes with [Groovy](http://www.groovy-lang.org/) this is also a dependency.


**NOTE:** These cannot be called production ready in any sense of the word. Use them as inspiration or a base for
getting started. Most of them were hacked together with the earlier free version(s) of ScriptRunner on a Jira 6.X.X version. 

### Workflow Scripts
The scripts can be ran from a file or embedded **INLINE** into the post-function, validation or conditions on a transition.

#### CloneAndLink.groovy And TransitionLinkedDefect.groovy 
**Use case**

A 1st line error management project and multiple 2nd line projects. Defects come into the 1st line project. 1st line
support verifies the defect and determine what 2nd line project(s) should handle it. 1st line support selects the project(s) from
 a multi-select list drop down and moves the issue to a status called awaiting action. A clone of the defect is generated
 into the selected project(s) and they are linked with a special link type for defects. 

The cloned defect is worked on in the 2nd line support team(s) and resolved. This triggers a transition in the 1st line project
 to a status "ready for test", if there are no other cloned defects not resolved.

* The assignee is set to the project lead of the Target Project.
* The summary is prepended with "CLONE of DEFECT KEY:", where key is the Key of the originating issue.
* The creation date is set to the date of creation.
* Links from Original issue are kept.
* Estimates and time spent are zeroed out on cloned issue.

##### How to use

* The Clone and link script is applied in 1st line support project.
* The Transition linked defect script is applied in all applicable 2nd line support projects.

**NOTE:** User permissions across the projects must be correct. There is a lot of hardcoded stuff in the scripts which will
need to be cleaned up.

#### OriginalEstimateValidation.groovy
The purpose of this script is to ensure sub-tasks Original Estimate field has a value.

##### How to use
Use this script as a validator on a transition and give an error message so the user knows why.

### JQL Scripts
Script runner provides a way to code JQL queries in scripts. That way we can do queries which are difficult, complex or
impossible with the standard query formats. These scripts must be ran from the file system. Script Runner provides a
script root under JIRA_HOME/scripts.

#### MismatchedThemes.groovy
The use case is trying to create a hierarchy of Theme->Epic->Story with Jira links. The idea being that Epics and Story's
  belong to a Theme. 

Purpose is to find all User Stories that have a linked "Theme" issue type where the Epic of the linked Theme is
**different** than the Epic of the User Story. If the either the User Story or the linked Themes has an Epic Link and the
other does not then this is seen as a mismatch.

##### How to use

* hasEpicMismatchWithTheme(): This will return an error as there are no quotation marks ("") and thus no query.
* hasEpicMismatchWithTheme(""): This will search all issues.
* hasEpicMismatchWithTheme("project = CP"): This will return stories for a specific project.

### Scripted Fields
Script Runner allows you to create custom fields based on a groovy script. These fields are **NON** editable and are 
calculated.

#### LastComment.groovy
Use case is showing the last comment of an issue from a JQL search. 

#### TimeSpentAsHours.groovy
Very simple script to calculate value in hours. Jira stores these values in milliseconds and presents them according 
to wishes, ie. hours, minutes, etc. The exports to word and xml will use the default estimation set in global 
configuration. The excel export does not do this :-( Therefor we need a scripted field to be used as a column for JQL searches.

## Other
Any other types of scripts that has to do with Jira.

### SQL 
SQL snippets for working with Jira's database. 
