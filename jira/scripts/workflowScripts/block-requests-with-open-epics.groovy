/*

 For a client, we created a new layer on top of the epics.  The
 parent-child (Hierarchy) link type is used to emulate this, in
 addition to configuring issue type schemes for the various projects.

 The script can also be used as a condition. Please see
 https://scriptrunner.adaptavist.com/5.9.1/jira/recipes/workflow/conditions.html
*/

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueManager
import com.atlassian.jira.issue.issuetype.IssueType
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.issue.link.IssueLinkType
import com.atlassian.jira.issue.status.Status
import com.opensymphony.workflow.InvalidInputException

IssueManager issueManager = ComponentAccessor.getIssueManager()
IssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager()

Issue request = issue as Issue  // Just in context

List<IssueLink> allOutIssueLink = issueLinkManager.getOutwardLinks(request.getId())

// some closures could simplify this

allOutIssueLink.each { IssueLink it ->
    Issue linkedIssue 		= it.destinationObject
    Status status		= linkedIssue.getStatus()
    IssueLinkType issueLinkType	= it.getIssueLinkType()

    if(!["Rejected", "Done"].contains(status.getName()) && linkedIssue.getIssueType().getName() == "Epic" && issueLinkType.getName() == "Hierarchy"){
        throw new InvalidInputException("All epics in Request must have either status in Done or Rejected");
    }
}
