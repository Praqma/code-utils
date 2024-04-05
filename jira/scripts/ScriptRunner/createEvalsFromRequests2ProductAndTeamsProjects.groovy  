import com.atlassian.jira.issue.watchers.WatcherManager
import org.apache.log4j.Level
import org.apache.log4j.Logger
import org.apache.commons.collections.Closure
import com.atlassian.jira.issue.customfields.option.LazyLoadedOption
import com.atlassian.jira.project.Project
import com.atlassian.jira.project.ProjectManager
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.issue.customfields.manager.OptionsManager
import com.atlassian.jira.issue.Issue
import com.atlassian.jira.event.type.EventDispatchOption
import com.atlassian.jira.issue.IssueManager
import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.customfields.option.Option
import com.atlassian.jira.issue.CustomFieldManager
import com.atlassian.jira.issue.MutableIssue
import com.atlassian.jira.bc.issue.IssueService
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.IssueInputParameters
import com.atlassian.jira.user.ApplicationUser

// @com.onresolve.scriptrunner.parameters.annotation.ShortTextInput(description = "Enter Jira to execute the script on - leave empty for non-debug modes", label = "Jira Request Issue")
// String jiraDebugIssue

Logger logger = Logger.getLogger("sacos.s5k.evalcreate")
logger.setLevel(Level.ALL)

IssueService issueService = ComponentAccessor.getIssueService()
IssueManager issueManager = ComponentAccessor.getIssueManager()
IssueInputParameters issueInputParameters = issueService.newIssueInputParameters();
CustomFieldManager customFieldManager = ComponentAccessor.getCustomFieldManager()
ProjectManager projectManager = ComponentAccessor.getProjectManager()
WatcherManager watcherManager = ComponentAccessor.getWatcherManager()
IssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager()
OptionsManager optionsManager = ComponentAccessor.getOptionsManager()

/*
Issue issue // enable this line for editor to function correctly 
if ( jiraDebugIssue != "" ){
	issue = issueManager.getIssueObject(jiraDebugIssue) // Add an issue for testing
	logger.setLevel(Level.ALL) // ALL, WARN
}
*/

ApplicationUser user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()

if(issue.getIssueType().getName() != "Request"){
    return;
}

String evalIssueTypeId = 11500 // Eval Issue type
Long requestToEvalLinkTypeId = 10901 // Evaluates Link
Long requestCfEvalComponents = 12141 // "Eval Projects" Custom Field
Long requestCfEvaluator = 12131 // "Evaluator" Custom Field

CustomField cf_targetEvals = customFieldManager.getCustomFieldObject(requestCfEvalComponents)

// added by Claus+Mads 24th of September
CustomField cf_targetEvaluator = customFieldManager.getCustomFieldObject(requestCfEvaluator)

Collection<String> targetEvalJiraProjects = (Collection<String>)issue.getCustomFieldValue(cf_targetEvals)
targetEvalJiraProjects = targetEvalJiraProjects.collect { it -> it.toString() }

ApplicationUser evaluator = issue.getCustomFieldValue(cf_targetEvaluator) as ApplicationUser

// two convenient closures
def isProject(String key, IssueLink it) { 
    it.destinationObject.getProjectObject().getKey() == key
}

def isAlreadyLinked(IssueLink it, String linktype, Logger logger){
    if ( it.getIssueLinkType().getId() == linktype ){
    	logger.info(it.getDestinationObject().getIssueType().getName() + ": " + it.getIssueLinkType().getName()+ ": Ok" )
        return true
    } else {
       	logger.info(it.getDestinationObject().getIssueType().getName() + ": " + it.getIssueLinkType().getName()+ ": Skip" )
        return false
    }
}

def isAlreadyLinked(IssueLink it, long linktype ){
    it.getIssueLinkType().getName() == linktype
}

// already done links
List<String> alreadyDone = issueLinkManager.getOutwardLinks(issue.id).each { isAlreadyLinked(it,evalIssueTypeId,logger) }.collect { IssueLink it ->
	it.destinationObject.getProjectObject().getKey()
}.toList()
Set<String> relevantProjects = targetEvalJiraProjects.toSet().minus(alreadyDone.toSet())

Collection<Project> projects = relevantProjects.collect { String it -> projectManager.getProjectByCurrentKey(it) }
projects.each { Project project ->
    IssueService.IssueResult createResult;
    
    def exists = issueLinkManager.getOutwardLinks(issue.id).find { IssueLink it ->  
		isProject(project.getKey(), it) &&  isAlreadyLinked(it,evalIssueTypeId,logger)
    } != null

    if(!exists){
    	logger.info("creating")
        issueInputParameters
        	.setReporterId(user.username)
            .setProjectId(project.getId())
            .setSummary(issue.getSummary())
            .setDescription("Intentionally left empty, see Parent for details")
            .setIssueTypeId(issue.getIssueTypeId())
        	.setPriorityId(issue.getPriority().getId())
            .setIssueTypeId(evalIssueTypeId) // Eval

        // added by Claus+Mads 24th of September
        if(cf_targetEvaluator != null){
            issueInputParameters.setAssigneeId(evaluator.username)
        }
        
      	IssueService.CreateValidationResult createValidationResult = issueService.validateCreate(user, issueInputParameters)

        if (createValidationResult.isValid())
        {
            createResult = issueService.create(user, createValidationResult)

            if (!createResult.isValid())
            {
                log.error("Error while creating the issue.")
            } else {
                MutableIssue newIssue = createResult.getIssue() as MutableIssue
                // creating of link
            	logger.info("NewIssue: " + newIssue.getKey() + ": " + newIssue.getAssignee() + ": "+ newIssue.getSummary())
            	issueLinkManager.createIssueLink(newIssue.id, issue.id, requestToEvalLinkTypeId, 0, user);
                watcherManager.stopWatching(user, newIssue);
            }
        }
        else {
            log.error(createValidationResult.errorCollection);
        }
    }
}
