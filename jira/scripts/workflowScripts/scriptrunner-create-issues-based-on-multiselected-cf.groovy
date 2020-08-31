import com.atlassian.jira.bc.project.component.ProjectComponent
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
def projectComponentManager = ComponentAccessor.getProjectComponentManager()
ApplicationUser user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()

def issue = issueManager.getIssueObject('SACOS-255')

Project project = projectManager.getProjectByCurrentKey("SACEVAL")
String evalIssueTypeId = 10201
Long requestToEvalLinkTypeId = 10000 // Blocks
Long requestCfEvalComponents = 12200 // "Eval components"

if(issue.getIssueType().getName() != "Request"){
    logger.info("Issue type is not executed on type Request: " + issue.getIssueType().getName())
    return;
}

CustomField cf_targetEvals = customFieldManager.getCustomFieldObject(requestCfEvalComponents)
Collection<String> targetEvals = (Collection<String>)issue.getCustomFieldValue(cf_targetEvals)
targetEvals = targetEvals.collect { it -> it.toString() }

// two convenient closures
def isProject(String key, IssueLink it) { 
    it.destinationObject.getProjectObject().getKey() == key
}

def isEvaluationTypeBlocksLink(IssueLink it, String evalIssueTypeId, Long requestToEvalLinkTypeId, Logger logger){
    if ( it.getDestinationObject().getIssueType().getId() == evalIssueTypeId && it.getIssueLinkType().getId() == requestToEvalLinkTypeId ){
    	logger.info(it.getDestinationObject().getIssueType().getName() + ": " + it.getIssueLinkType().getName()+ ": Ok" )
        return true
    } else {
       	logger.info(it.getDestinationObject().getIssueType().getName() + ": " + it.getIssueLinkType().getName()+ ": Skip" )
        return false
    }
}
 
logger.info(issue.key)
List<String> alreadyCreated = issueLinkManager.getOutwardLinks(issue.id).each {  isEvaluationTypeBlocksLink(it, evalIssueTypeId, requestToEvalLinkTypeId, logger) }.collect { IssueLink it ->  
    it.destinationObject?.getComponents().collect { 
        ProjectComponent pc -> pc.getName()
    }
}.flatten() as List<String>

logger.info("Target Evals: " + targetEvals.toSet())
logger.info("Already Evals: " + alreadyCreated.toSet())
Set<String> relevantEvals = targetEvals.toSet().minus(alreadyCreated.toSet())
logger.info("Missing Evals: " + relevantEvals)

relevantEvals.each { String evalComponent ->
    IssueService.IssueResult createResult;
    
    ProjectComponent componentName = projectComponentManager.findByComponentName(project.getId(), evalComponent)
    String summary = "[" + evalComponent + "] " + issue.getSummary()
        
    issueInputParameters
        .setProjectId(project.getId())
        .setSummary(summary)
        .setReporterId(issue.getReporterId())
        .setDescription("Intentionally left empty, see Parent for details")
        .setPriorityId(issue.getPriority().getId())
        .setIssueTypeId(evalIssueTypeId)
        .setComponentIds(componentName.getId())

    IssueService.CreateValidationResult createValidationResult = issueService.validateCreate(user, issueInputParameters)

    if (createValidationResult.isValid())
    {
        createResult = issueService.create(user, createValidationResult)

        if (!createResult.isValid())
        {
            log.error("Error while creating the issue.")
        } else {
            MutableIssue newIssue = createResult.getIssue() as MutableIssue
            // child/parent of link
            logger.info("NewIssue: " + newIssue.getKey() + ": " + newIssue.getAssignee() + ": "+ newIssue.getSummary())
            issueLinkManager.createIssueLink(issue.id, newIssue.id, requestToEvalLinkTypeId, 0, user) 
            watcherManager.stopWatching(user, newIssue);
            
        }
    }
    else {
        log.error(createValidationResult.errorCollection);
    }
}
