manager.listener.logger.println ("")
manager.listener.logger.println ("########################################################")
manager.listener.logger.println ("# Groovy script: Keep Upstream Builds Forever: START ")
manager.listener.logger.println ("########################################################")
manager.listener.logger.println ("")

import jenkins.model.*
import hudson.model.*

def setKeepLog(AbstractBuild build, boolean toggle_keep_forever ){
        manager.listener.logger.println("")
        manager.listener.logger.println("----------------------------------------------------------------------------------------------------------------------------------------------")
        manager.listener.logger.println("Upstream:" + build.getParent().getFullName() + " : " + build.number+ ":")
        manager.listener.logger.println("----------------------------------------------------------------------------------------------------------------------------------------------")
        manager.listener.logger.println(" : canToggleLogKeep(CURRENT) = " + build.canToggleLogKeep())
        manager.listener.logger.println(" : isKeepLog(CURRENT) = " + build.isKeepLog())
        manager.listener.logger.println("")
        manager.listener.logger.println(" ->  Update it" )
        build.keepLog(toggle_keep_forever)
        manager.listener.logger.println("")
        manager.listener.logger.println(" : isKeepLog (UPDATED): " + build.isKeepLog())
        manager.listener.logger.println("----------------------------------------------------------------------------------------------------------------------------------------------")
        manager.listener.logger.println("")
}

def handleUpstreamBuildCausesKeepLog(List<Cause> causes, boolean toggle_keep_forever ) {
  if (causes != null && !causes.isEmpty() ) {
    for ( Cause current : causes )  {
      if ( current instanceof Cause.UpstreamCause) {
        final Cause.UpstreamCause upstreamCause = (Cause.UpstreamCause) current;
        final String projectName = upstreamCause.getUpstreamProject();
        final Integer buildNumber = upstreamCause.getUpstreamBuild();
      
        final AbstractProject<?,?> upstreamProject = (AbstractProject<?,?>) manager.hudson.getItemByFullName(projectName);
        AbstractBuild upstream_build  = upstreamProject.getBuildByNumber(buildNumber)

        handleUpstreamBuildCausesKeepLog(upstream_build.getCauses(), toggle_keep_forever) 
        setKeepLog(upstream_build, toggle_keep_forever)

      }  else if ( current instanceof Cause.UserCause ) {
        Cause.UserCause user_cause = (Cause.UserCause)current;
        manager.listener.logger.println("NOTE: Cause for the build: User executed " + user_cause.getUserName());
      }
    }
  } else {  
    manager.listener.logger.println("causes != null && !causes.isEmpty()");
  }
}

def build = manager.build
def  toggle_keep_forever

def parsed_toggle_keep_forever = build.buildVariableResolver.resolve("toggle_keep_forever")
manager.listener.logger.println ("toggle_keep_forever parsed as env variable:" + parsed_toggle_keep_forever )

if ( parsed_toggle_keep_forever == null ||  parsed_toggle_keep_forever == "true" ) {
  toggle_keep_forever=true
}
if ( parsed_toggle_keep_forever == "false" ) {
  toggle_keep_forever=false
}
  

manager.listener.logger.println ("toggle_keep_forever:" + toggle_keep_forever )

handleUpstreamBuildCausesKeepLog(build.getCauses(), toggle_keep_forever)
setKeepLog(build, toggle_keep_forever )

manager.listener.logger.println ("")
manager.listener.logger.println ("########################################################")
manager.listener.logger.println ("# Groovy script: Keep Upstream Builds Forever: END")
manager.listener.logger.println ("########################################################")
manager.listener.logger.println ("")
