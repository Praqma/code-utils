# Transform and run script

The `transformAndRun` script transforms another script, before for using it in command that takes the script as input.


Eg. 

`wsadmin.bat -conntype SOAP -host localhost -port 10033 -user myusername -password mypassword -lang jython -f my-was-deploy-python-script.py -o deploy`

The idea is to make the `transformAndRun`-script, execute the above command, but before it executes the command itself it replaces some "place holders" with real values in the Python script called `my-was-deploy-python-script.py`.
The Python script used as input in the command often itself contain user names and passwords, but they shouldn't be hard-coded in the script but comes from for example the environment.
Then it executes the command using the transformed script, and finally cleans up the transformed file.

## Script flow

The script will - in order - have the following flow:

* transform commands in the configuration file using environment variables
* transform files using environment variables
* transform files using the transformation map
* run commands
* clean up transformation

Any excess key or key not found after the transformation will be reported as an error and the script will fail.


## wsadmin example

Follow later... you're welcome to contribute.

## Simple example

Run the script, passing in the config file as an argument. You will have to set the environment variable ENV_SECRET_WEAPON to successfully run the example:

`export ENV_SECRET_WEAPON='a chainsaw' && groovy transformAndRun.groovy config.yml`

It also uses environment variable USER, but that's usually already set.

The config file is a YAML file containing file and command entries. File entries are passed in as a map: [transformTarget, transformMap].
Commands are just listed as they would be executed in the shell.

Example configuration:

`config.yml`:

```
files:
- [story.txt, transform.yml]
commands:
- echo $USER is going to tell you a wonderful story.
- echo This is a story involving $ENV_SECRET_WEAPON!
- cat story.txt
```

Transform target files can be parametrized using the transform map files.

For example:

`transform.yml`: 

```
CLIENT: Jimmy
DESIRED_ACTION: play video games
SUPERIOR: mother
REQUIRED_TASK: clean his room
```

`story.txt`:

```
$CLIENT cannot $DESIRED_ACTION yet. $SUPERIOR told him to $REQUIRED_TASK first.
Luckily, $CLIENT can use his secret weapon, $ENV_SECRET_WEAPON, to $DESIRED_ACTION without having to $REQUIRED_TASK
```

## Conventions

* **It is a good conventions to prefix keys that uses environment variables with `ENV`.**
* **Passwords**? They should come from the environment of the build system. So have two choices:
** In the story.txt use $ENV_DEPLOY_USER_PASSWORD and it will be replaced. No need to mention this in the tranform map.
** For clarity, mention the the key in the transform map, then transform that first and use. It will then look like this in the transform map and configuration file:
transform.yml`: 

```
CLIENT: Jimmy
DESIRED_ACTION: play video games
SUPERIOR: mother
PASSWORD: $ENV_DEPLOY_USER_PASSWORD
REQUIRED_TASK: clean his room
```

`config.yml`:

```
files:
- [transform.yml, transform.yml]
- [story.txt, transform.yml]
commands:
- echo $USER is going to tell you a wonderful story.
- echo This is a story involving $ENV_SECRET_WEAPON!
- cat story.txt
```

_That will also clean up transform.yml afterwards automatically._



## Design and notes

The transform targets are expanded using Groovy's [Simple Template Engine](http://docs.groovy-lang.org/next/html/documentation/template-engines.html#_simpletemplateengine).

The script expands all the files, then runs all the commands. Then the transformed file is automatically cleaned up.

This means that the below configuration won't work properly, as *you can not transform the same file twice*:

```
files:
- [file.txt, mapX.yml]
- [file.txt, mapY.yml]
commands:
- cat file.txt
- cat file.txt
```


There is no debug switch on the script, to skip the clean up of the transformed file. This is deliberately to avoid leaving sensitive information around.
If you want to debug, you can always run `cat mytransformedfile.txt` as the first command to see if it works.


We have explicitly made the script replace environment variables in the command and files, to be able to be more cross-platform.
The command `cat $myfile` would work on linux as the system would automatically expand the environment variable when executing the command. If the environment variable was defined obviously.
On Windows we would have to write `cat %myfile%`. So we always uses $myfile and replaces with actual values.

### Limitations

You can have $some-word inside neither configuration file or the file being transformed without it will be interpreted as something that needs to be replaced.