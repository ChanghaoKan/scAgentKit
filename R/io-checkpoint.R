#' Save an AgentSeurat checkpoint to disk
#'
#' Serializes the full AgentSeurat (data + decision log + scripts + figures
#' registry) to a single `.qs2` file for fast reload. Recommended after each
#' major stage (QC, PCA, Harmony, clustering) so the agent can resume from
#' any step if later stages fail.
#'
#' @param obj An AgentSeurat object.
#' @param path File path ending in `.qs2`.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return The AgentSeurat object (invisibly), unchanged except for a
#'   checkpoint entry in the decision log.
#' @export
save_checkpoint <- function(obj, path, rationale = NULL) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  qs2::qs_save(obj, file = path)

  if (is.null(rationale)) {
    rationale <- sprintf("Checkpointed to %s at stage '%s'.", path, obj@stage)
  }

  script <- sprintf('# ---- Checkpoint ----\nqs2::qs_save(obj, "%s")', path)

  obj <- .record_step(
    obj            = obj,
    step_name      = "save_checkpoint",
    function_name  = "save_checkpoint",
    params         = list(path = path, stage = obj@stage),
    rationale      = rationale,
    script_snippet = script
  )
  invisible(obj)
}

#' Load an AgentSeurat checkpoint
#'
#' @param path Path to a `.qs2` file saved by [save_checkpoint()].
#' @return The loaded AgentSeurat object.
#' @export
load_checkpoint <- function(path) {
  obj <- qs2::qs_read(path)
  if (!methods::is(obj, "AgentSeurat")) {
    stop(sprintf("File '%s' does not contain an AgentSeurat object.", path))
  }
  obj
}
