# Build approach C (spec 025): packages/fsdabridge + the overlay in hybrid/.
#
#   Rscript tools/r-compare/make_hybrid.R <out_dir>
#
# Run from the repo root. Prints the files that differ from A, which is the
# whole cost of C over A.

args = commandArgs(trailingOnly = TRUE)
out = if (length(args) >= 1) args[1] else stop("usage: make_hybrid.R <out_dir>")
src = file.path("packages", "fsdabridge")
overlay = file.path("tools", "r-compare", "hybrid")

unlink(out, recursive = TRUE)
dir.create(out, recursive = TRUE)
file.copy(list.files(src, all.files = TRUE, no.. = TRUE, full.names = TRUE), out,
          recursive = TRUE)
unlink(file.path(out, "man"), recursive = TRUE)

rename = function(path) {
  txt = readLines(path, warn = FALSE)
  writeLines(gsub("\\bfsdabridge\\b", "fsdabridgeHybrid", txt), path)
}
for (f in c(file.path(out, "DESCRIPTION"),
            list.files(file.path(out, c("R", "tests", "inst/examples")),
                       pattern = "\\.R$", recursive = TRUE, full.names = TRUE))) {
  rename(f)
}

# DESCRIPTION: jsonlite reads the routine list.
desc = readLines(file.path(out, "DESCRIPTION"))
desc = sub("^    reticulate,$", "    jsonlite,\n    reticulate,", desc)
writeLines(desc, file.path(out, "DESCRIPTION"))

# facade.R: drop the hard-coded completion vector and the two methods using it;
# hybrid/R/completion.R replaces them.
facade = readLines(file.path(out, "R", "facade.R"))
cut = grep("^# Tab completion only", facade)
writeLines(facade[seq_len(cut - 1)], file.path(out, "R", "facade.R"))

# test-offline.R: the exported fsda_* set now includes fsda_help.
tf = file.path(out, "tests", "testthat", "test-offline.R")
tt = readLines(tf)
tt = sub('c("fsda_call", "fsda_last_error", "fsda_session", "fsda_shutdown")',
         'c("fsda_call", "fsda_help", "fsda_last_error", "fsda_session", "fsda_shutdown")',
         tt, fixed = TRUE)
writeLines(tt, tf)

for (f in list.files(overlay, recursive = TRUE)) {
  dir.create(dirname(file.path(out, f)), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(overlay, f), file.path(out, f), overwrite = TRUE)
}

# Twice: links between topics only resolve once man/ exists.
invisible(capture.output(roxygen2::roxygenise(out), type = "message"))
roxygen2::roxygenise(out)
cat("C differs from A in: DESCRIPTION, R/facade.R, tests/testthat/test-offline.R (edited);",
    paste(list.files(overlay, recursive = TRUE), collapse = ", "), "(added)\n")
