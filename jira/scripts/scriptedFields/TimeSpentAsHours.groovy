/**
 * Very simple script to calculate value in hours.
 * Jira stores these values in milliseconds and presents them according to wishes, ie. hours, minutes, etc.
 * The exports to word and xml will use the default estimation set in global configuration.
 * The excel export does not do this :-(
 * Therefor we need a scripted field to be used as a column for JQL searches.
 *
 * NOTE: The return must be a double as Script Runner expects this.
 */
def hours;
if (issue.getTimeSpent() != null) {
    hours = issue.getTimeSpent().doubleValue() / 3600
} else {
    hours = null
}
return hours
