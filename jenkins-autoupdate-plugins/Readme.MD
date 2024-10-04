# Jenkins Pipeline to update Jenkins plugins

This pipeline and script will install all updatable plugins.

It can be a struggle to keep Jenkins plugin updated, and I have seen many installations running with plugins that has been outdated years ago, and the
more versions you are behind the more reluctant you are to update.
The cure is update when updates are available.

It utilizes the [jenkins-cli](https://www.jenkins.io/doc/book/managing/cli/) `list-plugins` command to get the list
of installed plugins, and utilizes that the version plugin's version number will be enclosed in parenthesis if there is an update version of the plugin.

The output from `jenkins-cli list-plugins` is formatted like this example:

```text
ansible                            Ansible plugin                                  403.v8d0ca_dcb_b_502
ant                                Ant Plugin                                      511.v0a_a_1a_334f41b_
antisamy-markup-formatter          OWASP Markup Formatter Plugin                   (162.v0e6ec0fcfcf6)
apache-httpcomponents-client-4-api Apache HttpComponents Client 4.x API Plugin     4.5.14-208.v438351942757
...
```

in the example can be updated. An this pipeline *will* update to the new version.

## Requirements  

* Jenkins server configured to support [jenkins-cli](https://www.jenkins.io/doc/book/managing/cli/)
* A user credential with permission to update plugins
* The `Safe Restart Plugin`

## Setup

1. Configure a user with administrator permissions and create an api token for this user
2. Download jenkins-cli-jar from your <http://yourJenkinsUrl/jnlpJars/jenkins-cli.jar>
3. Verify jenkins responds to jenkins-cli by executing:

    ```bash
    java -jar jenkins-cli.jar -s <jenkins_url> -auth <theAdminUser>:<theAdminUsersAPIToken> list-plugins 
    ```

4. Create a Jenkins Secret type `username with password`, with the values from step 1. Note of it's ID value
5. Edit Jenkinsfile and replace `AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA` with the ID value from step 4.
6. Ensure you have functional, regular back of Jenkins
7. Create the pipeline and make it run on.
