# Offline coordinator acceptance: the parent is completed through its actual
# marker/evidence/manual-annotation approval chain. No synthetic state or fake
# annotation approval is substituted for that chain.
subcluster_integration_fixture <- function(small = FALSE) {
  set.seed(6041L)
  # Deliberately reverse the two numeric-looking literals: the coordinator's
  # raw-layer view must preserve source order, rather than UTF-8 sorting it.
  cells <- c("1", "001", "NA", "cell space", paste0("scopeCell", 5:72))
  counts <- matrix(stats::rpois(120L * 72L, 2), nrow = 120L,
    dimnames = list(c("MT-CO1", paste0("ScopeGene", 2:120)), cells))
  for (program in seq_len(6L)) {
    genes <- seq.int((program - 1L) * 10L + 2L, program * 10L + 1L)
    chosen <- seq.int((program - 1L) * 12L + 1L, program * 12L)
    counts[genes, chosen] <- counts[genes, chosen] + 9L
  }
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE),
    min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <-
    Matrix::Matrix(counts * 2L, sparse = TRUE)
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  membership <- rep(c("01", "1", "NA"), each = 24L)
  if (small) membership[1:4] <- "tiny"
  object$parent_cluster <- factor(membership, levels = c("NA", "1", "01", "tiny", "unused"))
  object$old_annotation <- factor(rep(c("prior", NA_character_), 36L),
    levels = c("unused", "prior"))
  object$sample <- rep(c("sample A", "sample B", "sample C"), each = 24L)
  object$capture <- object$sample
  object$technical_batch <- rep(c("batch A", "batch B", "batch C"), each = 24L)
  object$condition <- rep(c("Ca", "Ctrl"), 36L)
  object$private_note <- "Literal per-cell source metadata; never a model payload."
  object
}

subcluster_integration_context <- function() list(species = "human", tissue = "synthetic",
  columns = list(sample = "sample", capture = "capture", batch = "technical_batch",
    condition = "condition"),
  design = list(type = "public synthetic software fixture", technical_batch = TRUE,
    notes = "Each scoped parent cluster is a single technical batch; no valid integration contrast is inferred."),
  research_goal = "Test raw-count child analysis and exact-ID derived-parent writeback.",
  notes = "The planted expression and parent cluster assignments are software controls, not biological labels.")

subcluster_integration_plan <- function() list(schema = "scagentkit.strategy.v1",
  rationale = "A finite manually reviewed raw-count child software control.",
  risks = list("No biological identity or clustering optimum is established."),
  inferences = list(), qc = list(schema = "scagentkit.qc.v1",
    rationale = "Keep every frozen selected parent cell.", risks = list("No second quality filter requested."),
    filters = list(list(op = "range", metric = "nCount", min = 0L))),
  analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
    nfeatures = 50L, npcs = 6L, seed = 6041L),
  pcs = list(method = "fixed", ndim = 4L),
  batch = list(method = "none", reason = "No parent embedding or automatic batch correction is inherited."),
  clustering = list(resolution = .4, diagnostic_resolutions = NULL),
  umap = list(run = FALSE, n_neighbors = 20L))

subcluster_integration_network <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$factory <- 0L; calls$http <- 0L
  factory <- function(...) {
    calls$factory <- calls$factory + 1L
    stop("Offline child QA forbids remote provider factories.")
  }
  testthat::local_mocked_bindings(chat_deepseek = factory, chat_grok = factory,
    .package = "agentomicsCore", .env = env)
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls$http <- calls$http + 1L; stop("Offline child QA forbids HTTP dispatch.")
  }, .package = "httr2", .env = env)
  calls
}

subcluster_integration_files <- function(root) {
  if (!dir.exists(root)) return(stats::setNames(character(), character()))
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE))
  files <- files[!dir.exists(files)]
  stats::setNames(vapply(files, scAgentKit:::.sc_project_sha_file, character(1)),
    substring(files, nchar(root) + 2L))
}

subcluster_integration_decide <- function(root, action = "approve", snapshot = sc_run_inspect(root)) {
  node <- snapshot$review_node
  sc_run_review(root, action, node$kind, node$project_id, node$input_hash,
    node$proposal_hash, node$review_hash, node$expected_revision,
    reviewer = "offline child QA", reason = "Review exact scope, typed parameters and current evidence.")
}

subcluster_integration_continue <- function(root, snapshot = sc_run_inspect(root)) {
  suppressWarnings(sc_run_continue(root, snapshot$project_id, snapshot$input_hash, snapshot$revision))
}

subcluster_integration_parent <- function(work, object = subcluster_integration_fixture(), reference = NULL) {
  root <- file.path(work, "parent")
  proposal <- list(schema = "scagentkit.annotation.v1",
    annotations = lapply(unique(as.character(object$parent_cluster)), function(id)
      list(clusterId = id, label = "Unknown", confidence = "low",
        rationale = "Explicit synthetic parent label remains unresolved.", markers = list())))
  initial <- suppressWarnings(sc_run(object, root, context = subcluster_integration_context(),
    start_stage = "processed", processed_reason = "Explicit synthetic normalized object and literal manually assigned parent memberships; no prior biological analysis is claimed.",
    cluster_column = "parent_cluster", annotation_column = "parent_reviewed_type",
    provider = NULL, budget = 0, review = list(allow_external = FALSE),
    reference = reference, annotation_proposal = proposal))
  stopifnot(identical(initial$status, "awaiting_review"))
  subcluster_integration_decide(root)
  completed <- subcluster_integration_continue(root)
  stopifnot(identical(completed$status, "complete"))
  list(root = root, state = scAgentKit:::.sc_run_load(root),
    object = readRDS(completed$output$seurat), input = object)
}

subcluster_integration_create <- function(parent, child, clusters = "01", request_id = "create-child-1",
                                          plan = subcluster_integration_plan(), choices = list(), ...) {
  scope <- sc_run_subcluster_scope(parent$root)
  sc_run_subcluster(parent$root, child, clusters = clusters,
    parent_scope_hash = scope$parent_scope_hash,
    expected_parent_revision = sc_run_inspect(parent$root)$revision,
    strategy_proposal = plan, choices = choices,
    reviewer = "offline child QA", reason = "Select explicit literal parent cluster IDs for a fresh conditional analysis.",
    request_id = request_id, ...)
}

subcluster_integration_finish <- function(child, request_id = "unknown-child-1") {
  subcluster_integration_decide(child)
  paused <- subcluster_integration_continue(child)
  stopifnot(identical(paused$status, "awaiting_configuration"), identical(paused$stage, "annotation_propose"))
  snapshot <- sc_run_inspect(child)
  proposed <- sc_run_subcluster_unknown(child, snapshot$project_id, snapshot$input_hash, snapshot$revision,
    reviewer = "offline child QA", reason = "No AI identity inference; retain explicit low-confidence Unknown labels.",
    request_id = request_id)
  proposal_files <- subcluster_integration_files(child)
  repeated <- sc_run_subcluster_unknown(child, snapshot$project_id, snapshot$input_hash, snapshot$revision,
    reviewer = "offline child QA", reason = "No AI identity inference; retain explicit low-confidence Unknown labels.",
    request_id = request_id)
  expect_identical(repeated$run$revision, proposed$run$revision)
  expect_identical(subcluster_integration_files(child), proposal_files)
  expect_error(sc_run_subcluster_unknown(child, snapshot$project_id, snapshot$input_hash, snapshot$revision,
    reviewer = "offline child QA", reason = "Different payload must not reuse an existing request ID.",
    request_id = request_id), "request|payload|reused|different")
  expect_identical(subcluster_integration_files(child), proposal_files)
  subcluster_integration_decide(child)
  completed <- subcluster_integration_continue(child)
  stopifnot(identical(completed$status, "complete"))
  completed
}

subcluster_integration_apply <- function(child, snapshot = sc_run_subcluster_inspect(child),
                                         request_id = "apply-child-1", ...) {
  keys <- c("project_id", "input_hash", "expected_revision", "parent_scope_hash",
    "expected_parent_revision", "annotation_hash", "apply_hash", "column", "outside", "supersedes")
  exact <- snapshot$apply_snapshot
  stopifnot(is.list(exact), all(setdiff(keys, "supersedes") %in% names(exact)))
  do.call(sc_run_subcluster_apply, c(list(child_project = child), exact[intersect(keys, names(exact))],
    list(reviewer = "offline child QA", reason = "Write only verified retained literal child IDs into a fresh parent-derived column.",
      request_id = request_id), list(...)))
}

subcluster_integration_undo <- function(child, application_id, request_id = "undo-child-1") {
  snapshot <- sc_run_subcluster_inspect(child)
  run <- snapshot$run
  sc_run_subcluster_undo(child, application_id, run$project_id, run$input_hash, run$revision,
    snapshot$integration_revision, reviewer = "offline child QA",
    reason = "Undo exactly this child application into a new immutable derived object.", request_id = request_id)
}

test_that("one child strategy and annotation review produce an immutable parent-derived exact-ID subtype", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-complete-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  source <- subcluster_integration_fixture(); source_bytes <- serialize(source, NULL, version = 2L)
  parent <- subcluster_integration_parent(work, source)
  protected <- subcluster_integration_files(parent$root)
  child <- file.path(work, "child")
  initial <- subcluster_integration_create(parent, child)
  expect_identical(initial$status, "awaiting_review")
  expect_identical(initial$pending$kind, "strategy")
  state <- scAgentKit:::.sc_run_load(child)
  origin <- state$config$subcluster_origin
  selected <- colnames(parent$object)[as.character(parent$object$parent_cluster) == "01"]
  expect_identical(selected[1:2], c("1", "001"))
  expect_false(identical(selected, sort(enc2utf8(selected), method = "radix")))
  expect_identical(origin$selected_cells, selected)
  expect_identical(origin$selected_clusters, "01")
  expect_identical(origin$parent$project_id, parent$state$project_id)
  expect_identical(origin$parent$input_hash, parent$state$input_hash)
  expect_identical(origin$parent$revision, parent$state$revision)
  expect_identical(origin$parent$cluster_column, "parent_cluster")
  expect_identical(origin$selected_cells_hash, scAgentKit:::.sc_run_hash(selected))
  expect_identical(origin$parent_scope_hash, sc_run_subcluster_scope(parent$root)$parent_scope_hash)
  expect_identical(state$config$context$species, "human")
  expect_identical(state$config$context$tissue, "synthetic")
  expect_identical(state$config$subcluster_creation$choices,
    list(qc = "retain_selected", doublet = "keep", batch = "none", cycle = "none", reference = "none"))
  input <- scAgentKit:::.sc_run_get(child, state, "input")
  expect_identical(colnames(input), selected)
  expect_identical(SeuratObject::LayerData(input, assay = "RNA", layer = "counts"),
    SeuratObject::LayerData(parent$object, assay = "RNA", layer = "counts")[rownames(input), selected, drop = FALSE])
  expect_identical(SeuratObject::Layers(input[["RNA"]]), "counts")
  expect_length(input@reductions, 0L); expect_length(input@graphs, 0L)
  expect_identical(unique(as.character(SeuratObject::Idents(input))), "unassigned")
  for (name in names(parent$object[[]]))
    expect_identical(input[[]][[name]], parent$object[[]][selected, name])
  expect_null(state$files$qc_object); expect_null(state$files$strategy_basis)
  expect_identical(subcluster_integration_files(parent$root), protected)
  completed <- subcluster_integration_finish(child)
  state <- scAgentKit:::.sc_run_load(child)
  approvals <- Filter(function(event) identical(event$action, "approved"), state$history)
  expect_identical(vapply(approvals, function(event) event$details$kind, character(1)), c("strategy", "annotation"))
  for (stage in c("qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_apply"))
    expect_equal(sum(vapply(state$history, function(event) identical(event$action, "executed") &&
      identical(event$details$stage, stage), logical(1))), 1L)
  final <- readRDS(completed$output$seurat)
  expect_identical(colnames(final), selected)
  expect_true("pca" %in% names(final@reductions))
  expect_true("data" %in% SeuratObject::Layers(final[["RNA"]]))
  expect_true(all(final$sc_subtype == "Unknown"))
  expect_true(all(final$sc_subtype_confidence == "low"))
  expect_false(dir.exists(file.path(child, "provider")))
  expect_identical(subcluster_integration_files(parent$root), protected)
  before_repeat <- subcluster_integration_files(child)
  expect_identical(subcluster_integration_continue(child)$status, "complete")
  expect_identical(subcluster_integration_files(child), before_repeat)
  snapshot <- sc_run_subcluster_inspect(child, column = "reviewed_subtype")
  applied <- subcluster_integration_apply(child, snapshot)
  application <- applied$application
  expect_true(file.exists(application$output_path))
  derived <- readRDS(application$output_path)
  expect_identical(colnames(derived), colnames(parent$object))
  expect_identical(SeuratObject::LayerData(derived, assay = "RNA", layer = "counts"),
    SeuratObject::LayerData(parent$object, assay = "RNA", layer = "counts"))
  for (name in names(parent$object[[]])) expect_identical(derived[[]][[name]], parent$object[[]][[name]])
  expect_true(all(derived[[]][selected, "reviewed_subtype"] == "Unknown"))
  expect_true(all(is.na(derived[[]][setdiff(colnames(derived), selected), "reviewed_subtype"])))
  expect_true(all(derived[[]][selected, "reviewed_subtype_source_child"] == state$project_id))
  expect_identical(application$output_sha256, scAgentKit:::.sc_project_sha_file(application$output_path))
  after_apply <- subcluster_integration_files(child)
  repeated <- subcluster_integration_apply(child, snapshot)
  expect_identical(repeated$application$application_id, application$application_id)
  expect_identical(subcluster_integration_files(child), after_apply)
  expect_identical(subcluster_integration_files(parent$root), protected)
  expect_identical(serialize(source, NULL, version = 2L), source_bytes)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("child creation validates explicit choices IDs numerical settings and paths before publication", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-reject-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- subcluster_integration_parent(work, subcluster_integration_fixture(small = TRUE))
  protected <- subcluster_integration_files(parent$root)
  attempts <- list(list(clusters = character()), list(clusters = c("01", "01")),
    list(clusters = "missing"), list(clusters = NA_character_), list(clusters = "tiny"))
  for (index in seq_along(attempts)) {
    child <- file.path(work, paste0("rejected-scope-", index))
    expect_error(subcluster_integration_create(parent, child, clusters = attempts[[index]]$clusters),
      "cluster|select|unique|duplicat|21|cell|missing|NA|nonempty")
    expect_false(file.exists(file.path(child, "state.rds")))
    expect_identical(subcluster_integration_files(parent$root), protected)
  }
  for (index in seq_along(list("adaptive", "not-a-number", NA_real_, Inf, -1))) {
    bad <- subcluster_integration_plan()
    bad$clustering$resolution <- list("adaptive", "not-a-number", NA_real_, Inf, -1)[[index]]
    child <- file.path(work, paste0("rejected-resolution-", index))
    # Select 48 cells, avoiding the deliberately small '01' fixture scope.
    expect_error(subcluster_integration_create(parent, child, clusters = c("1", "NA"), plan = bad),
      "resolution|numeric|finite|number|positive")
    expect_false(file.exists(file.path(child, "state.rds")))
    expect_identical(subcluster_integration_files(parent$root), protected)
  }
  for (choice in list(list(doublet = "remove_predicted"), list(cycle = "inherit"),
                      list(batch = "inherit"), list(qc = "filter"), list(code = "never execute"))) {
    expect_error(subcluster_integration_create(parent, file.path(work, "bad-choice"),
      clusters = c("1", "NA"), choices = choice), "choice|Unsupported|unsupported")
    expect_false(file.exists(file.path(work, "bad-choice", "state.rds")))
  }
  expect_error(subcluster_integration_create(parent, file.path(parent$root, "child"),
    clusters = c("1", "NA")), "parent|outside|sibling|path|inside")
  expect_identical(subcluster_integration_files(parent$root), protected)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("whole-parent bindings distinguish literal selections and overlapping children never merge", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-overlap-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- subcluster_integration_parent(work)
  protected <- subcluster_integration_files(parent$root)
  scope_a <- sc_run_subcluster_scope(parent$root, clusters = "01")
  scope_b <- sc_run_subcluster_scope(parent$root, clusters = c("01", "1"))
  expect_identical(scope_a$parent_scope_hash, scope_b$parent_scope_hash)
  expect_equal(scope_a$selected$count, 24L)
  expect_equal(scope_b$selected$count, 48L)
  expect_false(identical(scope_a$selected$selection_hash, scope_b$selected$selection_hash))
  child_a <- file.path(work, "child-a"); child_b <- file.path(work, "child-b")
  first <- subcluster_integration_create(parent, child_a)
  first_files <- subcluster_integration_files(child_a)
  repeated <- subcluster_integration_create(parent, child_a)
  expect_identical(repeated$project_id, first$project_id)
  expect_identical(subcluster_integration_files(child_a), first_files)
  changed <- subcluster_integration_plan(); changed$analysis$seed <- 6042L
  expect_error(subcluster_integration_create(parent, child_a, plan = changed), "request|settings|differ|reuse")
  expect_identical(subcluster_integration_files(child_a), first_files)
  second <- subcluster_integration_create(parent, child_b, clusters = c("01", "1"), request_id = "create-child-2")
  expect_false(identical(second$project_id, first$project_id))
  a <- scAgentKit:::.sc_run_load(child_a); b <- scAgentKit:::.sc_run_load(child_b)
  expect_false(identical(a$config$subcluster_origin$scope_hash, b$config$subcluster_origin$scope_hash))
  expect_true(all(a$config$subcluster_origin$selected_cells %in% b$config$subcluster_origin$selected_cells))
  expect_identical(subcluster_integration_files(child_a), first_files)
  owner <- scAgentKit:::.sc_run_lock(parent$root)
  locked <- subcluster_integration_files(parent$root)
  expect_error(subcluster_integration_create(parent, file.path(work, "locked-child")), "locked")
  expect_identical(subcluster_integration_files(parent$root), locked)
  scAgentKit:::.sc_run_release(parent$root, owner)
  expect_identical(subcluster_integration_files(parent$root), protected)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("stale foreign or conflicting apply requests cannot alter a completed child or parent", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-apply-reject-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- subcluster_integration_parent(work)
  child <- file.path(work, "child")
  subcluster_integration_create(parent, child)
  subcluster_integration_finish(child)
  parent_files <- subcluster_integration_files(parent$root)
  snapshot <- sc_run_subcluster_inspect(child, column = "reviewed_subtype")
  protected <- subcluster_integration_files(child)
  fields <- c("project_id", "input_hash", "parent_scope_hash", "annotation_hash", "apply_hash")
  for (field in fields) {
    changed <- snapshot
    changed$apply_snapshot[[field]] <- if (field == "project_id") "foreign-project" else strrep("a", 64L)
    expect_error(subcluster_integration_apply(child, changed, request_id = paste0("bad-", field)),
      "Foreign|foreign|changed|scope|hash|Stale|stale|project|snapshot|annotation")
    expect_identical(subcluster_integration_files(child), protected)
    expect_identical(subcluster_integration_files(parent$root), parent_files)
  }
  for (field in c("expected_revision", "expected_parent_revision")) {
    changed <- snapshot; changed$apply_snapshot[[field]] <- changed$apply_snapshot[[field]] + 1L
    expect_error(subcluster_integration_apply(child, changed, request_id = paste0("bad-", field)), "revision|Stale|stale")
    expect_identical(subcluster_integration_files(child), protected)
  }
  conflict <- sc_run_subcluster_inspect(child, column = "old_annotation")
  expect_null(conflict$apply_snapshot)
  expect_match(conflict$apply_error, "column|exist|conflict")
  unsupported <- sc_run_subcluster_inspect(child, outside = "preserve")
  expect_null(unsupported$apply_snapshot)
  expect_match(unsupported$apply_error, "outside|NA|unsupported|Unsupported")
  expect_identical(subcluster_integration_files(child), protected)
  # Change parent revision through its real hash-chained event writer. The
  # stopped parent is owned by this test; the child must reject that new state
  # without rewriting either project after this deliberate revision change.
  state <- scAgentKit:::.sc_run_load(parent$root)
  state <- scAgentKit:::.sc_run_event(state, "fixture_parent_revision_changed",
    list(reason = "Explicit stale-binding software control."))
  scAgentKit:::.sc_run_save(parent$root, state)
  revised_parent <- subcluster_integration_files(parent$root)
  expect_error(subcluster_integration_apply(child, snapshot, request_id = "stale-parent-apply"),
    "parent|revision|scope|Stale|stale|changed")
  expect_identical(subcluster_integration_files(child), protected)
  expect_identical(subcluster_integration_files(parent$root), revised_parent)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("second QC filtering requires explicit child choice and writeback binds only approved retained IDs", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-filtered-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  source <- subcluster_integration_fixture()
  counts <- SeuratObject::LayerData(source, assay = "RNA", layer = "counts")
  counts[, "001"] <- 0; counts["ScopeGene2", "001"] <- 1
  SeuratObject::LayerData(source, assay = "RNA", layer = "counts") <- counts
  SeuratObject::LayerData(source, assay = "RNA", layer = "extra") <- counts * 2L
  source$nCount_RNA <- unname(Matrix::colSums(counts))
  source$nFeature_RNA <- unname(Matrix::colSums(counts > 0))
  source <- Seurat::NormalizeData(source, verbose = FALSE)
  parent <- subcluster_integration_parent(work, source)
  protected <- subcluster_integration_files(parent$root)
  plan <- subcluster_integration_plan()
  plan$qc <- list(schema = "scagentkit.qc.v1", rationale = "Explicitly exclude only the planted one-count control.",
    risks = list("Synthetic software exclusion, not a biological quality threshold."),
    filters = list(list(op = "range", metric = "nCount", min = 2L)))
  expect_error(subcluster_integration_create(parent, file.path(work, "not-authorized"), plan = plan),
    "retain_selected|filter|QC|choice")
  expect_false(file.exists(file.path(work, "not-authorized", "state.rds")))
  expect_identical(subcluster_integration_files(parent$root), protected)
  child <- file.path(work, "reviewed-filter")
  subcluster_integration_create(parent, child, plan = plan, choices = list(qc = "review"))
  completed <- subcluster_integration_finish(child)
  state <- scAgentKit:::.sc_run_load(child)
  frozen <- state$config$subcluster_origin$selected_cells
  retained <- setdiff(frozen, "001")
  expect_length(frozen, 24L); expect_length(retained, 23L)
  expect_identical(colnames(readRDS(completed$output$seurat)), retained)
  applied <- subcluster_integration_apply(child,
    sc_run_subcluster_inspect(child, column = "filtered_subtype"))
  derived <- readRDS(applied$application$output_path)
  expect_true(is.na(derived[[]]["001", "filtered_subtype"]))
  expect_true(all(derived[[]][retained, "filtered_subtype"] == "Unknown"))
  expect_true(all(is.na(derived[[]][setdiff(colnames(derived), retained), "filtered_subtype"])))
  expect_identical(colnames(derived), colnames(parent$object))
  expect_identical(SeuratObject::LayerData(derived, assay = "RNA", layer = "counts"),
    SeuratObject::LayerData(parent$object, assay = "RNA", layer = "counts"))
  expect_identical(state$config$subcluster_origin$selected_cells, frozen)
  expect_identical(subcluster_integration_files(parent$root), protected)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("reference inheritance copies a versioned snapshot but rebuilds candidates and review scope in the child", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-reference-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  reference <- data.frame(cell_type = c("Unresolved A", "Unresolved B"),
    marker = c("ScopeGene2", "ScopeGene12"), species = "human", tissue = "synthetic", stringsAsFactors = FALSE)
  attr(reference, "source_version") <- "CellMarker2.0"
  attr(reference, "source_url") <- "https://example.invalid/public-synthetic-reference"
  attr(reference, "marker_column") <- "Symbol"
  parent <- subcluster_integration_parent(work, reference = reference)
  protected <- subcluster_integration_files(parent$root)
  parent_evidence <- scAgentKit:::.sc_run_get(parent$root, parent$state, "annotation_evidence")
  expect_identical(parent_evidence$private$reference_provenance$source_version, "CellMarker2.0")
  child <- file.path(work, "child")
  subcluster_integration_create(parent, child, choices = list(reference = "inherit"))
  state <- scAgentKit:::.sc_run_load(child)
  inherited <- state$config$subcluster_creation$reference
  expect_identical(inherited$status, "inherited_snapshot")
  expect_identical(inherited$source_version, "CellMarker2.0")
  expect_identical(inherited$parent_artifact_sha256, parent$state$files$reference$sha256)
  expect_identical(inherited$parent_evidence_sha256, parent$state$files$annotation_evidence$sha256)
  expect_null(state$files$annotation_history_input)
  subcluster_integration_finish(child)
  state <- scAgentKit:::.sc_run_load(child)
  evidence <- scAgentKit:::.sc_run_get(child, state, "annotation_evidence")
  review <- scAgentKit:::.sc_run_get(child, state, "annotation_review")
  expect_identical(evidence$private$reference_provenance$source_version, "CellMarker2.0")
  expect_identical(evidence$private$input_cells$cell_id, state$config$subcluster_origin$selected_cells)
  expect_identical(review$cell_scope_hash, scAgentKit:::.sc_run_hash(evidence$private$input_cells))
  expect_identical(review$input_hash, state$input_hash)
  expect_false(identical(review$cell_scope_hash,
    scAgentKit:::.sc_run_hash(parent_evidence$private$input_cells)))
  expected_clusters <- unique(evidence$private$input_cells$cluster)
  expect_true(all(evidence$private$candidates$cluster %in% expected_clusters))
  expect_identical(subcluster_integration_files(parent$root), protected)

  mismatch_work <- file.path(work, "recorded-source-mismatch"); dir.create(mismatch_work)
  mismatch_path <- file.path(mismatch_work, "reference.csv")
  utils::write.csv(reference, mismatch_path, row.names = FALSE)
  mismatch_reference <- annot_load_reference(mismatch_path)
  attr(mismatch_reference, "source_version") <- "CellMarker2.0"
  changed_reference <- reference; changed_reference$marker[1L] <- "ScopeGene22"
  # The parent uses the actual loaded data frame, whose original MD5 remains
  # recorded. Change only this test's external public fixture before evidence
  # is computed; the parent then records the source/snapshot mismatch honestly.
  utils::write.csv(changed_reference, mismatch_path, row.names = FALSE)
  mismatch_parent <- subcluster_integration_parent(mismatch_work, reference = mismatch_reference)
  mismatch_evidence <- scAgentKit:::.sc_run_get(mismatch_parent$root, mismatch_parent$state, "annotation_evidence")
  expect_identical(mismatch_evidence$private$reference_provenance$source_file_status, "recorded_md5_mismatch")
  mismatch_files <- subcluster_integration_files(mismatch_parent$root)
  mismatch_child <- file.path(mismatch_work, "child")
  expect_error(subcluster_integration_create(mismatch_parent, mismatch_child,
    choices = list(reference = "inherit")), "reference|source|snapshot|stale|readable|mismatch|differ")
  expect_false(file.exists(file.path(mismatch_child, "state.rds")))
  expect_identical(subcluster_integration_files(mismatch_parent$root), mismatch_files)

  readable_work <- file.path(work, "readable-source-snapshot"); dir.create(readable_work)
  readable_path <- file.path(readable_work, "reference.csv")
  utils::write.csv(reference, readable_path, row.names = FALSE)
  readable_reference <- annot_load_reference(readable_path)
  attr(readable_reference, "source_version") <- "CellMarker2.0"
  readable_parent <- subcluster_integration_parent(readable_work, reference = readable_reference)
  readable_files <- subcluster_integration_files(readable_parent$root)
  readable_child <- file.path(readable_work, "child")
  subcluster_integration_create(readable_parent, readable_child, choices = list(reference = "inherit"))
  readable_state <- scAgentKit:::.sc_run_load(readable_child)
  snapshot <- scAgentKit:::.sc_run_get(readable_child, readable_state, "reference")
  expect_null(attr(snapshot, "source_path"))
  snapshot_hash <- scAgentKit:::.sc_run_hash(snapshot)
  original_source_sha <- scAgentKit:::.sc_project_sha_file(readable_path)
  expect_identical(readable_state$config$subcluster_creation$reference$source_sha256, original_source_sha)
  # Once the child owns a detached immutable data-frame snapshot, subsequent
  # changes to the external parent source file cannot redirect its scoring.
  utils::write.csv(changed_reference, readable_path, row.names = FALSE)
  expect_false(identical(scAgentKit:::.sc_project_sha_file(readable_path), original_source_sha))
  subcluster_integration_finish(readable_child, request_id = "unknown-detached-reference")
  readable_state <- scAgentKit:::.sc_run_load(readable_child)
  expect_identical(scAgentKit:::.sc_run_hash(scAgentKit:::.sc_run_get(readable_child, readable_state, "reference")), snapshot_hash)
  child_evidence <- scAgentKit:::.sc_run_get(readable_child, readable_state, "annotation_evidence")
  expect_identical(child_evidence$private$reference_provenance$source_version, "CellMarker2.0")
  expect_identical(child_evidence$private$reference_provenance$source_sha256, original_source_sha)
  expect_identical(child_evidence$private$input_cells$cell_id, readable_state$config$subcluster_origin$selected_cells)
  expect_identical(subcluster_integration_files(readable_parent$root), readable_files)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("a single child cluster with empty markers remains explicit Unknown and cannot annotate parent cluster zero", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-one-cluster-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- subcluster_integration_parent(work)
  protected <- subcluster_integration_files(parent$root)
  child <- file.path(work, "child")
  subcluster_integration_create(parent, child)
  # Only the public graph clustering result is controlled here, so the existing
  # adapter still builds its complete typed execution record. Counts, scaling,
  # PCA, neighbors, marker testing and all journal bindings remain real.
  testthat::local_mocked_bindings(FindClusters = function(object, ...) {
    data.frame(cluster = rep("0", nrow(object)), row.names = rownames(object), stringsAsFactors = FALSE)
  }, .package = "Seurat", .env = environment())
  completed <- subcluster_integration_finish(child)
  state <- scAgentKit:::.sc_run_load(child)
  object <- readRDS(completed$output$seurat)
  expect_identical(unique(as.character(object$sc_subcluster_clusters)), "0")
  expect_identical(nrow(scAgentKit:::.sc_run_get(child, state, "markers")$markers), 0L)
  evidence <- scAgentKit:::.sc_run_get(child, state, "annotation_evidence")
  expect_length(evidence$summary$clusters, 1L)
  expect_length(evidence$summary$clusters[[1L]]$markers, 0L)
  expect_true(all(object$sc_subtype == "Unknown"))
  expect_true(all(object$sc_subtype_confidence == "low"))
  applied <- subcluster_integration_apply(child,
    sc_run_subcluster_inspect(child, column = "single_subtype"))
  derived <- readRDS(applied$application$output_path)
  selected <- state$config$subcluster_origin$selected_cells
  expect_true(all(derived[[]][selected, "single_subtype"] == "Unknown"))
  expect_true(all(derived[[]][selected, "single_subtype_child_cluster"] == "0"))
  expect_true(all(is.na(derived[[]][setdiff(colnames(derived), selected), "single_subtype"])))
  expect_identical(derived$parent_cluster, parent$object$parent_cluster)
  expect_identical(subcluster_integration_files(parent$root), protected)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("a child annotation revision needs explicit own supersession and undo preserves every previous artifact", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-versioned-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- subcluster_integration_parent(work)
  protected <- subcluster_integration_files(parent$root)
  child <- file.path(work, "child")
  subcluster_integration_create(parent, child)
  subcluster_integration_finish(child)
  original_snapshot <- sc_run_subcluster_inspect(child, column = "versioned_subtype")
  first <- subcluster_integration_apply(child, original_snapshot)$application
  first_bytes <- readBin(first$output_path, "raw", n = file.info(first$output_path)$size)
  first_object <- readRDS(first$output_path)
  current <- sc_run_inspect(child); node <- current$review_node
  sc_run_review(child, "undo", "annotation", current$project_id, current$input_hash,
    node$proposal_hash, node$review_hash, current$revision,
    reviewer = "offline child QA", reason = "Reopen only the child's approved annotation; preserve applied artifacts.",
    decision_id = node$decision_id)
  evidence <- sc_run_inspect(child)$evidence
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(evidence$clusters,
    function(row) list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
      rationale = "Revised explicit Unknown reasoning after a second manual evidence review; biological identity remains unresolved.", markers = list())))
  sc_run_propose(child, proposal, "offline child QA", "Revise the child's literal annotation scope only.")
  subcluster_integration_decide(child)
  expect_identical(subcluster_integration_continue(child)$status, "complete")
  expect_identical(readBin(first$output_path, "raw", n = file.info(first$output_path)$size), first_bytes)
  unchanged <- subcluster_integration_files(child)
  expect_error(subcluster_integration_apply(child, original_snapshot, request_id = "old-annotation-apply"),
    "revision|stale|Stale|annotation|changed")
  expect_identical(subcluster_integration_files(child), unchanged)
  blocked <- sc_run_subcluster_inspect(child, column = "versioned_subtype")
  expect_null(blocked$apply_snapshot)
  expect_match(blocked$apply_error, "active|supersede|column")
  replacement <- sc_run_subcluster_inspect(child, column = "versioned_subtype", supersedes = first$application_id)
  second <- subcluster_integration_apply(child, replacement, request_id = "apply-child-revision-2")$application
  expect_false(identical(second$application_id, first$application_id))
  expect_false(identical(second$output_path, first$output_path))
  expect_identical(second$supersedes, first$application_id)
  second_object <- readRDS(second$output_path)
  selected <- scAgentKit:::.sc_run_load(child)$config$subcluster_origin$selected_cells
  expect_true(all(second_object[[]][selected, "versioned_subtype"] == "Unknown"))
  expect_true(all(second_object[[]][selected, "versioned_subtype_rationale"] == proposal$annotations[[1L]]$rationale))
  expect_false(identical(second_object[[]][selected, "versioned_subtype_rationale"],
    first_object[[]][selected, "versioned_subtype_rationale"]))
  expect_true(all(first_object[[]][selected, "versioned_subtype"] == "Unknown"))
  expect_identical(readBin(first$output_path, "raw", n = file.info(first$output_path)$size), first_bytes)
  second_sha <- scAgentKit:::.sc_project_sha_file(second$output_path)
  undo <- subcluster_integration_undo(child, second$application_id)
  expect_true(file.exists(undo$undo$output_path))
  expect_false(undo$undo$output_path %in% c(first$output_path, second$output_path))
  restored <- readRDS(undo$undo$output_path)
  expect_identical(serialize(restored, NULL, version = 2L), serialize(first_object, NULL, version = 2L))
  expect_identical(scAgentKit:::.sc_project_sha_file(first$output_path), first$output_sha256)
  expect_identical(scAgentKit:::.sc_project_sha_file(second$output_path), second_sha)
  after_undo <- subcluster_integration_files(child)
  # Same exact undo request is idempotent despite the integration revision
  # increasing on the first successful undo. A fresh request cannot undo it twice.
  repeated <- sc_run_subcluster_undo(child, second$application_id,
    replacement$run$project_id, replacement$run$input_hash, replacement$run$revision,
    undo$integration_revision - 1L, reviewer = "offline child QA",
    reason = "Undo exactly this child application into a new immutable derived object.", request_id = "undo-child-1")
  expect_identical(repeated$undo$output_path, undo$undo$output_path)
  expect_identical(subcluster_integration_files(child), after_undo)
  expect_error(subcluster_integration_undo(child, second$application_id, request_id = "undo-again"),
    "active|undone|undo|current")
  expect_identical(subcluster_integration_files(child), after_undo)
  expect_identical(subcluster_integration_files(parent$root), protected)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("a same-ID same-count child cannot import another child's application authority", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-cross-import-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  parent <- subcluster_integration_parent(work)
  protected <- subcluster_integration_files(parent$root)
  child_a <- file.path(work, "child-a"); child_b <- file.path(work, "child-b")
  subcluster_integration_create(parent, child_a, request_id = "create-a")
  subcluster_integration_create(parent, child_b, request_id = "create-b")
  subcluster_integration_finish(child_a, request_id = "unknown-a")
  subcluster_integration_finish(child_b, request_id = "unknown-b")
  a <- sc_run_subcluster_inspect(child_a, column = "cross_subtype")
  b <- sc_run_subcluster_inspect(child_b, column = "cross_subtype")
  state_a <- scAgentKit:::.sc_run_load(child_a); state_b <- scAgentKit:::.sc_run_load(child_b)
  expect_identical(state_a$config$subcluster_origin$selected_cells, state_b$config$subcluster_origin$selected_cells)
  expect_identical(state_a$input_hash, state_b$input_hash)
  expect_false(identical(a$run$project_id, b$run$project_id))
  before_a <- subcluster_integration_files(child_a); before_b <- subcluster_integration_files(child_b)
  expect_error(subcluster_integration_apply(child_b, a, request_id = "foreign-import"), "Foreign|foreign|cross-project|project")
  expect_identical(subcluster_integration_files(child_a), before_a)
  expect_identical(subcluster_integration_files(child_b), before_b)
  applied_a <- subcluster_integration_apply(child_a, a, request_id = "apply-a")$application
  applied_b <- subcluster_integration_apply(child_b, b, request_id = "apply-b")$application
  expect_false(identical(applied_a$output_path, applied_b$output_path))
  expect_true(file.exists(applied_a$output_path)); expect_true(file.exists(applied_b$output_path))
  expect_identical(subcluster_integration_files(parent$root), protected)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("receipt and orphan derived artifacts recover once from explicit injected errors without science mutation", {
  network <- subcluster_integration_network()
  work <- tempfile("subcluster-artifact-recovery-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  previous_crash <- getOption("scAgentKit.run_crash")
  on.exit(options(scAgentKit.run_crash = previous_crash), add = TRUE)
  parent <- subcluster_integration_parent(work)
  protected_parent <- subcluster_integration_files(parent$root)
  child <- file.path(work, "child")

  options(scAgentKit.run_crash = "subcluster_create:receipt")
  expect_error(subcluster_integration_create(parent, child, request_id = "recover-create"),
    "Injected crash at subcluster_create:receipt", fixed = TRUE)
  options(scAgentKit.run_crash = NULL)
  receipt <- file.path(child, ".subcluster-creation.rds")
  expect_true(file.exists(receipt)); expect_false(file.exists(file.path(child, "state.rds")))
  expect_false(dir.exists(file.path(parent$root, ".run-lock")))
  expect_false(dir.exists(file.path(child, ".run-lock")))
  expect_identical(names(subcluster_integration_files(child)), ".subcluster-creation.rds")
  receipt_sha <- scAgentKit:::.sc_project_sha_file(receipt)
  receipt_mtime <- file.info(receipt)$mtime
  expect_identical(subcluster_integration_files(parent$root), protected_parent)
  initial <- subcluster_integration_create(parent, child, request_id = "recover-create")
  expect_identical(initial$status, "awaiting_review")
  expect_identical(scAgentKit:::.sc_project_sha_file(receipt), receipt_sha)
  expect_identical(file.info(receipt)$mtime, receipt_mtime)
  state <- scAgentKit:::.sc_run_load(child)
  expect_equal(sum(vapply(state$history, function(event) identical(event$action, "subcluster_created"), logical(1))), 1L)
  created_files <- subcluster_integration_files(child)
  repeated <- subcluster_integration_create(parent, child, request_id = "recover-create")
  expect_identical(repeated$project_id, initial$project_id)
  expect_identical(subcluster_integration_files(child), created_files)
  expect_identical(subcluster_integration_files(parent$root), protected_parent)

  subcluster_integration_finish(child, request_id = "recover-unknown")
  protected_science <- subcluster_integration_files(child)
  snapshot <- sc_run_subcluster_inspect(child, column = "recovered_subtype")
  options(scAgentKit.run_crash = "subcluster_apply:artifact")
  expect_error(subcluster_integration_apply(child, snapshot, request_id = "recover-apply"),
    "Injected crash at subcluster_apply:artifact", fixed = TRUE)
  options(scAgentKit.run_crash = NULL)
  artifacts <- list.files(file.path(child, "reintegration"),
    pattern = "^apply-[a-f0-9]+[.]rds$", full.names = TRUE)
  expect_length(artifacts, 1L)
  apply_orphan <- artifacts[[1L]]
  apply_sha <- scAgentKit:::.sc_project_sha_file(apply_orphan)
  apply_mtime <- file.info(apply_orphan)$mtime
  expect_false(file.exists(file.path(child, "reintegration", "state.rds")))
  expect_length(scAgentKit:::.sc_run_subcluster_integration(child)$applications, 0L)
  files_after_error <- subcluster_integration_files(child)
  expect_identical(files_after_error[!startsWith(names(files_after_error), "reintegration/")], protected_science)
  expect_identical(subcluster_integration_files(parent$root), protected_parent)
  expect_false(dir.exists(file.path(parent$root, ".run-lock")))
  expect_false(dir.exists(file.path(child, ".run-lock")))
  applied <- subcluster_integration_apply(child, snapshot, request_id = "recover-apply")$application
  expect_identical(normalizePath(applied$output_path), normalizePath(apply_orphan))
  expect_identical(applied$output_sha256, apply_sha)
  expect_identical(file.info(apply_orphan)$mtime, apply_mtime)
  journal <- scAgentKit:::.sc_run_subcluster_integration(child)
  expect_length(journal$applications, 1L); expect_length(journal$history, 1L)
  expect_equal(sum(vapply(journal$history, function(event)
    identical(event$action, "applied_to_derived_parent"), logical(1))), 1L)
  applied_files <- subcluster_integration_files(child)
  expect_identical(subcluster_integration_apply(child, snapshot, request_id = "recover-apply")$application$application_id,
    applied$application_id)
  expect_identical(subcluster_integration_files(child), applied_files)

  options(scAgentKit.run_crash = "subcluster_undo:artifact")
  expect_error(subcluster_integration_undo(child, applied$application_id, request_id = "recover-undo"),
    "Injected crash at subcluster_undo:artifact", fixed = TRUE)
  options(scAgentKit.run_crash = NULL)
  artifacts <- list.files(file.path(child, "reintegration"),
    pattern = "^undo-[a-f0-9]+[.]rds$", full.names = TRUE)
  expect_length(artifacts, 1L)
  undo_orphan <- artifacts[[1L]]
  undo_sha <- scAgentKit:::.sc_project_sha_file(undo_orphan)
  undo_mtime <- file.info(undo_orphan)$mtime
  expect_identical(scAgentKit:::.sc_project_sha_file(apply_orphan), apply_sha)
  journal <- scAgentKit:::.sc_run_subcluster_integration(child)
  expect_length(journal$undos, 0L); expect_length(journal$history, 1L)
  expect_true(journal$applications[[applied$application_id]]$active)
  files_after_error <- subcluster_integration_files(child)
  expect_identical(files_after_error[!startsWith(names(files_after_error), "reintegration/")], protected_science)
  expect_identical(subcluster_integration_files(parent$root), protected_parent)
  expect_false(dir.exists(file.path(parent$root, ".run-lock")))
  expect_false(dir.exists(file.path(child, ".run-lock")))
  undone <- subcluster_integration_undo(child, applied$application_id, request_id = "recover-undo")
  expect_identical(normalizePath(undone$undo$output_path), normalizePath(undo_orphan))
  expect_identical(undone$undo$output_sha256, undo_sha)
  expect_identical(file.info(undo_orphan)$mtime, undo_mtime)
  expect_identical(serialize(readRDS(undo_orphan), NULL, version = 2L),
    serialize(parent$object, NULL, version = 2L))
  expect_identical(scAgentKit:::.sc_project_sha_file(apply_orphan), apply_sha)
  journal <- scAgentKit:::.sc_run_subcluster_integration(child)
  expect_length(journal$applications, 1L); expect_length(journal$undos, 1L)
  expect_length(journal$history, 2L)
  expect_false(journal$applications[[applied$application_id]]$active)
  expect_equal(sum(vapply(journal$history, function(event)
    identical(event$action, "derived_application_undone"), logical(1))), 1L)
  expect_identical(subcluster_integration_files(parent$root), protected_parent)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})
