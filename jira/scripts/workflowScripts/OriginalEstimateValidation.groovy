/**
 * This little snippet checks that an original estimate is set for sub task types.
 * Apply it as a validation on a transition and have script runner throw up an error message if it doesn't return true.
 */

import com.atlassian.jira.issue.Issue

if(issue.isSubTask()) {
    def rteval = false
    if(issue.getOriginalEstimate() != null) {
        retval true;
    }
    return retval
}