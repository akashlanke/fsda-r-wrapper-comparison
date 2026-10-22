# Live rows of the spec 025 matrix, run through ONE approach's own call surface.
#
#   Rscript tools/r-compare/live_rows.R A|B|C|Bfull
#
# Row 5  correctness: the check_engine.R cases (atol 1e-9), with fsda_call()/eval_m()
#        rebound to the approach's surface (A/C: fsda$<name>, B: the generated
#        function, or SKIP when it was not generated).
# Row 6  coverage: which FSDA routines resolve on the MATLAB path (A/C).
# Row 7  name/value options: Score(la, intercept) and an option absent from the JSON.
# Row 8  multiple outputs: mcd(Y, nargout = 2).
# Row 9  errors: where each failure is raised and what the user reads.
# Row 4  (C only) fsda_help("Score").
#
# Run from the repo root with FSDA_DEV_VENV set. Failures are classified per
# README section 6: a MatlabExecutionError is MATLAB rejecting inputs, not a bridge gap.

approach = commandArgs(trailingOnly = TRUE)[1]
pkg = c(A = "fsdabridge", B = "fsdabridgeGen", C = "fsdabridgeHybrid",
        Bfull = "fsdabridgeGenFull")[[approach]]
suppressPackageStartupMessages(library(pkg, character.only = TRUE))
ns = asNamespace(pkg)
generated = approach %in% c("B", "Bfull")

say = function(...) cat(..., "\n", sep = "")

# Where an error came from, by README section 6.
classify = function(e) {
  msg = conditionMessage(e)
  if (inherits(e, "not_generated")) return("not generated (B has no wrapper)")
  if (grepl("MatlabExecutionError", msg)) return("MATLAB (MatlabExecutionError: bad inputs, not a bridge gap)")
  if (grepl("not found on the MATLAB path", msg)) return("R facade (name check via MATLAB which)")
  if (grepl("Python|reticulate|TypeError|ValueError", msg)) return("Python bridge (conversion)")
  "R (before the bridge)"
}

one_line = function(msg, n = 220) {
  msg = gsub("[[:space:]]+", " ", msg)
  if (nchar(msg) > n) paste0(substr(msg, 1, n), " ...") else msg
}

# ---- the approach's surface, under the names check_engine.R uses -------------
route = function(name, args) {
  if (generated) {
    if (!exists(name, envir = ns, inherits = FALSE) || !(name %in% getNamespaceExports(pkg))) {
      stop(structure(class = c("not_generated", "error", "condition"),
                     list(message = paste0("no generated wrapper for ", name), call = NULL)))
    }
    do.call(get(name, envir = ns), args, quote = TRUE)
  } else {
    do.call(fsda[[name]], args, quote = TRUE)
  }
}

surface = new.env()
surface$fsda_call = function(h, name, ...) route(name, list(...))
surface$eval_m = function(h, expr, nargout = 1) get("eval_m", envir = ns)(NULL, expr, nargout = nargout)

# Pull the case functions and helpers out of check_engine.R without running it.
gate_file = file.path("code", "fsda_engine", "check_engine.R")
keep = "^(case_|read_matrix$|gate$|TOL$|LA$)"
for (ex in parse(gate_file)) {
  if (is.call(ex) && identical(ex[[1]], as.name("=")) && grepl(keep, deparse(ex[[2]]))) {
    eval(ex, surface)
  }
}
surface$CODE = "code"
surface$REFERENCE = file.path("code", "fsda_engine", "reference")
case_names = grep("^case_", ls(surface), value = TRUE)
case_order = c("numeric", "struct", "nested", "fsr", "fsraddt", "table", "univariatems",
               "corrnominal", "fsm", "mcd", "pcafs", "cressieread", "logfactorial",
               "tabulatefs", "tbwei", "gower", "tclustic", "removeextraspaces", "triu2vec",
               "bc", "combsfs", "lexunrank", "publishfs", "distribspec", "histfs", "boxplotb")
stopifnot(setequal(case_names, paste0("case_", case_order)))

say("=== spec 025 live rows: approach ", approach, " (package ", pkg, ") ===")
t_boot = system.time(get("eval_m", envir = ns)(NULL, "1"))[["elapsed"]]
say("session boot + first eval: ", round(t_boot, 1), " s")
d = get("diagnostics", envir = ns)(NULL)
say("R ", d$r, " | reticulate ", d$reticulate, " | Python ", d$python_version,
    " | MATLAB ", d$matlab, " | matlabengine ", d$matlabengine)

# ---- row 5 -------------------------------------------------------------------
if (approach != "Bfull") {
  say("\n## row 5: check_engine.R cases (atol 1e-9)")
  counts = c(PASS = 0, FAIL = 0, SKIP = 0, ERROR = 0)
  for (cn in case_order) {
    f = get(paste0("case_", cn), envir = surface)
    r = tryCatch(f(NULL), error = function(e) e)
    if (inherits(r, "not_generated")) {
      counts["SKIP"] = counts["SKIP"] + 1
      say(sprintf("  [SKIP ]  %-20s  %s", cn, conditionMessage(r)))
    } else if (inherits(r, "error")) {
      counts["ERROR"] = counts["ERROR"] + 1
      say(sprintf("  [ERROR]  %-20s  %s | %s", cn, classify(r), one_line(conditionMessage(r))))
    } else {
      tag = if (r$ok) "PASS" else "FAIL"
      counts[tag] = counts[tag] + 1
      say(sprintf("  [%-5s]  %-34s  max abs diff %.3e   %s", tag, r$name, r$diff, r$note))
    }
  }
  say("ROW5 ", paste(names(counts), counts, sep = "=", collapse = " "))
}

# ---- row 6 -------------------------------------------------------------------
if (!generated) {
  say("\n## row 6: routines in the Contents.m inventory that resolve on the MATLAB path")
  rows = jsonlite::fromJSON(file.path("tools", "r-compare", "hybrid", "inst", "extdata",
                                      "fsda_routines.json"))
  eng = get("fsda_session", envir = ns)()$engine
  found = vapply(rows$name, function(n) nzchar(eng$which(n)), logical(1))
  say("ROW6 inventory=", length(found), " on_path=", sum(found),
      " missing=", paste(rows$name[!found], collapse = ","))
} else {
  ex = getNamespaceExports(pkg)
  wr = setdiff(ex, c("start_engine", "fsda_call", "eval_m", "render_figures",
                     "wait_for_figures", "stop_engine", "diagnostics", "fsda_session",
                     "fsda_shutdown", "fsda_last_error"))
  say("\n## row 6: generated wrappers")
  say("ROW6 wrappers=", length(wr), " (fsda_call escape hatch still exported: ",
      "fsda_call" %in% ex, ")")
}

# ---- row 7 -------------------------------------------------------------------
wool = as.matrix(read.csv(file.path("code", "Score", "reference", "wool.csv")))
y = matrix(wool[, ncol(wool)], ncol = 1)
X = wool[, 1:(ncol(wool) - 1)]
gold = as.matrix(read.csv(file.path("code", "Score", "reference", "Score_check.csv")))[, "Score_fsda"]
try_row = function(label, expr) {
  t0 = proc.time()[["elapsed"]]
  r = tryCatch(expr, error = function(e) e)
  dt = round(proc.time()[["elapsed"]] - t0, 2)
  if (inherits(r, "error")) {
    say(sprintf("  %-46s ERROR [%s] (%.2fs) %s", label, classify(r), dt, one_line(conditionMessage(r))))
  } else {
    say(sprintf("  %-46s OK (%.2fs) %s", label, dt,
                paste(as.character(unlist(r)), collapse = " ")))
  }
  invisible(r)
}

say("\n## row 7: name/value options")
if (approach != "Bfull") {
  try_row("Score(y, X, la = LA, intercept = TRUE)", {
    out = route("Score", list(y, X, la = surface$LA, intercept = TRUE))
    sprintf("max|Score - gold| = %.3e", max(abs(as.numeric(out$Score) - gold)))
  })
  try_row("Score(y, X, la = 0.5, intercept = FALSE)", {
    out = route("Score", list(y, X, la = 0.5, intercept = FALSE))
    sprintf("Score = %.6f (differs from intercept=TRUE: %s)", as.numeric(out$Score),
            abs(as.numeric(out$Score) - as.numeric(route("Score", list(y, X, la = 0.5))$Score)) > 1e-12)
  })
  try_row("Score(y, X, notAnOption = 1)", {
    out = route("Score", list(y, X, notAnOption = 1))
    "accepted"
  })
}
if (approach != "B") {
  # ace's functionSignatures.json entry declares only y and X: maxit is real
  # (ace.m, 'maxit', default 20) but absent from the JSON.
  try_row("ace(y, X) vs ace(y, X, maxit = 3) [maxit not in JSON]", {
    a = route("ace", list(y, X))
    b = route("ace", list(y, X, maxit = 3))
    sprintf("max|ty(default) - ty(maxit=3)| = %.3e -> option reached MATLAB: %s",
            max(abs(as.numeric(a$ty) - as.numeric(b$ty))),
            max(abs(as.numeric(a$ty) - as.numeric(b$ty))) > 0)
  })
}
if (approach == "Bfull") {
  say("  formals(ace): ", paste(names(formals(get("ace", envir = ns))), collapse = ", "))
}

# ---- row 8 -------------------------------------------------------------------
if (approach != "Bfull") {
  say("\n## row 8: mcd(Y, nargout = 2)")
  Y = as.matrix(read.csv(file.path(surface$REFERENCE, "FSM_Y.csv")))
  try_row("mcd(Y, nargout = 2, plots = 0, msg = 0)", {
    surface$eval_m(NULL, "rng(0)", nargout = 0)
    res = route("mcd", list(Y, nargout = 2, plots = 0, msg = 0))
    sprintf("length=%d; classes=%s,%s; RAW$loc=[%s]; REW fields=%d", length(res),
            as.character(res[[1]]$class), as.character(res[[2]]$class),
            paste(sprintf("%.6f", as.numeric(res[[1]]$loc)), collapse = " "),
            length(names(res[[2]])))
  })
}

# ---- row 9 -------------------------------------------------------------------
if (approach != "Bfull") {
  say("\n## row 9: errors (origin | message)")
  MU = matrix(c(2, 2), nrow = 1)
  SIGMA = matrix(c(2, 0.5, 0.5, 1), 2, 2)
  try_row("mahalFS('abc', MU, SIGMA)  [char for matrix]", route("mahalFS", list("abc", MU, SIGMA)))
  try_row("mahalFS(list(1, 2), MU, SIGMA)  [R list]", route("mahalFS", list(list(1, 2), MU, SIGMA)))
  try_row("Score(y)  [required X missing]", route("Score", list(y)))
  try_row("Score(y, X, la = 'x')  [char for numeric option]", route("Score", list(y, X, la = "x")))
  if (generated) {
    try_row("Scroe(y, X)  [typo in routine name]", Scroe(y, X))
  } else {
    try_row("fsda$Scroe(y, X)  [typo in routine name]", fsda$Scroe(y, X))
  }
}

# ---- row 4 (C) ---------------------------------------------------------------
if (approach == "C") {
  say("\n## row 4: fsda_help('Score')")
  t0 = proc.time()[["elapsed"]]
  h = fsda_help("Score")
  txt = unclass(h)
  say("  chars=", nchar(txt), " lines=", length(strsplit(txt, "\n")[[1]]),
      " seconds=", round(proc.time()[["elapsed"]] - t0, 2))
  say("  first lines:")
  for (l in head(strsplit(txt, "\n")[[1]], 6)) say("    | ", l)
  say("  fsda_help('notARoutine'): ", one_line(unclass(fsda_help("notARoutine"))))
}

get("fsda_shutdown", envir = ns)()
say("\nDONE")
