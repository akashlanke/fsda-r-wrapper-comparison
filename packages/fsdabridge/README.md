# fsdabridge

Call [FSDA](https://github.com/UniprJRC/FSDA), the MATLAB robust-statistics
toolbox, from R.

```r
library(fsdabridge)

d   = fsda$mahalFS(Y, MU, SIGMA)
out = fsda$FSR(y, X, nsamp = 0, intercept = TRUE, plots = 0)
ic  = fsda$tclustIC(Y, kk = matrix(2:4, nrow = 1))
```

All three work, and **nothing in the package mentions `mahalFS`, `FSR` or
`tclustIC`.** There is no list of supported routines anywhere. Every FSDA
routine works, including ones added after this package was built.

This is a bridge, not a reimplementation: FSDA runs inside MATLAB at call time.
All data marshalling lives in the project's shared Python engine
(`code/fsda_engine/engine.py`); this package owns reticulate setup and R-side
ergonomics only, per `CONSTITUTION.md` section 3.

| | |
|---|---|
| R code | 610 lines, three files |
| Exports | 11 |
| Routine names in the package | zero |
| `R CMD check --as-cran` | clean |
| Tests | 74 offline, 29 live |
| Agreement gate | 8 routines at `1e-9` |

---

## How it works

`fsda` is an **empty list** carrying a class label. That label makes R's `$`
operator dispatch to our own function instead of doing an ordinary list lookup:

```r
fsda = structure(list(), class = "fsda_ns")

`$.fsda_ns` = function(x, name) {
  force(name)
  function(...) fsda_call(handle, name, ...)
}
```

Writing `fsda$FSR` makes R look for `FSR` inside the list, fail, and call
`$.fsda_ns(fsda, "FSR")` — which builds and returns a function that will call
`FSR`. So `fsda$FSR(y, X)` is two steps: `$` produces a function, then `(y, X)`
invokes it.

`"FSR"` exists only because someone typed it.

This is the same mechanism `pyfsda` uses on the Python side (a module-level
`__getattr__`). The Julia surface cannot do it — a Julia module cannot intercept
unknown names — so it hard-codes a routine list instead.

### Why not a list of routines

`FSDAjl` lists 17 routines. Two of them (`getYahoo`, `malfwdplot`) build fine
and fail when called: the shared engine deliberately does not marshal
struct-arrays or datetimes, and marshals structs out of MATLAB but not into it.
Neither has a working example in that package.

**A name in a list records that someone typed it once. It does not record that
it works.** With no list, nothing can make that claim.

### How a typo is caught

The facade builds a callable for any name at all, so what catches
`fsda$FSRR(...)`? **MATLAB does.**

The first time a name is used, the bridge asks MATLAB's own `which`. A path
comes back → the call proceeds. Nothing comes back → the call stops in R, before
anything is marshalled. Confirmed names are cached, so the round-trip is paid
once per name rather than once per call.

No list is involved: the question is identical for every name.

---

## Requirements

The package **installs, loads and passes its offline tests without any of
this.** Only actual calls need it.

| Component | Requirement |
|---|---|
| MATLAB | R2025b or later, with the FSDA Add-On on the path |
| Python | 3.9+, with `matlabengine` **matching your MATLAB release** |
| R | 4.1+, with `reticulate` |

The version match is the real constraint: R2025b pairs with
`matlabengine==25.2.*`, R2026a with `26.1.*`. A mismatch fails at `pip install`
time with a clear message.

---

## Setup

Create the virtualenv **outside** the package directory — one created inside it
ends up in the source tarball.

```bash
python3 -m venv fsda-venv
source fsda-venv/bin/activate              # Windows: fsda-venv\Scripts\activate
python -m pip install numpy "matlabengine==25.2.*"

export FSDA_DEV_VENV="$(command -v python)"
# Windows: set FSDA_DEV_VENV=C:\path\to\fsda-venv\Scripts\python.exe
```

`FSDA_DEV_VENV` must point at the venv's **python executable**, not its root.

```bash
cd packages/fsdabridge
R CMD INSTALL .
```

Check the bridge reaches MATLAB:

```bash
Rscript -e "library(fsdabridge); str(diagnostics())"
```

Both MATLAB and `matlabengine` versions should appear, and match.

`FSDA_ROOT` is only needed if FSDA is not already on the MATLAB path — an
Add-On installation is. Check with `matlab -batch "disp(which('FSR'))"`.

---

## Running the examples

```bash
cd inst/examples
Rscript 01_quickstart.R
Rscript 03_probe_output_shapes.R
Rscript 02_routines.R          # opens figures; close them to finish
```

| | |
|---|---|
| `01_quickstart.R` | smallest end-to-end check, with an agreement test against `stats::mahalanobis` |
| `02_routines.R` | FSR, LXS, MMreg, Score, FSM, mcd, graphics, struct arguments |
| `03_probe_output_shapes.R` | calls 15 routines raw and reports what each returns |

---

## Testing

Three layers, in increasing order of what they need.

```bash
# 1. Offline — no MATLAB, no Python. What CI and a CRAN build farm run.
Rscript -e 'library(fsdabridge); testthat::test_dir("tests/testthat")'

# 2. Live — real MATLAB and FSDA.
FSDA_LIVE=1 Rscript -e 'library(fsdabridge); testthat::test_dir("tests/testthat")'

# 3. Agreement gate — against committed FSDA references, at 1e-9.
Rscript data-raw/agreement_gate.R
```

On Windows, quote the other way round:
`Rscript -e "library(fsdabridge); testthat::test_dir('tests/testthat')"`

**The offline layer** covers the ways this design can fail *silently*: that
every callable closes over its own name, that the dispatch path never consults
the tab-completion list, that no routine name appears in it at all, that the
handle is detected by class rather than position, and that the export count
stays capped.

**The live layer** shares one MATLAB session across the file, so the suite pays
one startup rather than one per test. Two offline tests skip during a live run,
because the live layer legitimately leaves a session up.

**The agreement gate is the definition of done** (`CONSTITUTION.md` section 5).
It differs from the live tests: those confirm a call succeeds and its answer is
plausible, while the gate compares against a reference FSDA itself produced. A
change in the bridge, the engine or the MATLAB release then surfaces as a
numeric difference rather than as a still-plausible wrong answer.

Gold files live in `data-raw/reference/` and are committed. Regenerate with
`--update` only when a case deliberately changes, and read the diff first — an
`--update` that quietly absorbs a regression is worse than no gate.

---

## Conventions

Per `CONSTITUTION.md` section 4:

| | |
|---|---|
| 1-D input | crosses as a MATLAB **row** — pass `(n, 1)` for a column |
| output shape | MATLAB's natural shape, no silent reshape |
| indices | stay **1-based** |
| struct / table out | arrives as a named list |
| struct **into** MATLAB | not marshalled — see below |

The 1-D rule catches people. `y` as a plain vector becomes a MATLAB row, not a
column, and a regression routine will either error or fit the wrong thing. Pass
`matrix(y, ncol = 1)`.

### Plotting routines

The facade does not know which routines draw figures — knowing that would
require a list. Pass `nargout = 0`:

```r
fsda$yXplot(y, X, nargout = 0)
render_figures()
```

`boxplotb` is the exception worth knowing: it draws *and* returns a real data
struct, so it keeps `nargout = 1`. Its `handles` field crosses harmlessly as an
empty array, exactly as `CONSTITUTION.md` section 4 describes.

### Struct arguments

The shared engine marshals structs out of MATLAB but not in. A routine taking a
struct argument is driven by keeping the struct in the workspace:

```r
eval_m(NULL, "outEDA = FSMeda(Y, bsb, 'plots', 0);", nargout = 0)
eval_m(NULL, "malfwdplot(outEDA);", nargout = 0)
MAL = eval_m(NULL, "outEDA.MAL")
```

Note that `pyfsda` **has** solved this on the Python side — spec 020 added
`_dict_to_struct_var`, scoped deliberately to the pyfsda package engine. Bringing
that into the shared engine would remove this limitation for R and Julia at once,
and would need its own spec.

### Sessions

MATLAB starts on first use and is reused; startup costs tens of seconds. Release
it with `fsda_shutdown()`.

If the MATLAB process dies — killed externally, or lost when a machine sleeps —
that is detected and a fresh session started in its place. The liveness probe
costs about 15 ms against a 30-second restart.

When a routine fails, `fsda_last_error()` returns the condition object.

Pass a handle from `start_engine()` as the first argument to use a session of
your own; every function accepts one, and `NULL` means the shared session.
`stop_engine()` keeps its handle **required**, alone among these functions, so a
stray `stop_engine(NULL)` cannot kill a session someone else is using.

---

## Why there are no wrapper functions

The package ships zero per-routine wrappers, and this was measured rather than
assumed. `inst/examples/03_probe_output_shapes.R` calls 15 routines raw:

| outcome | count | meaning |
|---|---|---|
| named list | 12 | `out$beta` already works |
| single value | 2 | one matrix; nothing to name |
| unnamed positional | 1 | `[[1]]`, `[[2]]` — no names to reach |

The 12 are FSDA routines returning MATLAB structs, and a struct arrives as a
named list — the names are already there. The 2 are `mahalFS` and `unibiv`,
which return a bare matrix. The 1 is `kmeans`, which **is not an FSDA routine**:
it belongs to MATLAB's Statistics Toolbox, which predates FSDA's struct
convention.

So 14 of 15 need no wrapper, and the one that does is outside this package's
subject matter. Callers who need such a routine unpack by position:

```r
raw = fsda$kmeans(Y, 3, Replicates = 10, nargout = 4)
idx = raw[[1]]
```

**The rule, if the question comes up again:** a wrapper earns its place when the
raw output genuinely cannot be used, not when it could be tidier. Run the probe
first — if `out$field` already works, the wrapper buys nothing.

---

## Pros and cons

### What this approach gives

**Complete coverage.** Every FSDA routine works. One added tomorrow works today,
with no change to the package.

**Zero maintenance.** No list to keep in step with FSDA, no generator to re-run,
no manifest to edit. Adding a routine requires nothing.

**Nothing can lie.** The package makes no claim about which routines work, so no
claim can be false.

**Style drift is structurally impossible.** There is no per-routine code, so
several people cannot write it several different ways.

**Small enough to hold in your head.** 610 lines, three files, 11 exports. A bug
fixed once is fixed for every routine.

**Consistent across the project.** `pyfsda.FSR(y, X)` and `fsda$FSR(y, X)` are
recognisably the same design.

### What it costs

**No per-routine documentation.** `?FSR` gives nothing. There is one manual
page, `?fsda`, pointing at FSDA's own documentation for a routine's signature.

**No argument autocomplete.** Typing `fsda$FSR(` will not prompt for `y` and
`X`.

**The caller must know argument order.** Swap two matrices and the package
cannot tell, because it does not know what the routine expects.

**`nargout` is the caller's responsibility** for plotting routines.

**A gap on case-insensitive filesystems.** MATLAB's `which` resolves through the
file system, so on Windows and macOS a name differing from a real routine only
in case passes the check and is rejected later by MATLAB. `which('FSRR')`
returns the path to FSDA's real `FSRr.m`. The error still reaches the caller,
just from MATLAB rather than from R. `pyfsda` shares this, for the same reason.

### The trade-off, stated plainly

**Coverage in exchange for discoverability.**

There is no middle position. Either a routine name is written down somewhere —
and can then carry `@param` documentation and autocomplete — or it is not, and
every routine works for free. The two cannot both be had.

This package takes coverage, on the grounds that ~500 working routines with a
shared manual page serve users better than a smaller set with individual pages,
and that a list which needs maintaining will eventually stop being maintained.

Reasonable people weigh this differently. An alternative surface in this project
makes the opposite choice — validated arguments and per-routine documentation
for a curated set. That is a coherent position; it is a different point on the
same trade-off.

---

## What is in the package

```
R/engine.R    256   reticulate setup, fsda_call, eval_m, figures, diagnostics
R/session.R   127   the shared MATLAB session, recovery, last error
R/facade.R    227   $ dispatch — the mechanism
```

Eleven exports: `fsda` (the dispatcher), `fsda_call` and `eval_m`
(routine-agnostic calls), `fsda_session` and `fsda_shutdown` (the shared
session), `fsda_last_error`, `start_engine` and `stop_engine` (your own
session), `render_figures` and `wait_for_figures`, and `diagnostics`.

---

## Maintenance

There is nothing to update when FSDA adds a routine. Two things do need
attention.

`.fsda_common` in `R/facade.R` is the tab-completion list. It is a **suggestion
only** — `$` accepts every name whether or not it appears there, so nothing
breaks when it falls behind. An offline test asserts it can never quietly become
a gate.

`inst/python/engine.py` is a copy of `code/fsda_engine/engine.py`, shipped so an
installed package can find it via `system.file()`. Duplicates drift, so CI
compares their checksums on every push. To resync by hand:

```bash
cp code/fsda_engine/engine.py packages/fsdabridge/inst/python/engine.py
```

CI (`.github/workflows/R-CMD-check.yaml`) runs `R CMD check` on Linux and
Windows with no MATLAB present, at `error-on: note`, so every example and every
live test must skip cleanly.

After editing roxygen comments: `roxygen2::roxygenise()`.

---

## Distribution

`R CMD check --as-cran` is clean, but CRAN is not the right home. CRAN policy
expects a package's functionality to be testable on CRAN's own machines, and
every real call here requires MATLAB — proprietary, licensed, not present there.
`SystemRequirements` also names `matlabengine`, a PyPI package whose own build
requires a matching MATLAB installation.

**r-universe is the appropriate channel.** `install.packages()` works there, the
interface is CRAN-like, and packages with external proprietary dependencies are
accepted. Installing from GitHub also works:

```r
remotes::install_github("<org>/FSDA-bridge", subdir = "packages/fsdabridge")
```

`pyfsda` is on PyPI because PyPI does not review submissions; CRAN is a
different proposition.

---

## Licence

EUPL-1.2, consistent with FSDA's own licensing.
