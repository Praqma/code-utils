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
//import com.atlassian.jira.issue.RendererManager
//import com.atlassian.jira.issue.fields.renderer.IssueRenderContext
//import com.atlassian.jira.issue.fields.renderer.wiki.AtlassianWikiRenderer

IssueManager issueManager = ComponentAccessor.getIssueManager()

@com.onresolve.scriptrunner.parameters.annotation.ShortTextInput(description = "Enter Jira to execute the script on - leave empty for non-debug modes", label = "Jira Request Issue")
String jiraDebugIssue

Logger logger = Logger.getLogger("parent.parentSiblings")

logger.info("jiraDebugIssue=" + jiraDebugIssue)

//Issue issue
if ( jiraDebugIssue != null ){
	issue = issueManager.getIssueObject(jiraDebugIssue) // Add an issue for testing
	logger.setLevel(Level.ALL) // ALL, WARN
}



def findParent(Issue issue, Logger logger, IssueLinkManager issueLinkManager){
    if(issue.subTask){
        logger.info("Issue link type subtask - next: " + issue.subTask )
        return findParent(issue.getParentObject(), logger, issueLinkManager)
    }
    for(IssueLink issueLink : issueLinkManager.getInwardLinks(issue.id)){
        if (issueLink.issueLinkType.name == "Epic-Story Link" ) {
            logger.info("Issue link type E: " + issueLink.issueLinkType.name + " : " + issueLink.getSourceObject().getKey())
            return issueLink.getSourceObject()
        }
    }
}

try {
    
    IssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager()
    Issue parentIssue = findParent(issue, logger, issueLinkManager) as Issue
    Issue parentIssueNotNull
    if ( parentIssue ) {
        parentIssueNotNull=parentIssue
    	logger.info("Returned: " +  parentIssueNotNull)
    } else {
        logger.info("Returned null: " +  parentIssueNotNull)
    }

    def customFieldManager = ComponentAccessor.getCustomFieldManager()
    ImmutableCustomField siblings_cf = customFieldManager.getCustomFieldObjectsByName("Siblings")[0] as ImmutableCustomField
    def value
    if ( parentIssueNotNull ) {
        value = parentIssueNotNull.getCustomFieldValue(siblings_cf)
        logger.info("value: " +  value) 
        if (value) {
            value
            /*
            // It is already rendered in parent: 
            def rendererManager = ComponentAccessor.getComponent(RendererManager)
            def renderContext = new IssueRenderContext(issue)
            rendererManager.getRenderedContent(AtlassianWikiRenderer.RENDERER_TYPE, value, renderContext)
            */
        }
    }

} catch(Exception e){
    log.error(e)
}
