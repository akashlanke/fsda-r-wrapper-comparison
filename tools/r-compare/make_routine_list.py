"""Write the FSDA routine list that approach C's completion reads (spec 025).

Uses the codegen enumerator (Contents.m inventory) and the JSON parser, so the
list is every public routine with a .m file, flagged by whether FSDA's
functionSignatures.json describes it.

    python tools/r-compare/make_routine_list.py --fsda-root <FSDA> --out <json>
"""

import argparse
import json
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "codegen"))
import parse_fsda  # noqa: E402


def main(args) -> int:
    logging.disable(logging.WARNING)
    root = args.fsda_root
    routines = {}
    for folder in parse_fsda._enumerate_toolbox(root):
        signed = set()
        if folder["json_path"]:
            signed = set(parse_fsda._parse_json_signatures(root / folder["json_path"]))
        for name, info in folder["functions"].items():
            m_path = info["m_path"]
            if not (root / m_path).is_file() or name in routines:
                continue
            routines[name] = {
                "name": name,
                "folder": str(Path(m_path).parent),
                "category": info["category"],
                "has_signature": name in signed,
            }
    rows = sorted(routines.values(), key=lambda r: r["name"].lower())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(rows, indent=1), encoding="utf-8")
    print(json.dumps({"routines": len(rows),
                      "with_signature": sum(r["has_signature"] for r in rows)}))
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fsda-root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    sys.exit(main(parser.parse_args()))
