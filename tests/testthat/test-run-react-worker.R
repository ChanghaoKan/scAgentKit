test_that("one verified worker serves cold and hot calls without changing state", {
  f <- react_tool_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  before <- .sc_project_sha_file(file.path(f$root, "state.rds"))
  runtime <- .sc_run_react_worker_start(f$context)
  on.exit(runtime$process$kill_tree(), add = TRUE)
  cold <- .sc_run_react_worker_call(runtime, "cluster_markers", list(cluster_id = "0", n = 50))
  hot <- .sc_run_react_worker_call(runtime, "cluster_markers", list(cluster_id = "0", n = 50))
  expect_true(cold$ok); expect_true(hot$ok)
  expect_false(cold$cached); expect_true(hot$cached)
  expect_identical(cold$result, hot$result)
  expect_silent(.sc_run_react_worker_check(runtime, final = TRUE))
  expect_identical(.sc_project_sha_file(file.path(f$root, "state.rds")), before)
  expect_false(.sc_run_react_worker_call(runtime, "not_a_tool", list())$ok)
  bad <- .sc_run_react_worker_call(runtime, "gene_expression",
    list(cluster_id = "0", genes = rep("a", 21)))
  expect_identical(bad$error$code, "invalid_arguments")
})

test_that("worker checkpoint substitution is detected even at the same path", {
  f <- react_tool_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  runtime <- .sc_run_react_worker_start(f$context)
  on.exit(runtime$process$kill_tree(), add = TRUE)
  path <- file.path(f$root, f$context$binding$files$analysis$path)
  replacement <- tempfile(tmpdir = dirname(path))
  file.copy(path, replacement)
  old <- file.info(path)$mtime
  file.rename(replacement, path)
  Sys.setFileTime(path, old)
  expect_error(.sc_run_react_worker_check(runtime), class = "sc_run_react_error")
})

test_that("verified snapshot decodes the bytes it hashed and rejects corruption", {
  f <- react_tool_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  loaded <- .sc_run_react_snapshot(f$context)
  expect_true(environmentIsLocked(loaded$context$objects))
  expect_identical(.sc_run_react_cluster_markers(loaded$context, list(cluster_id = "0", n = 50)),
    .sc_run_react_cluster_markers(f$context, list(cluster_id = "0", n = 50)))
  path <- file.path(f$root, f$context$binding$files$markers$path)
  cat("corrupt", file = path, append = TRUE)
  expect_error(.sc_run_react_snapshot(f$context), class = "sc_run_react_error")
})

test_that("worker implementation drift is rejected before scientific loading", {
  f <- react_tool_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  context <- f$context
  context$binding$implementation_hash <- strrep("0", 64)
  expect_error(.sc_run_react_snapshot(context), class = "sc_run_react_error")
})

test_that("tool deadlines terminate workers and final SHA catches metadata-preserving edits", {
  f <- react_tool_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  runtime <- .sc_run_react_worker_start(f$context)
  on.exit(.sc_run_react_worker_close(runtime), add = TRUE)
  out <- .sc_run_react_worker_call(runtime, "cluster_markers",
    list(cluster_id = "0", n = 50), timeout = 0.000001)
  expect_identical(out$error$code, "timeout")
  expect_false(runtime$process$is_alive())
  expect_silent(.sc_run_react_worker_check(runtime, final = TRUE))
  path <- file.path(f$root, f$context$binding$files$markers$path)
  old <- file.info(path)$mtime
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  bytes[[length(bytes)]] <- as.raw(bitwXor(as.integer(bytes[[length(bytes)]]), 1L))
  writeBin(bytes, path); Sys.setFileTime(path, old)
  expect_silent(.sc_run_react_worker_check(runtime))
  expect_error(.sc_run_react_worker_check(runtime, final = TRUE), class = "sc_run_react_error")
})
