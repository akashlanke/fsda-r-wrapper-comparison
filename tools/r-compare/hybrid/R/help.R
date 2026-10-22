#' MATLAB help for an FSDA routine
#'
#' Runs `help <name>` in the engine's MATLAB session and returns the text, so
#' a routine's arguments, options and outputs can be read without leaving R.
#' The text is FSDA's own, so it is never out of date with the installed
#' toolbox.
#'
#' @param name Routine name, e.g. `"Score"`. Must be a MATLAB identifier.
#' @inheritParams fsda_call
#' @return A character string of class `"fsda_help"`; printing it shows the
#'   help text.
#' @examples
#' \dontrun{
#' fsda_help("Score")
#' }
#' @export
fsda_help = function(name, handle = NULL) {
  # The name is interpolated into a MATLAB statement, so it must be an identifier.
  if (!is.character(name) || length(name) != 1L || !grepl("^[A-Za-z]\\w*$", name)) {
    stop("name must be a single MATLAB identifier, e.g. \"Score\".", call. = FALSE)
  }
  txt = eval_m(handle, sprintf("evalc('help %s')", name))
  structure(paste(as.character(txt), collapse = ""), class = "fsda_help", routine = name)
}

#' @export
print.fsda_help = function(x, ...) {
  cat(unclass(x), "\n", sep = "")
  invisible(x)
}
