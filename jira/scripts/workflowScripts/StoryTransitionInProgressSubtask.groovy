/**
  Set the story status to In Progress when a Sub-task is set to In progress.
*/

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.config.SubTaskManager;
import com.atlassian.jira.issue.Issue;
import com.atlassian.jira.issue.MutableIssue;
import com.atlassian.jira.workflow.WorkflowTransitionUtil;
import com.atlassian.jira.workflow.WorkflowTransitionUtilImpl;
import com.atlassian.jira.util.JiraUtils;
import com.opensymphony.workflow.WorkflowContext;

Issue issue = issue

def issueService = ComponentAccessor.getIssueService()
def currentUser = ComponentAccessor.jiraAuthenticationContext.getLoggedInUser()

if(issue.isSubTask()) {
    // Need to use a mutable object to have read/write to parent, i.e., story
    MutableIssue parent = issue.getParentObject() as MutableIssue
    WorkflowTransitionUtil workflowTransitionUtil = (WorkflowTransitionUtil) JiraUtils.loadComponent(WorkflowTransitionUtilImpl.class)

    String originalParentStatus  = parent.getStatus().getSimpleStatus().getName()
    def isDevBacklogStatus = originalParentStatus in ['To Do', 'Clarification']

    if (isDevBacklogStatus) {
        workflowTransitionUtil.setIssue(parent)
        // 21 is the id of "In Progress", see Text of the Workflow
        // The state name can't be used directly
        workflowTransitionUtil.setAction(21)
        if (workflowTransitionUtil.validate()) {
            workflowTransitionUtil.progress()
        }
    }
}
