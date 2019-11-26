/**
  This small snippet can be used ass a post-function in a workflow to allow
  automatically assigning the new sub-task to the story assignee, unless
  one was provided during creation.
*/

import com.atlassian.jira.component.ComponentAccessor;
import com.atlassian.jira.issue.*;

def customFieldManager = ComponentAccessor.getCustomFieldManager()
def optionsManager = ComponentAccessor.getOptionsManager()

def user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()

if(issue.getIssueType().isSubTask()) {
    def parent = issue.getParentObject()
    if (parent != null  && issue.getAssignee() == null){
        issue.setAssignee(parent.getAssignee())
    }
}
