import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueImpl
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkImpl
import com.atlassian.jira.issue.link.DefaultIssueLinkManager
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.component.ComponentAccessor

import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.fields.ImmutableCustomField

def issue = issue as Issue

DefaultIssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager() as DefaultIssueLinkManager
def customFieldManager = ComponentAccessor.getCustomFieldManager()
ImmutableCustomField engine_type = customFieldManager.getCustomFieldObjectByName("Engine Type") as ImmutableCustomField
ImmutableCustomField requirementCustomField = customFieldManager.getCustomFieldObjectByName("Parent - ID") as ImmutableCustomField

try {
    customFieldManager.getCustomFieldObjects(issue)

    def requirement = issue.getCustomFieldValue(requirementCustomField)

    def issueManager = ComponentAccessor.getIssueManager()
    IssueImpl requirementIssue = issueManager.getIssueObject(requirement.toString()) as IssueImpl

    def engine_type_value = requirementIssue.getCustomFieldValue(engine_type)
    engine_type_value
} catch(Exception e){
    null
}