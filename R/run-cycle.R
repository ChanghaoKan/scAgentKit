# Cell-cycle diagnostics are a nonfiltering, local full-input reference. Only
# summary is suitable for a model request; scores and literal IDs stay private.

.sc_run_cycle_species <- function(species, name = "species") {
  .sc_project_string(species, name)
  .sc_run_species(species, allow_missing = FALSE)
}

.sc_run_cycle_gene_hash <- function(value) {
  value$gene_set_hash <- NULL
  .sc_run_hash(value)
}

#' Declare a literal, versioned cell-cycle gene set
#'
#' Human defaults load only the installed Seurat package's
#' `cc.genes.updated.2019` data. Mouse data require explicitly supplied lists.
#' No capitalization conversion, synonym search, or ortholog inference occurs.
#' Custom lists require a source and version. An optional named mapping must
#' cover every canonical symbol exactly once and map to unique input symbols.
#'
#' @param species Explicit human or mouse species declaration.
#' @param s_genes,g2m_genes Literal S and G2/M symbols, both supplied or both NULL.
#' @param source,version Nonempty provenance strings for custom lists.
#' @param symbol_mapping Optional named character vector from canonical symbols
#'   to literal input symbols, covering the complete union of both gene lists.
#' @return A versioned gene-set declaration for `sc_run(cycle_diagnostics=...)`.
#' @export
sc_cycle_gene_set <- function(species, s_genes = NULL, g2m_genes = NULL,
                              source = NULL, version = NULL,
                              symbol_mapping = NULL) {
  species <- .sc_run_cycle_species(species)
  builtin <- is.null(s_genes) && is.null(g2m_genes)
  package <- NULL
  if (builtin) {
    if (!identical(species, "human"))
      .sc_project_fail("Mouse cell-cycle scoring requires explicit, versioned literal S and G2/M gene lists; human symbols are never converted automatically.")
    if (!is.null(source) || !is.null(version))
      .sc_project_fail("Built-in gene-set source and version are fixed; provide both custom gene lists to declare another source.")
    if (!requireNamespace("Seurat", quietly = TRUE))
      .sc_project_fail("Seurat is unavailable; install it explicitly before loading cc.genes.updated.2019.")
    env <- new.env(parent = baseenv())
    loaded <- tryCatch({
      utils::data(list = "cc.genes.updated.2019", package = "Seurat", envir = env)
      exists("cc.genes.updated.2019", envir = env, inherits = FALSE)
    }, warning = function(w) FALSE, error = function(e) FALSE)
    if (!isTRUE(loaded))
      .sc_project_fail("Installed Seurat does not provide cc.genes.updated.2019 package data; supply explicitly versioned custom lists. No fallback gene set is used.")
    cc <- get("cc.genes.updated.2019", envir = env, inherits = FALSE)
    if (!is.list(cc) || is.null(cc$s.genes) || is.null(cc$g2m.genes))
      .sc_project_fail("Installed cc.genes.updated.2019 package data are malformed.")
    s_genes <- cc$s.genes; g2m_genes <- cc$g2m.genes
    source <- "Seurat::cc.genes.updated.2019"; version <- "2019"
    package <- list(name = "Seurat", version = as.character(utils::packageVersion("Seurat")),
                    data = "cc.genes.updated.2019")
  } else {
    if (is.null(s_genes) || is.null(g2m_genes))
      .sc_project_fail("Supply both custom S and G2/M lists; partial fallback is not supported.")
    .sc_project_string(source, "gene_set source")
    .sc_project_string(version, "gene_set version")
    if (!nzchar(trimws(source)) || !nzchar(trimws(version)))
      .sc_project_fail("Custom gene-set source and version must contain nonempty text.")
  }
  .sc_project_ids(s_genes, "S gene symbols")
  .sc_project_ids(g2m_genes, "G2/M gene symbols")
  canonical_s <- unname(s_genes); canonical_g2m <- unname(g2m_genes)
  symbols <- unique(c(canonical_s, canonical_g2m))
  if (!is.null(symbol_mapping)) {
    if (!is.character(symbol_mapping) || is.null(names(symbol_mapping)) ||
        anyNA(symbol_mapping) || any(!nzchar(symbol_mapping)) ||
        anyDuplicated(symbol_mapping) || anyNA(names(symbol_mapping)) ||
        any(!nzchar(names(symbol_mapping))) || anyDuplicated(names(symbol_mapping)) ||
        !setequal(names(symbol_mapping), symbols))
      .sc_project_fail("symbol_mapping must be an explicit one-to-one named canonical-to-input mapping covering every declared symbol exactly; no ortholog or case inference is performed.")
    symbol_mapping <- symbol_mapping[symbols]
    s_genes <- unname(symbol_mapping[canonical_s])
    g2m_genes <- unname(symbol_mapping[canonical_g2m])
  }
  result <- list(schema = "scagentkit.cycle-gene-set.v1", species = species,
    source = unname(source), version = unname(version),
    canonical_s_genes = canonical_s, canonical_g2m_genes = canonical_g2m,
    s_genes = unname(s_genes), g2m_genes = unname(g2m_genes),
    symbol_mapping = symbol_mapping, package = package)
  result$gene_set_hash <- .sc_run_cycle_gene_hash(result)
  result
}

.sc_run_cycle_gene_verify <- function(value) {
  fields <- c("schema", "species", "source", "version", "canonical_s_genes",
              "canonical_g2m_genes", "s_genes", "g2m_genes", "symbol_mapping",
              "package", "gene_set_hash")
  if (!is.list(value) || !identical(sort(names(value)), sort(fields)) ||
      !identical(value$schema, "scagentkit.cycle-gene-set.v1") ||
      !identical(value$gene_set_hash, .sc_run_cycle_gene_hash(value)))
    .sc_project_fail("Cell-cycle gene_set must be an intact declaration from sc_cycle_gene_set().")
  .sc_run_cycle_species(value$species)
  for (field in c("s_genes", "g2m_genes", "canonical_s_genes", "canonical_g2m_genes"))
    .sc_project_ids(value[[field]], paste0("gene_set$", field))
  invisible(TRUE)
}

.sc_run_cycle_options <- function(context, options) {
  if (is.null(options) || identical(options, FALSE)) return(NULL)
  if (!is.list(context) || is.null(context$species))
    .sc_project_fail("Cell-cycle diagnostics require explicit context$species matching the declared gene set.")
  species <- .sc_run_cycle_species(context$species, "context$species")
  fields <- c("gene_set", "column_prefix", "seed", "scale_factor", "nbin", "ctrl", "min_genes", "min_fraction")
  canonical <- is.list(options) && identical(options$schema, "scagentkit.cycle-options.v1")
  if (canonical) {
    if (!identical(options$species, species))
      .sc_project_fail("Cell-cycle options species does not match context$species.")
    options$schema <- NULL; options$species <- NULL
  }
  if (!is.list(options) || is.null(names(options)) || anyNA(names(options)) ||
      any(!nzchar(names(options))) || anyDuplicated(names(options)) ||
      !"gene_set" %in% names(options) || length(setdiff(names(options), fields)))
    .sc_project_fail("cycle_diagnostics must explicitly supply gene_set and only supported diagnostic options.")
  .sc_run_cycle_gene_verify(options$gene_set)
  if (!identical(options$gene_set$species, species))
    .sc_project_fail("Cell-cycle gene-set species does not match explicit context$species.")
  defaults <- list(column_prefix = "sc_cycle", seed = 17L, scale_factor = 10000,
                   nbin = 12L, ctrl = 5L, min_genes = 5L, min_fraction = .2)
  for (name in names(defaults)) if (is.null(options[[name]])) options[[name]] <- defaults[[name]]
  .sc_project_string(options$column_prefix, "cycle_diagnostics$column_prefix")
  if (!grepl("^[A-Za-z][A-Za-z0-9_.]*$", options$column_prefix))
    .sc_project_fail("Cycle column_prefix must start with a letter and contain only letters, digits, underscores, and periods.")
  for (name in c("seed", "nbin", "ctrl", "min_genes")) {
    lower <- switch(name, seed = 0, nbin = 2, 1)
    options[[name]] <- .sc_run_strategy_runtime_number(options[[name]], paste0("cycle ", name),
                                                    lower, .Machine$integer.max, integer = TRUE)
  }
  options$scale_factor <- .sc_run_strategy_runtime_number(options$scale_factor, "cycle scale_factor", 0, lower_open = TRUE)
  options$min_fraction <- .sc_run_strategy_runtime_number(options$min_fraction, "cycle min_fraction", 0, 1)
  c(list(schema = "scagentkit.cycle-options.v1", species = species), options[fields])
}

.sc_run_cycle_columns <- function(prefix) {
  stats::setNames(paste0(prefix, c("_S.Score", "_G2M.Score", "_Phase", "_CC.Difference")),
                  c("s_score", "g2m_score", "phase", "difference"))
}

.sc_run_cycle_seed <- function(seed, operation) {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv, inherits = FALSE) else NULL
  on.exit({
    if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv) else
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
        rm(".Random.seed", envir = .GlobalEnv)
  }, add = TRUE)
  set.seed(seed)
  operation()
}

.sc_run_cycle_control_check <- function(data, pool, genes, options) {
  if (length(pool) < options$nbin)
    return(list(applicable = FALSE, reason = "Expressed control pool has fewer features than the declared number of bins."))
  averages <- Matrix::rowMeans(data[pool, , drop = FALSE])
  averages <- averages[order(averages)]
  bins <- .sc_run_cycle_seed(options$seed, function() tryCatch(
    ggplot2::cut_number(averages + stats::rnorm(length(averages)) / 1e30,
                       n = options$nbin, labels = FALSE, right = FALSE),
    error = function(e) {
      if (grepl("Insufficient data values|breaks.*not unique|invalid number of intervals", conditionMessage(e)))
        return(NULL)
      .sc_project_fail(paste0("Cell-cycle control-bin computation failed; retry after resolving the underlying error: ", conditionMessage(e)))
    }))
  if (is.null(bins))
    return(list(applicable = FALSE, reason = "Expressed feature averages cannot support the declared equal-frequency control bins."))
  names(bins) <- names(averages)
  sizes <- table(bins)
  available <- as.integer(sizes[as.character(bins[genes])])
  if (anyNA(available) || any(available < options$ctrl))
    return(list(applicable = FALSE, reason = "A scored gene's expression bin has fewer available controls than declared ctrl.",
                min_control_pool = if (anyNA(available)) 0L else min(available)))
  list(applicable = TRUE, min_control_pool = min(available))
}

.sc_run_cycle_hash <- function(record) {
  record$evidence_hash <- NULL
  .sc_run_hash(record)
}

.sc_run_cycle_cell_counts <- function(counts, cells) {
  stats::setNames(vapply(cells, function(cell)
    .sc_project_sparse_hash(.sc_project_matrix(counts[, cell, drop = FALSE],
                                              "Cycle source counts", raw_counts = TRUE)), character(1)), cells)
}

.sc_run_cycle_evidence <- function(seu, config) {
  seu <- .sc_project_unwrap(seu)
  .sc_run_strategy_runtime_dependencies(c("Seurat", "SeuratObject", "Matrix", "ggplot2", "digest"))
  options <- .sc_run_cycle_options(config$context, config$cycle_diagnostics)
  if (is.null(options)) .sc_project_fail("Cell-cycle evidence requires explicitly enabled cycle_diagnostics.")
  assay <- config$assay; counts_layer <- config$counts_layer
  .sc_project_string(assay, "cycle assay"); .sc_project_string(counts_layer, "cycle counts_layer")
  if (grepl("^(data|scale\\.data|normalized)(\\.|$)", counts_layer, ignore.case = TRUE))
    .sc_project_fail("Cell-cycle diagnostics require genuine raw counts.")
  counts <- .sc_project_layer(seu, assay, counts_layer, raw_counts = TRUE)
  cells <- colnames(seu); .sc_project_ids(cells, "Cycle source cell IDs")
  if (!setequal(colnames(counts), cells) || !identical(rownames(seu[[]]), cells))
    .sc_project_fail("Cell-cycle counts and metadata must cover every source cell exactly.")
  columns <- .sc_run_cycle_columns(options$column_prefix)
  if (any(columns %in% names(seu[[]])))
    .sc_project_fail("Cell-cycle output column already exists; choose a fresh column_prefix to preserve source metadata.")
  features <- rownames(counts); genes <- options$gene_set
  expressed <- features[as.numeric(Matrix::rowSums(counts)) > 0]
  coverage <- lapply(list(S = genes$s_genes, G2M = genes$g2m_genes), function(symbols) {
    present <- intersect(symbols, features); measured <- intersect(symbols, expressed)
    list(requested = length(symbols), present = length(present), expressed = length(measured),
         present_fraction = length(present) / length(symbols),
         expressed_fraction = length(measured) / length(symbols))
  })
  s_use <- intersect(genes$s_genes, expressed); g2m_use <- intersect(genes$g2m_genes, expressed)
  reasons <- character()
  for (phase in names(coverage)) {
    item <- coverage[[phase]]
    if (item$expressed < options$min_genes || item$expressed_fraction < options$min_fraction)
      reasons <- c(reasons, paste0(phase, " expressed gene coverage does not meet the declared software prerequisites."))
  }
  score <- data.frame(cell_id = cells, stringsAsFactors = FALSE, check.names = FALSE)
  score[[columns[["s_score"]]]] <- rep(NA_real_, length(cells))
  score[[columns[["g2m_score"]]]] <- rep(NA_real_, length(cells))
  score[[columns[["phase"]]]] <- rep("Unknown", length(cells))
  score[[columns[["difference"]]]] <- rep(NA_real_, length(cells))
  control <- list(applicable = FALSE, reason = "Gene coverage is insufficient.")
  # A fresh diagnostic assay isolates normalization from existing source data,
  # split layers, HVGs, and reductions. Source cells/metadata remain untouched.
  scratch <- Seurat::CreateSeuratObject(counts = counts[, cells, drop = FALSE],
                                       assay = assay, min.cells = 0, min.features = 0)
  if (!identical(colnames(scratch), cells) || !identical(rownames(scratch[[assay]]), features))
    .sc_project_fail("Diagnostic assay construction changed literal cell or feature IDs; explicitly prepare supported feature symbols before retrying.")
  scratch <- Seurat::NormalizeData(scratch, assay = assay, normalization.method = "LogNormalize",
                                   scale.factor = options$scale_factor, verbose = FALSE)
  data <- .sc_project_layer(scratch, assay, "data")
  if (!length(reasons)) {
    control <- .sc_run_cycle_control_check(data, expressed, unique(c(s_use, g2m_use)), options)
    if (!isTRUE(control$applicable)) reasons <- c(reasons, control$reason) else {
      scored <- .sc_run_cycle_seed(options$seed, function() tryCatch(
        Seurat::CellCycleScoring(scratch, s.features = s_use, g2m.features = g2m_use,
                                assay = assay, pool = expressed, slot = "data", seed = options$seed,
                                nbin = options$nbin, ctrl = options$ctrl,
                                search = FALSE, set.ident = FALSE),
        error = function(e) {
          message <- conditionMessage(e)
          if (grepl("Insufficient data values|breaks.*not unique|cannot take a sample larger than the population", message))
            return(list(insufficient_reason = message))
          .sc_project_fail(paste0("Cell-cycle scoring failed; resolve the underlying dependency or runtime error and retry: ", message))
        }))
      if (is.list(scored) && !inherits(scored, "Seurat") && !is.null(scored$insufficient_reason)) {
        reasons <- c(reasons, paste0("Declared control-bin scoring is numerically inapplicable: ", scored$insufficient_reason))
      } else {
        measured <- scored[[]][cells, c("S.Score", "G2M.Score", "Phase"), drop = FALSE]
        if (nrow(measured) != length(cells) || !identical(rownames(measured), cells) ||
            !is.numeric(measured$S.Score) || !is.numeric(measured$G2M.Score))
          .sc_project_fail("Cell-cycle scoring did not return numeric scores for the exact source cell IDs.")
        if (any(!is.finite(measured$S.Score)) || any(!is.finite(measured$G2M.Score))) {
          reasons <- c(reasons, "Cell-cycle scoring produced nonfinite values; the reference is insufficient.")
        } else {
          if (anyNA(measured$Phase) || any(!as.character(measured$Phase) %in% c("G1", "S", "G2M", "Undecided")))
            .sc_project_fail("Cell-cycle scoring returned invalid phase labels.")
          score[[columns[["s_score"]]]] <- measured$S.Score
          score[[columns[["g2m_score"]]]] <- measured$G2M.Score
          score[[columns[["phase"]]]] <- as.character(measured$Phase)
          score[[columns[["difference"]]]] <- measured$S.Score - measured$G2M.Score
        }
      }
    }
  }
  status <- if (length(reasons)) "insufficient" else "available"
  phase_counts <- table(factor(score[[columns[["phase"]]]], levels = c("G1", "S", "G2M", "Undecided", "Unknown")))
  summary <- list(schema = "scagentkit.cycle.evidence.v1", status = status,
    reasons = unname(reasons), assay = assay, counts_layer = counts_layer,
    species = options$species, columns = columns, cells = length(cells), features = length(features),
    cohort = list(input_cells = length(cells), scored_cells = if (status == "available") length(cells) else 0L,
                  unknown_cells = if (status == "insufficient") length(cells) else 0L, removed_cells = 0L),
    gene_set = list(source = genes$source, version = genes$version, species = genes$species,
                    package = genes$package, hash = genes$gene_set_hash,
                    mapping_explicit = !is.null(genes$symbol_mapping),
                    symbol_mapping = genes$symbol_mapping,
                    s_genes = genes$s_genes, g2m_genes = genes$g2m_genes,
                    canonical_s_genes = genes$canonical_s_genes,
                    canonical_g2m_genes = genes$canonical_g2m_genes),
    coverage = coverage, control = control,
    options = options[c("column_prefix", "seed", "scale_factor", "nbin", "ctrl", "min_genes", "min_fraction")],
    normalization = list(method = "LogNormalize", scale_factor = options$scale_factor,
                         source = "genuine raw counts", layer = "data", scope = "isolated diagnostic copy"),
    scoring = list(function_name = "Seurat::CellCycleScoring", assay = assay, slot = "data",
                   pool = "all expressed input features", pool_features = length(expressed),
                   seed = options$seed, nbin = options$nbin, ctrl = options$ctrl,
                   search = FALSE, set_ident = FALSE,
                   seurat_version = as.character(utils::packageVersion("Seurat"))),
    reference = "fixed_full_input", refit_after_qc = FALSE,
    phase_counts = stats::setNames(as.list(as.integer(phase_counts)), names(phase_counts)),
    score_distributions = stats::setNames(lapply(columns[c("s_score", "g2m_score", "difference")],
                                     function(column) .sc_run_qc_distribution(score[[column]])),
                                    c("s_score", "g2m_score", "difference")),
    interpretation = c("Diagnostic full-input scores never filter or remove cells.",
      "Gene coverage, bin/control capacity, variance, and rank are software prerequisites, not scientific thresholds.",
      "Post-QC cells reuse this fixed full-input scoring reference without refitting controls or normalization.",
      "Phase is a gene-set heuristic; regression requires an explicit reviewed none/full/difference choice."))
  record <- list(summary = summary, scores = score, options = options, gene_set = genes,
    cell_ids = cells, feature_ids = features,
    matched_genes = list(S = s_use, G2M = g2m_use), expressed_pool = expressed,
    normalization_hash = .sc_project_sparse_hash(data),
    counts_hash = .sc_project_sparse_hash(counts),
    count_cell_hashes = .sc_run_cycle_cell_counts(counts, cells),
    cell_hash = .sc_run_hash(cells), features_hash = .sc_run_hash(features),
    gene_set_hash = genes$gene_set_hash, options_hash = .sc_run_hash(options), scores_hash = .sc_run_hash(score))
  record$evidence_hash <- .sc_run_cycle_hash(record)
  record
}

.sc_run_cycle_verify <- function(record) {
  if (!is.list(record) || !is.list(record$summary) ||
      !identical(record$summary$schema, "scagentkit.cycle.evidence.v1") ||
      !(identical(record$summary$status, "available") || identical(record$summary$status, "insufficient")) ||
      !identical(record$evidence_hash, .sc_run_cycle_hash(record)))
    .sc_project_fail("Cell-cycle evidence is missing or changed; regenerate it and obtain fresh review.")
  .sc_run_cycle_gene_verify(record$gene_set)
  canonical <- .sc_run_cycle_options(list(species = record$options$species), record$options)
  .sc_project_ids(record$cell_ids, "Cycle reference cell IDs")
  .sc_project_ids(record$feature_ids, "Cycle reference feature IDs")
  columns <- .sc_run_cycle_columns(record$options$column_prefix)
  if (!identical(record$options, canonical) || !identical(record$summary$columns, columns) ||
      !identical(record$cell_hash, .sc_run_hash(record$cell_ids)) ||
      !identical(record$features_hash, .sc_run_hash(record$feature_ids)) ||
      !identical(record$gene_set_hash, record$gene_set$gene_set_hash) ||
      !identical(record$options_hash, .sc_run_hash(record$options)) ||
      !identical(record$scores_hash, .sc_run_hash(record$scores)) ||
      !identical(record$options$gene_set, record$gene_set) ||
      !is.data.frame(record$scores) || !identical(names(record$scores), c("cell_id", unname(columns))) ||
      !identical(record$scores$cell_id, record$cell_ids) ||
      !identical(names(record$count_cell_hashes), record$cell_ids) ||
      anyNA(record$count_cell_hashes))
    .sc_project_fail("Cell-cycle reference identity, score, option, or gene-set hashes are inconsistent.")
  if (identical(record$summary$status, "insufficient") &&
      (!all(record$scores[[columns[["phase"]]]] == "Unknown") ||
       any(!is.na(as.matrix(record$scores[, unname(columns[c("s_score", "g2m_score", "difference")]), drop = FALSE])))))
    .sc_project_fail("Insufficient cell-cycle evidence must contain Unknown phases and missing scores.")
  if (identical(record$summary$status, "available")) {
    numeric_columns <- unname(columns[c("s_score", "g2m_score", "difference")])
    if (any(!vapply(record$scores[, numeric_columns, drop = FALSE], is.numeric, logical(1))) ||
        any(!is.finite(as.matrix(record$scores[, numeric_columns, drop = FALSE]))) ||
        anyNA(record$scores[[columns[["phase"]]]]) ||
        any(!record$scores[[columns[["phase"]]]] %in% c("G1", "S", "G2M", "Undecided")) ||
        !identical(record$scores[[columns[["difference"]]]],
                   record$scores[[columns[["s_score"]]]] - record$scores[[columns[["g2m_score"]]]]))
      .sc_project_fail("Available cell-cycle reference must have finite scores, valid phases, and an exact S-minus-G2M difference.")
  }
  invisible(TRUE)
}

.sc_run_cycle_attach <- function(seu, record) {
  .sc_run_cycle_verify(record)
  seu <- .sc_project_unwrap(seu)
  cells <- colnames(seu); .sc_project_ids(cells, "Retained cycle cell IDs")
  if (any(!cells %in% record$cell_ids))
    .sc_project_fail("Retained cells do not exactly match the fixed full-input cell-cycle reference.")
  columns <- record$summary$columns
  if (any(columns %in% names(seu[[]])))
    .sc_project_fail("Cell-cycle output column already exists; choose a fresh column_prefix before attachment.")
  metadata <- seu[[]]
  if (!identical(rownames(metadata), cells))
    .sc_project_fail("Retained metadata must follow the exact cell order before cycle attachment.")
  counts <- .sc_project_layer(seu, record$summary$assay, record$summary$counts_layer, raw_counts = TRUE)
  if (!identical(rownames(counts), record$feature_ids) || !setequal(colnames(counts), cells) ||
      !identical(.sc_run_cycle_cell_counts(counts, cells), record$count_cell_hashes[cells]))
    .sc_project_fail("Retained raw counts or literal feature IDs changed from the fixed full-input cycle reference.")
  values <- record$scores[match(cells, record$scores$cell_id), unname(columns), drop = FALSE]
  rownames(values) <- cells
  seu <- SeuratObject::AddMetaData(seu, metadata = values)
  if (!identical(colnames(seu), cells) ||
      !identical(seu[[]][, names(metadata), drop = FALSE], metadata))
    .sc_project_fail("Cell-cycle attachment changed original source metadata or literal cell order.")
  seu
}

.sc_run_cycle_validate_choice <- function(choice, record, keep_cells) {
  .sc_run_cycle_verify(record)
  if (!is.list(choice) || !identical(sort(names(choice)), c("method", "reason")))
    .sc_project_fail("Cycle choice requires exactly method and reason; arbitrary regressors or cell deletion are unsupported.")
  .sc_project_string(choice$method, "cycle$method"); .sc_project_string(choice$reason, "cycle$reason")
  if (!choice$method %in% c("none", "full", "difference") || !nzchar(trimws(choice$reason)))
    .sc_project_fail("Cycle choice must explicitly select none, full, or difference and give a nonempty reason.")
  .sc_project_ids(keep_cells, "Retained cycle cell IDs")
  if (any(!keep_cells %in% record$cell_ids))
    .sc_project_fail("Cycle choice retained cells are absent from the fixed full-input reference.")
  columns <- record$summary$columns
  regressors <- switch(choice$method, none = character(),
                        full = unname(columns[c("s_score", "g2m_score")]),
                        difference = unname(columns[["difference"]]))
  rank <- 0L; design_columns <- 0L; variance <- numeric()
  if (length(regressors)) {
    if (!identical(record$summary$status, "available"))
      .sc_project_fail("Cycle regression is inapplicable because the fixed scoring reference is insufficient; choose none or regenerate explicitly.")
    values <- record$scores[match(keep_cells, record$cell_ids), regressors, drop = FALSE]
    if (any(!vapply(values, is.numeric, logical(1))) || any(!is.finite(as.matrix(values))))
      .sc_project_fail("Cycle regressors must be finite numeric scores for every actually retained cell.")
    variance <- vapply(values, stats::var, numeric(1))
    if (any(!is.finite(variance)) || any(variance <= 0))
      .sc_project_fail("Cycle regression is inapplicable: a selected regressor has zero or unavailable variance in actually retained cells.")
    design <- cbind(intercept = 1, as.matrix(values))
    design_columns <- ncol(design); rank <- qr(design)$rank
    if (rank != design_columns || nrow(design) <= design_columns)
      .sc_project_fail("Cycle regression is inapplicable: retained-score design is rank deficient or has no residual degrees of freedom.")
  }
  list(choice = list(method = unname(choice$method), reason = unname(choice$reason)),
       method = unname(choice$method), regressors = regressors,
       applicability = list(status = "applicable", retained_cells = length(keep_cells),
                            regressor_variance = variance, design_rank = rank,
                            design_columns = design_columns,
                            scoring_status = record$summary$status,
                            reference = "fixed_full_input", refit_after_qc = FALSE),
       evidence_hash = record$evidence_hash)
}

.sc_run_cycle_plot <- function(record, path) {
  .sc_run_cycle_verify(record); .sc_project_string(path, "cycle plot path")
  grDevices::png(path, width = 960L, height = 720L, res = 120L)
  on.exit(grDevices::dev.off(), add = TRUE)
  if (identical(record$summary$status, "insufficient")) {
    graphics::plot.new()
    graphics::title("Cell-cycle diagnostics: insufficient")
    graphics::text(.5, .5, paste(strwrap(paste(record$summary$reasons, collapse = " "), 75L), collapse = "\n"))
  } else {
    columns <- record$summary$columns
    graphics::plot(record$scores[[columns[["s_score"]]]], record$scores[[columns[["g2m_score"]]]],
                   pch = 16L, cex = .45, col = grDevices::adjustcolor("#366da8", alpha.f = .45),
                   xlab = "S score", ylab = "G2/M score", main = "Fixed full-input cell-cycle reference")
    graphics::abline(h = 0, v = 0, col = "grey75", lty = 2L)
  }
  invisible(path)
}
