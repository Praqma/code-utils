#!/usr/bin/env bash

# This little sh file intends to generate a Slack-friendly list of branches merged into main that will be included in a new build/release.
# It is necessary to replace <ORGANIZATION> with the Repo Organization/Owner name and <REPO> with the repository name.


# First sed mapping handles the standard merges done by a GitHub PR.
# Second sed mapping handles the SQUASH merges done on a GitHub PR.
# ...Last sed mapping handles any remaining message that has not been transformed already by the previous rules.
git log --first-parent --format="%s:%an:%h" $(git describe --abbrev=0 --tags --match='deploy[/-]*')...main \
    | grep -v "i18n push & pull" \
    | sed -e 's/Merge pull request #\([0-9]*\) from <ORGANIZATION>\/\(.*\):\([^:]*\):[^:]*$/> https:\/\/github.com\/${ORGANIZATION}\/<REPO>\/pull\/\1 \`\2\` (\3)/g' \
    | sed -e 's/^\([^>].*\) [(]#\([0-9]*\)[)]:\([^:]*\):[^:]*$/> https:\/\/github.com\/<ORGANIZATION>\/<REPO>\/pull\/\2 \1 (\3)/g' \
    | sed -e 's/^\([^>].*\):\([^:]*\):\([^:]*\)$/> https:\/\/github.com\/<ORGANIZATION>\/<REPO>\/commit\/\3 :warning: \1 (\2)/g'



# SAMPLE OUTPUT after a sh scripts/print_next_release.sh call (check README for even better output):
#
# > https://github.com/<ORGANIZATION>/<REPO>/pull/4829 `branch-name-1` (author-name-1)
# > https://github.com/<ORGANIZATION>/<REPO>/pull/4811 `branch-name-2` (author-name-2)
#
# On Slackm ">" will be part of a UL, the PR urls will be formatted with links and the branch names in code-like formatting.