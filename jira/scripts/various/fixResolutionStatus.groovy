/**
  This script can be used to fix the resolution status after a bad import. When
  bulk editing the resolution status, the resolution date will be changed to the
  time of the request.

  Specifically, this was used to fix a problem after importing from Redmine where 
  the importer plugin from JIRA did not set the resolution status of closed tickets
  to either "Won't Fix" or "Done"/"Fixed".
*/

import com.atlassian.jira.ComponentManager
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.config.ResolutionManager
import com.atlassian.jira.config.StatusManager
import com.atlassian.jira.event.type.EventDispatchOption
import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.IssueManager
import com.atlassian.jira.issue.MutableIssue
import com.atlassian.jira.issue.UpdateIssueRequest
import com.atlassian.jira.issue.resolution.Resolution
import com.atlassian.jira.issue.search.SearchProvider
import com.atlassian.jira.jql.parser.JqlQueryParser
import com.atlassian.jira.security.Permissions
import com.atlassian.jira.user.ApplicationUser
import com.atlassian.jira.web.bean.PagerFilter

def resolutionManager = ComponentAccessor.getComponent(ResolutionManager)
def issueManager = ComponentAccessor.getIssueManager()
def resolution = resolutionManager.getResolutionByName("Done")
def user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()
def statusManager = ComponentAccessor.getComponent(StatusManager)
def jqlQueryParser = ComponentAccessor.getComponent(JqlQueryParser.class)
def searchProvider = ComponentAccessor.getComponent(SearchProvider.class)
def query = jqlQueryParser.parseQuery("resolution = 1 and status = Done")
def results = searchProvider.search(query, user, PagerFilter.getUnlimitedFilter())

results.getIssues().each {documentIssue ->
    //log.debug(documentIssue.key)
    def issue = issueManager.getIssueObject(documentIssue.id)
    setFixedResolution(issue.getKey(), resolution)
}

def void setFixedResolution(String issueKey, Resolution resolution)
{
    def issueManager = ComponentAccessor.getIssueManager()
    MutableIssue issueObject = issueManager.getIssueObject(issueKey)
    def issueResolutionDate = issueObject.getResolutionDate()
    def resolutionStatus = issueObject.getResolution().description
    def user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()
    def resolutionDate = issueObject.getResolutionDate()
    issueObject.setResolutionDate(issueResolutionDate)
    issueObject.setResolution(resolution)
    // remember that the updated-field can also be set, so it's even more transparent
    ComponentAccessor.getIssueManager().updateIssue((ApplicationUser)user, (MutableIssue)issueObject, UpdateIssueRequest.builder().build(), false)
}
