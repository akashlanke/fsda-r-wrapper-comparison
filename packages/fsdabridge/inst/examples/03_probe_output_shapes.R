# 03 -- Does raw facade output already give usable named fields?
#
#   FSDA_DEV_VENV=/path/to/venv/bin/python Rscript 03_probe_output_shapes.R
#
# The no-wrapper design rests on one empirical claim: FSDA routines return
# MATLAB structs, and a struct arrives as a named list, so out$beta works with
# no help. This script calls each routine RAW and reports what comes back, so
# the claim can be checked rather than assumed.
#
# Read the output as:
#   USABLE RAW   a named list, $ works, no wrapper would add anything
#   POSITIONAL   unnamed outputs, naming them is real work
#   BARE VALUE   a matrix or vector, nothing to shape
#
# kmeans is included as a control: it is NOT an FSDA routine but a MATLAB
# Statistics Toolbox one, and it is the only POSITIONAL case here. FSDA's own
# routines all return structs, which is why this package ships no wrappers.

library(fsdabridge)

set.seed(1)
n = 60
X = matrix(rnorm(n * 2), ncol = 2)
y = matrix(X %*% c(2, -1) + rnorm(n, sd = 0.5), ncol = 1)
y[c(3, 17, 41)] = y[c(3, 17, 41)] + 12
Y = cbind(X, y)

blobs = rbind(matrix(rnorm(80, mean = 0), ncol = 2),
              matrix(rnorm(80, mean = 6), ncol = 2),
              matrix(rnorm(80, mean = -6), ncol = 2))

probes = list(
  list(name = "mahalFS", call = function()
    fsda$mahalFS(Y, matrix(colMeans(Y), nrow = 1), cov(Y))),
  list(name = "Score", call = function()
    fsda$Score(y - min(y) + 1, X, la = c(-1, 0, 1), intercept = TRUE)),
  list(name = "FSR", call = function()
    fsda$FSR(y, X, nsamp = 0, intercept = TRUE, plots = 0, msg = 0)),
  list(name = "FSRaddt", call = function()
    fsda$FSRaddt(y, X, intercept = TRUE, plots = 0, msg = 0)),
  list(name = "FSRfan", call = function()
    fsda$FSRfan(y - min(y) + 1, X, la = c(-1, 0, 1), plots = 0, msg = 0)),
  list(name = "LXS (LTS)", call = function()
    fsda$LXS(y, X, intercept = TRUE, lms = 0, nsamp = 1000, plots = 0, msg = 0)),
  list(name = "LXS (LMS)", call = function()
    fsda$LXS(y, X, intercept = TRUE, lms = 1, nsamp = 1000, plots = 0, msg = 0)),
  list(name = "MMreg", call = function()
    fsda$MMreg(y, X, intercept = TRUE, plots = 0)),
  list(name = "FSM", call = function() {
    eval_m(NULL, "rng(0)", nargout = 0)
    fsda$FSM(Y, plots = 0, msg = 0)
  }),
  list(name = "FSMeda", call = function()
    fsda$FSMeda(Y, matrix(1:15, ncol = 1), init = 20, plots = 0, msg = 0)),
  list(name = "mcd", call = function() fsda$mcd(Y, plots = 0, msg = 0)),
  list(name = "unibiv", call = function() fsda$unibiv(Y, plots = 0)),
  list(name = "boxplotb", call = function() fsda$boxplotb(cbind(X[, 1], y))),
  list(name = "tclust", call = function() fsda$tclust(blobs, 3, 0.1, 10000)),
  # Not an FSDA routine. Included as the control case: MATLAB's own functions
  # return unnamed positional outputs, FSDA's do not.
  list(name = "kmeans", call = function() {
    eval_m(NULL, "rng(0);", nargout = 0)
    fsda$kmeans(blobs, 3, Replicates = 10, nargout = 4)
  })
)

describe = function(v) {
  d = dim(v)
  shape = if (!is.null(d)) paste(d, collapse = " x ") else paste0("len ", length(v))
  paste0(class(v)[1], " [", shape, "]")
}

verdict = function(r) {
  if (is.list(r) && !is.null(names(r)) && any(nzchar(names(r)))) "USABLE RAW"
  else if (is.list(r)) "POSITIONAL"
  else "BARE VALUE"
}

cat("Probing raw facade output shapes\n")
cat(strrep("=", 72), "\n\n")

verdicts = list()

for (p in probes) {
  cat(p$name, "\n", strrep("-", nchar(p$name)), "\n", sep = "")
  result = tryCatch(p$call(), error = function(e) e)

  if (inherits(result, "error")) {
    cat("  FAILED: ", conditionMessage(result), "\n\n", sep = "")
    verdicts[[p$name]] = "FAILED"
    next
  }

  verdicts[[p$name]] = verdict(result)
  cat("  ", verdict(result), "\n", sep = "")

  if (is.list(result)) {
    nms = names(result)
    if (is.null(nms)) nms = rep("", length(result))
    for (i in seq_along(result)) {
      label = if (nzchar(nms[i])) nms[i] else paste0("[[", i, "]]")
      cat(sprintf("    %-16s %s\n", label, describe(result[[i]])))
    }
  } else {
    cat("    ", describe(result), "\n", sep = "")
  }
  cat("\n")
}

cat(strrep("=", 72), "\nSUMMARY\n\n")
for (nm in names(verdicts)) cat(sprintf("  %-14s %s\n", nm, verdicts[[nm]]))

# BARE VALUE needs no wrapper either -- a plain matrix has nothing to shape.
# Only POSITIONAL does.
no_wrapper = sum(vapply(verdicts, function(v) v %in% c("USABLE RAW", "BARE VALUE"),
                        logical(1)))
positional = names(verdicts)[vapply(verdicts, function(v) v == "POSITIONAL",
                                    logical(1))]

cat("\n", no_wrapper, " of ", length(verdicts), " routines need no wrapper.\n", sep = "")
cat("  USABLE RAW -> out$field already works\n")
cat("  BARE VALUE -> a plain matrix, nothing to shape\n")
if (length(positional)) {
  cat("\nPOSITIONAL, so a wrapper earns its place: ",
      paste(positional, collapse = ", "), "\n", sep = "")
} else {
  cat("\nNothing came back positional.\n")
}

fsda_shutdown()
