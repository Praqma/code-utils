#!/bin/bash

# Hard coded values
SCRIPT_VERSION="1.0.0"
ARTIFACTORY_IMAGE="jfrog-docker-reg2.bintray.io/jfrog/artifactory-pro:latest"
ARTIFACTORY_PORT="8081:8081"
CONTAINER_NAME="artifactory_pro_latest_test"
TEST_SCRIPT="ArtifactHandlerTest.groovy"

#Commands: Change path if needed.
ECHO="echo"
WHOAMI="whoami"
DOCKER="docker"
GROOVY="groovy"
SLEEP="sleep"
SLEEP_INTERVAL=30


function print_help()
{
    $ECHO ""
    $ECHO "--------------------------------------------"
    $ECHO "It is expected that this script is located in the same directory as the test script!"
    $ECHO ""
    $ECHO "Usage: ./testArtifactory.sh"
    $ECHO ""
    $ECHO "SCRIPT_VERSION=$SCRIPT_VERSION"
    $ECHO "--------------------------------------------"

}
function usage()
{
    print_help
    1>&2; exit 1;
}

# TODO: THIS NEEDS WORK - We need to parse the output to see if it is there.
function cleanupContainer(){
    $ECHO "Check if container already exists."
    local CMD="$DOCKER ps --filter 'name=$CONTAINER_NAME'"
    $CMD
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: Could not CHECK for container: $CONTAINER_NAME!!!"
        exit 1
    fi

    $ECHO "Removing $CONTAINER_NAME"
    CMD="$DOCKER rm $CONTAINER_NAME"
    $CMD
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: Could not CHECK for container: $CONTAINER_NAME!!!"
        exit 1
    fi
}

function pullImage(){
    $ECHO "Pulling latest image..."
    local CMD="$DOCKER pull $ARTIFACTORY_IMAGE"
    $CMD
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: Could not PULL image: $ARTIFACTORY_IMAGE!!!"
        exit 1
    fi
}

function runContainer(){
    local CMD="$DOCKER run -d --name $CONTAINER_NAME -p $ARTIFACTORY_PORT $ARTIFACTORY_IMAGE"
    $CMD
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: Could not START container: $CONTAINER_NAME!!!"
        exit 1
    fi

    $ECHO "Waiting $SLEEP_INTERVAL for Artifactory to start..."
    CMD="$SLEEP $SLEEP_INTERVAL"
    $CMD
}

function setupDocker()
{
    $ECHO "Setting up Docker..."
    #cleanupContainer
    pullImage
    runContainer
}

function tearDownDocker(){
    $ECHO "Tearing down Docker..."
    local CMD="$DOCKER stop $CONTAINER_NAME"
    $CDM
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: Could not STOP container: $CONTAINER_NAME!!!"
        exit 1
    fi

    $ECHO "Waiting $SLEEP_INTERVAL for Artifactory to stop..."
    CMD="$SLEEP $SLEEP_INTERVAL"
    $CMD

    CMD="$DOCKER rm $CONTAINER_NAME"
    $CMD
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: Could not REMOVE container: $CONTAINER_NAME!!!"
        exit 1
    fi
}

function runTests(){
    $ECHO "Running tests..."
    local REPO1="libs-content-test"
    local REPO2="libs-content-local"
    local CMD="$GROOVY ArtifactHandler.groovy --action create-repo --repository $REPO1 --web-server http://localhost:8081/ --userName admin --password password"
    $CMD
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: Could not create REPO: $REPO1!!!"
        exit 1
    fi

    CMD="$GROOVY ArtifactHandler.groovy --action 'create-repo' --repository '$REPO2' --web-server 'http://localhost:8081/' --userName 'admin' --password 'password'"
    #$CMD
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: Could not create REPO: $REPO2!!!"
        exit 1
    fi

    CMD="$GROOVY $TEST_SCRIPT"
    $CMD
    if [ "$?" -ne 0 ]; then
        $ECHO "ERROR: ARTIFACTORY tests have failures!!!"
        exit 1
    fi
}

setupDocker
runTests
tearDownDocker