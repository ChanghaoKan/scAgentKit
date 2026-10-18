# Rank aggregation uses explicitly declared samples, never inferred conditions.
.sc_run_sample_hvg <- function(seu, assay, column, nfeatures) {
  if (!column %in% names(seu[[]])) stop("Sample HVG column is absent.", call. = FALSE)
  values <- as.character(seu[[]][[column]])
  if (anyNA(values) || any(!nzchar(values))) stop("Sample HVG requires complete sample IDs.", call. = FALSE)
  ids <- sort(unique(values), method = "radix")
  if (length(ids) < 2L || any(table(values) < 30L))
    stop("Sample HVG requires at least two explicitly declared samples with at least 30 retained cells each.", call. = FALSE)
  ranked <- lapply(ids, function(id) {
    working <- subset(seu, cells = colnames(seu)[values == id])
    working <- Seurat::FindVariableFeatures(working, assay = assay, selection.method = "vst",
      nfeatures = nfeatures, verbose = FALSE)
    genes <- SeuratObject::VariableFeatures(working[[assay]])
    if (length(genes) != nfeatures || anyDuplicated(genes))
      stop("An explicit sample cannot supply the requested number of unique HVGs.", call. = FALSE)
    genes
  }); names(ranked) <- ids
  genes <- sort(unique(unlist(ranked, use.names = FALSE)), method = "radix")
  frequency <- vapply(genes, function(gene) sum(vapply(ranked, function(x) gene %in% x, logical(1))), integer(1))
  ranks <- vapply(genes, function(gene) stats::median(vapply(ranked, function(x) {
    rank <- match(gene,x); if(is.na(rank)) nfeatures + 1 else rank
  }, numeric(1))), numeric(1))
  ordered <- order(-frequency, ranks, genes, method = "radix")
  selected <- head(genes[ordered], nfeatures)
  list(features = selected, sample_column = column, sample_cells = as.list(table(values)),
    sample_hvgs = ranked, selection_frequency = stats::setNames(frequency[match(selected,genes)],selected),
    median_rank = stats::setNames(ranks[match(selected,genes)],selected),
    method = "frequency then median within-sample rank (unselected rank=nfeatures+1), then literal gene",
    interpretation = "Equal sample contributions; empirical consensus can lose sample-specific biology. No automatic quality or batch inference.")
}
