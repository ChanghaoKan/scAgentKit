#!/usr/bin/env Rscript
# Fixed local IPC entry. JSON values are data; no eval/parse/source/provider call.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L || !args[[1L]] %in% c("inspect", "decision")) quit(status = 2L)
operation <- args[[1L]]; project_dir <- args[[2L]]
request_file <- args[[3L]]; response_file <- args[[4L]]
suppressPackageStartupMessages(library(scAgentKit))
answer <- tryCatch({
  if (operation == "inspect") {
    result <- scAgentKit::sc_run_inspect(project_dir)
  } else {
    request <- jsonlite::fromJSON(request_file, simplifyVector = FALSE)
    if (!is.list(request)) stop("QC request must be an object.")
    if (!is.null(request$gene_panels)) request$gene_panels <- lapply(request$gene_panels, function(panel) {
      if (is.list(panel) && is.null(names(panel))) {
        if (!all(vapply(panel, function(gene) is.character(gene) && length(gene) == 1L && !is.na(gene), logical(1))))
          stop("Every gene panel must be an array of literal gene names.")
        return(vapply(panel, identity, character(1)))
      }
      panel
    })
    result <- do.call(scAgentKit::sc_run_qc_review, c(list(project_dir = project_dir), request))
  }
  list(ok = TRUE, result = result, error = NULL)
}, error = function(problem) list(ok = FALSE, result = NULL, error = conditionMessage(problem)))
writeLines(as.character(jsonlite::toJSON(answer, auto_unbox = TRUE, null = "null", na = "null",
                                        digits = NA, force = TRUE)), response_file, useBytes = TRUE)
quit(status = if (isTRUE(answer$ok)) 0L else 1L)
