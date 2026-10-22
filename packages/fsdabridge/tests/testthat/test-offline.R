# Offline layer: everything here must pass WITHOUT MATLAB, FSDA or Python —
# this is the layer CRAN's build farm actually runs.

test_that("the bundled Python engine ships with the package", {
  path = system.file("python", "engine.py", package = "fsdabridge")
  expect_true(nzchar(path))
  expect_true(file.exists(path))
})

test_that("the exported surface is complete", {
  for (fn in c("start_engine", "fsda_call", "eval_m", "render_figures",
               "wait_for_figures", "stop_engine", "diagnostics",
               "fsda_session", "fsda_shutdown", "fsda_last_error")) {
    expect_true(is.function(get(fn, envir = asNamespace("fsdabridge"))),
                info = fn)
  }
  expect_s3_class(fsda, "fsda_ns")
})

test_that("fsda_call rejects a non-handle without touching Python", {
  expect_error(fsda_call(list(), "mahalFS"), "start_engine")
  expect_error(stop_engine(42), "start_engine")
  expect_error(stop_engine(NULL), "start_engine")

  # inherits() alone is not enough: a stale or hand-built list must fail too.
  half = structure(list(module = NULL, engine = NULL), class = "fsda_engine")
  expect_error(fsda_call(half, "FSR"), "start_engine")
})

test_that("shutdown is a no-op when nothing is running", {
  # testthat runs files alphabetically, so test-live.R goes first and — when
  # FSDA_LIVE is set — leaves the shared session up. This file must not assert
  # that no engine exists, and must not shut down a session the live layer is
  # still using.
  running = get(".is_running", envir = asNamespace("fsdabridge"))
  skip_if(running(), "a session is already up (test-live.R ran first)")

  expect_false(fsda_shutdown())
  expect_false(running())
})

test_that("no routine name is exported", {
  # Routines are reached as fsda$<name>, never as top-level functions, so
  # nothing here can mask the search path. Exporting `kmeans` would shadow
  # stats::kmeans for anyone who attaches the package.
  exports = getNamespaceExports("fsdabridge")
  for (nm in c("FSR", "Score", "mahalFS", "LXS", "mcd", "tclust", "kmeans")) {
    expect_false(nm %in% exports, info = nm)
  }
  # One dispatch object plus the engine surface, and nothing else. The package
  # has no per-routine wrappers at all; if this starts climbing, someone is
  # adding them again — the thing it is designed not to need.
  expect_lte(length(exports), 12)
})


# --- the facade -------------------------------------------------------------

test_that("the facade builds a callable for any name", {
  expect_true(is.function(fsda$FSR))
  expect_true(is.function(fsda$tclustIC))
  expect_true(is.function(fsda$aRoutineNobodyHasWrittenYet))
  expect_true(is.function(fsda[["not.a.syntactic.name"]]))
})

test_that("each wrapper closes over its own name", {
  # R closures capture the binding, not the value. Without force(name) in
  # .make_wrapper(), every wrapper would call whichever name was resolved last,
  # with no error at all. Read the captured name back out to prove they differ.
  captured = vapply(c("FSR", "Score", "mahalFS"),
                    function(n) get("name", envir = environment(fsda[[n]])),
                    character(1))
  expect_equal(unname(captured), c("FSR", "Score", "mahalFS"))
})

test_that("wrappers are cached, so the same name gives the same object", {
  expect_identical(fsda$FSR, fsda$FSR)
  expect_false(identical(fsda$FSR, fsda$Score))
})

test_that("the completion list is a suggestion, not a gate", {
  ns = asNamespace("fsdabridge")

  suggested = utils::.DollarNames(fsda, "")
  expect_true("mahalFS" %in% suggested)
  expect_false("aRoutineNobodyHasWrittenYet" %in% suggested)

  # Absent from the list, still callable. This is what an enumerated facade
  # cannot do.
  expect_true(is.function(fsda$aRoutineNobodyHasWrittenYet))

  # The list must never be consulted to decide what works.
  body_txt = paste(deparse(get(".make_wrapper", envir = ns)), collapse = " ")
  expect_false(grepl(".fsda_common", body_txt, fixed = TRUE))
})

test_that("no routine name is hard-coded in the mechanism", {
  # The moment a routine name appears in the dispatch path, the facade has a
  # list, and a list goes stale.
  ns = asNamespace("fsdabridge")
  for (fn in c(".make_wrapper", ".facade_handle", ".validate_routine")) {
    txt = paste(deparse(get(fn, envir = ns)), collapse = " ")
    for (nm in c("FSR", "mahalFS", "tclust", "yXplot")) {
      expect_false(grepl(paste0('"', nm, '"'), txt, fixed = TRUE),
                   info = paste(fn, nm))
    }
  }
})

test_that("an explicit handle is detected by class, never by position", {
  split = get(".facade_handle", envir = asNamespace("fsdabridge"))

  fake = structure(list(module = 1, engine = 1), class = "fsda_engine")
  out = split(list(fake, 1, 2))
  expect_identical(out$handle, fake)
  expect_length(out$rest, 2L)

  named = split(list(fake, 1, plots = 0))
  expect_named(named$rest, c("", "plots"))

  # Without a handle .facade_handle() would start a session, which must not
  # happen offline; check the branch condition instead of calling it.
  expect_false(inherits(matrix(1:4)[[1]], "fsda_engine"))
})

test_that("dot-names are refused, so R internals cannot become routines", {
  # str(), serialisation and internal machinery probe objects with dot-names.
  # Handing back a wrapper for those would be silently wrong.
  expect_error(fsda$.internal, "not an FSDA routine")
  expect_error(fsda[[".hidden"]], "not an FSDA routine")
})

test_that("a wrapper reports which routine it calls", {
  fn = fsda$FSR
  expect_s3_class(fn, "fsda_routine")
  expect_equal(attr(fn, "routine"), "FSR")
  expect_output(print(fn), "FSR")
  expect_true(is.function(fn))          # still an ordinary callable
})

test_that("validation can be switched off without touching the mechanism", {
  old = getOption("fsdabridge.validate")
  on.exit(options(fsdabridge.validate = old), add = TRUE)

  options(fsdabridge.validate = FALSE)
  validate = get(".validate_routine", envir = asNamespace("fsdabridge"))
  # Returns without asking MATLAB, so a NULL handle is never dereferenced.
  expect_false(validate(NULL, "anything"))
})

test_that("completion learns names used this session", {
  validated = get(".validated", envir = asNamespace("fsdabridge"))
  on.exit(rm(list = ls(validated, all.names = TRUE), envir = validated),
          add = TRUE)

  assign("someNewRoutine", TRUE, envir = validated)
  expect_true("someNewRoutine" %in% utils::.DollarNames(fsda, ""))
  expect_false(".handle" %in% utils::.DollarNames(fsda, ""))
})

test_that("the package ships no per-routine wrappers", {
  # Every routine is reached as fsda$<name>. A probe over 15 routines found
  # that FSDA returns structs, which arrive as named lists, so a wrapper would
  # only rename fields the caller can already see. See
  # inst/examples/03_probe_output_shapes.R.
  #
  # fsda_call() is not a wrapper: it is the engine's routine-agnostic call
  # surface, and takes the routine name as an argument.
  exports = getNamespaceExports("fsdabridge")
  expect_setequal(
    grep("^fsda_", exports, value = TRUE),
    c("fsda_call", "fsda_last_error", "fsda_session", "fsda_shutdown")
  )
})

test_that("printing the facade does not start an engine", {
  # The invariant is that printing does not CHANGE whether an engine is
  # running, which holds whether or not the live layer left one up.
  running = get(".is_running", envir = asNamespace("fsdabridge"))
  before = running()

  expect_output(print(fsda), "any FSDA routine")
  expect_identical(running(), before)
})


# --- session recovery and error capture -------------------------------------

test_that("fsda_last_error returns NULL or a condition, never anything else", {
  # Cannot assert it starts empty: testthat runs files alphabetically, so
  # test-live.R goes first and, under FSDA_LIVE, deliberately records a
  # failure. Assert the contract that holds either way.
  e = fsda_last_error()
  expect_true(is.null(e) || inherits(e, "condition"))
})

test_that(".record_failure keeps the condition and rethrows it unchanged", {
  record = get(".record_failure", envir = asNamespace("fsdabridge"))
  state = get(".state", envir = asNamespace("fsdabridge"))
  on.exit(assign("last_error", NULL, envir = state), add = TRUE)

  # The error must still reach the caller: recording it must not swallow it.
  expect_error(record(stop("boom")), "boom")

  captured = fsda_last_error()
  expect_s3_class(captured, "condition")
  expect_equal(conditionMessage(captured), "boom")
})

test_that("a successful call leaves the recorded error alone", {
  record = get(".record_failure", envir = asNamespace("fsdabridge"))
  state = get(".state", envir = asNamespace("fsdabridge"))
  on.exit(assign("last_error", NULL, envir = state), add = TRUE)

  expect_error(record(stop("first")), "first")
  expect_equal(record(42), 42)
  # Still the earlier failure: success does not clear it, shutdown does.
  expect_equal(conditionMessage(fsda_last_error()), "first")
})

test_that("shutdown clears the recorded error", {
  # Must not shut down a session the live layer is still using.
  running = get(".is_running", envir = asNamespace("fsdabridge"))
  skip_if(running(), "a session is already up (test-live.R ran first)")

  state = get(".state", envir = asNamespace("fsdabridge"))
  assign("last_error", simpleError("stale"), envir = state)
  on.exit(assign("last_error", NULL, envir = state), add = TRUE)

  fsda_shutdown()
  expect_null(fsda_last_error())
})

test_that(".session_alive treats an unusable handle as dead", {
  alive = get(".session_alive", envir = asNamespace("fsdabridge"))

  # No Python behind it, so version() cannot succeed. Must report FALSE rather
  # than propagate the error -- the caller uses this to decide whether to
  # restart, and an error here would defeat the recovery.
  dead = structure(list(module = NULL, engine = NULL), class = "fsda_engine")
  expect_false(alive(dead))
})

test_that("the agreement gate and CI workflow ship in the repository", {
  # Not in the built package (data-raw/ and .github/ are excluded), so look
  # relative to the source tree and skip when running from an install.
  gate = testthat::test_path("..", "..", "data-raw", "agreement_gate.R")
  ci = testthat::test_path("..", "..", ".github", "workflows",
                           "R-CMD-check.yaml")
  skip_if_not(file.exists(gate), "running from an installed package")

  expect_true(file.exists(gate))
  expect_true(file.exists(ci))
})
