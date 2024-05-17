import com.atlassian.jira.component.ComponentAccessor
import org.apache.log4j.Level
import org.apache.log4j.Logger
import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueImpl
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkImpl
import com.atlassian.jira.issue.link.DefaultIssueLinkManager
import com.atlassian.jira.issue.link.IssueLinkManager

import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.fields.ImmutableCustomField

Logger logger = Logger.getLogger("sacos.parent.Target products")
//logger.setLevel(Level.DEBUG)

//def issue = issue as Issue

DefaultIssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager() as DefaultIssueLinkManager
def customFieldManager = ComponentAccessor.getCustomFieldManager()
ImmutableCustomField custom_field = customFieldManager.getCustomFieldObjectByName("Target products") as ImmutableCustomField
logger.info(custom_field.fieldName)
ImmutableCustomField parentCustomField = customFieldManager.getCustomFieldObjectByName("Parent - ID") as ImmutableCustomField
logger.info(parentCustomField.fieldName)

try {
    customFieldManager.getCustomFieldObjects(issue)
    def issueManager = ComponentAccessor.getIssueManager()
    IssueImpl parentIssue = issueManager.getIssueObject(issue.getCustomFieldValue(parentCustomField).toString()) as IssueImpl
	logger.info(parentIssue)

    def value = parentIssue.getCustomFieldValue(custom_field)
    return value
} catch(Exception e){
    logger.error(e)
}