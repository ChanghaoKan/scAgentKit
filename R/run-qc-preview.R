# A local, pure impact calculation for typed QC. This object contains literal
# cell IDs and per-cell measurements and is never an AI aggregate payload.
.sc_run_qc_preview_cells_hash <- function(cells) {
  .sc_project_sha_text(.sc_project_json(.sc_project_array(cells)))
}

.sc_run_qc_preview_population <- function(metrics, indices) {
  list(cells = length(indices), metrics = stats::setNames(
    lapply(c("nCount", "nFeature", "percent_mt"), function(metric)
      .sc_run_qc_distribution(metrics[[metric]][indices])),
    c("nCount", "nFeature", "percent_mt")))
}

.sc_run_qc_preview_distributions <- function(metrics, keep) {
  population <- function(indices) {
    list(before = .sc_run_qc_preview_population(metrics, indices),
         retained = .sc_run_qc_preview_population(metrics, indices[keep[indices]]),
         removed = .sc_run_qc_preview_population(metrics, indices[!keep[indices]]))
  }
  grouped <- .sc_run_qc_groups(metrics)
  list(global = population(seq_len(nrow(metrics))),
       groups = lapply(seq_along(grouped), function(i) {
         group <- grouped[[i]]
         c(list(group_id = paste0("group", i), selector = group$selector),
           population(group$indices))
       }))
}

.sc_run_qc_preview_gene_panels <- function(gene_panels, evidence) {
  if (!is.list(gene_panels) || (length(gene_panels) &&
      (is.null(names(gene_panels)) || anyNA(names(gene_panels)) ||
       any(!nzchar(names(gene_panels))) || anyDuplicated(names(gene_panels)))))
    .sc_project_fail("QC gene panels must be a named list with unique nonempty panel names.")
  for (panel in gene_panels) {
    if (!is.character(panel) || !length(panel) || anyNA(panel) ||
        any(!nzchar(panel)) || anyDuplicated(panel))
      .sc_project_fail("Every QC gene panel must contain unique, nonempty literal feature IDs.")
  }
  features <- evidence$feature_ids
  known <- !is.null(features)
  if (known) {
    .sc_project_ids(features, "QC evidence feature IDs")
    if (!identical(.sc_run_qc_preview_cells_hash(features), evidence$features_hash))
      .sc_project_fail("QC evidence feature IDs changed; regenerate evidence before reviewing gene availability.")
  }
  list(parameters = gene_panels,
       records = lapply(seq_along(gene_panels), function(i) {
         genes <- gene_panels[[i]]
         list(id = names(gene_panels)[i], requested_genes = genes,
              availability_assessed = known,
              available_genes = if (known) genes[genes %in% features] else character(),
              unavailable_genes = if (known) genes[!genes %in% features] else character(),
              unknown_genes = if (known) character() else genes,
              expression_assessed = FALSE,
              interpretation = paste(
                "Only exact feature availability is assessed; no expression matrix was supplied to this preview.",
                "Unavailable genes are unknown measurements, not zero expression.",
                "Positive marker expression is not a quality standard or proof of cell identity."))
       }))
}

.sc_run_qc_preview_build <- function(proposal, evidence, sensitivity = list(),
                                     gene_panels = list(), retained_scope = NULL) {
  .sc_run_qc_rules_preview_build(proposal, evidence, sensitivity, gene_panels, retained_scope)
}

.sc_run_qc_rules_preview_build <- function(proposal, evidence, sensitivity = list(), gene_panels = list(), retained_scope = NULL) {
  evaluated <- .sc_run_qc_rules_evaluate(proposal, evidence, retained_scope)
  validated <- evaluated$validated; metrics <- evidence$metrics; cells <- metrics$cell_id
  keep <- evaluated$keep; base <- evaluated$base; statuses <- evaluated$statuses
  rule_ids <- if (length(statuses)) paste0("rule", seq_along(statuses)) else character()
  failures <- evaluated$failures; prior_excluded <- evaluated$prior_excluded
  dimnames(failures) <- list(NULL, rule_ids)
  failure_count <- rowSums(failures)
  if (!is.list(sensitivity) || (length(sensitivity) && !is.null(names(sensitivity))) || length(sensitivity) > 6L)
    .sc_project_fail("QC sensitivity must be an array of at most six explicit typed candidates.")
  candidates <- lapply(sensitivity, function(item) {
    .sc_run_strategy_fields(item, c("id", "proposal"), name = "QC sensitivity candidate")
    .sc_project_string(item$id, "sensitivity$id")
    if (identical(item$id, "primary")) .sc_project_fail("QC sensitivity candidate ID 'primary' is reserved for the reviewed proposal.")
    list(id = item$id, validated = .sc_run_qc_validate(item$proposal, evidence, retained_scope))
  })
  if (anyDuplicated(vapply(candidates, `[[`, character(1), "id")))
    .sc_project_fail("QC sensitivity candidate IDs must be unique.")
  panels <- .sc_run_qc_preview_gene_panels(gene_panels, evidence)
  impacts <- lapply(seq_along(statuses), function(i) {
    status <- statuses[[i]]
    exclusive <- base & !keep & status$failed & failure_count == 1L
    list(id = rule_ids[i], filter = status$rule, scope_cells = cells[status$selected], scoped = sum(status$selected),
      low_cells = cells[status$low], low = sum(status$low), high_cells = cells[status$high], high = sum(status$high),
      unavailable_cells = cells[status$unavailable], unavailable = sum(status$unavailable),
      independently_removed_cells = cells[status$failed], independently_removed = sum(status$failed),
      exclusively_removed_cells = cells[exclusive], exclusively_removed = sum(exclusive),
      primary_retained_in_scope = sum(status$selected & keep), primary_removed_in_scope = sum(status$selected & !keep))
  })
  fail_ids <- lapply(seq_along(cells), function(i) rule_ids[failures[i, ]])
  missing_ids <- lapply(seq_along(cells), function(i)
    rule_ids[vapply(statuses, function(status) status$unavailable[i], logical(1))])
  reason_ids <- lapply(seq_along(cells), function(i) as.character(c(if (!base[i]) "prefilter_excluded" else character(),
    if (prior_excluded[i]) "prior_excluded" else character(),
    unlist(lapply(seq_along(statuses), function(j) {
      if (!statuses[[j]]$failed[i]) return(character())
      if (identical(statuses[[j]]$rule$op, "mad_preset")) paste0(rule_ids[j], ":mad_preset") else
        if (statuses[[j]]$low[i]) paste0(rule_ids[j], ":low") else paste0(rule_ids[j], ":high")
    }), use.names = FALSE))))
  keys <- vapply(seq_along(cells), function(i) paste(paste(reason_ids[[i]], collapse = ","),
    paste(missing_ids[[i]], collapse = ","), sep = "|"), character(1))
  patterns <- lapply(unique(keys), function(key) {
    indices <- which(keys == key); first <- indices[1L]
    list(filter_ids = fail_ids[[first]], reason_ids = reason_ids[[first]],
      unavailable_filter_ids = missing_ids[[first]], prefilter_excluded = !base[first],
      prior_excluded = prior_excluded[first],
      count = length(indices), cell_ids = cells[indices], retained = sum(keep[indices]), removed = sum(!keep[indices]))
  })
  overlap <- crossprod(failures * 1L); storage.mode(overlap) <- "integer"
  comparisons <- lapply(candidates, function(candidate) {
    checked <- candidate$validated; candidate_keep <- cells %in% checked$keep_cells
    common <- keep & candidate_keep; union <- keep | candidate_keep; groups <- .sc_run_qc_groups(metrics)
    list(id = candidate$id, proposal = checked$proposal, retention = checked$retention,
      keep_cells = cells[candidate_keep], remove_cells = cells[!candidate_keep],
      keep_cell_hash = .sc_run_qc_preview_cells_hash(cells[candidate_keep]),
      intersection_cells = cells[common], intersection = sum(common), added_cells = cells[candidate_keep & !keep],
      added = sum(candidate_keep & !keep), removed_from_primary_cells = cells[keep & !candidate_keep],
      removed_from_primary = sum(keep & !candidate_keep), jaccard = sum(common) / sum(union),
      groups = lapply(seq_along(groups), function(i) {
        group <- groups[[i]]; indices <- group$indices
        list(group_id = paste0("group", i), selector = group$selector, before = length(indices),
          primary_retained = sum(keep[indices]), retained = sum(candidate_keep[indices]),
          added_cells = cells[indices[candidate_keep[indices] & !keep[indices]]],
          removed_from_primary_cells = cells[indices[keep[indices] & !candidate_keep[indices]]])
      }))
  })
  result <- list(schema = "scagentkit.qc.preview.v1", evidence_hash = validated$evidence_hash,
    diagnostic_replacements = if (is.null(validated$summary$effective_thresholds)) NULL else
      validated$summary[c("effective_thresholds", "replacement_impact")],
    canonical_parameters = list(proposal = validated$proposal,
      sensitivity = lapply(candidates, function(candidate) list(id = candidate$id, proposal = candidate$validated$proposal)),
      gene_panels = panels$parameters), retention = validated$retention,
    keep_cells = cells[keep], remove_cells = cells[!keep],
    keep_cell_hash = .sc_run_qc_preview_cells_hash(cells[keep]), remove_cell_hash = .sc_run_qc_preview_cells_hash(cells[!keep]),
    metrics = metrics, filter_impacts = impacts, patterns = patterns,
    overlap = list(filter_ids = rule_ids, counts = lapply(seq_along(rule_ids), function(i) unname(as.list(overlap[i, ]))),
      interpretation = "Counts represent overlapping measured failure predicates within prefilter eligibility; unavailable measurements are disclosed separately. Independent counts must not be added."),
    rule_logic = list(schema = "scagentkit.qc.rule-logic.v1", remove_if = validated$proposal$remove_if,
      rule_ids = rule_ids, prefilter_applied = !is.null(evidence$mad_record$prefilter_record),
      prefilter_eligible_cells = cells[base], prefilter_excluded_cells = cells[!base],
      prefilter_removed = sum(!base), prior_excluded_cells = cells[prior_excluded],
      prior_removed = sum(prior_excluded), quality_removed = validated$summary$quality_removed, final_retained = sum(keep)),
    distributions = .sc_run_qc_preview_distributions(metrics, keep),
    unavailable = list(metrics = lapply(c("nCount", "nFeature", "percent_mt"), function(metric) {
      missing <- !is.finite(metrics[[metric]]); list(metric = metric, count = sum(missing), cell_ids = cells[missing])
    }), zero_count_cells = cells[is.finite(metrics$nCount) & metrics$nCount == 0],
      mitochondrial = evidence$summary$mitochondrial, gene_panels = panels$records), sensitivity = comparisons,
    interpretation = c("An empty rules array adds no filtering and does not restore cells excluded by previously committed QC or doublet selection.",
      "For nonempty rules, any means OR of failures; all means AND of failures. These are deletion predicates, not passing conditions.",
      "Range boundaries are inclusive; only strict below/above measurements fail. Group selectors use exact declared sample/capture literals.",
      "Prefilter exclusions are mandatory and cannot be restored by either combination. Doublet marking/removal is a separate approved choice.",
      "Independent failure counts overlap; only the final exact removal set is the deduplicated cell total.",
      "Sensitivity candidates are explicit comparisons, not suggested optimal thresholds.",
      "Unavailable measurements are not zero and cannot silently authorize retention or deletion.",
      "MAD predicates use the saved exact candidate panel; no multiplier, threshold or grouping is invented.",
      "All exact cell IDs, measurements, flags and rule intersections remain local."))
  if (!is.null(evidence$mad_record)) {
    result$mad_panel <- evidence$mad_record$summary; result$mad_flags <- evidence$mad_record$flags
  }
  result
}
