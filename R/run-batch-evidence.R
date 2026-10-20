# Descriptive evidence only. Existing design/Harmony validators still govern
# executable choices; neither mixing nor these diagnostics grants approval.
.sc_run_batch_pool <- function(cells, batch, limit = 512L) {
  keys <- vapply(enc2utf8(cells), function(id)
    digest::digest(id, algo = "xxhash64", serialize = FALSE), character(1))
  groups <- split(seq_along(cells), batch)
  groups <- groups[order(names(groups), method = "radix")]
  groups <- lapply(groups, function(i) i[order(keys[i], cells[i], method = "radix")])
  selected <- unlist(lapply(seq_len(max(lengths(groups))), function(depth)
    unlist(lapply(groups, function(i) if (depth <= length(i)) i[depth]),
      use.names = FALSE)), use.names = FALSE)
  cells[head(selected, limit)]
}

.sc_run_batch_mixing <- function(embedding, batch, k = 20L) {
  cells <- rownames(embedding)
  if (length(cells) < 3L || length(unique(batch)) < 2L)
    return(list(status = "unavailable", reason = "At least three cells and two batches are required."))
  k <- min(k, length(cells) - 1L)
  neighbors <- .sc_run_harmony_neighbors(embedding, cells, k)
  observed <- vapply(seq_along(cells), function(i)
    mean(batch[neighbors[, i]] == batch[i]), numeric(1))
  # The null reference uses this exact candidate pool, not the original cohort.
  expected <- (as.numeric(table(batch)[batch]) - 1) / (length(cells) - 1)
  list(status = "available", cells = length(cells), k = k,
    observed = mean(observed), random_reference = mean(expected),
    excess = mean(observed - expected), cell_hash = .sc_run_hash(cells),
    candidate_pool_hash = .sc_run_hash(cells))
}

.sc_run_batch_purity <- function(embedding, labels, k = 20L) {
  cells <- rownames(embedding)
  if (length(cells) < 3L || length(labels) != length(cells) || anyNA(labels))
    return(list(status = "unavailable", reason = "Fixed diagnostic labels are unavailable."))
  neighbors <- .sc_run_harmony_neighbors(embedding, cells, min(k, length(cells) - 1L))
  purity <- vapply(seq_along(cells), function(i)
    mean(labels[neighbors[, i]] == labels[i]), numeric(1))
  list(status = "available", mean = mean(purity), cells = length(cells),
    label_hash = .sc_run_hash(stats::setNames(labels, cells)))
}

.sc_run_batch_design <- function(sample, batch, condition) {
  if (is.null(sample) || is.null(condition) ||
      length(sample) != length(batch) || length(condition) != length(batch) ||
      anyNA(sample) || anyNA(batch) || anyNA(condition))
    return(list(status = "unavailable", fully_confounded = FALSE,
      reason = "Declared sample, batch and condition are required; cells are not replicates."))
  rows <- unique(data.frame(sample = sample, batch = batch, condition = condition,
    stringsAsFactors = FALSE))
  if (anyDuplicated(rows$sample))
    return(list(status = "unavailable", fully_confounded = FALSE,
      reason = "A declared sample spans more than one batch or condition; resolve design metadata."))
  table <- table(rows$batch, rows$condition)
  fully <- ncol(table) > 1L && all(rowSums(table > 0) == 1L)
  list(status = "available", fully_confounded = fully,
    independent_samples = nrow(rows),
    condition_samples = lapply(sort(unique(rows$condition)), function(value)
      list(condition = value, samples = sum(rows$condition == value))),
    contingency = lapply(seq_len(nrow(table)), function(i)
      list(batch = rownames(table)[i], conditions = lapply(seq_len(ncol(table)), function(j)
        list(condition = colnames(table)[j], samples = unname(table[i, j]))))),
    boundary = "Sample-level declared design, not proof of independent biological sampling.")
}

.sc_run_batch_condition_signal <- function(embedding, sample, condition, labels,
                                           min_sample_cells = 3L) {
  missing <- function(reason) list(status = "unavailable", reason = reason)
  if (is.null(sample) || is.null(condition) || is.null(labels) ||
      any(vapply(list(sample, condition, labels), length, integer(1)) != nrow(embedding)) ||
      anyNA(sample) || anyNA(condition) || anyNA(labels))
    return(missing("Declared samples, conditions and fixed type labels are required."))
  design <- unique(data.frame(sample = sample, condition = condition))
  if (anyDuplicated(design$sample)) return(missing("A sample has inconsistent conditions."))
  conditions <- sort(unique(condition), method = "radix")
  if (length(conditions) < 2L || any(table(design$condition) < 2L))
    return(missing("Each condition needs at least two declared independent samples."))
  types <- lapply(sort(unique(labels), method = "radix"), function(label) {
    index <- which(labels == label)
    by_sample <- split(index, sample[index])
    by_sample <- by_sample[lengths(by_sample) >= min_sample_cells]
    available <- names(by_sample)
    groups <- design$condition[match(available, design$sample)]
    if (!all(conditions %in% groups) || any(table(groups) < 2L))
      return(list(label = label, status = "unavailable",
        reason = "This type lacks two supported samples in every condition."))
    centers <- do.call(rbind, lapply(by_sample, function(i) colMeans(embedding[i, , drop = FALSE])))
    pairs <- utils::combn(conditions, 2L, simplify = FALSE)
    results <- lapply(pairs, function(pair) {
      one <- centers[groups == pair[1], , drop = FALSE]
      two <- centers[groups == pair[2], , drop = FALSE]
      m1 <- colMeans(one); m2 <- colMeans(two)
      numerator <- sqrt(sum((m1 - m2)^2))
      denominator <- sqrt(mean(c(rowSums(sweep(one, 2L, m1)^2),
        rowSums(sweep(two, 2L, m2)^2))))
      valid <- is.finite(denominator) && denominator > sqrt(.Machine$double.eps)
      list(conditions = as.list(pair), status = if (valid) "available" else "unavailable",
        samples = as.list(c(nrow(one), nrow(two))), distance = numerator,
        within_sample_dispersion = denominator, ratio = if (valid) numerator / denominator else NULL,
        reason = if (valid) NULL else "Within-condition sample dispersion is zero or unavailable.")
    })
    list(label = label, status = "measured", pairs = results)
  })
  list(status = "measured", min_sample_cells = min_sample_cells,
    sample_weighting = "equal sample centroids", types = types)
}

.sc_run_batch_evidence <- function(embedding, roles, labels, after = NULL,
                                   design_supported = FALSE, excess_threshold = .1) {
  if (!is.matrix(embedding) || is.null(rownames(embedding)) ||
      anyDuplicated(rownames(embedding)) || any(!is.finite(embedding)))
    stop("Batch diagnostics require finite, uniquely named coordinates.", call. = FALSE)
  if (!is.null(after) && (!is.matrix(after) || ncol(after) != ncol(embedding) ||
      !identical(rownames(after), rownames(embedding)) ||
      any(!is.finite(after))))
    stop("Before and after embeddings must use identical cells and dimensions.", call. = FALSE)
  batch <- roles$batch
  if (is.null(batch) || length(batch) != nrow(embedding) || anyNA(batch))
    return(list(schema = "scagentkit.batch-evidence.v1", status = "insufficient_evidence",
      recommendation = "none", reason = "No complete declared technical batch is available."))
  batch <- as.character(batch)
  if (length(unique(batch)) < 2L)
    return(list(schema = "scagentkit.batch-evidence.v1", status = "not_applicable",
      recommendation = "none", reason = "Only one declared batch is present."))
  if (!is.numeric(excess_threshold) || length(excess_threshold) != 1L ||
      !is.finite(excess_threshold) || excess_threshold < 0 || excess_threshold > 1)
    stop("Batch effect threshold must be a declared finite fraction.", call. = FALSE)
  cells <- rownames(embedding)
  pool <- .sc_run_batch_pool(cells, batch)
  index <- match(pool, cells)
  selected <- embedding[pool, , drop = FALSE]
  mixing <- .sc_run_batch_mixing(selected, batch[index])
  design <- .sc_run_batch_design(roles$sample, batch, roles$condition)
  status <- if (isTRUE(design$fully_confounded)) "fully_confounded" else
    if (!identical(mixing$status, "available")) "insufficient_evidence" else
      if (mixing$excess <= excess_threshold) "no_effect_detected" else
        if (isTRUE(design_supported) && identical(design$status, "available"))
          "effect_detected_design_supported" else "insufficient_evidence"
  strata <- list()
  for (field in c("condition", "diagnostic_cluster")) {
    values <- if (field == "diagnostic_cluster") labels else roles$condition
    if (is.null(values) || length(values) != length(cells) || anyNA(values)) next
    strata[[field]] <- lapply(sort(unique(values[index]), method = "radix"), function(level) {
      keep <- values[index] == level
      list(level = level, evidence = .sc_run_batch_mixing(selected[keep, , drop = FALSE], batch[index][keep]))
    })
  }
  result <- list(schema = "scagentkit.batch-evidence.v1", status = status,
    recommendation = if (status == "effect_detected_design_supported") "harmony" else "none",
    design = design, design_supported = isTRUE(design_supported),
    threshold = list(excess = excess_threshold, status = "development_not_experiment_frozen"),
    scope = list(cells = length(pool), full_cells = length(cells),
      cell_hash = .sc_run_hash(pool), sampling = "hash-ordered batch round-robin, at most 512"),
    technical_mixing = list(before = mixing), within_strata = strata,
    type_structure = list(before = .sc_run_batch_purity(selected, if (is.null(labels)) NULL else labels[index])),
    condition_signal = list(before = .sc_run_batch_condition_signal(embedding,
      roles$sample, roles$condition, labels)),
    interpretation = "Separate technical and biological diagnostics, no composite score. Diagnostic clusters are proxies, not truth; absent detected effect does not prove no batch effect.")
  if (!is.null(after)) {
    result$technical_mixing$after <- .sc_run_batch_mixing(after[pool, , drop = FALSE], batch[index])
    result$type_structure$after <- .sc_run_batch_purity(after[pool, , drop = FALSE],
      if (is.null(labels)) NULL else labels[index])
    result$condition_signal$after <- .sc_run_batch_condition_signal(after, roles$sample, roles$condition, labels)
    if (identical(result$type_structure$before$status, "available") &&
        identical(result$type_structure$after$status, "available"))
      result$type_structure$change <- result$type_structure$after$mean - result$type_structure$before$mean
    result$technical_mixing$change <- result$technical_mixing$after$excess - mixing$excess
    result$preservation_thresholds <- list(status = "development_not_experiment_frozen",
      interpretation = "Report measured changes separately. No validated decline cutoff or automatic preservation verdict is asserted.")
  }
  result
}
