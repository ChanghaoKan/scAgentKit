#!/usr/bin/env Rscript
# Source after installing this checkout into the selected R library.
# CLI: Rscript --vanilla cell-cycle-review.R PROJECT_DIR MODE
# Modes: demo, inspect, approve, reject, continue, revise-none, revise-full,
#        revise-difference, propose-unknown, output.
# Synthetic software fixture only. No provider, key, download, dependency
# installation or model request is used. Review and Continue remain separate.
# Ordinary choices: none keeps signal; full regresses S.Score and G2M.Score.
# revise-difference is advanced and optional, using the same whole-strategy
# review. A cycle/proliferation research goal suggests considering retained
# signal; it never forces a method or establishes an automatically best choice.

suppressPackageStartupMessages(library(scAgentKit))
if (!all(c("sc_cycle_gene_set", "sc_run_strategy_revise", "sc_run_review",
           "sc_run_continue") %in% getNamespaceExports("scAgentKit")))
  stop("Install this checkout's cell-cycle package in the selected R library first.", call. = FALSE)
cycle_strategy_helpers <- system.file("examples", "analysis-strategy.R", package = "scAgentKit")
if (!nzchar(cycle_strategy_helpers))
  stop("The installed package must include examples/analysis-strategy.R.", call. = FALSE)
source(cycle_strategy_helpers)
rm(cycle_strategy_helpers)

cycle_example_gene_set <- function() {
  # Recognizable human symbols label planted programs. Their simulated counts
  # are not observed human biology and cannot validate marker specificity.
  sc_cycle_gene_set("human",
    s_genes = c("MCM5", "PCNA", "TYMS", "FEN1", "MCM2", "MCM4",
      "RRM1", "UNG", "GINS2", "MCM6", "CDCA7", "DTL"),
    g2m_genes = c("HMGB2", "CDK1", "NUSAP1", "UBE2C", "BIRC5", "TPX2",
      "TOP2A", "NDC80", "CKS2", "NUF2", "CKS1B", "MKI67"),
    source = "scAgentKit offline synthetic planted-program software fixture",
    version = "cell-cycle-fixture-v1")
}

cycle_example_input <- function() {
  set.seed(17L)
  genes <- cycle_example_gene_set()
  n_cells <- 180L
  background <- paste0("FixtureBackground", sprintf("%04d", seq_len(936L)))
  # Broad background means provide many controls in each expression bin.
  # Every requested bin/control parameter is passed unchanged to scoring.
  background_means <- seq(.2, 6, length.out = length(background))
  means <- c(rep(.35, length(genes$s_genes) + length(genes$g2m_genes)), background_means)
  values <- matrix(stats::rpois(length(means) * n_cells,
    lambda = rep(means, times = n_cells)), nrow = length(means))
  dimnames(values) <- list(c(genes$s_genes, genes$g2m_genes, background),
    paste0("fixture-cell-", sprintf("%03d", seq_len(n_cells))))
  program <- rep(c("planted-S", "planted-G2M", "planted-low-cycle"), each = 60L)
  for (row in genes$s_genes)
    values[row, program == "planted-S"] <- values[row, program == "planted-S"] +
      stats::rpois(sum(program == "planted-S"), lambda = 6)
  for (row in genes$g2m_genes)
    values[row, program == "planted-G2M"] <- values[row, program == "planted-G2M"] +
      stats::rpois(sum(program == "planted-G2M"), lambda = 6)
  # Independent artificial expression programs cross all three cycle groups.
  # These controls make it possible to inspect retained non-cycle variation.
  identity <- rep(rep(c("program-A", "program-B"), each = 30L), 3L)
  values[background[321:340], identity == "program-A"] <-
    values[background[321:340], identity == "program-A"] + 8L
  values[background[341:360], identity == "program-B"] <-
    values[background[341:360], identity == "program-B"] + 8L
  input <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(values, sparse = TRUE),
    min.cells = 0, min.features = 0)
  input$sample_id <- rep(rep(c("fixture-sample-A", "fixture-sample-B"), each = 30L), 3L)
  input$capture_id <- input$sample_id
  input$fixture_cycle_program <- program
  input$fixture_identity_program <- identity
  input
}

cycle_example_context <- function() {
  list(species = "human", tissue = "synthetic planted expression programs",
    columns = list(sample = "sample_id", capture = "capture_id"),
    design = list(type = "synthetic crossed cycle and expression programs",
      technical_batch = FALSE,
      notes = "Planted labels are software controls, not measured phases, cell types or technical batches."),
    research_goal = "Exercise fixed full-input diagnostics, explicit cycle regression and checkpoint reuse.",
    notes = "Synthetic counts only. This fixture does not validate a human biological analysis or a universal QC rule.")
}

cycle_example_proposal <- function() {
  list(schema = "scagentkit.strategy.v1",
    rationale = "Retain all synthetic cells and inspect the planted cycle signal before choosing any regression.",
    risks = list("No biological adequacy is established by simulated program recovery.",
      "Full regression can remove research-relevant proliferation variation.",
      "Fixed PCs, HVGs and resolution are software demonstration settings."),
    inferences = list("Synthetic planted programs are controls, not inferred cell types or phases."),
    qc = list(schema = "scagentkit.qc.v1",
      rationale = "No-filter synthetic QC isolates scoring and regression from cell selection.",
      risks = list("The inclusive feature range is a fixture policy, not a recommendation for real data."),
      filters = list(list(op = "range", metric = "nFeature", min = 0, max = 960))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 200L, npcs = 8L, seed = 17L),
    pcs = list(method = "fixed", ndim = 6L),
    batch = list(method = "none", reason = "No technical batch effect is asserted by this synthetic fixture."),
    cycle = list(method = "none", reason = "Inspect the full-input cycle reference while retaining the planted signal."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .4, .6)),
    umap = list(run = TRUE, n_neighbors = 15L))
}

cycle_example_start <- function(input, project_dir, context, gene_set, proposal,
                                column_prefix = "sc_cycle") {
  if (missing(proposal))
    stop("Supply a complete typed strategy appropriate to your input.", call. = FALSE)
  strategy_example_start(input, project_dir, context, strategy_proposal = proposal,
    cycle_diagnostics = list(gene_set = gene_set, column_prefix = column_prefix,
      seed = 17L, scale_factor = 10000, nbin = 12L, ctrl = 5L,
      min_genes = 5L, min_fraction = .2),
    annotation_column = "cycle_reviewed_identity")
}

cycle_example_inspect <- function(project_dir, save_snapshot = FALSE) {
  current <- strategy_example_inspect(project_dir)
  if (isTRUE(save_snapshot)) {
    path <- file.path(project_dir, "cell-cycle-example-displayed-snapshot.rds")
    temporary <- tempfile(".cell-cycle-example-snapshot-", tmpdir = project_dir)
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(current, temporary)
    if (!file.rename(temporary, path)) stop("Could not save the displayed convenience snapshot.")
  }
  invisible(current)
}

cycle_example_revise <- function(project_dir, snapshot, method, reviewer, reason) {
  if (length(method) != 1L || !method %in% c("none", "full", "difference"))
    stop("Choose exactly none, full or difference.", call. = FALSE)
  proposal <- snapshot$strategy_review$details$canonical_proposal
  if (is.null(proposal$cycle))
    stop("This project has no enabled cell-cycle strategy choice.", call. = FALSE)
  proposal$cycle <- list(method = method, reason = reason)
  strategy_example_revise(project_dir, snapshot, proposal, reviewer, reason)
}

cycle_example_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("demo", "inspect", "approve", "reject", "continue", "revise-none",
    "revise-full", "revise-difference", "propose-unknown", "output")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: cell-cycle-review.R PROJECT_DIR demo|inspect|approve|reject|continue|revise-none|revise-full|revise-difference|propose-unknown|output")
  project_dir <- args[[1L]]; mode <- args[[2L]]; reviewer <- "synthetic-cycle-example-analyst"
  if (mode == "demo") {
    input <- cycle_example_input()
    before <- digest::digest(input, algo = "sha256")
    cycle_example_start(input, project_dir, cycle_example_context(),
      cycle_example_gene_set(), cycle_example_proposal())
    stopifnot(identical(before, digest::digest(input, algo = "sha256")))
  } else if (mode == "inspect") return(cycle_example_inspect(project_dir, save_snapshot = TRUE))
  else if (mode == "output") {
    current <- sc_run_inspect(project_dir)
    if (!identical(current$status, "complete"))
      stop("Approve annotation and Continue before reading the final object.")
    final <- readRDS(current$output$seurat)
    cat("Final object:", current$output$seurat, "\n")
    print(table(final$cycle_reviewed_identity, useNA = "ifany"))
    return(invisible(final))
  } else {
    path <- file.path(project_dir, "cell-cycle-example-displayed-snapshot.rds")
    if (!file.exists(path)) stop("Run inspect and read its displayed evidence before this operation.")
    snapshot <- readRDS(path)
    if (mode == "continue") strategy_example_continue(project_dir, snapshot)
    else if (mode == "propose-unknown") strategy_example_unknown(project_dir, snapshot, reviewer)
    else if (startsWith(mode, "revise-")) {
      method <- sub("^revise-", "", mode)
      reason <- switch(method,
        none = "Retain cycle-related variation in this software fixture; inspect and approve the fresh whole strategy.",
        full = "Demonstrate standard regression of both fixed S and G2M scores; accept possible loss of planted proliferation variation for this software test.",
        difference = "Advanced optional comparison: regress S minus G2M to reduce planted phase contrast while retaining cycling-versus-low-cycle variation; use the same whole-strategy review.")
      cycle_example_revise(project_dir, snapshot, method, reviewer, reason)
    } else strategy_example_decide(project_dir, snapshot, mode, reviewer,
      reason = if (mode == "approve") "Approve this exact displayed synthetic software-test proposal; biological identities remain unresolved."
        else "Reject this exact displayed proposal; do not execute it.")
  }
  invisible(cycle_example_inspect(project_dir))
}

if (sys.nframe() == 0L) cycle_example_main()
