#!/usr/bin/env Rscript
# Source after installing this checkout into the selected private R library.
# CLI: Rscript --vanilla doublet-review.R PROJECT_DIR MODE
# Modes: demo, inspect, approve, reject, continue, revise-keep,
#        revise-remove-predicted, propose-unknown, output.
# This runs the real supported scDblFinder algorithm on synthetic controls.
# It is not a mock provider, a measured human experiment, or accuracy proof.
# No key, download, dependency installation, or model request is used.
# Scoring retains every source cell. Only an exact approved whole strategy
# can remove predicted doublets from the already approved QC cell scope.

suppressPackageStartupMessages(library(scAgentKit))
if (!all(c("sc_run", "sc_run_strategy_revise", "sc_run_review",
           "sc_run_continue") %in% getNamespaceExports("scAgentKit")) ||
    !"doublet_diagnostics" %in% names(formals(sc_run)))
  stop("Install this checkout's doublet package in the selected R library first.", call. = FALSE)
doublet_strategy_helpers <- system.file("examples", "analysis-strategy.R", package = "scAgentKit")
if (!nzchar(doublet_strategy_helpers))
  stop("The installed package must include examples/analysis-strategy.R.", call. = FALSE)
source(doublet_strategy_helpers)
rm(doublet_strategy_helpers)

doublet_example_input <- function() {
  set.seed(999L)
  genes <- paste0("DoubletFixtureGene", sprintf("%04d", seq_len(600L)))
  build_capture <- function(index) {
    # 200 independent singlet-controls with two artificial expression programs.
    # The shared floor guarantees >=200 raw counts without hidden filtering.
    values <- matrix(stats::rpois(length(genes) * 200L, lambda = .65),
      nrow = length(genes))
    values[seq_len(20L), ] <- values[seq_len(20L), ] + 10L
    values[41:70, 1:100] <- values[41:70, 1:100] +
      matrix(stats::rpois(30L * 100L, lambda = 8), nrow = 30L)
    values[71:100, 101:200] <- values[71:100, 101:200] +
      matrix(stats::rpois(30L * 100L, lambda = 8), nrow = 30L)
    # 20 exact count sums across programs, confined to this loading unit.
    # Planted labels are software controls, never real doublet ground truth.
    first <- sample.int(100L, 20L, replace = FALSE)
    second <- 100L + sample.int(100L, 20L, replace = FALSE)
    combined <- cbind(values, values[, first, drop = FALSE] + values[, second, drop = FALSE])
    dimnames(combined) <- list(genes,
      paste0("doublet-fixture-c", index, "-cell-", sprintf("%03d", seq_len(220L))))
    combined
  }
  values <- cbind(build_capture(1L), build_capture(2L))
  input <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(values, sparse = TRUE),
    min.cells = 0, min.features = 0)
  input$capture_id <- rep(c("fixture-capture-1", "fixture-capture-2"), each = 220L)
  # Biological-role labels cross both captures and are not used to split scores.
  input$sample_id <- rep(c(rep(c("fixture-sample-A", "fixture-sample-B"), 100L),
    rep("fixture-mixed-control", 20L)), 2L)
  input$donor_id <- rep(c(rep(c("fixture-donor-alpha", "fixture-donor-beta"), each = 50L),
    rep(c("fixture-donor-alpha", "fixture-donor-beta"), each = 50L),
    rep("fixture-mixed-control", 20L)), 2L)
  input$fixture_expression_program <- rep(c(rep("program-A", 100L),
    rep("program-B", 100L), rep("summed-A-plus-B", 20L)), 2L)
  input$fixture_planted_control <- rep(c(rep("singlet-control", 200L),
    rep("summed-count-control", 20L)), 2L)
  # Previous values deliberately use the legacy names and must be preserved.
  input$doublet_score <- rep(.17, ncol(input))
  input$doublet_class <- factor(rep("legacy-unreviewed", ncol(input)),
    levels = c("legacy-unreviewed", "legacy-unused-level"))
  input$prior_annotation <- factor(rep("fixture-unresolved", ncol(input)),
    levels = c("fixture-unresolved", "prior-unused-level"))
  input
}

doublet_example_context <- function() {
  list(species = "human", tissue = "synthetic independent expression programs",
    columns = list(sample = "sample_id", capture = "capture_id", donor = "donor_id"),
    design = list(type = "synthetic programs crossed with two declared loading units",
      technical_batch = FALSE,
      notes = "Sample and donor labels cross captures; none establish a technical batch or observed biology."),
    research_goal = "Inspect artificial expression programs and predicted doublet evidence while preserving the input and reviewing any cell removal.",
    notes = paste("Synthetic counts only; human is a scope declaration, not an observed human dataset.",
      "Planted sums and singlet labels are software controls, not real doublet or cell-type truth.",
      "There are no empty droplets in this constructed called-cell fixture."))
}

doublet_example_options <- function() {
  list(data_type = "scrna_droplet", technology = "declared_droplet_other",
    input_source = "scAgentKit synthetic count-sum fixture v1: constructed called cells, no empty-droplet columns; no real experiment claimed",
    empty_droplets_removed = TRUE,
    capture = list(method = "column", column = "capture_id",
      source = "Explicit fixture construction: each 220-cell block is one separate artificial loading unit; sample/donor labels are not captures"),
    rate = list(method = "manual", value = .08, sd = .02,
      source = "Explicit software-control expected-rate parameter; .08 is not an estimated or true biological rate, nor the realized planted-sum fraction"),
    column_prefix = "sc_doublet", seed = 999L, nfeatures = 200L,
    dims = 10L, artificial_doublets = 1500L, iter = 3L, clusters = FALSE)
}

doublet_example_proposal <- function() {
  list(schema = "scagentkit.strategy.v1",
    rationale = "Retain all synthetic controls initially and inspect the fixed full-input predicted doublet evidence before considering removal.",
    risks = list("Predicted classes and planted sums do not validate biological accuracy.",
      "Homotypic doublets can be missed and rare expression programs can receive high scores.",
      "Expected rate, PCs, HVGs and resolution here are explicit software settings."),
    inferences = list("Artificial programs and count sums are software controls, not inferred cell types, donors or biological doublets."),
    qc = list(schema = "scagentkit.qc.v1",
      rationale = "No-filter inclusive synthetic QC isolates doublet review from an additional QC selection policy.",
      risks = list("The fixture feature bounds are not a recommendation for private or public biological data."),
      filters = list(list(op = "range", metric = "nFeature", min = 0, max = 600))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 200L, npcs = 8L, seed = 999L),
    pcs = list(method = "fixed", ndim = 6L),
    batch = list(method = "none", reason = "No observed technical batch effect is asserted by the artificial loading-unit labels."),
    doublet = list(method = "keep", reason = "Scores are predictions; retain every QC-retained control while inspecting the saved diagnostics."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .4, .6)),
    umap = list(run = TRUE, n_neighbors = 15L))
}

doublet_example_start <- function(input, project_dir, context, doublet_diagnostics, proposal) {
  if (missing(doublet_diagnostics) || missing(proposal))
    stop("Supply explicit capture/rate diagnostics and a complete typed strategy appropriate to the input.", call. = FALSE)
  strategy_example_start(input, project_dir, context, strategy_proposal = proposal,
    doublet_diagnostics = doublet_diagnostics, annotation_column = "doublet_reviewed_identity")
}

doublet_example_inspect <- function(project_dir, save_snapshot = FALSE) {
  current <- strategy_example_inspect(project_dir)
  if (isTRUE(save_snapshot)) {
    path <- file.path(project_dir, "doublet-example-displayed-snapshot.rds")
    temporary <- tempfile(".doublet-example-snapshot-", tmpdir = project_dir)
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(current, temporary)
    if (!file.rename(temporary, path)) stop("Could not save the displayed convenience snapshot.")
  }
  invisible(current)
}

doublet_example_revise <- function(project_dir, snapshot, method, reviewer, reason) {
  if (length(method) != 1L || !method %in% c("keep", "remove_predicted"))
    stop("Choose exactly keep or remove_predicted.", call. = FALSE)
  proposal <- snapshot$strategy_review$details$canonical_proposal
  if (is.null(proposal$doublet))
    stop("This project has no enabled doublet strategy choice.", call. = FALSE)
  proposal$doublet <- list(method = method, reason = reason)
  strategy_example_revise(project_dir, snapshot, proposal, reviewer, reason)
}

doublet_example_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("demo", "inspect", "approve", "reject", "continue", "revise-keep",
    "revise-remove-predicted", "propose-unknown", "output")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: doublet-review.R PROJECT_DIR demo|inspect|approve|reject|continue|revise-keep|revise-remove-predicted|propose-unknown|output")
  project_dir <- args[[1L]]; mode <- args[[2L]]; reviewer <- "synthetic-doublet-example-analyst"
  if (mode == "demo") {
    input <- doublet_example_input()
    before <- digest::digest(input, algo = "sha256")
    doublet_example_start(input, project_dir, doublet_example_context(),
      doublet_example_options(), doublet_example_proposal())
    stopifnot(identical(before, digest::digest(input, algo = "sha256")))
  } else if (mode == "inspect") return(doublet_example_inspect(project_dir, save_snapshot = TRUE))
  else if (mode == "output") {
    current <- sc_run_inspect(project_dir)
    if (!identical(current$status, "complete"))
      stop("Approve annotation and Continue before reading the final object.")
    final <- readRDS(current$output$seurat)
    cat("Final object:", current$output$seurat, "\n")
    print(table(final$sc_doublet_class, useNA = "ifany"))
    print(table(final$doublet_reviewed_identity, useNA = "ifany"))
    return(invisible(final))
  } else {
    path <- file.path(project_dir, "doublet-example-displayed-snapshot.rds")
    if (!file.exists(path)) stop("Run inspect and read its displayed evidence before this operation.")
    snapshot <- readRDS(path)
    if (mode == "continue") strategy_example_continue(project_dir, snapshot)
    else if (mode == "propose-unknown") strategy_example_unknown(project_dir, snapshot, reviewer)
    else if (startsWith(mode, "revise-")) {
      method <- if (mode == "revise-keep") "keep" else "remove_predicted"
      reason <- if (method == "keep")
        "Retain all QC-retained controls and reuse fixed full-input doublet evidence; inspect and approve the fresh whole strategy." else
        "Explicit synthetic software comparison: remove exactly the saved predicted-doublet IDs within approved QC; accept that predictions are not biological truth and inspect the whole impact before approval."
      doublet_example_revise(project_dir, snapshot, method, reviewer, reason)
    } else strategy_example_decide(project_dir, snapshot, mode, reviewer,
      reason = if (mode == "approve") "Approve this exact displayed synthetic software-test proposal and its cell impact; biological identities remain unresolved."
        else "Reject this exact displayed proposal; do not execute it.")
  }
  invisible(doublet_example_inspect(project_dir))
}

if (sys.nframe() == 0L) doublet_example_main()
