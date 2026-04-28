#' Normalize counts (LogNormalize by default)
#'
#' Wrapper around [Seurat::NormalizeData()] that records parameters and
#' emits a reproducible script snippet. Operates only on single Seurat
#' objects (`data_type == "seurat"`); normalize *before* splitting if you
#' need per-sample intermediate steps, or *after* merging for integrated
#' workflows.
#'
#' @param obj An AgentSeurat object.
#' @param method Character, normalization method. Default "LogNormalize".
#'   Passed through to `normalization.method`.
#' @param scale_factor Numeric. Default 10000.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat.
#' @export
sc_normalize <- function(obj,
                         method       = "LogNormalize",
                         scale_factor = 10000,
                         rationale    = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("sc_normalize expects data_type == 'seurat'. Call qc_merge() first if needed.")
  }

  # v5 safety: NormalizeData on an Assay5 with split counts layers will
  # produce data layers per split (data.1, data.2, ...). Nearly every
  # downstream step then fails. Join once here and record the fact.
  was_split <- .has_split_layers(obj@data, "counts")
  if (was_split) {
    obj@data <- .ensure_joined(obj@data, "counts")
  }

  # Pull to local var to avoid S4-slot-access slowdown on Seurat v5.
  # (Same root cause as sc_scale: passing obj@data directly to Seurat verbs
  # triggers slot-dispatch overhead; assigning to a local variable first
  # makes it 100x+ faster on large objects.)
  seu <- obj@data
  seu <- Seurat::NormalizeData(
    seu,
    normalization.method = method,
    scale.factor         = scale_factor,
    verbose              = FALSE
  )
  obj@data <- seu

  join_prefix <- if (was_split) {
'# (v5) counts layers were split; join before normalizing.
seurat_obj[["RNA"]] <- JoinLayers(seurat_obj[["RNA"]])
'
  } else ""

  script <- sprintf(
'# ---- Normalization (%s, scale.factor = %s) ----
%sseurat_obj <- NormalizeData(seurat_obj,
                            normalization.method = "%s",
                            scale.factor = %s)',
    method, format(scale_factor), join_prefix,
    method, format(scale_factor)
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "%s normalization with scale.factor = %s applied globally.",
      method, format(scale_factor)
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "sc_normalize",
    function_name  = "sc_normalize",
    params         = list(method = method, scale_factor = scale_factor),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "normalized"
  )
}
