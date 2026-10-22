# fsdabridge 0.1.0

First release of the R surface as an installable package.

## The design

Named routine wrappers are replaced by a **generic facade**. `fsda$<name>(...)`
calls any FSDA routine: `$` is overloaded on an exported dispatch object, so a
routine name is caught as it is typed and a caller built on the spot. No routine
name appears anywhere in the dispatch path.

This is `pyfsda`'s module-level `__getattr__`, which R can reproduce exactly. It
removes three problems at once:

* **Coverage.** Every FSDA routine works, including ones added after this
  package was built. A curated list would cover a few dozen at most.

* **Style drift.** There is no per-routine code left for anyone to write, so
  there is nothing for several people's styles to drift across.

* **False positives.** A list of names records that someone typed a name once,
  not that it works. `FSDAjl` lists 17 routines, two of which build fine and
  fail when called. With no list, nothing can make that claim.

## Added

* `fsda` — the dispatch object. One export, one manual page.

* `fsda_session()`, `fsda_shutdown()` — a shared MATLAB session, started on
  first use and reused. Startup costs tens of seconds, so it is never started at
  load time; that also keeps `FSDA_DEV_VENV` settable after
  `library(fsdabridge)`.

* Stale-session recovery. If the MATLAB process dies — killed externally, or
  lost when a machine sleeps — that is detected and a fresh session started in
  its place, rather than failing with a low-level error on the next call. The
  liveness probe costs about 15 ms against a 30-second restart.

* `fsda_last_error()` — the condition object from the most recent failed call.
  Captured with `withCallingHandlers`, so the error still propagates normally
  and only a copy is kept. Cleared on shutdown.

* Routine existence is checked against the MATLAB path once per name per
  session, so a typo fails in R rather than inside the bridge.
  `options(fsdabridge.validate = FALSE)` turns it off.

* An agreement gate (`data-raw/agreement_gate.R`) covering eight routines —
  `mahalFS`, `FSR`, `Score`, `LXS` (LTS and LMS), `FSM`, `mcd`, `tclust` —
  against committed references at `1e-9`, per `CONSTITUTION.md` section 5. Every
  case goes through the facade, so the gate exercises the shipped call path.
  Anything stochastic is seeded MATLAB-side immediately before the call.

* CI (`.github/workflows/R-CMD-check.yaml`): `R CMD check` on Linux and Windows
  with no MATLAB present, at `error-on: note`. It also compares the bundled
  `engine.py` against `code/fsda_engine/engine.py` on every push — all
  marshalling lives in a single engine (`CONSTITUTION.md` section 3), and a
  stale copy would silently fork that contract for R users only.

* Three runnable examples under `inst/examples/`, including a probe that reports
  what every routine actually returns.

* `.onLoad` / `.onUnload` hooks. `.onLoad` deliberately does not touch Python:
  reticulate binds its interpreter on first use and cannot be rebound without a
  fresh R session.

## Removed

* Per-routine wrappers. Earlier drafts shipped `mahalFS()`, `Score()`, `FSM()`,
  `boxplotb()`, `yXplot()`, `malfwdplot()`, `fsda_tclust()` and `fsda_kmeans()`.
  All are reached as `fsda$mahalFS(...)` and so on.

  The decision was measured, not assumed.
  `inst/examples/03_probe_output_shapes.R` calls 15 routines raw: 12 return a
  named list, 2 return a bare matrix, and 1 returns unnamed positional
  outputs — and that one is `kmeans`, a MATLAB Statistics Toolbox function
  rather than an FSDA routine. FSDA's own convention is to return everything in
  one struct, which arrives as a named list, so `out$beta` works unaided.

  An offline test caps the export count, so this cannot drift back.

## Notes and known boundaries

* Structs marshal out of MATLAB but not in: the shared engine's `to_matlab()`
  has no `dict` branch. A routine taking a struct argument is driven with
  `eval_m()`, keeping the struct in the workspace.

  `pyfsda` has solved this on its side — spec 020 added `_dict_to_struct_var`,
  scoped deliberately to the pyfsda package engine. Bringing it into the shared
  engine would lift the limitation for R and Julia at once, and needs its own
  spec.

* The facade does not know which routines draw figures, so `nargout = 0` is the
  caller's to pass. Inferring it would require a list.

* MATLAB's `which` resolves through the filesystem, which is case-insensitive on
  Windows and macOS, so a typo differing from a real routine only in case passes
  the existence check and is rejected later by MATLAB's case-sensitive dispatch.
  `which('FSRR')` returns FSDA's real `FSRr.m`. `pyfsda` shares this.

* No per-routine `@param` documentation or argument autocomplete. This is the
  direct cost of having no routine names in the package, and it was chosen
  deliberately.

* `CONSTITUTION.md` pins MATLAB R2026a and `matlabengine==26.1.*`; this package
  declares `MATLAB (>= R2025b)` and was verified against R2025b with
  `matlabengine 25.2.2`. Worth reconciling.

* `CONSTITUTION.md` sections 1 and 6 say the project produces no package and
  needs no CI. This package and `pyfsda` both do; the constitution predates
  them.

## Verified

| | |
|---|---|
| `R CMD check --as-cran` | clean |
| Offline tests | 74 checks pass |
| Live tests | 29 checks pass against real MATLAB R2025b |
| Agreement gate | 8/8 at `1e-9`, reproducible across runs |
| Examples | all three run |
