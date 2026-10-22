#!/bin/sh
# Dry run for approach B (spec 025): parse the whole toolbox, generate wrappers
# for every IR record, then build + check --as-cran. Measures size and time only;
# the output stays in <build_dir> and is never committed.
#   sh tools/r-compare/12_dryrun_full.sh <fsda_root> <build_dir>
set -u
REPO=$(pwd); FSDA=$1; BUILD=$2; LOG=$REPO/tools/r-compare/logs/12_dryrun_full.log
mkdir -p "$BUILD"
{
  echo "## parse_fsda.py over the full toolbox"
  t0=$(python3 -c 'import time; print(time.time())')
  python3 -I tools/codegen/parse_fsda.py --fsda-root "$FSDA" --output "$BUILD/IntRep_full.json" 2> "$BUILD/parse_full.stderr"
  t1=$(python3 -c 'import time; print(time.time())')
  echo "parse_seconds=$(python3 -c "print(round($t1-$t0,2))")"
  echo "parse_warnings=$(wc -l < "$BUILD/parse_full.stderr" | tr -d ' ')"
  echo "ir_records=$(python3 -c "import json; print(len(json.load(open('$BUILD/IntRep_full.json'))))")"
  echo "ir_bytes=$(wc -c < "$BUILD/IntRep_full.json" | tr -d ' ')"
  echo "## gen_r.py over the full IR (with roxygen)"
  python3 -I tools/codegen/gen_r.py --ir "$BUILD/IntRep_full.json" --out "$BUILD/fsdabridgeGenFull" --package fsdabridgeGenFull --roxygen 2>&1 | tail -1
  echo "R_files=$(ls "$BUILD/fsdabridgeGenFull/R" | wc -l | tr -d ' ')  Rd_files=$(ls "$BUILD/fsdabridgeGenFull/man" | wc -l | tr -d ' ')"
  echo "R_lines=$(cat "$BUILD"/fsdabridgeGenFull/R/fsda_*.R | wc -l | tr -d ' ')  Rd_lines=$(cat "$BUILD"/fsdabridgeGenFull/man/*.Rd | wc -l | tr -d ' ')"
  echo "source_bytes=$(du -sk "$BUILD/fsdabridgeGenFull" | cut -f1)KB"
  echo "## R CMD build + check --as-cran"
  cd "$BUILD"
  t0=$(date +%s)
  R CMD build --no-manual fsdabridgeGenFull > check_full.log 2>&1
  tarball=$(ls -t fsdabridgeGenFull_*.tar.gz | head -1)
  echo "tarball_bytes=$(wc -c < "$tarball" | tr -d ' ')"
  R CMD check --as-cran --no-manual "$tarball" >> check_full.log 2>&1
  echo "check_wall_seconds=$(( $(date +%s) - t0 ))"
  grep -E "^Status:" check_full.log
  grep -E "\.\.\. (NOTE|WARNING|ERROR)" -A8 check_full.log | head -60
} > "$LOG" 2>&1
sh "$REPO/tools/r-compare/sanitize.sh" "$LOG" "$REPO" "$BUILD"
cat "$LOG" | head -30
