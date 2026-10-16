# Offline synthetic scaling check. No downloads, providers, or paid API calls.
# R_LIBS=../r-library-performance:/path/to/dependency-library Rscript \
#   benchmark/local_performance.R ../evidence/performance-baseline
args <- commandArgs(TRUE)
out <- args[[1L]]
if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE))) stop("Choose a new empty benchmark output directory.")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
suppressPackageStartupMessages(library(scAgentKit))
if (length(args) >= 2L && nzchar(args[[2L]])) {
  exporter <- new.env(parent = asNamespace("scAgentKit"))
  sys.source(args[[2L]], envir = exporter)
  sc_project_export <- exporter$sc_project_export
}
rows <- list()
measure <- function(n, operation, code) {
  gc(reset = TRUE)
  elapsed <- system.time(value <- force(code))[["elapsed"]]
  memory <- gc()
  rows[[length(rows) + 1L]] <<- data.frame(cells = n, operation = operation,
    seconds = elapsed, r_heap_peak_mb = sum(memory[, ncol(memory)]),
    genes = 1000L, density = .02, stringsAsFactors = FALSE)
  utils::write.csv(do.call(rbind, rows), file.path(out, "timings.csv"), row.names = FALSE)
  value
}
set.seed(8101)
sizes <- if (length(args) >= 3L) as.integer(strsplit(args[[3L]], ",", fixed = TRUE)[[1L]]) else c(1000L, 5000L, 10000L)
for (n in sizes) {
  # Exactly 20 distinct detected genes/cell: fixed density and gene count.
  genes <- c(scAgentKit:::.sc_project_panel |> unlist(use.names = FALSE), paste0("GENE", 1:1000))
  genes <- unique(genes)[1:1000]
  counts <- Matrix::sparseMatrix(i = unlist(replicate(n, sample.int(1000L, 20L), simplify = FALSE)),
    j = rep(seq_len(n), each = 20L), x = rep(seq_len(20L), n),
    dims = c(1000L, n), dimnames = list(genes, sprintf("cell%06d", seq_len(n))))
  seu <- SeuratObject::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(seu, layer = "data") <- log1p(counts)
  seu$seurat_clusters <- as.character(rep(0:2, length.out = n))
  coords <- cbind(UMAP_1 = sin(seq_len(n)), UMAP_2 = cos(seq_len(n)))
  rownames(coords) <- colnames(seu)
  seu[["umap"]] <- SeuratObject::CreateDimReducObject(embeddings = coords, key = "UMAP_", assay = "RNA")
  root <- file.path(out, paste0("cells-", n))
  dir.create(root)
  measure(n, "export", sc_project_export(seu, file.path(root, "export"), "synthetic"))
  measure(n, "export_directed_cluster", sc_project_export(seu, file.path(root, "directed"), "synthetic", directed_clusters = "0"))
  project <- file.path(root, "run")
  measure(n, "prepare_processed_complete", {
    initial <- suppressWarnings(sc_run(seu, project, start_stage = "processed", processed_reason = "Synthetic scaling control", provider = NULL, budget = 0))
    stopifnot(identical(initial$status, "awaiting_configuration"))
    ev <- sc_run_inspect(project)$evidence
    proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(ev$clusters,
      function(cl) list(clusterId = cl$clusterId, label = "unknown", confidence = "low", rationale = "Synthetic scaling control", markers = list())))
    pending <- sc_run_propose(project, proposal, "benchmark", "Offline software control")
    sc_run_approve(project, pending$pending$hash, "benchmark", "Synthetic scope reviewed")
    done <- suppressWarnings(sc_run_resume(project))
    stopifnot(identical(done$status, "complete"))
  })
  for (repeat_id in 1:3) measure(n, "inspect_complete", stopifnot(identical(sc_run_inspect(project)$status, "complete")))
  workspace <- file.path(root, "children"); dir.create(workspace)
  measure(n, "list_children_empty", stopifnot(length(sc_run_subcluster_list(project, workspace)$children) == 0L))
  child <- file.path(workspace, "child")
  scope <- sc_run_subcluster_scope(project, clusters = "0")
  measure(n, "create_child", sc_run_subcluster(project, child, clusters = "0",
    parent_scope_hash = scope$parent_scope_hash, expected_parent_revision = scope$expected_parent_revision,
    reviewer = "benchmark", reason = "Synthetic scaling control", request_id = "benchmark-child"))
  for (repeat_id in 1:3) measure(n, "list_children_one", stopifnot(length(sc_run_subcluster_list(project, workspace)$children) == 1L))
  rm(seu, counts); gc()
}
writeLines(capture.output(sessionInfo()), file.path(out, "session-info.txt"))
