# A fixed-graph resolution scan is descriptive evidence, not a lineage or
# biological-stability claim. Literal cell identifiers stay in local artifacts.
.sc_run_cluster_tree <- function(assignments, samples = NULL) {
  if (!is.list(assignments) || !length(assignments) || is.null(names(assignments)))
    stop("Cluster tree requires named scanned resolutions.", call. = FALSE)
  cells <- names(assignments[[1]])
  if (is.null(cells) || anyDuplicated(cells) || anyNA(cells) || any(!nzchar(cells)) ||
      !all(vapply(assignments, function(x) identical(names(x), cells) &&
        is.character(x) && !anyNA(x) && all(nzchar(x)), logical(1))))
    stop("Cluster tree requires the exact cell IDs and order for every resolution.", call. = FALSE)
  if (!is.null(samples) && (length(samples) != length(cells) || anyNA(samples)))
    stop("Cluster sample composition must match the exact cell scope.", call. = FALSE)
  nodes <- edges <- list()
  for (i in seq_along(assignments)) {
    membership <- assignments[[i]]
    for (label in unique(membership)) {
      selected <- membership == label
      node <- list(id = paste0(i, ":", label), resolution = as.numeric(names(assignments)[i]),
        cluster = label, cells = as.integer(sum(selected)), sample_counts = list())
      if (!is.null(samples)) node$sample_counts <- .sc_run_strategy_group_counts(samples[selected])
      nodes[[length(nodes) + 1L]] <- node
    }
    if (i > 1L) {
      previous <- assignments[[i - 1L]]
      pairs <- .sc_run_strategy_pairs(previous, membership, "source_cluster", "target_cluster")$rows
      for (pair in pairs) edges[[length(edges) + 1L]] <- c(pair,
        list(source = paste0(i - 1L, ":", pair$source_cluster), target = paste0(i, ":", pair$target_cluster),
          source_fraction = pair$cells / sum(previous == pair$source_cluster),
          target_fraction = pair$cells / sum(membership == pair$target_cluster)))
    }
  }
  list(nodes = nodes, edges = edges,
    interpretation = "Edges show observed shared-cell transitions between adjacent resolutions on one fixed graph. ARI measures resolution sensitivity, not resampling stability, lineage or biological correctness. Sample composition is descriptive; no donor replication is inferred.")
}

.sc_run_cluster_selection <- function(resolution, scan) {
  if (length(resolution) != 1L || !is.numeric(resolution) || !is.finite(resolution) ||
      !resolution %in% scan$resolutions)
    stop("Select an actually scanned resolution, or explicitly revise the diagnostic grid to request a new scan.", call. = FALSE)
  invisible(TRUE)
}

.sc_run_cluster_scan <- function(seu, config, plan, neighbors_artifact) {
  execution <- seu@misc$strategy_execution
  assignments <- execution$cluster$diagnostic_assignments
  sample_column <- config$context$columns$sample
  samples <- if (is.null(sample_column)) NULL else as.character(seu[[]][[sample_column]])
  tree <- .sc_run_cluster_tree(assignments, samples)
  markers <- lapply(assignments, function(membership) {
    working <- seu
    working[[config$cluster_column]] <- factor(unname(membership))
    found <- .sc_run_markers(working, config)
    list(status = if (nrow(found$marker_summary)) "measured" else "no_markers_passed",
      markers = .sc_run_annotation_marker_records(found$marker_summary), parameters = found$parameters,
      limitation = "Same-data differential markers support comparison; they do not independently validate cluster identities or the resolution.")
  })
  result <- list(schema = "scagentkit.cluster-scan.v1", neighbors_artifact = neighbors_artifact,
    cell_scope_hash = .sc_run_hash(colnames(seu)), graph_hash = .sc_run_hash(seu[["sc_strategy_snn"]]),
    selected_pcs = execution$neighbors$pcs, seed = plan$analysis$seed,
    resolutions = as.numeric(names(assignments)), diagnostic_resolutions = plan$clustering$diagnostic_resolutions,
    membership_hashes = lapply(assignments, .sc_run_hash),
    provisional_resolution = plan$clustering$resolution,
    candidates = execution$cluster$candidates, tree = tree, markers = markers,
    interpretation = "No resolution is automatically recommended. Review transitions, marker contrasts and sample composition; optional model suggestions require explicit existing transfer approval, and the author approves the final selection.")
  if (!is.null(config$scientific_review)) result$scientific_diagnostics <- .sc_run_science_diagnostics(seu,config,plan)
  result$hash <- .sc_run_hash(result)
  result
}

.sc_run_cluster_scan_get <- function(root, state) {
  if (is.null(state$files$cluster_scan)) return(NULL)
  artifact <- state$files$cluster_scan
  path <- file.path(root, artifact$path)
  if (!file.exists(path) || nzchar(Sys.readlink(path)) ||
      !identical(artifact$sha256, .sc_project_sha_file(path)))
    stop("Resolution scan artifact changed; review is stale.", call. = FALSE)
  scan <- .sc_run_get(root, state, "cluster_scan")
  if (!identical(scan$hash, .sc_run_hash(scan[setdiff(names(scan), "hash")])) ||
      !identical(scan$neighbors_artifact, state$files$strategy_neighbors))
    stop("Resolution scan or its exact neighbor artifact changed; review is stale.", call. = FALSE)
  scan
}

.sc_run_cluster_after <- function(root, state, plan) {
  if (!length(plan$clustering$diagnostic_resolutions) && is.null(state$config$scientific_review)) return(state)
  scan <- .sc_run_cluster_scan_get(root, state)
  if (is.null(scan)) {
    scan <- .sc_run_cluster_scan(.sc_run_get(root, state, "analysis"), state$config, plan,
      state$files$strategy_neighbors)
    state <- .sc_run_put(root, state, "cluster_scan", scan)
  }
  current <- .sc_run_get(root, state, "analysis")
  .sc_run_cluster_selection(plan$clustering$resolution, scan)
  membership <- current@misc$strategy_execution$cluster$diagnostic_assignments[[as.character(plan$clustering$resolution)]]
  if (!identical(.sc_run_hash(colnames(current)), scan$cell_scope_hash) ||
      !identical(.sc_run_hash(current[["sc_strategy_snn"]]), scan$graph_hash) ||
      !identical(current@misc$strategy_execution$neighbors$pcs, scan$selected_pcs) ||
      !identical(.sc_run_hash(membership), scan$membership_hashes[[as.character(plan$clustering$resolution)]]) ||
      !identical(as.character(current[[]][[state$config$cluster_column]]), unname(membership)))
    stop("Chosen resolution membership, cells, PCs or graph differ from the measured scan.", call. = FALSE)
  reviewed <- .sc_run_get(root, state, "strategy_review")$details$cluster_diagnostics
  if (!is.null(reviewed) && identical(reviewed$hash, scan$hash)) return(state)
  # Reuse the central scientific review, after measurement and before annotation.
  evidence <- .sc_run_get(root, state, "strategy_evidence")
  validated <- .sc_run_get(root, state, "strategy_validated")
  state$completed <- unique(c(state$completed, "strategy_cluster")); state$nodes$strategy_cluster <- "EXECUTED"
  state <- .sc_run_event(state, "executed", list(stage = "strategy_cluster", files = state$files))
  state$approved <- NULL; state$pending <- NULL
  state <- .sc_run_strategy_review_publish(root, state, validated, evidence)
  state <- .sc_run_strategy_pending(root, state, validated, evidence)
  state <- .sc_run_event(state, "resolution_scan_review_required", list(scan_hash = scan$hash,
    dispatch = "not_sent", boundary = "Author selection of measured resolution; same strategy review kind."))
  .sc_run_save(root, state)
  state
}
