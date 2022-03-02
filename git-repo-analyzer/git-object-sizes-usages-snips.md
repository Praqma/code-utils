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
You now have the repo to analyze in your workspace.
You can also at this stage add a `git lfs migrate` or `git filter-repo` to change the history and analyze the impack of your efforts ala

## LFS migrate
```
  git lfs migrate import -y --everything \
      --include="\
*.tar,*.bz2,*.mat,*.zip,*.wav,*.elf,*.exe,*.cof,*.f32,*.sdf,*.obj,*.dll,*.blob,*.pdb,*.a,*.dbg,*.bmp,*.pcm,*.yuv\
,*.bsc,*.dfu,*.png,*.jpg,*.pdf,*.ai,*.doc,*.docx,*.ppt,*.pptx,*.xls,*.xlsx\
,*.mp3,*.pyd,*.so,*.rom,*.mdl,*.jar,*.fig,*.bin,*.lib\
,*.Lib,*.EXE,*.LIB,*.PCM,*.PNG\
,*.Exe\
,GRU512_res_mel_GRUweights_bestepoch\
,C_voice_av_imag,C_voice_av_real,C_noise_av_imag,C_noise_av_real\
"
```

## Filter-repo 
```
filter_repo_file="../filter-repo-clean-file.txt" && rm -f ${filter_repo_file}

IFS=' '
for split_path in ${split_paths}; do
	echo "${split_path}" >> $filter_repo_file
done

git filter-repo \
    --force \
    --replace-refs delete-no-add \
    --paths-from-file $filter_repo_file

git gc --prune

du -sh ./objects
```


# Running it
```
bash code-utils/git-repo-analyzer/git-object-sizes-in-repo-analyzer.sh ${target_repo}.git
```

# Archiving
I usually archive the `*.txt` for later analyzis and sharing etc
