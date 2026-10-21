#!/usr/bin/env Rscript
# Read-only admission: no coordinator operation, lock, analysis or model call.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) quit(status = 2L)
valid <- tryCatch({
  suppressPackageStartupMessages(loadNamespace("scAgentKit"))
  getFromNamespace(".sc_project_format_check", "scAgentKit")(args[[1L]])
  TRUE
}, error = function(problem) FALSE)
if (isTRUE(valid)) cat("scagentkit.project-format.ok\n")
quit(status = if (isTRUE(valid)) 0L else 1L)
