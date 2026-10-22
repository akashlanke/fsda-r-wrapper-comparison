#!/bin/sh
# Strip machine-specific paths from a log so it can be committed (spec 025).
#   sanitize.sh <file> <repo_root> <build_dir>
sed -i.bak -e "s|$2|<repo>|g" -e "s|$3|<build>|g" -e "s|$HOME|~|g" "$1" && rm -f "$1.bak"
