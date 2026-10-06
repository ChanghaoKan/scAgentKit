#' Explicitly choose cell-cycle regression
#'
#' `mode = "none"` returns the object unchanged and performs no scaling.
#' `mode = "full"` calls [sc_scale()] with `S.Score` and `G2M.Score` to
#' reduce both phase and cycling-versus-noncycling variation.
#' `mode = "difference"` regresses `CC.Difference` to suppress the
#' S-versus-G2M phase contrast while preserving the distinction between
#' cycling and noncycling cells. Neither mode deletes cells.
#'
#' Full or difference regression requires finite, nonconstant scores and an
#' estimable retained-cell design. Re-run [sc_pca()] and downstream analyses
#' after either regression mode changes scaled data. A scientific rationale
#' and lineage context should guide the explicit choice; full is not a default.
#'
#' @param obj An AgentSeurat; scores are needed only for regression modes.
#' @param mode One of `"none"`, `"full"`, or `"difference"`; default `"none"`.
#' @param rationale Optional rationale for the audit record.
#' @return For `none`, the unchanged object. Otherwise an updated AgentSeurat
#'   at stage `"scaled"`, with downstream analyses requiring recomputation.
#' @export
sc_cellcycle_regress <- function(obj, mode = "none",
                                 rationale = NULL) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  mode <- match.arg(mode, c("none", "full", "difference"))
  if (identical(mode, "none")) return(obj)
  if (obj@data_type != "seurat")
    stop("sc_cellcycle_regress expects data_type == 'seurat'.", call. = FALSE)
  vars <- switch(mode, full = c("S.Score", "G2M.Score"), difference = "CC.Difference")
  metadata <- obj@data[[]]
  if (!all(vars %in% names(metadata)))
    stop("Required cell-cycle scores are missing; call sc_cellcycle_score() first.", call. = FALSE)
  scores <- metadata[, vars, drop = FALSE]
  if (any(!vapply(scores, is.numeric, logical(1))) || any(!is.finite(as.matrix(scores))) ||
      any(!is.finite(vapply(scores, stats::var, numeric(1)))) ||
      any(vapply(scores, stats::var, numeric(1)) <= 0))
    stop("Cell-cycle regression requires finite scores with nonzero variance in retained cells.", call. = FALSE)
  design <- cbind(intercept = 1, as.matrix(scores))
  if (qr(design)$rank != ncol(design) || nrow(design) <= ncol(design))
    stop("Cell-cycle regression design is rank deficient or has no residual degrees of freedom.", call. = FALSE)
  if (is.null(rationale)) rationale <- sprintf(
    "Explicit cell-cycle %s regression with %s; no cells removed. Re-run downstream PCA/UMAP/clustering.",
    mode, paste(vars, collapse = ", "))
  sc_scale(obj, vars_to_regress = vars, rationale = rationale)
}
