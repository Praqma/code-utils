import com.atlassian.jira.component.ComponentAccessor

import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueImpl
import com.atlassian.jira.issue.RendererManager

import com.atlassian.jira.issue.fields.renderer.IssueRenderContext
import com.atlassian.jira.issue.fields.renderer.wiki.AtlassianWikiRenderer

import com.atlassian.jira.issue.link.DefaultIssueLinkManager
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkImpl
import com.atlassian.jira.issue.link.IssueLinkManager

import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.fields.ImmutableCustomField

try {
    DefaultIssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager() as DefaultIssueLinkManager
    def customFieldManager = ComponentAccessor.getCustomFieldManager()
    ImmutableCustomField requirementCustomField = customFieldManager.getCustomFieldObjectsByName("Parent - ID")[0] as ImmutableCustomField

    def rendererManager = ComponentAccessor.getComponent(RendererManager)
    def renderContext = new IssueRenderContext(issue)
    def commentManager = ComponentAccessor.commentManager
    def comment = commentManager.getLastComment(issue)
    
    def requirement = issue.getCustomFieldValue(requirementCustomField)

    def issueManager = ComponentAccessor.getIssueManager()
    IssueImpl requirementIssue = issueManager.getIssueObject(requirement.toString()) as IssueImpl

    def links = issueLinkManager.getOutwardLinks(requirementIssue.getId())
    def linksMarkdown = links.findAll({
        IssueLink it -> it.destinationObject.key != issue.key
    }).collect({ 
    	IssueLink it -> "[" + it.destinationObject.key + "] *Status*: " + 
            it.destinationObject.getStatus().getName() + " *Fix version(s)*: " + 
            it.destinationObject.getFixVersions().join(", ") +
            "\n"
    }).join(" ")
    
    if (linksMarkdown) {
        rendererManager.getRenderedContent(AtlassianWikiRenderer.RENDERER_TYPE, linksMarkdown, renderContext)
    }
} catch(Exception e){
    null
}