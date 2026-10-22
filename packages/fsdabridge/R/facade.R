# The generic facade: `fsda$<name>(...)` calls any FSDA routine.
#
# No routine name appears anywhere in the dispatch path. A name exists only
# because someone typed it, so nothing here needs updating when FSDA adds a
# routine, and nothing here can claim a routine works when it does not.
#
# This is pyfsda's module-level __getattr__, which R reproduces by overloading
# `$`. Julia cannot: a module there cannot intercept unknown names, so its
# facade has to enumerate routines.
#
# The package ships no per-routine wrappers and needs none: FSDA routines
# return MATLAB structs, which arrive as named lists, so `out$beta` works
# unaided. inst/examples/03_probe_output_shapes.R checks that rather than
# assuming it.

# Callables, cached by name. Each closes over its name only -- the handle is
# resolved per call -- so one cache is valid across sessions.
.wrappers = new.env(parent = emptyenv())

# Names confirmed present on the MATLAB path. Tied to a session, since a new
# engine may have a different fsda_root.
.validated = new.env(parent = emptyenv())

# An explicit handle may lead the arguments; otherwise the shared session is
# used. Tested by S3 class and never by position, so a matrix in first position
# cannot be mistaken for a handle.
.facade_handle = function(args) {
  if (length(args) > 0L && inherits(args[[1L]], "fsda_engine")) {
    list(handle = args[[1L]], rest = args[-1L])
  } else {
    list(handle = fsda_session(), rest = args)
  }
}

# Ask MATLAB whether a routine exists, once per name per session, so a typo
# fails in R rather than deep inside the bridge. Generic: the question is
# identical for every name.
#
# One gap, on case-insensitive filesystems: `which` resolves through the file
# system, so a name differing from a real routine only by case (FSRR against
# FSDA's FSRr) passes here and is then rejected by MATLAB's case-sensitive
# dispatch. The error still reaches the caller, just from MATLAB.
.validate_routine = function(handle, name) {
  if (!isTRUE(getOption("fsdabridge.validate", TRUE))) {
    return(invisible(FALSE))
  }

  if (!identical(.validated$.handle, handle)) {
    rm(list = ls(.validated, all.names = TRUE), envir = .validated)
    assign(".handle", handle, envir = .validated)
  }
  if (isTRUE(.validated[[name]])) {
    return(invisible(TRUE))
  }

  found = tryCatch(handle$engine$which(name), error = function(e) "")
  if (!nzchar(found)) {
    stop("FSDA routine '", name, "' was not found on the MATLAB path. ",
         "Check the spelling, or that the FSDA toolbox is installed and on ",
         "the path (see start_engine(fsda_root = ...)).", call. = FALSE)
  }

  assign(name, TRUE, envir = .validated)
  invisible(TRUE)
}

.make_wrapper = function(name) {
  force(name)   # R closures capture the BINDING, not the value. Without this
                # every callable would invoke whichever name was resolved last,
                # silently and with no error.

  fn = function(...) {
    parts = .facade_handle(list(...))
    .validate_routine(parts$handle, name)
    # quote = TRUE keeps do.call from re-deparsing the arguments, which would
    # embed whole matrices in the call object and in any downstream error.
    #
    # .record_failure() keeps the condition object for fsda_last_error() and
    # rethrows it unchanged, so ordinary error handling is unaffected.
    .record_failure(
      do.call(fsda_call, c(list(parts$handle, name), parts$rest), quote = TRUE)
    )
  }

  structure(fn, class = c("fsda_routine", "function"), routine = name)
}

#' Call any FSDA routine
#'
#' `fsda$<name>(...)` calls the FSDA routine `<name>` through the shared engine
#' session. Positional arguments become MATLAB positional arguments in order;
#' named arguments become MATLAB name/value option pairs. `nargout`,
#' `echo_output` and `options` are consumed by the bridge rather than passed on.
#'
#' Every routine FSDA provides works, including ones added after this package
#' was built. There is no list of supported routines, so there is nothing to
#' keep up to date and nothing that can advertise a routine that does not work.
#'
#' An engine handle may lead the arguments to use a session of your own;
#' without one the shared session is used.
#'
#' @section Arguments and outputs:
#' This facade knows nothing about any individual routine -- not its arguments,
#' not how many values it returns. See the FSDA documentation for a routine's
#' own signature.
#'
#' A 1-D input crosses as a MATLAB **row**, so pass `y` as an `(n, 1)` matrix
#' when a routine wants a column. Outputs come back in MATLAB's natural shape,
#' and indices returned from MATLAB stay 1-based.
#'
#' FSDA routines return a struct, which arrives as a named list, so `out$beta`
#' works with no wrapper. MATLAB's own functions often return several unnamed
#' positional outputs instead; request them with `nargout` and unpack by
#' position:
#'
#' ```
#' raw = fsda$kmeans(Y, 3, Replicates = 10, nargout = 4)
#' idx = raw[[1]]
#' ```
#'
#' @section Plotting routines:
#' Pass `nargout = 0` for a routine called to draw a figure, so no graphics
#' handle is requested:
#'
#' ```
#' fsda$yXplot(y, X, nargout = 0)
#' render_figures()
#' ```
#'
#' `boxplotb` is the exception worth knowing: it draws *and* returns a real data
#' struct, so it keeps `nargout = 1`.
#'
#' @section Struct arguments:
#' The engine marshals MATLAB structs out but not in, so a routine taking a
#' struct argument is driven by keeping the struct in the workspace:
#'
#' ```
#' eval_m(NULL, "outEDA = FSMeda(Y, bsb, 'plots', 0);", nargout = 0)
#' eval_m(NULL, "malfwdplot(outEDA);", nargout = 0)
#' ```
#'
#' @section Typos:
#' The first time a name is used, MATLAB is asked whether the routine exists, so
#' a misspelling fails in R before anything is marshalled.
#'
#' On a case-insensitive filesystem this check resolves through the file system,
#' so a name differing from a real routine only by case (`FSRR` against FSDA's
#' `FSRr`) passes and is then rejected by MATLAB's case-sensitive dispatch. The
#' error still arrives, just from MATLAB rather than from R.
#'
#' `options(fsdabridge.validate = FALSE)` skips the check entirely.
#'
#' @format An object of class `"fsda_ns"`.
#' @seealso [fsda_call()] for the same call with the name as an argument,
#'   [fsda_session()] for the session it uses.
#' @examples
#' \dontrun{
#' out = fsda$FSR(y, X, nsamp = 0, intercept = TRUE, plots = 0)
#' d   = fsda$mahalFS(Y, matrix(colMeans(Y), nrow = 1), cov(Y))
#' ic  = fsda$tclustIC(Y, kk = matrix(2:4, nrow = 1), whichIC = "CLACLA")
#'
#' both = fsda$mcd(Y, nargout = 2)     # several MATLAB outputs
#' fsda$yXplot(y, X, nargout = 0)      # draw only
#'
#' h = start_engine()                  # your own session
#' d = fsda$mahalFS(h, Y, MU, SIGMA)
#' stop_engine(h)
#' }
#' @export
fsda = structure(list(), class = "fsda_ns")

#' @export
`$.fsda_ns` = function(x, name) {
  # Dot-names are R's own business: internals, str() and serialisation all probe
  # objects with them, and returning a routine callable would be silently wrong.
  if (startsWith(name, ".")) {
    stop("'", name, "' is not an FSDA routine name.", call. = FALSE)
  }

  wrapper = .wrappers[[name]]
  if (is.null(wrapper)) {
    wrapper = .make_wrapper(name)
    assign(name, wrapper, envir = .wrappers)
  }
  wrapper
}

#' @export
`[[.fsda_ns` = function(x, i, ...) {
  # Same mechanism, for names that are not syntactic R identifiers.
  `$.fsda_ns`(x, as.character(i))
}

#' @export
print.fsda_routine = function(x, ...) {
  routine = attr(x, "routine")
  cat("<fsda routine> ", routine, "\n", sep = "")
  cat("Calls FSDA '", routine, "' through the bridge. ",
      "See the FSDA documentation for its arguments.\n", sep = "")
  invisible(x)
}

# Tab completion only. This vector does not decide what works -- `$` accepts
# every name whether or not it appears here, so nothing breaks when it falls
# behind. test-offline.R asserts that it is never consulted.
.fsda_common = c(
  "mahalFS", "Score", "FSR", "FSRaddt", "FSRfan", "FSM", "FSMeda",
  "LXS", "MMreg", "mcd", "unibiv", "tclust", "tkmeans", "tclustIC",
  "pcaFS", "corrNominal", "boxplotb", "yXplot", "malfwdplot"
)

#' @export
.DollarNames.fsda_ns = function(x, pattern = "") {
  # Completion also learns: a routine used successfully this session is offered
  # from then on, even if it never appeared in .fsda_common.
  seen = setdiff(ls(.validated, all.names = FALSE), ".handle")
  grep(pattern, sort(unique(c(.fsda_common, seen))), value = TRUE)
}

#' @export
print.fsda_ns = function(x, ...) {
  cat("<fsda> call any FSDA routine as fsda$<name>(...)\n\n")
  cat("Completion suggests these; any other FSDA name works too:\n")
  cat(strwrap(paste(sort(.fsda_common), collapse = ", "),
              width = 76, indent = 2, exdent = 2), sep = "\n")
  invisible(x)
}
