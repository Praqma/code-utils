import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.CustomFieldManager
import com.opensymphony.workflow.InvalidInputException

CustomFieldManager cfManager = ComponentAccessor.getCustomFieldManager()
implSolutionCf = cfManager.getCustomFieldObjectsByName("Implemented solution")[0]

log.warn(implSolutionCf)
def implSolution = issue.getCustomFieldValue(implSolutionCf)
log.warn(implSolution)

if(["Bug", "Story", "Eval"].contains(issue.getIssueType().getName())){
    log.warn("Story, Bug, Eval")
    if(!implSolution?.trim()){
        throw new InvalidInputException("Implemented Solution is required for Story, Bug, Eval")
		false
    }
}
