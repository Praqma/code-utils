/*
 It's convenient to block transitioning epics to done when there are
 still stories and bugs that are not yet closed.

 Validators have the advantage that they don't hide the transition
 buttons, but yield a warning.

 The script can be used on a transition that goes into the Done state.
 It can easily be adapted to a condition as well. Please check
 examples under
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

Issue epic = issue as Issue  // in context

if(epic.getIssueType().getName() != "Epic"){
    return;
}

List<IssueLink> allOutIssueLink = issueLinkManager.getOutwardLinks(epic.getId())

allOutIssueLink.each { IssueLink it ->
    Issue linkedIssue 		= it.destinationObject
    Status status		= linkedIssue.getStatus()
    IssueLinkType issueLinkType	= it.getIssueLinkType()

    if(!["Rejected", "Done"].contains(status.getName()) && issueLinkType.getOutward() == "is Epic of"){
        throw new InvalidInputException("All stories and bugs in epic must be have status set to either Done or Rejected");
    }
}
