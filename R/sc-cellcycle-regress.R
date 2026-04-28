#' Regress out cell cycle signal (optional, after scoring)
#'
#' Convenience wrapper that calls [sc_scale()] with the appropriate
#' `vars.to.regress`. Two common strategies:
#'
#' \itemize{
#'   \item \code{mode = "full"}: regress `c("S.Score", "G2M.Score")`.
#'     Removes the entire cell cycle signal. Use when cell cycle is pure
#'     noise for your biology (most cases).
#'   \item \code{mode = "difference"}: regress `"CC.Difference"`.
#'     Removes only the *cycling vs non-cycling* contrast while preserving
#'     the proliferating identity. Use when proliferating cells are a
#'     biological group of interest (e.g. stem / progenitor / tumor
#'     cells) and you want to keep them clustered together rather than
#'     split across cycle phases.
#' }
#'
#' After calling this, you must re-run [sc_pca()] (and anything
#' downstream) since the scaled data has changed.
#'
#' @param obj An AgentSeurat object after [sc_cellcycle_score()].
#' @param mode Character, one of `"full"` or `"difference"`. No default;
#'   the caller must commit to a strategy.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat (stage "scaled"); downstream reductions
#'   invalidated.
#' @export
sc_cellcycle_regress <- function(obj,
                                 mode      = c("full", "difference"),
                                 rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (!"S.Score" %in% colnames(obj@data@meta.data)) {
    stop("S.Score not in metadata; call sc_cellcycle_score() first.")
  }
  mode <- match.arg(mode)

  vars <- switch(
    mode,
    full       = c("S.Score", "G2M.Score"),
    difference = "CC.Difference"
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Regressed out cell cycle (%s mode: %s). Downstream PCA/UMAP/clustering must be re-run.",
      mode, paste(vars, collapse = ", ")
    )
  }

  sc_scale(obj, vars_to_regress = vars, rationale = rationale)
}
