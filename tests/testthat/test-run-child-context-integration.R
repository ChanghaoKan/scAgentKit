# Fresh, public synthetic software controls. Every parent annotation and child
# strategy is approved through the actual coordinator; no saved project, cell
# identity, approval or provider response is fabricated for these checks.
child_context_integration_fixture <- function() {
  set.seed(1729L)
  cells <- c("1", "001", "NA", "cell space", paste0("freshContextCell", 5:96))
  counts <- matrix(stats::rpois(160L * 96L, 2), nrow = 160L,
    dimnames = list(c("MT-CO1", paste0("ContextGene", 2:160)), cells))
  for (program in seq_len(8L)) {
    genes <- seq.int((program - 1L) * 12L + 2L, program * 12L + 1L)
    chosen <- seq.int((program - 1L) * 12L + 1L, program * 12L)
    counts[genes, chosen] <- counts[genes, chosen] + 16L
  }
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE),
    min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <-
    Matrix::Matrix(counts * 2L, sparse = TRUE)
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  object$parent_cluster <- factor(rep(c("01", "1", "NA", "cluster space"), each = 24L),
    levels = c("NA", "1", "01", "cluster space", "unused"))
  object$old_annotation <- factor(rep(c("prior label", NA_character_), 48L),
    levels = c("unused annotation", "prior label"))
  object$sample <- rep(c("sample A", "sample B", "sample C", "sample D"), each = 24L)
  object$capture <- object$sample
  object$condition <- rep(c("treated", "control"), 48L)
  object$integer_metadata <- seq_len(96L)
  object$logical_metadata <- rep(c(TRUE, FALSE, NA), 32L)
  object$private_note <- "PRIVATE_PER_CELL_CONTEXT_SENTINEL"
  object
}

child_context_integration_plan <- function() list(schema = "scagentkit.strategy.v1",
  rationale = "A fresh manually reviewed synthetic child strategy.",
  risks = list("Expression programs are software controls, not biological validation."),
  inferences = list(), qc = list(schema = "scagentkit.qc.v1",
    rationale = "Retain the frozen selected raw-count scope.", risks = list("No second QC filter requested."),
    filters = list(list(op = "range", metric = "nCount", min = 0L))),
  analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
    nfeatures = 80L, npcs = 8L, seed = 1729L),
  pcs = list(method = "fixed", ndim = 6L),
  batch = list(method = "none", reason = "No inherited embedding or batch correction."),
  clustering = list(resolution = 1, diagnostic_resolutions = c(.5, .8, 1.2)),
  umap = list(run = FALSE, n_neighbors = 20L))

child_context_integration_network <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$factory <- 0L; calls$http <- 0L
  factory <- function(...) {
    calls$factory <- calls$factory + 1L
    stop("Fresh child context QA forbids remote provider factories.")
  }
  testthat::local_mocked_bindings(chat_deepseek = factory, chat_grok = factory,
    .package = "agentomicsCore", .env = env)
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls$http <- calls$http + 1L; stop("Fresh child context QA forbids HTTP dispatch.")
  }, .package = "httr2", .env = env)
  calls
}

child_context_integration_files <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE))
  files <- files[!dir.exists(files)]
  stats::setNames(vapply(files, scAgentKit:::.sc_project_sha_file, character(1)),
    substring(files, nchar(root) + 2L))
}

child_context_integration_decide <- function(root, action = "approve", node = sc_run_inspect(root)$review_node) {
  sc_run_review(root, action, node$kind, node$project_id, node$input_hash,
    node$proposal_hash, node$review_hash, node$expected_revision,
    reviewer = "PRIVATE_REVIEWER_CONTEXT_SENTINEL", reason = "Review the exact synthetic evidence and typed proposal.")
}

child_context_integration_continue <- function(root) {
  snapshot <- sc_run_inspect(root)
  suppressWarnings(sc_run_continue(root, snapshot$project_id, snapshot$input_hash, snapshot$revision))
}

child_context_integration_proposal <- function(evidence, labels = NULL) {
  list(schema = "scagentkit.annotation.v1", annotations = lapply(evidence$clusters, function(row) {
    label <- if (is.null(labels)) "Unknown" else labels[[row$clusterId]]
    if (is.null(label)) label <- "Unknown"
    genes <- if (identical(label, "Unknown")) list() else {
      stopifnot(length(row$markers) > 0L)
      list(row$markers[[1L]]$gene)
    }
    list(clusterId = row$clusterId, label = label,
      confidence = if (identical(label, "Unknown")) "low" else "medium",
      rationale = if (identical(label, "Unknown")) "Unresolved synthetic expression identity." else
        "A supplied current marker supports this synthetic software-control label.", markers = genes)
  }))
}

child_context_integration_parent <- function(work, labels = c("01" = "Parent lineage A", "1" = "Unknown",
                                                            "NA" = "Parent lineage B", "cluster space" = "Unreviewed")) {
  root <- file.path(work, "parent")
  source <- child_context_integration_fixture()
  unknown <- list(schema = "scagentkit.annotation.v1", annotations = lapply(
    unique(as.character(source$parent_cluster)), function(id) list(clusterId = id,
      label = "Unknown", confidence = "low", rationale = "Initial synthetic uncertainty.", markers = list())))
  initial <- suppressWarnings(sc_run(source, root,
    context = list(species = "human", tissue = "synthetic parent tissue",
      columns = list(sample = "sample", capture = "capture", condition = "condition"),
      research_goal = "Fresh software controls for conditional child context.",
      notes = "Planted expression programs establish no biological identity."),
    start_stage = "processed", processed_reason = "Fresh normalized synthetic counts and literal manually assigned parent clusters.",
    cluster_column = "parent_cluster", annotation_column = "parent_reviewed_type",
    provider = list(name = "mock", model = "context-software-control-v1", external = TRUE, reservation_usd = .01),
    budget = .05, review = list(allow_external = TRUE), annotation_proposal = unknown))
  stopifnot(identical(initial$status, "awaiting_review"))
  proposed <- child_context_integration_proposal(sc_run_inspect(root)$evidence, labels)
  sc_run_propose(root, proposed, "PRIVATE_REVIEWER_CONTEXT_SENTINEL", "Review supplied current parent marker evidence.")
  child_context_integration_decide(root)
  completed <- child_context_integration_continue(root)
  stopifnot(identical(completed$status, "complete"))
  list(root = root, state = scAgentKit:::.sc_run_load(root),
    object = readRDS(completed$output$seurat), source = source,
    review = sc_run_inspect(root)$review_node)
}

child_context_integration_create <- function(parent, root, clusters = "01", request_id = "fresh-child", inherit_model = TRUE) {
  scope <- sc_run_subcluster_scope(parent$root)
  sc_run_subcluster(parent$root, root, clusters = clusters,
    parent_scope_hash = scope$parent_scope_hash, expected_parent_revision = parent$state$revision,
    strategy_proposal = child_context_integration_plan(), inherit_model = inherit_model,
    reviewer = "PRIVATE_REVIEWER_CONTEXT_SENTINEL", reason = "Select literal parent clusters for a fresh raw-count child.",
    request_id = request_id)
}

child_context_integration_annotation_boundary <- function(root) {
  child_context_integration_decide(root)
  paused <- child_context_integration_continue(root)
  stopifnot(identical(paused$status, "awaiting_configuration"), identical(paused$stage, "annotation_propose"))
  paused
}

child_context_integration_set <- function(root, context, request_id, snapshot = sc_run_inspect(root), ...) {
  do.call(sc_run_set_child_context, c(list(project_dir = root, context = context,
    project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    expected_revision = snapshot$revision, expected_context_hash = snapshot$child_context$hash,
    reviewer = "PRIVATE_REVIEWER_CONTEXT_SENTINEL", reason = "Correct soft context after reviewing current child evidence.",
    request_id = request_id), list(...)))
}

child_context_integration_suggest <- function(root, action = "preview", view = NULL) {
  if (action == "preview") return(sc_run_suggest(root, "preview", simulate = TRUE))
  if (is.null(view)) view <- child_context_integration_suggest(root)
  sc_run_suggest(root, action, project_id = view$project_id, input_hash = view$input_hash,
    expected_revision = view$revision, suggestion_hash = view$suggestion_hash,
    reviewer = "PRIVATE_REVIEWER_CONTEXT_SENTINEL", reason = "Review this exact offline mock payload.", simulate = TRUE)
}

child_context_integration_expect_private <- function(text, root) {
  for (literal in c("PRIVATE_PER_CELL_CONTEXT_SENTINEL", "PRIVATE_REVIEWER_CONTEXT_SENTINEL",
                    "freshContextCell", "cell space", root))
    expect_false(grepl(literal, text, fixed = TRUE), info = paste("Private value leaked:", literal))
  expect_false(grepl('"(selected_cells|cell_ids|cell_id|parent_project|reviewer)"[[:space:]]*:', text))
}

test_that("fresh child context freezes aggregate approved parent identity without inheriting label authority", {
  network <- child_context_integration_network()
  work <- tempfile("fresh-child-context-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- child_context_integration_parent(work, labels = c("01" = "Parent lineage A", "1" = "Unknown",
    "NA" = "Parent lineage A", "cluster space" = "Unreviewed"))
  source_bytes <- serialize(parent$source, NULL, version = 2L)
  protected_parent <- child_context_integration_files(parent$root)
  child <- file.path(work, "child")
  created <- child_context_integration_create(parent, child, c("01", "NA"), inherit_model = FALSE)
  expect_identical(created$status, "awaiting_review")
  state <- scAgentKit:::.sc_run_load(child)
  context <- state$config$annotation_context
  expect_identical(sc_run_inspect(child)$child_context, context)
  expect_identical(context$schema, "scagentkit.child-context.v1")
  expect_identical(context$generation, 0L)
  expect_null(context$previous_hash)
  expect_match(context$hash, "^[a-f0-9]{64}$")
  expect_identical(context$effective, list(enabled = TRUE, lineage_hint = NULL,
    identity_status = "labeled", tissue = "synthetic parent tissue", notes = NULL))
  snapshot <- context$parent_snapshot
  expect_identical(snapshot$schema, "scagentkit.child-parent-context.v1")
  expect_identical(snapshot$identity_status, "labeled")
  expect_identical(snapshot$species, "human")
  expect_identical(snapshot$tissue, "synthetic parent tissue")
  expect_identical(snapshot$source$project_id, parent$state$project_id)
  expect_identical(snapshot$source$revision, parent$state$revision)
  expect_identical(snapshot$source$input_hash, parent$state$input_hash)
  expect_identical(snapshot$source$output_hash, state$config$subcluster_origin$parent$output_sha256)
  expect_identical(snapshot$source$scope_hash, state$config$subcluster_origin$scope_hash)
  expect_identical(snapshot$source$review_hash, parent$review$review_hash)
  expect_identical(snapshot$source$decision_id, parent$review$decision_id)
  expect_identical(snapshot$source$annotation_column, "parent_reviewed_type")
  expect_identical(snapshot$source$source_kind, "manual")
  expect_identical(snapshot$source$scientific_result, parent$state$output$scientific_result)
  expect_length(snapshot$scope, 2L); expect_length(snapshot$annotations, 2L)
  expect_identical(snapshot$scope[[1L]], list(parentClusterId = "01", cellCount = 24L))
  expect_identical(snapshot$scope[[2L]], list(parentClusterId = "NA", cellCount = 24L))
  row <- snapshot$annotations[[1L]]
  expect_identical(row$parentClusterId, "01"); expect_identical(row$cellCount, 24L)
  expect_identical(row$labels, list("Parent lineage A"))
  expect_identical(row$review_status, "approved_executed")
  expect_identical(row$identity_status, "labeled")
  expect_identical(row$confidence, "medium")
  selected <- colnames(parent$object)[as.character(parent$object$parent_cluster) %in% c("01", "NA")]
  expect_identical(selected[1:4], c("1", "001", "NA", "cell space"))
  input <- scAgentKit:::.sc_run_get(child, state, "input")
  expect_identical(colnames(input), selected)
  expect_identical(SeuratObject::LayerData(input, assay = "RNA", layer = "counts"),
    SeuratObject::LayerData(parent$object, assay = "RNA", layer = "counts")[rownames(input), selected, drop = FALSE])
  expect_identical(SeuratObject::Layers(input[["RNA"]]), "counts")
  expect_length(input@graphs, 0L); expect_length(input@reductions, 0L)
  expect_identical(unique(as.character(SeuratObject::Idents(input))), "unassigned")
  for (name in names(parent$object[[]]))
    expect_identical(input[[]][[name]], parent$object[[]][selected, name])
  child_context_integration_expect_private(scAgentKit:::.sc_project_json(context), child)
  child_context_integration_annotation_boundary(child)
  evidence <- sc_run_inspect(child)$evidence
  expect_identical(evidence$child_context, context)
  expect_identical(evidence$context$tissue, "synthetic parent tissue")
  labels <- stats::setNames(rep("Outside parent lineage", length(evidence$clusters)),
    vapply(evidence$clusters, `[[`, character(1), "clusterId"))
  proposal <- child_context_integration_proposal(evidence, labels)
  expect_false("Outside parent lineage" %in% unlist(row$labels, use.names = FALSE))
  expect_no_error(sc_run_propose(child, proposal, "offline QA", "Use only this child's actual supplied marker genes."))
  child_context_integration_decide(child)
  completed <- child_context_integration_continue(child)
  expect_identical(completed$status, "complete")
  out <- readRDS(completed$output$seurat)
  expect_identical(colnames(out), selected)
  expect_true(all(out$sc_subtype == "Outside parent lineage"))
  expect_true("pca" %in% names(out@reductions))
  for (name in names(parent$object[[]]))
    expect_identical(out[[]][[name]], parent$object[[]][selected, name])
  state <- scAgentKit:::.sc_run_load(child)
  inspected_files <- child_context_integration_files(child)
  inspection <- sc_run_inspect(child)
  basis <- scAgentKit:::.sc_run_get(child, state, "strategy_basis")
  pca <- basis@misc$strategy_execution$basis$pca
  diagnostic <- inspection$computed_diagnostics
  expect_identical(diagnostic$stage_counts$schema, "scagentkit.stage-counts.v1")
  stage_files <- c(input = "input", qc = "qc_object", analysis = "analysis",
    output = "output:output/seurat.rds")
  for (stage in names(stage_files)) {
    count <- diagnostic$stage_counts[[stage]]
    expect_identical(count$status, "saved", info = stage)
    expect_equal(count$cells, 48L, info = stage)
    expect_equal(count$cells, ncol(scAgentKit:::.sc_run_get(child, state, stage_files[[stage]])), info = stage)
    expect_identical(count$artifact_sha256, state$files[[stage_files[[stage]]]]$sha256, info = stage)
  }
  expect_identical(diagnostic$stage_counts$selection$status, "unavailable")
  expect_null(diagnostic$stage_counts$selection$cells)
  expect_null(diagnostic$stage_counts$selection$artifact_sha256)
  expect_identical(diagnostic$stage_counts$prefilter$status, "unavailable")
  expect_null(diagnostic$stage_counts$prefilter$original_cells)
  expect_identical(diagnostic$all_pc_variance$status, "saved")
  expect_identical(diagnostic$all_pc_variance$basis_artifact_sha256, state$files$strategy_basis$sha256)
  expect_identical(diagnostic$all_pc_variance$basis_artifact_sha256,
    scAgentKit:::.sc_project_sha_file(file.path(child, state$files$strategy_basis$path)))
  for (field in c("available_pcs", "fraction_per_pc", "cumulative_fraction", "denominator", "interpretation"))
    expect_identical(diagnostic$all_pc_variance[[field]], pca[[field]], info = field)
  expect_equal(length(diagnostic$all_pc_variance$fraction_per_pc), 8L)
  expect_identical(diagnostic$pc_candidates, pca$top50_candidates)
  cluster <- out@misc$strategy_execution$cluster
  candidate_fields <- c("resolution", "chosen", "n_clusters", "min_cluster_size",
    "max_cluster_size", "cluster_sizes", "ari_vs_chosen", "ari_vs_previous")
  expect_identical(diagnostic$cluster_candidates$analysis_artifact_sha256, state$files$analysis$sha256)
  expect_identical(diagnostic$cluster_candidates$basis_artifact_sha256, state$files$strategy_basis$sha256)
  expect_identical(diagnostic$cluster_candidates$chosen_resolution, cluster$resolution)
  expect_identical(diagnostic$cluster_candidates$candidates,
    lapply(cluster$candidates, function(row) row[candidate_fields]))
  expect_equal(vapply(diagnostic$cluster_candidates$candidates, `[[`, numeric(1), "resolution"), c(.5, .8, 1, 1.2))
  expect_null(diagnostic$cluster_candidates$diagnostic_assignments)
  expect_true(all(vapply(diagnostic$cluster_candidates$candidates,
    function(row) identical(names(row), candidate_fields), logical(1))))
  child_context_integration_expect_private(scAgentKit:::.sc_project_json(diagnostic), child)
  expect_identical(child_context_integration_files(child), inspected_files)
  expect_identical(scAgentKit:::.sc_run_load(child), state)
  for (stage in c("qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_apply"))
    expect_equal(sum(vapply(state$history, function(event)
      identical(event$action, "executed") && identical(event$details$stage, stage), logical(1))), 1L)
  expect_identical(child_context_integration_files(parent$root), protected_parent)
  expect_identical(serialize(parent$source, NULL, version = 2L), source_bytes)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("automatic parent context distinguishes Unknown and mixed literal cluster selections", {
  network <- child_context_integration_network()
  work <- tempfile("fresh-child-context-status-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- child_context_integration_parent(work)
  protected <- child_context_integration_files(parent$root)
  cases <- list(unknown = list(clusters = "1", status = "unknown"),
    mixed = list(clusters = c("01", "1"), status = "mixed"),
    different_labels = list(clusters = c("01", "NA"), status = "mixed"),
    unreviewed = list(clusters = "cluster space", status = "unreviewed"))
  for (name in names(cases)) {
    root <- file.path(work, name); one <- cases[[name]]
    child_context_integration_create(parent, root, one$clusters, paste0("status-", name))
    context <- sc_run_inspect(root)$child_context
    expect_identical(context$effective$identity_status, one$status)
    expect_identical(context$parent_snapshot$identity_status, one$status)
    expect_identical(vapply(context$parent_snapshot$scope, `[[`, character(1), "parentClusterId"), one$clusters)
    expect_true(all(vapply(context$parent_snapshot$scope, function(row) identical(row$cellCount, 24L), logical(1))))
    expect_true(all(vapply(context$parent_snapshot$annotations,
      function(row) identical(row$review_status, "approved_executed"), logical(1))))
  }
  unknown <- sc_run_inspect(file.path(work, "unknown"))$child_context
  expect_identical(unknown$parent_snapshot$annotations[[1L]]$labels, list("Unknown"))
  expect_identical(unknown$parent_snapshot$annotations[[1L]]$identity_status, "unknown")
  expect_identical(child_context_integration_files(parent$root), protected)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("child context corrections invalidate annotation authority while preserving science and ledger artifacts", {
  network <- child_context_integration_network()
  work <- tempfile("fresh-child-context-correction-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- child_context_integration_parent(work)
  protected_parent <- child_context_integration_files(parent$root)
  child <- file.path(work, "child")
  child_context_integration_create(parent, child, c("01", "1"))
  child_context_integration_annotation_boundary(child)
  before <- scAgentKit:::.sc_run_load(child)
  original <- sc_run_inspect(child)
  preview_a <- child_context_integration_suggest(child)
  child_context_integration_expect_private(preview_a$preview$user_prompt, child)
  approved <- child_context_integration_suggest(child, "approve", preview_a)
  candidate <- child_context_integration_suggest(child, "request", approved)
  expect_identical(candidate$status, "candidate")
  expect_identical(candidate$response$cost_usd, 0)
  adopted <- child_context_integration_suggest(child, "adopt", candidate)
  expect_identical(adopted$status, "awaiting_review")
  expect_false(is.null(adopted$review_node))
  state_before <- scAgentKit:::.sc_run_load(child)
  expect_false(is.null(state_before$files$manual_annotation))
  expect_false(is.null(state_before$files$annotation_validated))
  expect_false(is.null(state_before$files$annotation_review))
  expect_false(is.null(state_before$files$annotation_suggestion_response))
  expect_false(is.null(state_before$files$annotation_suggestion_adoption))
  expect_true(length(state_before$suggestion_transfer_hashes) > 0L)
  files_before <- child_context_integration_files(child)
  ledger <- files_before[startsWith(names(files_before), "provider/")]
  expect_true("provider/ledger.json" %in% names(ledger))
  stale_node <- adopted$review_node
  patch <- list(lineage_hint = "Corrected soft lineage", identity_status = "unreviewed",
    tissue = "synthetic corrected tissue", notes = "Review child markers without forcing a parent label.")
  corrected <- child_context_integration_set(child, patch, "context-B", adopted)
  expect_identical(corrected$status, "awaiting_configuration")
  expect_identical(corrected$stage, "annotation_propose")
  expect_null(corrected$pending); expect_null(corrected$review_node)
  after <- scAgentKit:::.sc_run_load(child)
  expect_identical(after$config$annotation_context$generation, 1L)
  expect_identical(after$config$annotation_context$previous_hash, original$child_context$hash)
  expect_identical(after$config$annotation_context$parent_snapshot, original$child_context$parent_snapshot)
  expect_identical(after$config$annotation_context$effective$lineage_hint, patch$lineage_hint)
  expect_identical(after$config$annotation_context$effective$identity_status, patch$identity_status)
  expect_identical(after$config$annotation_context$effective$tissue, patch$tissue)
  expect_identical(after$config$annotation_context$effective$notes, patch$notes)
  expect_identical(after$config_hash, scAgentKit:::.sc_run_hash(after$config))
  expect_false(identical(after$config_hash, state_before$config_hash))
  expect_identical(after$config$context, before$config$context)
  expect_identical(after$config$subcluster_creation, before$config$subcluster_creation)
  expect_identical(after$config$subcluster_origin, before$config$subcluster_origin)
  expect_identical(after$config$analysis, before$config$analysis)
  expect_identical(after$config$markers, before$config$markers)
  expect_identical(after$approvals, state_before$approvals)
  expect_identical(after$completed, state_before$completed)
  expect_identical(after$history[seq_along(state_before$history)], state_before$history)
  expect_length(after$transfer_hashes, 0L); expect_length(after$suggestion_transfer_hashes, 0L)
  expect_null(after$suggestion); expect_null(after$pending); expect_null(after$approved)
  cleared <- c("annotation_request", "annotation_response", "manual_annotation", "annotation_validated",
    "annotation_review", "annotation_suggestion_response", "annotation_suggestion_adoption")
  for (name in cleared) expect_null(after$files[[name]], info = name)
  protected_names <- setdiff(names(state_before$files), c(cleared, "annotation_evidence", "child_annotation_context"))
  expect_identical(after$files[protected_names], state_before$files[protected_names])
  # Invalidating current pointers does not delete prior immutable artifacts.
  files_after <- child_context_integration_files(child)
  immutable <- setdiff(names(files_before), c("state.rds", "status.json", "decision_history.json", "proposal.json"))
  expect_identical(files_after[immutable], files_before[immutable])
  expect_identical(files_after[names(ledger)], ledger)
  expect_false(identical(after$files$annotation_evidence$sha256, state_before$files$annotation_evidence$sha256))
  expect_identical(scAgentKit:::.sc_run_get(child, after, "annotation_evidence")$private$input_cells,
    scAgentKit:::.sc_run_get(child, state_before, "annotation_evidence")$private$input_cells)
  corrected_evidence <- sc_run_inspect(child)$evidence
  expect_identical(corrected_evidence$context$tissue, patch$tissue)
  expect_identical(corrected_evidence$child_context, corrected$child_context)
  preview_b <- child_context_integration_suggest(child)
  expect_false(preview_b$can_request); expect_true(preview_b$can_approve)
  expect_false(identical(preview_b$preview$request_hash, preview_a$preview$request_hash))
  outgoing <- jsonlite::fromJSON(preview_b$preview$user_prompt, simplifyVector = FALSE)
  expect_identical(outgoing$evidence$child_context$generation, 1L)
  expect_identical(outgoing$evidence$context$tissue, patch$tissue)
  child_context_integration_expect_private(preview_b$preview$user_prompt, child)
  repeated <- child_context_integration_set(child, patch, "context-B", adopted)
  expect_identical(repeated$revision, corrected$revision)
  expect_identical(child_context_integration_files(child), files_after)
  changed_payload <- patch; changed_payload$notes <- "A different correction payload."
  expect_error(child_context_integration_set(child, changed_payload, "context-B", adopted), "request|payload|reus|different")
  expect_identical(child_context_integration_files(child), files_after)
  expect_error(child_context_integration_decide(child, node = stale_node), "[Ss]tale|review|proposal")
  expect_identical(child_context_integration_files(child), files_after)
  expect_error(child_context_integration_suggest(child, "request", candidate), "revision|[Ss]tale|binding")
  expect_identical(child_context_integration_files(child), files_after)
  # A -> B -> A has the same effective fields but fresh monotonic generation.
  restored <- child_context_integration_set(child, original$child_context$effective, "context-A-again")
  expect_identical(restored$child_context$effective, original$child_context$effective)
  expect_identical(restored$child_context$generation, 2L)
  expect_identical(restored$child_context$previous_hash, corrected$child_context$hash)
  preview_a_again <- child_context_integration_suggest(child)
  expect_false(identical(preview_a_again$preview$request_hash, preview_a$preview$request_hash))
  expect_false(identical(preview_a_again$preview$request_hash, preview_b$preview$request_hash))
  expect_identical(child_context_integration_files(child)[names(ledger)], ledger)
  expect_identical(child_context_integration_files(parent$root), protected_parent)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("context corrections accept stopped annotation stages and reject foreign stale locked or executed scope", {
  network <- child_context_integration_network()
  work <- tempfile("fresh-child-context-boundary-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- child_context_integration_parent(work)
  child <- file.path(work, "child")
  child_context_integration_create(parent, child, inherit_model = FALSE)
  strategy <- sc_run_inspect(child)
  protected <- child_context_integration_files(child)
  expect_error(child_context_integration_set(child, list(notes = "Too early."), "context-strategy"), "annotation|stage|bound|stopped")
  expect_identical(child_context_integration_files(child), protected)
  parent_binding <- sc_run_inspect(parent$root)
  parent_binding$child_context <- list(hash = strategy$child_context$hash)
  expect_error(child_context_integration_set(parent$root, list(notes = "Not a child."), "context-parent", parent_binding),
    "child|scoped|subcluster")
  child_context_integration_annotation_boundary(child)
  initial <- sc_run_inspect(child)
  protected <- child_context_integration_files(child)
  for (field in c("project_id", "input_hash", "revision")) {
    bad <- initial
    bad[[field]] <- switch(field, project_id = "foreign-child-project", input_hash = strrep("f", 64L), revision = initial$revision - 1L)
    expect_error(child_context_integration_set(child, list(notes = "Rejected binding."), paste0("bad-", field), bad),
      "[Ff]oreign|input|revision|[Ss]tale")
    expect_identical(child_context_integration_files(child), protected)
  }
  bad <- initial; bad$child_context$hash <- strrep("e", 64L)
  expect_error(child_context_integration_set(child, list(notes = "Rejected hash."), "bad-context-hash", bad), "context|hash|[Ss]tale")
  expect_identical(child_context_integration_files(child), protected)
  owner <- scAgentKit:::.sc_run_lock(child)
  locked <- child_context_integration_files(child)
  expect_error(child_context_integration_set(child, list(notes = "Locked correction."), "locked-context", initial), "locked")
  expect_identical(child_context_integration_files(child), locked)
  scAgentKit:::.sc_run_release(child, owner)
  expect_identical(child_context_integration_files(child), protected)
  invalid <- list(list(enabled = NA), list(enabled = "true"), list(identity_status = "certain"),
    list(lineage_hint = c("A", "B")), list(tissue = 123L), list(notes = list("R text")),
    list(parent_snapshot = list()), list(generation = 99L), list(provider = "deepseek"))
  for (index in seq_along(invalid)) {
    expect_error(child_context_integration_set(child, invalid[[index]], paste0("invalid-", index), initial),
      "context|enabled|identity|lineage|tissue|notes|[Uu]nsupported|field|scalar|logical|character|named|object")
    expect_identical(child_context_integration_files(child), protected)
  }
  changed <- child_context_integration_set(child, list(enabled = FALSE), "disable-context", initial)
  expect_identical(changed$child_context$effective$enabled, FALSE)
  expect_identical(changed$child_context$generation, 1L)
  unchanged_effective <- child_context_integration_set(child, list(enabled = FALSE), "disable-context-again")
  expect_identical(unchanged_effective$child_context$effective, changed$child_context$effective)
  expect_identical(unchanged_effective$child_context$generation, 2L)
  expect_false(identical(unchanged_effective$child_context$hash, changed$child_context$hash))
  sc_run_propose(child, child_context_integration_proposal(sc_run_inspect(child)$evidence), "offline QA", "Explicit Unknown requires no invented markers.")
  waiting <- sc_run_inspect(child)
  expect_identical(waiting$status, "awaiting_review")
  changed <- child_context_integration_set(child, list(enabled = TRUE, notes = "Revise a pending annotation."), "pending-context")
  expect_null(changed$pending)
  sc_run_propose(child, child_context_integration_proposal(sc_run_inspect(child)$evidence), "offline QA", "Independent Unknown proposal.")
  child_context_integration_decide(child, "reject")
  expect_identical(sc_run_inspect(child)$status, "rejected")
  changed <- child_context_integration_set(child, list(notes = "Revise a rejected annotation."), "rejected-context")
  expect_identical(changed$status, "awaiting_configuration")
  sc_run_propose(child, child_context_integration_proposal(sc_run_inspect(child)$evidence), "offline QA", "Fresh unresolved annotation.")
  approved <- child_context_integration_decide(child)
  expect_identical(approved$stage, "annotation_apply")
  expect_identical(approved$status, "ready")
  old <- approved$review_node
  changed <- child_context_integration_set(child, list(notes = "Correct an approved but unexecuted annotation."), "approved-context", approved)
  expect_identical(changed$stage, "annotation_propose")
  expect_null(changed$pending)
  protected <- child_context_integration_files(child)
  expect_error(child_context_integration_decide(child, node = old), "[Ss]tale|review|proposal")
  expect_identical(child_context_integration_files(child), protected)
  sc_run_propose(child, child_context_integration_proposal(sc_run_inspect(child)$evidence), "offline QA", "Final explicit Unknown.")
  child_context_integration_decide(child)
  completed <- child_context_integration_continue(child)
  expect_identical(completed$status, "complete")
  expect_true(all(readRDS(completed$output$seurat)$sc_subtype == "Unknown"))
  protected <- child_context_integration_files(child)
  expect_error(child_context_integration_set(child, list(notes = "Executed annotation cannot be corrected."), "executed-context"),
    "execut|complete|annotation|stage|stopped")
  expect_identical(child_context_integration_files(child), protected)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("context crash recovery keeps prior pointers and an uncertain provider hold without duplicate generations", {
  network <- child_context_integration_network()
  work <- tempfile("fresh-child-context-crash-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  withr::local_options(scAgentKit.run_crash = NULL)
  parent <- child_context_integration_parent(work)
  protected_parent <- child_context_integration_files(parent$root)
  child <- file.path(work, "child")
  child_context_integration_create(parent, child, c("01", "1"))
  child_context_integration_annotation_boundary(child)
  preview <- sc_run_suggest(child, "preview", simulate = FALSE)
  approved <- sc_run_suggest(child, "approve", project_id = preview$project_id,
    input_hash = preview$input_hash, expected_revision = preview$revision,
    suggestion_hash = preview$suggestion_hash, reviewer = "offline QA",
    reason = "Approve an exact offline callback software control.", simulate = FALSE)
  callbacks <- 0L
  held <- sc_run_suggest(child, "request", project_id = approved$project_id,
    input_hash = approved$input_hash, expected_revision = approved$revision,
    suggestion_hash = approved$suggestion_hash, reviewer = "offline QA",
    reason = "Exercise uncertain accounting with no remote dispatch.", simulate = FALSE,
    chat_fn = function(...) {
      callbacks <<- callbacks + 1L
      stop("An artificial offline callback error; no remote connection exists.")
    })
  expect_identical(callbacks, 1L)
  expect_identical(held$response$status, "delivery_uncertain")
  expect_equal(held$preview$held_usd, .01)
  ledger <- child_context_integration_files(child)
  ledger <- ledger[startsWith(names(ledger), "provider/")]
  expect_true("provider/ledger.json" %in% names(ledger))
  before <- sc_run_inspect(child)
  state_before <- scAgentKit:::.sc_run_load(child)
  journal_sha <- scAgentKit:::.sc_project_sha_file(file.path(child, "state.rds"))
  patch <- list(notes = "Retry safely after precommit context artifact publication.")
  options(scAgentKit.run_crash = "child_context:artifacts")
  expect_error(child_context_integration_set(child, patch, "context-crash-artifacts", before),
    "Injected crash at child_context:artifacts", fixed = TRUE)
  options(scAgentKit.run_crash = NULL)
  expect_identical(scAgentKit:::.sc_project_sha_file(file.path(child, "state.rds")), journal_sha)
  stopped <- scAgentKit:::.sc_run_load(child)
  expect_identical(stopped$config$annotation_context, state_before$config$annotation_context)
  expect_identical(stopped$files, state_before$files)
  expect_identical(stopped$history, state_before$history)
  expect_false(dir.exists(file.path(child, ".run-lock")))
  expect_identical(child_context_integration_files(child)[names(ledger)], ledger)
  retried <- child_context_integration_set(child, patch, "context-crash-artifacts", before)
  expect_identical(retried$child_context$generation, 1L)
  expect_identical(retried$child_context$previous_hash, before$child_context$hash)
  expect_identical(child_context_integration_files(child)[names(ledger)], ledger)
  committed_args <- list(project_dir = child, context = list(notes = "Retry a durable committed correction after a fresh R process."),
    project_id = retried$project_id, input_hash = retried$input_hash,
    expected_revision = retried$revision, expected_context_hash = retried$child_context$hash,
    reviewer = "PRIVATE_REVIEWER_CONTEXT_SENTINEL", reason = "Correct soft context after reviewing current child evidence.",
    request_id = "context-crash-commit")
  options(scAgentKit.run_crash = "child_context:commit")
  expect_error(do.call(sc_run_set_child_context, committed_args), "Injected crash at child_context:commit", fixed = TRUE)
  options(scAgentKit.run_crash = NULL)
  committed <- sc_run_inspect(child)
  expect_identical(committed$child_context$generation, 2L)
  expect_identical(committed$child_context$previous_hash, retried$child_context$hash)
  files_committed <- child_context_integration_files(child)
  script <- file.path(work, "fresh-process-context-retry.R")
  arguments <- file.path(work, "fresh-process-context-retry-args.rds")
  outcome <- file.path(work, "fresh-process-context-retry-result.rds")
  package <- getNamespaceInfo(asNamespace("scAgentKit"), "path")
  fingerprint <- function() {
    ns <- asNamespace("scAgentKit")
    selected <- sort(grep("^(sc_run|\\.sc_run_)", ls(ns, all.names = TRUE), value = TRUE))
    stats::setNames(vapply(selected, function(name) {
      fn <- get(name, envir = ns)
      scAgentKit:::.sc_run_hash(list(formals = paste(deparse(formals(fn), width.cutoff = 500L), collapse = "\n"),
        body = paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n")))
    }, character(1)), selected)
  }
  saveRDS(list(package = package, libraries = .libPaths(), request = committed_args, outcome = outcome,
    code = fingerprint()), arguments)
  writeLines(c("local({", "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "if (file.exists(file.path(args$package,'R','run.R'))) pkgload::load_all(args$package,quiet=TRUE,helpers=FALSE) else suppressPackageStartupMessages(library(scAgentKit,lib.loc=dirname(args$package)))",
    "stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('scAgentKit'),'path')),normalizePath(args$package)))",
    "calls <- new.env(parent=emptyenv()); calls$factory <- calls$http <- 0L",
    "factory <- function(...) { calls$factory <- calls$factory + 1L; stop('No remote factory is permitted.') }",
    "testthat::local_mocked_bindings(chat_deepseek=factory, chat_grok=factory, .package='agentomicsCore', .env=environment())",
    "testthat::local_mocked_bindings(req_perform=function(...) { calls$http <- calls$http + 1L; stop('No HTTP is permitted.') }, .package='httr2', .env=environment())",
    "ns <- asNamespace('scAgentKit')",
    "selected <- sort(grep('^(sc_run|\\\\.sc_run_)', ls(ns, all.names=TRUE), value=TRUE))",
    "code <- stats::setNames(vapply(selected, function(name) { fn <- get(name,envir=ns); scAgentKit:::.sc_run_hash(list(formals=paste(deparse(formals(fn),width.cutoff=500L),collapse='\\n'),body=paste(deparse(body(fn),width.cutoff=500L),collapse='\\n'))) }, character(1)), selected)",
    "if (!identical(args$code, code)) stop(paste('Fresh source differs at', args$package, ':', paste(union(names(code)[code != args$code[names(code)]], setdiff(names(args$code),names(code))),collapse=', ')))",
    "result <- do.call(scAgentKit::sc_run_set_child_context, args$request)",
    "saveRDS(list(revision=result$revision, context=result$child_context, factory=calls$factory, http=calls$http), args$outcome)",
    "})"), script)
  process_output <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), shQuote(arguments)), stdout = TRUE, stderr = TRUE))
  expect_null(attr(process_output, "status"), info = paste(process_output, collapse = "\n"))
  expect_true(file.exists(outcome))
  if (file.exists(outcome)) {
    fresh <- readRDS(outcome)
    expect_identical(fresh$revision, committed$revision)
    expect_identical(fresh$context, committed$child_context)
    expect_identical(fresh$factory, 0L); expect_identical(fresh$http, 0L)
  }
  expect_identical(child_context_integration_files(child), files_committed)
  expect_identical(child_context_integration_files(child)[names(ledger)], ledger)
  expect_identical(callbacks, 1L)
  events <- Filter(function(event) identical(event$action, "child_context_corrected"),
    scAgentKit:::.sc_run_load(child)$history)
  expect_length(events, 2L)
  expect_identical(vapply(events, function(event) event$details$generation, integer(1)), c(1L, 2L))
  expect_identical(child_context_integration_files(parent$root), protected_parent)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})
