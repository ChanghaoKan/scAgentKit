# Human edits are protected by a versioned local artifact. Model adoption may
# fill untouched choices, never silently replace rows the analyst already saved.
.sc_run_draft_controls <- function(root, state) {
  if (!is.null(state$files$human_draft_controls)) {
    record <- state$files$human_draft_controls
    file <- file.path(root, record$path)
    if (!file.exists(file) || nzchar(Sys.readlink(file)) || !identical(.sc_project_sha_file(file), record$sha256))
      stop("Manual draft control checkpoint changed; restore its protected version before adoption.", call. = FALSE)
    value <- .sc_run_get(root, state, "human_draft_controls")
    if (!identical(value$schema, "scagentkit.human-draft-controls.v1"))
      stop("Manual draft controls are invalid; restore the protected checkpoint.", call. = FALSE)
    return(value)
  }
  list(schema = "scagentkit.human-draft-controls.v1",
    strategy_fields = state$config$input_policy$protected_strategy_fields,
    annotation_clusters = character(), annotation_scope_hash = NULL)
}

.sc_run_annotation_draft_scope <- function(root, state) {
  if (is.null(state$files$annotation_evidence)) return(NULL)
  .sc_run_hash(.sc_run_get(root, state, "annotation_evidence")$private$input_cells)
}

.sc_run_draft_track <- function(root, state, kind, before, after) {
  if (is.null(state$config$input_policy)) return(state)
  controls <- .sc_run_draft_controls(root, state)
  if (kind == "strategy") {
    fields <- setdiff(union(names(before), names(after)), "schema")
    changed <- fields[!vapply(fields, function(key) identical(before[[key]], after[[key]]), logical(1))]
    controls$strategy_fields <- unique(c(controls$strategy_fields, changed))
  } else if (kind == "annotation") {
    scope <- .sc_run_annotation_draft_scope(root, state)
    if (!identical(scope, controls$annotation_scope_hash)) controls$annotation_clusters <- character()
    previous <- before$annotations
    changed <- vapply(Filter(function(row) {
      old <- Filter(function(item) identical(item$clusterId, row$clusterId), previous)
      !length(old) || !identical(old[[1L]], row)
    }, after$annotations), function(row) row$clusterId, character(1))
    controls$annotation_clusters <- unique(c(controls$annotation_clusters, changed))
    controls$annotation_scope_hash <- scope
  } else return(state)
  state <- .sc_run_put(root, state, "human_draft_controls", controls)
  .sc_run_event(state, "human_draft_edits_recorded", list(kind = kind, edited = changed,
    controls_sha256 = state$files$human_draft_controls$sha256,
    boundary = "Retain saved analyst edits during model adoption; this is not scientific approval."))
}

.sc_run_merge_model_draft <- function(root, state, kind, candidate) {
  controls <- .sc_run_draft_controls(root, state)
  preserved <- character()
  if (kind == "strategy" && !is.null(state$files$strategy_validated)) {
    current <- .sc_run_get(root, state, "strategy_validated")$proposal
    preserved <- intersect(controls$strategy_fields, intersect(names(current), names(candidate)))
    for (field in preserved) candidate[[field]] <- current[[field]]
    reason_keys <- c(qc = "qc", analysis = "hvg", pcs = "pcs", batch = "batch", clustering = "clustering",
      umap = "umap", cycle = "cycle", doublet = "doublet")
    for (field in intersect(preserved, names(reason_keys))) {
      key <- reason_keys[[field]]
      if (!is.null(current$choice_reasons[[key]]) && !is.null(candidate$choice_reasons))
        candidate$choice_reasons[[key]] <- current$choice_reasons[[key]]
    }
  } else if (kind == "annotation" && !is.null(state$files$annotation_validated) &&
      identical(controls$annotation_scope_hash, .sc_run_annotation_draft_scope(root, state))) {
    current <- .sc_run_get(root, state, "annotation_validated")
    ids <- vapply(current$annotations, function(row) row$clusterId, character(1))
    preserved <- intersect(controls$annotation_clusters, ids)
    candidate$annotations <- lapply(candidate$annotations, function(row)
      if (row$clusterId %in% preserved) current$annotations[[match(row$clusterId, ids)]] else row)
  }
  list(proposal = candidate, preserved = preserved)
}
