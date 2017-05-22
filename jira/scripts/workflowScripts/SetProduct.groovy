/**
 * This is a post function script. It is intended to be added to a create transition. It will set a single select list
 * custom field called "Product" to an option that matches. This is a SD use case therefor the request channel part of
 * the query.
 *
 * It is EXPECTED that the label is in the summary and enclosed in brackets [].
 * To handled more labels just copy the script to a new post function and change th label constant.
 *
 * It is on purpose I do not handle more than one label in the script. I like to keep them simple, short and with as
 * few loops as possible. It also has the advantage of being able to remove label post functions without modifying the
 * script. If you want, it is easy enough to add the wanted lab els in an array and iterate through them.
 *
 * NOTE: That order of the post functions matter. This script MUST be after the reindex post function. Also if the summary
 * contains more than one valid label then the last post function will override any previously set values.
 */

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.event.type.EventDispatchOption
import com.atlassian.jira.issue.search.SearchProvider
import com.atlassian.jira.jql.parser.JqlQueryParser
import com.atlassian.jira.web.bean.PagerFilter

def KEY = "key = "
def ESCAPE = "\\"
def QUOTE = '"'
// TODO -ø makie this an array and iterate through them looking for a match
def LABEL = "SPU"
def BRACKET_OPEN = "["
def BRACKET_CLOSE = "]"
def CHANNEL = "request-channel-type = email"
def CONTAINS = " ~ "
def OPERATOR = " AND "
def FIELD = "summary"
def REG_EX = ~".*(\\[${LABEL}\\]).*"

def user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()

// TODO - This will happen after we check that a label is in the summary. We will just check for channel type
// Setup and execute query
def QUERY = KEY + issue.getKey() + OPERATOR + FIELD + CONTAINS + QUOTE + ESCAPE + ESCAPE +
        BRACKET_OPEN + LABEL + ESCAPE + ESCAPE + BRACKET_CLOSE + QUOTE + OPERATOR + CHANNEL
log.debug("QUERY is: " + QUERY)

def jqlQueryParser = ComponentAccessor.getComponent(JqlQueryParser)
def searchProvider = ComponentAccessor.getComponent(SearchProvider)
def query = jqlQueryParser.parseQuery(QUERY)
def results = searchProvider.search(query, user, PagerFilter.getUnlimitedFilter())

// Update issue if label is exact match
def issueManager = ComponentAccessor.getIssueManager()
def customFieldManager = ComponentAccessor.getCustomFieldManager()
def productCF = customFieldManager.getCustomFieldObjectByName("Product")
def optionsManager = ComponentAccessor.getOptionsManager()

results.getIssues().each { documentIssue ->
    // A mutable issue to work with. All updates to issue must be done on mutable issues.
    def issueMutable = issueManager.getIssueObject(documentIssue.id)
    // As JIRA does not support exact matches with the contain '~' operator, we need to do it with Java RegEx. sigh...
    if (issueMutable.getSummary() ==~ REG_EX) {
        def cfConfig = productCF.getRelevantConfig(issueMutable)
        def option = optionsManager.getOptions(cfConfig)?.find { it.toString() == LABEL }
        log.debug("Updating field: " + productCF.getName() + " to value: " + option.toString() + " on issue: " + issueMutable.getKey())
        issueMutable.setCustomFieldValue(productCF,option)
        issueManager.updateIssue(user,issueMutable, EventDispatchOption.ISSUE_UPDATED,false)
    }
}
