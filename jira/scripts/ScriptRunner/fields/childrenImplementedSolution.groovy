import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.IssueManager
import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueImpl
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkImpl
import com.atlassian.jira.issue.link.DefaultIssueLinkManager
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.component.ComponentAccessor

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.RendererManager
import com.atlassian.jira.issue.fields.renderer.IssueRenderContext
import com.atlassian.jira.issue.fields.renderer.wiki.AtlassianWikiRenderer

DefaultIssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager() as DefaultIssueLinkManager
def customFieldManager = ComponentAccessor.getCustomFieldManager()

def rendererManager = ComponentAccessor.getComponent(RendererManager)
def renderContext = new IssueRenderContext(issue)

def EPIC_STORY_LINK = "Epic-Story Link"

try {
	CustomField implementedSolutionCf = customFieldManager.getCustomFieldObjectsByName("Implemented solution")[0]

    def stories = issueLinkManager.getOutwardLinks(issue.id).findAll {
       it.issueLinkType.name == EPIC_STORY_LINK
    }

    def table = """| *Story*   | *Implemented Solution* |
"""
    def implSolutionMap = stories.collectEntries { IssueLink it ->
    	[it.getDestinationObject().key, it.getDestinationObject().getCustomFieldValue(implementedSolutionCf)]
    }
    if(implSolutionMap.keySet().size() > 0){
        for (entry in implSolutionMap) {
            def value = entry?.value?.replaceAll("\n", "* ")
            table = table.concat("""|${entry.key} | * ${value} |
""")
        }
    }
    
    rendererManager.getRenderedContent(AtlassianWikiRenderer.RENDERER_TYPE, table, renderContext)
} catch(Exception e){
    e
}
