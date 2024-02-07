import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueManager
import com.atlassian.jira.issue.issuetype.IssueType
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.issue.link.IssueLinkType
import com.atlassian.jira.issue.status.Status
import com.atlassian.jira.user.ApplicationUser
import com.opensymphony.workflow.InvalidInputException

IssueManager issueManager = ComponentAccessor.getIssueManager()
ApplicationUser user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()
IssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager()

Issue epic = issue as Issue

List<IssueLink> allOutIssueLink = issueLinkManager.getOutwardLinks(epic.getId())

allOutIssueLink.each { IssueLink it -> 
	Issue linkedIssue 			= it.destinationObject
	Status status				= linkedIssue.getStatus()
	IssueLinkType issueLinkType	= it.getIssueLinkType()

    if(!["Rejected", "Done"].contains(status.getName()) && issueLinkType.getOutward() == "is Epic of"){
        throw new InvalidInputException("All stories and bugs in epic must be either Rejected or Done");
    }
}
