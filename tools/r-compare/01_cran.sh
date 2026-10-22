#!/bin/sh
# Row 1: R CMD build + R CMD check --as-cran for A, B, C (spec 025).
# Live MATLAB tests stay skipped (FSDA_LIVE unset).
#   sh tools/r-compare/01_cran.sh <build_dir>
set -u
REPO=$(pwd); BUILD=$1; LOGS=$REPO/tools/r-compare/logs
mkdir -p "$BUILD" "$LOGS"
[ -d "$BUILD/fsdabridgeHybrid" ] || Rscript tools/r-compare/make_hybrid.R "$BUILD/fsdabridgeHybrid" >/dev/null 2>&1
unset FSDA_LIVE
for pkg in packages/fsdabridge packages/fsdabridgeGen "$BUILD/fsdabridgeHybrid"; do
  name=$(basename "$pkg")
  log=$LOGS/01_cran_$name.log
  (
    cd "$BUILD"
    t0=$(date +%s)
    R CMD build --no-manual "$( cd "$REPO" && cd "$pkg" && pwd )" > "$log" 2>&1
    tarball=$(ls -t "${name}"_*.tar.gz | head -1)
    _R_CHECK_FORCE_SUGGESTS_=false R CMD check --as-cran --no-manual "$tarball" >> "$log" 2>&1
    t1=$(date +%s)
    echo "WALL_SECONDS=$((t1 - t0))" >> "$log"
  )
  sh tools/r-compare/sanitize.sh "$log" "$REPO" "$BUILD"
  printf '%s: ' "$name"; grep -E "^Status:|WALL_SECONDS" "$log" | tr '\n' ' '; echo
done
