#!/usr/bin/env Rscript
# Local CLI only: paths and study facts never come from browser requests.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
request <- jsonlite::fromJSON(args[1], simplifyVector = FALSE)
suppressPackageStartupMessages(library(scAgentKit))
checkout <- normalizePath(request$checkout, mustWork = TRUE)
ns <- asNamespace("scAgentKit")
installed <- sort(grep("^(sc_run|\\.sc_run_)", ls(ns, all.names = TRUE), value = TRUE))
installed <- unique(c(installed, grep("^\\.sc_ui_", ls(ns, all.names = TRUE), value = TRUE),
  "sc_analyze", "sc_open", "sc_review", "sc_project_prepare", ".sc_project_layer",
  ".sc_project_identity", "sc_select_pcs", ".adjusted_rand_index", "sc_cycle_gene_set"))
definitions <- list()
for (file in sort(list.files(file.path(checkout, "R"), pattern = "[.]R$", full.names = TRUE))) {
  for (expr in parse(file)) if (is.call(expr) && identical(expr[[1]], as.name("<-")) &&
      is.symbol(expr[[2]]) && is.call(expr[[3]]) && identical(expr[[3]][[1]], as.name("function")))
    definitions[[as.character(expr[[2]])]] <- expr[[3]]
}
signature <- function(fn) list(formals = paste(deparse(formals(fn), width.cutoff = 500L), collapse = "\n"),
  body = paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n"))
for (name in installed) {
  expr <- definitions[[name]]
  if (is.null(expr)) stop("Installed package and source checkout differ. Install this checkout in the selected library first.")
  # Evaluate only a parsed function constructor, never its body or arbitrary
  # top-level checkout code; this compares the installed execution functions.
  source_fn <- eval(expr, envir = baseenv())
  if (!identical(signature(get(name, ns)), signature(source_fn)))
    stop("Installed package and source checkout differ. Install this checkout in the selected library first.")
}
source_names <- grep("^(sc_run|\\.sc_run_)", names(definitions), value = TRUE)
if (!setequal(source_names, grep("^(sc_run|\\.sc_run_)", installed, value = TRUE)))
  stop("Installed package and source checkout expose different workflow functions.")
input <- readRDS(request$input)
if (inherits(input, "Seurat") && (length(input@reductions) || "seurat_clusters" %in% colnames(input[[]])))
  message("Input contains saved reductions or clusters. They do not establish analysis quality. Selected entry: ", request$entry)
if (file.exists(request$project)) stop("Use a new project path; open saved projects with server.py --run-project instead.")
# Validate counts/layers and declared context before sc_run creates a directory.
# This reads the input only and uses the same scientific input validation.
invisible(get(".sc_run_input", ns)(request$input, context = request$context,
  start_stage = if (identical(request$entry, "processed")) "processed" else "qc",
  processed_reason = if (identical(request$entry, "processed")) request$processed_reason else NULL,
  cluster_column = request$cluster_column))
if (identical(request$entry, "processed")) {
  scAgentKit::sc_run(request$input, request$project, context = request$context,
    start_stage = "processed", processed_reason = request$processed_reason,
    cluster_column = request$cluster_column, provider = NULL, budget = 0)
} else scAgentKit::sc_analyze(request$input, request$project, context = request$context,
  provider = NULL, budget = 0)
view <- scAgentKit::sc_run_inspect(request$project)
jsonlite::write_json(list(project_id = view$project_id, status = view$status, stage = view$stage),
  args[2], auto_unbox = TRUE)
