# Scripts for Bamboo stuff

## Find latest release tag and store it for later
`find_and_store_latest_tag.sh` finds the latest tag matching a hardcoded pattern. 
It stores this as a property in a gitinfo.properties file. 
This allows for environment injection in a following build step.

If no tag is found, it will actually create and push a Rel_0.0.0 tag
