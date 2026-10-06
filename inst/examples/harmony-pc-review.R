#!/usr/bin/env Rscript
# Source after installing this checkout in your selected private R library.
# CLI: Rscript --vanilla harmony-pc-review.R PROJECT_DIR MODE
# Modes: demo, inspect, approve, reject, continue, revise-harmony-85,
#        revise-none-80, revise-top50-85, propose-unknown, finish-unknown, output.
# Initial explicit strategy: retain all fixture cells, no batch correction,
# and .80 of the first min(50, actually computed PCs) variance window.
# Review the actual saved PC candidates before optional explicit Harmony.
# Synthetic controls do not establish real batch effects or preservation.
# No model request, key read, download or dependency installation is performed.

suppressPackageStartupMessages(library(scAgentKit))
if (!all(c("sc_run", "sc_run_strategy_revise", "sc_run_review", "sc_run_continue") %in%
         getNamespaceExports("scAgentKit")))
  stop("Install this checkout's Harmony/PC package in the selected R library first.", call. = FALSE)
harmony_pc_helpers <- system.file("examples", "analysis-strategy.R", package = "scAgentKit")
if (!nzchar(harmony_pc_helpers))
  stop("The installed package must include examples/analysis-strategy.R.", call. = FALSE)
source(harmony_pc_helpers)
rm(harmony_pc_helpers)

harmony_pc_example_input <- function() {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit(if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv) else
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
  set.seed(999L)
  n_genes <- 500L; n_cells <- 240L
  values <- matrix(stats::rpois(n_genes * n_cells, lambda = 2), nrow = n_genes)
  # Independent fabricated programs reduce reliance on a single dominant PC.
  # Their labels are never used to tune or select the PC/batch policy.
  program <- rep(seq_len(6L), length.out = n_cells)
  for (i in seq_len(6L)) {
    genes <- seq.int((i - 1L) * 10L + 1L, i * 10L)
    selected <- which(program == i)
    values[genes, selected] <- values[genes, selected, drop = FALSE] + 5L
  }
  batch <- rep(c("fixture-technical-A", "fixture-technical-B"), each = 120L)
  condition <- rep(rep(c("fixture-control", "fixture-perturbation"), each = 60L), 2L)
  values[81:100, batch == "fixture-technical-B"] <-
    values[81:100, batch == "fixture-technical-B", drop = FALSE] + 2L
  values[101:120, condition == "fixture-perturbation"] <-
    values[101:120, condition == "fixture-perturbation", drop = FALSE] + 2L
  dimnames(values) <- list(paste0("HarmonyFixtureGene", sprintf("%04d", seq_len(n_genes))),
    paste0("harmony-fixture-cell-", sprintf("%03d", seq_len(n_cells))))
  input <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(values, sparse = TRUE),
    min.cells = 0, min.features = 0)
  input$technical_batch <- batch
  input$condition <- condition
  # Sample is nested within condition, while the chosen technical factor crosses
  # condition. Correcting sample requires a different applicability check and
  # is not authorized by this example.
  input$sample_id <- rep(paste0("fixture-sample-", seq_len(4L)), each = 60L)
  input$donor_id <- rep(rep(c("fixture-donor-u", "fixture-donor-v"), each = 30L), 4L)
  input$capture_id <- rep(rep(c("fixture-loading-1", "fixture-loading-2"), each = 60L), 2L)
  input$fixture_program <- paste0("fabricated-program-", program)
  input$prior_annotation <- factor(rep("fixture-unresolved", ncol(input)),
    levels = c("fixture-unresolved", "prior-unused-level"))
  input
}

harmony_pc_example_context <- function() {
  list(species = "human", tissue = "synthetic crossed technical/condition factors",
    columns = list(sample = "sample_id", donor = "donor_id", capture = "capture_id",
      batch = "technical_batch", condition = "condition"),
    design = list(type = "Two-level constructed technical factor crossing two condition labels",
      technical_batch = TRUE,
      notes = "A fabricated gene-count offset represents a technical software control. Both technical levels contain both conditions; biological sample IDs are separately nested within condition. No observed experiment or preserved biology is claimed."),
    research_goal = "Inspect computed PC policies and explicit guarded embedding correction with exact source preservation and recoverable review.",
    notes = paste("Synthetic raw counts only; no mitochondrial gene convention is present.",
      "Human is a method-scope declaration, not observed human data.",
      "Program/condition/technical labels are software controls, not inference truth or an integration-performance benchmark."))
}

harmony_pc_example_proposal <- function(threshold = 0.80) {
  if (!is.numeric(threshold) || length(threshold) != 1L || !is.finite(threshold) ||
      !threshold %in% c(0.80, 0.85))
    stop("This example supports exactly .80 or .85 top-50 policy thresholds.", call. = FALSE)
  list(schema = "scagentkit.strategy.v1",
    rationale = "Explicit synthetic comparison: retain source cells and inspect an approved computed-PC policy before considering guarded Harmony.",
    risks = list("Synthetic factor/program labels do not establish biological correctness.",
      "A PC-window fraction is not full-expression variance or an optimal dimension.",
      "Correction can absorb biological signal despite omitting condition as a covariate."),
    inferences = list("Constructed software factors only; no observed sample, donor or cell identity is inferred."),
    qc = list(schema = "scagentkit.qc.v1",
      rationale = "Inclusive no-deletion fixture range isolates the PC/correction comparison from a quality filtering policy.",
      risks = list("This range is fixture syntax, not a recommendation for biological data."),
      filters = list(list(op = "range", metric = "nFeature", min = 0, max = 500))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 200L, npcs = 50L, seed = 999L),
    pcs = list(method = "computed_top50", threshold = unname(as.numeric(threshold))),
    batch = list(method = "none", reason = "Begin with the original PCA basis; constructed crossed factors do not automatically authorize correction."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .4, .6)),
    umap = list(run = TRUE, n_neighbors = 15L))
}

harmony_pc_example_start <- function(input, project_dir, context, proposal) {
  if (missing(proposal)) stop("Supply a complete explicit typed strategy appropriate to this input.")
  strategy_example_start(input, project_dir, context, strategy_proposal = proposal,
    annotation_column = "harmony_reviewed_identity")
}

harmony_pc_example_inspect <- function(project_dir, save_snapshot = FALSE) {
  current <- strategy_example_inspect(project_dir)
  if (!is.null(current$strategy_review$details$pc_diagnostics)) {
    cat("Computed-PC policy and actual saved candidates (pending before PCA):\n")
    print(current$strategy_review$details$pc_diagnostics)
  }
  if (!is.null(current$computed_diagnostics)) {
    cat("Actual post-approval cached PCA and optional Harmony diagnostics:\n")
    print(current$computed_diagnostics)
  }
  if (isTRUE(save_snapshot)) {
    path <- file.path(project_dir, "harmony-pc-example-displayed-snapshot.rds")
    temporary <- tempfile(".harmony-pc-example-snapshot-", tmpdir = project_dir)
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(current, temporary)
    if (!file.rename(temporary, path)) stop("Could not save the displayed convenience snapshot.")
  }
  invisible(current)
}

harmony_pc_example_approve <- function(project_dir, snapshot, reviewer, reason) {
  strategy_example_decide(project_dir, snapshot, "approve", reviewer, reason)
}

harmony_pc_example_continue <- function(project_dir, snapshot, retry = FALSE) {
  strategy_example_continue(project_dir, snapshot, retry = retry)
}

harmony_pc_example_revise <- function(project_dir, snapshot, method, threshold,
                                       reviewer, reason) {
  if (!is.character(method) || length(method) != 1L || is.na(method) ||
      !method %in% c("none", "harmony"))
    stop("Choose an explicit none or harmony batch policy.", call. = FALSE)
  if (!is.numeric(threshold) || length(threshold) != 1L || !is.finite(threshold) ||
      !threshold %in% c(0.80, 0.85))
    stop("Choose exactly .80 or .85 for this computed top-50 comparison.", call. = FALSE)
  proposal <- snapshot$strategy_review$details$canonical_proposal
  if (is.null(proposal$analysis) || is.null(proposal$pcs))
    stop("Inspect a raw-entry strategy; processed reuse does not authorize these revisions.", call. = FALSE)
  proposal$pcs <- list(method = "computed_top50", threshold = unname(as.numeric(threshold)))
  proposal$batch <- if (method == "none") list(method = "none", reason = reason) else
    list(method = "harmony", group_by_vars = "technical_batch", theta = 2,
      lambda = 1, sigma = 0.1, max_iter = 10L, nclust = 10L, reason = reason)
  # Revalidation uses the exact selected design and supported installed package.
  # QC/preprocessing/PCA stay cached; changed downstream results require a
  # fresh whole approval and explicit Continue.
  strategy_example_revise(project_dir, snapshot, proposal, reviewer, reason)
}

harmony_pc_example_finish_unknown <- function(project_dir, snapshot, reviewer, reason) {
  annotations <- snapshot$annotation_review$details$canonical_proposal$annotations
  if (is.null(annotations) || !length(annotations) ||
      !all(vapply(annotations, function(row) identical(row$label, "Unknown") &&
        identical(row$confidence, "low"), logical(1))))
    stop("First propose manual Unknown/low labels, then inspect that exact annotation review.", call. = FALSE)
  # Calling this explicit operation approves only the displayed unresolved
  # annotation; it neither invents labels nor approves a strategy.
  strategy_example_decide(project_dir, snapshot, "approve", reviewer, reason)
  approved <- harmony_pc_example_inspect(project_dir)
  harmony_pc_example_continue(project_dir, approved)
}

harmony_pc_example_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("demo", "inspect", "approve", "reject", "continue", "revise-harmony-85",
    "revise-none-80", "revise-top50-85", "propose-unknown", "finish-unknown", "output")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: harmony-pc-review.R PROJECT_DIR demo|inspect|approve|reject|continue|revise-harmony-85|revise-none-80|revise-top50-85|propose-unknown|finish-unknown|output")
  project_dir <- args[[1L]]; mode <- args[[2L]]; reviewer <- "synthetic-Harmony-PC-example-analyst"
  if (mode == "demo") {
    input <- harmony_pc_example_input()
    before <- digest::digest(input, algo = "sha256")
    harmony_pc_example_start(input, project_dir, harmony_pc_example_context(),
      harmony_pc_example_proposal())
    stopifnot(identical(before, digest::digest(input, algo = "sha256")))
  } else if (mode == "inspect") return(harmony_pc_example_inspect(project_dir, save_snapshot = TRUE))
  else if (mode == "output") {
    current <- sc_run_inspect(project_dir)
    if (!identical(current$status, "complete"))
      stop("Approve annotation and Continue before reading the final object.")
    cat("Final object:", current$output$seurat, "\n")
    return(invisible(readRDS(current$output$seurat)))
  } else {
    path <- file.path(project_dir, "harmony-pc-example-displayed-snapshot.rds")
    if (!file.exists(path)) stop("Run inspect and read the displayed evidence before this operation.")
    snapshot <- readRDS(path)
    if (mode == "continue") harmony_pc_example_continue(project_dir, snapshot)
    else if (mode == "propose-unknown") strategy_example_unknown(project_dir, snapshot, reviewer)
    else if (mode == "finish-unknown") harmony_pc_example_finish_unknown(project_dir, snapshot, reviewer,
      "Approve these exact displayed Unknown/low synthetic identities and complete the saved run.")
    else if (startsWith(mode, "revise-")) {
      method <- if (mode == "revise-harmony-85") "harmony" else
        if (mode == "revise-none-80") "none" else
          snapshot$strategy_review$details$canonical_proposal$batch$method
      threshold <- if (mode == "revise-none-80") .80 else .85
      harmony_pc_example_revise(project_dir, snapshot, method, threshold, reviewer,
        paste("Explicit synthetic comparison:", mode,
          "; inspect measured PC/design evidence and approve the fresh whole strategy before execution."))
    } else if (mode == "approve") harmony_pc_example_approve(project_dir, snapshot, reviewer,
      "Approve this exact whole synthetic snapshot and stated unresolved scientific risks.")
    else strategy_example_decide(project_dir, snapshot, "reject", reviewer,
      "Reject this exact proposal without executing its embedding or cell-selection choices.")
  }
  invisible(harmony_pc_example_inspect(project_dir))
}

if (sys.nframe() == 0L) harmony_pc_example_main()
