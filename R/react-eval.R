# Shared versioned scorer for the package and evaluation-v2. Historical v1
# metrics are unchanged; its named label maps can be passed directly.
.sc_react_eval_table <- function(value, name) {
  if (is.character(value) && length(value) == 1L)
    value <- utils::read.csv(value, colClasses = "character", check.names = FALSE,
      stringsAsFactors = FALSE, na.strings = "")
  if (!is.data.frame(value) || anyDuplicated(names(value)) ||
      sum(c("cell_id", "cluster_id") %in% names(value)) != 1L)
    stop(name, " needs exactly one ID column: cell_id or cluster_id.", call. = FALSE)
  key <- intersect(c("cell_id", "cluster_id"), names(value))
  value[[key]] <- as.character(value[[key]])
  .sc_project_ids(value[[key]], paste(name, key))
  value
}

.sc_react_eval_map <- function(labels, mapping, cl) {
  mapping <- .sc_run_reference_map(mapping, "evaluation label map", labels = TRUE)
  resolved <- .sc_run_reference_resolve(labels, mapping, labels = TRUE)
  valid_ids <- .cl_candidates(cl)
  known <- unique(resolved[!is.na(resolved) & nzchar(resolved)])
  hits <- lapply(known, function(label) {
    id <- toupper(label)
    if (grepl("^CL:[0-9]{7}$", id) && id %in% valid_ids) return(id)
    .cl_match_one(label, cl)$cl_id
  })
  ids <- vapply(hits, function(x) if (is.null(x)) NA_character_ else x, character(1))
  out <- ids[match(resolved, known)]
  unname(out)
}

.sc_react_eval_ancestors <- function(id, cl, max_distance = 3L) {
  if (is.na(id)) return(stats::setNames(integer(), character()))
  distances <- stats::setNames(0L, id)
  frontier <- id
  for (depth in seq_len(max_distance)) {
    parents <- unique(unlist(cl$parents[frontier], use.names = FALSE))
    frontier <- setdiff(parents[startsWith(parents, "CL:")], names(distances))
    if (!length(frontier)) break
    distances <- c(distances, stats::setNames(rep(depth, length(frontier)), frontier))
  }
  distances
}

.sc_react_eval_labels <- function(table, membership, mapping, cl, truth = FALSE) {
  if (!"label" %in% names(table)) stop("Evaluation labels require a label column.", call. = FALSE)
  id_column <- intersect(c("cell_id", "cluster_id"), names(table))
  universe <- if (id_column == "cell_id") membership$cell_id else unique(membership$cluster)
  if (any(!table[[id_column]] %in% universe))
    stop("Evaluation contains IDs outside the saved annotation membership.", call. = FALSE)
  labels <- as.character(table$label)
  ids <- .sc_react_eval_map(labels, mapping, cl)
  if ("cl_id" %in% names(table)) {
    supplied <- !is.na(table$cl_id) & nzchar(table$cl_id)
    if (any(!table$cl_id[supplied] %in% .cl_candidates(cl)))
      stop("An explicit CL ID is absent or obsolete in the frozen ontology.", call. = FALSE)
    if (any(supplied & !is.na(ids) & table$cl_id != ids, na.rm = TRUE))
      stop("Explicit CL IDs contradict the exact label mapping.", call. = FALSE)
    ids[supplied] <- table$cl_id[supplied]
  }
  unknown <- !is.na(labels) & tolower(trimws(labels)) %in% c("unknown", "unannotated")
  missing <- is.na(labels) | !nzchar(trimws(labels))
  status <- ifelse(missing, "missing", ifelse(unknown, "unknown",
    ifelse(is.na(ids), "unmapped", "mapped")))
  if ("status" %in% names(table)) {
    allowed <- if (truth) c("mapped", "truth", "author_label", "reference_prediction") else
      c("candidate_only_not_reviewed", "reference_prediction", "mapped")
    explicit_unknown <- table$status %in% c("unknown", "explicit_unknown_control")
    failure <- !is.na(table$status) & nzchar(table$status) &
      !table$status %in% c(allowed, "unknown", "explicit_unknown_control")
    status[explicit_unknown] <- "unknown"
    status[failure] <- if (truth) "ambiguous" else "missing"
  }
  ids[status != "mapped"] <- NA_character_
  clusters <- sort(unique(membership$cluster), method = "radix")
  groups <- split(membership$cell_id, membership$cluster)
  indices <- stats::setNames(seq_len(nrow(table)), table[[id_column]])
  rows <- lapply(clusters, function(cluster) {
    cells <- groups[[cluster]]
    scope <- .sc_run_hash(sort(cells, method = "radix"))
    index <- unname(indices[if (id_column == "cell_id") cells else cluster])
    states <- status[index]; mapped <- ids[index]
    states[is.na(states)] <- "missing"
    if (id_column == "cluster_id") {
      if ("membership_hash" %in% names(table) && !is.na(index) &&
          !identical(table$membership_hash[index], scope))
        stop("Cluster labels refer to a different membership hash.", call. = FALSE)
      return(data.frame(cluster_id = cluster, cl_id = mapped, status = states,
        valid_fraction = as.numeric(states == "mapped"), majority_fraction = as.numeric(states == "mapped"),
        cells = length(cells), membership_hash = scope, stringsAsFactors = FALSE))
    }
    good <- states == "mapped"
    frequencies <- sort(base::table(mapped[good]), decreasing = TRUE)
    coverage <- mean(good)
    majority <- if (sum(good)) max(frequencies) / sum(good) else 0
    pass <- coverage >= .8 && majority >= .8
    result_status <- if (pass) "mapped" else if (all(states == "unknown")) "unknown" else
      if (any(states == "unmapped") && coverage < .8) "unmapped" else
        if (all(states == "missing")) "missing" else "ambiguous"
    data.frame(cluster_id = cluster,
      cl_id = if (pass) names(frequencies)[1L] else NA_character_,
      status = result_status, valid_fraction = coverage, majority_fraction = majority,
      cells = length(cells), membership_hash = scope, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

.sc_react_eval_score <- function(truth, prediction, cl, allowed_ancestors) {
  stopifnot(identical(truth$cluster_id, prediction$cluster_id))
  valid <- truth$status == "mapped"
  exact <- valid & prediction$status == "mapped" & truth$cl_id == prediction$cl_id
  exact[is.na(exact)] <- FALSE
  distances <- vapply(seq_len(nrow(truth)), function(i) {
    if (!valid[i] || prediction$status[i] != "mapped") return(NA_integer_)
    if (exact[i]) return(0L)
    if (!prediction$cl_id[i] %in% allowed_ancestors) return(NA_integer_)
    ancestors <- .sc_react_eval_ancestors(truth$cl_id[i], cl)
    unname(ancestors[match(prediction$cl_id[i], names(ancestors))])
  }, integer(1))
  parent <- !is.na(distances) & distances > 0L
  primary <- valid & prediction$status != "unmapped"
  ratio <- function(n, d) if (d) n / d else NA_real_
  data.frame(total = nrow(truth), truth_scoreable = sum(valid),
    truth_unmapped = sum(truth$status == "unmapped"),
    truth_ambiguous = sum(truth$status == "ambiguous"),
    truth_missing_or_unknown = sum(truth$status %in% c("missing", "unknown")),
    pred_unmapped = sum(prediction$status == "unmapped"),
    pred_unknown = sum(prediction$status == "unknown"),
    pred_failed_or_mixed = sum(prediction$status %in% c("missing", "ambiguous")),
    denominator = sum(primary), strict_denominator = sum(valid),
    exact_correct = sum(exact), direct_parent_correct = sum(distances == 1L, na.rm = TRUE),
    ancestor_2_3_correct = sum(distances %in% 2:3),
    accuracy_exact = ratio(sum(exact), sum(primary)),
    accuracy_hierarchical = ratio(sum(exact | parent), sum(primary)),
    strict_accuracy_exact = ratio(sum(exact), sum(valid)),
    strict_accuracy_hierarchical = ratio(sum(exact | parent), sum(valid)),
    prediction_mapping_coverage = ratio(sum(prediction$status == "mapped"), nrow(prediction)),
    truth_mapping_coverage = ratio(sum(valid), nrow(truth)),
    unknown_fraction = ratio(sum(prediction$status == "unknown"), nrow(prediction)),
    correct_yield = ratio(sum(exact | parent), nrow(truth)),
    denominator_reason = if (sum(primary)) "" else "No scoreable units after unmapped-prediction exclusion",
    stringsAsFactors = FALSE)
}

.sc_react_eval_accounting <- function(entries) {
  total <- function(field, usage = FALSE) {
    values <- lapply(entries, function(x) if (usage) x$usage[[field]] else x[[field]])
    known <- vapply(values, function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0, logical(1))
    list(recorded = if (length(entries)) sum(unlist(values[known])) else NA_real_,
      unknown_calls = sum(!known))
  }
  list(calls = length(entries), cost = total("cost_usd"),
    input_tokens = total("input_tokens", TRUE), output_tokens = total("output_tokens", TRUE))
}

.sc_react_eval_cells <- function(table, membership, mapping, cl, truth = FALSE) {
  if ("cluster_id" %in% names(table)) {
    index <- match(membership$cluster, table$cluster_id)
    table <- table[index, setdiff(names(table), c("cluster_id", "membership_hash")), drop = FALSE]
    table$cell_id <- membership$cell_id
  }
  singleton <- data.frame(cell_id = membership$cell_id, cluster = membership$cell_id)
  .sc_react_eval_labels(table, singleton, mapping, cl, truth)
}

#' Compare baseline, ReAct and external labels with frozen local truth
#' @param project Saved project with completed ReAct annotation.
#' @param truth Label data.frame or CSV, keyed by cell_id or cluster_id.
#' @param external Named list of external label tables or CSV paths.
#' @param label_map Named character vector, or list with prediction/truth vectors.
#'   Existing evaluation-v1 label-map sections can be supplied unchanged.
#' @param allowed_ancestors Frozen meaningful CL IDs allowed for parent matches.
#'   Empty means exact scoring only; no broad-root credit is invented.
#' @param obo_path Optional explicit local CL ontology, otherwise the bundled snapshot.
#' @param output_dir Optional new directory; NULL creates a new evaluation directory.
#' @return Metrics, cluster outcomes and provenance, with CSV/JSON export paths.
#' @export
sc_react_eval <- function(project, truth, external = list(), label_map = NULL,
                          allowed_ancestors = character(), obo_path = NULL, output_dir = NULL) {
  root <- .sc_run_root(project); state <- .sc_run_load(root)
  if (is.null(state$files$annotation_react_run))
    stop("This project has no saved baseline/ReAct pair.", call. = FALSE)
  run <- .sc_run_get(root, state, "annotation_react_run")
  if (!identical(run$status, "completed")) stop("Complete the annotation session before evaluation.", call. = FALSE)
  membership <- .sc_run_get(root, state, "annotation_evidence")$private$input_cells
  cl <- .get_cl_ontology(obo_path)
  if (!is.character(allowed_ancestors) || anyNA(allowed_ancestors) ||
      anyDuplicated(allowed_ancestors) || any(!allowed_ancestors %in% .cl_candidates(cl)))
    stop("allowed_ancestors must contain unique frozen CL IDs.", call. = FALSE)
  if (any(tolower(cl$name[allowed_ancestors]) %in%
      c("cell", "native cell", "animal cell", "eukaryotic cell", "somatic cell")))
    stop("Universal root classes cannot receive parent-match credit.", call. = FALSE)
  maps <- if (is.null(label_map) || is.character(label_map))
    list(prediction = label_map, truth = label_map) else label_map
  if (!is.list(maps) || (length(maps) && (is.null(names(maps)) ||
      anyDuplicated(names(maps)) || any(!names(maps) %in% c("prediction", "truth")))))
    stop("label_map supports prediction and truth mappings only.", call. = FALSE)
  truth <- .sc_react_eval_table(truth, "truth")
  truths <- .sc_react_eval_truths(truth, maps$truth, cl, allowed_ancestors)
  targets <- lapply(truths, .sc_react_eval_labels, membership = membership,
    mapping = maps$truth, cl = cl, truth = TRUE)
  target <- targets$primary
  to_table <- function(proposal) do.call(rbind, lapply(proposal$annotations, function(x)
    data.frame(cluster_id = x$clusterId, label = x$label, confidence = x$confidence,
      stringsAsFactors = FALSE)))
  predictions <- list(baseline = to_table(run$baseline), react = to_table(run$proposal))
  if (!is.list(external) || (length(external) && (is.null(names(external)) ||
      anyDuplicated(names(external)) || any(!nzchar(names(external))) ||
      any(names(external) %in% names(predictions)))))
    stop("External comparisons need distinct method names.", call. = FALSE)
  for (name in names(external)) predictions[[name]] <- .sc_react_eval_table(external[[name]], name)
  audit <- .sc_run_react_audit(root, state)
  difficult <- target$cluster_id %in% unlist(run$targets, use.names = FALSE)
  scores <- rows <- cell_rows <- list()
  for (truth_source in names(targets)) for (method in names(predictions)) {
    target <- targets[[truth_source]]
    predicted <- .sc_react_eval_labels(predictions[[method]], membership, maps$prediction, cl)
    rows[[paste(truth_source, method)]] <- data.frame(truth_source = truth_source, method = method, target,
      predicted_cl_id = predicted$cl_id, prediction_status = predicted$status,
      difficult = difficult, stringsAsFactors = FALSE)
    for (scope in c("all", "difficult")) {
      selected <- if (scope == "all") rep(TRUE, nrow(target)) else difficult
      scores[[paste(truth_source, method, scope)]] <- cbind(unit = "cluster", truth_source = truth_source, method = method, scope = scope,
        .sc_react_eval_score(target[selected, ], predicted[selected, ], cl, allowed_ancestors))
    }
    cell_target <- .sc_react_eval_cells(truths[[truth_source]], membership, maps$truth, cl, TRUE)
    cell_prediction <- .sc_react_eval_cells(predictions[[method]], membership, maps$prediction, cl)
    cell_difficult <- membership$cluster[match(cell_target$cluster_id, membership$cell_id)] %in%
      unlist(run$targets, use.names = FALSE)
    agreement <- attr(truths, "agreement")
    disagreement <- if (is.null(agreement)) rep(FALSE, nrow(cell_target)) else
      agreement$disagreement[match(cell_target$cluster_id, agreement$cell_id)]
    disagreement[is.na(disagreement)] <- FALSE
    cell_rows[[paste(truth_source, method)]] <- data.frame(
      truth_source = truth_source, method = method, cell_id = cell_target$cluster_id,
      truth_cl_id = cell_target$cl_id, truth_status = cell_target$status,
      predicted_cl_id = cell_prediction$cl_id, prediction_status = cell_prediction$status,
      difficult = cell_difficult, annotator_disagreement = disagreement)
    for (scope in c("all", "difficult", if (!is.null(agreement)) "annotator_disagreement")) {
      selected <- switch(scope, all = rep(TRUE, nrow(cell_target)),
        difficult = cell_difficult, annotator_disagreement = disagreement)
      scores[[paste("cell", truth_source, method, scope)]] <- cbind(unit = "cell",
        truth_source = truth_source, method = method, scope = scope,
        .sc_react_eval_score(cell_target[selected, ], cell_prediction[selected, ], cl, allowed_ancestors))
    }
  }
  metrics <- do.call(rbind, scores); rownames(metrics) <- NULL
  cluster_results <- do.call(rbind, rows); rownames(cluster_results) <- NULL
  steps <- do.call(rbind, lapply(audit$clusters, function(x) data.frame(
    cluster_id = x$cluster_id, steps = x$model_turns, tool_calls = x$tool_calls,
    fallback = !is.null(x$fallback_reason),
    fallback_reason = if (is.null(x$fallback_reason)) "" else x$fallback_reason)))
  if (is.null(steps)) steps <- data.frame(cluster_id = character(), steps = integer(),
    tool_calls = integer(), fallback = logical(), fallback_reason = character())
  absent <- setdiff(targets$primary$cluster_id, steps$cluster_id)
  if (length(absent)) steps <- rbind(steps, data.frame(cluster_id = absent,
    steps = 0L, tool_calls = 0L, fallback = FALSE, fallback_reason = ""))
  steps$difficult <- steps$cluster_id %in% unlist(run$targets, use.names = FALSE)
  ledger <- .sc_run_provider_read(file.path(root, "provider", "ledger.json"))
  baseline_entries <- Filter(function(x) identical(x$purpose, "annotation"), ledger$entries)
  react_entries <- Filter(function(x) identical(x$session_id, run$session$id) &&
    identical(x$purpose, "annotation_react"), ledger$entries)
  counts <- table(steps$fallback_reason[steps$fallback])
  fallback_counts <- data.frame(reason = as.character(names(counts)), clusters = as.integer(counts),
    stringsAsFactors = FALSE)
  result <- list(schema = "scagentkit.react-evaluation.v2", scoring = "CL-directed-distance3-80-80-primary-and-strict.v1",
    metrics = metrics, clusters = cluster_results, cells = do.call(rbind, cell_rows),
    steps = steps, fallback_reasons = fallback_counts,
    annotator_agreement = attr(truths, "agreement"),
    annotator_agreement_summary = attr(truths, "agreement_summary"),
    fallback_rate = if (nrow(steps)) mean(steps$fallback) else NA_real_,
    difficult_fallback_rate = if (any(steps$difficult)) mean(steps$fallback[steps$difficult]) else NA_real_,
    accounting = list(baseline = .sc_react_eval_accounting(baseline_entries),
      react_increment = .sc_react_eval_accounting(react_entries),
      annotation_total = .sc_react_eval_accounting(c(baseline_entries, react_entries))),
    configuration = run$binding$policy, provider = state$config$provider[c("name", "model")],
    provenance = list(run_id = run$id, membership_hash = .sc_run_hash(membership),
      truth_hash = .sc_run_hash(truth), prediction_hashes = lapply(predictions, .sc_run_hash),
      label_map_hash = .sc_run_hash(maps), allowed_ancestors = allowed_ancestors,
      ancestor_hash = .sc_run_hash(allowed_ancestors), ontology = attr(cl, "scAgentKit_source")),
    accounting_scope = "Baseline accounting includes all saved project annotation-purpose calls; ReAct increment is restricted to this session. Recorded totals exclude explicitly counted unknown costs.",
    boundary = "Cluster IDs must refer to this saved partition. For independently reclustered methods supply cell IDs. Truth and external predictions are evaluator-only; no API call or scientific approval.")
  if (is.null(output_dir)) {
    parent <- file.path(root, "evaluation"); dir.create(parent, recursive = TRUE, showWarnings = FALSE)
    output_dir <- tempfile("react-", tmpdir = parent)
  }
  if (file.exists(output_dir)) stop("Choose a new evaluation output directory.", call. = FALSE)
  dir.create(output_dir, recursive = TRUE)
  for (name in c("metrics", "clusters", "cells", "steps", "fallback_reasons"))
    utils::write.csv(result[[name]], file.path(output_dir, paste0(name, ".csv")), row.names = FALSE, na = "")
  if (!is.null(result$annotator_agreement))
    utils::write.csv(result$annotator_agreement, file.path(output_dir, "annotator_agreement.csv"), row.names = FALSE, na = "")
  .sc_run_atomic(result, file.path(output_dir, "evaluation.json"), json = TRUE)
  result$output_dir <- normalizePath(output_dir)
  result
}
