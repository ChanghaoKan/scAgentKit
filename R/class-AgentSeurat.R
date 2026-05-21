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
#' @slot token_usage List of per-step LLM token consumption summaries
#'   (added in v0.2.0). One entry per pipeline step that involved an LLM
#'   call. Each entry is a list with `input_tokens`, `output_tokens`,
#'   `cached_tokens`, `n_calls`, and a `by_model` data frame.
#' @slot version Character, the scAgentKit version that created this
#'   object. Used by [upgrade_checkpoint()] to handle backward
#'   compatibility when loading saved objects.
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
    token_usage = "list",
    version     = "character",
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
    token_usage = list(),
    version     = NA_character_,
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

  # Stamp the constructing scAgentKit version onto the object so future
  # upgrade_checkpoint() can decide how to migrate stored fields.
  pkg_version <- tryCatch(
    as.character(utils::packageVersion("scAgentKit")),
    error = function(e) NA_character_
  )

  obj <- methods::new(
    "AgentSeurat",
    data       = seurat,
    data_type  = data_type,
    stage      = "initialized",
    version    = pkg_version %||% NA_character_,
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
  ver <- if (length(object@version) == 0 || is.na(object@version)) {
    "<unknown>"
  } else object@version
  cat("  Version:    ", ver, "\n", sep = "")
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

  # Token usage one-liner if any LLM calls happened
  if (length(object@token_usage) > 0) {
    tot_in  <- sum(vapply(object@token_usage,
                          function(x) x$input_tokens  %||% 0L, integer(1)))
    tot_out <- sum(vapply(object@token_usage,
                          function(x) x$output_tokens %||% 0L, integer(1)))
    n_calls <- sum(vapply(object@token_usage,
                          function(x) x$n_calls %||% 0L, integer(1)))
    cat(sprintf("  LLM tokens: %d in + %d out across %d call(s)\n",
                tot_in, tot_out, n_calls))
  }

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


#' Return the per-step LLM token usage log
#'
#' Each pipeline step that issued LLM calls records its consumption here.
#' Use this for cost reporting and as a more granular alternative to the
#' global [token_usage_summary()].
#'
#' @param obj An AgentSeurat object.
#' @return A named list keyed by step name. Each entry is a list with
#'   `input_tokens`, `output_tokens`, `cached_tokens`, `n_calls`, and a
#'   `by_model` data frame.
#' @export
get_token_usage <- function(obj) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  obj@token_usage
}


#' Upgrade a saved AgentSeurat from an older scAgentKit version
#'
#' Saved checkpoints (qs/rds) from older scAgentKit releases may be missing
#' slots that newer versions expect. This function fills in defaults so
#' `obj` round-trips through the current S4 class without errors.
#'
#' Currently handles:
#' \itemize{
#'   \item pre-v0.2.0 objects without `@@token_usage` slot
#'   \item pre-v0.2.0 objects without `@@version` slot
#' }
#'
#' @param obj An AgentSeurat object loaded from a checkpoint.
#' @return The same object with any missing slots populated.
#' @export
upgrade_checkpoint <- function(obj) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  # methods::slotNames returns what the *current* class definition has;
  # if a slot exists in the class but not the loaded object, methods::slot
  # returns the prototype default — so we mostly need to check whether
  # the object actually carries data in the new slots and stamp the
  # version.
  changed <- character(0)
  if (length(methods::slot(obj, "token_usage", check = FALSE)) == 0 &&
      !is.list(methods::slot(obj, "token_usage", check = FALSE))) {
    methods::slot(obj, "token_usage") <- list()
    changed <- c(changed, "token_usage")
  }
  current_ver <- methods::slot(obj, "version", check = FALSE)
  if (length(current_ver) == 0 || is.na(current_ver) || !nzchar(current_ver)) {
    methods::slot(obj, "version") <-
      tryCatch(as.character(utils::packageVersion("scAgentKit")),
               error = function(e) "unknown")
    changed <- c(changed, "version")
  }
  if (length(changed) > 0) {
    message(sprintf(
      "[upgrade_checkpoint] populated missing slot(s): %s",
      paste(changed, collapse = ", ")
    ))
  }
  obj
}
