# Power Ping

Checks DNS look, TCP connection and ping and curl of http(s) addresses against a list of hosts in the configuration file.

Use if for example on a Jenkins build slave, to make sure all deployment target can be reach just before starting complex deployments. Typically relevant in cases with complex networking setup, and no so regularly deployment. Things can change over the weeks.

Obviously monitoring can be an alternative, but this checks from one host to another, not from a monitoring server.

## Config file

The configuration file is a YAML file with the following structure: 

```
defaults:
  web_server_ports: [80] 
env_prod:
  http://www.google.com: [web_server_ports]
  http://artifactory.macrohard.com: [web_server_ports, 50000]
env_qa:
  http://www.google.com: [web_server_ports]
  http://test.macrohard.com: [web_server_ports, 10000]
```

See [`config-example.yml`](config-example.yml)

## Usage

`groovy powerPing.groovy myConfigFile.yml env_prod env_qa`


## Roadmap and improvements

* support reporting in junit format, so each check is reported as a unit-test
* allow a configuration, globally, or per target, to fail the script if a check fail - interesting if used in a Jenkins job
* allow multiline host defintion, so the following repeated configuration becomes simpler:
```
  testdb1.praqma.net:
    ports: [database_standard_ports]
  testdb2.praqma.net:
    ports: [database_standard_ports]
  testdb3.praqma.net:
    ports: [database_standard_ports]
```
simpler as
```
  testdb1.praqma.net, testdb2.praqma.net, testdb2.praqma.net:
    ports: [database_standard_ports]
```
* allow a combination of configuration target, such as `GENERIC` in the `config-example.yml` or `QA` in `projectEnvironments.yml` to be executed based on environment variables. E.g. to be used in Jenkins job automation, to allow chosing configuration based on slave node name or something.

