#!/usr/bin/env Rscript
# Source after installing this checkout in your selected private R library.
# CLI: Rscript --vanilla mad-review.R PROJECT_DIR MODE
# Modes: demo, inspect, propose-keep-all, propose-conservative-and3,
#        propose-any-quality3, approve, reject, continue, propose-unknown, output.
# Starts with no provider: local statistics finish at awaiting_configuration.
# Inspect the whole panel, then submit and approve one complete strategy.
# The synthetic controls are software fixtures, not real cell-quality truth.
# Optional doublet evidence uses the real supported capture-specific scorer.
# No key, model request, download or dependency installation is performed.

suppressPackageStartupMessages(library(scAgentKit))
if (!all(c("sc_run", "sc_run_strategy_revise", "sc_run_review",
           "sc_run_continue") %in% getNamespaceExports("scAgentKit")) ||
    !"qc_mad" %in% names(formals(sc_run)))
  stop("Install this checkout's MAD package in the selected R library first.", call. = FALSE)
mad_strategy_helpers <- system.file("examples", "analysis-strategy.R", package = "scAgentKit")
if (!nzchar(mad_strategy_helpers))
  stop("The installed package must include examples/analysis-strategy.R.", call. = FALSE)
source(mad_strategy_helpers)
rm(mad_strategy_helpers)

mad_example_input <- function() {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit(if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv) else
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
  set.seed(999L)
  genes <- c(paste0("MT-MadFixture", seq_len(6L)),
    paste0("RPSMadFixture", seq_len(6L)), paste0("RPLMadFixture", seq_len(6L)),
    "HBA1", "HBA2", "HBB", "HBD", "HBM", "HBQ1", "HBZ", "HBZP1",
    paste0("MadFixtureGene", sprintf("%04d", seq_len(574L))))
  make_capture <- function(index) {
    # Two declared comparison pools occur within each physical loading unit.
    # Non-MT count floors keep all fixture cells above the scoring prerequisite.
    values <- cbind(
      matrix(stats::rpois(600L * 120L, lambda = .6), nrow = 600L),
      matrix(stats::rpois(600L * 120L, lambda = .9), nrow = 600L))
    values[30:49, ] <- values[30:49, ] + 12L
    values[1:6, ] <- values[1:6, ] +
      matrix(stats::rpois(6L * 240L, lambda = 4), nrow = 6L)
    values[50:69, seq(1L, 240L, by = 2L)] <-
      values[50:69, seq(1L, 240L, by = 2L)] + 8L
    values[70:89, seq(2L, 240L, by = 2L)] <-
      values[70:89, seq(2L, 240L, by = 2L)] + 8L
    # These fabricated patterns exercise an AND/OR comparison, without using
    # the labels to select or tune thresholds. Counts remain >=200.
    low_pattern <- c(1:4, 121:124)
    values[, low_pattern] <- 0L
    values[1:6, low_pattern] <- 20L
    values[30:45, low_pattern] <- 8L
    high_pattern <- c(5:6, 125:126)
    values[, high_pattern] <- (values[, high_pattern, drop = FALSE] + 1L) * 4L
    dimnames(values) <- list(genes,
      paste0("mad-fixture-c", index, "-cell-", sprintf("%03d", seq_len(240L))))
    values
  }
  counts <- Matrix::Matrix(cbind(make_capture(1L), make_capture(2L)), sparse = TRUE)
  input <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  input$qc_pool <- rep(rep(c("fixture-pool-A", "fixture-pool-B"), each = 120L), 2L)
  input$capture_id <- rep(c("fixture-loading-1", "fixture-loading-2"), each = 240L)
  input$sample_id <- rep(c("fixture-sample-alpha", "fixture-sample-beta"), 240L)
  input$donor_id <- rep(rep(c("fixture-donor-u", "fixture-donor-v"), each = 20L), 12L)
  input$fixture_pattern <- rep(rep("ordinary-control", 240L), 2L)
  input$fixture_pattern[rep(c(1:4, 121:124), 2L) + rep(c(0L, 240L), each = 8L)] <-
    "fabricated-low-count-low-feature-high-mt-control"
  input$fixture_pattern[rep(c(5:6, 125:126), 2L) + rep(c(0L, 240L), each = 4L)] <-
    "fabricated-high-RNA-control"
  # Existing user metadata, including legacy names and unused factor levels,
  # remains independent of the new diagnostic output columns.
  input$doublet_score <- rep(.17, ncol(input))
  input$doublet_class <- factor(rep("legacy-unreviewed", ncol(input)),
    levels = c("legacy-unreviewed", "legacy-unused-level"))
  input$prior_annotation <- factor(rep("fixture-unresolved", ncol(input)),
    levels = c("fixture-unresolved", "prior-unused-level"))
  stopifnot(min(Matrix::colSums(counts)) >= 200)
  input
}

mad_example_context <- function() {
  list(species = "human", tissue = "synthetic expression/QC metric programs",
    columns = list(qc_group = "qc_pool", sample = "sample_id",
      capture = "capture_id", donor = "donor_id"),
    design = list(type = "Synthetic independent QC pools and expression programs across two declared captures",
      technical_batch = FALSE,
      notes = "QC pool, sample and donor labels cross captures; no observed biological or technical relationship is asserted."),
    research_goal = "Inspect fixed group statistics and finite whole-panel quality choices with exact IDs and recoverable analysis.",
    notes = paste("Synthetic raw counts only. Human is a method scope declaration, not observed human data.",
      "The fabricated low-quality/high-RNA labels are software controls and never selection truth.",
      "Empty droplets are absent by construction; neither capture nor sample is inferred from donor."))
}

mad_example_options <- function(prefilter = list(method = "none")) {
  list(grouping = list(method = "column", declared_role = "qc_group",
    column = "qc_pool", source = "Explicit fixture construction: each capture contains 120 cells from each declared metric-comparison pool, independently of sample/donor labels"),
    prefilter = prefilter)
}

mad_example_doublet_options <- function() {
  list(data_type = "scrna_droplet", technology = "declared_droplet_other",
    input_source = "Synthetic MAD fixture v1: constructed called cells without empty droplets; no observed experiment claimed",
    empty_droplets_removed = TRUE, full_called_cohort = FALSE,
    capture = list(method = "column", column = "capture_id",
      source = "Explicit fixture construction: each 240-cell block is one independent artificial loading unit"),
    rate = list(method = "manual", value = .08, sd = .02,
      source = "Explicit software expected-rate setting, not measured prevalence or fabricated-pattern fraction"),
    column_prefix = "sc_doublet", seed = 999L, nfeatures = 200L,
    dims = 10L, artificial_doublets = 1500L, iter = 3L, clusters = FALSE)
}

mad_example_start <- function(input, project_dir, context, qc_mad,
                              doublet_diagnostics = mad_example_doublet_options()) {
  if (missing(qc_mad)) stop("Supply an explicit declared QC grouping.", call. = FALSE)
  strategy_example_start(input, project_dir, context,
    qc_mad = qc_mad, doublet_diagnostics = doublet_diagnostics,
    annotation_column = "mad_reviewed_identity")
}

mad_example_panel <- function(snapshot) {
  panel <- if (!is.null(snapshot$strategy_review))
    snapshot$strategy_review$details$mad_panel else snapshot$evidence$qc_mad
  if (is.null(panel) || !is.character(panel$panel_hash) || length(panel$panel_hash) != 1L ||
      is.na(panel$panel_hash) || !grepl("^[0-9a-f]{64}$", panel$panel_hash))
    stop("Inspect this MAD project's current saved panel before proposing a policy.", call. = FALSE)
  panel
}

mad_example_inspect <- function(project_dir, save_snapshot = FALSE) {
  current <- strategy_example_inspect(project_dir)
  if (!is.null(current$evidence$qc_mad)) {
    cat("Saved deterministic QC candidate panel, before quality filtering:\n")
    print(current$evidence$qc_mad)
  }
  if (isTRUE(save_snapshot)) {
    path <- file.path(project_dir, "mad-example-displayed-snapshot.rds")
    temporary <- tempfile(".mad-example-snapshot-", tmpdir = project_dir)
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(current, temporary)
    if (!file.rename(temporary, path)) stop("Could not save the displayed convenience snapshot.")
  }
  invisible(current)
}

mad_example_propose <- function(project_dir, snapshot, preset_id, reviewer, reason) {
  choices <- c("keep_all", "conservative_and3", "low_counts3", "low_features3", "high_mt3", "any_quality3")
  if (!is.character(preset_id) || length(preset_id) != 1L || is.na(preset_id) ||
      !preset_id %in% choices)
    stop("Choose one supported preset ID; unavailable measured candidates are rejected by the coordinator.", call. = FALSE)
  panel <- mad_example_panel(snapshot)
  proposal <- if (!is.null(snapshot$strategy_review))
    snapshot$strategy_review$details$canonical_proposal else
      list(schema = "scagentkit.strategy.v1",
        rationale = "Explicit synthetic software comparison with one joint quality/analysis approval and unresolved biological identities.",
        risks = list("Relative metric outliers are not observed cell-quality truth.",
          "Metric modes and extreme RNA/mitochondrial values may reflect biology in real inputs.",
          "The expected doublet rate, PCs, HVGs and resolution are explicit fixture settings, not tuned biological recommendations."),
        inferences = list("Synthetic controls only: no observed donor, cell type or doublet identities are inferred."),
        analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
          nfeatures = 200L, npcs = 8L, seed = 999L),
        pcs = list(method = "fixed", ndim = 6L),
        batch = list(method = "none", reason = "Synthetic labels do not establish a technical batch effect; no integration is proposed."),
        clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .4, .6)),
        umap = list(run = TRUE, n_neighbors = 15L))
  proposal$qc <- list(schema = "scagentkit.qc.mad.v1", rationale = reason,
    risks = list("A relative group threshold may flag valid biology or miss a poor-quality majority.",
      "Unknown or degenerate required metrics make removal candidates unavailable.",
      "High-RNA, ribosomal and hemoglobin measurements are diagnostic only."),
    preset_id = preset_id, panel_hash = panel$panel_hash)
  if (!is.null(snapshot$evidence$doublet_diagnostics) ||
      !is.null(snapshot$strategy_review$details$doublet_diagnostics))
    if (is.null(proposal$doublet)) proposal$doublet <- list(method = "keep",
      reason = "Retain predicted doublets in this quality-policy comparison; predictions are not biological truth.")
  # The initial configuration boundary has no decision node. The exact inspected
  # project/input/revision guards still apply to this complete proposal.
  strategy_example_revise(project_dir, snapshot, proposal, reviewer, reason)
}

mad_example_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("demo", "inspect", "propose-keep-all", "propose-conservative-and3",
    "propose-any-quality3", "approve", "reject", "continue", "propose-unknown", "output")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: mad-review.R PROJECT_DIR demo|inspect|propose-keep-all|propose-conservative-and3|propose-any-quality3|approve|reject|continue|propose-unknown|output")
  project_dir <- args[[1L]]; mode <- args[[2L]]; reviewer <- "synthetic-MAD-example-analyst"
  if (mode == "demo") {
    input <- mad_example_input()
    before <- digest::digest(input, algo = "sha256")
    mad_example_start(input, project_dir, mad_example_context(), mad_example_options())
    stopifnot(identical(before, digest::digest(input, algo = "sha256")))
  } else if (mode == "inspect") return(mad_example_inspect(project_dir, save_snapshot = TRUE))
  else if (mode == "output") {
    current <- sc_run_inspect(project_dir)
    if (!identical(current$status, "complete"))
      stop("Approve annotation and Continue before reading the final object.")
    final <- readRDS(current$output$seurat)
    cat("Final object:", current$output$seurat, "\n")
    print(table(final$mad_reviewed_identity, useNA = "ifany"))
    return(invisible(final))
  } else {
    path <- file.path(project_dir, "mad-example-displayed-snapshot.rds")
    if (!file.exists(path)) stop("Run inspect and read its displayed panel before this operation.")
    snapshot <- readRDS(path)
    if (mode == "continue") strategy_example_continue(project_dir, snapshot)
    else if (mode == "propose-unknown") strategy_example_unknown(project_dir, snapshot, reviewer)
    else if (startsWith(mode, "propose-")) {
      preset_id <- switch(mode, "propose-keep-all" = "keep_all",
        "propose-conservative-and3" = "conservative_and3", "propose-any-quality3" = "any_quality3")
      mad_example_propose(project_dir, snapshot, preset_id, reviewer,
        paste("Explicit synthetic comparison:", preset_id,
          "; inspect every group's measured impact and approve the whole strategy before execution."))
    } else strategy_example_decide(project_dir, snapshot, mode, reviewer,
      reason = if (mode == "approve")
        "Approve this exact whole synthetic snapshot and displayed scope, with biological identity unresolved."
      else "Reject this exact whole snapshot without executing its cell selection.")
  }
  invisible(mad_example_inspect(project_dir))
}

if (sys.nframe() == 0L) mad_example_main()
