# These tests exercise the qc_mad filtering logic on a small synthetic
# Seurat-like object built with bare-minimum scaffolding. We can't build
# a real Seurat in a unit test without SeuratData, so we test the
# build_keep behaviour indirectly by examining the resulting cell count.
#
# Strategy: create a minimal Seurat with controlled count distribution
# where a single huge outlier should be filtered in linear space but
# NOT in log10 space — proving the new log10 default is the right call.

skip_if_no_seurat <- function() {
  testthat::skip_if_not_installed("Seurat")
}

make_minimal_seurat <- function(counts_per_cell, features_per_cell,
                                  mt_pct = NULL) {
  n_cells <- length(counts_per_cell)
  # Build a sparse count matrix with the requested per-cell library sizes.
  # 1000 genes, distribute count uniformly across the requested feature count.
  n_genes <- 1000
  mat <- Matrix::Matrix(0, nrow = n_genes, ncol = n_cells, sparse = TRUE)
  rownames(mat) <- paste0("gene", seq_len(n_genes))
  colnames(mat) <- paste0("cell", seq_len(n_cells))
  for (j in seq_len(n_cells)) {
    n_feat <- features_per_cell[j]
    per_gene <- ceiling(counts_per_cell[j] / max(n_feat, 1))
    idx <- seq_len(n_feat)
    mat[idx, j] <- per_gene
  }
  seu <- Seurat::CreateSeuratObject(counts = mat)
  if (!is.null(mt_pct)) {
    seu$percent.mt <- mt_pct
  }
  seu
}

test_that("qc_mad in log10 space keeps more right-tail cells than linear-space MAD", {
  skip_if_no_seurat()
  # Realistic scRNA-seq library size distribution: log10(nCount) is
  # roughly normal with SD ~ 0.3. In linear space, this has a heavy
  # right tail — large library cells (well-expressed lymphocytes,
  # active myeloid) at the upper tail are biologically real and should
  # be retained, but linear-space MAD trims them.
  set.seed(123)
  n <- 200
  log_cnts  <- stats::rnorm(n, mean = 3.5, sd = 0.30)  # log10(counts)
  log_feats <- stats::rnorm(n, mean = 3.0, sd = 0.25)
  cnts  <- round(10^log_cnts)
  feats <- round(10^log_feats)
  seu <- make_minimal_seurat(cnts, feats)

  obj <- AgentSeurat(seu)
  obj@data$nCount_RNA   <- as.numeric(cnts)
  obj@data$nFeature_RNA <- as.numeric(feats)

  # Linear-space MAD (pre-v0.1.24): trims the heavy right tail
  obj_linear <- qc_mad(obj, nmad = 3, log_metrics = character(0),
                       metrics = c("nCount_RNA", "nFeature_RNA"))
  # Log10-space MAD (new default): preserves the symmetric tail
  obj_log <- qc_mad(obj, nmad = 3,
                    log_metrics = c("nCount_RNA", "nFeature_RNA"),
                    metrics     = c("nCount_RNA", "nFeature_RNA"))

  expect_gt(ncol(obj_log@data), ncol(obj_linear@data))
})

test_that("qc_mad upper-only metrics (percent.mt) stay in linear space", {
  skip_if_no_seurat()
  set.seed(42)
  n <- 100
  log_cnts  <- stats::rnorm(n, mean = 3.5, sd = 0.30)
  log_feats <- stats::rnorm(n, mean = 3.0, sd = 0.25)
  cnts  <- round(10^log_cnts)
  feats <- round(10^log_feats)
  seu   <- make_minimal_seurat(cnts, feats)
  # 99 normal cells with mt% around 5, one with mt% = 60
  mt    <- c(rep(5, 99), 60)
  seu$percent.mt <- mt

  obj <- AgentSeurat(seu)
  obj@data$nCount_RNA   <- as.numeric(cnts)
  obj@data$nFeature_RNA <- as.numeric(feats)
  obj@data$percent.mt   <- mt

  # mt is upper-only — high-mt outlier must be removed
  obj_filt <- qc_mad(obj, nmad = 3, metrics = c("percent.mt"),
                     log_metrics = character(0))
  expect_lt(ncol(obj_filt@data), n)
  mt_after <- obj_filt@data$percent.mt
  expect_true(all(mt_after < 60))
})
