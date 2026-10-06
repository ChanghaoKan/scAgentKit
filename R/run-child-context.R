# Parent labels are provenance and optional hypotheses, never child identity
# authority. This aggregate envelope is separate from calculation context.
.sc_run_child_context_fields <- function(value, fields, name) {
  if (!is.list(value) || (length(fields) && is.null(names(value))) ||
      anyNA(names(value)) || anyDuplicated(names(value)) ||
      !setequal(names(value), fields))
    stop(name, " has missing or unsupported fields.", call. = FALSE)
  value
}
.sc_run_child_context_text <- function(value, name, limit = 2000L, nullable = FALSE) {
  if (nullable && is.null(value)) return(NULL)
  .sc_project_string(value, name)
  if (!nzchar(trimws(value)) || nchar(value, type = "bytes") > limit)
    stop(name, " must be nonempty bounded text.", call. = FALSE)
  value
}
.sc_run_child_label_state <- function(labels, reviewed) {
  if (!reviewed) return("unreviewed")
  if (length(labels) > 1L) return("mixed")
  if (!length(labels) || tolower(trimws(labels)) %in% c("unknown", "unannotated", "undetermined")) return("unknown")
  if (tolower(trimws(labels)) == "unreviewed") return("unreviewed")
  if (tolower(trimws(labels)) %in% c("mixed", "mixed cells", "mixed population")) return("mixed")
  "labeled"
}
.sc_run_child_scope_state <- function(rows) {
  states <- vapply(rows, `[[`, character(1), "identity_status")
  labels <- unique(unlist(lapply(rows, `[[`, "labels"), use.names = FALSE))
  if ("unreviewed" %in% states) "unreviewed" else if ("mixed" %in% states || length(labels) > 1L)
    "mixed" else if ("unknown" %in% states) "unknown" else "labeled"
}
.sc_run_child_parent_snapshot <- function(parent, origin) {
  .sc_run_subcluster_origin_verify(origin)
  if (!identical(parent$binding, origin$parent))
    stop("Parent context differs from its frozen selection.", call. = FALSE)
  metadata <- parent$seu[[]]
  column <- parent$state$config$annotation_column
  record <- if (is.null(parent$state$files$annotation_review)) NULL else
    .sc_run_annotation_review_view(parent$root, parent$state)
  decisions <- if (is.null(record)) list() else
    Filter(function(event) identical(event$action, "approved"), record$lifecycle$decisions)
  reviewed <- !is.null(record) && isTRUE(record$lifecycle$executed) &&
    !isTRUE(record$lifecycle$undone) && length(decisions) > 0L
  if (reviewed && (!identical(record$cluster_column, origin$parent$cluster_column) ||
      !identical(record$target_column, column)))
    stop("Reviewed parent annotation columns differ from the frozen parent scope.", call. = FALSE)
  rows <- lapply(origin$selected_clusters, function(id) {
    cells <- origin$selected_cells[parent$membership[origin$selected_cells] == id]
    labels <- if (is.character(column) && column %in% names(metadata))
      unique(as.character(metadata[cells, column])) else character()
    labels <- labels[!is.na(labels) & nzchar(labels)]
    confidence <- NULL
    if (reviewed) {
      proposed <- Filter(function(row) identical(row$clusterId, id), record$details$canonical_proposal$annotations)
      if (length(proposed) != 1L || length(labels) != 1L ||
          !identical(labels, proposed[[1L]]$label))
        stop("Parent approved annotation and selected output labels differ.", call. = FALSE)
      confidence <- proposed[[1L]]$confidence
    }
    list(parentClusterId = id, cellCount = length(cells), labels = .sc_project_array(labels),
      review_status = if (reviewed) "approved_executed" else "unreviewed",
      identity_status = .sc_run_child_label_state(labels, reviewed), confidence = confidence)
  })
  decision <- if (length(decisions)) tail(decisions, 1L)[[1L]]$details else NULL
  snapshot <- list(schema = "scagentkit.child-parent-context.v1",
    source = list(project_id = parent$state$project_id, revision = parent$state$revision,
      input_hash = parent$state$input_hash, output_hash = origin$parent$output_sha256,
      scope_hash = origin$scope_hash, review_hash = if (reviewed) record$hash else NULL,
      decision_id = if (reviewed) decision$decision_id else NULL,
      source_kind = if (reviewed) record$details$source$kind else "not_recorded",
      annotation_column = column,
      scientific_result = parent$state$output$scientific_result),
    species = parent$state$config$context$species, tissue = parent$state$config$context$tissue,
    scope = lapply(rows, function(row) row[c("parentClusterId", "cellCount")]),
    annotations = rows, identity_status = .sc_run_child_scope_state(rows))
  .sc_run_child_snapshot_verify(snapshot)
  snapshot
}
.sc_run_child_snapshot_verify <- function(snapshot) {
  .sc_run_child_context_fields(snapshot,
    c("schema", "source", "species", "tissue", "scope", "annotations", "identity_status"), "Parent context snapshot")
  if (!identical(snapshot$schema, "scagentkit.child-parent-context.v1"))
    stop("Unsupported parent context snapshot schema.", call. = FALSE)
  source <- .sc_run_child_context_fields(snapshot$source,
    c("project_id", "revision", "input_hash", "output_hash", "scope_hash", "review_hash",
      "decision_id", "source_kind", "annotation_column", "scientific_result"), "Parent context provenance")
  for (field in c("project_id", "decision_id", "annotation_column", "scientific_result"))
    .sc_run_child_context_text(source[[field]], paste0("parent ", field), nullable = field != "project_id")
  .sc_run_strategy_number(source$revision, "parent context revision", 0, integer = TRUE)
  if (!is.character(source$source_kind) || length(source$source_kind) != 1L ||
      is.na(source$source_kind) || !source$source_kind %in% c("manual", "model", "mock", "provider_response", "unknown", "not_recorded"))
    stop("Parent annotation source_kind is missing or unsupported.", call. = FALSE)
  for (field in c("input_hash", "output_hash", "scope_hash", "review_hash")) {
    if (field == "review_hash" && is.null(source[[field]])) next
    .sc_run_review_hash_string(source[[field]], paste0("parent ", field))
  }
  for (field in c("species", "tissue")) .sc_run_child_context_text(snapshot[[field]], field, nullable = TRUE)
  if (!is.list(snapshot$scope) || !length(snapshot$scope) || !is.null(names(snapshot$scope)) ||
      !is.list(snapshot$annotations) || !is.null(names(snapshot$annotations)) ||
      length(snapshot$scope) != length(snapshot$annotations))
    stop("Parent context scope requires aligned aggregate arrays.", call. = FALSE)
  ids <- vapply(seq_along(snapshot$scope), function(i) {
    scope <- .sc_run_child_context_fields(snapshot$scope[[i]], c("parentClusterId", "cellCount"), "Parent aggregate scope")
    row <- .sc_run_child_context_fields(snapshot$annotations[[i]],
      c("parentClusterId", "cellCount", "labels", "review_status", "identity_status", "confidence"), "Parent annotation context")
    .sc_project_string(scope$parentClusterId, "parentClusterId")
    .sc_run_strategy_number(scope$cellCount, "parent scope cellCount", 1, integer = TRUE)
    if (!identical(scope, row[c("parentClusterId", "cellCount")]) ||
        !is.list(row$labels) || !is.null(names(row$labels)) ||
        any(!vapply(row$labels, function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x), logical(1))) ||
        anyDuplicated(unlist(row$labels, use.names = FALSE)) ||
        !is.character(row$review_status) || length(row$review_status) != 1L ||
        !row$review_status %in% c("approved_executed", "unreviewed") ||
        !identical(row$identity_status, .sc_run_child_label_state(unlist(row$labels, use.names = FALSE),
          identical(row$review_status, "approved_executed"))) ||
        (!is.null(row$confidence) && (!is.character(row$confidence) || length(row$confidence) != 1L ||
          is.na(row$confidence) || !row$confidence %in% c("low", "medium", "high"))))
      stop("Parent context labels, status or aggregate scope are inconsistent.", call. = FALSE)
    scope$parentClusterId
  }, character(1))
  if (anyDuplicated(ids) || !identical(snapshot$identity_status, .sc_run_child_scope_state(snapshot$annotations)))
    stop("Parent context identities are duplicated or inconsistent.", call. = FALSE)
  .sc_project_json_check(snapshot)
  invisible(snapshot)
}
.sc_run_child_context_effective <- function(value) {
  .sc_run_child_context_fields(value, c("enabled", "lineage_hint", "identity_status", "tissue", "notes"), "Editable child context")
  if (!identical(value$enabled, TRUE) && !identical(value$enabled, FALSE))
    stop("Child context enabled must be TRUE or FALSE.", call. = FALSE)
  if (!is.character(value$identity_status) || length(value$identity_status) != 1L ||
      is.na(value$identity_status) || !value$identity_status %in% c("labeled", "unknown", "mixed", "unreviewed"))
    stop("Child identity_status must be labeled, unknown, mixed or unreviewed; it describes a hypothesis, not biological truth.", call. = FALSE)
  .sc_run_child_context_text(value$lineage_hint, "lineage_hint", 200L, nullable = TRUE)
  .sc_run_child_context_text(value$tissue, "annotation tissue", 200L, nullable = TRUE)
  .sc_run_child_context_text(value$notes, "annotation notes", nullable = TRUE)
  value
}
.sc_run_child_context_initial <- function(snapshot) {
  .sc_run_child_snapshot_verify(snapshot)
  value <- list(schema = "scagentkit.child-context.v1", generation = 0L,
    parent_snapshot = snapshot, effective = list(enabled = TRUE, lineage_hint = NULL,
      identity_status = snapshot$identity_status, tissue = snapshot$tissue, notes = NULL),
    previous_hash = NULL)
  value$hash <- .sc_run_hash(value)
  value
}
.sc_run_child_context_verify <- function(value) {
  .sc_run_child_context_fields(value,
    c("schema", "generation", "parent_snapshot", "effective", "previous_hash", "hash"), "Child context")
  if (!identical(value$schema, "scagentkit.child-context.v1") ||
      !identical(value$hash, .sc_run_hash(value[setdiff(names(value), "hash")])))
    stop("Child context schema or fingerprint changed.", call. = FALSE)
  .sc_run_strategy_number(value$generation, "child context generation", 0, .Machine$integer.max, integer = TRUE)
  if (value$generation == 0L) {
    if (!is.null(value$previous_hash)) stop("Initial child context must have no previous hash.", call. = FALSE)
  } else .sc_run_review_hash_string(value$previous_hash, "previous context hash")
  .sc_run_child_snapshot_verify(value$parent_snapshot)
  .sc_run_child_context_effective(value$effective)
  invisible(value)
}
.sc_run_child_context_public <- function(value) {
  if (is.null(value)) return(NULL)
  .sc_run_child_context_verify(value)
  # Exact fields contain only cluster IDs/counts, reviewed labels, declared
  # context and provenance hashes. Local paths/cell IDs/reviewers are absent.
  value
}
.sc_run_child_context_for_annotation <- function(context, child_context) {
  if (is.null(child_context)) return(context)
  .sc_run_child_context_verify(child_context)
  if (!is.null(child_context$effective$tissue)) context$tissue <- child_context$effective$tissue
  context
}
.sc_run_child_context_assessment <- function(label, child_context, options = NULL) {
  if (is.null(child_context)) return(NULL)
  .sc_run_child_context_verify(child_context)
  effective <- child_context$effective
  labels <- if (!is.null(effective$lineage_hint)) effective$lineage_hint else
    unique(unlist(lapply(child_context$parent_snapshot$annotations, `[[`, "labels"), use.names = FALSE))
  applicable <- isTRUE(effective$enabled) && identical(effective$identity_status, "labeled") && length(labels)
  relations <- if (applicable) lapply(labels, function(expected) c(list(expected_label = expected),
    .sc_run_joint_label_relation(label, expected, .sc_run_reference_options(options)))) else list()
  statuses <- vapply(relations, `[[`, character(1), "status")
  warning <- if (!applicable) "no_resolved_parent_expectation" else
    if (any(statuses %in% c("exact_label", "mapped_name", "granularity"))) "compatible_label" else
      if (length(statuses) && all(statuses == "lineage_disagreement")) "explicit_cross_lineage_warning" else
        "unresolved_parent_label_difference"
  list(context_hash = child_context$hash, generation = child_context$generation,
    status = warning, relations = relations, blocking = FALSE,
    interpretation = "Parent labels and analyst corrections are soft hypotheses. Current expression evidence can override them; label differences do not authorize rejection or filtering. Cross-lineage claims require explicit declarations. Missing top markers do not establish absent expression.")
}
.sc_run_child_context_patch <- function(value, edits) {
  .sc_run_child_context_verify(value)
  allowed <- names(value$effective)
  edits <- .sc_run_annotation_options(edits, allowed, "child context edits")
  if (!length(edits)) stop("Supply at least one editable child context field.", call. = FALSE)
  effective <- value$effective
  for (name in names(edits)) effective[name] <- list(edits[[name]])
  effective <- .sc_run_child_context_effective(effective)
  if (effective$identity_status == "labeled" && is.null(effective$lineage_hint) &&
      value$parent_snapshot$identity_status != "labeled")
    stop("A labeled correction to an unresolved parent scope requires an explicit lineage_hint.", call. = FALSE)
  if (value$generation >= .Machine$integer.max) stop("Child context generation limit reached.", call. = FALSE)
  out <- value
  out$previous_hash <- value$hash; out$generation <- as.integer(value$generation + 1L)
  out$effective <- effective; out$hash <- NULL; out$hash <- .sc_run_hash(out)
  .sc_run_child_context_verify(out)
  out
}

#' Correct soft child annotation context without rerunning analysis
#'
#' Supports scoped children stopped before annotation writeback. Frozen parent
#' facts and selection remain unchanged; corrections are analyst hypotheses.
#' Changes require fresh annotation and exact outgoing-payload approvals. No
#' provider call, expression computation or browser action is performed.
#' @param project_dir Scoped child run directory.
#' @param context Named edit list containing enabled, lineage_hint,
#'   identity_status (labeled/unknown/mixed/unreviewed), tissue and/or notes.
#'   A lineage hint is a hypothesis, never a label whitelist. NULL clears a
#'   hint, tissue override or notes; unspecified fields retain their values.
#' @param project_id,input_hash Exact current inspected project/input bindings.
#' @param expected_revision Exact inspected run revision; required, never NULL.
#' @param expected_context_hash Exact inspected child_context$hash.
#' @param reviewer,reason Analyst identity and nonempty correction rationale.
#' @param request_id Stable literal identifier for idempotent correction retry.
#' @return Fresh inspection, awaiting a new annotation proposal. Previously
#'   approved calculation artifacts and the usage ledger remain unchanged.
#' @export
sc_run_set_child_context <- function(project_dir, context, project_id, input_hash,
                                    expected_revision, expected_context_hash,
                                    reviewer, reason, request_id) {
  .sc_project_string(project_id, "project_id")
  .sc_run_review_hash_string(input_hash, "input_hash")
  .sc_run_review_hash_string(expected_context_hash, "expected_context_hash")
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  request_id <- .sc_run_subcluster_request_id(request_id)
  if (is.null(expected_revision)) stop("The exact expected_revision is required.", call. = FALSE)
  .sc_run_strategy_number(expected_revision, "expected_revision", 0, integer = TRUE)
  root <- .sc_run_root(project_dir)
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!identical(project_id, state$project_id) || !identical(input_hash, state$input_hash))
    stop("Foreign project or changed input; inspect the scoped child.", call. = FALSE)
  if (is.null(state$config$subcluster_origin) || !isTRUE(state$config$strategy) ||
      is.null(state$config$annotation_context))
    stop("Context correction requires a fresh scoped child with saved aggregate parent context.", call. = FALSE)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed; context correction is stale.", call. = FALSE)
  request <- list(project_id = project_id, input_hash = input_hash,
    expected_revision = expected_revision, expected_context_hash = expected_context_hash,
    context = context, reviewer = reviewer, reason = reason, request_id = request_id)
  request_hash <- .sc_run_hash(request)
  prior <- state$child_context_requests[[request_id]]
  if (!is.null(prior)) {
    if (!identical(prior$request_hash, request_hash))
      stop("Correction request_id was reused with a different payload.", call. = FALSE)
    return(sc_run_inspect(root))
  }
  .sc_run_qc_revision_check(state, expected_revision)
  current <- state$config$annotation_context
  .sc_run_child_context_verify(current)
  if (!identical(current$parent_snapshot, state$config$subcluster_creation$parent_annotation_context) ||
      !identical(current$hash, expected_context_hash))
    stop("Stale or changed child context; inspect its exact current hash.", call. = FALSE)
  if (!state$stage %in% c("annotation_propose", "annotation_apply") ||
      state$status %in% c("running", "complete") ||
      "annotation_apply" %in% state$completed || !is.null(state$files$annotated) ||
      is.null(state$files$analysis) || is.null(state$files$markers))
    stop("Correct child context only at a stopped annotation proposal/application before writeback; undo an executed annotation first.", call. = FALSE)
  updated <- .sc_run_child_context_patch(current, context)
  config <- state$config; config$annotation_context <- updated
  reference <- if (is.null(state$files$reference)) NULL else .sc_run_get(root, state, "reference")
  evidence <- .sc_run_annotation_evidence(.sc_run_get(root, state, "analysis"),
    .sc_run_get(root, state, "markers"), config$context, reference,
    cluster_column = config$cluster_column, reference_review = config$reference_review,
    assay = config$assay, annotation_context = updated)
  if (!is.null(state$files$annotation_history_input)) evidence$private$historical <-
    .sc_run_annotation_history_import(.sc_run_get(root, state, "annotation_history_input"), evidence)
  detached <- intersect(c("manual_annotation", "annotation_request", "annotation_response",
    "annotation_validated", "annotation_review", "annotation_suggestion_adoption",
    "annotation_suggestion_response"), names(state$files))
  previous <- state$files[detached]
  state$config <- config; state$config_hash <- .sc_run_hash(config)
  state <- .sc_run_put(root, state, "child_annotation_context", updated)
  state <- .sc_run_put(root, state, "annotation_evidence", evidence)
  state$files[detached] <- NULL
  # Keep explicit NULL keys: `$suggestion` must not partially match the
  # suggestion_transfer_hashes vector after removing a live suggestion.
  state[c("pending", "approved", "suggestion")] <- list(NULL, NULL, NULL)
  state$transfer_hashes <- state$suggestion_transfer_hashes <- character()
  state$failure <- state$output <- NULL
  state$stage <- "annotation_propose"; state$status <- "awaiting_configuration"
  state$completed <- setdiff(state$completed, c("annotation_propose", "annotation_apply", "finalize"))
  state$nodes$annotation_propose <- "NEEDS_CONFIGURATION"
  state$nodes$annotation_apply <- state$nodes$finalize <- NULL
  state <- .sc_run_event(state, "child_context_corrected", list(reviewer = reviewer, reason = reason,
    request_id = request_id, request_hash = request_hash, previous_context_hash = current$hash,
    context_hash = updated$hash, generation = updated$generation,
    previous_artifacts = previous, config_hash = state$config_hash,
    calculation_reused = c("analysis", "markers"), provider_dispatch = "not_sent",
    authority = "New annotation context only; prior annotation proposals, approvals and outgoing consents are inactive."))
  state$child_context_requests[[request_id]] <- list(request_hash = request_hash,
    context_hash = updated$hash, revision = state$revision)
  .sc_run_crash("child_context:artifacts")
  .sc_run_save(root, state)
  .sc_run_crash("child_context:commit")
  sc_run_inspect(root)
}
