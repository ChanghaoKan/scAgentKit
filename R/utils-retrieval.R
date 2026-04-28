# Internal helper: retrieve the most recent decision's params for a given step.
# Used by downstream tools that need values from upstream (e.g. sc_harmony
# needs ndim from sc_select_pcs).

.get_step_params <- function(obj, step_name) {
  hits <- Filter(function(d) d$step == step_name, obj@decisions)
  if (length(hits) == 0) return(NULL)
  hits[[length(hits)]]$params
}

# Retrieve ndim from the most recent sc_select_pcs call, or error with a
# clear message.
.require_ndim <- function(obj) {
  p <- .get_step_params(obj, "sc_select_pcs")
  if (is.null(p) || is.null(p$ndim)) {
    stop("ndim not set. Call sc_select_pcs() first.")
  }
  p$ndim
}
