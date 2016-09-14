REPOSITORY_URL = 'https://github.com/Praqma/code-utils.git'
MAIN_BRANCH = 'master'
REMOTE_NAME = 'origin'
JOB_LABELS = 'dockerhost1'
AUTOMATION_USER = 'ReleasePraqma'
NUM_OF_BUILDS_TO_KEEP = 100
// id of a credential created on the Jenkins master
GITHUB_PRAQMA_CREDENTIALS = '100247a2-70f4-4a4e-a9f6-266d139da9db'

INTEGRATION_JOB_NAME = 'code-utils_-_integrate_GEN'

job(INTEGRATION_JOB_NAME) {
    logRotator {
        numToKeep(NUM_OF_BUILDS_TO_KEEP)
    }
    description("Integrate changes from ready branches to master, no verification, \nonly to ensure we follow the A Pragmatic Workflow: http://www.praqma.com/stories/a-pragmatic-workflow/" )
    // Setting quit period as both seed job and the integration job are triggerede by Github push events
    // and we want the seed job to run first.
    quietPeriod(15)
    label(JOB_LABELS)

    properties {
        ownership {
            primaryOwnerId('bue')
            coOwnerIds('bue')
        }
    }

    authorization {
        permission('hudson.model.Item.Read', 'anonymous')
    }

    scm {
        git {
            remote {
                name(REMOTE_NAME)
                url(REPOSITORY_URL)
                // Chose credential created on the Jenkins master globally with the id GITHUB_PRAQMA_CREDENTIALS
                credentials(GITHUB_PRAQMA_CREDENTIALS)
            }
            branch("$REMOTE_NAME/ready/**")

            extensions {
                wipeOutWorkspace()
            }
        }
    }

    triggers {
        githubPush()
    }

    steps {
        shell('echo "This job is only for integration of changes from ready branches. Currently no automated verification."')
    }

    wrappers {
        buildName('${BUILD_NUMBER}#${GIT_REVISION,length=8}(${GIT_BRANCH})')
        pretestedIntegration("SQUASHED", MAIN_BRANCH, REMOTE_NAME)
    }

    publishers {
        pretestedIntegration()
        mailer('bue@praqma.net', false, true)
    }

}

