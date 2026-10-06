annotation_review_fixture <- function(manual = TRUE, response = NULL, reference = FALSE) {
  root <- tempfile("annotation-review-")
  dir.create(root)
  input <- data.frame(cell_id = c("001", "1", "NA", "cell space", "Ca", "Ctrl"),
                      cluster = rep(c("01", "NA"), 3), stringsAsFactors = FALSE)
  marker <- function(id, gene, fold, within, outside) list(clusterId = id, gene = gene,
    avgLog2FC = fold, pct1 = within, pct2 = outside, pAdj = .001,
    source = "Seurat::FindAllMarkers")
  candidates <- scAgentKit:::.empty_reference_matches()
  if (reference) candidates <- data.frame(cluster = c("01", "NA"),
    cell_type = c("local liver candidate", "local lymphoid candidate"),
    overlap_count = c(1L, 1L), celltype_size = c(2L, 2L), score = c(.5, .5),
    matched_markers = c("ALB", "CD3D"), stringsAsFactors = FALSE)
  evidence <- list(summary = list(schema = "scagentkit.annotation-evidence.v1", clusters = list(
    list(clusterId = "01", cellCount = 3L, markers = list(
      marker("01", "ALB", 3, .9, .1), marker("01", "TTR", 2, .8, .05))),
    list(clusterId = "NA", cellCount = 3L, markers = list(
      marker("NA", "CD3D", 3, .9, .1), marker("NA", "CD3E", 2, .8, .05))))),
    private = list(input_cells = input, cluster_column = "chosen_clusters",
      candidates = candidates, candidates_all = candidates,
      reference_provenance = list(status = if (reference) "matched" else "not_supplied",
                                  mode = "independent_local_reference")))
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = list(
    list(clusterId = "NA", label = "T-like", confidence = "medium",
         rationale = "Supplied CD3D evidence supports a broad provisional label.", markers = list("CD3D")),
    list(clusterId = "01", label = "Liver-like", confidence = "low",
         rationale = "Supplied ALB evidence supports a broad provisional label.", markers = list("ALB"))))
  validated <- scAgentKit:::.sc_run_annotation_validate(proposal, evidence)
  config <- list(annotation_column = "fresh_annotation", provider = list(name = "deepseek",
    model = "configured-only", generation = list(temperature = 0), external = TRUE))
  state <- list(config = config, config_hash = scAgentKit:::.sc_run_hash(config),
    implementation_hash = scAgentKit:::.sc_run_implementation(),
    files = list(), history = list(), revision = 0L, approvals = list(),
    pending = NULL, approved = NULL, completed = character(), nodes = list(),
    stage = "annotation_propose", status = "ready")
  state <- scAgentKit:::.sc_run_put(root, state, "input", input)
  state$input_hash <- state$files$input$sha256
  state <- scAgentKit:::.sc_run_put(root, state, "annotation_evidence", evidence)
  state <- scAgentKit:::.sc_run_put(root, state, "annotation_validated", validated)
  if (!is.null(response)) state <- scAgentKit:::.sc_run_put(root, state, "annotation_response", response)
  if (manual) {
    state <- scAgentKit:::.sc_run_put(root, state, "manual_annotation", proposal)
    state <- scAgentKit:::.sc_run_event(state, "manual_proposal",
      list(kind = "annotation", reviewer = "fixture analyst", reason = "Use broad labels.",
           hash = scAgentKit:::.sc_run_hash(proposal)))
  }
  state <- scAgentKit:::.sc_run_annotation_review_publish(root, state, validated, evidence)
  state <- scAgentKit:::.sc_run_pending(state, "annotation", validated,
                                      scAgentKit:::.sc_run_hash(evidence), "annotation_apply")
  list(root = root, state = state, evidence = evidence, proposal = proposal, validated = validated)
}

test_that("annotation snapshot preserves literal scope and exact supplied cited statistics", {
  fixture <- annotation_review_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  before <- fixture
  record <- scAgentKit:::.sc_run_annotation_review_verify(fixture$root, fixture$state)
  expect_identical(fixture, before)
  expect_identical(record$schema, "scagentkit.annotation.review.v1")
  expect_identical(record$details$input_cells, fixture$evidence$private$input_cells)
  expect_identical(record$details$annotations[[1]]$cell_ids, c("001", "NA", "Ca"))
  expect_identical(record$details$annotations[[2]]$cell_ids, c("1", "cell space", "Ctrl"))
  expect_identical(record$details$annotations[[1]]$proposal$clusterId, "01")
  expect_identical(record$details$annotations[[1]]$proposal$label, "Liver-like")
  expect_identical(record$details$annotations[[1]]$cited_marker_stats,
                   fixture$evidence$summary$clusters[[1]]$markers[1])
  expect_identical(record$details$annotations[[1]]$supplied_marker_stats,
                   fixture$evidence$summary$clusters[[1]]$markers)
  expect_identical(record$cell_scope_hash, scAgentKit:::.sc_run_hash(fixture$evidence$private$input_cells))
  expect_identical(record$target_column, "fresh_annotation")
  expect_identical(record$details$output_columns$confidence, "fresh_annotation_confidence")
  expect_identical(fixture$state$pending$proposal, fixture$validated)
  expect_true("annotation_review" %in% names(fixture$state$pending$binding$files))
  expect_identical(record$hash, scAgentKit:::.sc_run_annotation_review_hash(record))
  expect_identical(record$details$source$kind, "manual")
  expect_false(record$details$annotations[[1]]$expression_assessment$per_cell_assessed)
  expect_false(record$details$annotations[[1]]$negative_evidence$assessed)
  expect_match(paste(record$details$limitations, collapse = " "), "not calibrated probabilities")
  expect_match(paste(record$details$limitations, collapse = " "), "not evidence of absent")
  expect_identical(scAgentKit:::.sc_run_annotation_review_summary(record)$hash, record$hash)
  expect_false("details" %in% names(scAgentKit:::.sc_run_annotation_review_summary(record)))
})

test_that("local reference availability is explicit and remains independent", {
  no_reference <- annotation_review_fixture()
  with_reference <- annotation_review_fixture(reference = TRUE)
  on.exit(unlink(c(no_reference$root, with_reference$root), recursive = TRUE), add = TRUE)
  absent <- scAgentKit:::.sc_run_annotation_review_verify(no_reference$root, no_reference$state)
  present <- scAgentKit:::.sc_run_annotation_review_verify(with_reference$root, with_reference$state)
  expect_identical(absent$details$annotations[[1]]$local_reference$status, "not_supplied")
  expect_length(absent$details$annotations[[1]]$local_reference$candidates, 0L)
  expect_identical(present$details$annotations[[1]]$local_reference$status, "available")
  expect_identical(present$details$annotations[[1]]$local_reference$candidates[[1]]$label,
                   "local liver candidate")
  expect_equal(present$details$annotations[[1]]$local_reference$candidates[[1]]$score, .5)
  expect_identical(present$details$annotations[[1]]$proposal$label, "Liver-like")
  expect_match(present$details$statistic_units$candidate_score, "not a calibrated probability")
  bad <- with_reference$evidence
  bad$private$reference_provenance$status <- "not_supplied"
  expect_error(scAgentKit:::.sc_run_annotation_review_build(with_reference$root,
    with_reference$state, with_reference$validated, bad), "marked absent")
})

test_that("proposal origins require real artifacts and historical responses remain distinct", {
  unknown <- annotation_review_fixture(manual = FALSE)
  on.exit(unlink(unknown$root, recursive = TRUE), add = TRUE)
  record <- scAgentKit:::.sc_run_annotation_review_verify(unknown$root, unknown$state)
  expect_identical(record$details$source$kind, "unknown")
  expect_identical(record$details$source$configured_provider$model, "configured-only")
  expect_identical(record$details$source$provider_response$status, "not_recorded")
  historical <- unknown$proposal
  historical$annotations[[2]]$label <- "Hepatocyte suggestion"
  response <- list(status = "ok", content = historical, raw = "do not expose raw response",
    provider = list(name = "mock", model = "offline-fixture", external = FALSE,
      api_key = "must-not-expose-fixture", generation = list(temperature = 0, api_key = "hidden")),
    request_hash = strrep("a", 64), cached = TRUE, cost_usd = 0,
    usage = list(input_tokens = 3, output_tokens = 2, cached_tokens = 1, secret = "hidden"))
  manual <- annotation_review_fixture(response = response)
  unmatched <- annotation_review_fixture(manual = FALSE, response = response)
  matched_response <- response
  matched_response$content <- unknown$proposal
  mock <- annotation_review_fixture(manual = FALSE, response = matched_response)
  on.exit(unlink(c(manual$root, unmatched$root, mock$root), recursive = TRUE), add = TRUE)
  edited <- scAgentKit:::.sc_run_annotation_review_verify(manual$root, manual$state)
  expect_identical(edited$details$source$kind, "manual")
  expect_false(edited$details$source$provider_response$matches_current)
  expect_identical(edited$details$source$provider_response$proposal$annotations[[1]]$label,
                   "Hepatocyte suggestion")
  expect_identical(edited$details$annotations[[1]]$proposal$label, "Liver-like")
  json <- scAgentKit:::.sc_project_json(edited)
  expect_false(grepl("must-not-expose|do not expose raw|hidden|api_key", json))
  expect_identical(scAgentKit:::.sc_run_annotation_review_verify(mock$root, mock$state)$details$source$kind, "mock")
  unmatched_source <- scAgentKit:::.sc_run_annotation_review_verify(unmatched$root, unmatched$state)$details$source
  expect_identical(unmatched_source$kind, "unknown")
  expect_identical(unmatched_source$provider_response$kind, "mock")
  expect_false(unmatched_source$provider_response$matches_current)
  invalid_response <- response
  invalid_response$status <- "invalid_response"
  invalid_response$content <- NULL
  invalid <- annotation_review_fixture(manual = FALSE, response = invalid_response)
  on.exit(unlink(invalid$root, recursive = TRUE), add = TRUE)
  invalid_source <- scAgentKit:::.sc_run_annotation_review_verify(invalid$root, invalid$state)$details$source
  expect_identical(invalid_source$kind, "unknown")
  expect_identical(invalid_source$provider_response$kind, "mock")
  expect_null(invalid_source$provider_response$proposal)
  no_provider <- matched_response
  no_provider$provider <- NULL
  fixture <- annotation_review_fixture(manual = FALSE, response = no_provider)
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  expect_identical(scAgentKit:::.sc_run_annotation_review_verify(fixture$root, fixture$state)$details$source$kind,
                   "provider_response")
})

test_that("annotation snapshot fails closed on hallucinations counts IDs and membership changes", {
  fixture <- annotation_review_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  hallucination <- fixture$validated
  hallucination$annotations[[1]]$markers <- list("MISSING-GENE")
  expect_error(scAgentKit:::.sc_run_annotation_review_build(fixture$root, fixture$state,
    hallucination, fixture$evidence), "absent.*evidence")
  duplicate <- fixture$evidence
  duplicate$private$input_cells$cell_id[2] <- "001"
  expect_error(scAgentKit:::.sc_run_annotation_review_build(fixture$root, fixture$state,
    fixture$validated, duplicate), "unique")
  wrong_count <- fixture$evidence
  wrong_count$summary$clusters[[1]]$cellCount <- 4L
  expect_error(scAgentKit:::.sc_run_annotation_review_build(fixture$root, fixture$state,
    fixture$validated, wrong_count), "cell counts")
  wrong_membership <- fixture$validated
  attr(wrong_membership, "input_cells")$cluster[1] <- "NA"
  expect_error(scAgentKit:::.sc_run_annotation_review_build(fixture$root, fixture$state,
    wrong_membership, fixture$evidence), "membership changed")
  wrong_statistics <- fixture$evidence
  wrong_statistics$summary$clusters[[1]]$markers[[1]]$pct1 <- 2
  expect_error(scAgentKit:::.sc_run_annotation_review_build(fixture$root, fixture$state,
    fixture$validated, wrong_statistics), "finite number in \\[0,1\\]")
})

test_that("snapshot state bindings protect exact evidence rules target and pending node", {
  fixture <- annotation_review_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  changed <- fixture$state
  changed$input_hash <- strrep("f", 64)
  expect_error(scAgentKit:::.sc_run_annotation_review_verify(fixture$root, changed), "fingerprint changed")
  changed <- fixture$state
  changed$config$annotation_column <- "different_target"
  changed$config_hash <- scAgentKit:::.sc_run_hash(changed$config)
  expect_error(scAgentKit:::.sc_run_annotation_review_verify(fixture$root, changed), "fingerprint changed")
  changed <- fixture$state
  changed$pending$proposal$annotations[[1]]$label <- "Changed unseen label"
  expect_error(scAgentKit:::.sc_run_annotation_review_verify(fixture$root, changed), "node binding changed")
  evidence_file <- file.path(fixture$root, fixture$state$files$annotation_evidence$path)
  altered <- fixture$evidence
  altered$summary$clusters[[1]]$markers[[1]]$avgLog2FC <- 100
  saveRDS(altered, evidence_file, version = 2L)
  expect_error(scAgentKit:::.sc_run_annotation_review_verify(fixture$root, fixture$state), "no longer matches")
  saveRDS(fixture$evidence, evidence_file, version = 2L)
  record_path <- file.path(fixture$root, fixture$state$files$annotation_review$path)
  record <- readRDS(record_path)
  record$details$annotations[[1]]$proposal$confidence <- "high"
  saveRDS(record, record_path, version = 2L)
  expect_error(scAgentKit:::.sc_run_annotation_review_verify(fixture$root, fixture$state), "fingerprint changed")
})

test_that("decision records bind the review and lifecycle preserves a verified audited undo", {
  fixture <- annotation_review_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  state <- fixture$state
  record <- scAgentKit:::.sc_run_annotation_review_view(fixture$root, state)
  expect_true(record$lifecycle$current_proposal)
  expect_false(record$lifecycle$executed)
  expect_false(record$lifecycle$undone)
  expect_identical(record$hash, scAgentKit:::.sc_run_annotation_review_hash(record))
  decision <- scAgentKit:::.sc_run_annotation_review_decision_details(fixture$root, state,
    "fixture reviewer", "Reviewed exact evidence and scope.")
  expect_identical(decision$review_hash, record$hash)
  expect_identical(decision$proposal_hash, state$pending$hash)
  expect_identical(decision$target_column, "fresh_annotation")
  expect_identical(decision$revision_reviewed, state$revision)
  state <- scAgentKit:::.sc_run_event(state, "approved", decision)
  state$approvals[[state$pending$hash]] <- decision
  state$approved <- state$pending; state$pending <- NULL
  state$completed <- "annotation_apply"; state$status <- "complete"; state$stage <- "complete"
  complete <- scAgentKit:::.sc_run_annotation_review_view(fixture$root, state)
  expect_true(complete$lifecycle$executed)
  expect_false(complete$lifecycle$current_proposal)
  expect_length(complete$lifecycle$decisions, 1L)
  state <- scAgentKit:::.sc_run_event(state, "annotation_undone",
    list(decision_id = decision$decision_id, reviewer = "fixture reviewer", reason = "Reconsider labels."))
  state$files$annotation_validated <- NULL; state$files$manual_annotation <- NULL
  state$approved <- NULL; state$completed <- character()
  state$stage <- "annotation_propose"; state$status <- "awaiting_configuration"
  undone <- scAgentKit:::.sc_run_annotation_review_view(fixture$root, state)
  expect_identical(undone$hash, record$hash)
  expect_true(undone$lifecycle$undone)
  expect_false(undone$lifecycle$executed)
  expect_false(undone$lifecycle$current_proposal)
  expect_identical(undone$details$source$kind, "manual")
  missing_audit <- state
  missing_audit$history <- missing_audit$history[-length(missing_audit$history)]
  expect_error(scAgentKit:::.sc_run_annotation_review_view(fixture$root, missing_audit), "matching audited undo")
  expect_error(scAgentKit:::.sc_run_annotation_review_decision_details(fixture$root, state,
    "fixture reviewer", "Cannot approve a historical snapshot."), "No current annotation")
})
