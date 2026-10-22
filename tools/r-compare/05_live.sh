#!/bin/sh
# Rows 4 (C), 5, 6, 7, 8, 9 live through MATLAB, one session per approach (spec 025).
#   R_LIBS=<lib with the four packages> sh tools/r-compare/05_live.sh <build_dir>
set -u
REPO=$(pwd); BUILD=$1
for a in A B C Bfull; do
  log=$REPO/tools/r-compare/logs/05_live_$a.log
  Rscript tools/r-compare/live_rows.R "$a" > "$log" 2>&1
  sh tools/r-compare/sanitize.sh "$log" "$REPO" "$BUILD"
  echo "$a: $(grep -E '^ROW5|^ROW6' "$log" | tr '\n' ' ')"
done
