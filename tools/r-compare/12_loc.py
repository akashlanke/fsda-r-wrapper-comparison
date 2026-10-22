"""Row 12: lines of R (and generator) per approach, split code / roxygen / comment.

    python tools/r-compare/12_loc.py [<build_dir>/fsdabridgeGenFull]
"""

import sys
from pathlib import Path


def count(paths) -> dict:
    c = {"files": 0, "code": 0, "roxygen": 0, "comment": 0}
    for p in paths:
        c["files"] += 1
        for line in Path(p).read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if not s:
                continue
            if s.startswith("#'"):
                c["roxygen"] += 1
            elif s.startswith("#"):
                c["comment"] += 1
            else:
                c["code"] += 1
    return c


def row(label, paths):
    c = count(paths)
    print(f"  {label:<52} files={c['files']:>3} code={c['code']:>5} "
          f"roxygen={c['roxygen']:>5} comment={c['comment']:>4}")


def py(label, path):
    lines = [l for l in Path(path).read_text(encoding="utf-8").splitlines() if l.strip()]
    print(f"  {label:<52} non-blank lines={len(lines)}")


A = Path("packages/fsdabridge")
G = Path("packages/fsdabridgeGen")
H = Path("tools/r-compare/hybrid")
print("A (fsdabridge)")
row("hand-written R/", sorted((A / "R").glob("*.R")))
row("hand-written tests/", sorted((A / "tests").rglob("*.R")))
print("B (fsdabridgeGen, 10 routines)")
row("generated wrappers R/fsda_*.R", sorted((G / "R").glob("fsda_*.R")))
row("generated call path R/zz_invoke.R", [G / "R" / "zz_invoke.R"])
row("runtime copied from A (engine.R, session.R)", [G / "R" / "engine.R", G / "R" / "session.R"])
py("generator tools/codegen/gen_r.py", "tools/codegen/gen_r.py")
py("hand-curated IR tools/codegen/tmp_spec.json", "tools/codegen/tmp_spec.json")
if len(sys.argv) > 1:
    F = Path(sys.argv[1])
    row("dry run, full IR: generated R/fsda_*.R", sorted((F / "R").glob("fsda_*.R")))
print("C (fsdabridgeHybrid = A + overlay)")
row("A's R/ as copied (make_hybrid.R then drops 23 lines)", sorted((A / "R").glob("*.R")))
row("overlay R/ (completion.R, help.R)", sorted((H / "R").glob("*.R")))
row("overlay tests/", sorted((H / "tests").rglob("*.R")))
row("builder make_hybrid.R", ["tools/r-compare/make_hybrid.R"])
py("routine list builder make_routine_list.py", "tools/r-compare/make_routine_list.py")
