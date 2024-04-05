import com.atlassian.jira.ComponentManager;
import com.atlassian.jira.component.ComponentAccessor;
import com.atlassian.jira.issue.CustomFieldManager;
import com.atlassian.jira.issue.fields.CustomField;
import com.atlassian.jira.issue.IssueManager;
import com.atlassian.jira.issue.MutableIssue;
import com.atlassian.jira.issue.Issue; 
import com.atlassian.jira.user.ApplicationUser;
import com.atlassian.jira.bc.issue.IssueService
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.IssueInputParametersImpl

def currentUser = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()
def issueManager = ComponentAccessor.issueManager
IssueService issueService = ComponentAccessor.getIssueService()
def actionId = 31 // change this to the step that you want the issues to be transitioned to

def transitionValidationResult
def transitionResult


def epicLink = ComponentAccessor.customFieldManager.getCustomFieldObjectByName("Epic Link")
def epic = issue.getCustomFieldValue(epicLink) as String
if(epic){
    def issueE = issueManager.getIssueObject(epic);
    if(issueE.getStatus().name != "In Progress" )
    {
        transitionValidationResult = issueService.validateTransition(currentUser, issueE.id, actionId,new IssueInputParametersImpl())
        if (transitionValidationResult.isValid()) {
            transitionResult = issueService.transition(currentUser, transitionValidationResult)
            if (transitionResult.isValid())
                { log.debug("Transitioned issue $issue through action $actionId") }
            else
                { log.debug("Transition result is not valid") }
       }else{
          log.debug("The transitionValidation is not valid")
       }

    }
}