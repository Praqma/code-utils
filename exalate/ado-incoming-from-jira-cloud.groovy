//////////////////////////////////

import java.text.SimpleDateFormat
def sdf = new SimpleDateFormat("yyyy-MM-dd hh:mm:ss")

////////////////////////////////////////////////////////////
//  Issue project handling
////////////////////////////////////////////////////////////
// Left: remote(Jira) and right local (AzDo)
def issueProjectMapping = [
  "EXSYNC" : "exalate-sync" ,
  "ONEGN"  : "GN-DataSyncTemp",
  "<default>" : "${defaultAdoproject}",
]
// Extracting Project Key from the incoming replica's key
def targetProjectMapping = issueProjectMapping[replica.project.key] 

if (! targetProjectMapping ) {
    targetProjectMapping = issueProjectMapping["<default>"] 
    if (! targetProjectMapping ) {
        debug.error('Project mapping unsupported :' + replica.project.key)
    }
}

    
////////////////////////////////////////////////////////////
//  Issue Type handling
////////////////////////////////////////////////////////////
// Left: remote(AzDO) and right local (Jira)
def issueTypeMapping 
if ( replica.project.key == "AIIS" ) {
    issueTypeMapping = [
        "Task" : "Feature"
    ]
    // debug.error("AIIS found - stop")
} else {
    issueTypeMapping = [
        "Platform Request" : "Feature" ,
        "Bug" : "Bug",
        "Task" : "User Story"
    ]
}

if(firstSync){
    workItem.typeName = issueTypeMapping[replica.type.name]
    if ( ! workItem.typeName ){
      debug.error("Unsupported issue type mapping: " + replica.type.name + " -> " + issueTypeMapping[replica.type.name] ) 
    }
}
//debug.error('Type: ' + replica.type.name + ' : ' + nodeHelper.getIssueType(replica.type?.name, workItem.projectKey)?.name ?: "Bug" )

if(firstSync){
   workItem.projectKey   = targetProjectMapping
} else {
    if (replica.project.key != "AIIS" && workItem.typeName != "Bug" ) {
        workItem.comments     = commentHelper.mergeComments(workItem, replica, { comment ->
                            comment.body =
                                "[(" + sdf.format(comment.created) + ") " + 
                                  comment.author.displayName +
                                  " | email: " + comment.author.email +
                                "]" +
                                  " commented: \n" +
                            comment.body + "\n" 
                            def authorUser = nodeHelper.getUserByEmail(comment.author.email,targetProjectMapping )
                            if ( authorUser ) {
                                comment.executor = authorUser ?: comment.author  // Set to proxy user or default if not found
                            }
                    }
        )
        return
    }
}

def tempDescription='Original from Jira: <a href="https://' +jira_cloud_prefix+ '.atlassian.net/browse/' + replica.key + '">https://' +jira_cloud_prefix+ '.atlassian.net/browse/' + replica.key + '</a><br>'
tempDescription +=  replica.descriptionHtml

https://community.exalate.com/questions/88245806/createdby-field-in-ado-workitem-set-to-proxy-user-
//issue."Created by" = replica.reporter

def assignee = nodeHelper.getUserByEmail(replica.assignee?.email,workItem.projectKey)  ?: defaultUser
def reporter = nodeHelper.getUserByEmail(replica.reporter.email, workItem.projectKey)  ?: defaultUser

tempDescription +=  "<br><b>Jira reporter:</b> ${replica.reporter.displayName} ( ${replica.reporter.email} )"

if (replica.assignee) {
    if ( assignee == defaultUser ){
        tempDescription +=  "<br><b>Jira assignee:</b> ${replica.assignee.displayName} ( ${replica.assignee.email} )"
    }
}

workItem.assignee  = assignee
workItem.reporter  = reporter

if ( replica.linkToJamaFeaturesHTML ){
    tempDescription +=  "<br><b>Jira Links to Jama:</b><br>" + replica.linkToJamaFeaturesHTML
}
if (replica.driverProjects.value){ 
    tempDescription +=  "<br><b>Jira Driver Projects:</b><br>"
    replica.driverProjects.value.each{ it ->
        tempDescription += ' - ' + it.value + '<br>'
    }
}
if (replica.myLabels) {
    tempDescription +=  "<br><b>Jira Labels:</b><br>"
    replica.myLabels.each{ it ->
        tempDescription += ' - ' + it.label + '<br>'
    }
}
if (replica.issueLinksString){
    tempDescription +=  "<br><b>Jira links Strings: [link,type,isOutwards]</b><br>"
    replica.issueLinksString.each{ it ->
        tempDescription += ' - ' + it + '<br>'
    }
}
if ( replica.remoteIssueLinks ) {
    tempDescription +=  "<br><b>Jira Remote Links:</b><br>"
    replica.remoteIssueLinks.each{ it ->
        tempDescription += ' - <a href="' + it.url +'">' + it.url + '</a><br>' 
    }
}
if ( replica.components ) {
    tempDescription +=  "<br><b>Jira components:</b><br>"
    replica.components.each{ it ->
        tempDescription += ' - ' + it.name + '<br>'
    }
}
if ( replica.function ) {
    tempDescription +=  "<br><b>Jira Function:</b> " + replica.function.value
}

if ( replica.userImpact ) {
    tempDescription +=  "<br><b>Jira User Impact:</b> " + replica.userImpact + '<br>'
}

if ( replica.foundBy ) {
    tempDescription +=  "<br><b>Jira Found By:</b> " + replica.foundBy.value + '<br>'
    def issueFoundByMapping = [
        "<jira-attr-value>"           : "<ADO-attr-value>", 
    ]
    workItem."Custom.Reportedfrom" = issueFoundByMapping[replica.foundBy.value]
}
if ( replica.targetBuild ) {
    tempDescription +=  "<b>Jira Target Build:</b> " + replica.targetBuild + '<br>'
}
if ( replica.affectsVersions ) {
    tempDescription +=  "<br><b>Jira Affects Version:</b><br>"
    replica.affectsVersions.each{ it ->
        tempDescription += ' - ' + it.name + '<br>'
    }
}
if ( replica.fixVersions ) {
    tempDescription +=  "<br><b>Jira FixVersions:</b><br>"
    replica.fixVersions.each{ it ->
        tempDescription += ' - ' + it.name + '<br>'
    }
}

if ( replica.storyPoints ) {
    tempDescription +=  "<br><b>Jira Story Points:</b> " + replica.storyPoints + '<br>'
}
tempDescription +=  "<br><br><b>Jira Team Estimates:</b><br>"
if (replica.Estimate1 && replica.TeamEstimate1){
    tempDescription += replica.TeamEstimate1.value + ": " + replica.Estimate1.value
}
if (replica.Estimate2 && replica.TeamEstimate2){
    tempDescription += "<br>" + replica.TeamEstimate2.value + ": " + replica.Estimate2.value
}
if (replica.Estimate3 && replica.TeamEstimate3){
    tempDescription += "<br>" + replica.TeamEstimate3.value + ": " + replica.Estimate3.value
}
if (replica.Estimate4 && replica.TeamEstimate4){
    tempDescription += "<br>" + replica.TeamEstimate4.value + ": " + replica.Estimate4.value
}
if (replica.Estimate5 && replica.TeamEstimate5){
    tempDescription += "<br>" + replica.TeamEstimate5.value + ": " + replica.Estimate5.value
}

if ( replica.type.name == "Bug" ) {
    if ( replica.jamaProxy ) {
        tempDescription +=  "<br><b>Jira Jama proxy:</b> " + replica.jamaProxy + '<br>'
    } 

    // It is now description // workItem."Microsoft.VSTS.TCM.ReproSteps"   = tempDescription
}
// debug.error(tempDescription )
workItem.description  = tempDescription

if ( workItem.typeName == "Bug" ) {
    //Map priority beteween Az and JIRA
    if (replica.priority) {
        def priorityMapping = [
            "Blocker" : "1", 
            "Critical": "2", 
            "Major"   : "3", 
            "Minor"   : "4",
            "Trivial" : "4"
        ]  
        workItem.priority = nodeHelper.getPriority(priorityMapping[replica.priority.name])
        //debug.error("replica.priority: ${replica.priority.name} -> ${priorityMapping[replica.priority.name]}; ${workItem.priority.name} ")
    }
     
    workItem."Microsoft.VSTS.Build.IntegrationBuild" = replica.fixedIn
    workItem."Microsoft.VSTS.Build.FoundIn" = replica.foundIn

    workItem.originalEstimate  = issue.originalEstimate
    if ( replica.fixVersions ) {
        def tempResolvedIn=replica.fixVersions.collect{ it.name }.join(",")
        workItem."Custom.ResolvedIn" = tempResolvedIn
    }
}

if ( workItem.typeName == "Feature" ) {
    def fixVersionMapping = [
        ""     : "",
        "PI25" : "2024 Q3 PI",
        "PI26" : "2024 Q3 PI",
        "PI27" : "2024 Q4 PI",
        "PI28" : "2025 Q1 PI",
        "PI29" : "2025 Q2 PI",
        "PI30" : "2025 Q3 PI"
    ]

    if ( replica.fixVersions ) {
        def reqForPI =  fixVersionMapping[replica.fixVersions?.first()?.name ?: ""]
        if (reqForPI) {
            workItem."Custom.RequestforPI" = fixVersionMapping[replica.fixVersions?.first()?.name ?: ""]
        }
    }
}

////////////////////////////////////////////////////////////
//  workItem fields handling
////////////////////////////////////////////////////////////
if ( replica.type.name == "Task" ) {
    workItem.summary      = "[ ${replica.key} ]: (${replica.type.name}) ${replica.summary}".take(128)

} else {
    workItem.summary      = "[ ${replica.key} ]: ${replica.summary}".take(128)
}
workItem.summary      = "[ ${replica.key} ]: ${replica.summary}".take(128)
workItem.attachments  = attachmentHelper.mergeAttachments(workItem, replica)
workItem.comments     = commentHelper.mergeComments(workItem, replica, { comment ->
                            comment.body =
                                "[(" + sdf.format(comment.created) + ") " + 
                                  comment.author.displayName +
                                  " | email: " + comment.author.email +
                                "]" +
                                  " commented: \n" +
                            comment.body + "\n" 
                            def authorUser = nodeHelper.getUserByEmail(comment.author.email,targetProjectMapping )
                            if ( authorUser ) {
                                comment.executor = authorUser ?: comment.author  // Set to proxy user or default if not found
                            }
                    }
)


workItem."Microsoft.VSTS.Common.BusinessValue" = replica.customFields.impactValue?.value?.value

def targetDate
if (replica.dueDate?.value){
    targetDate = sdf.format(replica.dueDate.value)
//    workItem."Microsoft.VSTS.Scheduling.TargetDate" = targetDate
}

def areaPathMapping = [
    "<jira-project>" : targetProjectMapping + '\\pathA\\pathB',
]
 

if (areaPathMapping[replica.project.key]) {
    // Set the Area Path using the mapping
    workItem.areaPath = areaPathMapping[replica.project.key]
} else {
    debug.error("ERROR: no mapped - areaPathMapping[replica.project.key]: " + areaPathMapping[replica.project.key] + " / " + workItem.projectKey )
}




////////////////////////////////////////////////////////////
//  Issue Type handling
////////////////////////////////////////////////////////////

//Map status beteween Az and JIRA 
// Left: remote(Jira) and right local (AzDo)
def statusMapping = []
if ( replica.issueType.name == "Platform Request" ) {
    statusMapping = [
        "Funnel"            : "New", 
        "Open"              : "New", 
        "Analyzing"         : "New", 
        "Portfolio Backlog" : "Ready", 
        "Info pending"      : "New", 
        "Reviewing"         : "New", 
        "Closed"            : "Closed",
        "打开"              : "New", 
    ]
/*

*/
} else {
    statusMapping = [
        "Open"            : "New", 
        "In Progress"     : "Active", 
        "Ready for Review": "Resolved", 
        "In Testing"      : "Resolved", 
        "Closed"          : "Closed",
        "In Test"         : "Resolved",
        "Resolved"        : "Resolved",
        "Draft"           : "New",
        "New"             : "New",
        "Ready for test"  : "Resolved",
        "Abandoned"       : "Closed",
        "Done"            : "Closed",
        "To Do"           : "New",
        "Requires feature testing" : "New",
        "Reopened"        : "New",
        "In Feature testing" : "Resolved",
        "Ready for merge" : "Resolved",
        "Blocked"         : "New",
        "打开"            : "New", 
        "已解决"           : "Accepted",
        "正在进行"     : "Active",
        "已解决"           : "Resolved",
    ]
}
/*
*/


def localStatus = statusMapping[replica.status.name]
if(localStatus){
  // Only set the status if it is mapped
  workItem.setStatus(localStatus)
} else {
    debug.error("Status mapping failed: " + replica.status.name )
}


////////////////////////////////////////////////////////////
//  Issue parent handling
////////////////////////////////////////////////////////////
// https://community.exalate.com/display/exacom/Jira+Cloud+Azure+DevOps%3A+Bi-directional+hierarchy+sync
if (replica.parentId) {
   def localParent = syncHelper.getLocalIssueKeyFromRemoteId(replica.parentId.toLong())
   if (localParent) {
      workItem.parentId = localParent.id
   }
}


if (replica.acceptanceCriteriaHTML){
    workItem."GNR.AcceptanceCriteria"  = replica.acceptanceCriteriaHTML
}

if (replica.requestType){
    if (replica.requestType.value == "Feature" ){
        workItem."Microsoft.VSTS.Common.ValueArea"="Business"
    } else {
        workItem."Microsoft.VSTS.Common.ValueArea"="Enabler"
    }
}

def mappingProject = [
    "<jira-project>"  : "<ado-atribute>" ,  
]
if ( mappingProject[replica.project.key] ){ 
    workItem."Custom.Product" = mappingProject[replica.project.key]
}

//debug.error("STOP")
return

// Skip issue link for now .. it does not work for "scala" in Exalate node : https://exalate.atlassian.net/servicedesk/customer/portal/5/EASE-32878

def project = workItem.projectKey
def res =httpClient.get( "/${project}/_apis/wit/workItems/${workItem.id}/revisions",true)
def await = { f -> scala.concurrent.Await$.MODULE$.result(f, scala.concurrent.duration.Duration.apply(1, java.util.concurrent.TimeUnit.MINUTES)) }
def creds = await(httpClient.azureClient.getCredentials())
def token = creds.accessToken()
def baseUrl = creds.issueTrackerUrl()
def localUrl = baseUrl + '/_apis/wit/workItems/' + workItem.id

int x =0
res.value.relations.each{
    revision ->
        def createIterationBody1 = [
            [
                op: "test",
                path: "/rev",
                value: (int) res.value.size()
            ],
            [
                op:"remove",
                path:"/relations/${x++}"
            ]
        ]
        def createIterationBodyStr1 = groovy.json.JsonOutput.toJson(createIterationBody1)
        converter = scala.collection.JavaConverters;
        arrForScala = [new scala.Tuple2("Content-Type","application/json-patch+json")]
        scalaSeq = converter.asScalaIteratorConverter(arrForScala.iterator()).asScala().toSeq();
        createIterationBodyStr1 = groovy.json.JsonOutput.toJson(createIterationBody1)
        def result1 = await(httpClient.azureClient.ws
            .url(baseUrl+"/${project}/_apis/wit/workitems/${workItem.id}?api-version=6.0")
            .addHttpHeaders(scalaSeq)
            .withAuth(token, token, play.api.libs.ws.WSAuthScheme$BASIC$.MODULE$)
            .withBody(play.api.libs.json.Json.parse(createIterationBodyStr1), play.api.libs.ws.JsonBodyWritables$.MODULE$.writeableOf_JsValue)
            .withMethod("PATCH")
            .execute())
}         

             
def linkTypeMapping = [
    "blocks": "System.LinkTypes.Dependency-Reverse",
    "relates to": "System.LinkTypes.Related"
]

def issueLinks = replica.issueLinks
if (issueLinks) {
    issueLinks.each{
        def localLinkedIssue = syncHelper.getLocalIssueKeyFromRemoteId(it.otherIssueId.toLong())
        if (!localLinkedIssue?.id) { return; }
        def localLinkedUrl = baseUrl + "/_apis/wit/workItems/" + localLinkedIssue.id
        def createIterationBody = [        
                [
                    op : "test",
                    path : "/rev",
                    value : (int) res.value.size()
                ],
                [
                    op : "add",
                    path: "/relations/-",
                    value: [
                        "rel":"${linkTypeMapping[it.linkName]}",
                        "url":"${localLinkedUrl}",
                        "attributes": [
                            "comment": "link created via Exalate"
                        ]
                    ]
                ]
            ]
            
        def createIterationBodyStr = groovy.json.JsonOutput.toJson(createIterationBody)

        converter = scala.collection.JavaConverters;
        arrForScala = [new scala.Tuple2("Content-Type","application/json-patch+json")]
        scalaSeq = converter.asScalaIteratorConverter(arrForScala.iterator()).asScala().toSeq();
        createIterationBodyStr = groovy.json.JsonOutput.toJson(createIterationBody)
        def result = await(httpClient.azureClient.ws
            .url(baseUrl+"/${project}/_apis/wit/workitems/${workItem.id}?api-version=6.0")
            .addHttpHeaders(scalaSeq)
            .withAuth(token, token, play.api.libs.ws.WSAuthScheme$BASIC$.MODULE$)
            .withBody(play.api.libs.json.Json.parse(createIterationBodyStr), play.api.libs.ws.JsonBodyWritables$.MODULE$.writeableOf_JsValue)
            .withMethod("PATCH")
            .execute())
        debug.error("it->" + it.otherIssueId + " await_url:" + baseUrl +"/${project}/_apis/wit/workitems/${workItem.id}" + createIterationBodyStr + "\nRESULT:" + result)
   
    }
} else {
    debug.error('links else error')
}
