import com.atlassian.jira.bc.project.component.ProjectComponentManager
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
import com.atlassian.jira.issue.IssueFieldConstants
import com.opensymphony.workflow.InvalidInputException
import com.onresolve.scriptrunner.parameters.annotation.*
import com.onresolve.scriptrunner.parameters.annotation.meta.Option

@ShortTextInput(description = "Enter Jira to execute the script on - leave empty for non-debug modes", label = "Jira Request Issue")
String jiraDebugIssue

@Select(
    description = "Select mode of execution: validation or creation",
    label = "Select execution type",
    options =
        [
            @Option(label = "Validator", value = "validator"),
            @Option(label = "Post function", value = "postfunction")
        ]
)
String selectedExecutionMode
if ( selectedExecutionMode == "" ){
	selectedExecutionMode = "validator"  // "postfunction" 
}

Logger logger = Logger.getLogger("request2epic."+ selectedExecutionMode)
logger.info("selectedExecutionMode: ${selectedExecutionMode}")

IssueService issueService = ComponentAccessor.getIssueService()
IssueManager issueManager = ComponentAccessor.getIssueManager()
IssueInputParameters issueInputParameters = issueService.newIssueInputParameters();
CustomFieldManager customFieldManager = ComponentAccessor.getCustomFieldManager()
ProjectManager projectManager = ComponentAccessor.getProjectManager()
WatcherManager watcherManager = ComponentAccessor.getWatcherManager()
IssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager()
OptionsManager optionsManager = ComponentAccessor.getOptionsManager()
ProjectComponentManager projectComponentManager = ComponentAccessor.getProjectComponentManager()

ApplicationUser user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()

logger.setLevel(Level.WARN) // ALL, WARN
Issue issue
if ( jiraDebugIssue != "" ){
	issue = issueManager.getIssueObject(jiraDebugIssue) // Add an issue for testing
	logger.setLevel(Level.ALL) // ALL, WARN
}
if(issue.getIssueType().getName() != "Request"){
    return;
}

CustomField cf_targetProducts = customFieldManager.getCustomFieldObject(12121) // "Target Products"
Collection<String> targetProducts = (Collection<String>)issue.getCustomFieldValue(cf_targetProducts)
targetProducts = targetProducts.collect { it -> it.toString() }

Collection<String> target = targetProducts.collect { it -> it.toString() }

// two convenient closures
def isProject(String key, IssueLink it) { 
    it.destinationObject.getProjectObject().getKey() == key
}

def isChildParentLink(IssueLink it){
    it.getIssueLinkType().getName() == "Hierarchy"
}

// already done links
List<String> alreadyDone = issueLinkManager.getOutwardLinks(issue.id).each { isChildParentLink(it) }.collect { IssueLink it ->
	it.destinationObject.getProjectObject().getKey()
}.toList()
Set<String> relevantProjects = targetProducts.toSet().minus(alreadyDone.toSet())

relevantProjects.collect { String projectKeyString -> 
    logger.info("Finding project with string: ${projectKeyString}") 
    Project p = projectManager.getProjectByCurrentKey(projectKeyString)
    if ( p == null ){
        throw new InvalidInputException(customFieldManager.getCustomFieldObject(12121).getName(), "The desired project key: ${projectKeyString} cannot be found. Please investigate." ) // "Target Products"
    }
}

Collection<Project> projects = relevantProjects.collect { String projectKeyString -> 
    projectManager.getProjectByCurrentKey(projectKeyString) 
}

Collection<String> requestComponents = issue.getComponents().collect { ProjectComponent component ->  
    logger.info("Source project component names: ${component.getName()}" )
	component.getName() 
}

projects.each { Project project ->
	
    logger.info("Target project name-ID: " + project.getName() + "-" + project.getId())
    requestComponents.collect { String compString ->  
        try {
            projectComponentManager.findByComponentName(project.getId(),compString).getId()
            logger.info("Target project component name: ${compString} " + projectComponentManager.findByComponentName(project.getId(),compString).getId())
        } catch (Exception e) {
            throw new InvalidInputException(IssueFieldConstants.COMPONENTS, "The desired component ${compString} cannot be found in project: ${project}. Please investigate." + e )
        }
    }
    Long[] thisProjectCompIds = requestComponents.collect { String compString ->  
           projectComponentManager.findByComponentName(project.getId(),compString).getId()
    } as Long[]
    logger.info("Target project: ComponentID " + thisProjectCompIds.collect{ Long it -> it})
    IssueService.IssueResult createResult;
    
    def exists = issueLinkManager.getOutwardLinks(issue.id).find { IssueLink it ->  
		isProject(project.getKey(), it) && isChildParentLink(it)
    } != null

    if(!exists){
    	logger.info("validating")
        issueInputParameters
            .setProjectId(project.getId())
            .setSummary(issue.getSummary())
            .setReporterId(issue.getReporterId())
            .setIssueTypeId(issue.getIssueTypeId())
        	.setDescription("Intentionally left empty, see Parent for details")
        	.setComponentIds(thisProjectCompIds)
            .setPriorityId(issue.getPriority().getId())
            .setIssueTypeId("10000") // Epic
            .addCustomFieldValue(10002, issue.getSummary()) // Epic Name
        
    	IssueService.CreateValidationResult createValidationResult = issueService.validateCreate(user, issueInputParameters)
         if ( ! createValidationResult.warningCollection.getWarnings().isEmpty() )
        	logger.warn("WARN: " + createValidationResult.warningCollection.getWarnings() )
        logger.info( createValidationResult.getIssue().getComponents() )
		Collection<Long> cp_output = createValidationResult.getIssue()?.getComponents().collect{ ProjectComponent pc -> pc.getId() }

        if ( thisProjectCompIds.collect{ Long it -> it}.containsAll( cp_output ) ) {  
        	throw new InvalidInputException(IssueFieldConstants.COMPONENTS, "The desired component list does match the new issue component list. Is the 'component(s)' field part of the Create screen of project: ${project.key}. Please investigate." )
        }
        if (!createValidationResult.isValid()) {
			log.error(createValidationResult.errorCollection);
			throw new InvalidInputException(IssueFieldConstants.COMPONENTS, "Unknown issue validating fields for Epic creating in project: ${project.key}. Please investigate." )
        } else {
            if ( selectedExecutionMode == "postfunction" ){
                /*
                / BEGIN: ONLY RELAVANT FOR POST FUNTION
                */
                logger.info("Creating")
                createResult = issueService.create(user, createValidationResult)

                if (!createResult.isValid())
                {
                    logger.error("Error while creating the issue.")
                } else {
                    MutableIssue newIssue = createResult.getIssue() as MutableIssue
                    logger.info("Creating parent relationship")
                    issueLinkManager.createIssueLink(issue.id, newIssue.id, 10900, 0, user) // Hierarchy
                    logger.info("Remove ${user} watching of new issue")
                    watcherManager.stopWatching(user, newIssue);
                }
                /*
                / END: ONLY RELAVANT FOR POST FUNTION
                */
            }
        }
    }
}
