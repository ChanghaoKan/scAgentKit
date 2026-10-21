#!/usr/bin/env Rscript
# Test-only source contract. The installed bridge is tested by R CMD check.
args <- commandArgs(TRUE)
stopifnot(length(args) >= 3L)
repo <- args[[1L]]; operation <- args[[2L]]; project <- args[[3L]]
scope <- new.env(parent = baseenv())
sys.source(file.path(repo, "R", "run-state.R"), envir = scope)
sys.source(file.path(repo, "R", "project-format.R"), envir = scope)
stopifnot(!"scAgentKit" %in% loadedNamespaces())
if (identical(operation, "state")) {
  stopifnot(length(args) == 6L)
  version <- if (identical(args[[4L]], "missing")) NULL else as.integer(args[[4L]])
  state <- list(project_format_version = version, config = list(), history = list(),
                revision = 0L, files = list())
  if (nzchar(args[[5L]])) state$config$subcluster_origin <- list(parent_project = args[[5L]])
  hash <- scope$.sc_run_hash(state)
  if (identical(args[[6L]], "bad")) hash <- strrep("0", 64L)
  saveRDS(list(schema = "scagentkit.run-state.v1", hash = hash, state = state),
          file.path(project, "state.rds"), version = 2L)
} else if (identical(operation, "check")) {
  stopifnot(length(args) == 3L)
  valid <- tryCatch({ scope$.sc_project_format_check(project); TRUE }, error = function(e) FALSE)
  stopifnot(!"scAgentKit" %in% loadedNamespaces())
  if (isTRUE(valid)) cat("scagentkit.project-format.ok\n")
  quit(status = if (isTRUE(valid)) 0L else 1L)
} else stop("Unsupported test helper operation")
