# Tests

This just describes an idea of testing code-utils.

Idea: Be able to test all our code-utils, as a _black box_ - the say we use them on Jenkins and the automated setups.

So typically this means, but is not limited to, calling a script with parameters.

## How to

This directory contain a test script, to run tests towards the different scripts in the repository.

Test script takes two parameters:

* platform: Windows or Linux
* testsuite: functional (later maybe unit, regression ...)

Since this is to be executed from a Jenkins job, upon changes in the repository, it needs to be cross platform as we want tests to run on the two platforms.

    groovy run_tests.groovy $platform $testsuite

The groovy script will execute, based on platform either:

    ./run_tests_$platform.sh $testsuite
    ./run_tests_$platform.bat $testsuite

The script will chose which tests to include in a test suite based on a include file (which is cross-platform): $testsuite/tests.inc`. E.g. `functional/tests.inc`.



## Info

Unit testing in Bash:

* http://stackoverflow.com/a/1339454
* http://stackoverflow.com/a/27859950
* http://stackoverflow.com/a/14009705
* http://testanything.org/producers.html
* https://github.com/sstephenson/bats

TAP: 
> If Bats is not connected to a terminal—in other words, if you run it from a continuous integration system, or redirect its output to a file—the results are displayed in human-readable, machine-parsable TAP format.
https://github.com/sstephenson/bats#running-tests


Windows ???

* http://blog.pluralsight.com/test-powershell-with-whatif

