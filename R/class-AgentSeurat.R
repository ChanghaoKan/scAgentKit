#' AgentSeurat: S4 container for agent-driven scRNA-seq analysis
#'
#' An S4 class that wraps a Seurat object (or list of Seurat objects during
#' per-sample processing) together with decision logs, reproducible script
#' snippets, figure metadata, and stage tracking. Every tool function in
#' scAgentKit takes and returns an AgentSeurat, accumulating state as the
#' pipeline progresses.
#'
#' @slot data The core data payload. Either a single Seurat object or a
#'   named list of Seurat objects (during per-sample processing phases).
#' @slot data_type Character, either "seurat" or "seurat_list", indicating
#'   the structure of @@data.
#' @slot stage Character tag for the current pipeline stage
#'   (e.g. "initialized", "qc_metrics_added", "doublet_removed",
#'   "normalized", "pca_done", "harmony_integrated", "clustered",
#'   "annotated").
#' @slot decisions List of decision records. Each element is a list with
#'   fields: step, function_name, timestamp, params, rationale,
#'   success.
#' @slot scripts Character vector of R script snippets; concatenating these
#'   reproduces the analysis from scratch.
#' @slot figures Data frame with columns step, path, description,
#'   recording figures generated during the pipeline.
#' @slot params Flat list of the most recently applied parameters (useful
#'   for quick inspection; full history lives in @@decisions).
#' @slot created_at POSIXct timestamp of object creation.
#' @slot updated_at POSIXct timestamp of the last modification.
#'
#' @name AgentSeurat-class
#' @rdname AgentSeurat-class
#' @exportClass AgentSeurat
methods::setClass(
  "AgentSeurat",
  slots = c(
    data        = "ANY",
    data_type   = "character",
    stage       = "character",
    decisions   = "list",
    scripts     = "character",
    figures     = "data.frame",
    params      = "list",
    created_at  = "POSIXct",
    updated_at  = "POSIXct"
  ),
  prototype = list(
    data        = NULL,
    data_type   = "seurat",
    stage       = "initialized",
    decisions   = list(),
    scripts     = character(0),
    figures     = data.frame(
      step        = character(0),
      path        = character(0),
      description = character(0),
      stringsAsFactors = FALSE
    ),
    params      = list(),
    created_at  = Sys.time(),
    updated_at  = Sys.time()
  )
)

#' Construct an AgentSeurat from a Seurat object
#'
#' Entry point of the pipeline. Wraps a user-supplied Seurat object (or a
#' list of Seurat objects) into an AgentSeurat container.
#'
#' @param seurat A Seurat object or a named list of Seurat objects.
#' @param initial_script Optional character string recording how the input
#'   was loaded (e.g. the readRDS call); will be prepended to the
#'   reproducible script.
#'
#' @return An AgentSeurat object at stage "initialized".
#' @export
#'
#' @examples
#' \dontrun{
#'   seu <- readRDS("my_data.rds")
#'   obj <- AgentSeurat(seu, initial_script = 'seu <- readRDS("my_data.rds")')
#' }
AgentSeurat <- function(seurat, initial_script = NULL) {
  data_type <- if (is.list(seurat) && !inherits(seurat, "Seurat")) {
    "seurat_list"
  } else {
    "seurat"
  }

  obj <- methods::new(
    "AgentSeurat",
    data       = seurat,
    data_type  = data_type,
    stage      = "initialized",
    created_at = Sys.time(),
    updated_at = Sys.time()
  )

  if (!is.null(initial_script)) {
    obj@scripts <- c(obj@scripts, initial_script)
  }

  obj
}

#' @rdname AgentSeurat-class
#' @param object An AgentSeurat object.
#' @export
methods::setMethod("show", "AgentSeurat", function(object) {
  cat("<AgentSeurat>\n")
  cat("  Stage:      ", object@stage, "\n", sep = "")
  cat("  Data type:  ", object@data_type, "\n", sep = "")

  if (object@data_type == "seurat") {
    n_cells <- tryCatch(ncol(object@data), error = function(e) NA)
    n_genes <- tryCatch(nrow(object@data), error = function(e) NA)
    cat("  Cells:      ", n_cells, "\n", sep = "")
    cat("  Genes:      ", n_genes, "\n", sep = "")
  } else {
    n_samples <- length(object@data)
    cell_counts <- tryCatch(
      vapply(object@data, function(s) as.integer(ncol(s)), integer(1)),
      error = function(e) NA
    )
    cat("  Samples:    ", n_samples, "\n", sep = "")
    if (!any(is.na(cell_counts))) {
      cat("  Cells:      ", sum(cell_counts),
          " (total across ", n_samples, " samples)\n", sep = "")
    }
  }

  cat("  Decisions:  ", length(object@decisions), " steps recorded\n", sep = "")
  cat("  Figures:    ", nrow(object@figures), "\n", sep = "")
  cat("  Updated:    ", format(object@updated_at, "%Y-%m-%d %H:%M:%S"),
      "\n", sep = "")
  invisible(NULL)
})

# ---- Getters ----------------------------------------------------------------

#' Extract the underlying Seurat object (or list)
#' @param obj An AgentSeurat object.
#' @return A Seurat object or a list of Seurat objects.
#' @export
get_seurat <- function(obj) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  obj@data
}

#' Return the accumulated decision log
#' @param obj An AgentSeurat object.
#' @return A list of decision records.
#' @export
get_decisions <- function(obj) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  obj@decisions
}

#' Return the accumulated reproducible R script
#'
#' Concatenates all recorded script snippets, separated by blank lines,
#' yielding a self-contained R script that reproduces the analysis.
#'
#' @param obj An AgentSeurat object.
#' @return Character string containing the full reproducible script.
#' @export
get_script <- function(obj) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  paste(obj@scripts, collapse = "\n\n")
}

#' Return the figure registry
#' @param obj An AgentSeurat object.
#' @return Data frame with columns step, path, description.
#' @export
get_figures <- function(obj) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  obj@figures
}
