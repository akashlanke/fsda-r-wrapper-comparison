# 02 -- Several routines, one call surface
#
#   FSDA_DEV_VENV=/path/to/venv/bin/python Rscript 02_routines.R
#
# Nothing in the package mentions any of the routines below. They work because
# the facade does not know which routines exist.
#
# Opens MATLAB figure windows near the end. Close them to finish.

library(fsdabridge)

set.seed(1)
n = 60
X = matrix(rnorm(n * 2), ncol = 2)
y = matrix(X %*% c(2, -1) + rnorm(n, sd = 0.5), ncol = 1)
y[c(3, 17, 41)] = y[c(3, 17, 41)] + 12    # planted outliers
Y = cbind(X, y)

cat("data:", n, "observations,", ncol(X), "predictors\n\n")


# --- Forward search ----------------------------------------------------------

out = fsda$FSR(y, X, nsamp = 0, intercept = TRUE, plots = 0, msg = 0)
cat("FSR\n  flagged:", as.integer(out$ListOut), "  (planted at 3, 17, 41)\n\n")


# --- Robust regression -------------------------------------------------------
#
# out$beta works straight off the facade: FSDA returns a struct, so the field
# is already there. A wrapper doing as.numeric(out$beta) would buy nothing.

lts = fsda$LXS(y, X, intercept = TRUE, lms = 0, nsamp = 1000, plots = 0, msg = 0)
lms = fsda$LXS(y, X, intercept = TRUE, lms = 1, nsamp = 1000, plots = 0, msg = 0)
mm  = fsda$MMreg(y, X, intercept = TRUE, plots = 0)

cat("Robust regression (true beta: 2, -1, intercept 0)\n")
cat("  LTS   :", round(as.numeric(lts$beta), 4), "\n")
cat("  LMS   :", round(as.numeric(lms$beta), 4), "\n")
cat("  MMreg :", round(as.numeric(mm$beta), 4), "\n")
cat("  OLS   :", round(coef(lm(y ~ X)), 4), "  <- dragged by the outliers\n\n")


# --- Box-Cox score test ------------------------------------------------------

la = c(-1, -0.5, 0, 0.5, 1)
score = fsda$Score(y - min(y) + 1, X, la = la, intercept = TRUE)
cat("Score\n")
for (i in seq_along(la)) {
  cat(sprintf("  lambda = %5.1f   score = %8.4f\n",
              la[i], as.numeric(score$Score)[i]))
}
cat("\n")


# --- Multivariate ------------------------------------------------------------

eval_m(NULL, "rng(0)", nargout = 0)      # FSM draws a random initial subset
fsm = fsda$FSM(Y, plots = 0, msg = 0)
cat("FSM\n  outliers:", as.integer(fsm$outliers), "\n\n")

cat("mcd\n  fields:", paste(head(names(fsda$mcd(Y, plots = 0, msg = 0)), 6),
                            collapse = ", "), "\n\n")


# --- Graphics: pass nargout = 0 ----------------------------------------------
#
# The facade does not know which routines draw figures — knowing that would
# need a list, and a list goes stale. So you say so. Without nargout = 0 the
# bridge would request a return value and try to marshal a MATLAB graphics
# handle, which is not a thing that crosses.

eval_m(NULL, "close all;", nargout = 0)
fsda$yXplot(y, X, nargout = 0)
render_figures()
cat("yXplot drawn; open figures:",
    as.numeric(eval_m(NULL, "double(numel(findobj(0,'type','figure')))")), "\n\n")

# boxplotb is the exception: it draws AND returns a real data struct, so it
# keeps nargout = 1. Its `handles` field crosses harmlessly as an empty array.
bx = fsda$boxplotb(cbind(X[, 1], y))
render_figures()
cat("boxplotb\n  centroid:", round(as.numeric(bx$cent), 4), "\n")
cat("  outliers:", sort(as.numeric(bx$outliers)), "\n\n")


# --- Struct arguments: the one real gap --------------------------------------
#
# The engine marshals MATLAB structs OUT but not IN — to_matlab() has no dict
# branch. A routine whose argument is a struct is driven by keeping the struct
# in the workspace and naming it, bringing back only the fields you need.

fsda_call(NULL, "assignin", "base", "Ydata", Y, nargout = 0)
eval_m(NULL, "outEDA = FSMeda(Ydata, (1:15)', 'init', 20, 'msg', 0, 'plots', 0);",
       nargout = 0)
eval_m(NULL, "malfwdplot(outEDA);", nargout = 0)
MAL = as.matrix(eval_m(NULL, "outEDA.MAL"))
cat("malfwdplot drawn from a struct kept MATLAB-side\n")
cat("  MAL:", paste(dim(MAL), collapse = " x "), "\n\n")

cat("Close the figure windows to finish.\n")
wait_for_figures()

fsda_shutdown()
