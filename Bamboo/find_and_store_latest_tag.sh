# For Bamboo: Find and store latest release tag.
#
# Script to find the lastest release tag and store it in a properties file
#
# This allows for environment injection in a later step in the build. 
# (this is currently the easiest way in Bamboo to pass env values).
#
# The script find the latest tag matching "Rel.*". 
# 
# NOTE: If no previous tag is found,
# the script creates a Rel_0.0.0 tag on the initial commit.
# This is a opinionated design choice and might not be what you want.
# It was chosen in context as an easy alternative to make later steps always work.
#

# Find the latest release tag using git describe
tag=git describe --tags --match 'Rel.*' --abbrev=0

# If the above command fails, it is probably because no matching tag was found
# So we actually solve this by adding a 0.0.0 tag to the initial commit.
if [ $? -ne 0 ]; then
	# Find initial commit (find commit with zero parents)
	initial=git rev-list --max-parents=0 HEAD
	tag=Rel_0.0.0
	# Tag the found initial commit as Rel_0.0.0
	git tag -m "Initial commit tagged as Rel_0.0.0" $tag $initial 

	# Do the annoying workaround needed because Bamboo plan repos are
	# cloned from a local filesystem cache, so we can't push to "origin".
	# Luckily, Bamboo provides a variable with the location of the original repo
	# So we can add that as a new remote
	git remote add central ${bamboo.planRepository.repositoryUrl}
	git remote update central
	# Push the Rel_0.0.0 tag
	git push central $tag
fi

# write tag description as latest_tag to a gitinfo.properties file
"latest_tag=$tag" | out-file -encoding ascii gitinfo.properties


