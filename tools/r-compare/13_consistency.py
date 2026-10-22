"""Row 13: map every pyfsda.<name>(...) call in pyfsda's examples/README onto A, B, C.

    python tools/r-compare/13_consistency.py
"""

import json
import re
from pathlib import Path

PY_HELPERS = {"start", "stop", "engine", "fetch", "clear", "load", "FsdaEngine", "to_dataframe"}
PY_ONLY_KW = {"frames", "store"}          # pyfsda engine only; the R engine.py lacks them
generated = {r["name"] for r in json.loads(Path("tools/codegen/tmp_spec.json").read_text())}

calls = []
srcs = sorted(Path("packages/pyfsda/examples").glob("*.py")) + [Path("packages/pyfsda/README.md")]
for src in srcs:
    for m in re.finditer(r"pyfsda\.([A-Za-z]\w*)\(([^()\n]*(?:\([^()\n]*\)[^()\n]*)*)\)", src.read_text()):
        calls.append((src.name, m.group(1), m.group(2).strip()))

seen, routines, helpers, pyonly = set(), 0, 0, 0
print(f"{'pyfsda call':<58} | A / C                          | B")
for src, name, args in calls:
    key = (name, args)
    if key in seen:
        continue
    seen.add(key)
    kws = set(re.findall(r"\b([A-Za-z]\w*)\s*=", args))
    if name in PY_HELPERS:
        helpers += 1
        print(f"{name + '(' + args[:40] + ')':<58} | no R equivalent (pyfsda helper) | same")
        continue
    routines += 1
    r_args = args.replace("True", "TRUE").replace("False", "FALSE").replace("None", "NULL")
    bad = kws & PY_ONLY_KW
    if bad:
        pyonly += 1
    a = f"fsda${name}({r_args[:22]})" + (f" [drop {','.join(sorted(bad))}]" if bad else "")
    b = (f"{name}(...)" if name in generated else "not generated -> fsda_call()") + (" [drop]" if bad else "")
    print(f"{name + '(' + args[:46] + ')':<58} | {a:<30} | {b}")
print(f"\nSUMMARY distinct_calls={len(seen)} routine_calls={routines} helper_calls={helpers} "
      f"routine_calls_using_pyfsda_only_kwargs={pyonly} "
      f"B_generated_hits={sum(1 for n, a in seen if n in generated)}")
