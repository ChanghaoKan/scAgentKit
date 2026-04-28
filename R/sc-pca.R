#' Run PCA on the scaled data
#'
#' Wrapper around [Seurat::RunPCA()]. Uses variable features by default.
#'
#' @param obj An AgentSeurat object (stage >= scaled).
#' @param npcs Integer, number of PCs to compute. Default 50.
#' @param features Optional character vector of features. If NULL, uses
#'   `VariableFeatures(object)`.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat; the resulting `pca` reduction is attached
#'   to the Seurat object.
#' @export
sc_pca <- function(obj,
                   npcs      = 50,
                   features  = NULL,
                   rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("sc_pca expects data_type == 'seurat'.")
  }

  seu <- obj@data
  features_use <- if (!is.null(features)) features else Seurat::VariableFeatures(seu)
  # Direct call (not do.call); see sc_scale comment.
  seu <- Seurat::RunPCA(seu, features = features_use,
                        npcs = npcs, verbose = FALSE)
  obj@data <- seu

  script <- sprintf(
'# ---- PCA (npcs = %d) ----
seurat_obj <- RunPCA(seurat_obj,
                     features = VariableFeatures(seurat_obj),
                     npcs = %d)',
    npcs, npcs
  )

  if (is.null(rationale)) {
    rationale <- sprintf("PCA computed on %d PCs using variable features.", npcs)
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_pca",
    function_name  = "sc_pca",
    params         = list(npcs = npcs,
                          features_supplied = !is.null(features)),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "pca_done"
  )
}

#' Automatically select number of PCs by cumulative variance
#'
#' Computes the minimum number of PCs whose cumulative variance exceeds
#' `threshold`. Optionally saves an elbow plot for inspection. The chosen
#' `ndim` is stored in `@@params$ndim` so that downstream functions
#' ([sc_harmony()], [sc_umap()], [sc_find_neighbors()]) pick it up
#' by default.
#'
#' @param obj An AgentSeurat object after [sc_pca()].
#' @param threshold Cumulative variance fraction. Default 0.80.
#' @param plot_elbow Logical. If TRUE, saves an elbow plot to `plot_dir`.
#' @param plot_dir Directory for the elbow plot. Default "figures".
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat with `@@params$ndim` set.
#' @export
sc_select_pcs <- function(obj,
                          threshold  = 0.80,
                          plot_elbow = TRUE,
                          plot_dir   = "figures",
                          rationale  = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  pca <- tryCatch(obj@data[["pca"]], error = function(e) NULL)
  if (is.null(pca)) stop("No 'pca' reduction found; call sc_pca() first.")

  xx <- cumsum(pca@stdev^2)
  xx <- xx / max(xx)
  ndim <- which(xx >= threshold)[1]
  if (is.na(ndim)) ndim <- length(pca@stdev)

  plot_path <- NA_character_
  if (plot_elbow) {
    dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)
    plot_path <- file.path(plot_dir, "pca_elbow.png")
    p <- Seurat::ElbowPlot(obj@data, ndims = length(pca@stdev)) +
      ggplot2::geom_vline(xintercept = ndim, linetype = "dashed",
                          color = "red") +
      ggplot2::labs(subtitle = sprintf(
        "Selected ndim = %d (cum. var >= %.0f%%)", ndim, 100 * threshold))
    ggplot2::ggsave(plot_path, p, width = 7, height = 5, dpi = 150)
  }

  script <- sprintf(
'# ---- PC selection (cum. variance >= %.2f) ----
xx   <- cumsum(seurat_obj[["pca"]]@stdev^2)
xx   <- xx / max(xx)
ndim <- which(xx >= %.2f)[1]
cat("Selected", ndim, "PCs\\n")',
    threshold, threshold
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Selected %d PCs (cumulative variance >= %.0f%%) for downstream steps.",
      ndim, 100 * threshold
    )
  }

  # Persist ndim so downstream functions can default to it
  obj@params$ndim <- ndim

  obj <- .record_step(
    obj            = obj,
    step_name      = "sc_select_pcs",
    function_name  = "sc_select_pcs",
    params         = list(threshold = threshold, ndim = ndim,
                          plot_path = plot_path),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "pcs_selected"
  )

  if (plot_elbow) {
    obj <- .record_figure(obj, step = "sc_select_pcs",
                          path = plot_path,
                          description = sprintf("Elbow plot (ndim = %d)", ndim))
  }
  obj
}
