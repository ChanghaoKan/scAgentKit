#' Start or reopen a reviewed analysis in the local browser
#' @param input Local RDS, 10x MEX directory, or sample table (data.frame/CSV/TSV).
#' @param sample_id Explicit ID for one MEX directory; table inputs declare it per row.
#' @param matrix_kind Explicit raw/filtered declaration for one MEX directory.
#' @param cell_metadata Optional keyed sample_id/barcode cell metadata data.frame/CSV/TSV.
#' @param scientific_review Explicit optional rebuilding/extended expression diagnostics, off by default.
#'   New raw strategy projects retain applicable declared-human classic panel evidence.
#' @param feature_key Original names with recorded technical keys (default), or compatible IDs.
#' @param project_dir New project directory, or the same saved project to reopen.
#' @param context Declared species, tissue, research_goal, optional notes, columns and design.
#'   Required on creation; omitted when reopening with saved context.
#' @param checkout Optional matching developer checkout. Installed resources are the default.
#'   Set explicitly or via options(scAgentKit.checkout=...) only for development.
#' @param python Existing Python 3.9+ executable; detected by default.
#' @param browse Open the local URL in the browser.
#' @param provider Explicit provider name/list; NULL detects exactly one DeepSeek/Grok key, otherwise manual.
#' @param budget Explicit project USD cap; zero until a real-provider default is calibrated.
#' @param review Creation-time transfer policy; optional explicit project scope skips repeated
#'   transfer approvals within its provider/categories/budget. Payloads remain inspectable.
#' @param model_suggestions Operator mode: auto, off, configured, or simulate.
#'   Uses the saved provider; creation-time transfer scope or exact payload approval is required.
#' @param reuse_processed Explicitly reuse processed layers/clusters. Default FALSE.
#' @param processed_reason Required reason for processed reuse.
#' @param cluster_column Saved cluster column for processed reuse.
#' @return Invisibly, local service URL, PID, project ID and reuse status.
#' @export
sc_start <- function(input, project_dir, context = NULL, checkout = NULL,
  python = NULL, browse = interactive(), reuse_processed = FALSE,
  processed_reason = NULL, cluster_column = "seurat_clusters",
  model_suggestions = c("auto", "off", "configured", "simulate"),
  sample_id = NULL, matrix_kind = NULL, cell_metadata = NULL,
  feature_key = c("name", "id"), scientific_review = NULL,
  provider = NULL, budget = 0, review = list(allow_external = FALSE)) {
  if(is.list(scientific_review) && is.character(scientific_review$panels) && length(scientific_review$panels)==1L &&
      !is.null(context$species) && !identical(.sc_run_species(context$species,allow_missing=TRUE),"human"))
    stop("Built-in panels require human species; supply explicit genes for another species.",call.=FALSE)
  scientific_review <- .sc_run_science_options(scientific_review)
  model_suggestions <- match.arg(model_suggestions)
  .sc_project_string(project_dir, "project_dir")
  existing <- file.exists(file.path(path.expand(project_dir), "state.rds"))
  if (existing && is.null(context)) context <- .sc_run_load(.sc_run_root(project_dir))$config$context
  imported <- .sc_ui_tenx_input(input, context, sample_id, matrix_kind, cell_metadata, match.arg(feature_key))
  context <- imported$context
  if (imported$imported) {
    if (reuse_processed) stop("10x MEX is raw counts; processed reuse requires an explicitly prepared Seurat RDS.",call.=FALSE)
    input <- tempfile("scagentkit-tenx-",fileext=".rds")
    on.exit(unlink(input),add=TRUE)
    saveRDS(imported$input,input,version=2L)
  }
  .sc_project_string(input, "input RDS path")
  input <- normalizePath(path.expand(input), mustWork = TRUE)
  if (dir.exists(input)) stop("input must be an RDS file.", call. = FALSE)
  for (flag in c("browse", "reuse_processed")) if (!is.logical(get(flag)) ||
      length(get(flag)) != 1L || is.na(get(flag))) stop(flag, " must be TRUE or FALSE.", call. = FALSE)
  existing <- file.exists(file.path(path.expand(project_dir), "state.rds"))
  if (!existing && !reuse_processed && !missing(cluster_column) && !identical(cluster_column,"sc_strategy_clusters"))
    stop("cluster_column selects processed input membership; raw analysis creates sc_strategy_clusters.",call.=FALSE)
  preferences <- file.path(path.expand(project_dir), ".workbench-review-launcher", "preferences.json")
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
    if (!is.null(scientific_review) && !identical(scientific_review,state$config$scientific_review))
      stop("Reopening cannot replace saved scientific diagnostics; use the original configuration or a new project.",call.=FALSE)
    reuse_processed <- identical(state$config$start_stage, "processed")
    processed_reason <- state$config$processed_reason
    cluster_column <- state$config$cluster_column
  }
  setup <- .sc_start_provider_setup(provider, if (!missing(budget)) budget,
    if (!missing(review)) review, if (existing) state$config)
  if (model_suggestions == "auto") model_suggestions <- if (identical(setup$provider$name, "manual")) "off" else
    if (identical(setup$provider$name, "mock")) "simulate" else "configured"
  if (model_suggestions == "simulate" && !identical(setup$provider$name, "mock"))
    stop("Simulation requires provider='mock'; choose a new project for another provider.", call. = FALSE)
  if (!is.list(context) || anyDuplicated(names(context)) || !all(c("species", "tissue", "research_goal") %in% names(context)) ||
      length(setdiff(names(context), c("species", "tissue", "research_goal", "notes", "columns", "design"))))
    stop("Supply named context with species, tissue, research_goal and optional notes, columns, design.", call. = FALSE)
  for (field in c("species", "tissue", "research_goal")) .sc_project_string(context[[field]], field)
  if (!is.null(context$notes) && (!is.character(context$notes) || length(context$notes)!=1L || is.na(context$notes)))
    stop("notes must be one text value.",call.=FALSE)
  if (is.null(checkout)) checkout <- getOption("scAgentKit.checkout")
  if (!is.null(checkout)) {
    checkout <- normalizePath(path.expand(checkout),mustWork=TRUE)
    runtime <- file.path(checkout,"inst","workbench")
    if (!dir.exists(file.path(checkout,"R"))) stop("Developer checkout must contain R sources.",call.=FALSE)
  } else runtime <- system.file("workbench",package="scAgentKit")
  if (!nzchar(runtime) || !file.exists(file.path(runtime,"start_analysis.py")))
    stop("Installed browser runtime missing; reinstall scAgentKit.",call.=FALSE)
  runtime <- .sc_start_runtime_check(runtime,checkout)
  launcher <- file.path(runtime,"start_analysis.py")
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
    if (!is.null(checkout)) c("--source-checkout",shQuote(checkout)),
    "--cluster-column", shQuote(if (!existing && !reuse_processed && missing(cluster_column)) "sc_strategy_clusters" else cluster_column),
    if (!browse) "--no-browser", if (existing) "--reopen",
    if (imported$imported) "--tenx-import",
    if (model_suggestions == "configured") "--model-suggestions",
    if (model_suggestions == "simulate") "--model-mock")
  if (reuse_processed) {
    .sc_project_string(processed_reason, "processed_reason")
    args <- c(args, "--reuse-processed", "--processed-reason", shQuote(processed_reason))
  }
  if (!is.null(scientific_review)) {
    if (reuse_processed) stop("Scientific diagnostics require a new raw entry.",call.=FALSE)
    science_file <- tempfile("scagentkit-science-",fileext=".json")
    on.exit(unlink(science_file),add=TRUE)
    jsonlite::write_json(scientific_review,science_file,auto_unbox=TRUE,null="null")
    Sys.chmod(science_file,"0600")
    args <- c(args,"--scientific-review-file",shQuote(science_file))
  }
  if (!existing) {
    setup_file <- tempfile("scagentkit-provider-", fileext = ".json")
    on.exit(unlink(setup_file), add = TRUE)
    jsonlite::write_json(setup, setup_file, auto_unbox = TRUE, null = "null")
    Sys.chmod(setup_file, "0600")
    args <- c(args, "--model-config-file", shQuote(setup_file))
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
  jsonlite::write_json(list(checkout=checkout,runtime=runtime),preferences,auto_unbox=TRUE,null="null")
  # The existing read-only opener accepts a root containing workbench/. Point it
  # at the installed package without changing its saved execution fingerprint.
  readonly <- file.path(path.expand(project_dir),".workbench-launcher","preferences.json")
  if (!file.exists(readonly)) {
    dir.create(dirname(readonly),recursive=TRUE,showWarnings=FALSE,mode="0700")
    jsonlite::write_json(list(checkout=dirname(runtime)),readonly,auto_unbox=TRUE)
  }
  cat(result$url,"\n")
  invisible(result)
}
