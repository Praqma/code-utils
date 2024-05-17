import com.atlassian.jira.ComponentAccessor
import com.atlassian.jira.issue.CustomFieldManager
import com.atlassian.jira.component.ComponentAccessor;
import org.apache.log4j.Level
import org.apache.log4j.Logger

import com.atlassian.jira.issue.search.SearchProvider
import com.atlassian.jira.jql.parser.JqlQueryParser
import com.atlassian.jira.web.bean.PagerFilter

import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueManager

IssueManager issueManager = ComponentAccessor.getIssueManager()
def issueLinkManager = ComponentAccessor.getIssueLinkManager()
def cfManager = ComponentAccessor.getCustomFieldManager()

Logger logger = Logger.getLogger("sacos.aggregate.estimation")
logger.setLevel(Level.ALL)

@com.onresolve.scriptrunner.parameters.annotation.ShortTextInput(description = "Enter Jira to execute the script on - leave empty for non-debug modes", label = "Jira Request Issue")
String jiraDebugIssue

logger.info("jiraDebugIssue=" + jiraDebugIssue)

//Issue issue
if ( jiraDebugIssue != null ){
	issue = issueManager.getIssueObject(jiraDebugIssue) // Add an issue for testing
	logger.setLevel(Level.ALL) // ALL, WARN
}


long totalOrigTime = 0
if (issue.getIssueTypeId() != "10000") {
    logger.info("Issue type is not executed on type: " + issue.getIssueType().getName())
    return null
} else {
    logger.info("Issue type is Epic - proceed: " + issue.getIssueType().getName())
}

issueLinkManager.getOutwardLinks(issue.id)?.each {issueLink ->
    if (issueLink.issueLinkType.name == "Epic-Story Link" ) {
		long origTime = issueLink.destinationObject.originalEstimate?:0
        if ( origTime != 0 ){ 
        	logger.info(issueLink.destinationObject.getIssueType().name + ": " + issueLink.destinationObject.getKey() + " : " + issueLink.issueLinkType.name + " : OK : originalEstimate=" + origTime )
        	totalOrigTime = origTime + totalOrigTime;
       	    logger.info("Aggregated : " + totalOrigTime )
		}
        issueLink.destinationObject.getSubTaskObjects()?.each { issueSubtask ->
			long origTimeSubtask = issueSubtask.originalEstimate?:0   
	        if ( origTimeSubtask != 0 ){ 
		        logger.info("Subtask: " + issueSubtask.getKey() + " : OK  : originalEstimate=" + origTimeSubtask )
        	    totalOrigTime = origTimeSubtask + totalOrigTime;
			    logger.info("Aggregated : " + totalOrigTime )
            }
        }
    } else {
        logger.info("Issue link type: " + issueLink.issueLinkType.name + " : -skip")
    }
    
}
logger.info("Total time estimate: " + totalOrigTime )

return totalOrigTime 


