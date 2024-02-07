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
import com.atlassian.jira.bc.project.component.ProjectComponent


Logger logger = Logger.getLogger("sacos.s5k.createEpics")
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

@com.onresolve.scriptrunner.parameters.annotation.ShortTextInput(description = "Enter Jira to execute the script on - leave empty for non-debug modes", label = "Jira Request Issue")
String jiraDebugIssue

logger.info("jiraDebugIssue=" + jiraDebugIssue)

//Issue issue
if ( jiraDebugIssue != null ){
	issue = issueManager.getIssueObject(jiraDebugIssue) // Add an issue for testing
	logger.setLevel(Level.ALL) // ALL, WARN
}
ApplicationUser user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()

if(issue.getIssueType().getName() != "Request"){
    return;
}

CustomField cf_targetProducts = customFieldManager.getCustomFieldObject(12121) // "Target products"
Collection<String> targetProducts = (Collection<String>)issue.getCustomFieldValue(cf_targetProducts)
targetProducts = targetProducts.collect { it -> it.toString() }
logger.info("Target products: " + targetProducts )

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

CustomField cf_ewh = customFieldManager.getCustomFieldObject(12154) // Expected Work Hours
CustomField cf_ec = customFieldManager.getCustomFieldObject(12112) // Expected Cost

// Expected Work Hours
logger.warn(cf_ewh)
def fieldConfig_ewh = cf_ewh.getRelevantConfig(issue)
def option_ewh = optionsManager.getOptions(fieldConfig_ewh).getOptionForValue((String)issue.getCustomFieldValue(cf_ewh), null)

List<Option> options_ewh = optionsManager.findByOptionValue((String)issue.getCustomFieldValue(cf_ewh));
CustomField customField_ewh = option_ewh.getRelatedCustomField().getCustomField();

// Expected Cost
def fieldConfig_ec = cf_ec.getRelevantConfig(issue)
def option_ec = optionsManager.getOptions(fieldConfig_ec).getOptionForValue((String)issue.getCustomFieldValue(cf_ec), null)

List<Option> options_ec = optionsManager.findByOptionValue((String)issue.getCustomFieldValue(cf_ec));
CustomField customField_ec = option_ec.getRelatedCustomField().getCustomField();

logger.info(issue.key)
Collection<String> requestComponents = issue.getComponents().collect { ProjectComponent component ->  
    logger.info("Source project component names: ${component.getName()}" )
	component.getName() 
}

Collection<Project> projects = relevantProjects.collect { String it -> projectManager.getProjectByCurrentKey(it) }

projects.each { Project project ->
    logger.info("Target project name-ID: ${project.getName()} (${project.getKey()}) internal ID: ${project.getId()}")
    Long[] thisProjectCompIds = requestComponents.collect { String compString ->  
           projectComponentManager.findByComponentName(project.getId(),compString).getId()
    } as Long[]
    logger.info("Target project: ComponentID " + thisProjectCompIds.collect{ Long it -> it})    
    
       
    IssueService.IssueResult createResult;
    
    def exists = issueLinkManager.getOutwardLinks(issue.id).find { IssueLink it ->  
		isProject(project.getKey(), it) && isChildParentLink(it)
    } != null

    if(!exists){
    	log.info("creating")
        issueInputParameters
            .setProjectId(project.getId())
            .setSummary("[" + project.getKey() + "] " + issue.getSummary())
            .setReporterId(issue.getReporter().username)
            .setIssueTypeId(issue.getIssueTypeId())
            .setDescription("Intentionally left empty, see Parent for details")
            .setComponentIds(thisProjectCompIds)
            .addCustomFieldValue(12129, "-") // Accounting
            .addCustomFieldValue(10002, "[" + project.getKey() + "] " + issue.getSummary() ) // Epic Name
            .setPriorityId(issue.getPriority().getId())
            .setIssueTypeId("10000") // Epic
            .addCustomFieldValue(customField_ewh.getId(), "" + option_ewh.getOptionId())
        	.addCustomFieldValue(customField_ec.getId(), "" + option_ec.getOptionId())
        
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
                issueLinkManager.createIssueLink(issue.id, newIssue.id, 10900, 0, user) // Hierarchy
                watcherManager.stopWatching(user, newIssue);
            }
        }
        else {
            log.error(createValidationResult.errorCollection);
        }
    }
}
