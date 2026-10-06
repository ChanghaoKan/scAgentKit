# Exercise the exact production stage exporter, without evaluating the bridge's
# CLI/coordinator entry or running any analysis. The private toy only has saved
# layers, literal membership, saved coordinates and a supplied marker row.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
suppressPackageStartupMessages(library(scAgentKit))
ns <- asNamespace("scAgentKit")
get <- function(name) base::get(name, envir = ns, inherits = FALSE)
hash <- get(".sc_run_hash"); sha <- get(".sc_project_sha_file")
root <- tempfile("saved-stage-unit-"); dir.create(root); dir.create(file.path(root, "checkpoints"))
on.exit_cleanup <- function() unlink(root, recursive = TRUE)
counts <- Matrix::Matrix(matrix(c(3, 0, 2, 0, 1, 0, 0, 2, 1, 3, 0, 2), nrow = 3), sparse = TRUE)
rownames(counts) <- c("G1", "G2", "G3"); colnames(counts) <- c("NA", "001", "cell 中文", "1")
seu <- SeuratObject::CreateSeuratObject(counts = counts)
SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- counts
seu$seurat_clusters <- c("T alpha", "T alpha", "NA", "NA")
seu$private_metadata <- "PRIVATE_METADATA_SENTINEL"
seu$old_annotation <- "PRIVATE_ANNOTATION_SENTINEL"
seu@misc$sc_project_prepare <- list(private = "PRIVATE_MISC_SENTINEL")
coordinates <- matrix(seq_len(8) / 3, ncol = 2, dimnames = list(colnames(seu), c("UMAP_1", "UMAP_2")))
seu[["umap"]] <- SeuratObject::CreateDimReducObject(embeddings = coordinates, key = "UMAP_", assay = "RNA")
markers <- data.frame(cluster = "T alpha", gene = "G1", avg_log2FC = 1.5, pct.1 = .7, pct.2 = .2, p_val_adj = .01)
expected <- data.frame(cell_id = colnames(seu), cluster = as.character(seu$seurat_clusters), stringsAsFactors = FALSE)
annotation <- list(private = list(input_cells = expected, cluster_column = "seurat_clusters",
  candidates = "PRIVATE_CANDIDATE_SENTINEL"))
state <- list(project_id = "run-unit-stage", input_hash = strrep("a",64), config_hash = strrep("b",64),
  implementation_hash = strrep("c",64), revision = 9L,
  config = list(cluster_column = "seurat_clusters", assay = "RNA", counts_layer = "counts", normalized_layer = "data"), files = list())
put <- function(name, value) {
  path <- file.path("checkpoints", paste0(name, "-", hash(value), ".rds"))
  saveRDS(value, file.path(root, path), version = 2L)
  state$files[[name]] <<- list(path = path, sha256 = sha(file.path(root, path)))
}
put("analysis", seu); put("markers", markers); put("annotation_evidence", annotation)
run <- list(annotation_review = NULL); before <- strrep("d",64); head <- strrep("e",64)
found <- NULL
walk <- function(node) {
  if (missing(node) || !is.call(node)) return(invisible(NULL))
  if (identical(node[[1L]], as.name("<-")) && identical(node[[2L]], as.name("stage_bundle")) && is.call(node[[3L]])) {
    factory <- node[[3L]][[1L]]
    while (is.call(factory) && identical(factory[[1L]], as.name("("))) factory <- factory[[2L]]
    if (is.call(factory) && identical(factory[[1L]], as.name("function"))) found <<- eval(factory)
  }
  for (item in as.list(node)) walk(item)
}
for (expression in parse(args[[1L]])) walk(expression)
stopifnot(is.function(found))
reject <- function(expected_message) {
  problem <- tryCatch({found(); NULL}, error = identity)
  stopifnot(inherits(problem, "error"), grepl(expected_message, conditionMessage(problem), fixed = TRUE))
}
tryCatch({
  files_before <- vapply(list.files(root, recursive = TRUE, full.names = TRUE), sha, character(1))
  value <- found()
  stopifnot(identical(sort(names(value$blobs)), c("manifest.json", "project.json")), value$cell_count == 4L,
    identical(value$scope_hash, hash(expected)), identical(value$checkpoint_records, state$files),
    identical(files_before, vapply(list.files(root, recursive = TRUE, full.names = TRUE), sha, character(1))))
  document <- jsonlite::fromJSON(value$blobs$project.json, simplifyVector = FALSE)
  stopifnot(length(document$embedding$points) == 4L, length(document$markers) == 1L,
    is.null(document$sourceAnnotation), !length(document$candidates), !length(document$models),
    !length(document$directed$clusters), all(vapply(document$cells, function(x) !length(x$qc), logical(1))),
    !grepl("PRIVATE_", value$blobs$project.json, fixed = TRUE),
    identical(document$parameters$savedStageSnapshot$records, state$files))
  original <- state$files
  state$files$markers <- NULL; reject("Missing saved analysis evidence"); state$files <- original
  state$files$analysis$path <- "../foreign.rds"; reject("Saved stage checkpoint changed or is foreign"); state$files <- original
  state$files$analysis$sha256 <- strrep("0",64); reject("Saved stage checkpoint changed or is foreign"); state$files <- original
  path <- file.path(root, state$files$markers$path); bytes <- readBin(path, "raw", file.info(path)$size)
  unlink(path); reject("Saved stage checkpoint changed or is foreign"); writeBin(bytes, path)
  writeBin(charToRaw("tampered marker checkpoint"), path); reject("Saved stage checkpoint changed or is foreign"); writeBin(bytes, path)
  put("annotation_evidence", modifyList(annotation, list(private = list(input_cells = expected[4:1, , drop = FALSE]))))
  reject("Analysis cells differ from saved annotation scope"); state$files <- original
  run$annotation_review <- list(cell_scope_hash = strrep("0",64)); reject("Annotation review scope differs"); run$annotation_review <- NULL
  cat("PASS production R saved-stage export: exact cells/markers, no private metadata, missing/foreign/tampered/stale scope refused; no analysis/API/project mutation\n")
}, finally = on.exit_cleanup())
