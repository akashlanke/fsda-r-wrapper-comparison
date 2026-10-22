# The shared MATLAB session.
#
# Starting MATLAB costs tens of seconds, so the package holds one session and
# reuses it. It starts on first use, never at load time, so FSDA_DEV_VENV can
# still be set after library(fsdabridge).
#
# State lives in an environment, not a top-level variable: a package namespace
# is locked after load, so `<<-` onto a namespace binding fails at runtime,
# while an environment's contents stay mutable.

.state = new.env(parent = emptyenv())

# Is the handle still backed by a live MATLAB process?
#
# A session can die under us -- MATLAB killed from the task manager, a crash, a
# laptop resumed from sleep. Without this check the next call fails somewhere
# deep inside reticulate with an error that says nothing useful.
#
# The probe asks MATLAB for its version, which costs one round-trip and no
# computation. Measured at roughly 15 ms, against a MATLAB start of ~30 s, so
# recovering automatically is far cheaper than the alternative.
.session_alive = function(handle) {
  isTRUE(tryCatch({
    handle$engine$version()
    TRUE
  }, error = function(e) FALSE))
}

#' The shared FSDA engine session
#'
#' `fsda_session()` returns the package-wide engine handle, starting it on first
#' use. Every call made without an explicit handle -- `FSR(y, X)`,
#' `eval_m(NULL, ...)`, `render_figures()` -- routes through this one session,
#' so MATLAB boots once per R session rather than once per call.
#'
#' If the MATLAB process behind the session has died -- killed externally, or
#' lost when a machine slept -- this is detected and a fresh session is started
#' in its place, rather than failing with a low-level error on the next call.
#'
#' Pass `routine`, `python` or `fsda_root` only on the call that actually starts
#' the session; they are ignored afterwards. `fsda_shutdown()` releases it, and
#' is safe to call when nothing is running. Handles from [start_engine()] are
#' independent and unaffected -- release those with [stop_engine()].
#'
#' @inheritParams start_engine
#' @return `fsda_session()` returns the shared object of class
#'   `"fsda_engine"`. `fsda_shutdown()` invisibly returns `TRUE` if a session
#'   was stopped and `FALSE` if none was running.
#' @seealso the generated wrappers to call routines, [start_engine()] for your own session,
#'   [fsda_last_error()] for the condition from the last failed call.
#' @examples
#' \dontrun{
#' fsda_session(fsda_root = "~/FSDA")   # optional, before the first call
#' d = mahalFS(Y, MU, SIGMA)
#' fsda_shutdown()
#' }
#' @export
fsda_session = function(routine = NULL, python = Sys.getenv("FSDA_DEV_VENV"),
                        fsda_root = NULL) {
  if (!is.null(.state$engine) && !.session_alive(.state$engine)) {
    message("fsdabridgeGen: the MATLAB session stopped responding -- restarting it.")
    .state$engine = NULL
  }

  if (is.null(.state$engine)) {
    message("fsdabridgeGen: starting the MATLAB engine (this takes a moment)...")
    .state$engine = start_engine(routine = routine, python = python,
                                 fsda_root = fsda_root)
  }
  .state$engine
}

#' @rdname fsda_session
#' @export

fsda_shutdown = function() {
  # Cleared unconditionally: a recorded error describes a session, and after
  # this call there is no session, whether or not one was running.
  .state$last_error = NULL

  if (is.null(.state$engine)) {
    return(invisible(FALSE))
  }
  handle = .state$engine
  .state$engine = NULL          # cleared first, so a failing stop cannot strand us
  try(stop_engine(handle), silent = TRUE)
  invisible(TRUE)
}

#' The condition from the last failed FSDA call
#'
#' A failing routine raises a MATLAB error that reticulate wraps and rethrows.
#' The message reaches the console, but the condition object itself is gone by
#' the time you would want to inspect it. This keeps the most recent one.
#'
#' Cleared when a session is shut down, so it never describes a session that no
#' longer exists.
#'
#' @return The condition object from the most recent failed call, or `NULL` if
#'   no call has failed in this session.
#' @seealso the generated wrappers to call routines.
#' @examples
#' \dontrun{
#' try(FSR(y, X))
#' e = fsda_last_error()
#' conditionMessage(e)
#' }
#' @export
fsda_last_error = function() {
  .state$last_error
}

# Record a failure and rethrow it unchanged, so normal error handling is
# untouched and the condition is still available afterwards.
.record_failure = function(expr) {
  withCallingHandlers(
    expr,
    error = function(e) {
      .state$last_error = e
    }
  )
}

# Internal. The offline tests use it to assert they never boot MATLAB.
.is_running = function() {
  !is.null(.state$engine)
}
