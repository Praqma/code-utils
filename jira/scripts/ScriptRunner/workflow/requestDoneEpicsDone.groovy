import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.workflow.TransitionOptions

// the name of the action you want to move the issue to
final actionName = 'Close'

//Name of the resolution children issues should have
final resolutionName = 'Done'

// the name of the issue link
final issueLinkName = ''

def workflow = ComponentAccessor.workflowManager.getWorkflow(issue)
def actionId = workflow.allActions.findByName(actionName)?.id
def linkManager = ComponentAccessor.issueLinkManager

def epicIssue = linkManager.getInwardLinks(issue.id).find { it.issueLinkType.name == issueLinkName }?.sourceObject
if (!epicIssue) {
    return
}

// Find all the linked - with the "Epic-Story Link" link - issues that their status is not the same as resolutionName

def linkedIssues = linkManager
    .getOutwardLinks(epicIssue.id)
    .findAll { it.issueLinkType.name == issueLinkName }
    *.destinationObject?.findAll { it.resolution?.name != resolutionName }

// If there are still open linked issues (except the one in transition) - then do nothing

if (linkedIssues - issue) {
    return
}

def issueService = ComponentAccessor.issueService
def inputParameters = issueService.newIssueInputParameters()

inputParameters.setComment('This Epic closed automatically because all the issues in this Epic are closed.')
inputParameters.setSkipScreenCheck(true)

def transitionOptions = new TransitionOptions.Builder()
    .skipConditions()
    .skipPermissions()
    .skipValidators()
    .build()

def loggedInUser = ComponentAccessor.jiraAuthenticationContext.loggedInUser
def transitionValidationResult = issueService.validateTransition(loggedInUser, epicIssue.id, actionId, inputParameters, transitionOptions)
assert transitionValidationResult.valid: transitionValidationResult.errorCollection

def result = issueService.transition(loggedInUser, transitionValidationResult)
assert result.valid: result.errorCollection