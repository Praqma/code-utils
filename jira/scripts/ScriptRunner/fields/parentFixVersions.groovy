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
	Logger logger = Logger.getLogger("parent.FixVersions")
    IssueManager issueManager = ComponentAccessor.getIssueManager()
    
    IssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager()
    Issue parentIssue = findParent(issue, logger, issueLinkManager) as Issue
	logger.debug(parentIssue)

    parentIssue.getFixVersions()
} catch(Exception e){
    log.error(e)
}