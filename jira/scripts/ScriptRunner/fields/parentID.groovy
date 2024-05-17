import com.atlassian.jira.issue.Issue
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkImpl
import com.atlassian.jira.issue.link.DefaultIssueLinkManager
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.fields.CustomField
import com.atlassian.jira.issue.fields.ImmutableCustomField

class RequirementFinder {
	DefaultIssueLinkManager issueLinkManager = ComponentAccessor.getIssueLinkManager() as DefaultIssueLinkManager
    def customFieldManager = ComponentAccessor.getCustomFieldManager()

    private Issue getRequirementForEpic(Issue epic){
        if(epic == null){
            return null;
        }
        Issue requirement = null;
        Collection<IssueLink> links = issueLinkManager.getInwardLinks(epic.getId())
        try {
            links = links.findAll({it -> it.getIssueLinkType().getName() == "Hierarchy" && it.sourceObject.getIssueType().getName() == 'Request'})
            return links[0].sourceObject
        } catch (Exception e){
            return null
        }
    } 

    public String getRequirement(Issue issueObject){
        if(issueObject?.getIssueType()?.getName() == "Request"){
            return issueObject; // or null
        }
        if(issueObject?.getIssueType()?.getName() == "Epic"){
            return this.getRequirementForEpic(issueObject)
        }
        return null;
    }
}
def issue = issue as Issue
def requirementFinder = new RequirementFinder();
requirementFinder.getRequirement(issue)