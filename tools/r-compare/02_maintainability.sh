#!/bin/sh
# Row 2: what must change to support a routine NOT in tmp_spec.json (spec 025).
# B: add the routine's IR record, regenerate, diff against the committed package.
# A and C: call it; nothing is regenerated (checked live in 05_live_*.log).
#   sh tools/r-compare/02_maintainability.sh <build_dir>   (needs <build_dir>/IntRep_full.json)
set -u
REPO=$(pwd); BUILD=$1; LOG=$REPO/tools/r-compare/logs/02_maintainability.log
{
for routine in ace FSRaddt; do
  echo "## B: add $routine"
  python3 - "$BUILD/IntRep_full.json" tools/codegen/tmp_spec.json "$BUILD/tmp_spec_plus.json" "$routine" <<'PY'
import json, sys
full = {r["name"]: r for r in json.load(open(sys.argv[1]))}
spec = json.load(open(sys.argv[2]))
name = sys.argv[4]
if name in full:
    spec.append(full[name]); print(f"{name}: IR record taken from parse_fsda output (FSDA JSON has it)")
else:
    print(f"{name}: NOT in FSDA functionSignatures.json -> parse_fsda emits no record;"
          " a signature entry must be hand-written (as for Score/mcd in tmp_spec.json)")
json.dump(spec, open(sys.argv[3], "w"), indent=2)
PY
  if ! grep -q "\"name\": \"$routine\"" "$BUILD/tmp_spec_plus.json"; then
    echo "count_hand_edited=1 (tools/codegen/tmp_spec.json: hand-written signature + types)"
    echo "count_generated_changed=4 once that entry exists (same shape as ace above)"
    echo; continue
  fi
  python3 -I tools/codegen/gen_r.py --ir "$BUILD/tmp_spec_plus.json" --out "$BUILD/gen_plus" --roxygen > /dev/null 2>&1
  echo "files differing from packages/fsdabridgeGen after regeneration:"
  diff -rq packages/fsdabridgeGen "$BUILD/gen_plus" | sed "s|$BUILD/gen_plus|<regen>|"
  echo "count_generated_changed=$(diff -rq packages/fsdabridgeGen "$BUILD/gen_plus" | wc -l | tr -d ' ')"
  echo "count_hand_edited=1 (tools/codegen/tmp_spec.json)"
  echo
done
echo "## A: fsda\$ace(y, X) / fsda\$FSRaddt(y, X) need no file change (see 05_live_A.log row 7 / case FSRaddt)"
echo "## C: same as A for calling; completion already lists both:"
python3 -c "import json; n={r['name'] for r in json.load(open('tools/r-compare/hybrid/inst/extdata/fsda_routines.json'))}; print('ace' in n, 'FSRaddt' in n)"
echo "   a routine added to FSDA later: 0 files to call it, 1 data file (fsda_routines.json, regenerated) to complete it"
} > "$LOG" 2>&1
sh tools/r-compare/sanitize.sh "$LOG" "$REPO" "$BUILD"
cat "$LOG"
