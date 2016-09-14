# Jenkins job DSL

The Jenkins job DSL groovy scripts creates the job for this project.

You need a seed job to run the Job DSL script, that is for now manually created.

Configuration:

* on github push on this repo, start the job
* process the Jenkins job DSL script: `jenkins-job-dsl/seed.groovy`
* disable removed jobs
* ignore removed views
* NOTE is looks on ready branches, as we suppose job dsl changes comes in this way also.
