/**
 * Purpose is to Transition a linked Defect when a clone of the issue 
 * is resolved or closed.
 *
 * The parent defect(Has "defect is cloned by" link) must not have any
 * other cloned defects not resolved.
 *
 * If the parent defect has no unresolved cloned defects it will be transitioned
 * to "Ready For Test".
 *
 * An issue link type of "Defect Cloners" must exist.
 * The Project Name of the parent Defect must be UAT.
 * The status of the parent defect must be "Awaiting Action".
 *
 */


import com.atlassian.jira.issue.index.IssueIndexManager
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.bc.issue.IssueService.TransitionValidationResult
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.security.JiraAuthenticationContext
import com.atlassian.jira.workflow.IssueWorkflowManager
import com.opensymphony.workflow.loader.ActionDescriptor

def final String ISSUE_TYPE = "Defect"; // Issue type we are working with
def final String LINK_TYPE_NAME = "Defect Cloners"; // Link types we care about
def final String LINKED_ISSUE_STATUS = "Awaiting Action"; // The status we expect the parent defect to be in
def final String LINKED_ISSUE_ACTION = "Ready for Test"; // The next status we want to transition parent defect to

IssueLinkManager linkMgr = ComponentAccessor.getIssueLinkManager();
IssueIndexManager issueIndexMgr = ComponentAccessor.getIssueIndexManager();
IssueWorkflowManager issueWfManager = ComponentAccessor.getComponentOfType(IssueWorkflowManager);
JiraAuthenticationContext authContext = ComponentAccessor.getJiraAuthenticationContext();

def final currentUserObj = authContext.getUser().getDirectoryUser();

if (issue.getIssueTypeObject().getName() == ISSUE_TYPE) {
    for (IssueLink link in linkMgr.getOutwardLinks(issue.id)) {
        def issueLinkTypeName = link.issueLinkType.name;
        def linkedIssue = link.getDestinationObject();
        def linkedIssueProjectName = linkedIssue.getProjectObject().getName();
        def linkedIssueKey = linkedIssue.getKey();
        def linkedIssueID = linkedIssue.getId();
        def linkedIssueStatus = linkedIssue.getStatusObject().getName();

        if (issueLinkTypeName == LINK_TYPE_NAME && linkedIssueStatus == LINKED_ISSUE_STATUS) {
            def allClosed = true;
            for (IssueLink parentIssueLink in linkMgr.getInwardLinks(linkedIssueID)) {
                def parentLinkedIssue = parentIssueLink.getSourceObject();
                def parentLinkedIssueResolution = parentLinkedIssue.getResolutionObject();
                def parentLinkedIssueKey = parentLinkedIssue.getKey();
                def parentLinkedIssueLinkType = parentIssueLink.issueLinkType.name;

                if (issue.getKey() != parentLinkedIssueKey && parentLinkedIssueLinkType == LINK_TYPE_NAME) {
                    if (parentLinkedIssueResolution) {
                        log.debug("Parent issue Defect Link: resolution is " + parentLinkedIssueResolution.getName());
                    } else {
                        allClosed = false;
                        log.debug("Originating defect has at least one cloned defect: " + parentLinkedIssueKey +
                                " : which is not resolved.\n Will not transition parent issue.");
                        break;
                    }
                }
            }

            log.debug("All issues closed? " + allClosed);
            if (allClosed) {
                def actionID = 0;
                def availActions = issueWfManager.getAvailableActions(linkedIssue, authContext.getUser());
                for (ActionDescriptor descriptor : availActions) {
                    if (descriptor.getName() == LINKED_ISSUE_ACTION) {
                        actionID = descriptor.getId();
                        break;
                    }
                }

                if (actionID) {
                    log.debug("Transition issue " + linkedIssueKey);
                    issueService = ComponentAccessor.getIssueService();
                    issueInputParameters = issueService.newIssueInputParameters();
                    TransitionValidationResult validationResult = issueService.validateTransition(currentUserObj, linkedIssue.getId(), actionID, issueInputParameters);
                    if (validationResult.isValid()) {
                        issueService.transition(currentUserObj, validationResult);
                        log.debug("Transitioned");
                        issueIndexMgr.reIndex(validationResult.getIssue());
                        log.debug("Reindexed")
                    } else {
                        Collection<String> errors = validationResult.getErrorCollection().getErrorMessages();
                        for (errmsg in errors) {
                            log.debug("[ERROR] - Error message:" + errmsg);
                        }
                    }
                }
            }
        }
    }
}
