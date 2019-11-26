/*
  Stories with open blocking issues should not be set to Done.
  The button disappears from the issue view.

  This is meant to be added as a Condition on a transition.
*/

import com.atlassian.jira.issue.*;
import com.atlassian.jira.component.ComponentAccessor;
import com.atlassian.jira.issue.link.*;
import java.util.List

def  issueLinkManager = ComponentAccessor.getIssueLinkManager()
def issueManager = ComponentAccessor.getIssueManager()

// issue is a special variable of the context of the transition
def issue = issue

// https://scriptrunner.adaptavist.com/latest/jira/custom-workflow-functions.html, see under Conditions
passesCondition = true

if(issue.getIssueType().getName() == "Story"){
    List links = issueLinkManager.getInwardLinks(issue.id)
    for(IssueLink issueLink : links){
        if(issueLink.issueLinkType.name == "Is blocked by"){
            def status = issueLink.destinationObject.getStatus().getName()
            if(!["Rejected", "Done"].contains(status)){
                passesCondition = false
                break;
            }
        }
    }
}
// functional programming style, no need for return
passesCondition
