#' Find highly variable features
#'
#' Wrapper around [Seurat::FindVariableFeatures()]. Updates the Seurat
#' object's variable features slot and records the choice for downstream
#' PCA/scaling.
#'
#' @param obj An AgentSeurat object (stage >= normalized).
#' @param method Selection method. Default "vst".
#' @param nfeatures Integer, number of HVGs. Default 2000.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat.
#' @export
sc_find_hvg <- function(obj,
                        method     = "vst",
                        nfeatures  = 2000,
                        rationale  = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("sc_find_hvg expects data_type == 'seurat'.")
  }

  # Pull to local var (see sc_scale for rationale).
  seu <- obj@data
  seu <- Seurat::FindVariableFeatures(
    seu,
    selection.method = method,
    nfeatures        = nfeatures,
    verbose          = FALSE
  )
  obj@data <- seu

  script <- sprintf(
'# ---- Highly variable features (%s, n = %d) ----
seurat_obj <- FindVariableFeatures(seurat_obj,
                                   selection.method = "%s",
                                   nfeatures = %d)',
    method, nfeatures, method, nfeatures
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Selected top %d HVGs via %s for downstream scaling and PCA.",
      nfeatures, method
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_find_hvg",
    function_name  = "sc_find_hvg",
    params         = list(method = method, nfeatures = nfeatures),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "hvg_found"
  )
}
