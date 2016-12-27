/**
 * Created by EXT.Tim.Harris on 20-02-2015.
 *
 * Purpose is to find all User Stories that have a linked "Theme" issue type
 * where the Epic of the linked Theme is different than the Epic of the User Story.
 *
 * If the either the User Story or the linked Themes has an Epic Link and the other
 * does not then this is seen as a mismatch.
 *
 */

package com.onresolve.jira.groovy.jql

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.Issue
import com.atlassian.crowd.embedded.api.User
import com.atlassian.jira.issue.link.IssueLink
import com.atlassian.jira.issue.link.IssueLinkManager
import com.atlassian.jira.jql.query.QueryCreationContext
import com.atlassian.jira.util.MessageSet
import com.atlassian.query.clause.TerminalClause
import com.atlassian.query.operand.FunctionOperand
import org.apache.lucene.index.Term
import org.apache.lucene.search.BooleanClause
import org.apache.lucene.search.BooleanQuery
import org.apache.lucene.search.Query
import org.apache.lucene.search.TermQuery

class MismatchedThemes extends AbstractScriptedJqlFunction implements JqlQueryFunction{
    Category log = Category.getInstance(MismatchedThemes.class)

    @Override
    String getDescription() {
        "Returns all stories where the epic link is not the same as the epic link of the linked Theme(if there is a linked Theme)." +
                " Non Linked Stories and themes are seen as mismatches!"
    }

    @Override
    List<Map> getArguments() {
        [
                [
                        "description": "Subquery",
                        "optional": false,
                ]
        ]
    }

    @Override
    String getFunctionName() {
        "hasEpicMismatchWithTheme"
    }

    def String subquery = "";
    @Override
    MessageSet validate(User user, FunctionOperand operand, TerminalClause terminalClause) {
        def messageSet = super.validate(user, operand, terminalClause)
        if(operand.args.size() <= 0){
            messageSet.addErrorMessage("You must supply a sub-query! It may be an empty set of parenthesis if you wish." +
                    " This will search ALL issues!")
        } else {
            subquery = operand.args[0]
        }
        return messageSet;

    }

    @Override
    Query getQuery(QueryCreationContext queryCreationContext, FunctionOperand operand, TerminalClause terminalClause) {
        def booleanQuery = new BooleanQuery()
        def themeEpic;
        def storyEpic;

        log.debug("This is the subquery: " + subquery + "\n")
        issues = getIssues(subquery)
        for (Issue currIssue in issues) {
            if (currIssue.getIssueTypeId() == "10001") {
                storyEpic = getEpicLinkField(currIssue);
                def Issue theme = getLinkedTheme(currIssue);
                if(theme && theme.getIssueTypeObject().getName() == "Theme") {
                    themeEpic = getEpicLinkField(theme);
                    if(storyEpic != themeEpic) {
                        booleanQuery.add(new TermQuery(new Term("issue_id",currIssue.id as String)),BooleanClause.Occur.SHOULD)
                    }
                }
            }
        }
        return booleanQuery;

    }

    static String getEpicLinkField(Issue issue) {
        def customFieldMgr = ComponentAccessor.getCustomFieldManager();
        def epicLinkField = customFieldMgr.getCustomFieldObjects(issue).find
                {it.name == 'Epic Link'}
        return  epicLinkField.getValue(issue);
    }

    static Issue getLinkedTheme(Issue story) {
        def IssueLinkManager linkMgr = ComponentAccessor.getIssueLinkManager();
        def theme = null;
        for (IssueLink link in linkMgr.getOutwardLinks(story.getId())) {
            if (link.getIssueLinkType().getName() == "Theme") {
                theme = link.getDestinationObject();
                break;
            }
        }
        return theme;
    }
}
