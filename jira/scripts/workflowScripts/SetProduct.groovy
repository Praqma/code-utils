/**
 * This is a post function script. It is intended to be added to a create transition. It will set a single select list
 * custom field called "Product" to an option that matches. This is a SD use case therefor the request channel part of
 * the query.
 *
 * It is EXPECTED that the label is in the summary and enclosed in brackets [].
 * If there is no matching option a warning will be put in the logs. Nothing else...
 *
 * NOTE: That order of the post functions matter. This script MUST be after the reindex post function. Also if the summary
 * contains more than one valid label then the last match function will override any previously set values.
 */

import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.event.type.EventDispatchOption
import com.atlassian.jira.issue.search.SearchProvider
import com.atlassian.jira.jql.parser.JqlQueryParser
import com.atlassian.jira.web.bean.PagerFilter

def KEY = "key = "
def ESCAPE = "\\"
def QUOTE = '"'
def LABELS = ["SPU", "BIA", "No Option"]
def BRACKET_OPEN = "["
def BRACKET_CLOSE = "]"
def CHANNEL = "request-channel-type = email"
def CONTAINS = " ~ "
def OPERATOR = " AND "
def FIELD = "summary"
def user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()
def issueManager = ComponentAccessor.getIssueManager()
def customFieldManager = ComponentAccessor.getCustomFieldManager()
def productCF = customFieldManager.getCustomFieldObjectByName("Product")
def optionsManager = ComponentAccessor.getOptionsManager()
def jqlQueryParser = ComponentAccessor.getComponent(JqlQueryParser)
def searchProvider = ComponentAccessor.getComponent(SearchProvider)

// Mutable issue
def issueMutable = issueManager.getIssueObject(issue.getKey())

// Update issue if label is exact match
LABELS.each {
    def LABEL = it
    def REGEX = ~".*(\\[${LABEL}\\]).*"
    log.debug("REGEX: " + REGEX)

    if (issueMutable.getSummary() ==~ REGEX) {
        // Check that it iS an email channel, is the same key and has the label. Kind of overkill...
        def QUERY = KEY + issueMutable.getKey() + OPERATOR + FIELD + CONTAINS + QUOTE + ESCAPE + ESCAPE +
                BRACKET_OPEN + LABEL + ESCAPE + ESCAPE + BRACKET_CLOSE + QUOTE + OPERATOR + CHANNEL

        log.debug("QUERY is: " + QUERY)
        def query = jqlQueryParser.parseQuery(QUERY)
        def results = searchProvider.search(query, user, PagerFilter.getUnlimitedFilter())

        // This should only return one item
        results.getIssues().each { documentIssue ->
            def cfConfig = productCF.getRelevantConfig(issueMutable)
            def option = optionsManager.getOptions(cfConfig)?.find { it.toString() == LABEL }
            if (option != null) {
                log.debug("Updating field: " + productCF.getName() + " to value: " + option.toString() + " on issue: " + issueMutable.getKey())
                issueMutable.setCustomFieldValue(productCF, option)
                issueManager.updateIssue(user, issueMutable, EventDispatchOption.ISSUE_UPDATED, false)
            } else {
                log.warn("No matching option for LABEL: " + LABEL)
            }
        }
    }
}
