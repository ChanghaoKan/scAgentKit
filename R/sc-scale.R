#' Scale and center expression values
#'
#' Wrapper around [Seurat::ScaleData()] with a critical default change:
#' \strong{by default we scale only the variable features}, not all genes.
#' Seurat's own default (`features = NULL`) scales every gene, which on a
#' typical 20k+ gene matrix takes minutes for no downstream benefit —
#' [sc_pca()] uses only variable features anyway, and visualisation tools
#' like [Seurat::DoHeatmap()] need scaled data only for the genes plotted.
#'
#' Three modes:
#' \itemize{
#'   \item Default (`features = NULL, all_features = FALSE`): scale on
#'     `VariableFeatures(obj@@data)` only. Fast (seconds on 10k cells).
#'   \item Explicit feature list (`features = c("GENE1", ...)`): scale
#'     exactly those.
#'   \item All genes (`all_features = TRUE`): replicate Seurat's
#'     untouched behaviour. Slow but lets you `DoHeatmap()` arbitrary
#'     genes later.
#' }
#'
#' Use `vars_to_regress` to regress out unwanted sources of variation
#' (cell cycle scores, percent.mt, ...). Regression is the slow part of
#' ScaleData; combined with the all-genes default it produced the ">10
#' minute" experience users used to hit.
#'
#' @param obj An AgentSeurat object (stage >= hvg_found).
#' @param features Optional character vector of features to scale. If
#'   NULL and `all_features = FALSE` (the new default), uses
#'   `VariableFeatures(obj@@data)`.
#' @param all_features Logical. If TRUE, scale every gene (Seurat's
#'   default behaviour). Default FALSE.
#' @param vars_to_regress Optional character vector of metadata columns
#'   to regress out. Default NULL.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat at stage "scaled".
#' @export
sc_scale <- function(obj,
                     features        = NULL,
                     all_features    = FALSE,
                     vars_to_regress = NULL,
                     rationale       = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("sc_scale expects data_type == 'seurat'.")
  }

  # Pull obj@data into a local variable. This is required: passing
  # `obj@data` directly to Seurat verbs (or via do.call) re-runs S4
  # dispatch on Assay5 in a way that hangs indefinitely.
  seu <- obj@data
  # Resolve which features to scale. Read from the local `seu`.
  if (is.null(features) && !isTRUE(all_features)) {
    features <- Seurat::VariableFeatures(seu)
    if (length(features) == 0) {
      warning("No VariableFeatures found; falling back to all_features = TRUE. ",
              "Run sc_find_hvg() first to enable the fast HVG-only path.")
      features <- NULL
      all_features <- TRUE
    }
  }

  # Direct call (NOT do.call) for the same reason as above.
  seu <- if (is.null(features) && is.null(vars_to_regress)) {
    Seurat::ScaleData(seu, verbose = FALSE)
  } else if (is.null(vars_to_regress)) {
    Seurat::ScaleData(seu, features = features, verbose = FALSE)
  } else if (is.null(features)) {
    Seurat::ScaleData(seu, vars.to.regress = vars_to_regress, verbose = FALSE)
  } else {
    Seurat::ScaleData(seu, features = features,
                      vars.to.regress = vars_to_regress, verbose = FALSE)
  }
  obj@data <- seu

  # Build script snippet matching the exact path taken
  feature_arg <- if (isTRUE(all_features)) {
    ""
  } else {
    ',\n                        features = VariableFeatures(seurat_obj)'
  }
  vars_str <- if (is.null(vars_to_regress)) {
    ""
  } else {
    sprintf(',\n                        vars.to.regress = c(%s)',
            paste0('"', vars_to_regress, '"', collapse = ", "))
  }
  scope_label <- if (isTRUE(all_features)) {
    "all genes"
  } else if (!is.null(features) && length(features) > 0) {
    sprintf("%d variable features", length(features))
  } else {
    "variable features"
  }
  script <- sprintf(
'# ---- Scale and center (%s%s) ----
seurat_obj <- ScaleData(seurat_obj%s%s)',
    scope_label,
    if (is.null(vars_to_regress)) "" else
      sprintf("; regressing %s", paste(vars_to_regress, collapse = ", ")),
    feature_arg, vars_str
  )

  if (is.null(rationale)) {
    rationale <- if (is.null(vars_to_regress)) {
      sprintf("ScaleData on %s; no confounders regressed.", scope_label)
    } else {
      sprintf("ScaleData on %s; regressed: %s.",
              scope_label, paste(vars_to_regress, collapse = ", "))
    }
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_scale",
    function_name  = "sc_scale",
    params         = list(
      n_features_scaled = if (isTRUE(all_features)) "all" else length(features),
      all_features      = all_features,
      vars_to_regress   = vars_to_regress
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "scaled"
  )
}
