import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueImpl
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkImpl
import com.atlassian.jira.issue.link.DefaultIssueLinkManager
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.component.ComponentAccessor

import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.fields.ImmutableCustomField

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.RendererManager
import com.atlassian.jira.issue.fields.renderer.IssueRenderContext
import com.atlassian.jira.issue.fields.renderer.wiki.AtlassianWikiRenderer

def issue = issue as Issue

DefaultIssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager() as DefaultIssueLinkManager
def customFieldManager = ComponentAccessor.getCustomFieldManager()
ImmutableCustomField custom_field = customFieldManager.getCustomFieldObjectByName("Accounting") as ImmutableCustomField
ImmutableCustomField requirementCustomField = customFieldManager.getCustomFieldObjectByName("Parent - ID") as ImmutableCustomField

def rendererManager = ComponentAccessor.getComponent(RendererManager)
def renderContext = new IssueRenderContext(issue)
def commentManager = ComponentAccessor.commentManager

try {
    customFieldManager.getCustomFieldObjects(issue)
    def requirement = issue.getCustomFieldValue(requirementCustomField)

    def issueManager = ComponentAccessor.getIssueManager()
    IssueImpl requirementIssue = issueManager.getIssueObject(requirement.toString()) as IssueImpl

    def value = requirementIssue.getDescription()

	if (value) {
	    rendererManager.getRenderedContent(AtlassianWikiRenderer.RENDERER_TYPE, value, renderContext)
    }

} catch(Exception e){
    null
}
