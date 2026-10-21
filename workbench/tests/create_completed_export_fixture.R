# Offline completed project for native convenience-export recovery checks.
args <- commandArgs(trailingOnly = TRUE)
suppressPackageStartupMessages(library(scAgentKit))
data("pbmc_small", package = "SeuratObject")
pbmc_small$seurat_clusters <- as.character(SeuratObject::Idents(pbmc_small))
out <- suppressWarnings(sc_run(pbmc_small, args[[1]], start_stage = "processed",
  processed_reason = "Public pbmc_small processed software fixture", provider = NULL))
stopifnot(identical(out$status, "awaiting_configuration"))
evidence <- sc_run_inspect(args[[1]])$evidence
proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(evidence$clusters,
  function(cl) list(clusterId = cl$clusterId, label = "unknown", confidence = "low",
    rationale = "Software fixture only", markers = list())))
out <- sc_run_propose(args[[1]], proposal, "test", "Offline fixture")
sc_run_approve(args[[1]], out$pending$hash, "test", "Reviewed synthetic scope")
stopifnot(identical(suppressWarnings(sc_run_resume(args[[1]]))$status, "complete"))
