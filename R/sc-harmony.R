#' Batch integration with Harmony
#'
#' Wrapper around [harmony::RunHarmony()]. The choice of `group_by_vars`
#' (the batch variable) is one of the highest-impact decisions in the
#' pipeline: over-correction can erase real biological differences between
#' conditions, under-correction leaves technical noise dominating the
#' embedding. This function treats the batch variable as an *explicit
#' required argument* (no default), forcing the caller (agent or user) to
#' commit to a deliberate choice rather than silently picking one.
#'
#' @param obj An AgentSeurat object after [sc_pca()].
#' @param group_by_vars Character (or character vector) naming the
#'   metadata column(s) to correct for. There is no default; common
#'   choices include `"sample"`, `"Seq.Batch.ID"`, `"donor"`. If you
#'   believe the data needs no correction, skip this function entirely
#'   rather than passing a dummy variable.
#' @param ndim Integer, PCs to use. Defaults to `obj@@params$ndim` if
#'   [sc_select_pcs()] has been called.
#' @param max_iter Maximum Harmony iterations. Default 10.
#' @param seed Integer, random seed. Default 999.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat with a `harmony` reduction attached.
#' @export
sc_harmony <- function(obj,
                       group_by_vars,
                       ndim      = NULL,
                       max_iter  = 10,
                       seed      = 999,
                       rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (missing(group_by_vars) || is.null(group_by_vars)) {
    stop("`group_by_vars` is required. Name the batch variable explicitly, or skip sc_harmony() if no correction is needed.")
  }
  if (!requireNamespace("harmony", quietly = TRUE)) {
    stop("Package 'harmony' is required for sc_harmony.")
  }

  if (is.null(ndim)) ndim <- obj@params$ndim
  if (is.null(ndim)) {
    stop("`ndim` not supplied and obj@params$ndim not set. Run sc_select_pcs() first or pass ndim explicitly.")
  }

  # Verify column(s) exist
  missing_cols <- setdiff(group_by_vars, colnames(obj@data@meta.data))
  if (length(missing_cols) > 0) {
    stop(sprintf("Metadata column(s) not found: %s",
                 paste(missing_cols, collapse = ", ")))
  }

  set.seed(seed)
  seu <- obj@data
  seu <- harmony::RunHarmony(
    seu,
    reduction      = "pca",
    group.by.vars  = group_by_vars,
    reduction.save = "harmony",
    max_iter       = max_iter
  )
  obj@data <- seu

  vars_str <- if (length(group_by_vars) == 1) {
    sprintf('"%s"', group_by_vars)
  } else {
    paste0('c("', paste(group_by_vars, collapse = '", "'), '")')
  }

  script <- sprintf(
'# ---- Harmony batch integration ----
set.seed(%d)
seurat_obj <- RunHarmony(seurat_obj,
                         reduction      = "pca",
                         group.by.vars  = %s,
                         reduction.save = "harmony",
                         max_iter       = %d)',
    seed, vars_str, max_iter
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Harmony integration on %s using top %d PCs, %d iterations.",
      paste(group_by_vars, collapse = "+"), ndim, max_iter
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_harmony",
    function_name  = "sc_harmony",
    params         = list(group_by_vars = group_by_vars, ndim = ndim,
                          max_iter = max_iter, seed = seed),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "harmony_integrated"
  )
}
