#' AgentSeurat: scRNA-seq-specific subclass of AgentOmics
#'
#' A thin S4 subclass of [agentomicsCore::AgentOmics] that signals
#' "this container holds Seurat-shaped data". It adds no new slots and
#' overrides no behaviour -- the subclass exists for backward
#' compatibility with checkpoints saved by scAgentKit v0.1.x/v0.2.x
#' (whose serialised objects have class `"AgentSeurat"`) and to give
#' downstream code a domain-specific type tag.
#'
#' New objects constructed via [AgentSeurat()] carry both classes
#' (`AgentSeurat` AND `AgentOmics`), so `methods::is(obj, "AgentOmics")`
#' continues to pass and the entire agentomicsCore extension API
#' (`record_step()`, `find_in_decisions()`, `render_report()`, ...)
#' works unchanged.
#'
#' @name AgentSeurat-class
#' @rdname AgentSeurat-class
#' @importFrom methods setClass setMethod new is validObject slotNames as callNextMethod setValidity
#' @importClassesFrom agentomicsCore AgentOmics
#' @exportClass AgentSeurat
methods::setClass(
  "AgentSeurat",
  contains = "AgentOmics"
)


#' Construct an AgentSeurat from a Seurat object
#'
#' Convenience wrapper around [agentomicsCore::AgentOmics()] that stamps
#' the scAgentKit package version onto the object and returns an
#' instance of the [AgentSeurat-class] subclass.
#'
#' @param seurat A Seurat object or a named list of Seurat objects.
#' @param initial_script Optional character string recording how the
#'   input was loaded; prepended to the generated script trace.
#'
#' @return An AgentSeurat object (which inherits from AgentOmics).
#' @export
AgentSeurat <- function(seurat, initial_script = NULL) {
  data_type <- if (is.list(seurat) && !inherits(seurat, "Seurat")) {
    "seurat_list"
  } else {
    "seurat"
  }
  pkg_version <- tryCatch(
    as.character(utils::packageVersion("scAgentKit")),
    error = function(e) NA_character_
  )
  # Construct the subclass directly. AgentSeurat inherits every slot from
  # AgentOmics, so methods::new() with the AgentOmics slots is valid and
  # avoids any superclass->subclass coercion ambiguity.
  obj <- methods::new(
    "AgentSeurat",
    data       = seurat,
    data_type  = data_type,
    stage      = "initialized",
    version    = if (length(pkg_version) == 0 || is.na(pkg_version)) {
      NA_character_
    } else pkg_version,
    created_at = Sys.time(),
    updated_at = Sys.time()
  )
  if (!is.null(initial_script)) {
    obj@scripts <- c(obj@scripts, initial_script)
  }
  obj
}
