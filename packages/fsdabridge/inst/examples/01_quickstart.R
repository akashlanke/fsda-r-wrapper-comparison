# 01 -- Quickstart
#
# The smallest thing that proves the bridge works end to end.
#
#   FSDA_DEV_VENV=/path/to/venv/bin/python Rscript 01_quickstart.R
#
# Set FSDA_ROOT too if FSDA is not already on the MATLAB path.

library(fsdabridge)

fsda_root = Sys.getenv("FSDA_ROOT")
if (nzchar(fsda_root)) {
  # Only honoured by the call that starts the session, so do it first.
  # invisible(), or the handle prints itself at the top level.
  invisible(fsda_session(fsda_root = fsda_root))
}


# --- 1. Every routine is called the same way ---------------------------------
#
# fsda$<name>(...) reaches any FSDA routine. There is no list of supported
# names anywhere in the package, so a routine added to FSDA tomorrow works
# today.

set.seed(42)
Y = matrix(rnorm(60), ncol = 3)
MU = matrix(colMeans(Y), nrow = 1)

d = fsda$mahalFS(Y, MU, cov(Y))
cat("mahalFS returned", length(d), "distances\n")
cat("first three:", round(head(as.numeric(d), 3), 4), "\n\n")


# --- 2. Check it against R ---------------------------------------------------
#
# The agreement gate: a bridge that returns plausible numbers is not finished.

gap = max(abs(as.numeric(d) - stats::mahalanobis(Y, colMeans(Y), cov(Y))))
cat("max difference vs stats::mahalanobis:", format(gap, scientific = TRUE), "\n")
cat("agrees to 1e-9:", gap < 1e-9, "\n\n")


# --- 3. Output is already usable ---------------------------------------------
#
# FSDA routines return MATLAB structs, and a struct arrives as a named list.
# No wrapper is needed to reach a field.

set.seed(1)
n = 50
X = matrix(rnorm(n * 2), ncol = 2)
y = matrix(X %*% c(2, -1) + rnorm(n), ncol = 1)   # (n, 1): a 1-D vector would
y[c(7, 22)] = y[c(7, 22)] + 10                    # cross into MATLAB as a ROW

out = fsda$FSR(y, X, nsamp = 0, intercept = TRUE, plots = 0, msg = 0)
cat("FSR returned fields:", paste(head(names(out), 8), collapse = ", "), "...\n")
cat("outliers (MATLAB 1-based):", as.integer(out$ListOut), "\n")
cat("(planted at 7 and 22)\n\n")


# --- 4. A typo fails in R, not somewhere inside MATLAB -----------------------
#
# The first time a name is used, MATLAB is asked whether the routine exists, so
# a misspelling is caught before anything is marshalled.
#
# One caveat, and it is a Windows one: `which` resolves through a
# case-insensitive filesystem, so a typo that differs from a real routine only
# by case (FSRR vs FSRr) is found by the check and then rejected by MATLAB's
# case-sensitive function dispatch. The error still arrives, just from MATLAB
# rather than from R.

bad = tryCatch(fsda$notARealRoutine(y, X), error = function(e) conditionMessage(e))
cat("fsda$notARealRoutine(...) ->", bad, "\n\n")


# --- 5. Release the session --------------------------------------------------
#
# MATLAB starts on the first call and stays up. One session serves everything.

fsda_shutdown()
cat("done\n")
