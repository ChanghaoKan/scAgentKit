test_that("audit exports remain bound to state and distinguish unknown costs", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  state <- .sc_run_load(f$root)
  run <- list(id = "run", session = list(id = "session"), status = "completed",
    targets = c("0", "index", "../outside"), traces = list(),
    binding = list(policy = list(mode = "all"), prompt_hash = "prompt"))
  for (id in run$targets) {
    trace <- list(cluster_id = id, session_id = "session", status = "completed",
      turns = list(list(usage = list(input_tokens = 10, output_tokens = 2), cost_usd = NULL)),
      tools = list(list(tool = "gene_expression", source = "tool:1", model_turn = 1L,
        arguments = list(genes = list("G01")), response = list(ok = TRUE,
          result = paste(rep("证据", 3000), collapse = "")))),
      result = list(row = list(label = "Unknown")))
    key <- paste0("react_cluster_", .sc_run_hash(id))
    state <- .sc_run_put(f$root, state, key, trace)
    run$traces[[id]] <- state$files[[key]]
  }
  state <- .sc_run_put(f$root, state, "annotation_react_run", run)
  audit <- .sc_run_react_audit(f$root, state)
  expect_equal(audit$summary$input_tokens$known, 30)
  expect_equal(audit$summary$unknown_cost_turns, 3)
  expect_equal(audit$summary$known_cost_usd, 0)
  expect_identical(audit$clusters[[1]]$tools[[1]]$evidence_status, "untested_background")
  preview <- audit$clusters[[1]]$tools[[1]]$preview
  expect_true(preview$truncated)
  expect_lte(nchar(preview$text, type = "bytes"), 4096L)
  exports <- .sc_run_react_export(f$root, state)
  expect_length(unique(vapply(exports, `[[`, "", "path")), 3)
  expect_identical(exports[[1]]$path, "annotation/react/0.json")
  expect_true(all(vapply(exports, function(x)
    identical(x$sha256, .sc_project_sha_file(file.path(f$root, x$path))), logical(1))))
  index <- jsonlite::read_json(file.path(f$root, "annotation/react/index.json"))
  expect_identical(index$schema, "scagentkit.react-export-index.v1")
  expect_false(file.exists(file.path(f$root, "outside.json")))
  key <- paste0("react_cluster_", .sc_run_hash("0"))
  state$files[[key]]$sha256 <- paste(rep("0", 64), collapse = "")
  expect_error(.sc_run_react_audit(f$root, state), "committed state")
})
