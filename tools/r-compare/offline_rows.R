# Offline rows of the spec 025 matrix (no MATLAB needed).
#
#   R_LIBS=<lib> Rscript tools/r-compare/offline_rows.R <build_dir>
#
# Row 3  autocompletion: utils:::.DollarNames and R's console completer.
# Row 4  documentation: does ?Score exist in each package?
# Row 10 namespace clashes: library() after stats and robustbase, then conflicts().
# Row 11 load time (fresh R, median of 10) and tarball / installed size.

build = commandArgs(trailingOnly = TRUE)[1]
pkgs = c(A = "fsdabridge", B = "fsdabridgeGen", C = "fsdabridgeHybrid")
say = function(...) cat(..., "\n", sep = "")
rscript = file.path(R.home("bin"), "Rscript")
fresh = function(code) system2(rscript, c("-e", shQuote(code)), stdout = TRUE, stderr = TRUE)

# R's own TAB completion, as the console (and ESS) sees it.
complete = function(line) {
  utils:::.assignLinebuffer(line)
  utils:::.assignEnd(nchar(line))
  utils:::.guessTokenFromLine()
  utils:::.completeToken()
  utils:::.retrieveCompletions()
}

say("## row 3: autocompletion")
for (a in names(pkgs)) {
  out = fresh(sprintf(paste0(
    "suppressPackageStartupMessages(library(%s));",
    "complete = %s;",
    "cat('  .DollarNames(fsda, \"Sc\"): ', if (exists('fsda')) paste(utils:::.DollarNames(fsda, '^Sc'), collapse=' ') else '(no fsda object)', '\\n');",
    "cat('  TAB on fsda$Sc        : ', paste(complete('fsda$Sc'), collapse=' '), '\\n');",
    "cat('  TAB on Sc             : ', paste(grep('^Sc', complete('Sc'), value=TRUE), collapse=' '), '\\n');",
    "cat('  TAB on Score(y, X,    : ', paste(grep('=$', complete('Score(y, X, '), value=TRUE), collapse=' '), '\\n');",
    "cat('  TAB on fsda$Score(y,X,: ', paste(grep('=$', complete('fsda$Score(y, X, '), value=TRUE), collapse=' '), '\\n');",
    "if (exists('Score')) cat('  formals(Score)        : ', paste(names(formals(Score)), collapse=', '), '\\n')"),
    pkgs[[a]], paste(deparse(complete), collapse = "\n")))
  say(a, " (", pkgs[[a]], ")"); say(paste(out, collapse = "\n"))
}

say("\n## row 4: documentation")
for (a in names(pkgs)) {
  db = tools::Rd_db(pkgs[[a]])
  topics = sort(sub("\\.Rd$", "", names(db)))
  has = "Score.Rd" %in% names(db)
  say(a, ": Rd topics=", length(topics), "; ?Score exists=", has,
      "; help('Score', package=) hits=", length(utils::help("Score", package = (pkgs[[a]]))))
  if (has) {
    txt = capture.output(tools::Rd2txt(db[["Score.Rd"]], options = list(underline_titles = FALSE)))
    say("  Score.Rd -> ", length(txt), " text lines; head:")
    for (l in head(txt[nzchar(trimws(txt))], 8)) say("    | ", l)
  }
}

say("\n## row 10: namespace clashes (fresh R: library(stats); library(robustbase); library(pkg))")
for (a in names(pkgs)) {
  out = fresh(sprintf(paste0(
    "suppressPackageStartupMessages({library(stats); library(robustbase); library(%s)});",
    "cf = conflicts(detail = TRUE); mine = cf[['package:%s']];",
    "cat('  masks/masked: ', if (length(mine)) paste(mine, collapse=' ') else '(none)', '\\n');",
    "all = conflicts(); cat('  conflicts() total: ', length(all), '\\n')"), pkgs[[a]], pkgs[[a]]))
  say(a, ":"); say(paste(out, collapse = "\n"))
}
# Masking the other way: names a generated package would shadow if a user
# attaches it after robustbase/MASS, checked against every installed package.
gen = setdiff(getNamespaceExports("fsdabridgeGen"), c("fsda_call", "eval_m"))
other = c("stats", "robustbase", "MASS", "rrcov", "cluster")
for (o in other) {
  if (requireNamespace(o, quietly = TRUE)) {
    hit = intersect(gen, getNamespaceExports(o))
    say("  B exports also exported by ", o, ": ", if (length(hit)) paste(hit, collapse = " ") else "(none)")
  }
}

say("\n## row 11: load time and size")
for (a in names(pkgs)) {
  times = vapply(1:10, function(i) {
    as.numeric(fresh(sprintf("cat(system.time(suppressPackageStartupMessages(library(%s)))[['elapsed']])",
                             pkgs[[a]])))
  }, numeric(1))
  tarball = Sys.glob(file.path(build, paste0(pkgs[[a]], "_*.tar.gz")))
  inst = find.package(pkgs[[a]])
  inst_kb = sum(file.size(list.files(inst, recursive = TRUE, full.names = TRUE))) / 1024
  say(sprintf("%s: library() median %.3f s (min %.3f, max %.3f, n=10); tarball %d bytes; installed %.0f KB",
              a, median(times), min(times), max(times), file.size(tarball[1]), inst_kb))
}
# What library() actually loads (reticulate is deferred to the first call), the
# deferred cost, and the full-IR dry-run package for scale.
for (p in c(pkgs, Bfull = "fsdabridgeGenFull")) {
  out = fresh(sprintf(paste0("a = loadedNamespaces(); t = system.time(library(%s))[['elapsed']];",
                             "cat(t, 'newly loaded:', setdiff(loadedNamespaces(), a))"), p))
  say("  ", p, ": library() ", out)
}
say("  deferred to first call: loadNamespace('reticulate') ",
    fresh("cat(system.time(loadNamespace('reticulate'))[['elapsed']])"), " s",
    "; MATLAB engine boot: see 'session boot' in 05_live_*.log")
full = Sys.glob(file.path(build, "fsdabridgeGenFull_*.tar.gz"))
if (length(full)) say("  Bfull (83 wrappers) tarball ", file.size(full[1]), " bytes")
