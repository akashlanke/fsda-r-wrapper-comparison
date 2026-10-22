# Tab completion for `fsda$`, fed from a JSON routine list (spec 025, approach C).
#
# inst/extdata/fsda_routines.json is generated from FSDA's Contents.m inventory
# by tools/r-compare/make_routine_list.py. As in the plain facade, the list only
# suggests: `$` accepts every name whether or not it appears here, so a stale
# list costs a completion, never a call.

.routine_cache = new.env(parent = emptyenv())

# Read once per R session; an unreadable file degrades to "no suggestions".
.fsda_routines = function() {
  if (is.null(.routine_cache$names)) {
    path = system.file("extdata", "fsda_routines.json", package = "fsdabridgeHybrid")
    rows = if (nzchar(path)) tryCatch(jsonlite::fromJSON(path), error = function(e) NULL)
    .routine_cache$names = if (is.null(rows$name)) character(0) else as.character(rows$name)
  }
  .routine_cache$names
}

#' @importFrom utils .DollarNames
#' @export
.DollarNames.fsda_ns = function(x, pattern = "") {
  # Routines used successfully this session are offered too, as in the facade.
  seen = setdiff(ls(.validated, all.names = FALSE), ".handle")
  grep(pattern, sort(unique(c(.fsda_routines(), seen))), value = TRUE)
}

#' @export
print.fsda_ns = function(x, ...) {
  cat("<fsda> call any FSDA routine as fsda$<name>(...)\n")
  cat("Completion knows ", length(.fsda_routines()),
      " routines (fsda$<TAB>); any other name works too.\n", sep = "")
  cat("fsda_help(\"<name>\") shows MATLAB's help for a routine.\n")
  invisible(x)
}
