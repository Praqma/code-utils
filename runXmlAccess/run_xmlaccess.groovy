package XmlAccess

import XmlAccess.Command

/*****************************************************************************
/* File: run_xmlaccess.groovy
/* Usage: groovy run_xmlaccess [OPTIONS] URL SRCDIR
/* Options: -stopOnFailure  exits as soon as one of the commands fails
/* Purpose: Execute all enumerated xmlaccess scripts in the directory
/*          specified in 2nd argument against the portal server specified
/*          with the url in 1st argument
/* Requirements: The script assumes two environment variable as available
/*               DEPLOY_USER
/*               DEPLOY_PASS
/*               They represent the account used to deploy (run xmlaccess)
/*
/*****************************************************************************/

def cli = new CliBuilder(usage: 'groovy run_xmlaccess [OPTIONS] URL SRCDIR')
cli.stopOnFailure('stop the script as soon as a command fails')

def options = cli.parse(args)
assert options

assert options.arguments().size() == 2 : "Insufficient arguments. Requires Url and srcDir"
def url = options.arguments()[0]
def srcDir  = options.arguments()[1]

def deployUser = System.getenv('DEPLOY_USER')
assert deployUser : "Requires DEPLOY_USER environment variable"
def deployPass = System.getenv('DEPLOY_PASS')
assert deployPass : "Requires DEPLOY_PASS environment variable"

println "Portal URL: " + url
println "xmlaccess directory: " + srcDir

def files = []
def dir = new File(srcDir)
println "Files found:"
dir.eachFileMatch(~/\d-.*\.xml/) { file ->
    files << file
    println file.path
}

def failed
// .find breaks on return true, continues on return false.
// Clever trick to get stopOnFailure to work.
files.find { file ->
    try{
        String inPath = file.path
        String outPath = file.path + ".out"
        String command = "cmd /c xmlaccess -user $deployUser -password $deployPass -url $url -in $inPath -out $outPath"
        def exitCode = Command.run(command)
        if(exitCode != 0){
            println "Failed for $file with exit code $exitCode"
            failed = true
            return options.stopOnFailure
        }
    } catch (Exception ex){
        println "Failed for $file with Exception:\n$ex.message"
        println ex.stackTrace
        failed = true
        return options.stopOnFailure
    }
}
System.exit(failed ? 1 : 0)