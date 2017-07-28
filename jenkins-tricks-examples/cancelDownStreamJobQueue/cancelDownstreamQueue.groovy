manager.listener.logger.println ("")
manager.listener.logger.println ("####################################################################")
manager.listener.logger.println ("# Groovy script: Cancelling downstream queue before triggering them ")
manager.listener.logger.println ("####################################################################")
manager.listener.logger.println ("")

//import jenkins.model.Jenkins
def jenkinsQueue = manager.hudson.instance.queue

def downstream_jobs = manager.build.getParent().getDownstreamProjects()

def downstream_job_name = []
downstream_jobs.each { job ->
   downstream_job_name.add( job.getFullName()) 
}

downstream_job_name.each { job_name ->
    manager.listener.logger.println ("Downstream project: " + job_name)
    def queue = []
    jenkinsQueue.getItems().each {  queue_item ->
        if ( queue_item.task.getFullName() == job_name ) { 
           queue.add(queue_item)
        }    
    }

    def queue_list = []
    queue.each { queue_item -> 
           queue_list.add( queue_item.getId()) }

    if ( queue_list.size() == 0 ) {
        manager.listener.logger.println ("There is no jobs in the queue of: " + job_name )
    } else {
        queue_list.each { queue_id ->
        manager.listener.logger.println ("Cancelling queue item: " + queue_id + " of job: " + job_name )
        jenkinsQueue.doCancelItem(queue_id) 
        }
    }
}
manager.listener.logger.println ("")
manager.listener.logger.println ("####################################################################")
manager.listener.logger.println ("# Groovy script: DONE ")
manager.listener.logger.println ("####################################################################")
manager.listener.logger.println ("")
