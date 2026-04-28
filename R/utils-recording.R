# Internal helpers for recording decisions, scripts, and figures.
# Not exported.

# Append a decision + script snippet to an AgentSeurat.
#
# Every tool function calls this at the end, so that the returned object
# carries a complete audit trail.
#
# @param obj AgentSeurat object to update.
# @param step_name Short machine-readable name (matches @@stage convention).
# @param function_name Name of the calling function (for the log).
# @param params Named list of parameters passed to the function.
# @param rationale Human-readable explanation of why this step was taken
#   (ideally LLM-generated or defaulted to a template).
# @param script_snippet Character string with the R code that reproduces
#   this step; will be appended to obj@scripts.
# @param new_stage Optional character, if provided updates obj@stage.
# @param success Logical, whether the step completed successfully.
.record_step <- function(obj,
                         step_name,
                         function_name,
                         params,
                         rationale,
                         script_snippet,
                         new_stage = NULL,
                         success = TRUE) {

  decision <- list(
    step          = step_name,
    function_name = function_name,
    timestamp     = Sys.time(),
    params        = params,
    rationale     = rationale,
    success       = success
  )

  obj@decisions <- c(obj@decisions, list(decision))
  obj@scripts   <- c(obj@scripts, script_snippet)
  # Merge instead of overwrite: @params accumulates rich intermediate
  # products (ndim, batch_candidates, markers_filtered, llm_annotations,
  # reference_matches, resolution_recommendation, ...) that downstream
  # tools depend on. Overwriting wiped them out. Keys present in the new
  # `params` arg take precedence.
  if (length(params) > 0) {
    obj@params[names(params)] <- params
  }
  obj@updated_at <- Sys.time()
  if (!is.null(new_stage)) {
    obj@stage <- new_stage
  }
  obj
}

# Register a figure file against an AgentSeurat.
.record_figure <- function(obj, step, path, description) {
  new_row <- data.frame(
    step        = step,
    path        = path,
    description = description,
    stringsAsFactors = FALSE
  )
  obj@figures <- rbind(obj@figures, new_row)
  obj
}

# Format a named list of parameters into an R-call-style snippet fragment,
# e.g. list(min_nCount = 1000, min_nFeature = 500) becomes
# "min_nCount = 1000, min_nFeature = 500".
.format_params <- function(params) {
  if (length(params) == 0) return("")
  parts <- vapply(names(params), function(nm) {
    val <- params[[nm]]
    val_fmt <- if (is.character(val)) {
      paste0('"', val, '"')
    } else if (is.null(val)) {
      "NULL"
    } else if (is.logical(val)) {
      as.character(val)
    } else if (length(val) > 1) {
      paste0("c(", paste(vapply(val, .format_scalar, character(1)),
                         collapse = ", "), ")")
    } else {
      format(val)
    }
    paste0(nm, " = ", val_fmt)
  }, character(1))
  paste(parts, collapse = ", ")
}

# Format a scalar value for inclusion in a snippet.
.format_scalar <- function(val) {
  if (is.character(val)) paste0('"', val, '"') else format(val)
}

# Search the decision log for a parameter value recorded at a previous step.
#
# Used by downstream functions to auto-pull upstream choices (e.g. ndim
# selected during sc_pca is reused by sc_harmony, sc_umap, sc_cluster
# unless overridden).
#
# @param obj AgentSeurat object.
# @param param_name Name of the parameter to look up.
# @param from_step Optional, restrict search to a specific step name.
# @return The most recently recorded value, or NULL if not found.
.find_in_decisions <- function(obj, param_name, from_step = NULL) {
  for (d in rev(obj@decisions)) {
    if (!is.null(from_step) && d$step != from_step) next
    if (param_name %in% names(d$params)) {
      return(d$params[[param_name]])
    }
  }
  NULL
}

# Apply a function across seurat object or list of seurat objects,
# hiding the data_type branching from the caller.
#
# @param obj AgentSeurat object.
# @param fn A function(seu, ...) -> Seurat.
# @param ... Extra arguments passed to fn.
# @return Updated AgentSeurat object with fn applied in place.
.apply_to_data <- function(obj, fn, ...) {
  if (obj@data_type == "seurat") {
    obj@data <- fn(obj@data, ...)
  } else {
    obj@data <- lapply(obj@data, fn, ...)
  }
  obj
}

# ---- Seurat v5 compatibility helpers ---------------------------------------
#
# Seurat v5 splits counts/data/scale.data into "layers" on the Assay5
# object, and a merged object can hold multiple counts layers (counts.1,
# counts.2, ...) until `JoinLayers()` is called. Many Seurat verbs refuse
# to work on unjoined multi-layer objects (VlnPlot, as.SingleCellExperiment,
# subset with features=, etc.). The helpers below centralise the
# "join if v5 and multi-layer" logic so every tool can be v5-safe with
# one line.

# Return TRUE iff the object's default assay is Seurat v5 (Assay5).
.is_v5_assay <- function(seu) {
  default <- Seurat::DefaultAssay(seu)
  methods::is(seu[[default]], "Assay5")
}

# Return TRUE iff the v5 assay currently holds more than one layer for
# the given `layer_type` (one of "counts", "data", "scale.data"). On v3
# objects, always returns FALSE.
.has_split_layers <- function(seu, layer_type = "counts") {
  if (!.is_v5_assay(seu)) return(FALSE)
  default <- Seurat::DefaultAssay(seu)
  layers  <- SeuratObject::Layers(seu[[default]])
  matches <- grep(sprintf("^%s(\\.|$)", layer_type), layers, value = TRUE)
  length(matches) > 1
}

# Ensure the given layer is joined. For v5 with split layers, call
# JoinLayers on the default assay. No-op otherwise.
.ensure_joined <- function(seu, layer_type = "counts") {
  if (.has_split_layers(seu, layer_type)) {
    default <- Seurat::DefaultAssay(seu)
    seu[[default]] <- SeuratObject::JoinLayers(seu[[default]])
  }
  seu
}
