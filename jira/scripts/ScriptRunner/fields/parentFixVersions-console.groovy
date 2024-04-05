import org.apache.log4j.Level
import org.apache.log4j.Logger

import com.atlassian.jira.issue.IssueManager
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueImpl
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkImpl
import com.atlassian.jira.issue.link.DefaultIssueLinkManager
import com.atlassian.jira.issue.link.IssueLinkManager

import com.atlassian.jira.project.version.Version

import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.fields.ImmutableCustomField

IssueManager issueManager = ComponentAccessor.getIssueManager()
IssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager()
def projectComponentManager = ComponentAccessor.getProjectComponentManager()

@com.onresolve.scriptrunner.parameters.annotation.ShortTextInput(description = "Enter Jira to execute the script on - leave empty for non-debug modes", label = "Jira Request Issue")
String jiraDebugIssue

Logger logger = Logger.getLogger("parent.FixVersions")

logger.info("jiraDebugIssue=" + jiraDebugIssue)

//Issue issue
if ( jiraDebugIssue != null ){
	issue = issueManager.getIssueObject(jiraDebugIssue) // Add an issue for testing
	logger.setLevel(Level.ALL) // ALL, WARN
}


def findParent(Issue issue, Logger logger, IssueLinkManager issueLinkManager){
    if(issue.subTask){
        return findParent(issue.getParentObject(), logger, issueLinkManager)
    }
    for(IssueLink issueLink : issueLinkManager.getInwardLinks(issue.id)){
        if (issueLink.issueLinkType.name == "Epic-Story Link" ) {
            logger.debug("Issue link type: " + issueLink.issueLinkType.name + " : " + issueLink.getSourceObject().getKey())
            return issueLink.getSourceObject()
        } 
    }
}

try {
    Issue parentIssue = findParent(issue, logger, issueLinkManager) as Issue
	logger.debug(parentIssue)

    parentIssue.getFixVersions()
} catch(Exception e){
    log.error(e)
}