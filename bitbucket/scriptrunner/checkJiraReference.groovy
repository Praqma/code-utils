/*
  This snippet allows to bypass commits if they are not in "../ready/.." branch, as described in Git Phlow.

  Checks that commits reference JIRA issues and that they're assigned to the committer (checked with email 
  and name only).  Jira issues must be in progress.

  Accessed via the application link, and use REST API calls.
*/

import com.atlassian.bitbucket.commit.Commit
import com.atlassian.bitbucket.commit.CommitService
import com.atlassian.bitbucket.commit.CommitsBetweenRequest
import com.atlassian.bitbucket.commit.CommitsBetweenRequest
import com.atlassian.bitbucket.event.hook.RepositoryHookEvent
import com.atlassian.bitbucket.repository.RefChange
import com.atlassian.bitbucket.repository.Repository
import com.atlassian.bitbucket.repository.SimpleMinimalRef
import com.atlassian.bitbucket.util.Page
import com.atlassian.bitbucket.util.PageRequest
import com.atlassian.bitbucket.util.PageRequestImpl

import com.atlassian.applinks.api.ApplicationLinkService
import com.atlassian.applinks.api.application.jira.JiraApplicationType

import com.atlassian.sal.api.component.ComponentLocator
import com.atlassian.sal.api.net.Response
import com.atlassian.sal.api.net.ResponseException
import com.atlassian.sal.api.net.ResponseHandler

import com.atlassian.bitbucket.auth.AuthenticationContext
import com.atlassian.bitbucket.user.UserService

import com.atlassian.bitbucket.user.ApplicationUser
import com.atlassian.bitbucket.user.Person

import com.atlassian.bitbucket.hook.HookResponse

import com.onresolve.scriptrunner.canned.bitbucket.util.BitbucketCannedScriptUtils

import groovy.json.JsonBuilder

import static com.atlassian.sal.api.net.Request.MethodType.GET

import groovy.json.JsonSlurper
import groovy.json.JsonParserType

import java.util.regex.Pattern
import java.util.regex.Matcher
import java.util.ArrayList

def accepted = false;
def repository = repository as Repository

CommitService commitService = ComponentLocator.getComponent(CommitService.class);

public String integrationBranch(String refChange){
    List parts = refChange.split("/").asType(List)
    parts.remove(parts[-1])
    parts.remove(parts[-1])
    // there's always a matching integration branch from  
    parts.add("master")
    return parts.join("/")
}

public ArrayList<String> findJiraKeys(String commitMsg){
    ArrayList<String> matches = new ArrayList<>();
    def m = commitMsg =~ /((?<!([A-Z0-9]{1,10})-?)[A-Z0-9]+-\d+)/
    m.iterator().each {
        // don't mind the warning from the ScriptRunner console
        matches.add(it[0]);
    }
    return matches;
}

// turn this into a class!
public Map checkJiraReference(String jiraKey, Person user){
    try {
        def appLinkService = ComponentLocator.getComponent(ApplicationLinkService)
        def appLink = appLinkService.getPrimaryApplicationLink(JiraApplicationType)
        def applicationLinkRequestFactory = appLink.createImpersonatingAuthenticatedRequestFactory()
	log.warn("/rest/api/latest/issue/" + jiraKey)
        def request = applicationLinkRequestFactory.createRequest(GET, "/rest/api/latest/issue/" + jiraKey)
        def result = request.execute()
        
        JsonSlurper jsonSlurper = new JsonSlurper()
      	def parser = new JsonSlurper().setType(JsonParserType.LAX)
      	def json = parser.parseText(result) as Map
        return json as Map
    } catch(Exception e){
        return [:];
    }
}

public boolean checkStatus(String status){
    return status == "In Progress"
}

public boolean checkCommitAuthor(Person person, Map assignee){
    return person.emailAddress == assignee.emailAddress && person.name == assignee.name;
}

ArrayList<String> jiraReferences;

String branchIntegration;
StringBuilder stringBuilder = new StringBuilder();

for(RefChange refChange in refChanges){
    // we don't care about dev branches, only the Pre-Tested Integration stuff
    if(refChange.refId.indexOf("/ready/") == -1){
        hookResponse.out().println(BitbucketCannedScriptUtils.wrapHookResponse(new StringBuilder("Not a ready branch")));
        accepted = true;
        break;
    }

    PageRequest nextPage = new PageRequestImpl(0, 25);
    branchIntegration = integrationBranch(refChange.ref.displayId.toString())
    CommitsBetweenRequest request = new CommitsBetweenRequest.Builder(repository)
    	.exclude(branchIntegration)
    	.include(refChange.getToHash())
    	.build();

    PageRequest pageRequest = new PageRequestImpl(0, 25);

    Page<Commit> commits = commitService.getCommitsBetween(
        request,
        pageRequest
    );
    
    for (Commit commit in commits.getValues()) {
    	// limit to just the first line
        if(commit.getParents().size() >= 2){
            stringBuilder.append("Please don't make merge commits\n");
            accepted = false;
        }
        jiraReferences = findJiraKeys(commit.getMessage());
        if(jiraReferences.size() == 0){
            stringBuilder.append(commit.id + ": '" + commit.getMessage() + "' does not reference any JIRA issues\n");
        }
        else {
            stringBuilder.append("Processing :" + commit.id + ": '" + commit.getMessage() + "'\n");
            for (String reference in jiraReferences){
                Map jiraReference = checkJiraReference(reference, commit.author) as Map;
                if(jiraReference.size() != 0) {
                    if(!checkCommitAuthor(commit.getAuthor(), jiraReference.fields.assignee) || !checkStatus(jiraReference.fields.status.name)){
                        stringBuilder.append("  - " + reference + " : assigned == ${jiraReference.fields.assignee.name} and status == ${jiraReference.fields.status.name}\n")
                        accepted = false;
                    } else {
                        stringBuilder.append("  - " + reference + " : assigned == committer and status == In Progress\n")
                    }
                }
            }
        }
    }
}

hookResponse.out().println("             Summary of your commits");

if(!accepted){
    hookResponse.out().println(BitbucketCannedScriptUtils.wrapHookResponse(stringBuilder));
    return false;
} else {
    hookResponse.out().println(BitbucketCannedScriptUtils.wrapHookResponse(new StringBuilder("You did a good job, all commits reference valid JIRA issues")))
    return true;
}
