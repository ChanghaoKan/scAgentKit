# Pure descriptions of already measured resolution evidence. No scoring,
# computation, provider dispatch, draft mutation or scientific approval.
.sc_run_recommend_resolution <- function(scan, validated) {
  step <- list(id = "resolution", status = "recommend_execute", assessment = "pending_computation",
    title = "Compare measured clustering resolutions", reasons = list(), completed = list(),
    candidates = list(), conflicts = list(), uncertainty = list(), missing = list(),
    next_decision = "Compute the explicitly approved resolution scan, then return to the next concentrated review before selecting a final resolution.")
  if (is.list(validated$proposal) && is.null(validated$proposal$clustering)) {
    step$status <- "recommend_skip"; step$assessment <- "unavailable"
    step$reasons <- list("This strategy reuses supplied processed clusters; no new resolution is selected.")
    step$next_decision <- "Review the supplied cluster provenance and current marker evidence."
    return(step)
  }
  if (is.null(scan)) {
    step$reasons <- list("No measured fixed-graph scan exists; the provisional resolution is not an evidence-based recommendation.")
    step$missing <- list(list(field = "resolution.scan", label = "Measured resolution scan",
      reason = "Cluster transitions, marker coverage and sample composition must be measured before alternatives can be assessed."))
    return(step)
  }
  fail <- function(reason) {
    step$status <- "insufficient_information"; step$assessment <- "unavailable"
    step$reasons <- list(reason)
    step$missing <- list(list(field = "resolution.scan", label = "Intact measured scan", reason = reason))
    step$next_decision <- "Restore and verify the saved scan or explicitly request a new scan; do not select an invented candidate."
    step
  }
  if (!is.list(scan)) return(fail("A saved structured scan is required."))
  resolutions <- scan$resolutions; nodes <- scan$tree$nodes; edges <- scan$tree$edges
  if (!identical(scan$schema, "scagentkit.cluster-scan.v1") || !is.numeric(resolutions) ||
      !length(resolutions) || any(!is.finite(resolutions)) || any(resolutions <= 0 | resolutions > 2) ||
      anyDuplicated(resolutions) || !is.list(nodes) || !length(nodes) || !is.list(edges))
    return(fail("Actual finite scanned resolutions and their saved cluster tree are required."))
  node_ok <- function(n) is.list(n) && is.character(n$id) && length(n$id) == 1L &&
    !is.na(n$id) && nzchar(n$id) && is.character(n$cluster) && length(n$cluster) == 1L &&
    !is.na(n$cluster) && nzchar(n$cluster) && is.numeric(n$resolution) && length(n$resolution) == 1L &&
    is.finite(n$resolution) && n$resolution %in% resolutions && is.numeric(n$cells) &&
    length(n$cells) == 1L && is.finite(n$cells) && n$cells > 0 && n$cells == floor(n$cells)
  if (!all(vapply(nodes, node_ok, logical(1)))) return(fail("Saved cluster nodes require literal IDs and positive measured cell counts."))
  node_ids <- vapply(nodes, `[[`, character(1), "id")
  if (anyDuplicated(node_ids)) return(fail("Saved cluster node IDs are ambiguous."))
  resolutions <- sort(resolutions, method = "radix")
  levels <- lapply(resolutions, function(r) Filter(function(n) n$resolution == r, nodes))
  totals <- vapply(levels, function(level) sum(vapply(level, `[[`, numeric(1), "cells")), numeric(1))
  if (any(totals <= 0) || length(unique(totals)) != 1L ||
      any(vapply(levels, function(level) anyDuplicated(vapply(level, `[[`, character(1), "cluster")) > 0L, logical(1))))
    return(fail("Every scanned resolution must describe the same cell total with unique literal cluster IDs."))
  edge_ok <- function(e) is.list(e) && length(e$source) == 1L && length(e$target) == 1L &&
    e$source %in% node_ids && e$target %in% node_ids && is.numeric(e$cells) &&
    length(e$cells) == 1L && is.finite(e$cells) && e$cells > 0 && e$cells == floor(e$cells)
  if (length(edges) && !all(vapply(edges, edge_ok, logical(1))))
    return(fail("Saved transitions must connect real measured nodes with positive shared-cell counts."))
  if (length(edges) && anyDuplicated(vapply(edges, function(e)
      paste0(nchar(e$source, type = "bytes"), ":", e$source, e$target), character(1))))
    return(fail("Repeated source-target transitions cannot establish independent splits or merges."))
  if (length(resolutions) > 1L) {
    expected_edges <- list()
    for (i in seq.int(2L, length(resolutions))) {
      a <- vapply(levels[[i - 1L]], `[[`, character(1), "id")
      b <- vapply(levels[[i]], `[[`, character(1), "id")
      pair <- Filter(function(e) e$source %in% a && e$target %in% b, edges)
      for (n in c(levels[[i - 1L]], levels[[i]])) {
        shared <- if (n$id %in% a) Filter(function(e) identical(e$source, n$id), pair) else
          Filter(function(e) identical(e$target, n$id), pair)
        if (sum(vapply(shared, `[[`, numeric(1), "cells")) != n$cells)
          return(fail("Adjacent transitions must account for every measured cell in each source and target cluster."))
      }
      expected_edges <- c(expected_edges, pair)
    }
    if (length(expected_edges) != length(edges)) return(fail("Transitions must connect adjacent scanned resolutions only."))
  }
  # Equivalence needs an exact saved membership hash or a complete adjacent
  # bijection of all cells; equal cluster counts/ARI alone are insufficient.
  parent <- seq_along(resolutions)
  find <- function(i) {while (parent[i] != i) i <- parent[i]; i}
  for (i in seq_along(resolutions)) for (j in seq_len(i - 1L)) {
    left <- scan$membership_hashes[[as.character(resolutions[j])]]
    right <- scan$membership_hashes[[as.character(resolutions[i])]]
    equivalent <- is.character(left) && length(left) == 1L && !is.na(left) && nzchar(left) && identical(left, right)
    if (i == j + 1L) {
      a <- vapply(levels[[j]], `[[`, character(1), "id"); b <- vapply(levels[[i]], `[[`, character(1), "id")
      pair <- Filter(function(e) e$source %in% a && e$target %in% b, edges)
      equivalent <- equivalent || (length(pair) == length(a) && length(a) == length(b) &&
        !anyDuplicated(vapply(pair, `[[`, character(1), "source")) &&
        !anyDuplicated(vapply(pair, `[[`, character(1), "target")) &&
        all(vapply(pair, function(e) e$cells == nodes[[match(e$source, node_ids)]]$cells &&
          e$cells == nodes[[match(e$target, node_ids)]]$cells, logical(1))))
    }
    if (equivalent) parent[find(i)] <- find(j)
  }
  step$assessment <- "assessed"
  step$reasons <- list("Retain measured alternatives for author comparison; no composite score, ranking or default-0.5 preference is used.")
  step$completed <- list("Fixed-cell, fixed-PC/neighbor-graph resolution scan and recorded cluster transitions are available.")
  step$conflicts <- list()
  step$uncertainty <- list("Sample concentration can reflect biology or technical structure; more sample mixing and more marker hits are not automatic optimization targets.",
    "ARI and shared-cell transitions describe resolution sensitivity, not resampling stability, lineage or biological correctness.",
    "Same-data differential markers do not independently validate identities; missing passing markers do not establish that a population is absent.",
    "No externally validated optimum, biological accuracy or sample/donor replication is established by this scan.")
  for (i in seq_along(resolutions)) {
    r <- resolutions[i]; level <- levels[[i]]; key <- as.character(r)
    ids <- vapply(level, `[[`, character(1), "id"); clusters <- vapply(level, `[[`, character(1), "cluster")
    incoming <- Filter(function(e) e$target %in% ids, edges)
    outgoing <- Filter(function(e) e$source %in% ids, edges)
    split_sources <- if (length(incoming)) sum(table(vapply(incoming, `[[`, character(1), "source")) > 1L) else 0L
    merge_targets <- if (length(incoming)) sum(table(vapply(incoming, `[[`, character(1), "target")) > 1L) else 0L
    record <- scan$markers[[key]]
    measured_markers <- is.list(record) && is.character(record$status) && length(record$status) == 1L &&
      !is.na(record$status) && record$status %in% c("measured", "no_markers_passed") && is.list(record$markers)
    valid_marker <- function(m) is.list(m) && length(m$clusterId) == 1L && m$clusterId %in% clusters &&
      is.character(m$gene) && length(m$gene) == 1L && !is.na(m$gene) && nzchar(m$gene) &&
      all(vapply(m[c("avgLog2FC", "pct1", "pct2", "pAdj")], function(v) is.numeric(v) && length(v) == 1L && is.finite(v), logical(1))) &&
      all(c("avgLog2FC", "pct1", "pct2", "pAdj") %in% names(m)) && m$avgLog2FC > 0 &&
      m$pct1 >= 0 && m$pct1 <= 1 && m$pct2 >= 0 && m$pct2 <= 1 && m$pAdj >= 0 && m$pAdj <= 1
    supporting <- if (measured_markers) Filter(valid_marker, record$markers) else list()
    supported <- unique(vapply(supporting, `[[`, character(1), "clusterId"))
    gap <- if (measured_markers) setdiff(clusters, supported) else NULL
    composition <- lapply(level, function(n) {
      rows <- n$sample_counts
      valid <- is.list(rows) && length(rows) > 0 && all(vapply(rows, function(x)
        is.character(x$value) && length(x$value) == 1L && !is.na(x$value) && nzchar(x$value) &&
        is.numeric(x$cells) && length(x$cells) == 1L && is.finite(x$cells) && x$cells > 0, logical(1)))
      if (valid) valid <- sum(vapply(rows, `[[`, numeric(1), "cells")) == n$cells &&
        !anyDuplicated(vapply(rows, `[[`, character(1), "value"))
      list(cluster = n$cluster, available = isTRUE(valid), samples = if (isTRUE(valid)) length(rows) else NULL,
        largest_fraction = if (isTRUE(valid)) max(vapply(rows, `[[`, numeric(1), "cells")) / n$cells else NULL)
    })
    measured_samples <- sum(vapply(composition, `[[`, logical(1), "available"))
    concentrated <- sum(vapply(composition, function(x) isTRUE(x$available) && x$samples == 1L, logical(1)))
    equivalent <- resolutions[vapply(seq_along(resolutions), function(j) j != i && find(j) == find(i), logical(1))]
    stats <- Filter(function(row) identical(as.numeric(row$resolution), r), scan$candidates)
    ari <- if (length(stats) == 1L) stats[[1]]$ari_vs_previous else NULL
    if (!is.numeric(ari) || length(ari) != 1L || !is.finite(ari)) ari <- NULL
    reasons <- list(paste0(length(level), " measured clusters across ", totals[i], " cells; ", split_sources,
      " incoming split sources and ", merge_targets, " incoming merge targets."),
      if (measured_markers) paste0(length(supported), "/", length(level), " clusters have a saved passing positive marker; ", length(gap), " lack that support.") else "Saved passing-marker coverage is unavailable; no zero coverage is imputed.",
      if (measured_samples) paste0(concentrated, "/", measured_samples, " measured clusters contain one declared sample; inspect study design rather than maximizing mixing.") else "Declared sample composition is unavailable; no sample or donor identity is inferred.")
    if (!is.null(ari)) reasons <- c(reasons, list(paste0("Saved ARI against the preceding resolution: ", signif(ari, 6L), "; parameter sensitivity only, not independent biological stability.")))
    if (length(equivalent)) reasons <- c(reasons, list(paste0("Same measured membership partition as resolution(s) ", paste(equivalent, collapse = ", "), "; equivalent options, not independent support.")))
    conflicts <- list()
    if (length(gap)) conflicts <- c(conflicts, list(paste0("Passing marker support missing for literal cluster(s): ", paste(gap, collapse = ", "), ". This is an evidence gap, not a biological rejection.")))
    if (concentrated) conflicts <- c(conflicts, list("Single-sample clusters require biological/technical design review; do not erase them merely to increase mixing."))
    if (split_sources || merge_targets) conflicts <- c(conflicts, list("Observed splits/merges need marker and study-context interpretation; additional clusters are not automatically improvements."))
    step$candidates[[i]] <- list(id = paste0("resolution_", key), label = paste0("Resolution ", key, " — ", length(level), " observed clusters"),
      changes = list(clustering = list(resolution = r)), available = TRUE,
      role = if (length(equivalent)) "equivalent" else if (length(conflicts) || !measured_markers || measured_samples < length(level)) "alternative_with_conflicts" else "candidate",
      reasons = reasons,
      impact = list(resolution = r, clusters = length(level), cells = totals[i],
        marker_supported_clusters = if (measured_markers) length(supported) else NULL, marker_missing_clusters = gap,
        sample_status = if (!measured_samples) "unavailable" else if (measured_samples == length(level)) "available" else "partial",
        sample_composition = composition, single_sample_clusters = if (measured_samples) concentrated else NULL,
        incoming_split_sources = as.integer(split_sources), incoming_merge_targets = as.integer(merge_targets),
        incoming_transitions = incoming, outgoing_transitions = outgoing, ari_vs_previous = ari,
        equivalent_options = equivalent), conflicts = conflicts)
    if (!measured_markers) step$missing <- c(step$missing, list(list(field = paste0("resolution.", key, ".markers"),
      label = paste0("Resolution ", key, " marker evidence"), reason = "No saved measured marker result; do not interpret missing evidence as zero expression.")))
    if (measured_samples < length(level)) step$missing <- c(step$missing, list(list(field = paste0("resolution.", key, ".samples"),
      label = paste0("Resolution ", key, " sample composition"), reason = "Complete declared-sample counts are unavailable for some or all clusters.")))
  }
  step$next_decision <- "Compare measured alternatives and their evidence gaps, apply one scanned resolution to the draft, then approve the exact scientific plan; no candidate executes or approves itself."
  step
}
