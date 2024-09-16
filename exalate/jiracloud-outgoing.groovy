
replica.reporter            = issue.reporter
replica.assignee            = issue.assignee
replica.labels              = issue.labels
replica.myLabels            = issue.labels
replica.descriptionHtml     = nodeHelper.getHtmlField(issue, "description")
replica.environmentHtml     = nodeHelper.getHtmlField(issue, "Environment")

replica.linkToJamaFeaturesMD   = issue.customFields."Link to Jama Features".value
replica.linkToJamaFeaturesHTML = nodeHelper.getHtmlField(issue, "customfield_11990")
replica.jamaProxy   = issue.customFields."Jama proxy".value

replica.acceptanceCriteriaMD   = issue.customFields."Acceptance Criteria".value
replica.acceptanceCriteriaHTML = nodeHelper.getHtmlField(issue, "customfield_11972")

replica.acceptanceCriteriaHTML = nodeHelper.getHtmlField(issue, "customfield_11972")

replica.driverProjects   = issue.customFields."Driver project(s)"

replica.requestType = issue.customFields."Platform Request type".value

replica.fixVersions       = issue.fixVersions
replica.affectsVersions   = issue."Affects versions"
replica.targetBuild       = issue."Target Build"?.value
replica.test              = issue."Test"

replica.userImpact        = issue."User Impact"?.value

replica.foundIn          = issue.customFields."Found in".value
replica.foundBy          = issue.customFields."Found by"?.value
replica.fixedIn          = issue.customFields."Fixed in"?.value

replica.function          = issue.customFields."Function"?.value


replica.reopenedDate          = issue.customFields."Reopened date"?.value

replica.issueLinks = issue.issueLinks
replica.issueLinksString = issue.issueLinks.collect{ it -> 
    def local_url='https://'+ jira_cloud_prefix +'.atlassian.net/browse/' + nodeHelper.getHubIssue(it.otherIssueId).key
    '<a href="' + local_url + '">' + local_url + "</a>:" + it.linkName + "," + it.isOutward
}
//debug.error("${nodeHelper.getHubIssue(issue.issueLinks[0].otherIssueId).key}")

replica.remoteIssueLinks = nodeHelper.getRemoteIssueLinks(issue)

replica.weblinks = issue.weblinks.collect { weblink ->
    [
        url: weblink.url,
        title: weblink.title,
        description: weblink.description
    ]
}
replica.weblinks2 = issue.get("issuelinks").findAll { link ->
        link.type.name == "Web Link"
    }.collect { webLink ->
    [
        url: webLink.outwardIssue != null ? webLink.outwardIssue.get("url") : null,
        title: webLink.outwardIssue != null ? webLink.outwardIssue.get("title") : "",
        description: webLink.outwardIssue != null ? webLink.outwardIssue.get("description") : ""
    ]
}

replica.derefLinks = issue.issuelinks.collect { link ->
      [
          id: link.id,  // Get the link ID
          url: link.url,
          linkName: link.linkName
      ]
}

replica.status         = issue.status
replica.parentId       = issue.parentId

// COMMENTS
replica.comments = nodeHelper.getHtmlComments(issue)
////

replica.project        = issue.project
replica.key            = issue.key
replica.type           = issue.type
replica.summary        = issue.summary
replica.priority       = issue.priority
replica.attachments    = issue.attachments

replica.components      = issue.components

replica.storyPoints       = issue.customFields."Story Points"?.value
replica.originalEstimate  = issue.originalEstimate

replica.TeamEstimate1 = issue.customFields."Team Estimate 1".value
replica.TeamEstimate2 = issue.customFields."Team Estimate 2".value
replica.TeamEstimate3 = issue.customFields."Team Estimate 3".value
replica.TeamEstimate4 = issue.customFields."Team Estimate 4".value
replica.TeamEstimate5 = issue.customFields."Team Estimate 5".value

replica.Estimate1 = issue.customFields."Estimate 1".value
replica.Estimate2 = issue.customFields."Estimate 2".value
replica.Estimate3 = issue.customFields."Estimate 3".value
replica.Estimate4 = issue.customFields."Estimate 4".value
replica.Estimate5 = issue.customFields."Estimate 5".value
