"""Generate an R package of per-routine FSDA wrappers from the codegen IR.

Spec 025 (evaluation of R wrapper strategies, approach B). Reads the IR that
parse_fsda.py writes (schema: docs/DESIGN-codegen-parser.md section 4) and
emits one R function per record, with roxygen documentation built from the
IR prose. The runtime (engine start, shared session, fsda_call) is copied
from packages/fsdabridge so both approaches marshal through identical code.

    python tools/codegen/gen_r.py --ir tools/codegen/tmp_spec.json \
        --out packages/fsdabridgeGen [--roxygen]
"""

import argparse
import json
import keyword
import logging
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

log = logging.getLogger("gen_r")

REPO = Path(__file__).resolve().parents[2]
RUNTIME_PKG = REPO / "packages" / "fsdabridge"
ENGINE_PY = REPO / "code" / "fsda_engine" / "engine.py"

# Formals the wrappers own; an FSDA input with one of these names is renamed.
_RESERVED = {"nargout", "..."}

# R reserved words, which cannot be formals.
_R_RESERVED = {
    "if", "else", "repeat", "while", "function", "for", "next", "break",
    "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "in",
}

# Characters with meaning in Rd. Generated blocks are tagged @noMd, so only Rd
# escaping applies (FSDA prose carries LaTeX, which markdown mode mangles).
_RD_ESCAPE = re.compile(r"([\\%{}])")


def _rd(text) -> str:
    """Escape IR prose for a roxygen (Rd) block; collapse whitespace."""
    if not text:
        return ""
    text = " ".join(str(text).split())
    text = _RD_ESCAPE.sub(r"\\\1", text)
    return text.replace("@", "@@")


def _r_name(name: str) -> str:
    """Map a MATLAB identifier to a syntactic R formal."""
    if name in _R_RESERVED or name in _RESERVED or keyword.iskeyword(name):
        return name + "_"
    return name


def _type_text(matlab_type) -> str:
    """Render an OR-of-AND type list as prose for the docs."""
    if not matlab_type:
        return "untyped"
    return " | ".join(", ".join(atoms) for atoms in matlab_type)


def _comment(lines: list) -> list:
    return ["#' " + line if line else "#'" for line in lines]


def _param_doc(param: dict) -> str:
    text = param.get("purpose_long") or param.get("purpose_short") or ""
    kind = param.get("kind")
    tag = {"namevalue": "Name/value option", "ordered": "Optional positional"}.get(kind)
    prefix = f"({tag}; " if tag else "("
    return f"{prefix}MATLAB type: {_rd(_type_text(param.get('matlab_type')))}.) {_rd(text)}"


def _return_doc(outputs: list) -> list:
    if not outputs:
        return ["@return The routine's first MATLAB output converted to R; a list of",
                "  outputs when \\code{nargout > 1}."]
    lines = ["@return With \\code{nargout = 1}, the first output; with \\code{nargout = k}, a list of",
             "  the first k outputs, in this order:", "  \\describe{"]
    for out in outputs:
        desc = out.get("short_desc") or out.get("long_desc") or "(no description in the IR)"
        lines.append(f"    \\item{{{_rd(out['name'])}}}{{{_rd(desc)}")
        fields = out.get("fields") or []
        if fields:
            lines.append("      Fields:")
            lines.append("      \\itemize{")
            for field in fields:
                lines.append(f"        \\item \\code{{{_rd(field['name'])}}}: {_rd(field.get('desc'))}")
            lines.append("      }")
        lines.append("    }")
    lines.append("  }")
    return lines


def _render_wrapper(record: dict) -> str:
    """Emit one R wrapper function with its roxygen block."""
    name = record["name"]
    inputs = record.get("inputs") or []
    required = [p for p in inputs if p.get("kind") == "required"]
    ordered = [p for p in inputs if p.get("kind") == "ordered"]
    namevalue = [p for p in inputs if p.get("kind") == "namevalue"]

    formals = [_r_name(p["name"]) for p in required]
    formals += [f"{_r_name(p['name'])} = NULL" for p in ordered + namevalue]
    formals += ["...", "nargout = 1L"]

    title = record.get("description_short") or name
    doc = [f"{_rd(name)}: {_rd(title)}", ""]
    doc.append(_rd(record.get("description_long")) or _rd(title))
    doc.append("")
    if record.get("category"):
        doc += [f"FSDA category: {_rd(record['category'])}.", ""]
    for param in required + ordered + namevalue:
        doc.append(f"@param {_r_name(param['name'])} {_param_doc(param)}")
    doc.append("@param ... Further MATLAB name/value options not listed in the FSDA")
    doc.append("  signature file, passed through unchanged.")
    doc.append("@param nargout Number of MATLAB outputs to request (default 1).")
    doc += _return_doc(record.get("outputs") or [])
    see_also = [s for s in record.get("see_also") or [] if re.fullmatch(r"\w+", s)]
    if see_also:
        doc.append("@seealso FSDA: " + ", ".join(_rd(s) for s in see_also))
    if record.get("fsda_url"):
        doc.append(f"@references <{record['fsda_url']}>")
    doc.append("@noMd")
    doc.append("@export")

    pos = ", ".join(_r_name(p["name"]) for p in required)
    opt_pos = ", ".join(_r_name(p["name"]) for p in ordered)
    nv = ", ".join(f"`{p['name']}` = {_r_name(p['name'])}" for p in namevalue)
    body = [
        f"{name} = function({', '.join(formals)}) {{",
        f"  .fsda_invoke(\"{name}\",",
        f"    required = list({pos}),",
        f"    ordered = list({opt_pos}),",
        f"    namevalue = list({nv}),",
        "    extra = list(...),",
        "    nargout = nargout)",
        "}",
    ]
    return "\n".join(_comment(doc) + body) + "\n"


_INVOKE = '''# Generated by tools/codegen/gen_r.py -- do not edit by hand.
#
# Shared call path for every generated wrapper. NULL means "not given": a NULL
# name/value option is not sent, trailing NULL ordered arguments are dropped,
# and an interior one is sent as an empty matrix (MATLAB's "use the default").

.fsda_invoke = function(name, required, ordered, namevalue, extra, nargout) {
  keep = which(!vapply(ordered, is.null, logical(1)))
  ordered = if (length(keep) == 0L) list() else ordered[seq_len(max(keep))]
  ordered = lapply(ordered, function(v) if (is.null(v)) matrix(numeric(0), 0, 0) else v)
  namevalue = namevalue[!vapply(namevalue, is.null, logical(1))]
  args = c(list(NULL, name), required, ordered, namevalue, extra,
           list(nargout = nargout))
  .record_failure(do.call(fsda_call, args, quote = TRUE))
}
'''


def _description(pkg: str, n: int) -> str:
    return f"""Package: {pkg}
Type: Package
Title: Generated Wrappers for the FSDA MATLAB Toolbox
Version: 0.0.1
Authors@R:
    person("FSDA-bridge", "contributors", email = "fsda-bridge@example.org",
           role = c("aut", "cre"))
Description: Per-routine R wrappers for {n} routines of the FSDA MATLAB
    toolbox for robust statistics, generated from the toolbox's function
    signature metadata. Calls go through 'reticulate' and the MATLAB Engine
    API for Python. MATLAB, the FSDA toolbox and the 'matlabengine' Python
    package are required at runtime only.
License: EUPL (>= 1.2)
Encoding: UTF-8
Imports:
    reticulate,
    utils
Suggests:
    testthat (>= 3.0.0)
SystemRequirements: MATLAB (>= R2025b), FSDA MATLAB toolbox, Python (>=
    3.9), matlabengine (Python package matching the MATLAB release)
Config/testthat/edition: 3
Roxygen: list(markdown = TRUE)
"""


def _copy_runtime(pkg: str, out: Path) -> None:
    """Copy the hand-written runtime from packages/fsdabridge, renamed."""
    for fname in ("engine.R", "session.R"):
        text = (RUNTIME_PKG / "R" / fname).read_text(encoding="utf-8")
        text = text.replace('package = "fsdabridge"', f'package = "{pkg}"')
        text = text.replace("'fsdabridge'", f"'{pkg}'")
        text = text.replace("fsdabridge:", f"{pkg}:")
        text = text.replace("[fsda] is a friendlier", "Generated wrappers are a friendlier")
        text = text.replace("`fsda$FSR(y, X)` reaches", "`FSR(y, X)` reaches")
        text = re.sub(r"\[fsda\]", "the generated wrappers", text)
        text = text.replace("`fsda$FSR(y, X)`", "`FSR(y, X)`")
        text = text.replace("fsda$mahalFS(", "mahalFS(").replace("fsda$FSR(", "FSR(")
        (out / "R" / fname).write_text(text, encoding="utf-8")
    (out / "inst" / "python").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ENGINE_PY, out / "inst" / "python" / "engine.py")


def generate(records: list, out: Path, pkg: str) -> dict:
    """Write the package; return counts for the size/time measurement."""
    if out.exists():
        shutil.rmtree(out)
    (out / "R").mkdir(parents=True)
    _copy_runtime(pkg, out)
    (out / "R" / "zz_invoke.R").write_text(_INVOKE, encoding="utf-8")

    written = 0
    for record in records:
        if not re.fullmatch(r"[A-Za-z]\w*", record["name"]):
            log.warning("%s: not a syntactic R name, skipping", record["name"])
            continue
        path = out / "R" / f"fsda_{record['name']}.R"
        header = "# Generated by tools/codegen/gen_r.py from the IR -- do not edit by hand.\n\n"
        path.write_text(header + _render_wrapper(record), encoding="utf-8")
        written += 1

    (out / "DESCRIPTION").write_text(_description(pkg, written), encoding="utf-8")
    (out / "NAMESPACE").write_text("# Generated by roxygen2: do not edit by hand\n",
                                   encoding="utf-8")
    (out / ".Rbuildignore").write_text("^.*\\.Rcheck$\n^.*\\.tar\\.gz$\n", encoding="utf-8")
    return {"wrappers": written}


def main(args) -> int:
    records = json.loads(args.ir.read_text(encoding="utf-8"))
    t0 = time.perf_counter()
    stats = generate(records, args.out, args.package)
    stats["generate_s"] = round(time.perf_counter() - t0, 3)
    if args.roxygen:
        t1 = time.perf_counter()
        # Twice: on the first pass man/ is empty, so links between the copied
        # runtime topics cannot resolve yet and roxygen warns spuriously.
        for _ in range(2):
            proc = subprocess.run(
                ["Rscript", "-e", "roxygen2::roxygenise()"], cwd=args.out,
                capture_output=True, text=True,
            )
        stats["roxygen_s"] = round(time.perf_counter() - t1, 3)
        stats["roxygen_rc"] = proc.returncode
        if proc.returncode != 0:
            log.error("roxygen failed:\n%s", proc.stderr)
        elif proc.stderr.strip():
            log.warning("roxygen:\n%s", proc.stderr.strip())
    print(json.dumps(stats))
    return 0 if stats.get("roxygen_rc", 0) == 0 else 1


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING, format="%(name)s: %(message)s")
    parser = argparse.ArgumentParser(description="Generate R wrappers from the IR.")
    parser.add_argument("--ir", type=Path, required=True, help="IR JSON file")
    parser.add_argument("--out", type=Path, required=True, help="package directory")
    parser.add_argument("--package", default="fsdabridgeGen", help="R package name")
    parser.add_argument("--roxygen", action="store_true", help="run roxygen2 after")
    sys.exit(main(parser.parse_args()))
