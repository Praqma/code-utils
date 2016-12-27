/**
 * Purpose is to clone an issue type to a user selected project.
 * The user performing the action must have permission to create issue
 * in the target project. The cloned issue will be linked to the original 
 * defect with a "clones" link type.
 *
 * User selected project is a custom field called "Target Project".
 * The assignee is set to the project lead of the Target Project.
 * The summary is prepended with CLONE.
 * The creation date is set to the date of creation.
 * Links from Original issue are kept.
 * Estimates and time spent are zeroed out on cloned issue.
 *
 */

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.CustomFieldManager
import com.atlassian.jira.issue.IssueFactory
import com.atlassian.jira.issue.IssueManager
import com.atlassian.jira.issue.MutableIssue
import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.project.Project
import com.atlassian.jira.project.ProjectManager
import com.atlassian.jira.security.JiraAuthenticationContext
import com.atlassian.jira.issue.link.IssueLinkTypeManager
import com.atlassian.jira.issue.link.IssueLinkType

def final String LINK_TYPE_NAME = "Defect Cloners"; // Link types we care about

CustomFieldManager cfMgr = ComponentAccessor.getCustomFieldManager();
ProjectManager projectMgr = ComponentAccessor.getProjectManager();
IssueLinkManager linkMgr = ComponentAccessor.getIssueLinkManager();
IssueLinkTypeManager linkTypeMgr = ComponentAccessor.getComponentOfType(IssueLinkTypeManager);
IssueManager issueMgr = ComponentAccessor.getIssueManager();
IssueFactory issueFactory = ComponentAccessor.getIssueFactory();
JiraAuthenticationContext authContext = ComponentAccessor.getJiraAuthenticationContext();

final def currentUserObj = authContext.getUser().getDirectoryUser();
final def currentUserName = authContext.getUser().getName();
final def CustomField cf = cfMgr.getCustomFieldObjects(issue).find() {it.name == 'Target Project'}
def Project projectObj;

if(cf != null){
    def Map projMap = issue.getCustomFieldValue(cf);
    if(projMap != null){
        projectObj = projectMgr.getProjectByCurrentKey(projMap.get("key") as String);
    }
}

def MutableIssue newIssue = issueFactory.cloneIssue(issue);
if (projectObj != null){
    newIssue.setProjectId(projectObj.id);
    newIssue.setAssignee(projectMgr.getDefaultAssignee(projectObj,projectObj.getProjectComponents()));
}
newIssue.setSummary("CLONE of DEFECT " + '"' + issue.getKey() + '"' + ": " + newIssue.getSummary());
newIssue.setOriginalEstimate(0);
newIssue.setEstimate(0);
newIssue.setTimeSpent(0);
created = new java.sql.Timestamp(Calendar.getInstance().getTime().getTime());
newIssue.setCreated(created);
params = ["issue":newIssue];
newIssue = issueMgr.createIssueObject(currentUserName, params);

def Collection<IssueLinkType> linkTypesCollection = linkTypeMgr.getIssueLinkTypes();
def clonersID = 0;
for (IssueLinkType linkType : linkTypesCollection) {
    if (linkType.getName() == LINK_TYPE_NAME) {
        clonersID = linkType.getId();
        break;
    }
}

def sequence = 0;
for (IssueLink link in linkMgr.getInwardLinks(issue.id)) {
    if(link.getIssueLinkType().getName() != LINK_TYPE_NAME) {
        linkMgr.createIssueLink(link.getSourceId(),newIssue.id, link.getLinkTypeId(),sequence,currentUserObj)
        sequence++;
    }
}
linkMgr.createIssueLink(newIssue.id,issue.id,clonersID,sequence,currentUserObj)
