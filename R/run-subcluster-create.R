# Scoped children use the existing typed coordinator. This file only creates a
# fresh raw-count input and binds explicit inheritance choices to that run.
.sc_run_subcluster_choices <- function(choices) {
  defaults <- list(qc = "retain_selected", doublet = "keep", batch = "none",
                   cycle = "none", reference = "none")
  choices <- .sc_run_annotation_options(choices, names(defaults), "subcluster choices")
  for (name in names(defaults)) if (is.null(choices[[name]])) choices[[name]] <- defaults[[name]]
  allowed <- list(qc = c("retain_selected", "review"), doublet = "keep",
                  batch = c("none", "review"), cycle = c("none", "recompute"),
                  reference = c("none", "inherit"))
  for (name in names(defaults)) {
    value <- choices[[name]]
    if (!is.character(value) || length(value) != 1L || is.na(value) ||
        !value %in% allowed[[name]])
      stop("Unsupported subcluster choice ", name, ": use ",
           paste(allowed[[name]], collapse = " or "), ".", call. = FALSE)
  }
  choices[names(defaults)]
}

.sc_run_subcluster_request_id <- function(request_id) {
  .sc_project_string(request_id, "request_id")
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", request_id))
    stop("request_id must be a literal 1-128 character identifier containing letters, digits, periods, underscores or hyphens.", call. = FALSE)
  request_id
}

.sc_run_subcluster_lock_verify <- function(root, owner) {
  path <- file.path(root, ".run-lock", "owner.rds")
  if (!is.list(owner) || !file.exists(path) || nzchar(Sys.readlink(path)))
    stop("Scoped initialization requires its exact owned child lock.", call. = FALSE)
  saved <- readRDS(path)
  if (!identical(saved, owner) || !identical(owner$pid, Sys.getpid()) ||
      !identical(owner$host, unname(Sys.info()["nodename"])))
    stop("Scoped initialization lock must belong to this exact R process and child project.", call. = FALSE)
  invisible(TRUE)
}

.sc_run_subcluster_software_plan <- function(counts, cycle = FALSE) {
  expressed <- sum(Matrix::rowSums(counts > 0) > 0)
  nfeatures <- as.integer(min(2000L, expressed, nrow(counts)))
  npcs <- as.integer(min(30L, ncol(counts) - 1L, nfeatures - 1L))
  if (ncol(counts) < 21L || nfeatures < 3L || npcs < 2L)
    stop("The scoped child requires at least 21 cells and three expressed features for the supported k=20 graph and PCA; no parameter fallback is performed.", call. = FALSE)
  result <- list(schema = "scagentkit.strategy.v1",
    rationale = "Explicit software starting plan for the selected raw-count child; review these finite settings before computation. This plan was not proposed by an AI.",
    risks = list("Parent selection is a conditional analysis scope, not independent biological validation.",
                 "Resolution 0.4 and bounded dimension/HVG settings are disclosed software starting choices, not a scientific optimum."),
    inferences = list(), qc = list(schema = "scagentkit.qc.v1",
      rationale = "Retain the complete frozen parent selection; no second filtering or doublet removal is requested.",
      risks = list("Previous parent QC provenance remains relevant; retained cells are not guaranteed to be biologically valid."),
      filters = list(list(op = "range", metric = "nFeature", min = 0,
                          max = nrow(counts), group = NULL))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
                    nfeatures = nfeatures, npcs = npcs, seed = 17L),
    pcs = list(method = "fixed", ndim = as.integer(min(20L, npcs))),
    batch = list(method = "none", reason = "Rebuild child PCA from raw counts; no parent corrected embedding or automatic correction is inherited."),
    clustering = list(resolution = 0.4, diagnostic_resolutions = NULL),
    umap = list(run = TRUE, n_neighbors = as.integer(min(30L, ncol(counts) - 1L))))
  if (cycle) result$cycle <- list(method = "none", reason = "Fresh child cycle diagnostics are for review; no regression is preapproved.")
  result
}

.sc_run_subcluster_score_source <- function(parent, origin, counts, kind) {
  name <- paste0(kind, "_diagnostics")
  artifact <- parent$state$files[[name]]
  if (is.null(artifact)) return(list(status = "not_recorded", action = "not_recomputed",
    interpretation = "Any existing source metadata are preserved as metadata only; no verified parent diagnostic artifact was supplied."))
  record <- .sc_run_get(parent$root, parent$state, name)
  if (kind == "cycle") .sc_run_cycle_verify(record) else .sc_run_doublet_verify(record)
  cells <- origin$selected_cells
  if (any(!cells %in% record$cell_ids) || !identical(rownames(counts), record$feature_ids) ||
      !identical(.sc_run_cycle_cell_counts(counts, cells), record$count_cell_hashes[cells]))
    stop("Saved parent ", kind, " evidence does not cover the selected raw-count scope exactly.", call. = FALSE)
  columns <- unname(unlist(record$summary$columns, use.names = FALSE))
  metadata <- parent$seu[[]]
  if (!length(columns) || any(!columns %in% names(metadata)) ||
      !is.data.frame(record$scores) || !"cell_id" %in% names(record$scores))
    stop("Saved parent ", kind, " score columns or cell-ID evidence are incomplete.", call. = FALSE)
  expected <- record$scores[match(cells, record$scores$cell_id), columns, drop = FALSE]
  actual <- metadata[cells, columns, drop = FALSE]
  rownames(expected) <- rownames(actual) <- cells
  if (!identical(actual, expected))
    stop("Parent ", kind, " metadata differ from their saved exact-ID score evidence.", call. = FALSE)
  list(status = "verified_parent_evidence", artifact_sha256 = artifact$sha256,
    evidence_hash = record$evidence_hash, source_scope = "parent_fixed_scoring_cohort",
    selected_scope_hash = origin$scope_hash, selected_cells = length(cells),
    columns = as.list(columns), diagnostics_status = record$summary$status,
    gene_set = if (kind == "cycle") record$summary$gene_set else NULL,
    action = "source_metadata_only; not_recomputed; no_filtering_or_regression_authority",
    interpretation = "Scores retain their original parent reference and applicability; they are not fresh child diagnostics or permission to remove cells/regress.")
}

.sc_run_subcluster_reference_snapshot <- function(parent, choices) {
  if (!identical(choices$reference, "inherit")) return(list(reference = NULL,
    options = .sc_run_reference_options(), provenance = list(status = "not_inherited")))
  if (is.null(parent$state$files$reference) || is.null(parent$state$files$annotation_evidence))
    stop("Reference inheritance requires a saved parent reference and its annotation evidence provenance.", call. = FALSE)
  options <- .sc_run_reference_options(parent$state$config$reference_review)
  recorded <- .sc_run_get(parent$root, parent$state, "annotation_evidence")$private$reference_provenance
  version <- recorded$source_version
  if (!is.character(version) || length(version) != 1L || is.na(version) || !nzchar(trimws(version)))
    stop("Reference inheritance requires an explicit saved parent source version.", call. = FALSE)
  reference <- .sc_run_get(parent$root, parent$state, "reference")
  if (is.character(reference) && length(reference) == 1L && !is.na(reference)) {
    if (!identical(recorded$source_file_status, "readable") ||
        !file.exists(reference) || dir.exists(reference) || nzchar(Sys.readlink(reference)) ||
        is.null(recorded$source_sha256) ||
        !identical(.sc_project_sha_file(reference), recorded$source_sha256))
      stop("Parent reference source changed or has no recorded source SHA256; inheritance is stale.", call. = FALSE)
    reference <- annot_load_reference(reference)
  }
  if (!is.data.frame(reference) || anyDuplicated(names(reference)))
    stop("Parent reference snapshot must be an unambiguous local marker data frame.", call. = FALSE)
  reference <- .validate_marker_reference(reference)
  source_path <- attr(reference, "source_path")
  if (!is.null(source_path)) {
    if (!identical(recorded$source_file_status, "readable") ||
        !is.character(source_path) || length(source_path) != 1L || is.na(source_path) ||
        !file.exists(source_path) || dir.exists(source_path) || nzchar(Sys.readlink(source_path)) ||
        is.null(recorded$source_sha256) ||
        !identical(.sc_project_sha_file(source_path), recorded$source_sha256))
      stop("Parent reference recorded source changed; inheritance is stale.", call. = FALSE)
    source_md5 <- attr(reference, "source_md5")
    if (!is.null(source_md5) && !identical(unname(tools::md5sum(source_path)), source_md5))
      stop("Parent reference snapshot and its recorded source differ; inheritance is stale.", call. = FALSE)
    # The child owns a data-frame snapshot. Parent source provenance is recorded
    # separately rather than making future child scoring read the parent file.
    attr(reference, "source_path") <- NULL
  }
  options$provenance$version <- version
  if (!is.null(recorded$source_sha256)) options$provenance$source_sha256 <- recorded$source_sha256
  options$provenance$preparation_note <- "Immutable snapshot inherited from the parent reference; candidates are derived again from the child's current markers and clusters."
  options <- .sc_run_reference_options(options)
  list(reference = reference, options = options, provenance = list(status = "inherited_snapshot",
    parent_artifact_sha256 = parent$state$files$reference$sha256,
    parent_evidence_sha256 = parent$state$files$annotation_evidence$sha256,
    snapshot_hash = .sc_run_hash(reference), source_version = version,
    source_sha256 = recorded$source_sha256,
    policy = "Child marker evidence and reference candidates are rederived; no parent cluster candidates, annotations or model history are imported."))
}

.sc_run_subcluster_strategy <- function(state, validated, evidence) {
  if (is.null(state$config$subcluster_origin)) return(invisible(TRUE))
  origin <- state$config$subcluster_origin
  .sc_run_subcluster_origin_verify(origin)
  choices <- .sc_run_subcluster_choices(state$config$subcluster_creation$choices)
  if (!identical(evidence$private$cell_ids, origin$selected_cells))
    stop("Child strategy evidence differs from its frozen exact cell selection.", call. = FALSE)
  keep <- if (!is.null(validated$selected_cells)) validated$selected_cells else validated$qc_validated$keep_cells
  .sc_project_ids(keep, "Approved child retained cell IDs")
  if (!identical(keep, origin$selected_cells[origin$selected_cells %in% keep]))
    stop("Child retained scope must be an ordered exact-ID subset of its frozen parent selection.", call. = FALSE)
  if (identical(choices$qc, "retain_selected") && !identical(keep, origin$selected_cells))
    stop("Child QC choice retain_selected prohibits a second cell filter; create a child with qc='review' to request an explicit centrally reviewed selection.", call. = FALSE)
  if (!is.null(validated$proposal$doublet) && !identical(validated$proposal$doublet$method, "keep"))
    stop("Child doublet refitting/removal is unsupported; the explicit choice is keep.", call. = FALSE)
  if (identical(choices$batch, "none") && !identical(validated$proposal$batch$method, "none"))
    stop("Child batch choice none prohibits correction; create a child with batch='review' for a fresh typed design review.", call. = FALSE)
  if (identical(choices$cycle, "none") && !is.null(validated$proposal$cycle) &&
      !identical(validated$proposal$cycle$method, "none"))
    stop("Child cycle choice none prohibits regression; fresh explicit recompute diagnostics are required.", call. = FALSE)
  invisible(TRUE)
}

.sc_run_subcluster_preflight <- function(proposal, counts, cycle_enabled) {
  .sc_run_strategy_fields(proposal,
    c("schema", "rationale", "risks", "inferences", "qc", "analysis", "pcs", "batch", "clustering", "umap"),
    optional = if (cycle_enabled) "cycle" else character(), name = "Child strategy proposal")
  if (!identical(proposal$schema, "scagentkit.strategy.v1"))
    stop("Unsupported child strategy schema.", call. = FALSE)
  settings <- .sc_run_strategy_fields(proposal$analysis,
    c("normalization_method", "scale_factor", "nfeatures", "npcs", "seed"), name = "Child analysis")
  if (!identical(settings$normalization_method, "LogNormalize"))
    stop("Child analysis supports LogNormalize only.", call. = FALSE)
  .sc_run_strategy_number(settings$scale_factor, "child scale_factor", 0, open_min = TRUE)
  expressed <- sum(Matrix::rowSums(counts > 0) > 0)
  nfeatures <- .sc_run_strategy_number(settings$nfeatures, "child nfeatures", 3,
    min(nrow(counts), expressed), integer = TRUE)
  npcs <- .sc_run_strategy_number(settings$npcs, "child npcs", 2, integer = TRUE)
  if (npcs >= min(nfeatures, ncol(counts)))
    stop("Requested child npcs must be below both selected cells and requested HVGs; no clipping is supported.", call. = FALSE)
  .sc_run_strategy_number(settings$seed, "child seed", 0, .Machine$integer.max, integer = TRUE)
  clustering <- .sc_run_strategy_fields(proposal$clustering, "resolution", "diagnostic_resolutions", "Child clustering")
  .sc_run_strategy_number(clustering$resolution, "child resolution", 0, 2, open_min = TRUE)
  resolutions <- clustering$diagnostic_resolutions
  if (is.list(resolutions) && is.null(names(resolutions))) resolutions <- unlist(resolutions, use.names = FALSE)
  if (!is.null(resolutions) && (!is.numeric(resolutions) || !length(resolutions) || length(resolutions) > 5L ||
      any(!is.finite(resolutions)) || any(resolutions <= 0 | resolutions > 2) || anyDuplicated(resolutions)))
    stop("Child diagnostic_resolutions must be at most five distinct finite values in (0,2].", call. = FALSE)
  pcs <- .sc_run_strategy_fields(proposal$pcs, "method", c("ndim", "threshold"), "Child PCs")
  if (identical(pcs$method, "fixed")) {
    .sc_run_strategy_fields(pcs, c("method", "ndim"), name = "Child fixed PCs")
    .sc_run_strategy_number(pcs$ndim, "child ndim", 2, npcs, integer = TRUE)
  } else if (pcs$method %in% c("computed_variance", "computed_top50")) {
    .sc_run_strategy_fields(pcs, c("method", "threshold"), name = "Child computed PCs")
    threshold <- .sc_run_strategy_number(pcs$threshold, "child PC threshold", 0, 1, open_min = TRUE, open_max = TRUE)
    if (identical(pcs$method, "computed_top50") && !threshold %in% c(.8, .85))
      stop("Child computed_top50 supports exact 0.80 or 0.85 only.", call. = FALSE)
  } else stop("Unsupported child PC method.", call. = FALSE)
  .sc_run_harmony_parameters(proposal$batch, retained = ncol(counts))
  umap <- .sc_run_strategy_fields(proposal$umap, c("run", "n_neighbors"), name = "Child UMAP")
  if (!is.logical(umap$run) || length(umap$run) != 1L || is.na(umap$run))
    stop("Child UMAP run must be TRUE or FALSE.", call. = FALSE)
  .sc_run_strategy_number(umap$n_neighbors, "child UMAP neighbors", 3, ncol(counts) - 1L, integer = TRUE)
  if (cycle_enabled && !is.null(proposal$cycle)) {
    choice <- .sc_run_strategy_fields(proposal$cycle, c("method", "reason"), name = "Child cycle")
    if (!is.character(choice$method) || length(choice$method) != 1L || is.na(choice$method) ||
        !choice$method %in% c("none", "full", "difference"))
      stop("Unsupported child cycle method.", call. = FALSE)
    .sc_run_strategy_text(choice$reason, "child cycle reason")
  }
  invisible(TRUE)
}

#' Create an independently reviewed raw-count child from exact parent clusters
#' @param parent_project Completed immutable parent project.
#' @param child_project New sibling project directory, outside the parent.
#' @param clusters One or more literal parent cluster IDs.
#' @param parent_scope_hash,expected_parent_revision Exact inspected parent scope.
#' @param strategy_proposal Optional complete typed strategy. NULL supplies an
#'   explicitly disclosed software starting plan for whole-strategy review.
#' @param choices Explicit QC, doublet, batch, cycle and reference policies.
#' @param cycle_diagnostics Fresh child cycle scoring options for recompute only.
#' @param annotation_column Fresh child label column, never a parent overwrite.
#' @param reviewer,reason Analyst identity and selection rationale.
#' @param request_id Stable literal creation identifier for retry/idempotence.
#' @param inherit_model Explicit TRUE to copy the parent's immutable provider,
#'   per-project budget and transfer policy into a new child. No keys or runtime
#'   callbacks are copied. Default FALSE creates a manual, zero-budget child.
#' @return Durable child status; no computation beyond local diagnostic evidence
#'   executes until the exact centralized strategy approval.
#' @export
sc_run_subcluster <- function(parent_project, child_project, clusters,
                              parent_scope_hash, expected_parent_revision,
                              strategy_proposal = NULL,
                              choices = list(qc = "retain_selected", doublet = "keep",
                                batch = "none", cycle = "none", reference = "none"),
                              cycle_diagnostics = NULL, annotation_column = "sc_subtype",
                              reviewer, reason, request_id, inherit_model = FALSE) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  .sc_run_review_hash_string(parent_scope_hash, "parent_scope_hash")
  request_id <- .sc_run_subcluster_request_id(request_id)
  choices <- .sc_run_subcluster_choices(choices)
  if (!identical(inherit_model, TRUE) && !identical(inherit_model, FALSE))
    stop("inherit_model must be TRUE or FALSE.", call. = FALSE)
  if (is.null(expected_parent_revision))
    stop("The exact inspected expected_parent_revision is required.", call. = FALSE)
  paths <- .sc_run_subcluster_paths(parent_project, child_project)
  owner <- .sc_run_lock(paths$parent); on.exit(.sc_run_release(paths$parent, owner), add = TRUE)
  parent <- .sc_run_subcluster_parent(paths$parent)
  model_policy <- if (inherit_model) list(inherit_model = TRUE,
    provider = .sc_run_provider_spec(parent$state$config$provider)$metadata,
    budget = parent$state$config$budget,
    allow_external = isTRUE(parent$state$config$review$allow_external)) else NULL
  .sc_run_qc_revision_check(parent$state, expected_parent_revision)
  origin <- .sc_run_subcluster_selection(parent, clusters)
  if (!identical(origin$parent_scope_hash, parent_scope_hash))
    stop("Parent cluster selection or scope hash changed; inspect the exact current selection.", call. = FALSE)
  .sc_run_subcluster_origin_verify(origin)
  parent_annotation_context <- .sc_run_child_parent_snapshot(parent, origin)
  cells <- origin$selected_cells
  if (length(cells) < 21L)
    stop("The supported child graph requires at least 21 selected cells; no silent resolution or neighbor fallback is available.", call. = FALSE)
  assay <- parent$state$config$assay
  counts <- .sc_project_layer(parent$seu, assay, parent$state$config$counts_layer, raw_counts = TRUE)
  if (any(!cells %in% colnames(counts))) stop("Parent raw counts lack selected cell IDs.", call. = FALSE)
  counts <- counts[, cells, drop = FALSE]
  metadata <- parent$seu[[]][cells, , drop = FALSE]
  if (!identical(rownames(metadata), cells)) stop("Selected metadata cell order differs from exact input IDs.", call. = FALSE)
  child_cluster <- "sc_subcluster_clusters"
  if (child_cluster %in% names(metadata)) stop("Child cluster output column already exists in parent metadata; choose a parent without that conflicting reserved column.", call. = FALSE)
  source_cluster <- "sc_parent_cluster"
  while (source_cluster %in% names(metadata)) source_cluster <- paste0(source_cluster, "_source")
  metadata[[source_cluster]] <- unname(parent$membership[cells])
  child <- Seurat::CreateSeuratObject(counts = counts, assay = assay,
    min.cells = 0, min.features = 0, meta.data = metadata)
  if (!identical(colnames(child), cells) || !identical(rownames(child), rownames(counts)))
    stop("Child reconstruction would rename literal feature/cell IDs; no child was created.", call. = FALSE)
  # Restore the exact source metadata types/levels by ID; generated parent
  # cluster labels stay source facts and are never used as child active Idents.
  child <- SeuratObject::AddMetaData(child, metadata = metadata)
  SeuratObject::Idents(child) <- factor(rep("unassigned", length(cells)))
  if (!identical(child[[]][cells, names(metadata), drop = FALSE], metadata) ||
      length(child@reductions) || length(child@graphs) ||
      !identical(SeuratObject::Layers(child[[assay]]), "counts"))
    stop("Fresh child input must preserve exact metadata and contain only raw counts without parent reductions/graphs.", call. = FALSE)
  .sc_run_annotation_target(child, annotation_column, child_cluster)
  context <- parent$state$config$context
  source_context <- list(parent_project_id = parent$state$project_id,
    parent_revision = parent$state$revision, scope_hash = origin$scope_hash,
    selected_clusters = as.list(origin$selected_clusters), selected_cells = length(cells),
    source_cluster_column = source_cluster, choices = choices,
    policy = "Selected raw counts; parent cluster/annotation metadata are source context, not child truth. No parent normalization, embedding, graph, or cluster result is reused.")
  note <- paste("Scoped child from a completed parent; selected", length(cells),
    "cells. Inheritance choices:", paste(paste(names(choices), unlist(choices), sep = "="), collapse = ", "),
    ". Parent cluster labels are source metadata only; child results require new review.")
  context$notes <- if (is.null(context$notes)) note else paste(context$notes, note, sep = "\n")
  context <- .sc_run_context(context, child)
  if (identical(choices$cycle, "recompute")) {
    if (is.null(cycle_diagnostics) || identical(cycle_diagnostics, FALSE))
      stop("cycle='recompute' requires explicit fresh child cycle_diagnostics and a fresh output prefix.", call. = FALSE)
    cycle_diagnostics <- .sc_run_cycle_options(context, cycle_diagnostics)
    if (any(.sc_run_cycle_columns(cycle_diagnostics$column_prefix) %in% names(metadata)))
      stop("Fresh child cycle diagnostics need a new column_prefix; parent score columns must be preserved.", call. = FALSE)
  } else if (!is.null(cycle_diagnostics) && !identical(cycle_diagnostics, FALSE))
    stop("Child cycle_diagnostics require the explicit cycle='recompute' choice.", call. = FALSE)
  inherited <- .sc_run_subcluster_reference_snapshot(parent, choices)
  score_sources <- list(cycle = .sc_run_subcluster_score_source(parent, origin, counts, "cycle"),
                        doublet = .sc_run_subcluster_score_source(parent, origin, counts, "doublet"))
  software_plan <- is.null(strategy_proposal)
  if (software_plan) strategy_proposal <- .sc_run_subcluster_software_plan(counts,
    !is.null(cycle_diagnostics) && !identical(cycle_diagnostics, FALSE))
  # Reuse the coordinator's exact field/number validators before publication.
  # Actual QC effects, subset-dependent rank and fresh cycle applicability are
  # evaluated once in the normal saved strategy evidence/review path.
  .sc_run_subcluster_preflight(strategy_proposal, counts,
    !is.null(cycle_diagnostics) && !identical(cycle_diagnostics, FALSE))
  qc_preflight <- .sc_run_qc_validate(strategy_proposal$qc,
    .sc_run_qc_evidence(child, context, assay, "counts"))
  if (identical(choices$qc, "retain_selected") && !setequal(qc_preflight$keep_cells, cells))
    stop("Child QC choice retain_selected prohibits a second filter; request qc='review' explicitly.", call. = FALSE)
  if (identical(choices$batch, "none") && !identical(strategy_proposal$batch$method, "none"))
    stop("Child batch choice none requires a none strategy; request batch='review' explicitly.", call. = FALSE)
  payload <- list(schema = "scagentkit.subcluster-create-request.v1", origin = origin,
    parent_annotation_context = parent_annotation_context,
    context = context, choices = choices, strategy_proposal = strategy_proposal,
    plan_source = if (software_plan) "software_starting_plan" else "manual_typed_strategy",
    cycle_diagnostics = cycle_diagnostics, annotation_column = annotation_column,
    child_cluster_column = child_cluster, source_cluster_column = source_cluster,
    reference = inherited$provenance, reference_review = inherited$options,
    source_scores = score_sources, reviewer = reviewer, reason = reason,
    child_project = paths$child)
  creation <- list(schema = "scagentkit.subcluster-creation.v1", request_id = request_id,
    request_hash = .sc_run_hash(payload), choices = choices, reviewer = reviewer, reason = reason,
    plan_source = payload$plan_source, source_context = source_context,
    parent_annotation_context = parent_annotation_context,
    reference = inherited$provenance, source_scores = score_sources,
    child_cluster_column = child_cluster, source_cluster_column = source_cluster)
  if (inherit_model) {
    payload$model_policy <- model_policy
    creation$request_hash <- .sc_run_hash(payload)
    creation$model_policy <- model_policy
  }
  if (!dir.exists(paths$child) && !dir.create(paths$child, showWarnings = FALSE))
    stop("Child directory could not be created.", call. = FALSE)
  child_owner <- .sc_run_lock(paths$child)
  on.exit(.sc_run_release(paths$child, child_owner), add = TRUE, after = FALSE)
  receipt_path <- file.path(paths$child, ".subcluster-creation.rds")
  if (file.exists(receipt_path)) {
    receipt <- readRDS(receipt_path)
    if (!identical(receipt$schema, "scagentkit.subcluster-initialization.v1") ||
        !identical(receipt$origin, origin) || !identical(receipt$creation, creation))
      stop("Existing child request, settings or frozen origin differ; reuse of its path is refused.", call. = FALSE)
    if (file.exists(file.path(paths$child, "state.rds"))) {
      saved <- .sc_run_load(paths$child)
      if (!identical(saved$config$subcluster_origin, origin) ||
          !identical(saved$config$subcluster_creation, creation))
        stop("Existing child state differs from its creation request.", call. = FALSE)
      return(sc_run_inspect(paths$child))
    }
  } else {
    if (length(setdiff(list.files(paths$child, all.files = TRUE, no.. = TRUE), ".run-lock")))
      stop("Child directory contains foreign files; no creation was performed.", call. = FALSE)
    .sc_run_atomic(list(schema = "scagentkit.subcluster-initialization.v1", origin = origin,
      creation = creation), receipt_path)
  }
  .sc_run_crash("subcluster_create:receipt")
  .sc_run_subcluster_check_parent(origin)
  sc_run(child, paths$child, context = context,
    provider = if (inherit_model) model_policy$provider else NULL, chat_fn = NULL,
    budget = if (inherit_model) model_policy$budget else 0,
    review = list(allow_external = if (inherit_model) model_policy$allow_external else FALSE), assay = assay,
    counts_layer = "counts", normalized_layer = "data", cluster_column = child_cluster,
    reference = inherited$reference, reference_review = inherited$options,
    annotation_column = annotation_column, strategy = TRUE,
    strategy_proposal = strategy_proposal, cycle_diagnostics = cycle_diagnostics,
    subcluster_origin = origin, subcluster_creation = creation,
    .subcluster_lock_owner = child_owner)
}
