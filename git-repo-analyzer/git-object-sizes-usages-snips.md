# Installing
I usually "install" the repo analyser in the CI(Jenkins etc.) job this way:
```#!/bin/bash
set -euo pipefail

if [[ -d code-utils ]]; then
    git -C code-utils fetch origin -ap
    git -C code-utils reset --hard origin/master
else
	git clone https://github.com/Praqma/code-utils.git
fi
```

# Get the repo to analyze
Either you have already cloned/update the repo from the SCM plugin of your CI system. You can do bare, mirror or sparse as the workspace is not needed. Or you can now clone it:
```
#!/bin/bash
set -euo pipefail

if [[ -d ${repo}.git ]]; then
  git -C {trepo} fetch origin -ap
else
  git clone --bare ${repo} --mirror ${repo}.git
fi
```
You now have the repo to analyze in your workspace


# Running it
```
bash code-utils/git-repo-analyzer/git-object-sizes-in-repo-analyzer.sh ${target_repo}.git
```

# Archiving
I usually 
