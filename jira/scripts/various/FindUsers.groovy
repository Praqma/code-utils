/**
  In case that there's an additional group that controls access to certain projects,
  it can be useful to search for users who are only members of one group, but should 
  also have access to the second group.
*/

import com.atlassian.crowd.manager.directory.DirectoryManager
import com.atlassian.jira.bc.JiraServiceContextImpl
import com.atlassian.jira.bc.user.UserService
import com.atlassian.jira.bc.user.search.UserSearchParams
import com.atlassian.jira.bc.user.search.UserSearchService
import com.atlassian.jira.security.groups.GroupManager
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.ComponentManager
import com.atlassian.jira.security.login.LoginManager
import com.atlassian.jira.user.ApplicationUser
​
// Either it can be Internal JIRA or one managed by Active Directory
final String directoryToCheck = "Active Directory server"
​
def loginManager = ComponentAccessor.getComponent(LoginManager)
def directoryManager = ComponentAccessor.getComponent(DirectoryManager)
GroupManager groupManager = ComponentManager.getComponentInstanceOfType(GroupManager.class)
​
UserSearchParams.Builder paramBuilder = UserSearchParams.builder()
    .allowEmptyQuery(true)
    .includeActive(true)
    .includeInactive(false)
​
JiraServiceContextImpl jiraServiceContext = new JiraServiceContextImpl(ComponentAccessor.jiraAuthenticationContext.loggedInUser)
​
def trusted = groupManager.getGroup("second-level-group")
​
def allActiveUsers = ComponentAccessor.getComponent(UserSearchService).findUsers(jiraServiceContext, "", paramBuilder.build())
def directoryId = directoryManager.findAllDirectories()?.find { it.name.toLowerCase() == directoryToCheck.toLowerCase() }?.id
​
def idleUsers = allActiveUsers.findAll { user ->
    user.directoryId == directoryId && loginManager.getLoginInfo(user.username)?.lastLoginTime && groupManager.getGroupNamesForUser(user).contains("jira-software-users") && groupManager.getGroupNamesForUser(user).size() == 1
}
