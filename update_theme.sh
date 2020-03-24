#!/usr/bin/env bash

# Display available updates.
cd themes/jane
git fetch
git log --pretty=oneline --abbrev-commit --decorate HEAD..origin/master
cd ../../

# Update submodule.
git submodule update --remote --merge
