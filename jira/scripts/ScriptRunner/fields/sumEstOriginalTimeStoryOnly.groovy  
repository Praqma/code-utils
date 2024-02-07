import com.atlassian.jira.ComponentAccessor
import com.atlassian.jira.issue.CustomFieldManager
import com.atlassian.jira.component.ComponentAccessor;
import org.apache.log4j.Level
import org.apache.log4j.Logger

import com.atlassian.jira.issue.search.SearchProvider
import com.atlassian.jira.jql.parser.JqlQueryParser
import com.atlassian.jira.web.bean.PagerFilter

def issueLinkManager = ComponentAccessor.getIssueLinkManager()
def cfManager = ComponentAccessor.getCustomFieldManager()

Logger logger = Logger.getLogger("sacos.aggregate.estimation")
logger.setLevel(Level.ALL)

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
        logger.info("Issue link type: " + issueLink.issueLinkType.name + " : OK  : originalEstimate=" + origTime )
        totalOrigTime = origTime + totalOrigTime;
    } else {
        logger.info("Issue link type: " + issueLink.issueLinkType.name + " : -skip")
    }
}
logger.info("Total time estimate: " + totalOrigTime )

return totalOrigTime 


