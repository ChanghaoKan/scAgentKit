#!/usr/bin/env Rscript
# Offline, non-PBMC synthetic demonstration. No key, network request, or API fee.
# Install this version of scAgentKit before running the script.
# Each command runs in a separate R process and returns when review is needed:
#   Rscript --vanilla server_first.R /durable/path/to/toy-project run
#   Rscript --vanilla server_first.R /durable/path/to/toy-project inspect
#   Rscript --vanilla server_first.R /durable/path/to/toy-project approve
#   Rscript --vanilla server_first.R /durable/path/to/toy-project resume
#   Rscript --vanilla server_first.R /durable/path/to/toy-project inspect
#   Rscript --vanilla server_first.R /durable/path/to/toy-project approve
#   Rscript --vanilla server_first.R /durable/path/to/toy-project resume
# The approve mode is only for this deliberately synthetic mechanism example.
# For a real study, inspect the current evidence and decide in R as in the guide.

suppressPackageStartupMessages(library(scAgentKit))

make_server_demo_input <- function() {
  set.seed(73031)
  modules <- list(
    epithelial = c("EPCAM", "KRT8", "KRT18", "KRT19", "KRT7", "MUC1", "TACSTD2", "CLDN3"),
    stromal = c("COL1A1", "COL1A2", "COL3A1", "DCN", "LUM", "COL6A1", "COL6A2", "PDGFRA"),
    endothelial = c("PECAM1", "VWF", "KDR", "EMCN", "ENG", "RAMP2", "ESAM", "CDH5"))
  genes <- c(unlist(modules, use.names = FALSE), "MT-CO1", sprintf("feature%04d", 1:575))
  cells <- sprintf("toy-cell-%03d", 1:180)
  toy_population <- rep(names(modules), each = 60)
  # This small toy construction uses a 600 x 180 temporary matrix; the input
  # supplied to Seurat and the coordinator is sparse integer raw counts.
  counts <- matrix(rpois(length(genes) * length(cells), 0.35), nrow = length(genes),
                   dimnames = list(genes, cells))
  for (population in names(modules)) {
    selected <- toy_population == population
    counts[modules[[population]], selected] <- matrix(
      1L + rpois(length(modules[[population]]) * sum(selected), 6),
      nrow = length(modules[[population]]))
  }
  counts["MT-CO1", ] <- rpois(length(cells), 1)
  toy <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE),
    project = "Server-first synthetic example", min.cells = 0, min.features = 0)
  toy$sample_id <- rep(rep(c("sample-A", "sample-B"), each = 30), 3)
  toy$capture_id <- rep(c("capture-A", "capture-B"), length.out = ncol(toy))
  toy$prep_batch <- rep(c("prep-A", "prep-B"), length.out = ncol(toy))
  toy$condition <- rep(c("vehicle", "treatment", "treatment", "vehicle"), length.out = ncol(toy))
  toy$original_annotation <- factor(rep(c("earlier-label", NA_character_), length.out = ncol(toy)))
  toy
}

server_demo_context <- function() list(
  species = "human", tissue = "synthetic epithelial, stromal and endothelial mixture",
  columns = list(sample = "sample_id", capture = "capture_id", batch = "prep_batch",
                 condition = "condition"),
  notes = paste("Entirely synthetic counts for testing saved review and recovery.",
    "The planted modules are not a biological benchmark. Samples and captures",
    "are literal toy labels, not donors. Condition is biological context;",
    "batch integration is intentionally skipped."))

server_demo_provider <- function() list(name = "mock", model = "offline-toy-v1", external = FALSE)

server_demo_chat <- function(system_prompt, user_prompt) {
  payload <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
  evidence <- payload$evidence
  if (identical(evidence$schema, "scagentkit.qc.evidence.v1")) {
    filters <- lapply(evidence$groups, function(group) list(op = "range",
      metric = "nFeature", min = max(1, floor(group$metrics$nFeature$p05)),
      group = group$selector))
    response <- list(schema = "scagentkit.qc.v1",
      rationale = paste("Offline mock only: illustrate a lower detected-feature",
        "bound derived from each supplied sample/capture group's observed p05.",
        "Review the predicted retention before applying it."),
      risks = list("A toy quantile rule is not a validated QC rule for real tissue.",
        "A low-depth population may be biologically real; thresholds need analyst review."),
      filters = unname(filters))
  } else if (identical(evidence$schema, "scagentkit.annotation-evidence.v1")) {
    response <- list(schema = "scagentkit.annotation.v1",
      annotations = lapply(evidence$clusters, function(cluster) list(
        clusterId = cluster$clusterId, label = "Unknown", confidence = "low",
        rationale = paste("Offline mock abstains from biological interpretation.",
          "The available toy marker evidence is retained for human review."),
        markers = lapply(utils::head(cluster$markers, 3), function(marker) marker$gene))))
  } else stop("Unexpected aggregate evidence schema in the offline demo.")
  list(content = as.character(jsonlite::toJSON(response, auto_unbox = TRUE,
    null = "null", na = "null", digits = NA)),
    usage = list(input_tokens = 0, output_tokens = 0, cached_tokens = 0),
    cost_usd = 0, model = "offline-toy-v1")
}

server_demo_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (length(args) < 1 || length(args) > 2)
    stop("Usage: server_first.R PROJECT_DIR [run|inspect|approve|reject|resume]", call. = FALSE)
  project_dir <- args[[1]]
  mode <- if (length(args) == 2) args[[2]] else "run"
  if (mode == "run") {
    toy <- make_server_demo_input()
    source_hash <- digest::digest(toy, algo = "sha256")
    result <- sc_run(toy, project_dir = project_dir, context = server_demo_context(),
      provider = server_demo_provider(), chat_fn = server_demo_chat, budget = 0,
      analysis = list(nfeatures = 200L, npcs = 12L, dims = 1:10,
        resolution = 0.3, seed = 73031L, umap_neighbors = 20L))
    stopifnot(identical(source_hash, digest::digest(toy, algo = "sha256")))
  } else if (mode == "inspect") {
    result <- sc_run_inspect(project_dir)
  } else if (mode %in% c("approve", "reject")) {
    current <- sc_run_inspect(project_dir)
    if (current$status != "awaiting_review" || is.null(current$pending$hash))
      stop("No current proposal awaits review; inspect the project first.", call. = FALSE)
    result <- if (mode == "approve") sc_run_approve(project_dir,
      proposal_hash = current$pending$hash, reviewer = "synthetic-demo-analyst",
      reason = "Reviewed this synthetic mechanism example; mock labels intentionally remain Unknown.")
      else sc_run_reject(project_dir, proposal_hash = current$pending$hash,
        reviewer = "synthetic-demo-analyst", reason = "Rejecting the toy proposal to demonstrate persistent review.")
  } else if (mode == "resume") {
    result <- sc_run_resume(project_dir, provider = server_demo_provider(), chat_fn = server_demo_chat)
  } else stop("Unsupported demo mode.", call. = FALSE)
  print(result)
  if (identical(result$status, "failed")) stop(result$failure$message, call. = FALSE)
  if (identical(result$status, "complete")) {
    final <- readRDS(result$output$seurat)
    print(table(final$sc_annotation, useNA = "ifany"))
    cat("Final object:", result$output$seurat, "\n")
  }
  invisible(result)
}

if (sys.nframe() == 0L) server_demo_main()
