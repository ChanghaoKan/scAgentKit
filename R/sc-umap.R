#' Run UMAP on PCA or Harmony embedding
#'
#' Wrapper around [Seurat::RunUMAP()]. Defaults to the `harmony` reduction
#' if present, otherwise falls back to `pca`.
#'
#' @param obj An AgentSeurat object.
#' @param reduction Character, source reduction. If NULL (default), picks
#'   `"harmony"` when present, otherwise `"pca"`.
#' @param ndim Integer, dims to use. Defaults to `obj@@params$ndim`.
#' @param reduction_name Name to store the UMAP under. Default `"umap"`.
#' @param seed Integer seed. Default 999.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat with `umap` reduction attached.
#' @export
sc_umap <- function(obj,
                    reduction       = NULL,
                    ndim            = NULL,
                    reduction_name  = "umap",
                    seed            = 999,
                    rationale       = NULL) {
  .legacy_workflow_warn("sc_umap")


  stopifnot(methods::is(obj, "AgentSeurat"))

  if (is.null(reduction)) {
    reduction <- if ("harmony" %in% names(obj@data@reductions)) "harmony" else "pca"
  }
  if (is.null(ndim)) ndim <- obj@params$ndim
  if (is.null(ndim)) {
    if (!is.null(obj@params$pcs_visual_recommendation$status) &&
        !identical(obj@params$pcs_visual_recommendation$status, "ok")) {
      stop("The latest visual PC selection failed; review it and select PCs again, or pass ndim explicitly. Historical ndim is audit-only.")
    }
    stop("`ndim` not supplied; run sc_select_pcs() or pass ndim directly.")
  }

  set.seed(seed)
  seu <- obj@data
  seu <- Seurat::RunUMAP(
    seu,
    reduction      = reduction,
    dims           = seq_len(ndim),
    reduction.name = reduction_name,
    seed.use       = seed,
    verbose        = FALSE
  )
  obj@data <- seu

  script <- sprintf(
'# ---- UMAP (reduction = %s, dims = 1:%d) ----
seurat_obj <- RunUMAP(seurat_obj,
                      reduction      = "%s",
                      dims           = 1:%d,
                      reduction.name = "%s",
                      seed.use       = %d)',
    reduction, ndim, reduction, ndim, reduction_name, seed
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "UMAP computed on %s reduction using 1:%d dims, stored as '%s'.",
      reduction, ndim, reduction_name
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_umap",
    function_name  = "sc_umap",
    params         = list(reduction = reduction, ndim = ndim,
                          reduction_name = reduction_name, seed = seed),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "umap_done"
  )
}
