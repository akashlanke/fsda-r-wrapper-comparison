# Approach C additions: JSON-fed completion and fsda_help(). Offline unless noted.

test_that("completion is fed from the bundled routine list", {
  suggested = utils::.DollarNames(fsda, "^Sc")
  expect_true(all(c("Score", "ScoreYJ") %in% suggested))
  expect_true(length(utils::.DollarNames(fsda, "")) > 300)
})

test_that("a name missing from the list still works", {
  expect_false("aRoutineNobodyHasWrittenYet" %in% utils::.DollarNames(fsda, ""))
  expect_true(is.function(fsda$aRoutineNobodyHasWrittenYet))
})

test_that("fsda_help rejects a non-identifier before reaching MATLAB", {
  expect_error(fsda_help("Score'); system('x"), "identifier")
  expect_error(fsda_help(c("a", "b")), "identifier")
})

test_that("live: fsda_help returns MATLAB's help text", {
  skip_if(!nzchar(Sys.getenv("FSDA_LIVE")), "set FSDA_LIVE=1 to run live tests")
  txt = fsda_help("mahalFS")
  expect_s3_class(txt, "fsda_help")
  expect_match(unclass(txt), "mahalFS")
})
