/**
 * This is a post function script. It is intended to be added to a create transition. It will set CheckBox values of a
 * custom field called "Development Team" to an option that matches. This is a SD use case therefor the request channel part of
 * the query.
 *
 * It is EXPECTED that the label is in the summary and enclosed in brackets [].
 * If there is no matching option a warning will be put in the logs. Nothing else...
 *
 * NOTE: That order of the post functions matter. This script MUST be after the reindex post function. Also if the summary
 * contains more than one valid label then the last match function will override any previously set values.
 */

import com.atlassian.jira.event.type.EventDispatchOption
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.issue.search.SearchProvider
import com.atlassian.jira.jql.parser.JqlQueryParser
import com.atlassian.jira.web.bean.PagerFilter

def KEY = "key = "
def ESCAPE = "\\"
def QUOTE = '"'
def LABELS = ["DEV", "SPU", "BIA", "No Option"]
def BRACKET_OPEN = "["
def BRACKET_CLOSE = "]"
def CHANNEL = "request-channel-type = email"
def CONTAINS = " ~ "
def OPERATOR = " AND "
def FIELD = "summary"
def user = ComponentAccessor.getJiraAuthenticationContext().getLoggedInUser()
def issueManager = ComponentAccessor.getIssueManager()
def customFieldManager = ComponentAccessor.getCustomFieldManager()
def productCF = customFieldManager.getCustomFieldObjectByName("Development Team")
def optionsManager = ComponentAccessor.getOptionsManager()
def jqlQueryParser = ComponentAccessor.getComponent(JqlQueryParser)
def searchProvider = ComponentAccessor.getComponent(SearchProvider)

// Mutable issue and array of checkbox options to set
def issueMutable = issueManager.getIssueObject(issue.getKey())
def optionsToSelect = []

// Checkbox Options
def cfConfig = productCF.getRelevantConfig(issueMutable)
def optionsAvailable = optionsManager.getOptions(cfConfig)
log.debug("Options Available: " + optionsAvailable.toString())

// Loop through the labels and see if they are in the summary. If so add them to the optionsToSelect array.
LABELS.each {
    def LABEL = it
    def REGEX = ~".*(\\[${LABEL}\\]).*"
    if (issueMutable.getSummary() ==~ REGEX) {
        // Check that it iS an email channel, is the same key and has the label. Kind of overkill...
        def QUERY = KEY + issueMutable.getKey() + OPERATOR + FIELD + CONTAINS + QUOTE + ESCAPE + ESCAPE +
                BRACKET_OPEN + LABEL + ESCAPE + ESCAPE + BRACKET_CLOSE + QUOTE + OPERATOR + CHANNEL
        log.debug("--------------------")
        log.debug("QUERY is: " + QUERY)

        // This should only return one item.
        def query = jqlQueryParser.parseQuery(QUERY)
        def results = searchProvider.search(query, user, PagerFilter.getUnlimitedFilter())
        if (results != null) {
            log.debug("Find Option: " + LABEL)
            def option = optionsAvailable.find {it.value in LABEL}
            if (option != null) {
                log.debug("Option to select: " + option)
                optionsToSelect.add(option)
            } else {
                log.warn("LABEL: " + LABEL + " not found as an option! Check the custom field!")
            }
        }
        log.debug("--------------------")
    }
}

log.debug("These options will be selected" + optionsToSelect.toString())
issueMutable.setCustomFieldValue(productCF,optionsToSelect)
issueManager.updateIssue(user, issueMutable, EventDispatchOption.ISSUE_UPDATED, false)
