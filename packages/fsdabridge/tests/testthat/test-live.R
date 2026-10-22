# Live layer: exercises MATLAB/FSDA through the bridge. Opt-in only — skipped
# everywhere by default (CRAN has no MATLAB; the engine start costs ~30 s).
# Run locally with:  FSDA_LIVE=1 Rscript -e 'testthat::test_dir("tests/testthat")'
#
# One shared session serves the whole file, so the suite pays a single MATLAB
# start rather than one per test.

live_session = function(routine = NULL) {
  skip_if(!nzchar(Sys.getenv("FSDA_LIVE")),
          "set FSDA_LIVE=1 (with FSDA_DEV_VENV / FSDA_ROOT) to run live tests")
  fsda_root = Sys.getenv("FSDA_ROOT")
  if (!nzchar(fsda_root)) fsda_root = NULL
  fsda_session(routine = routine, fsda_root = fsda_root)
}

# A small regression problem with three planted outliers, reused below.
make_data = function(seed = 1, n = 60) {
  set.seed(seed)
  X = matrix(rnorm(n * 2), ncol = 2)
  y = matrix(X %*% c(2, -1) + rnorm(n, sd = 0.5), ncol = 1)
  y[c(3, 17, 41)] = y[c(3, 17, 41)] + 12
  list(X = X, y = y, planted = c(3, 17, 41))
}

test_that("live smoke test: mahalFS agrees with stats::mahalanobis", {
  h = live_session("mahalFS")

  set.seed(42)
  Y = matrix(rnorm(60), ncol = 3)
  MU = matrix(colMeans(Y), nrow = 1)
  SIGMA = cov(Y)

  d_fsda = as.numeric(fsda$mahalFS(h, Y, MU, SIGMA))
  d_r = as.numeric(stats::mahalanobis(Y, colMeans(Y), SIGMA))
  expect_lt(max(abs(d_fsda - d_r)), 1e-9)
})

test_that("the facade and fsda_call reach the same result", {
  # The two surfaces must be interchangeable; a divergence means one of them is
  # not routing through the same engine path.
  h = live_session()

  set.seed(7)
  Y = matrix(rnorm(40), ncol = 2)
  MU = matrix(colMeans(Y), nrow = 1)

  expect_equal(as.numeric(fsda$mahalFS(h, Y, MU, cov(Y))),
               as.numeric(fsda_call(h, "mahalFS", Y, MU, cov(Y))))
})

test_that("FSR finds the planted outliers", {
  h = live_session()
  d = make_data()

  out = fsda$FSR(h, d$y, d$X, nsamp = 0, intercept = TRUE, plots = 0, msg = 0)
  expect_true(all(d$planted %in% as.integer(out$ListOut)))
})

test_that("raw output is already usable, so wrappers are mostly unnecessary", {
  # The empirical claim the no-wrapper design rests on: FSDA routines return
  # MATLAB structs, and a struct arrives as a named list, so out$beta works
  # with no help. If this fails, the design needs revisiting.
  h = live_session()
  d = make_data()

  out = fsda$LXS(h, d$y, d$X, intercept = TRUE, lms = 0, nsamp = 1000,
                 plots = 0, msg = 0)

  expect_type(out, "list")
  expect_true(!is.null(names(out)))
  expect_false(is.null(out$beta))
  expect_false(is.null(out$weights))
})

test_that("a routine with no wrapper anywhere still works", {
  # The point of the design: nothing in this package mentions FSRaddt or mcd.
  h = live_session()
  d = make_data()

  addt = fsda$FSRaddt(h, d$y, d$X, intercept = TRUE, plots = 0, msg = 0)
  expect_false(is.null(addt$Tdel))

  robust = fsda$mcd(h, cbind(d$X, d$y), plots = 0, msg = 0)
  expect_type(robust, "list")
})

test_that("a typo fails in R rather than inside MATLAB", {
  # Deliberately a name with no case-variant in FSDA. On Windows `which`
  # resolves through a case-insensitive filesystem, so "FSRR" would be matched
  # to FSDA's FSRr, pass the check, and then be rejected by MATLAB's
  # case-sensitive dispatch -- an error from the wrong side.
  h = live_session()
  expect_error(fsda$FSRRR(h, 1), "not found on the MATLAB path")
  expect_error(fsda$notARealRoutine(h, 1), "not found on the MATLAB path")
})

test_that("plotting routines run with nargout = 0", {
  h = live_session()
  on.exit(try(eval_m(h, "close all;", nargout = 0), silent = TRUE), add = TRUE)
  d = make_data()

  eval_m(h, "close all;", nargout = 0)
  result = fsda$yXplot(h, d$y, d$X, nargout = 0)

  expect_null(result)
  figures = as.numeric(eval_m(h, "double(numel(findobj(0,'type','figure')))"))
  expect_gt(figures[1], 0)
})

test_that("a struct is driven MATLAB-side, since it does not marshal inward", {
  # engine.py's to_matlab() has no dict branch, so a struct argument is handed
  # to a routine by keeping it in the workspace and naming it.
  h = live_session()
  d = make_data()
  Y = cbind(d$X, d$y)

  eda = fsda$FSMeda(h, Y, matrix(1:15, ncol = 1), init = 20, plots = 0, msg = 0)
  expect_false(is.null(eda$MAL))       # structs marshal OUT without trouble

  on.exit(try(eval_m(h, "close all;", nargout = 0), silent = TRUE), add = TRUE)
  eval_m(h, "close all;", nargout = 0)
  fsda_call(h, "assignin", "base", "Ydata", Y, nargout = 0)
  eval_m(h, "outEDA = FSMeda(Ydata, (1:15)', 'init', 20, 'msg', 0, 'plots', 0);",
         nargout = 0)
  eval_m(h, "malfwdplot(outEDA);", nargout = 0)

  MAL = as.matrix(eval_m(h, "outEDA.MAL"))
  expect_equal(as.matrix(eda$MAL), MAL)
})

test_that("MATLAB's own functions return unnamed positional outputs", {
  # Not an FSDA routine, and the reason this package has no wrappers: MATLAB's
  # kmeans returns four unnamed outputs, so there is no raw$idx to reach. FSDA's
  # own routines return structs and do not have this problem. Callers who need
  # such a function pass nargout and unpack by position.
  h = live_session()

  set.seed(5)
  Y = rbind(matrix(rnorm(60, mean = 0), ncol = 2),
            matrix(rnorm(60, mean = 6), ncol = 2))

  raw = fsda$kmeans(h, Y, 2, Replicates = 5, nargout = 4)
  expect_length(raw, 4L)
  expect_null(raw$idx)                        # no names to reach
  expect_equal(length(as.vector(raw[[1]])), nrow(Y))   # labels, by position
  expect_equal(dim(raw[[2]]), c(2L, 2L))              # centroids
})

test_that("the shared session survives across calls", {
  running = get(".is_running", envir = asNamespace("fsdabridge"))
  live_session()
  expect_true(running())

  set.seed(2)
  Y = matrix(rnorm(20), ncol = 2)
  fsda$mahalFS(Y, matrix(colMeans(Y), nrow = 1), cov(Y))
  expect_true(running())
})


test_that("a failed routine leaves its condition in fsda_last_error", {
  live_session()

  expect_error(fsda$FSR("not a matrix"))
  captured = fsda_last_error()

  expect_s3_class(captured, "condition")
  expect_true(nzchar(conditionMessage(captured)))
})

test_that("a dead MATLAB process is detected and replaced", {
  # The recovery path. Killing the engine behind the handle leaves the session
  # object intact but unusable; the next fsda_session() must notice and start a
  # fresh one rather than failing somewhere inside reticulate.
  h = live_session()
  alive = get(".session_alive", envir = asNamespace("fsdabridge"))

  expect_true(alive(h))

  stop_engine(h)                  # kill the process, keep the stale handle
  expect_false(alive(h))

  fresh = fsda_session()
  expect_true(alive(fresh))
  expect_false(identical(fresh, h))

  # And the new session works.
  set.seed(4)
  Y = matrix(rnorm(30), ncol = 3)
  d = fsda$mahalFS(Y, matrix(colMeans(Y), nrow = 1), cov(Y))
  expect_length(as.numeric(d), nrow(Y))
})
