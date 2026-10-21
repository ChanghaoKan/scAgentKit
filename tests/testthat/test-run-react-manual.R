test_that("manual citation deletion publishes a verifiable review with the reduced authority", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  state <- .sc_run_load(f$root)
  state$config$annotation_column <- "cell_type"
  state$config_hash <- .sc_run_hash(state$config)
  evidence <- .sc_run_get(f$root, state, "annotation_evidence")
  evidence$summary$clusters <- lapply(evidence$summary$clusters, function(cluster) {
    cluster$markers <- lapply(cluster$markers, function(marker) {
      marker$clusterId <- cluster$clusterId; marker$source <- "saved software fixture"; marker
    }); cluster
  })
  evidence$private$candidates <- .empty_reference_matches()
  evidence$private$candidates_all <- .empty_reference_matches()
  evidence$private$reference_provenance <- list(status = "not_supplied")
  evidence$private$reference_evidence <- list(schema = "scagentkit.reference-evidence.v1",
    provenance = evidence$private$reference_provenance,
    per_cluster = lapply(evidence$summary$clusters, function(cluster)
      list(clusterId = cluster$clusterId, cellCount = cluster$cellCount, status = "not_supplied",
        candidates = list(), all_candidates = list(),
        marker_symbols = .sc_run_reference_symbols(vapply(cluster$markers, `[[`, character(1), "gene"), NULL))))
  state <- .sc_run_put(f$root, state, "annotation_evidence", evidence)
  .sc_run_save(f$root, state)
  run <- .sc_run_react_refine(f$root, f$baseline, react_mock())
  edited <- run$proposal
  edited$annotations[[1]]$label <- "Unknown"
  edited$annotations[[1]]$markers <- list()
  .sc_run_propose_locked(f$root, .sc_run_load(f$root), edited,
    "fixture-reviewer", "Remove one supporting citation.", drive = FALSE)
  state <- .sc_run_load(f$root)
  expect_silent(.sc_run_annotation_review_verify(f$root, state))
  expect_null(state$approved)
  expect_identical(state$pending$kind, "annotation")
  expect_error(.sc_run_annotation_validate(run$proposal,
    .sc_run_react_review_evidence(f$root, state)), "absent")
})
