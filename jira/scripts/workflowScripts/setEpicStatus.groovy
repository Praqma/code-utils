/*
 JIRA does not handle the epic status when transitioning the Epic to done.
 The epics are then still shown in the Scrum board.

 You can use this script on a transition that takes the issue to a
 done state, and likewise, you can use it on transitions that go out
 of the state by adjusting the epicStatus variable. Epic Status is
 configured as a custom field with options (it may differ):

 - To Do
 - In Progress
 - Done
 */

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.CustomFieldManager
import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueManager
import com.atlassian.jira.issue.ModifiedValue
import com.atlassian.jira.issue.customfields.CustomFieldType
import com.atlassian.jira.issue.customfields.manager.OptionsManager
import com.atlassian.jira.issue.customfields.option.Option
import com.atlassian.jira.issue.customfields.option.Options
import com.atlassian.jira.issue.fields.config.FieldConfig
import com.atlassian.jira.issue.util.DefaultIssueChangeHolder
import com.atlassian.jira.user.ApplicationUser

IssueManager issueManager = ComponentAccessor.getIssueManager()
CustomFieldManager customFieldManager = ComponentAccessor.getCustomFieldManager()
OptionsManager optionsManager = ComponentAccessor.getOptionsManager()
ApplicationUser user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()

Issue epic = issue as Issue

if(epic.getIssueType().getName() != "Epic"){
    return
}

def epicStatusCf = customFieldManager.getCustomFieldObjectByName("Epic Status")
def epicStatus = "Done"  // To Do
def changeHolder = new DefaultIssueChangeHolder()

FieldConfig epicStatusFieldConfig = epicStatusCf.getRelevantConfig(epic)

Options epicStatusOptions = optionsManager.getOptions(epicStatusFieldConfig);
Option epicStatusOption = epicStatusOptions.getOptionForValue(epicStatus, null);
epicStatusCf.updateValue(null, epic, new ModifiedValue(epic.getCustomFieldValue(epicStatusCf), epicStatusOption), changeHolder)
