#' Start or reopen a reviewed analysis in the local browser
#' @param input Local RDS path containing counts or a Seurat object.
#' @param project_dir New project directory, or the same saved project to reopen.
#' @param context Declared species, tissue, research_goal, optional notes, columns and design.
#'   Required on creation; omitted when reopening with saved context.
#' @param checkout Matching source checkout containing workbench/start_analysis.py.
#'   Supply once or set options(scAgentKit.checkout=...). Remembered per project.
#' @param python Existing Python 3.9+ executable; detected by default.
#' @param browse Open the local URL in the browser.
#' @param reuse_processed Explicitly reuse processed layers/clusters. Default FALSE.
#' @param processed_reason Required reason for processed reuse.
#' @param cluster_column Saved cluster column for processed reuse.
#' @return Invisibly, local service URL, PID, project ID and reuse status.
#' @export
sc_start <- function(input, project_dir, context = NULL, checkout = NULL,
  python = NULL, browse = interactive(), reuse_processed = FALSE,
  processed_reason = NULL, cluster_column = "seurat_clusters") {
  .sc_project_string(input, "input RDS path")
  .sc_project_string(project_dir, "project_dir")
  input <- normalizePath(path.expand(input), mustWork = TRUE)
  if (dir.exists(input)) stop("input must be an RDS file.", call. = FALSE)
  for (flag in c("browse", "reuse_processed")) if (!is.logical(get(flag)) ||
      length(get(flag)) != 1L || is.na(get(flag))) stop(flag, " must be TRUE or FALSE.", call. = FALSE)
  existing <- file.exists(file.path(path.expand(project_dir), "state.rds"))
  if (!existing && !reuse_processed && !missing(cluster_column) && !identical(cluster_column,"sc_strategy_clusters"))
    stop("cluster_column selects processed input membership; raw analysis creates sc_strategy_clusters.",call.=FALSE)
  saved <- list()
  preferences <- file.path(path.expand(project_dir), ".workbench-review-launcher", "preferences.json")
  if (file.exists(preferences)) saved <- jsonlite::fromJSON(preferences)
  if (existing) {
    state <- .sc_run_load(.sc_run_root(project_dir))
    if (!is.null(context) && (!is.list(context) || is.null(names(context)) || anyDuplicated(names(context)) ||
        any(!vapply(names(context),function(name)identical(context[[name]],state$config$context[[name]]),logical(1)))))
      stop("Reopening uses saved context; omit context rather than replacing study facts.", call. = FALSE)
    if ((!missing(reuse_processed) && !identical(reuse_processed, identical(state$config$start_stage,"processed"))) ||
        (!missing(cluster_column) && !identical(cluster_column,state$config$cluster_column)) ||
        (!is.null(processed_reason) && !identical(processed_reason,state$config$processed_reason)))
      stop("Reopening cannot replace saved entry, reuse reason or cluster column.", call. = FALSE)
    context <- state$config$context
    reuse_processed <- identical(state$config$start_stage, "processed")
    processed_reason <- state$config$processed_reason
    cluster_column <- state$config$cluster_column
  }
  if (!is.list(context) || anyDuplicated(names(context)) || !all(c("species", "tissue", "research_goal") %in% names(context)) ||
      length(setdiff(names(context), c("species", "tissue", "research_goal", "notes", "columns", "design"))))
    stop("Supply named context with species, tissue, research_goal and optional notes, columns, design.", call. = FALSE)
  for (field in c("species", "tissue", "research_goal")) .sc_project_string(context[[field]], field)
  if (!is.null(context$notes) && (!is.character(context$notes) || length(context$notes)!=1L || is.na(context$notes)))
    stop("notes must be one text value.",call.=FALSE)
  if (is.null(checkout)) checkout <- getOption("scAgentKit.checkout", saved$checkout)
  if (is.null(checkout)) stop("First use needs a matching source checkout: set checkout='/path/to/scAgentKit' or options(scAgentKit.checkout=...). Python and browser assets are not included in the installed R package.", call. = FALSE)
  checkout <- normalizePath(path.expand(checkout), mustWork = TRUE)
  launcher <- file.path(checkout, "workbench", "start_analysis.py")
  if (!file.exists(launcher)) stop("checkout must contain workbench/start_analysis.py.", call. = FALSE)
  if (is.null(python)) python <- unname(Sys.which("python3"))
  if (length(python) != 1L || is.na(python) || !nzchar(python)) stop("Install/configure Python 3.9+ before starting the workbench.", call. = FALSE)
  context_file <- tempfile("scagentkit-context-",fileext=".json")
  on.exit(unlink(context_file),add=TRUE)
  if (identical(context$notes,"")) context$notes <- NULL
  jsonlite::write_json(context,context_file,auto_unbox=TRUE,null="null")
  Sys.chmod(context_file,"0600")
  args <- c(shQuote(launcher), shQuote(input), "--project", shQuote(path.expand(project_dir)),
    "--species", shQuote(context$species), "--tissue", shQuote(context$tissue),
    "--research-goal", shQuote(context$research_goal), "--notes", shQuote(if (is.null(context$notes)) "" else context$notes),
    "--rscript", shQuote(file.path(R.home("bin"), "Rscript")),
    "--r-library", shQuote(paste(.libPaths(), collapse=.Platform$path.sep)), "--background",
    "--context-file",shQuote(context_file),
    "--cluster-column", shQuote(if (!existing && !reuse_processed && missing(cluster_column)) "sc_strategy_clusters" else cluster_column),
    if (!browse) "--no-browser", if (existing) "--reopen")
  if (reuse_processed) {
    .sc_project_string(processed_reason, "processed_reason")
    args <- c(args, "--reuse-processed", "--processed-reason", shQuote(processed_reason))
  }
  error_file <- tempfile("scagentkit-start-error-")
  on.exit(unlink(error_file),add=TRUE)
  response <- suppressWarnings(system2(python, args, stdout=TRUE, stderr=error_file))
  if (!is.null(attr(response,"status")) && attr(response,"status") != 0L) {
    lines <- if (file.exists(error_file)) readLines(error_file,warn=FALSE) else character()
    problem <- head(grep("^Error|^RuntimeError|^.*: error:",lines,value=TRUE),2L)
    stop("Local startup failed. ",substr(paste(problem,collapse=" "),1,1200),
      " Verify matching checkout/package, Python and the selected R library; existing project authority was not replaced.",call.=FALSE)
  }
  result <- jsonlite::fromJSON(paste(response,collapse="\n"))
  dir.create(dirname(preferences),recursive=TRUE,showWarnings=FALSE,mode="0700")
  jsonlite::write_json(list(checkout=checkout),preferences,auto_unbox=TRUE)
  cat(result$url,"\n")
  invisible(result)
}
