#' Per-sample doublet detection with scDblFinder
#'
#' Runs scDblFinder on each element of a Seurat list and optionally removes
#' detected doublets. Running *per sample* (rather than on a merged object)
#' is critical: merged-object doublet detection inflates false positives
#' because inter-sample cell-type mixing is misread as heterotypic doublets.
#'
#' Requires `data_type == "seurat_list"`. Call [qc_split()] first.
#'
#' @param obj An AgentSeurat object with `data_type == "seurat_list"`.
#' @param remove Logical. If TRUE (default), cells classified as doublets
#'   are removed in place. If FALSE, doublet metadata is added but cells
#'   are kept, allowing downstream inspection.
#' @param seed Integer seed for reproducibility. Default 999.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat object with `doublet_class` and
#'   `doublet_score` in the metadata of each sample.
#' @export
qc_doublet <- function(obj,
                       remove    = TRUE,
                       seed      = 999,
                       rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat_list") {
    stop("qc_doublet requires data_type == 'seurat_list'. Call qc_split() first.")
  }
  if (!requireNamespace("scDblFinder", quietly = TRUE)) {
    stop("Package 'scDblFinder' is required for qc_doublet.")
  }
  if (!requireNamespace("SingleCellExperiment", quietly = TRUE)) {
    stop("Package 'SingleCellExperiment' is required for qc_doublet.")
  }

  n_before <- .count_cells(obj)

  detect_one <- function(seu) {
    # Seurat v5 safety: qc_doublet typically runs on per-sample objects
    # where counts is a single layer, but if upstream code merged and
    # re-split, layers could be fragmented. Ensure joined first.
    seu <- .ensure_joined(seu, "counts")

    # Build SCE explicitly from the counts matrix so we never rely on
    # as.SingleCellExperiment's assumptions about which layer to pull.
    # scDblFinder only needs counts.
    counts_mat <- SeuratObject::GetAssayData(
      seu, assay = Seurat::DefaultAssay(seu), layer = "counts"
    )
    sce <- SingleCellExperiment::SingleCellExperiment(
      assays = list(counts = counts_mat)
    )
    set.seed(seed)
    sce <- scDblFinder::scDblFinder(sce)

    seu$doublet_class <- sce$scDblFinder.class
    seu$doublet_score <- sce$scDblFinder.score
    if (remove) {
      seu <- subset(seu, subset = doublet_class == "singlet")
    }
    seu
  }

  obj@data <- lapply(obj@data, detect_one)
  n_after  <- .count_cells(obj)

  # Doublet rates per sample (from metadata)
  rate_summary <- vapply(obj@data, function(seu) {
    mean(seu$doublet_class == "doublet")
  }, numeric(1))
  rate_str <- paste(
    sprintf("%s=%.2f%%", names(rate_summary), 100 * rate_summary),
    collapse = ", "
  )

  script <- sprintf(
'# ---- Per-sample doublet detection (scDblFinder) ----
# MUST run per sample; merging before detection inflates false positives.
# Build SCE from counts directly (v5-safe; avoids as.SingleCellExperiment
# layer ambiguity with Assay5 objects).
seurat_list <- lapply(seurat_list, function(seu) {
  if (methods::is(seu[[DefaultAssay(seu)]], "Assay5")) {
    seu[[DefaultAssay(seu)]] <- JoinLayers(seu[[DefaultAssay(seu)]])
  }
  counts_mat <- GetAssayData(seu, assay = DefaultAssay(seu), layer = "counts")
  sce <- SingleCellExperiment::SingleCellExperiment(
    assays = list(counts = counts_mat))
  set.seed(%d)
  sce <- scDblFinder::scDblFinder(sce)
  seu$doublet_class <- sce$scDblFinder.class
  seu$doublet_score <- sce$scDblFinder.score
  %s
})',
    seed,
    if (remove) 'subset(seu, subset = doublet_class == "singlet")' else 'seu'
  )

  if (is.null(rationale)) {
    rationale <- if (remove) {
      sprintf("scDblFinder per-sample; removed doublets. Rates: %s. %d -> %d cells.",
              rate_str, n_before, n_after)
    } else {
      sprintf("scDblFinder per-sample; metadata added (not removed). Rates: %s.",
              rate_str)
    }
  }

  .record_step(
    obj            = obj,
    step_name      = "qc_doublet",
    function_name  = "qc_doublet",
    params         = list(
      remove    = remove,
      seed      = seed,
      n_before  = n_before,
      n_after   = n_after,
      per_sample_doublet_rate = as.list(rate_summary)
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = if (remove) "doublet_removed" else "doublet_scored"
  )
}
