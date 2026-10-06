#!/usr/bin/env Rscript
# Reuse an already processed Seurat object without rerunning its basic analysis.
# Defaults to a synthetic processed object. Optional local RDS is read in place:
#   Rscript --vanilla server_processed.R /durable/path/to/project
#   Rscript --vanilla server_processed.R /durable/path/to/project /server/data/processed.rds
# Review the saved annotation proposal; approve and resume as shown in the guide.
# No external provider or credential is used by this example.

suppressPackageStartupMessages(library(scAgentKit))
helper <- system.file("examples", "server_first.R", package = "scAgentKit")
if (!nzchar(helper)) stop("Install the current package with its server-first examples.", call. = FALSE)
source(helper, local = TRUE)

server_processed_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (length(args) < 1 || length(args) > 2)
    stop("Usage: server_processed.R PROJECT_DIR [LOCAL_PROCESSED_RDS]", call. = FALSE)
  project_dir <- args[[1]]
  if (length(args) == 2) {
    input <- normalizePath(args[[2]], mustWork = TRUE)
    original <- readRDS(input)
    context <- list(species = "human", tissue = "declare the actual tissue for your study",
      notes = "Local processed RDS example. Replace this context and reason with verified study provenance.")
    reason <- paste("Analyst explicitly selected processed entry for the supplied local RDS.",
      "Replace this example reason with the verified prior QC, normalization and clustering provenance.")
  } else {
    # This call creates a known processed toy for demonstration only. For an
    # existing study object, pass it straight to sc_run below and omit preparation.
    original <- sc_project_prepare(make_server_demo_input(), nfeatures = 200L,
      npcs = 12L, dims = 1:10, resolution = 0.3, seed = 73031L, umap_neighbors = 20L)
    input <- original
    context <- server_demo_context()
    reason <- paste("Synthetic toy was explicitly prepared before this run with",
      "sc_project_prepare; retain all 180 cells, its normalized RNA layer,",
      "PCA, UMAP and cluster membership. No raw-QC filtering was requested.")
  }
  source_hash <- digest::digest(original, algo = "sha256")
  result <- sc_run(input, project_dir = project_dir, context = context,
    start_stage = "processed", processed_reason = reason,
    assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    cluster_column = "seurat_clusters", provider = server_demo_provider(),
    chat_fn = server_demo_chat, budget = 0)
  stopifnot(identical(source_hash, digest::digest(original, algo = "sha256")),
    all(c("qc_evidence", "qc_propose", "qc_apply", "analysis") %in% result$completed))
  print(result)
  if (identical(result$status, "failed")) stop(result$failure$message, call. = FALSE)
  cat("Basic analysis reused. Inspect the saved annotation proposal before approval.\n")
  invisible(result)
}

if (sys.nframe() == 0L) server_processed_main()
