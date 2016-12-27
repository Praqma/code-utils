# Jira filters

You have a good and re-useable filter, for a generic workflow? Share it here...

* Please put a few lines of use-case for the filter
* Post the filter itself
* Mention any dependencies, e.g. plugins needed

_The filters also serves as a good guideline on how to work in Jira as they follow many of our best-practices_.

## Assignee resolves, team members close

To help knowledge sharing and cross-functional team effort it can be a good idea to let team members close issue, after the assignee resolves them.
That way another team member get to read what was done. It also helps to get new ideas and future improvements this workflow, so often new follow-up issues with even better ideas can be created.

The following filter with find resolved issues withint the last 8 hours. Subscribe to th filter on daily basis, and when you get a mail go over the resolved issues to close those you didn't resolve yourself.

CICD issues latest resolved: `project = CICD AND status = Resolved AND resolved >= -8h AND status != Closed`

## You want to know everything?

If you truely want to know everything, here are all the issues you're not watching:

`project = CICD AND creator not in (myjirausername) AND reporter not in (myjirausername) AND assignee not in (myjirausername) AND statusCategory not in (Done) AND watcher not in (myjirausername)`

## Filters in filters

Tracking several filters in say one Kanban board, you can use filters in filter. But be carefull they tend to get really really slow:

`filter = "12679" OR filter = "12692" OR filter = "12832" OR labels in (CICD-debt) ORDER BY Rank`

## All epic tasks

This finds all tasks that have an epic assigned to them. Easy to get an overview, you can add columns in the view to see the epic.

`project = "CICD" AND component in ("CoDE") AND status not in (Closed, Resolved) AND "Epic link" != EMPTY ORDER BY "Epic Link"`

## Active cases

Once upon a time a project defined _active cases_ as cases in the CoDE component without epic link, or those with component CoDE but where there was an epic link and the epic in progress.
That allowed for omitting issues from epic not put in progress yet and do planning on epics wihout someone working on them.
The labels are to remove some general issues with special labels.

`(project = "CICD" AND component in ("CoDE") AND "Epic link" = EMPTY OR project = "CICD" AND component in ("CoDE") AND "Epic Link" != EMPTY AND issueFunction in linkedIssuesOf("issuetype = Epic AND status = \"In Progress\"")) AND status not in (Closed, Resolved) AND issueFunction not in issueFieldMatch("", labels, "CICD-*|assessment")`

## Ad-hoc work is issues without epics

If we define ad-hoc work, like support requests coming, as those issues not really planned thus not belonging to an epic they can be found with:

`project = "CICD" AND component = "CoDE" AND "Epic Link" = EMPTY AND statusCategory not in (Done) AND issueFunction not in issueFieldMatch("", labels, "CICD-*|assessment") AND issuetype not in (Epic) AND issueFunction not in linkedIssuesOf("issuetype = Epic")`

Some labels are not considered workable issues also, thus omitted.
