#!/usr/bin/env Rscript
# One fixed local-only R operation. No provider/code callback from HTTP.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) quit(status = 2L)
project_dir <- args[[1L]]; request_file <- args[[2L]]; response_file <- args[[3L]]
suppressPackageStartupMessages(library(scAgentKit))
answer <- tryCatch({
  request <- jsonlite::fromJSON(request_file, simplifyVector = FALSE)
  fields <- c("project_id", "input_hash", "expected_revision", "request_id", "retry")
  if (!is.list(request) || is.null(names(request)) || anyDuplicated(names(request)) ||
      !setequal(names(request), fields)) stop("Unsupported local continuation request.")
  if (!"sc_run_continue" %in% getNamespaceExports("scAgentKit")) stop("Install the local continuation package.")
  result <- scAgentKit::sc_run_continue(project_dir = project_dir,
    project_id = request$project_id, input_hash = request$input_hash,
    expected_revision = request$expected_revision, retry = request$retry)
  # Worker needs only the verified stop point, never a raw object/payload/log.
  summary <- result[c("schema", "project_id", "input_hash", "status", "stage", "revision")]
  list(ok = TRUE, result = summary, error = NULL)
}, error = function(problem) list(ok = FALSE, result = NULL,
  error = list(code = "local_continue_rejected",
    message = "The local coordinator rejected continuation. Inspect the saved run in R.")))
temporary <- tempfile(".continue-response-", tmpdir = dirname(response_file))
writeLines(as.character(jsonlite::toJSON(answer, auto_unbox = TRUE, null = "null", na = "null",
  digits = NA, force = TRUE)), temporary, useBytes = TRUE)
if (!file.rename(temporary, response_file)) quit(status = 2L)
quit(status = if (isTRUE(answer$ok)) 0L else 1L)
