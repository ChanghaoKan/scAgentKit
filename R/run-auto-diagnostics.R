# Automatic diagnostics compute evidence only. Missing prerequisites remain
# explicit; no guessed capture, inferred cell calling, regression or deletion.
.sc_run_automatic_diagnostics <- function(seu, config, cycle, doublet) {
  policy <- config$input_policy
  assessments <- list()
  if (isTRUE(policy$automatic_cycle) && is.null(cycle)) {
    gene_set <- tryCatch(.sc_run_automatic_cycle_genes(seu, config$assay, config$context$species), error = function(e) e)
    if (inherits(gene_set, "error")) {
      assessments$cycle <- list(status = "unavailable", reason = conditionMessage(gene_set), regression = "none")
    } else {
      prefix <- "sc_cycle"; index <- 0L
      while (any(.sc_run_cycle_columns(prefix) %in% names(seu[[]]))) {
        index <- index + 1L; prefix <- paste0("sc_cycle_auto", index)
      }
      cycle <- list(gene_set = gene_set, column_prefix = prefix)
      assessments$cycle <- list(status = "pending_measurement", regression = "none",
        reason = "Attempt saved S/G2M scoring with actual gene coverage and control-pool guards; scoring alone authorizes no regression or cell deletion.")
    }
  } else if (!is.null(policy)) assessments$cycle <- list(status = if (is.null(cycle) || identical(cycle, FALSE)) "disabled" else "explicitly_configured",
    regression = "none", reason = "Preserve the explicit cell-cycle diagnostic configuration.")
  mode <- policy$doublet_mode
  if (!is.null(mode)) {
    if (identical(mode, "off")) {
      if (!is.null(doublet) && !identical(doublet, FALSE))
        stop("doublet='off' conflicts with explicit doublet_diagnostics; omit the diagnostics or select a scoring mode.", call. = FALSE)
      doublet <- NULL
      assessments$doublet <- list(status = "disabled", mode = mode, assessed = FALSE,
        reason = "Doublet assessment was explicitly disabled; this does not establish singlet status.")
    } else {
      requested <- config
      requested$doublet_diagnostics <- doublet
      preparation <- .sc_run_recommend_doublet_options(requested)
      if (isTRUE(preparation$ready)) {
        requested$doublet_diagnostics <- preparation$options
        guard <- tryCatch(.sc_run_recommend_facts_doublet_guard(seu, requested),
          error = function(e) list(ready = FALSE, reasons = list(conditionMessage(e))))
      } else guard <- list(ready = FALSE, reasons = c(preparation$blockers,
        lapply(preparation$missing, function(item) item$reason)))
      ready <- isTRUE(preparation$ready) && isTRUE(guard$ready)
      doublet <- if (ready) preparation$options else NULL
      assessments$doublet <- list(status = if (ready) "pending_measurement" else "unavailable", mode = mode,
        assessed = FALSE, handling = if (mode == "remove") "exact_review_required" else "flag_only",
        reasons = if (ready) list("Called-cell, capture, dependency and cohort prerequisites passed. Scores are predictions, not truth; no cells are deleted before approval.") else guard$reasons)
    }
  }
  list(cycle = cycle, doublet = doublet, assessments = assessments)
}

.sc_run_automatic_cycle_genes <- function(seu, assay, species) {
  gene_set <- sc_cycle_gene_set(species)
  features <- rownames(seu[[assay]])
  if (!any(grepl("^ENS(MUS)?G[0-9]+", features))) return(gene_set)
  metadata <- seu[[assay]][[]]
  if (anyDuplicated(rownames(metadata)) || !all(features %in% rownames(metadata)))
    stop("Feature symbol annotations do not align with the assay; supply an explicit cell-cycle gene mapping.", call. = FALSE)
  canonical <- unique(c(gene_set$canonical_s_genes, gene_set$canonical_g2m_genes))
  maps <- list()
  for (column in intersect(c("sc_feature_name", "gene_symbol", "gene_name", "symbol", "SYMBOL"), names(metadata))) {
    values <- metadata[features, column]
    if (!(is.character(values) || is.factor(values))) next
    values <- as.character(values)
    mapping <- stats::setNames(canonical, canonical)
    for (gene in canonical) {
      hit <- which(!is.na(values) & values == gene)
      if (length(hit) == 1L) mapping[[gene]] <- features[[hit]]
    }
    if (any(unname(mapping) != canonical) && !anyDuplicated(unname(mapping))) maps[[column]] <- mapping
  }
  if (!length(maps)) return(gene_set)
  if (any(!vapply(maps, identical, logical(1), maps[[1L]])))
    stop("Existing gene-symbol columns disagree about cell-cycle mapping; resolve them or supply one explicit gene set.", call. = FALSE)
  sc_cycle_gene_set(species, symbol_mapping = maps[[1L]])
}
