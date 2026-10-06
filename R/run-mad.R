# Deterministic local MAD evidence and a finite, reviewed preset panel.
# This coordinator path is separate from the legacy qc_mad/range interfaces.
# Only `summary` is eligible for an explicitly approved aggregate AI preview.
.sc_run_mad_fields <- function(value, required, allowed = required, label) {
  if (!is.list(value) || is.null(names(value)) || anyNA(names(value)) ||
      any(!nzchar(names(value))) || anyDuplicated(names(value)) ||
      length(setdiff(required, names(value))) || length(setdiff(names(value), allowed)))
    .sc_project_fail(paste0(label, " requires exactly the supported named fields."))
  invisible(TRUE)
}

.sc_run_mad_text <- function(value, label) {
  .sc_project_string(value, label)
  if (!nzchar(trimws(value))) .sc_project_fail(paste0(label, " must contain nonempty provenance text."))
  unname(value)
}

.sc_run_mad_options <- function(context, supplied) {
  if (is.null(supplied) || identical(supplied, FALSE)) return(NULL)
  if (!is.list(context)) .sc_project_fail("MAD QC requires an explicitly supplied context list.")
  value <- supplied
  if (is.list(value) && identical(value$schema, "scagentkit.qc.mad-options.v1")) value$schema <- NULL
  .sc_run_mad_fields(value, "grouping", c("grouping", "k", "min_group_cells", "mad_constant"), "qc_mad")
  group <- value$grouping
  .sc_run_mad_fields(group, c("method", "source"),
    c("method", "source", "column", "declared_role", "id"), "MAD grouping")
  group$source <- .sc_run_mad_text(group$source, "MAD grouping source")
  if (identical(group$method, "column")) {
    .sc_run_mad_fields(group, c("method", "column", "declared_role", "source"), label = "MAD column grouping")
    group$column <- .sc_run_mad_text(group$column, "MAD grouping column")
    if (!identical(group$declared_role, "qc_group") && !identical(group$declared_role, "sample"))
      .sc_project_fail("MAD declared_role must explicitly be qc_group or sample; capture, donor, condition and batch are never inferred as quality groups.")
    declared <- if (is.list(context$columns)) context$columns[[group$declared_role]] else NULL
    if (!identical(group$column, declared))
      .sc_project_fail("MAD grouping column must match its explicitly declared context$columns$qc_group or context$columns$sample role.")
    group <- group[c("method", "column", "declared_role", "source")]
  } else if (identical(group$method, "single")) {
    .sc_run_mad_fields(group, c("method", "id", "source"), label = "MAD single grouping")
    group$id <- .sc_run_mad_text(group$id, "MAD single grouping id")
    group <- group[c("method", "id", "source")]
  } else .sc_project_fail("MAD grouping requires an explicit column role or a sourced single-group declaration; no sample/donor/capture relationship is guessed.")
  defaults <- list(k = 3, min_group_cells = 30L, mad_constant = 1.4826)
  for (field in names(defaults)) {
    current <- value[[field]]
    if (is.null(current)) current <- defaults[[field]]
    if (!is.numeric(current) || length(current) != 1L || !is.finite(current) ||
        current != defaults[[field]])
      .sc_project_fail(paste0("MAD ", field, " currently supports exactly ", defaults[[field]], "; unsupported parameters are not clipped or silently substituted."))
  }
  list(schema = "scagentkit.qc.mad-options.v1", grouping = group,
    k = 3, min_group_cells = 30L, mad_constant = 1.4826)
}

.sc_run_mad_groups <- function(seu, options, cells) {
  grouping <- options$grouping
  if (identical(grouping$method, "single")) values <- rep(grouping$id, length(cells)) else {
    metadata <- seu[[]]
    .sc_project_ids(rownames(metadata), "MAD metadata cell IDs")
    if (!setequal(rownames(metadata), cells) || sum(names(metadata) == grouping$column) != 1L)
      .sc_project_fail("MAD grouping metadata must cover every original cell with one unambiguous declared column.")
    values <- metadata[cells, grouping$column]
    if (!(is.character(values) || is.factor(values) || is.numeric(values) || is.logical(values)) ||
        anyNA(values) || any(!nzchar(trimws(as.character(values)))) ||
        (is.numeric(values) && any(!is.finite(values))))
      .sc_project_fail("MAD grouping values must be finite, nonempty, nonmissing atomic literal values; empty samples cannot become a guessed group.")
    values <- as.character(values)
  }
  stats::setNames(enc2utf8(unname(values)), cells)
}

.sc_run_mad_versions <- function() {
  list(R = as.character(getRversion()), stats = as.character(utils::packageVersion("stats")),
    Matrix = as.character(utils::packageVersion("Matrix")),
    SeuratObject = as.character(utils::packageVersion("SeuratObject")),
    algorithm = "scagentkit.qc.mad.local.v1")
}

.sc_run_mad_presets <- function() {
  list(
    list(preset_id = "keep_all", label = "Keep all cells passing the explicit minimal prefilter", rule = "No quality-metric deletion.", required_metrics = character()),
    list(preset_id = "conservative_and3", label = "Joint low counts AND low features AND high mitochondrial fraction", rule = "Remove only low_count & low_feature & high_mt.", required_metrics = c("nCount", "nFeature", "percent_mt")),
    list(preset_id = "low_counts3", label = "Low counts alone", rule = "Remove low_count only.", required_metrics = "nCount"),
    list(preset_id = "low_features3", label = "Low features alone", rule = "Remove low_feature only.", required_metrics = "nFeature"),
    list(preset_id = "high_mt3", label = "High mitochondrial fraction alone", rule = "Remove high_mt only.", required_metrics = "percent_mt"),
    list(preset_id = "any_quality3", label = "Low counts OR low features OR high mitochondrial fraction", rule = "Remove low_count | low_feature | high_mt.", required_metrics = c("nCount", "nFeature", "percent_mt")))
}

.sc_run_mad_multimodal_warning <- function(values) {
  values <- sort(values[is.finite(values)], method = "radix")
  n <- length(values)
  if (n < 30L) return(character())
  gaps <- diff(values); index <- which.max(gaps)
  required <- max(5L, ceiling(.15 * n))
  if (!length(index) || index < required || n - index < required) return(character())
  within <- max(stats::IQR(values[seq_len(index)], type = 7L),
    stats::IQR(values[seq.int(index + 1L, n)], type = 7L),
    sqrt(.Machine$double.eps) * max(1, abs(stats::median(values))))
  if (gaps[index] > 3 * within)
    "A large-gap distribution heuristic suggests separated subpopulations; this is a warning, not proof of multimodality or poor quality. Review the group and tissue context." else character()
}

.sc_run_mad_metric <- function(values, metric, options) {
  log_metric <- metric %in% c("nCount", "nFeature")
  finite <- is.finite(values)
  reasons <- character()
  if (length(values) < options$min_group_cells)
    reasons <- c(reasons, "Fewer than 30 prefilter-passing cells; the minimum is declared software policy, not a biological guarantee.")
  if (any(!finite)) reasons <- c(reasons, "One or more group measurements are missing or nonfinite; no value is imputed or interpreted as zero.")
  if (any(finite & (values < 0 | (!log_metric & values > 100))))
    reasons <- c(reasons, "One or more measurements are outside the supported count/fraction domain.")
  measured <- values[finite & values >= 0 & (log_metric | values <= 100)]
  transformed <- if (log_metric) log10(measured + 1) else measured
  med <- if (length(transformed)) stats::median(transformed) else NULL
  raw <- if (length(transformed)) stats::median(abs(transformed - med)) else NULL
  scaled <- if (is.null(raw)) NULL else options$mad_constant * raw
  cutoff <- if (is.null(med)) NULL else sqrt(.Machine$double.eps) * max(1, abs(med))
  if (is.null(scaled)) reasons <- c(reasons, "No finite group measurements are available.") else if (scaled <= cutoff)
    reasons <- c(reasons, "MAD is zero or near zero under the recorded numerical cutoff; non-keep presets needing this metric are unavailable.")
  # Descriptive median/MAD remain visible when insufficient. Unavailable
  # metrics have no executable threshold; numerical zero is not Unknown.
  lower <- if (length(reasons)) NULL else med - options$k * scaled
  upper <- if (length(reasons)) NULL else med + options$k * scaled
  raw_lower <- if (log_metric && !is.null(lower)) 10^lower - 1 else NULL
  raw_upper <- if (log_metric && !is.null(upper)) 10^upper - 1 else upper
  # The comparison for count/feature metrics occurs on the exact transformed
  # scale. An overflowing inverse-display bound is unknown, never an Infinity
  # that could be confused with a supported raw range operation.
  if (!is.null(raw_lower) && !is.finite(raw_lower)) raw_lower <- NULL
  if (!is.null(raw_upper) && !is.finite(raw_upper)) raw_upper <- NULL
  exact <- list(median = med, mad_raw = raw, scaled_mad = scaled,
    near_zero_cutoff = cutoff, lower_transformed = if (log_metric) lower else NULL,
    upper_transformed = upper, lower_raw = raw_lower, upper_raw = raw_upper)
  display <- lapply(exact, function(value) if (is.null(value)) NULL else signif(value, 6L))
  list(metric = metric, available = !length(reasons), n = length(values), measured = length(measured),
    missing = sum(!finite), transform = if (log_metric) "log10(x+1)" else "identity",
    tail = if (log_metric) "lower deletion; upper flag only" else "upper deletion",
    exact = exact, display = display, unavailable_reasons = unique(reasons),
    warnings = .sc_run_mad_multimodal_warning(transformed))
}

.sc_run_mad_diagnostic_percent <- function(counts, cells, species, kind) {
  patterns <- list(human = c(ribo = "^RP[SL]", hb = "^HB[ABDEGQZ]"),
                   mouse = c(ribo = "^Rp[sl]", hb = "^Hb[abdegqz]"))
  # Exact declared-species symbol patterns are software diagnostics. No case
  # conversion, synonym lookup, reference download, or inferred species occurs.
  pattern <- if (is.null(species)) NULL else unname(patterns[[species]][kind])
  genes <- if (is.null(pattern)) character() else grep(pattern, rownames(counts), value = TRUE)
  values <- rep(NA_real_, length(cells))
  totals <- as.numeric(Matrix::colSums(counts[, cells, drop = FALSE]))
  if (length(genes)) {
    positive <- totals > 0 & is.finite(totals)
    numerator <- as.numeric(Matrix::colSums(counts[genes, cells, drop = FALSE]))
    values[positive] <- 100 * numerator[positive] / totals[positive]
  }
  list(values = values, provenance = list(available = length(genes) > 0L,
    species = species, pattern = pattern, source = "scAgentKit declared-species literal symbol-pattern diagnostics v1",
    matched_gene_count = length(genes), gene_hash = .sc_run_hash(genes),
    unavailable_reason = if (length(genes)) NULL else "No matching genes or supported species declaration; diagnostic percentage is unavailable, not zero.",
    action = "diagnostic only; never used for candidate deletion"))
}

.sc_run_mad_compute <- function(metrics, group_map, prefilter_cells, options) {
  cells <- metrics$cell_id
  prefilter <- cells %in% prefilter_cells
  flags <- data.frame(cell_id = cells, qc_group = unname(group_map), prefilter_pass = prefilter,
    low_count = rep(NA, length(cells)), low_feature = rep(NA, length(cells)), high_mt = rep(NA, length(cells)),
    high_rna_count = rep(NA, length(cells)), high_rna_feature = rep(NA, length(cells)),
    stringsAsFactors = FALSE, check.names = FALSE)
  values <- sort(unique(unname(group_map)), method = "radix")
  groups <- lapply(seq_along(values), function(i) {
    value <- values[i]; all_indices <- which(group_map == value)
    indices <- all_indices[prefilter[all_indices]]
    stats <- stats::setNames(lapply(c("nCount", "nFeature", "percent_mt"), function(metric)
      .sc_run_mad_metric(metrics[[metric]][indices], metric, options)), c("nCount", "nFeature", "percent_mt"))
    if (stats$nCount$available) {
      transformed <- log10(metrics$nCount[indices] + 1)
      flags$low_count[indices] <<- transformed < stats$nCount$exact$lower_transformed
      flags$high_rna_count[indices] <<- transformed > stats$nCount$exact$upper_transformed
    }
    if (stats$nFeature$available) {
      transformed <- log10(metrics$nFeature[indices] + 1)
      flags$low_feature[indices] <<- transformed < stats$nFeature$exact$lower_transformed
      flags$high_rna_feature[indices] <<- transformed > stats$nFeature$exact$upper_transformed
    }
    if (stats$percent_mt$available)
      flags$high_mt[indices] <<- metrics$percent_mt[indices] > stats$percent_mt$exact$upper_raw
    flag_counts <- lapply(c("low_count", "low_feature", "high_mt", "high_rna_count", "high_rna_feature"), function(field)
      if (!length(indices)) 0L else if (anyNA(flags[[field]][indices])) NULL else sum(flags[[field]][indices]))
    names(flag_counts) <- c("low_count", "low_feature", "high_mt", "high_rna_count", "high_rna_feature")
    list(group_id = paste0("group", i), value = value, before = length(all_indices), pre_score = length(indices),
      metrics = stats, flags = flag_counts,
      diagnostic_metrics = list(percent_ribo = .sc_run_qc_distribution(metrics$percent_ribo[indices]),
        percent_hb = .sc_run_qc_distribution(metrics$percent_hb[indices])),
      warnings = unique(c(unlist(lapply(stats, `[[`, "warnings"), use.names = FALSE),
        "Median/MAD cannot determine whether most cells are poor quality; an independently sourced tissue/capture baseline is needed.",
        if (!length(indices)) "This original group has zero cells after the explicit prefilter; retention is known zero, not an unavailable estimate." else character())))
  })
  candidates <- .sc_run_mad_presets()
  selections <- stats::setNames(vector("list", length(candidates)), vapply(candidates, `[[`, character(1), "preset_id"))
  panels <- lapply(candidates, function(candidate) {
    requirements <- candidate$required_metrics
    unavailable <- unlist(lapply(groups, function(group) {
      if (!group$pre_score) return(character())
      unlist(lapply(requirements, function(metric) if (isTRUE(group$metrics[[metric]]$available)) character() else
        paste0("Group ", group$value, ", ", metric, ": ", paste(group$metrics[[metric]]$unavailable_reasons, collapse = " "))), use.names = FALSE)
    }), use.names = FALSE)
    usable <- !length(unavailable)
    selected <- NULL
    if (usable) {
      removed <- switch(candidate$preset_id, keep_all = rep(FALSE, length(cells)),
        conservative_and3 = flags$low_count & flags$low_feature & flags$high_mt,
        low_counts3 = flags$low_count, low_features3 = flags$low_feature,
        high_mt3 = flags$high_mt,
        any_quality3 = flags$low_count | flags$low_feature | flags$high_mt)
      # Flags outside the immutable prefilter cohort are deliberately unknown.
      removed[!prefilter] <- FALSE
      selected <- prefilter & !removed
      if (anyNA(selected)) .sc_project_fail("An available MAD candidate contains unknown cell decisions; no partial rule is executable.")
      selections[candidate$preset_id] <<- list(cells[selected])
    }
    per_group <- lapply(groups, function(group) {
      original <- group_map == group$value
      retained <- if (!group$pre_score) 0L else if (usable) sum(selected[original]) else NULL
      list(group_id = group$group_id, value = group$value,
        selector = stats::setNames(list(group$value), if (identical(options$grouping$method, "column")) options$grouping$declared_role else "qc_group"),
        before = group$before, pre_score = group$pre_score, retained = retained,
        quality_removed = if (is.null(retained)) NULL else group$pre_score - retained,
        removed = if (is.null(retained)) NULL else group$before - retained,
        fraction_retained = if (is.null(retained)) NULL else retained / group$before,
        empty_after_quality = if (is.null(retained)) NULL else retained == 0L)
    })
    c(candidate[setdiff(names(candidate), "required_metrics")], list(available = usable, required_metrics = requirements,
      unavailable_reasons = unique(unavailable), before = length(cells), pre_score = sum(prefilter),
      retained = if (usable) sum(selected) else NULL,
      quality_removed = if (usable) sum(prefilter) - sum(selected) else NULL,
      removed = if (usable) length(cells) - sum(selected) else NULL,
      fraction_retained = if (usable) mean(selected) else NULL,
      all_cells_removed = if (usable) !any(selected) else NULL, groups = per_group))
  })
  list(flags = flags, groups = groups, presets = panels, selections = selections)
}

.sc_run_mad_hash <- function(record) .sc_run_hash(record[setdiff(names(record), "evidence_hash")])

.sc_run_mad_baseline_qc <- function(evidence) {
  baseline <- evidence
  baseline$mad_record <- NULL
  if (is.list(baseline$summary)) baseline$summary$mad <- NULL
  baseline$evidence_hash <- .sc_run_qc_hash(baseline)
  baseline
}

.sc_run_mad_panel_hash <- function(record) {
  summary <- record$summary; summary$panel_hash <- NULL
  .sc_run_hash(list(options_hash = record$options_hash, context_hash = record$context_hash,
    counts_hash = record$counts_hash, cell_hash = record$cell_hash, features_hash = record$features_hash,
    group_hash = record$group_hash, metrics_hash = record$metrics_hash,
    prefilter_hash = record$prefilter_hash, qc_evidence_hash = record$qc_evidence_hash,
    versions_hash = record$versions_hash, summary = summary,
    flags_hash = record$flags_hash, selections_hash = record$selections_hash))
}

.sc_run_mad_evidence <- function(seu, config, qc_evidence, prefilter_record = NULL) {
  seu <- .sc_project_unwrap(seu)
  options <- .sc_run_mad_options(config$context, config$qc_mad)
  if (is.null(options)) .sc_project_fail("MAD evidence requires an explicitly enabled qc_mad configuration.")
  if (!is.list(qc_evidence) || !is.null(qc_evidence$mad_record) ||
      !identical(qc_evidence$evidence_hash, .sc_run_qc_hash(qc_evidence)))
    .sc_project_fail("MAD evidence requires the unchanged original QC evidence before attaching the MAD panel.")
  cells <- colnames(seu); .sc_project_ids(cells, "MAD original cell IDs")
  counts <- .sc_project_layer(seu, config$assay, config$counts_layer, raw_counts = TRUE)
  count_hash <- .sc_project_sparse_hash(counts)
  if (!identical(cells, qc_evidence$metrics$cell_id) || !setequal(colnames(counts), cells) ||
      !identical(count_hash, qc_evidence$counts_hash) || !identical(rownames(counts), qc_evidence$feature_ids))
    .sc_project_fail("MAD original raw counts, feature IDs or literal cell IDs differ from the actual QC input.")
  prefilter_cells <- cells
  if (!is.null(prefilter_record)) {
    .sc_run_prefilter_verify(prefilter_record)
    if (!identical(prefilter_record$cell_ids, cells) ||
        !identical(prefilter_record$feature_ids, rownames(counts)) ||
        !identical(prefilter_record$counts_hash, count_hash))
      .sc_project_fail("MAD prefilter record belongs to different original input; no stale cohort is accepted.")
    prefilter_cells <- prefilter_record$keep_cells
  }
  if (!is.character(prefilter_cells) || anyNA(prefilter_cells) || anyDuplicated(prefilter_cells) ||
      !identical(prefilter_cells, cells[cells %in% prefilter_cells]))
    .sc_project_fail("MAD prefilter cell IDs must be an exact ordered subset of original input cells.")
  metrics <- qc_evidence$metrics[, c("cell_id", "nCount", "nFeature", "percent_mt"), drop = FALSE]
  rownames(metrics) <- NULL
  for (field in c("nCount", "nFeature", "percent_mt")) {
    if (!is.numeric(metrics[[field]])) .sc_project_fail("MAD QC measurements require numeric count/feature/mitochondrial values.")
    metrics[[field]] <- unname(as.numeric(metrics[[field]]))
  }
  species <- .sc_run_species(config$context$species, allow_missing = TRUE)
  ribo <- .sc_run_mad_diagnostic_percent(counts, cells, species, "ribo")
  hb <- .sc_run_mad_diagnostic_percent(counts, cells, species, "hb")
  metrics$percent_ribo <- ribo$values; metrics$percent_hb <- hb$values
  group_map <- .sc_run_mad_groups(seu, options, cells)
  computed <- .sc_run_mad_compute(metrics, group_map, prefilter_cells, options)
  versions <- .sc_run_mad_versions()
  summary <- list(schema = "scagentkit.qc.mad.evidence.v1", status = "available",
    grouping = options$grouping,
    stage_counts = list(original_cells = length(cells), pre_score_cells = length(prefilter_cells),
      statistics_cells = length(prefilter_cells), quality_choice = "pending"),
    method = list(k = options$k, mad_constant = options$mad_constant, min_group_cells = options$min_group_cells,
      counts_features_transform = "log10(x+1)", mt_transform = "identity",
      near_zero_policy = "scaled_MAD <= sqrt(.Machine$double.eps) * max(1, abs(median))",
      comparisons = "Strict low < lower threshold and mitochondrial > upper threshold; equality is retained.",
      high_rna_action = "flag only; no high-count/high-feature deletion", ribo_hb_action = "diagnostic only; no deletion",
      default_preset_id = "keep_all", threshold_display = "6 significant digits for display only; exact numeric thresholds govern selection"),
    groups = computed$groups, presets = computed$presets,
    diagnostics = list(percent_ribo = ribo$provenance, percent_hb = hb$provenance), versions = versions,
    warnings = c("All presets require one explicit concentrated approval; the software never switches quality rules in the background.",
      "No preset is universally best. Retained-cell counts and annotations are impact evidence, not truth or tuning targets.",
      "Median/MAD assumes a useful group reference distribution and cannot certify majority-good cells or diagnose disease biology.",
      "Declared QC groups and physical capture/loading units are separate roles; neither implies donor identity.",
      "Per-cell values and literal cell IDs remain local; only this aggregate panel can be previewed for an approved model request."))
  record <- list(summary = summary, options = options, context = config$context, versions = versions,
    cell_ids = cells, feature_ids = rownames(counts), group_map = group_map, metrics = metrics,
    prefilter_record = prefilter_record, prefilter_cells = prefilter_cells,
    flags = computed$flags, selections = computed$selections,
    counts_hash = count_hash, qc_evidence_hash = qc_evidence$evidence_hash,
    context_hash = .sc_run_hash(config$context), prefilter_hash = if (is.null(prefilter_record)) NULL else prefilter_record$evidence_hash,
    cell_hash = .sc_run_hash(cells), features_hash = .sc_run_hash(rownames(counts)),
    group_hash = .sc_run_hash(group_map), options_hash = .sc_run_hash(options), versions_hash = .sc_run_hash(versions),
    metrics_hash = .sc_run_hash(metrics), flags_hash = .sc_run_hash(computed$flags), selections_hash = .sc_run_hash(computed$selections))
  record$panel_hash <- .sc_run_mad_panel_hash(record)
  record$summary$panel_hash <- record$panel_hash
  record$evidence_hash <- .sc_run_mad_hash(record)
  .sc_run_mad_verify(record)
  record
}

.sc_run_mad_verify <- function(record) {
  if (!is.list(record) || !is.list(record$summary) ||
      !identical(record$summary$schema, "scagentkit.qc.mad.evidence.v1") ||
      !identical(record$evidence_hash, .sc_run_mad_hash(record)))
    .sc_project_fail("MAD evidence is missing or changed; regenerate the local panel and obtain a fresh approval.")
  .sc_project_ids(record$cell_ids, "MAD evidence cell IDs")
  .sc_project_ids(record$feature_ids, "MAD evidence feature IDs")
  options <- .sc_run_mad_options(record$context, record$options)
  if (!identical(options, record$options) ||
      !identical(record$options_hash, .sc_run_hash(record$options)) ||
      !identical(record$context_hash, .sc_run_hash(record$context)) ||
      !identical(record$versions_hash, .sc_run_hash(record$versions)) ||
      !identical(record$summary$versions, record$versions) ||
      !identical(record$cell_hash, .sc_run_hash(record$cell_ids)) ||
      !identical(record$features_hash, .sc_run_hash(record$feature_ids)) ||
      !identical(names(record$group_map), record$cell_ids) ||
      !is.character(record$group_map) || anyNA(record$group_map) || any(!nzchar(trimws(record$group_map))) ||
      !identical(record$group_hash, .sc_run_hash(record$group_map)) ||
      !identical(record$metrics$cell_id, record$cell_ids) ||
      !identical(record$metrics_hash, .sc_run_hash(record$metrics)) ||
      !identical(record$flags_hash, .sc_run_hash(record$flags)) ||
      !identical(record$selections_hash, .sc_run_hash(record$selections)))
    .sc_project_fail("MAD options, context, versions, grouping, cell IDs or local measurements changed; the panel is stale.")
  if (!is.character(record$prefilter_cells) || anyNA(record$prefilter_cells) || anyDuplicated(record$prefilter_cells) ||
      !identical(record$prefilter_cells, record$cell_ids[record$cell_ids %in% record$prefilter_cells]))
    .sc_project_fail("MAD prefilter cohort changed or contains unsupported IDs.")
  if (is.null(record$prefilter_record)) {
    if (!is.null(record$prefilter_hash) || !identical(record$prefilter_cells, record$cell_ids))
      .sc_project_fail("MAD no-prefilter evidence must retain the original scoring/statistics cohort.")
  } else {
    .sc_run_prefilter_verify(record$prefilter_record)
    if (!identical(record$prefilter_hash, record$prefilter_record$evidence_hash) ||
        !identical(record$prefilter_cells, record$prefilter_record$keep_cells) ||
        !identical(record$cell_ids, record$prefilter_record$cell_ids) ||
        !identical(record$feature_ids, record$prefilter_record$feature_ids) ||
        !identical(record$counts_hash, record$prefilter_record$counts_hash))
      .sc_project_fail("MAD prefilter provenance or original source identity changed.")
  }
  computed <- .sc_run_mad_compute(record$metrics, record$group_map, record$prefilter_cells, options)
  if (!identical(record$flags, computed$flags) || !identical(record$selections, computed$selections) ||
      !identical(record$summary$groups, computed$groups) || !identical(record$summary$presets, computed$presets) ||
      !identical(record$summary$grouping, options$grouping) ||
      !identical(record$summary$stage_counts, list(original_cells = length(record$cell_ids),
        pre_score_cells = length(record$prefilter_cells), statistics_cells = length(record$prefilter_cells), quality_choice = "pending")) ||
      !identical(record$panel_hash, .sc_run_mad_panel_hash(record)) ||
      !identical(record$summary$panel_hash, record$panel_hash))
    .sc_project_fail("MAD exact thresholds, flags, finite preset panel or stage counts changed; obtain a fresh approval.")
  invisible(TRUE)
}

.sc_run_mad_validate <- function(proposal, evidence) {
  qc <- if (is.list(evidence$qc)) evidence$qc else evidence
  record <- qc$mad_record
  if (is.null(record)) record <- evidence$mad_record
  if (is.null(record) && is.list(evidence$private)) record <- evidence$private$mad_record
  .sc_run_mad_verify(record)
  if (!is.list(qc) || is.null(qc$metrics) ||
      !identical(qc$evidence_hash, .sc_run_qc_hash(qc)) ||
      !identical(record$qc_evidence_hash, .sc_run_mad_baseline_qc(qc)$evidence_hash) ||
      !identical(record$cell_ids, qc$metrics$cell_id) ||
      !identical(record$feature_ids, qc$feature_ids) || !identical(record$counts_hash, qc$counts_hash))
    .sc_project_fail("MAD panel belongs to different or changed original QC evidence; approval is stale.")
  .sc_run_mad_fields(proposal, c("schema", "rationale", "risks", "preset_id", "panel_hash"), label = "MAD QC proposal")
  if (!identical(proposal$schema, "scagentkit.qc.mad.v1")) .sc_project_fail("Unsupported MAD QC proposal schema.")
  rationale <- .sc_run_mad_text(proposal$rationale, "MAD proposal rationale")
  risks <- proposal$risks
  if (is.list(risks)) {
    if (!is.null(names(risks)) || !all(vapply(risks, function(value) is.character(value) && length(value) == 1L && !is.na(value) && nzchar(trimws(value)), logical(1))))
      .sc_project_fail("MAD proposal risks must be an unnamed text array, possibly empty.")
    risks <- unlist(risks, use.names = FALSE)
    if (!length(risks)) risks <- character()
  }
  if (!is.character(risks) || anyNA(risks) || any(!nzchar(trimws(risks))))
    .sc_project_fail("MAD proposal risks must be a text array, possibly empty.")
  .sc_run_mad_text(proposal$preset_id, "MAD preset_id")
  if (!identical(proposal$panel_hash, record$panel_hash))
    .sc_project_fail("MAD panel hash differs from this exact local candidate panel; stale approval is rejected.")
  index <- which(vapply(record$summary$presets, `[[`, character(1), "preset_id") == proposal$preset_id)
  if (length(index) != 1L) .sc_project_fail("Unsupported MAD preset; model-generated thresholds, genes, code or extra operations are not executable.")
  panel <- record$summary$presets[[index]]
  if (!isTRUE(panel$available)) .sc_project_fail(paste0("MAD preset is unavailable: ", paste(panel$unavailable_reasons, collapse = " ")))
  keep <- record$selections[[proposal$preset_id]]
  if (!length(keep)) .sc_project_fail("MAD preset would remove every original cell; revise the explicit prefilter or choose a supported quality preset before approval.")
  canonical <- list(schema = "scagentkit.qc.mad.v1", rationale = rationale, risks = unname(risks),
    preset_id = unname(proposal$preset_id), panel_hash = record$panel_hash)
  retention_groups <- lapply(panel$groups, function(group) group[c("group_id", "selector", "before", "retained", "removed", "fraction_retained")])
  retention <- list(before = panel$before, retained = panel$retained, removed = panel$removed,
    fraction_retained = panel$fraction_retained, groups = retention_groups)
  list(proposal = canonical, retention = retention, keep_cells = keep, evidence_hash = qc$evidence_hash,
    panel_hash = record$panel_hash,
    summary = list(preset_id = panel$preset_id, label = panel$label, rule = panel$rule,
      original_cells = panel$before, pre_score_cells = panel$pre_score, post_qc_cells = panel$retained,
      prefilter_removed = panel$before - panel$pre_score, quality_removed = panel$quality_removed,
      groups = panel$groups, high_rna_action = "flag only", ribo_hb_action = "diagnostic only"))
}
