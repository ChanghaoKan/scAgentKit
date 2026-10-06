joint_integration_fixture <- function() {
  set.seed(561)
  genes <- c("ALB", "TTR", "CD3D", "CD3E", paste0("Gene", 5:60))
  counts <- matrix(rpois(3600, 1), 60, dimnames = list(genes, paste0("literal", 1:60)))
  counts[1:2, 1:30] <- counts[1:2, 1:30] + 20L
  counts[3:4, 31:60] <- counts[3:4, 31:60] + 20L
  object <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(counts, sparse = TRUE))
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- log1p(Matrix::Matrix(counts, sparse = TRUE))
  object$seurat_clusters <- rep(c("01", "NA"), each = 30)
  object$old_annotation <- factor(rep(c("prior A", NA_character_), each = 30))
  reference <- data.frame(cell_type = c("DistinctLocalType", "DistinctLocalType", "OtherLocalType"),
    marker = c("ALB", "TTR", "CD3D"), tissue = "blood", species = "human", source = "synthetic test")
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(c("01", "NA"), function(id)
    list(clusterId = id, label = "Unknown", confidence = "low", rationale = "Software control; identity unresolved.", markers = list())))
  list(object = object, reference = reference, proposal = proposal,
       context = list(species = "human", tissue = "blood", notes = "Synthetic software test."))
}

test_that("independent excludes reference candidates while guided discloses dependency", {
  f <- joint_integration_fixture()
  table <- data.frame(cluster = c("01", "01", "NA"), gene = c("ALB", "TTR", "CD3D"),
    avg_log2FC = 2, pct.1 = .8, pct.2 = .1, p_val_adj = .001)
  independent <- scAgentKit:::.sc_run_annotation_evidence(f$object, table, f$context, f$reference)
  guided <- scAgentKit:::.sc_run_annotation_evidence(f$object, table, f$context, f$reference,
    reference_review = list(ai_mode = "guided"))
  one <- scAgentKit:::.sc_run_request("annotation", independent$summary, list(context = f$context))
  two <- scAgentKit:::.sc_run_request("annotation", guided$summary, list(context = f$context))
  expect_false(grepl("DistinctLocalType", one$user_prompt, fixed = TRUE))
  expect_true(grepl("DistinctLocalType", two$user_prompt, fixed = TRUE))
  expect_match(two$system_prompt, "depends on that reference")
  expect_false(grepl("These are independent suggestions", two$system_prompt, fixed = TRUE))
  expect_null(independent$summary$reference_candidates)
  expect_length(guided$summary$reference_candidates, 2)
})

test_that("historical imports verify bytes and exact original cell/cluster scope without a model", {
  f <- joint_integration_fixture(); directory <- tempfile(); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  source <- file.path(directory, "original.rds"); saveRDS(f$object, source)
  response <- file.path(directory, "old-response.json")
  writeLines('{"historical":true,"note":"synthetic saved response"}', response)
  evidence <- list(summary = list(clusters = lapply(c("01", "NA"), function(id)
    list(clusterId = id, cellCount = 30L, markers = list()))), private = list(
      input_cells = data.frame(cell_id = colnames(f$object), cluster = as.character(f$object$seurat_clusters)),
      cluster_column = "seurat_clusters"))
  value <- list(annotations = f$proposal$annotations, response_paths = response,
    source_object_path = source, provider = "saved-test-provider", model = "saved-test-model",
    reference_dependency = "guided")
  imported <- scAgentKit:::.sc_run_annotation_history_import(value, evidence)
  expect_identical(imported$provenance$scope_status, "verified")
  expect_false(imported$provenance$new_request)
  expect_identical(imported$provenance$response_sha256, scAgentKit:::.sc_project_sha_file(response))
  evidence$private$input_cells$cluster[1] <- "NA"
  expect_identical(scAgentKit:::.sc_run_annotation_history_import(value, evidence)$provenance$scope_status, "mismatch")
  value$api_key <- "must reject arbitrary secret field"
  expect_error(scAgentKit:::.sc_run_annotation_history_import(value, evidence), "Unsupported")
  value$api_key <- NULL; writeLines('{broken', response)
  expect_error(scAgentKit:::.sc_run_annotation_history_import(value, evidence), "corrupted")
})

test_that("reference refresh invalidates old whole approval and reuses saved analysis/markers", {
  f <- joint_integration_fixture(); directory <- tempfile(); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  source <- file.path(directory, "source.rds"); saveRDS(f$object, source)
  project <- file.path(directory, "project")
  suppressWarnings(sc_run(source, project, f$context, start_stage = "processed",
    processed_reason = "Synthetic source has verified data layer and literal clusters.",
    reference = f$reference, annotation_proposal = f$proposal, annotation_column = "reviewed_new"))
  original <- sc_run_inspect(project); expect_identical(original$status, "awaiting_review")
  old <- original$review_node
  sc_run_review(project, "approve", kind = "annotation", project_id = old$project_id,
    input_hash = old$input_hash, proposal_hash = old$proposal_hash, review_hash = old$review_hash,
    expected_revision = old$expected_revision, reviewer = "test", reason = "Initial exact whole plan.")
  current <- sc_run_inspect(project)
  before <- readRDS(file.path(project, "state.rds"))$state
  snapshots <- before$files[c("analysis", "markers")]
  bytes <- readBin(file.path(project, "state.rds"), "raw", n = file.info(file.path(project, "state.rds"))$size)
  expect_error(sc_run_set_reference(project, data.frame(wrong = 1), current$project_id,
    current$input_hash, current$revision, "test", "Invalid reference"), "reference|cell_type|marker")
  expect_identical(readBin(file.path(project, "state.rds"), "raw", n = length(bytes)), bytes)
  sc_run_set_reference(project, f$reference, current$project_id, current$input_hash, current$revision,
    reviewer = "test", reason = "Explicit candidate-count correction; old approval must be inactive.",
    reference_review = list(top_n = 1L))
  refreshed <- sc_run_inspect(project)
  expect_identical(refreshed$status, "awaiting_review")
  expect_false(identical(refreshed$annotation_review$hash, original$annotation_review$hash))
  after <- readRDS(file.path(project, "state.rds"))$state
  expect_identical(after$files[c("analysis", "markers")], snapshots)
  expect_null(after$approved)
  expect_error(sc_run_review(project, "approve", kind = "annotation", project_id = old$project_id,
    input_hash = old$input_hash, proposal_hash = old$proposal_hash, review_hash = old$review_hash,
    expected_revision = old$expected_revision, reviewer = "test", reason = "Stale snapshot"), "[Ss]tale|revision|fingerprint|changed")
  node <- refreshed$review_node
  sc_run_review(project, "approve", kind = node$kind, project_id = node$project_id,
    input_hash = node$input_hash, proposal_hash = node$proposal_hash, review_hash = node$review_hash,
    expected_revision = node$expected_revision, reviewer = "test", reason = "Approve rebuilt exact plan.")
  approved <- sc_run_inspect(project)
  sc_run_continue(project, approved$project_id, approved$input_hash, approved$revision)
  final <- sc_run_inspect(project); expect_identical(final$status, "complete")
  out <- readRDS(final$output$seurat)
  summary <- jsonlite::fromJSON(file.path(project, "output", "annotation_evidence_summary.json"), simplifyVector = FALSE)
  expect_identical(summary$review_hash, final$annotation_review$hash)
  expect_null(summary$clusters[[1]]$database$all_candidates)
  expect_identical(colnames(out), colnames(f$object))
  expect_identical(out$old_annotation, f$object$old_annotation)
  expect_identical(SeuratObject::LayerData(out, assay = "RNA", layer = "counts"),
                   SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts"))
  expect_true(all(out$reviewed_new == "Unknown"))
  expect_error(sc_run_set_reference(project, f$reference, final$project_id, final$input_hash,
    final$revision, "test", "Too late"), "before annotation")
})
