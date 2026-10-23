full_review_input <- function() {
  counts <- Matrix::Matrix(matrix(2L, 30L, 24L,
    dimnames = list(c("MT-CO1", paste0("GENE", 2:30)), paste0("cell", 1:24))), sparse = TRUE)
  Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
}
full_review_qc_reply <- function(...) .sc_project_json(list(schema = "scagentkit.qc.rules.v1",
  rationale = "Synthetic recovery control; retain cells for review.", risks = list(), remove_if = "any", rules = list()))

test_that("public failure rollback retains ordinary receipts for explicit retry", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  failed <- sc_run(full_review_input(), root, provider = "mock", chat_fn = function(...) "invalid",
    context = list(species = "human", tissue = "synthetic"))
  expect_identical(failed$status, "failed")
  expect_length(grep("^provider_request_", names(.sc_run_load(root)$files)), 1L)
  resumed <- sc_run_resume(root, chat_fn = full_review_qc_reply, retry = TRUE)
  expect_identical(resumed$status, "awaiting_review")
  expect_identical(resumed$pending$kind, "qc")
})

test_that("invoice reconciliation preserves the currently reviewed scientific proposal", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  provider <- list(name = "offline-external-fixture", model = "fixture", external = TRUE)
  first <- sc_run(full_review_input(), root, provider = provider, chat_fn = full_review_qc_reply,
    context = list(species = "human", tissue = "synthetic"), review = list(allow_external = TRUE))
  expect_identical(first$pending$kind, "external_transfer")
  sc_run_approve(root, first$pending$hash, "reviewer", "Approve the exact synthetic transfer.")
  reviewed <- sc_run_resume(root, chat_fn = full_review_qc_reply)
  expect_identical(reviewed$pending$kind, "qc")
  ledger <- .sc_run_provider_read(file.path(root, "provider", "ledger.json"))
  sc_run_provider_reconcile(root, tail(ledger$entries, 1L)[[1L]]$request_hash, 1,
    "reviewer", "Synthetic independently confirmed invoice.")
  inspected <- sc_run_inspect(root)
  expect_identical(inspected$pending$hash, reviewed$pending$hash)
  expect_identical(inspected$status, "awaiting_review")
})

test_that("reference refresh detaches old ReAct authority and permits a fresh manual proposal", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  object <- SeuratObject::pbmc_small
  object$seurat_clusters <- as.character(SeuratObject::Idents(object))
  calls <- 0L
  baseline <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    evidence <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)$evidence
    ids <- vapply(evidence$clusters, `[[`, "", "clusterId")
    rows <- lapply(ids, function(id) list(clusterId = id, label = "Unknown", confidence = "low",
      rationale = "Synthetic control; identity remains unresolved.", markers = list()))
    risks <- lapply(ids, function(id) {
      value <- .sc_run_react_unassessed_risks(id)
      value$fields <- lapply(value$fields, function(field) {field$source <- "model"; field})
      value
    })
    .sc_project_json(list(schema = "scagentkit.annotation-draft.v1",
      proposal = list(schema = "scagentkit.annotation.v1", annotations = rows), risk_flags = risks))
  }
  started <- suppressWarnings(sc_run(object, root, provider = "mock", chat_fn = baseline,
    context = list(species = "human", tissue = "blood"), start_stage = "processed",
    processed_reason = "Bundled software control, without biological validation.", react = list(mode = "all")))
  expect_identical(started$status, "awaiting_review")
  before <- sc_run_inspect(root); saved <- .sc_run_load(root)
  old_run <- saved$files$annotation_react_run
  refreshed <- sc_run_set_reference(root, data.frame(cell_type = "Local candidate", marker = "CD3D",
    species = "human", tissue = "blood"), before$project_id, before$input_hash, before$revision,
    "reviewer", "Refresh explicit local reference evidence.")
  expect_identical(refreshed$status, "awaiting_configuration")
  after <- .sc_run_load(root)
  expect_false(any(c("annotation_react_run", "annotation_react_citations", "annotation_baseline_risks") %in% names(after$files)))
  expect_identical(.sc_project_sha_file(file.path(root, old_run$path)), old_run$sha256)
  evidence <- .sc_run_get(root, after, "annotation_evidence")
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(evidence$summary$clusters,
    function(row) list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
      rationale = "Fresh local evidence reviewed; identity remains unresolved.", markers = list())))
  expect_identical(sc_run_propose(root, proposal, "reviewer", "New manual scope.")$status, "awaiting_review")
  expect_equal(calls, 1L)
})
