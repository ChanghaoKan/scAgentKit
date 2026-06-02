#' Build the shared-nearest-neighbor graph
#'
#' Wrapper around [Seurat::FindNeighbors()]. Uses `harmony` if available,
#' otherwise `pca`. The SNN graph is the substrate for Louvain clustering;
#' you only need to rebuild it if you change `reduction` or `ndim`.
#'
#' @param obj An AgentSeurat object.
#' @param reduction Character, source reduction (default auto-picks).
#' @param ndim Integer (defaults to `obj@@params$ndim`).
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat with SNN graph attached.
#' @export
sc_find_neighbors <- function(obj,
                              reduction = NULL,
                              ndim      = NULL,
                              rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (is.null(reduction)) {
    reduction <- if ("harmony" %in% names(obj@data@reductions)) "harmony" else "pca"
  }
  if (is.null(ndim)) ndim <- obj@params$ndim
  if (is.null(ndim)) {
    stop("`ndim` not supplied; run sc_select_pcs() or pass ndim directly.")
  }

  seu <- obj@data
  seu <- Seurat::FindNeighbors(seu, reduction = reduction,
                               dims = seq_len(ndim), verbose = FALSE)
  obj@data <- seu

  script <- sprintf(
'# ---- FindNeighbors (reduction = %s, dims = 1:%d) ----
seurat_obj <- FindNeighbors(seurat_obj, reduction = "%s", dims = 1:%d)',
    reduction, ndim, reduction, ndim
  )

  if (is.null(rationale)) {
    rationale <- sprintf("SNN graph built on %s (1:%d).", reduction, ndim)
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_find_neighbors",
    function_name  = "sc_find_neighbors",
    params         = list(reduction = reduction, ndim = ndim),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "neighbors_found"
  )
}

#' Multi-resolution clustering sweep + clustree diagnostic
#'
#' Runs [Seurat::FindClusters()] at a range of resolutions and saves a
#' clustree plot to help pick a stable resolution. Does NOT commit to a
#' single resolution -- call [sc_cluster()] after inspecting clustree.
#' This two-step pattern mirrors the human workflow (explore -> commit).
#'
#' @param obj An AgentSeurat object after [sc_find_neighbors()].
#' @param resolutions Numeric vector of resolutions to test.
#'   Default `seq(0.1, 0.5, 0.1)`.
#' @param plot_dir Directory for the clustree plot. Default "figures".
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat with multiple `RNA_snn_res.*` metadata
#'   columns and a clustree figure registered in `@@figures`.
#' @export
sc_cluster_sweep <- function(obj,
                             resolutions = seq(0.1, 0.5, 0.1),
                             plot_dir    = "figures",
                             rationale   = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (!requireNamespace("clustree", quietly = TRUE)) {
    stop("Package 'clustree' is required for sc_cluster_sweep.")
  }

  seu <- obj@data
  seu <- Seurat::FindClusters(seu, resolution = resolutions,
                              verbose = FALSE)
  obj@data <- seu

  # The clustree visualisation is helpful but optional. ggraph/clustree
  # versions older than the user's ggplot2 will fail with errors like
  # "Unknown guide: edge_colourbar". Don't let a plotting failure
  # discard the (successful) clustering work -- wrap in tryCatch.
  dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)
  plot_path <- file.path(plot_dir, "clustree.png")
  plot_ok <- tryCatch({
    p <- clustree::clustree(obj@data@meta.data, prefix = "RNA_snn_res.")
    ggplot2::ggsave(plot_path, p, width = 8, height = 8, dpi = 150)
    TRUE
  }, error = function(e) {
    warning("clustree plot failed (clustering itself succeeded): ",
            conditionMessage(e),
            "\nUpgrade with install.packages(c('ggraph','clustree')) ",
            "and call sc_plot_clustree(obj) later if you want the plot.",
            call. = FALSE)
    FALSE
  })

  # Per-resolution cluster counts for the decision log
  cluster_counts <- lapply(resolutions, function(r) {
    col <- sprintf("RNA_snn_res.%s", format(r))
    if (col %in% colnames(obj@data@meta.data)) {
      length(unique(obj@data@meta.data[[col]]))
    } else NA_integer_
  })
  names(cluster_counts) <- as.character(resolutions)

  res_str <- paste(sprintf("%.2f", resolutions), collapse = ", ")
  script <- sprintf(
'# ---- Cluster sweep (resolutions: %s) ----
seurat_obj <- FindClusters(seurat_obj, resolution = c(%s))
clustree::clustree(seurat_obj@meta.data, prefix = "RNA_snn_res.")',
    res_str, res_str
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Cluster sweep across %d resolutions; clustree saved to %s. Inspect stability before committing.",
      length(resolutions), plot_path
    )
  }

  obj <- .record_step(
    obj            = obj,
    step_name      = "sc_cluster_sweep",
    function_name  = "sc_cluster_sweep",
    params         = list(resolutions = resolutions,
                          n_clusters_per_resolution = cluster_counts,
                          clustree_plot_ok = plot_ok),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "cluster_sweep_done"
  )
  if (isTRUE(plot_ok)) {
    obj <- .record_figure(obj, step = "sc_cluster_sweep", path = plot_path,
                          description = sprintf("Clustree across resolutions %s", res_str))
  }
  obj
}

#' Commit to a single clustering resolution
#'
#' @param obj An AgentSeurat object after [sc_find_neighbors()] (and
#'   optionally [sc_cluster_sweep()]).
#' @param resolution Numeric, the resolution to commit to.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat; `seurat_clusters` metadata column is the
#'   committed clustering.
#' @export
sc_cluster <- function(obj,
                       resolution,
                       rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (missing(resolution)) {
    stop("`resolution` is required; inspect clustree from sc_cluster_sweep() first.")
  }

  seu <- obj@data
  seu <- Seurat::FindClusters(seu, resolution = resolution,
                              verbose = FALSE)
  obj@data <- seu
  n_clusters <- length(unique(obj@data$seurat_clusters))

  script <- sprintf(
'# ---- Commit clustering (resolution = %s) ----
seurat_obj <- FindClusters(seurat_obj, resolution = %s)',
    format(resolution), format(resolution)
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Committed resolution = %s, producing %d clusters.",
      format(resolution), n_clusters
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_cluster",
    function_name  = "sc_cluster",
    params         = list(resolution = resolution, n_clusters = n_clusters),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "clustered"
  )
}
