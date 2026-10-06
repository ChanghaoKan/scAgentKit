#!/usr/bin/env Rscript
# Fixed local IPC. Browser fields are typed JSON data, never executable R.
args <- commandArgs(trailingOnly = TRUE)
suggestion_actions <- c("preview", "approve", "request", "adopt", "discard")
if (length(args) != 4L || !args[[1L]] %in% c("inspect", "decision", paste0("suggestion_", suggestion_actions))) quit(status = 2L)
operation <- args[[1L]]; project_dir <- args[[2L]]
request_file <- args[[3L]]; response_file <- args[[4L]]
suppressPackageStartupMessages(library(scAgentKit))
answer <- tryCatch({
  if (operation == "inspect") {
    result <- scAgentKit::sc_run_inspect(project_dir)
  } else if (startsWith(operation, "suggestion_")) {
    request <- jsonlite::fromJSON(request_file, simplifyVector = FALSE)
    if (!is.list(request)) stop("Suggestion request must be an object.")
    result <- do.call(scAgentKit::sc_run_suggest, c(list(project_dir = project_dir,
      action = sub("^suggestion_", "", operation)), request))
    # Adoption returns the full scientific inspector in headless R. Keep this
    # IPC narrow: the browser refreshes scientific review with its own endpoint.
    # Large marker evidence must never turn a saved adoption into an HTTP error.
    if (identical(result$schema, "scagentkit.run.v1")) {
      suggestion <- result$suggestion
      if (!is.list(suggestion) || !identical(suggestion$schema, "scagentkit.run-suggestion.v1") ||
          !identical(suggestion$project_id, result$project_id) ||
          !identical(suggestion$input_hash, result$input_hash) ||
          !identical(suggestion$revision, result$revision))
        stop("Scientific inspector and suggestion projection have different bindings.")
      result <- suggestion
    }
  } else {
    request <- jsonlite::fromJSON(request_file, simplifyVector = FALSE)
    if (!is.list(request)) stop("Run review request must be an object.")
    if (!is.null(request$gene_panels)) request$gene_panels <- lapply(request$gene_panels, function(panel) {
      if (is.list(panel) && is.null(names(panel))) {
        if (!all(vapply(panel, function(gene) is.character(gene) && length(gene) == 1L && !is.na(gene), logical(1))))
          stop("Every gene panel must be an array of literal gene names.")
        return(vapply(panel, identity, character(1)))
      }
      panel
    })
    result <- do.call(scAgentKit::sc_run_review, c(list(project_dir = project_dir), request))
  }
  list(ok = TRUE, result = result, error = NULL)
}, error = function(problem) list(ok = FALSE, result = NULL,
  error = if (startsWith(operation, "suggestion_"))
    "Suggestion coordinator rejected this action; inspect the saved state and exact preview binding."
  else conditionMessage(problem)))
writeLines(as.character(jsonlite::toJSON(answer, auto_unbox = TRUE, null = "null", na = "null",
                                        digits = NA, force = TRUE)), response_file, useBytes = TRUE)
quit(status = if (isTRUE(answer$ok)) 0L else 1L)
