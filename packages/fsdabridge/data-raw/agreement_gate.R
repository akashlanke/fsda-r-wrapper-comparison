# Agreement gate -- the project's definition of done.
#
# CONSTITUTION.md section 5: a port must reproduce genuine FSDA output. Same
# values, same flagged units, same structure, to 1e-9. A port not checked
# against the oracle is not finished.
#
# This is not the same thing as the live test suite. Those tests check that a
# call succeeds and that its answer is plausible -- FSR finds the units we
# planted, mahalFS agrees with stats::mahalanobis. This compares against a
# committed reference produced by FSDA itself, so a change in the bridge, the
# engine or the MATLAB release shows up as a numeric difference rather than as
# a still-plausible wrong answer.
#
# Not run by R CMD check: data-raw/ is excluded from the built package. Run it
# by hand on a machine with MATLAB, FSDA and a matched matlabengine:
#
#   Rscript data-raw/agreement_gate.R
#   Rscript data-raw/agreement_gate.R --update   # rewrite the gold files
#
# Gold files live in data-raw/reference/. Regenerate with --update only when a
# case or its inputs deliberately change, and read the diff before committing:
# an --update that silently absorbs a real regression is worse than no gate.

suppressPackageStartupMessages(library(fsdabridge))

TOLERANCE = 1e-9

args = commandArgs(trailingOnly = TRUE)
update_mode = "--update" %in% args

# Resolve reference/ relative to this script, so the gate runs from the package
# root, from data-raw/, or from anywhere else.
script_dir = local({
  cmd = grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(cmd) == 1) {
    return(normalizePath(dirname(sub("^--file=", "", cmd)), winslash = "/",
                         mustWork = TRUE))
  }
  normalizePath(file.path(getwd(), "data-raw"), winslash = "/", mustWork = FALSE)
})
reference_dir = file.path(script_dir, "reference")

fsda_root = Sys.getenv("FSDA_ROOT")
if (!nzchar(fsda_root)) fsda_root = NULL

engine_up = tryCatch({
  fsda_session(fsda_root = fsda_root)
  TRUE
}, error = function(e) {
  message("Could not start an engine: ", conditionMessage(e))
  FALSE
})

if (!engine_up) {
  stop("The agreement gate needs MATLAB, the FSDA Add-On and a matched ",
       "matlabengine. Set FSDA_DEV_VENV (and FSDA_ROOT if FSDA is not ",
       "already on the MATLAB path). See README.md.", call. = FALSE)
}

on.exit(fsda_shutdown(), add = TRUE)

results = list()

check_case = function(label, actual, gold_file) {
  gold_path = file.path(reference_dir, gold_file)

  if (update_mode || !file.exists(gold_path)) {
    dir.create(reference_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(actual, gold_path)
    cat(sprintf("[%-12s] gold written -> %s\n", label, basename(gold_path)))
    return(invisible(TRUE))
  }

  gold = readRDS(gold_path)
  diff = all.equal(actual, gold, tolerance = TOLERANCE)
  ok = isTRUE(diff)

  cat(sprintf("[%-12s] %s\n", label, if (ok) "PASS" else "FAIL"))
  if (!ok) {
    cat("               ", paste(diff, collapse = "\n                "), "\n")
  }

  results[[label]] <<- ok
  invisible(ok)
}


# --- cases ------------------------------------------------------------------
#
# Every routine is reached through the facade, exactly as a user would reach
# it -- the gate exercises the shipped call path, not a private one.
#
# Anything stochastic is seeded MATLAB-side immediately before the call, so the
# gold file stays reproducible.

set.seed(1)
Y = matrix(rnorm(40), ncol = 2)
check_case("mahalFS",
           fsda$mahalFS(Y, matrix(colMeans(Y), nrow = 1), cov(Y)),
           "mahalFS.rds")

set.seed(2)
n = 60
X = matrix(rnorm(n * 2), ncol = 2)
y = matrix(cbind(1, X) %*% c(1, 2, -1) + rnorm(n, sd = 0.2), ncol = 1)
y[c(3, 17, 41)] = y[c(3, 17, 41)] + 12       # planted outliers

check_case("FSR",
           fsda$FSR(y, X, nsamp = 0, intercept = TRUE, plots = 0, msg = 0),
           "FSR.rds")

check_case("Score",
           fsda$Score(y - min(y) + 1, X, la = c(-1, -0.5, 0, 0.5, 1),
                      intercept = TRUE),
           "Score.rds")

eval_m(NULL, "rng(0);", nargout = 0)
check_case("LXS_LTS",
           fsda$LXS(y, X, intercept = TRUE, lms = 0, nsamp = 1000,
                    plots = 0, msg = 0),
           "LXS_LTS.rds")

eval_m(NULL, "rng(0);", nargout = 0)
check_case("LXS_LMS",
           fsda$LXS(y, X, intercept = TRUE, lms = 1, nsamp = 1000,
                    plots = 0, msg = 0),
           "LXS_LMS.rds")

eval_m(NULL, "rng(0);", nargout = 0)   # FSM draws a random initial subset
check_case("FSM",
           fsda$FSM(cbind(X, y), plots = 0, msg = 0),
           "FSM.rds")

check_case("mcd",
           fsda$mcd(cbind(X, y), plots = 0, msg = 0),
           "mcd.rds")

set.seed(3)
blobs = rbind(matrix(rnorm(80, mean = 0), ncol = 2),
              matrix(rnorm(80, mean = 6), ncol = 2),
              matrix(rnorm(80, mean = -6), ncol = 2))
check_case("tclust",
           fsda$tclust(blobs, 3, 0.1, 10000),
           "tclust.rds")


# --- verdict ----------------------------------------------------------------

if (update_mode) {
  cat("\nGold files rewritten. Review the diff before committing.\n")
} else if (length(results) == 0) {
  cat("\nNo case had a gold file; all were written just now.\n")
  cat("Run the gate again to compare against them.\n")
} else {
  failed = sum(!unlist(results))
  cat("\n")
  if (failed > 0) {
    stop(failed, " of ", length(results),
         " agreement-gate case(s) FAILED at tolerance ", TOLERANCE, ".",
         call. = FALSE)
  }
  cat("All ", length(results), " agreement-gate cases PASS at tolerance ",
      TOLERANCE, ".\n", sep = "")
}
