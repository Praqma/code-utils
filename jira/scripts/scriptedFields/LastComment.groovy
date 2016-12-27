/**
 * Sometimes it is nice to show the last comments in an issue search.
 * Add the field to a column in JQL searches.
 */

import com.atlassian.jira.component.ComponentAccessor

def commentManager = ComponentAccessor.getCommentManager()
def comments = commentManager.getComments(issue)

if (comments) {
    comments.last().author + ": " + comments.last().body
}
