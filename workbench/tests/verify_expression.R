#!/usr/bin/env Rscript
# Independent verification against existing RNA layers, without matrix export.
suppressPackageStartupMessages(library(SeuratObject))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(digest))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Usage: verify_expression.R SOURCE_RDS EXPRESSION_JSON INPUT_CELLS_CSV", call. = FALSE)
source_sha_before <- digest(args[1], algo = "sha256", file = TRUE)
object <- readRDS(args[1])
bundle <- fromJSON(args[2], simplifyVector = FALSE)
input <- read.csv(args[3], stringsAsFactors = FALSE, colClasses = "character")
ids <- unlist(bundle$scope$cell_ids, use.names = FALSE)
stopifnot(identical(source_sha_before, bundle$source$rds_sha256),
          identical(sort(input$cell_id[input$cluster == "6"]), ids),
          length(ids) == 155L, !anyDuplicated(ids))
counts <- LayerData(object, assay = "RNA", layer = "counts")
normalized <- LayerData(object, assay = "RNA", layer = "data")
stopifnot(ncol(counts) == 2638L, setequal(colnames(counts), input$cell_id))
equal_number <- function(a, b) {
  length(a) == length(b) && all(abs(as.numeric(a) - as.numeric(b)) <= 5e-13)
}
gene_checks <- 0L
for (gene in vapply(bundle$panel, function(x) x$gene, character(1))) {
  observed_counts <- lapply(bundle$cells, function(cell) cell$counts[[gene]])
  observed_norm <- lapply(bundle$cells, function(cell) cell$normalized[[gene]])
  if (!gene %in% rownames(counts)) {
    stopifnot(all(vapply(observed_counts, is.null, logical(1))),
              all(vapply(observed_norm, is.null, logical(1))))
  } else {
    stopifnot(equal_number(unlist(observed_counts, use.names = FALSE), as.numeric(counts[gene, ids])),
              equal_number(unlist(observed_norm, use.names = FALSE), as.numeric(normalized[gene, ids])))
  }
  gene_checks <- gene_checks + 1L
}
qc_checks <- 0L
for (field in c("nCount_RNA", "nFeature_RNA", "percent.mt", "orig.ident")) {
  observed <- unlist(lapply(bundle$cells, function(cell) cell$qc[[field]]), use.names = FALSE)
  actual <- object@meta.data[ids, field]
  if (field == "orig.ident") stopifnot(identical(as.character(observed), as.character(actual)))
  else stopifnot(equal_number(observed, actual))
  qc_checks <- qc_checks + 1L
}
stopifnot(identical(digest(args[1], algo = "sha256", file = TRUE), source_sha_before))
cat(toJSON(list(status = "passed", exact_scope = TRUE, gene_checks = gene_checks,
                per_cell_values_checked = 155L * gene_checks * 2L, qc_checks = qc_checks,
                numeric_tolerance = 5e-13, source_sha256 = source_sha_before,
                read_only_source_unchanged = TRUE, api_calls = 0L), auto_unbox = TRUE), "\n")
