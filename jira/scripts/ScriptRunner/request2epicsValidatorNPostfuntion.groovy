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
import com.atlassian.jira.issue.fields.config.FieldConfigImpl
import com.opensymphony.workflow.InvalidInputException
//import com.onresolve.scriptrunner.parameters.annotation.*
//import com.onresolve.scriptrunner.parameters.annotation.meta.Option

@com.onresolve.scriptrunner.parameters.annotation.ShortTextInput(description = "Enter Jira to execute the script on - leave empty for non-debug modes", label = "Jira Request Issue")
String jiraDebugIssue

@com.onresolve.scriptrunner.parameters.annotation.Select(
    description = "Select mode of execution: validation or creation",
    label = "Select execution type",
    options =
        [
            @com.onresolve.scriptrunner.parameters.annotation.meta.Option(label = "Validator", value = "validator"),
            @com.onresolve.scriptrunner.parameters.annotation.meta.Option(label = "Post function", value = "postfunction")
        ]
)
String selectedExecutionMode


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

//logger.setLevel(Level.WARN) // ALL, WARN
//Issue issue // enable this line for editor to function correctly 
if ( jiraDebugIssue != "" ){
//	issue = issueManager.getIssueObject(jiraDebugIssue) // Add an issue for testing
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
        // customFieldManager.getCustomFieldObject(11700).getName() It should have been in context of the scripted field, but
        // does not work. Removing context with make it global on the screen
        throw new InvalidInputException("The desired project key: ${projectKeyString} cannot be found. Please investigate." )
    }
}

Collection<Project> projects = relevantProjects.collect { String projectKeyString -> 
    projectManager.getProjectByCurrentKey(projectKeyString) 
}

Collection<String> requestComponents = issue.getComponents().collect { ProjectComponent component ->  
    logger.info("Source project component names: ${component.getName()}" )
	component.getName() 
}

CustomField cf_ewh = customFieldManager.getCustomFieldObject(12154) // Expected Work Hours
CustomField cf_ec = customFieldManager.getCustomFieldObject(12112) // Expected Cost

// Expected Work Hours
FieldConfigImpl fieldConfig_ewh = (FieldConfigImpl)cf_ewh.getRelevantConfig(issue)
Option option_ewh = optionsManager.getOptions(fieldConfig_ewh).getOptionForValue((String)issue.getCustomFieldValue(cf_ewh), null)

List<Option> options_ewh = optionsManager.findByOptionValue((String)issue.getCustomFieldValue(cf_ewh))
CustomField customField_ewh = option_ewh.getRelatedCustomField().getCustomField()

// Expected Cost
FieldConfigImpl fieldConfig_ec = (FieldConfigImpl)cf_ec.getRelevantConfig(issue)
Option option_ec = optionsManager.getOptions(fieldConfig_ec).getOptionForValue((String)issue.getCustomFieldValue(cf_ec), null)

List<Option> options_ec = optionsManager.findByOptionValue((String)issue.getCustomFieldValue(cf_ec))
CustomField customField_ec = option_ec.getRelatedCustomField().getCustomField();


projects.each { Project project ->
	
    logger.info("Target project name-ID: ${project.getName()} (${project.getKey()}) internal ID: ${project.getId()}")
    requestComponents.collect { String compString ->  
        try {
            projectComponentManager.findByComponentName(project.getId(),compString).getId()
            logger.info("Target project component name: ${compString} " + projectComponentManager.findByComponentName(project.getId(),compString).getId())
        } catch (Exception e) {
            throw new InvalidInputException(IssueFieldConstants.COMPONENTS, "The desired component ${compString} cannot be found in project: ${project.getName()}(${project.getKey()}). Please investigate." )
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
        logger.info(issue.getReporter().username ) 
        issueInputParameters
            .setProjectId(project.getId())
            .setSummary(issue.getSummary())
            .setReporterId(issue.getReporter().username)
            .setIssueTypeId(issue.getIssueTypeId())
        	.setDescription("Intentionally left empty, see Parent for details")
        	.setComponentIds(thisProjectCompIds)
            .setPriorityId(issue.getPriority().getId())
            .setIssueTypeId("10000") // Epic
            .addCustomFieldValue(10002, issue.getSummary()) // Epic Name
            .addCustomFieldValue(12129, "-") // Accounting Custom Field
            .addCustomFieldValue(customField_ewh.getId(), "" + option_ewh.getOptionId())
        	.addCustomFieldValue(customField_ec.getId(), "" + option_ec.getOptionId())
        
    	IssueService.CreateValidationResult createValidationResult = issueService.validateCreate(user, issueInputParameters)
         if ( ! createValidationResult.warningCollection.getWarnings().isEmpty() )
        	logger.warn("WARN: " + createValidationResult.warningCollection.getWarnings() )
        logger.info( createValidationResult.getIssue()?.getComponents() )
		Collection<Long> cp_output = createValidationResult.getIssue()?.getComponents().collect{ ProjectComponent pc -> pc.getId() }
        
        logger.info( cp_output )
        logger.info( thisProjectCompIds.collect{ Long it -> it} )

        if (  ! thisProjectCompIds.collect{ Long it -> it}.containsAll( cp_output ) ) {  
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
                    issueLinkManager.createIssueLink(issue.id, newIssue.id, 10900, 0, user) // Link 'Hierarchy' 
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