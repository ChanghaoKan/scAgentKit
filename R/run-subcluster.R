# Scoped child authority and derived-parent output. The completed parent is read
# only; neither numeric cluster names nor captured row positions are mappings.
.sc_run_subcluster_id <- function(value, name = "request_id") {
  .sc_project_string(value, name)
  if (nchar(value, type = "bytes") > 200L || !grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", value))
    stop(name, " must be a bounded literal identifier without a path.", call. = FALSE)
  value
}
.sc_run_subcluster_paths <- function(parent, child) {
  parent <- .sc_run_root(parent)
  .sc_project_string(child, "child_project")
  expanded <- path.expand(child)
  link <- Sys.readlink(expanded)
  if (basename(expanded) %in% c(".", "..", "") || (!is.na(link) && nzchar(link)))
    stop("Child project must be a new real directory outside its parent.", call. = FALSE)
  directory <- normalizePath(dirname(expanded), mustWork = TRUE)
  child <- file.path(directory, basename(expanded))
  if (identical(parent, child) || startsWith(child, paste0(parent, "/")) ||
      startsWith(parent, paste0(child, "/")))
    stop("Parent and child directories must be separate; never write inside the parent.", call. = FALSE)
  if (file.exists(child) && !dir.exists(child)) stop("Child project path is not a directory.", call. = FALSE)
  list(parent = parent, child = child)
}
.sc_run_subcluster_output <- function(root, state) {
  if (!identical(state$status, "complete") || !identical(state$stage, "complete"))
    stop("A completed, reviewed parent or child output is required.", call. = FALSE)
  record <- state$files[["output:output/seurat.rds"]]
  if (is.null(record) || !identical(record$path, "output/seurat.rds") ||
      !identical(state$output$seurat, file.path(root, record$path)))
    stop("Completed output is not the journal-bound Seurat artifact.", call. = FALSE)
  path <- file.path(root, record$path)
  if (!file.exists(path) || nzchar(Sys.readlink(path)) ||
      !identical(.sc_project_sha_file(path), record$sha256))
    stop("Completed Seurat output changed; stale scope rejected.", call. = FALSE)
  list(seu = .sc_project_unwrap(readRDS(path)), record = record)
}
.sc_run_subcluster_parent <- function(root, cluster_column = NULL) {
  root <- .sc_run_root(root)
  state <- .sc_run_load(root, verify_subcluster = FALSE)
  if (!is.null(state$config$subcluster_origin))
    stop("This increment supports one parent-to-child level; nested children are not supported.", call. = FALSE)
  output <- .sc_run_subcluster_output(root, state)
  seu <- output$seu; cells <- colnames(seu)
  .sc_project_ids(cells, "Parent literal cell IDs")
  metadata <- seu[[]]
  .sc_project_ids(rownames(metadata), "Parent metadata IDs")
  if (!setequal(cells, rownames(metadata)) || anyDuplicated(names(metadata)))
    stop("Parent metadata identity is missing, duplicated or ambiguous.", call. = FALSE)
  if (is.null(cluster_column)) cluster_column <- state$config$cluster_column
  .sc_project_string(cluster_column, "cluster_column")
  if (sum(names(metadata) == cluster_column) != 1L)
    stop("Explicit parent cluster column is missing or ambiguous.", call. = FALSE)
  membership <- stats::setNames(as.character(metadata[cells, cluster_column]), cells)
  if (anyNA(membership) || any(!nzchar(membership)))
    stop("Parent membership contains missing or empty cluster IDs.", call. = FALSE)
  counts <- .sc_project_layer(seu, state$config$assay, state$config$counts_layer, raw_counts = TRUE)
  if (!setequal(colnames(counts), cells)) stop("Parent raw-count layer does not cover the complete literal cell scope.", call. = FALSE)
  counts <- counts[, cells, drop = FALSE]
  binding <- list(project_id = state$project_id, input_hash = state$input_hash,
    revision = state$revision, history_head = .sc_run_public(state)$history_head,
    state_sha256 = .sc_project_sha_file(file.path(root, "state.rds")),
    output_sha256 = output$record$sha256, cluster_column = cluster_column,
    membership_hash = .sc_run_hash(data.frame(cell_id = cells, cluster = membership, stringsAsFactors = FALSE)),
    parent_cells_hash = .sc_run_hash(cells), assay = state$config$assay,
    counts_layer = state$config$counts_layer, raw_counts_hash = .sc_run_hash(counts))
  list(root = root, state = state, seu = seu, cells = cells, membership = membership,
       counts = counts, binding = binding)
}
.sc_run_subcluster_selection <- function(parent, clusters) {
  if (!is.character(clusters) || !length(clusters) || anyNA(clusters) ||
      any(!nzchar(clusters)) || anyDuplicated(clusters))
    stop("Select one or more unique literal cluster IDs; numeric positions, duplicates and empty selection are rejected.", call. = FALSE)
  if (any(!clusters %in% parent$membership))
    stop("Selected cluster ID is absent from this exact parent membership.", call. = FALSE)
  selected <- parent$cells[parent$membership %in% clusters]
  .sc_project_ids(selected, "Selected literal cell IDs")
  origin <- list(schema = "scagentkit.subcluster.origin.v1", parent_project = parent$root,
    parent = parent$binding, parent_scope_hash = .sc_run_hash(parent$binding),
    selected_clusters = unname(clusters), selected_cells = selected,
    selected_cells_hash = .sc_run_hash(selected),
    selected_cell_set_hash = .sc_run_hash(sort(enc2utf8(selected), method = "radix")),
    raw_counts_hash = .sc_run_hash(parent$counts[, selected, drop = FALSE]),
    source_context_hash = .sc_run_hash(parent$state$config$context))
  origin$scope_hash <- .sc_run_hash(origin)
  origin
}
.sc_run_subcluster_origin_verify <- function(origin) {
  fields <- c("schema", "parent_project", "parent", "parent_scope_hash", "selected_clusters",
    "selected_cells", "selected_cells_hash", "selected_cell_set_hash", "raw_counts_hash",
    "source_context_hash", "scope_hash")
  if (!is.list(origin) || anyDuplicated(names(origin)) || !setequal(names(origin), fields) ||
      !identical(origin$schema, "scagentkit.subcluster.origin.v1"))
    stop("Invalid frozen child origin.", call. = FALSE)
  .sc_project_ids(origin$selected_cells, "Frozen selected cell IDs")
  if (!identical(origin$scope_hash, .sc_run_hash(origin[setdiff(names(origin), "scope_hash")])) ||
      !identical(origin$parent_scope_hash, .sc_run_hash(origin$parent)) ||
      !identical(origin$selected_cells_hash, .sc_run_hash(origin$selected_cells)) ||
      !identical(origin$selected_cell_set_hash, .sc_run_hash(sort(enc2utf8(origin$selected_cells), method = "radix"))))
    stop("Frozen child origin/hash changed.", call. = FALSE)
  invisible(origin)
}
.sc_run_subcluster_check_parent <- function(origin) {
  .sc_run_subcluster_origin_verify(origin)
  parent <- .sc_run_subcluster_parent(origin$parent_project, origin$parent$cluster_column)
  current <- .sc_run_subcluster_selection(parent, origin$selected_clusters)
  if (!identical(origin, current))
    stop("Parent input, revision, output or cluster scope changed; stale child authority rejected.", call. = FALSE)
  parent
}
.sc_run_subcluster_guard <- function(root, state) {
  origin <- state$config$subcluster_origin
  if (is.null(origin)) return(invisible(TRUE))
  .sc_run_subcluster_check_parent(origin)
  .sc_run_subcluster_paths(origin$parent_project, root)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) || is.null(state$files$subcluster_origin) ||
      is.null(state$files$subcluster_creation) ||
      !identical(.sc_run_get(root, state, "subcluster_origin"), origin) ||
      !identical(.sc_run_get(root, state, "subcluster_creation"), state$config$subcluster_creation))
    stop("Child creation or origin authority changed.", call. = FALSE)
  input <- .sc_run_get(root, state, "input")
  if (!identical(colnames(input), origin$selected_cells) ||
      !identical(.sc_run_hash(.sc_project_layer(input, state$config$assay, state$config$counts_layer,
        raw_counts = TRUE)[, origin$selected_cells, drop = FALSE]), origin$raw_counts_hash))
    stop("Child raw-count input or literal IDs differ from the frozen parent selection.", call. = FALSE)
  invisible(TRUE)
}
.sc_run_subcluster_origin_public <- function(origin) {
  .sc_run_subcluster_origin_verify(origin)
  list(schema = origin$schema, parent_project_id = origin$parent$project_id,
    parent_input_hash = origin$parent$input_hash, parent_revision = origin$parent$revision,
    parent_scope_hash = origin$parent_scope_hash, parent_output_hash = origin$parent$output_sha256,
    parent_cluster_column = origin$parent$cluster_column,
    selected_clusters = .sc_project_array(origin$selected_clusters), selected_cells = length(origin$selected_cells),
    selected_cell_scope_hash = origin$scope_hash, selected_cells_hash = origin$selected_cells_hash,
    source_context_hash = origin$source_context_hash,
    notice = "Parent labels identify source selection only; they are not child biological truth. Literal IDs remain local.")
}

#' Inspect exact completed-parent cluster scope without changing files
#' @param parent_project Completed server-side parent run.
#' @param clusters Optional explicit literal cluster labels to preview.
#' @param cluster_column Optional explicit parent membership column.
#' @return Immutable parent fingerprints and cluster counts, never positional mappings.
#' @export
sc_run_subcluster_scope <- function(parent_project, clusters = NULL, cluster_column = NULL) {
  parent <- .sc_run_subcluster_parent(parent_project, cluster_column)
  labels <- sort(unique(enc2utf8(parent$membership)), method = "radix")
  selected <- if (is.null(clusters)) NULL else .sc_run_subcluster_selection(parent, clusters)
  list(schema = "scagentkit.subcluster.parent.v1", parent_project_id = parent$state$project_id,
    input_hash = parent$state$input_hash, expected_parent_revision = parent$state$revision,
    parent_scope_hash = .sc_run_hash(parent$binding), parent_output_hash = parent$binding$output_sha256,
    cluster_column = parent$binding$cluster_column, total_cells = length(parent$cells),
    context = parent$state$config$context[c("species", "tissue")],
    clusters = lapply(labels, function(label) list(clusterId = label, cell_count = sum(parent$membership == label))),
    selected = if (is.null(selected)) NULL else list(clusters = .sc_project_array(selected$selected_clusters),
      count = length(selected$selected_cells), selection_hash = selected$scope_hash),
    limitations = list("Raw counts are selected by exact literal cell IDs. Child normalization, HVGs, PCA and clusters are calculated afresh under one central strategy approval.",
      "Default policy retains selected cells; no second doublet fit, inherited correction or biological guarantee.",
      "At least 21 selected cells are needed by the current fixed k=20 neighbor pipeline."))
}
.sc_run_subcluster_workspace <- function(parent, workspace) {
  parent <- .sc_run_root(parent); workspace <- .sc_run_root(workspace)
  if (identical(parent, workspace) || startsWith(workspace, paste0(parent, "/")) ||
      startsWith(parent, paste0(workspace, "/")))
    stop("Child workspace must be separate from the immutable parent.", call. = FALSE)
  workspace
}

#' List locally registered children belonging to one immutable parent
#' @param parent_project Completed parent run.
#' @param workspace Operator-selected existing child workspace, outside the parent.
#' @return Verified child records; local paths are for R/IPC and must not be accepted as browser arguments.
#' @export
sc_run_subcluster_list <- function(parent_project, workspace) {
  parent <- .sc_run_subcluster_parent(parent_project)
  workspace <- .sc_run_subcluster_workspace(parent$root, workspace)
  directories <- list.dirs(workspace, recursive = FALSE, full.names = TRUE)
  children <- list()
  for (directory in directories) {
    if (nzchar(Sys.readlink(directory)) || !file.exists(file.path(directory, "state.rds"))) next
    state <- .sc_run_load(directory, verify_subcluster = FALSE)
    origin <- state$config$subcluster_origin
    if (is.null(origin)) next
    .sc_run_subcluster_origin_verify(origin)
    if (!identical(origin$parent_project, parent$root) ||
        !identical(origin$parent$project_id, parent$state$project_id)) next
    result <- sc_run_subcluster_inspect(directory)
    children[[length(children) + 1L]] <- list(project_id = state$project_id, project_dir = directory,
      status = state$status, stage = state$stage, revision = state$revision,
      origin = result$origin, parent_current = result$parent_current,
      applications = result$applications)
  }
  identifiers <- vapply(children, `[[`, character(1), "project_id")
  if (anyDuplicated(identifiers)) stop("Child project IDs are duplicated; registry resolution rejected.", call. = FALSE)
  list(schema = "scagentkit.subcluster.registry.v1", parent_project_id = parent$state$project_id,
       parent_scope_hash = .sc_run_hash(parent$binding), children = children)
}
.sc_run_subcluster_resolve <- function(parent_project, workspace, child_id) {
  .sc_project_string(child_id, "child_id")
  children <- sc_run_subcluster_list(parent_project, workspace)$children
  chosen <- Filter(function(child) identical(child$project_id, child_id), children)
  if (length(chosen) != 1L) stop("Child ID is absent or foreign to this registered parent workspace.", call. = FALSE)
  chosen[[1L]]$project_dir
}

.sc_run_subcluster_fields <- function(column) {
  .sc_project_string(column, "column")
  if (nchar(column, type = "bytes") > 120L) stop("Subtype column name is too long.", call. = FALSE)
  c(label = column, confidence = paste0(column, "_confidence"),
    rationale = paste0(column, "_rationale"), source_child = paste0(column, "_source_child"),
    child_cluster = paste0(column, "_child_cluster"))
}
.sc_run_subcluster_copy <- function(parent_seu, child_seu, expected_cells, column,
  child_project_id, child_cluster_column, child_annotation_column) {
  parent_seu <- .sc_project_unwrap(parent_seu); child_seu <- .sc_project_unwrap(child_seu)
  parent_ids <- colnames(parent_seu); child_ids <- colnames(child_seu)
  .sc_project_ids(parent_ids, "Parent literal cell IDs")
  .sc_project_ids(child_ids, "Child literal cell IDs")
  .sc_project_ids(expected_cells, "Approved retained child IDs")
  if (!setequal(child_ids, expected_cells) || any(!expected_cells %in% parent_ids))
    stop("Child has missing, duplicate or foreign cells relative to the exact approved retained scope.", call. = FALSE)
  parent_meta <- parent_seu[[]]; child_meta <- child_seu[[]]
  .sc_project_ids(rownames(parent_meta), "Parent metadata cell IDs")
  .sc_project_ids(rownames(child_meta), "Child metadata cell IDs")
  if (!setequal(rownames(parent_meta), parent_ids) || !setequal(rownames(child_meta), child_ids) ||
      anyDuplicated(names(parent_meta)) || anyDuplicated(names(child_meta)))
    stop("Parent/child metadata identity is incomplete or ambiguous.", call. = FALSE)
  fields <- .sc_run_subcluster_fields(column)
  if (any(fields %in% names(parent_meta)))
    stop("Subtype target or companion columns already exist; choose a fresh column.", call. = FALSE)
  sources <- c(label = child_annotation_column, confidence = paste0(child_annotation_column, "_confidence"),
    rationale = paste0(child_annotation_column, "_rationale"), child_cluster = child_cluster_column)
  if (!all(sources %in% names(child_meta))) stop("Reviewed child annotation or cluster columns are missing.", call. = FALSE)
  for (name in sources) {
    value <- child_meta[child_ids, name]
    if (!(is.character(value) || is.factor(value)) || anyNA(value) || any(!nzchar(as.character(value))))
      stop("Child reviewed labels or provenance contain empty/missing values.", call. = FALSE)
  }
  .sc_project_string(child_project_id, "child_project_id")
  before <- .sc_run_hash(parent_seu)
  result <- parent_seu; index <- match(parent_ids, child_ids)
  for (field in names(fields)) {
    value <- rep(NA_character_, length(parent_ids)); retained <- which(!is.na(index))
    value[retained] <- if (field == "source_child") child_project_id else
      as.character(child_meta[child_ids[index[retained]], sources[[field]]])
    result[[fields[[field]]]] <- stats::setNames(value, parent_ids)
  }
  if (!identical(colnames(result), parent_ids) ||
      !identical(result[[]][parent_ids, names(parent_meta), drop = FALSE], parent_meta[parent_ids, , drop = FALSE]) ||
      !identical(.sc_run_hash(parent_seu), before))
    stop("Derived annotation changed original parent identity or metadata.", call. = FALSE)
  restored <- result
  for (field in fields) restored[[field]] <- NULL
  # Public metadata assignment can reorder data.frame attributes without
  # changing any value. Compare the restored whole object, including every
  # assay/reduction/graph, while the original's byte hash above guards mutation.
  if (!identical(restored, parent_seu)) stop("Derived copy changed parent data beyond new subtype columns.", call. = FALSE)
  list(seu = result, fields = fields, retained_cells = child_ids)
}

.sc_run_subcluster_integration <- function(root) {
  path <- file.path(root, "reintegration", "state.rds")
  empty <- list(schema = "scagentkit.subcluster.integration.v1", revision = 0L,
    history = list(), applications = list(), undos = list(), requests = list(), files = list())
  if (!file.exists(path)) return(empty)
  if (nzchar(Sys.readlink(path))) stop("Integration state cannot be a symlink.", call. = FALSE)
  envelope <- readRDS(path)
  if (!identical(envelope$hash, .sc_run_hash(envelope$state)) ||
      !identical(envelope$state$schema, empty$schema))
    stop("Integration journal checksum mismatch.", call. = FALSE)
  journal <- envelope$state; previous <- strrep("0", 64)
  for (i in seq_along(journal$history)) {
    event <- journal$history[[i]]; hash <- event$hash; event$hash <- NULL
    if (!identical(event$sequence, i) || !identical(event$previous_hash, previous) ||
        !identical(hash, .sc_run_hash(event))) stop("Integration history hash chain changed.", call. = FALSE)
    previous <- hash
  }
  if (!identical(journal$revision, length(journal$history))) stop("Integration journal revision changed.", call. = FALSE)
  for (record in journal$files) {
    if (!is.character(record$path) || !grepl("^reintegration/[A-Za-z0-9_.-]+\\.rds$", record$path))
      stop("Invalid derived output path in integration journal.", call. = FALSE)
    file <- file.path(root, record$path)
    if (!file.exists(file) || nzchar(Sys.readlink(file)) || !identical(.sc_project_sha_file(file), record$sha256))
      stop("A saved derived output changed; integration authority is stale.", call. = FALSE)
  }
  journal
}
.sc_run_subcluster_integration_event <- function(journal, action, details) {
  event <- list(sequence = length(journal$history) + 1L, created_at = .sc_run_time(),
    action = action, details = details,
    previous_hash = if (length(journal$history)) tail(journal$history, 1L)[[1L]]$hash else strrep("0", 64))
  event$hash <- .sc_run_hash(event)
  journal$history[[length(journal$history) + 1L]] <- event
  journal$revision <- length(journal$history)
  journal
}
.sc_run_subcluster_integration_save <- function(root, journal) {
  .sc_run_atomic(list(schema = "scagentkit.subcluster.integration-state.v1",
    hash = .sc_run_hash(journal), state = journal), file.path(root, "reintegration", "state.rds"))
  .sc_run_atomic(list(schema = journal$schema, revision = journal$revision,
    applications = unname(journal$applications), undos = unname(journal$undos),
    history = journal$history), file.path(root, "reintegration", "history.json"), json = TRUE)
  invisible(journal)
}
.sc_run_subcluster_child_review <- function(root, state) {
  .sc_run_subcluster_guard(root, state)
  if (!identical(state$implementation_hash, .sc_run_implementation()))
    stop("Child implementation changed; apply requires its frozen tested runtime.", call. = FALSE)
  .sc_run_require_approval(state, "annotation")
  review <- .sc_run_annotation_review_verify(root, state)
  output <- .sc_run_subcluster_output(root, state)
  origin <- state$config$subcluster_origin
  strategy <- .sc_run_strategy_review_verify(root, state)
  for (key in names(strategy$details$dependency_hashes))
    if (!identical(state$strategy_authorizations[[key]]$dependency_hash, strategy$details$dependency_hashes[[key]]) ||
        !any(vapply(state$approvals, function(decision) identical(decision$kind, "strategy") &&
          identical(decision$decision_id, state$strategy_authorizations[[key]]$decision_id) &&
          identical(decision$input_hash, state$input_hash) &&
          identical(decision$dependency_hashes[[key]], strategy$details$dependency_hashes[[key]]), logical(1))))
      stop("Executed child strategy component authorization is missing or stale.", call. = FALSE)
  validated <- .sc_run_get(root, state, "strategy_validated")
  expected <- if (!is.null(validated$selected_cells)) validated$selected_cells else validated$qc_validated$keep_cells
  .sc_project_ids(expected, "Approved retained selected cells")
  if (any(!expected %in% origin$selected_cells) ||
      !setequal(expected, colnames(output$seu)))
    stop("Completed child has missing or foreign cells relative to its approved retained selection.", call. = FALSE)
  proposal <- .sc_run_get(root, state, "annotation_validated")
  rebuilt <- .sc_run_annotation_apply(.sc_run_get(root, state, "analysis"), proposal,
    state$config$annotation_column)
  cells <- colnames(output$seu)
  fields <- c(state$config$cluster_column, state$config$annotation_column,
    paste0(state$config$annotation_column, c("_confidence", "_rationale")))
  if (!identical(rebuilt[[]][cells, fields, drop = FALSE], output$seu[[]][cells, fields, drop = FALSE]))
    stop("Child labels differ from the exact executed annotation approval.", call. = FALSE)
  input <- .sc_run_get(root, state, "input")
  original <- .sc_project_layer(input, state$config$assay, state$config$counts_layer, raw_counts = TRUE)[, cells, drop = FALSE]
  current <- .sc_project_layer(output$seu, state$config$assay, state$config$counts_layer, raw_counts = TRUE)
  current <- current[, cells, drop = FALSE]
  if (!identical(.sc_run_hash(original), .sc_run_hash(current)))
    stop("Child raw counts changed after selection.", call. = FALSE)
  decision <- state$approvals[[state$approved$hash]]
  authorized <- list(kind = "annotation", input_hash = state$input_hash,
    proposal_hash = state$approved$hash, review_hash = review$hash,
    config_hash = state$config_hash, implementation_hash = state$implementation_hash,
    parameters_hash = review$parameters_hash, rules_hash = review$rules_hash,
    cell_scope_hash = review$cell_scope_hash, target_column = review$target_column)
  if (!all(vapply(names(authorized), function(name) identical(decision[[name]], authorized[[name]]), logical(1))))
    stop("Executed child annotation decision is foreign or differs from its current exact approval.", call. = FALSE)
  annotation_hash <- .sc_run_hash(list(project_id = state$project_id, input_hash = state$input_hash,
    config_hash = state$config_hash, origin_scope_hash = origin$scope_hash,
    decision = decision, review_hash = review$hash, evidence_hash = review$evidence_hash,
    output_sha256 = output$record$sha256,
    labels = data.frame(cell_id = cells, output$seu[[]][cells, fields, drop = FALSE],
      row.names = NULL, check.names = FALSE),
    reference = state$files$reference, strategy_hash = strategy$hash))
  list(seu = output$seu, output = output$record, expected_cells = expected,
    annotation_hash = annotation_hash, decision = decision, review = review)
}
.sc_run_subcluster_snapshot <- function(root, state, parent, child, journal, column, outside, supersedes) {
  if (!identical(outside, "NA")) stop("This version supports only explicit outside='NA'.", call. = FALSE)
  fields <- .sc_run_subcluster_fields(column)
  if (any(fields %in% names(parent$seu[[]]))) stop("Parent target or companion column already exists.", call. = FALSE)
  active <- Filter(function(application) isTRUE(application$active) && identical(application$column, column), journal$applications)
  if (is.null(supersedes)) {
    if (length(active)) stop("This child already has an active application to this column; explicitly supersede it or choose a fresh column.", call. = FALSE)
  } else {
    .sc_run_subcluster_id(supersedes, "supersedes")
    prior <- journal$applications[[supersedes]]
    if (is.null(prior) || !isTRUE(prior$active) || !identical(prior$column, column) ||
        !identical(prior$child_project_id, state$project_id) ||
        !identical(prior$origin_scope_hash, state$config$subcluster_origin$scope_hash) || length(active) != 1L)
      stop("Supersedes must identify this child's exact current active application and target column.", call. = FALSE)
  }
  result <- list(project_id = state$project_id, input_hash = state$input_hash,
    expected_revision = state$revision, parent_scope_hash = state$config$subcluster_origin$parent_scope_hash,
    expected_parent_revision = parent$state$revision, annotation_hash = child$annotation_hash,
    column = column, outside = outside, supersedes = supersedes)
  result$apply_hash <- .sc_run_hash(list(authority = result, origin_scope_hash = state$config$subcluster_origin$scope_hash,
    integration_revision = journal$revision, parent_output_sha256 = parent$binding$output_sha256,
    child_output_sha256 = child$output$sha256, retained_cell_scope_hash = .sc_run_hash(child$expected_cells), fields = fields))
  result$selected_cells <- length(state$config$subcluster_origin$selected_cells)
  result$retained_cells <- length(child$expected_cells)
  result$excluded_selected_cells <- result$selected_cells - result$retained_cells
  result$target_columns <- as.list(unname(fields))
  result$child_output_sha256 <- child$output$sha256
  result$integration_revision <- journal$revision
  result
}

#' Inspect child provenance and derived-parent application authority
#' @param child_project Scoped child project.
#' @param column Fresh subtype column on the derived parent.
#' @param outside Explicit NA policy for every cell outside the approved retained child.
#' @param supersedes Optional exact own previous active application to replace in a new version.
#' @return Child state, frozen provenance, current applicability, history and exact apply snapshot.
#' @export
sc_run_subcluster_inspect <- function(child_project, column = "sc_subtype", outside = "NA", supersedes = NULL) {
  root <- .sc_run_root(child_project)
  state <- .sc_run_load(root, verify_subcluster = FALSE)
  if (is.null(state$config$subcluster_origin)) stop("This is not a scoped child project.", call. = FALSE)
  origin <- state$config$subcluster_origin
  .sc_run_subcluster_origin_verify(origin)
  if (!identical(.sc_run_get(root, state, "subcluster_origin"), origin)) stop("Child origin artifact changed.", call. = FALSE)
  journal <- .sc_run_subcluster_integration(root)
  parent <- tryCatch(.sc_run_subcluster_check_parent(origin), error = identity)
  current <- !inherits(parent, "error")
  answer <- list(schema = "scagentkit.subcluster.child.v1", run = .sc_run_public(state),
    origin = .sc_run_subcluster_origin_public(origin), parent_current = current,
    parent_error = if (current) NULL else conditionMessage(parent),
    integration_revision = journal$revision, applications = unname(journal$applications),
    undos = unname(journal$undos), active_application_id = NULL,
    apply_snapshot = NULL, apply_error = NULL, review_error = NULL)
  if (current) {
    full <- tryCatch(sc_run_inspect(root), error = identity)
    if (inherits(full, "error")) answer$review_error <- conditionMessage(full)
    else answer$run <- full
  }
  active <- Filter(function(application) isTRUE(application$active) && identical(application$column, column), journal$applications)
  if (length(active) == 1L) answer$active_application_id <- active[[1L]]$application_id
  if (current && identical(state$status, "complete")) {
    snapshot <- tryCatch({
      child <- .sc_run_subcluster_child_review(root, state)
      .sc_run_subcluster_snapshot(root, state, parent, child, journal, column, outside, supersedes)
    }, error = identity)
    if (inherits(snapshot, "error")) answer$apply_error <- conditionMessage(snapshot)
    else answer$apply_snapshot <- snapshot
  }
  answer
}
.sc_run_subcluster_write_derived <- function(root, journal, id, object) {
  relative <- file.path("reintegration", paste0(id, ".rds")); path <- file.path(root, relative)
  if (file.exists(path)) {
    if (nzchar(Sys.readlink(path)) || !identical(.sc_run_hash(readRDS(path)), .sc_run_hash(object)))
      stop("Existing derived artifact differs from this exact request.", call. = FALSE)
  } else .sc_run_atomic(object, path)
  record <- list(path = relative, sha256 = .sc_project_sha_file(path))
  journal$files[[id]] <- record
  list(journal = journal, path = path, record = record)
}
.sc_run_subcluster_assert_request <- function(state, project_id, input_hash, expected_revision) {
  .sc_project_string(project_id, "project_id"); .sc_run_review_hash_string(input_hash, "input_hash")
  if (!identical(state$project_id, project_id) || !identical(state$input_hash, input_hash))
    stop("Foreign child project or input; cross-project apply/import is rejected.", call. = FALSE)
  .sc_run_qc_revision_check(state, expected_revision)
}

#' Apply approved child labels by cell ID to a new parent-derived Seurat file
#' @param child_project Scoped completed child.
#' @param project_id,input_hash,expected_revision Exact child inspection identity.
#' @param parent_scope_hash,expected_parent_revision Frozen parent authority.
#' @param annotation_hash,apply_hash Exact hashes in the displayed apply snapshot.
#' @param column Fresh subtype column.
#' @param reviewer,reason Analyst identity and application rationale.
#' @param request_id Stable application identifier for idempotent repeated requests.
#' @param outside Explicit NA policy for cells outside the approved retained selection.
#' @param supersedes Optional own active application to supersede in a new immutable version.
#' @return Child inspection plus application receipt and a new derived RDS path.
#' @export
sc_run_subcluster_apply <- function(child_project, project_id, input_hash, expected_revision,
  parent_scope_hash, expected_parent_revision, annotation_hash, apply_hash, column,
  reviewer, reason, request_id, outside = "NA", supersedes = NULL) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  .sc_run_subcluster_id(request_id)
  for (name in c("parent_scope_hash", "annotation_hash", "apply_hash"))
    .sc_run_review_hash_string(get(name), name)
  root <- .sc_run_root(child_project); initial <- .sc_run_load(root, verify_subcluster = FALSE)
  if (is.null(initial$config$subcluster_origin)) stop("Only a scoped child can apply labels.", call. = FALSE)
  origin <- initial$config$subcluster_origin; .sc_run_subcluster_origin_verify(origin)
  parent_owner <- .sc_run_lock(origin$parent_project); on.exit(.sc_run_release(origin$parent_project, parent_owner), add = TRUE)
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  .sc_run_subcluster_assert_request(state, project_id, input_hash, expected_revision)
  parent <- .sc_run_subcluster_check_parent(origin)
  .sc_run_qc_revision_check(parent$state, expected_parent_revision)
  if (!identical(parent_scope_hash, origin$parent_scope_hash)) stop("Parent scope hash is stale.", call. = FALSE)
  journal <- .sc_run_subcluster_integration(root)
  request <- list(operation = "apply", project_id = project_id, input_hash = input_hash,
    expected_revision = expected_revision, parent_scope_hash = parent_scope_hash,
    expected_parent_revision = expected_parent_revision, annotation_hash = annotation_hash,
    apply_hash = apply_hash, column = column, outside = outside, supersedes = supersedes,
    reviewer = reviewer, reason = reason)
  request_hash <- .sc_run_hash(request); prior <- journal$requests[[request_id]]
  if (!is.null(prior)) {
    if (!identical(prior$request_hash, request_hash) || !identical(prior$operation, "apply"))
      stop("Request ID was already used with a different application payload.", call. = FALSE)
    answer <- sc_run_subcluster_inspect(root, column)
    answer$application <- journal$applications[[prior$application_id]]
    return(answer)
  }
  child <- .sc_run_subcluster_child_review(root, state)
  snapshot <- .sc_run_subcluster_snapshot(root, state, parent, child, journal, column, outside, supersedes)
  if (!identical(annotation_hash, snapshot$annotation_hash) || !identical(apply_hash, snapshot$apply_hash))
    stop("Child annotation, application preview or integration revision changed; stale apply rejected.", call. = FALSE)
  copied <- .sc_run_subcluster_copy(parent$seu, child$seu, child$expected_cells, column,
    state$project_id, state$config$cluster_column, state$config$annotation_column)
  id <- paste0("apply-", substr(.sc_run_hash(list(request_id = request_id, request_hash = request_hash)), 1L, 32L))
  saved <- .sc_run_subcluster_write_derived(root, journal, id, copied$seu); journal <- saved$journal
  .sc_run_crash("subcluster_apply:artifact")
  receipt <- list(application_id = id, status = "applied", active = TRUE, created_at = .sc_run_time(),
    parent_project_id = parent$state$project_id, parent_input_hash = parent$state$input_hash,
    parent_revision = parent$state$revision, parent_scope_hash = parent_scope_hash,
    parent_output_sha256 = parent$binding$output_sha256, child_project_id = state$project_id,
    child_input_hash = state$input_hash, child_revision = state$revision,
    origin_scope_hash = origin$scope_hash, retained_cell_scope_hash = .sc_run_hash(child$expected_cells),
    annotation_hash = annotation_hash, annotation_decision_id = child$decision$decision_id,
    annotation_review_hash = child$review$hash, apply_hash = apply_hash,
    column = column, fields = as.list(unname(copied$fields)), outside = outside,
    selected_cells = length(origin$selected_cells), retained_cells = length(child$expected_cells),
    excluded_selected_cells = length(origin$selected_cells) - length(child$expected_cells),
    supersedes = supersedes, output_path = saved$path, output_sha256 = saved$record$sha256,
    reviewer = reviewer, reason = reason, request_id = request_id,
    interpretation = "Literal cell-ID mapping from this executed child approval into a new parent copy. Child cluster IDs are provenance only; original parent files and annotations are unchanged.")
  if (!is.null(supersedes)) {
    journal$applications[[supersedes]]$status <- "superseded"
    journal$applications[[supersedes]]$active <- FALSE
  }
  journal$applications[[id]] <- receipt
  journal$requests[[request_id]] <- list(operation = "apply", request_hash = request_hash, application_id = id)
  journal <- .sc_run_subcluster_integration_event(journal, "applied_to_derived_parent", receipt)
  .sc_run_subcluster_integration_save(root, journal)
  answer <- sc_run_subcluster_inspect(root, column); answer$application <- receipt
  answer
}

#' Prepare explicit unresolved child labels for normal annotation review
#' @param child_project Scoped child at its annotation proposal boundary.
#' @param project_id,input_hash,expected_revision Exact current child identity.
#' @param reviewer,reason Analyst identity and reason to remain unresolved.
#' @param request_id Stable typed request identifier.
#' @return Child inspection with a saved Unknown/low proposal, awaiting approval.
#' @export
sc_run_subcluster_unknown <- function(child_project, project_id, input_hash, expected_revision,
  reviewer, reason, request_id) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  .sc_run_subcluster_id(request_id)
  root <- .sc_run_root(child_project); owner <- .sc_run_lock(root)
  on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (is.null(state$config$subcluster_origin)) stop("Unknown preparation is only available for a registered scoped child.", call. = FALSE)
  if (!identical(state$project_id, project_id) || !identical(state$input_hash, input_hash))
    stop("Foreign child project or changed input.", call. = FALSE)
  request <- list(operation = "unknown", project_id = project_id, input_hash = input_hash,
    expected_revision = expected_revision, reviewer = reviewer, reason = reason)
  hash <- .sc_run_hash(request)
  previous <- Filter(function(event) identical(event$action, "manual_proposal") &&
    identical(event$details$subcluster_unknown_request_id, request_id), state$history)
  if (length(previous)) {
    if (!identical(tail(previous, 1L)[[1L]]$details$subcluster_unknown_request_hash, hash))
      stop("Unknown request ID was reused with a different payload.", call. = FALSE)
    return(sc_run_subcluster_inspect(root))
  }
  .sc_run_subcluster_assert_request(state, project_id, input_hash, expected_revision)
  if (!identical(state$stage, "annotation_propose") ||
      !state$status %in% c("awaiting_configuration", "ready", "rejected") ||
      is.null(state$files$annotation_evidence) || !is.null(state$pending))
    stop("Inspect the saved child annotation configuration boundary before preparing Unknown labels.", call. = FALSE)
  evidence <- .sc_run_get(root, state, "annotation_evidence")
  ids <- vapply(evidence$summary$clusters, `[[`, character(1), "clusterId")
  .sc_project_ids(ids, "Saved child annotation cluster IDs")
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(ids,
    function(id) list(clusterId = id, label = "Unknown", confidence = "low",
      rationale = paste("Unresolved child annotation; no model inference or biological identity is claimed.", reason),
      markers = list())))
  .sc_run_propose_locked(root, state, proposal, reviewer, reason, drive = FALSE,
    review_binding = list(subcluster_unknown_request_id = request_id,
      subcluster_unknown_request_hash = hash, child_scope_hash = state$config$subcluster_origin$scope_hash))
  sc_run_subcluster_inspect(root)
}

#' Undo one exact derived-parent application by creating a restored version
#' @param child_project Scoped child owning the application.
#' @param application_id Exact active own application identifier.
#' @param project_id,input_hash,expected_revision Exact current child inspection.
#' @param integration_revision Exact inspected integration journal revision.
#' @param reviewer,reason Analyst identity and restoration rationale.
#' @param request_id Stable undo identifier for idempotent repeated requests.
#' @return Child inspection plus immutable restoration receipt; no parent file is modified.
#' @export
sc_run_subcluster_undo <- function(child_project, application_id, project_id, input_hash,
  expected_revision, integration_revision, reviewer, reason, request_id) {
  .sc_run_subcluster_id(application_id, "application_id"); .sc_run_subcluster_id(request_id)
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(child_project); initial <- .sc_run_load(root, verify_subcluster = FALSE)
  origin <- initial$config$subcluster_origin
  if (is.null(origin)) stop("Undo requires the scoped child that owns the application.", call. = FALSE)
  .sc_run_subcluster_origin_verify(origin)
  parent_owner <- .sc_run_lock(origin$parent_project); on.exit(.sc_run_release(origin$parent_project, parent_owner), add = TRUE)
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  .sc_run_subcluster_assert_request(state, project_id, input_hash, expected_revision)
  parent <- .sc_run_subcluster_check_parent(origin)
  journal <- .sc_run_subcluster_integration(root)
  request <- list(operation = "undo", application_id = application_id, project_id = project_id,
    input_hash = input_hash, expected_revision = expected_revision,
    integration_revision = integration_revision, reviewer = reviewer, reason = reason)
  hash <- .sc_run_hash(request); previous <- journal$requests[[request_id]]
  if (!is.null(previous)) {
    if (!identical(previous$request_hash, hash) || !identical(previous$operation, "undo"))
      stop("Undo request ID was reused with a different payload.", call. = FALSE)
    answer <- sc_run_subcluster_inspect(root)
    answer$undo <- journal$undos[[previous$undo_id]]
    return(answer)
  }
  .sc_run_qc_revision_check(journal, integration_revision)
  application <- journal$applications[[application_id]]
  if (is.null(application) || !isTRUE(application$active) ||
      !identical(application$child_project_id, project_id) ||
      !identical(application$origin_scope_hash, origin$scope_hash))
    stop("Only this child's exact active application can be undone; foreign or superseded IDs are rejected.", call. = FALSE)
  restore_application <- application$supersedes
  if (is.null(restore_application)) restored <- parent$seu else {
    prior <- journal$applications[[restore_application]]
    if (is.null(prior) || !identical(prior$child_project_id, project_id) ||
        !identical(prior$column, application$column) ||
        !identical(prior$origin_scope_hash, origin$scope_hash))
      stop("Superseded restoration link differs from this exact child/target scope.", call. = FALSE)
    record <- journal$files[[restore_application]]
    restored <- .sc_project_unwrap(readRDS(file.path(root, record$path)))
  }
  id <- paste0("undo-", substr(.sc_run_hash(list(request_id = request_id, hash = hash)), 1L, 32L))
  saved <- .sc_run_subcluster_write_derived(root, journal, id, restored); journal <- saved$journal
  .sc_run_crash("subcluster_undo:artifact")
  receipt <- list(undo_id = id, application_id = application_id, status = "undone",
    created_at = .sc_run_time(), child_project_id = project_id, child_input_hash = input_hash,
    child_revision = state$revision, parent_project_id = parent$state$project_id,
    parent_scope_hash = origin$parent_scope_hash, origin_scope_hash = origin$scope_hash,
    restored_application_id = restore_application, output_path = saved$path,
    output_sha256 = saved$record$sha256, reviewer = reviewer, reason = reason, request_id = request_id,
    interpretation = "New restored derived artifact. Original parent, applied versions and decision history are retained.")
  journal$applications[[application_id]]$active <- FALSE
  journal$applications[[application_id]]$status <- "undone"
  if (!is.null(restore_application)) {
    journal$applications[[restore_application]]$active <- TRUE
    journal$applications[[restore_application]]$status <- "applied"
  }
  journal$undos[[id]] <- receipt
  journal$requests[[request_id]] <- list(operation = "undo", request_hash = hash, undo_id = id)
  journal <- .sc_run_subcluster_integration_event(journal, "derived_application_undone", receipt)
  .sc_run_subcluster_integration_save(root, journal)
  answer <- sc_run_subcluster_inspect(root, application$column); answer$undo <- receipt
  answer
}
