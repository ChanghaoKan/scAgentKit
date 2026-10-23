#' Start or reopen a reviewed analysis in the local browser
#' @param input Local RDS, MEX directory, or sample table; NULL reopens saved checkpoints.
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
#' @param react Auto (default), all, off, or a validated ReAct policy list.
#' @param subcluster_workspace Separate existing directory for explicit child analyses; NULL disables it.
#' @param reference_tissue Explicit exact ACT scope, separate from the study tissue; NULL uses study tissue.
#' @param model_timeout Whole suggestion-worker seconds (1–86400); NULL derives a bound from saved policy.
#' @param biological_diagnostics Diagnostic-only QC/batch evidence for raw input; TRUE by default.
#' @param review Creation-time transfer policy; optional explicit project scope skips repeated
#'   transfer approvals within its provider and categories. Payloads remain inspectable.
#' @param model_suggestions Operator mode: auto, off, configured, or simulate.
#'   Uses the saved provider; creation-time transfer scope or exact payload approval is required.
#' @param reuse_processed Explicitly reuse processed layers/clusters. Default FALSE.
#' @param processed_reason Required reason for processed reuse.
#' @param cluster_column Saved cluster column for processed reuse.
#' @return Invisibly, local service URL, PID, project ID and reuse status.
#' @export
sc_start <- function(input = NULL, project_dir, context = NULL, checkout = NULL,
  python = NULL, browse = interactive(), reuse_processed = FALSE,
  processed_reason = NULL, cluster_column = "seurat_clusters",
  model_suggestions = c("auto", "off", "configured", "simulate"),
  sample_id = NULL, matrix_kind = NULL, cell_metadata = NULL,
  feature_key = c("name", "id"), scientific_review = NULL,
  provider = NULL, review = list(allow_external = FALSE),
  doublet = c("auto", "off", "flag", "remove"),
  react = c("auto", "all", "off"), biological_diagnostics = TRUE,
  model_timeout = NULL, subcluster_workspace = NULL, reference_tissue = NULL) {
  .sc_project_format_entry(project_dir, allow_new = TRUE)
  react_supplied <- !missing(react)
  biology_supplied <- !missing(biological_diagnostics)
  react <- .sc_run_turn_policy(if (is.list(react)) react else list(mode = match.arg(react)))
  if (!is.null(model_timeout)) {
    model_timeout <- .sc_run_provider_number(model_timeout, "model_timeout", 1, 86400)
    if (model_timeout != floor(model_timeout)) stop("model_timeout must be whole seconds.", call. = FALSE)
  }
  biology <- .sc_run_biology_options(biological_diagnostics)
  if(is.list(scientific_review) && is.character(scientific_review$panels) && length(scientific_review$panels)==1L &&
      !is.null(context$species) && !identical(.sc_run_species(context$species,allow_missing=TRUE),"human"))
    stop("Built-in panels require human species; supply explicit genes for another species.",call.=FALSE)
  scientific_review <- .sc_run_science_options(scientific_review)
  model_suggestions <- match.arg(model_suggestions)
  doublet_supplied <- !missing(doublet)
  doublet <- match.arg(doublet)
  .sc_project_string(project_dir, "project_dir")
  existing <- file.exists(file.path(path.expand(project_dir), "state.rds"))
  project_only <- is.null(input)
  if (project_only && !existing) stop("Supply input for a new project, or project_dir for an existing saved project.", call. = FALSE)
  if (project_only && (!is.null(sample_id) || !is.null(matrix_kind) || !is.null(cell_metadata) || !missing(feature_key)))
    stop("Project-only reopening uses protected input checkpoints; omit import options.", call. = FALSE)
  if (existing && is.null(context)) context <- .sc_run_load(.sc_run_root(project_dir))$config$context
  imported <- list(imported = FALSE)
  if (!project_only) {
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
    if (dir.exists(input)) stop("input must be an RDS file or an explicitly declared MEX directory.", call. = FALSE)
  }
  for (flag in c("browse", "reuse_processed")) if (!is.logical(get(flag)) ||
      length(get(flag)) != 1L || is.na(get(flag))) stop(flag, " must be TRUE or FALSE.", call. = FALSE)
  existing <- file.exists(file.path(path.expand(project_dir), "state.rds"))
  if (!existing && reuse_processed) {
    if (doublet_supplied && doublet != "off") stop("Processed reuse does not run new doublet diagnostics; use doublet='off' or start a raw project.", call. = FALSE)
    doublet <- "off"
    if (biology_supplied && !is.null(biology)) stop("Biological diagnostics require raw input; use biological_diagnostics=FALSE for processed reuse.", call. = FALSE)
    biology <- NULL
  }
  if (!existing && !reuse_processed && !missing(cluster_column) && !identical(cluster_column,"sc_strategy_clusters"))
    stop("cluster_column selects processed input membership; raw analysis creates sc_strategy_clusters.",call.=FALSE)
  preferences <- file.path(path.expand(project_dir), ".workbench-review-launcher", "preferences.json")
  if (existing) {
    state <- .sc_run_load(.sc_run_root(project_dir))
    if (!identical(state$implementation_hash, .sc_run_implementation()))
      stop("Reopen this project with its original matching software environment; no project upgrade is performed.", call. = FALSE)
    if (!is.null(reference_tissue)) stop("Reopening uses saved reference scope; omit reference_tissue. Use sc_run_set_reference for an explicit evidence revision before annotation application.", call. = FALSE)
    if (!is.null(context) && (!is.list(context) || is.null(names(context)) || anyDuplicated(names(context)) ||
        any(!vapply(names(context),function(name)identical(context[[name]],state$config$context[[name]]),logical(1)))))
      stop("Reopening uses saved context; omit context rather than replacing study facts.", call. = FALSE)
    if ((!missing(reuse_processed) && !identical(reuse_processed, identical(state$config$start_stage,"processed"))) ||
        (!missing(cluster_column) && !identical(cluster_column,state$config$cluster_column)) ||
        (!is.null(processed_reason) && !identical(processed_reason,state$config$processed_reason)))
      stop("Reopening cannot replace saved entry, reuse reason or cluster column. Omit these options to use the saved choices, or create a new project.", call. = FALSE)
    if (react_supplied && !identical(react, state$config$react)) stop("Reopening uses saved ReAct settings; omit react or create a new project.", call. = FALSE)
    if (biology_supplied && !identical(biology, state$config$biological_diagnostics)) stop("Reopening uses saved biological diagnostics; omit this option or create a new project.", call. = FALSE)
    react <- state$config$react; biology <- state$config$biological_diagnostics
    context <- state$config$context
    if (doublet_supplied && !identical(doublet, state$config$input_policy$doublet_mode))
      stop("Reopening uses the saved doublet mode; omit doublet or create a new project.", call. = FALSE)
    if (!is.null(scientific_review) && !identical(scientific_review,state$config$scientific_review))
      stop("Reopening cannot replace saved scientific diagnostics; use the original configuration or a new project.",call.=FALSE)
    reuse_processed <- identical(state$config$start_stage, "processed")
    processed_reason <- state$config$processed_reason
    cluster_column <- state$config$cluster_column
  }
  setup <- .sc_start_provider_setup(provider,
    review = if (!missing(review)) review, saved = if (existing) state$config, react = react)
  if (model_suggestions == "auto") model_suggestions <- if (identical(setup$provider$name, "manual")) "off" else
    if (identical(setup$provider$name, "mock")) "simulate" else "configured"
  if (is.null(model_timeout)) {
    call_timeout <- setup$provider$generation$timeout_secs
    if (is.null(call_timeout)) call_timeout <- 180
    model_timeout <- as.integer(min(86400, ceiling(call_timeout + 120 +
      2 * react$tool_timeout_seconds + if (react$mode == "off") 0 else
        react$max_steps * react$cluster_timeout_seconds)))
  }
  message("Effective ReAct limits: ", react$max_steps_per_cluster, " turns/cluster; ",
    react$max_steps, " turns/session; ", react$cluster_timeout_seconds,
    " seconds/cluster; ", react$tool_timeout_seconds, " seconds/tool; ",
    react$max_payload_bytes, " conversation bytes. Whole suggestion worker: ",
    model_timeout, " seconds. One-shot requests share this byte setting; scan uses available request space. Model token capacity is separate.")
  if (model_suggestions == "simulate" && !identical(setup$provider$name, "mock"))
    stop("Simulation requires provider='mock'; choose a new project for another provider.", call. = FALSE)
  if (!project_only && (!is.list(context) || anyDuplicated(names(context)) || !all(c("species", "tissue", "research_goal") %in% names(context)) ||
      length(setdiff(names(context), c("species", "tissue", "research_goal", "notes", "columns", "design")))))
    stop("Supply named context with species, tissue, research_goal and optional notes, columns, design. Declare the actual study facts; omit unavailable optional roles.", call. = FALSE)
  if (!project_only) for (field in c("species", "tissue", "research_goal")) .sc_project_string(context[[field]], field)
  if (!is.null(context$notes) && (!is.character(context$notes) || length(context$notes)!=1L || is.na(context$notes)))
    stop("notes must be one text value. Supply a single study note or omit notes.",call.=FALSE)
  if (is.null(checkout)) checkout <- getOption("scAgentKit.checkout")
  if (!is.null(checkout)) {
    checkout <- normalizePath(path.expand(checkout),mustWork=TRUE)
    runtime <- file.path(checkout,"inst","workbench")
    if (!dir.exists(file.path(checkout,"R"))) stop("Developer checkout must contain R sources. Choose the matching repository root, or omit checkout to use the installed runtime.",call.=FALSE)
  } else runtime <- system.file("workbench",package="scAgentKit")
  if (!nzchar(runtime) || !file.exists(file.path(runtime,"start_analysis.py")))
    stop("Installed browser runtime missing; reinstall scAgentKit.",call.=FALSE)
  runtime <- .sc_start_runtime_check(runtime,checkout)
  launcher <- file.path(runtime,"start_analysis.py")
  if (is.null(python)) python <- unname(Sys.which("python3"))
  if (length(python) != 1L || is.na(python) || !nzchar(python)) stop("Install/configure Python 3.9+ before starting the workbench.", call. = FALSE)
  if (!is.null(reference_tissue)) {
    .sc_project_string(reference_tissue, "reference_tissue")
    reference <- annot_act_reference(context$species, reference_tissue)
    message("Explicit ACT reference scope: ", reference_tissue, "; ", nrow(reference), " marker rows. Study tissue remains: ", context$tissue, ".")
  }
  if (!is.null(subcluster_workspace)) {
    .sc_project_string(subcluster_workspace, "subcluster_workspace")
    if (nzchar(Sys.readlink(path.expand(subcluster_workspace)))) stop("subcluster_workspace must not be a symlink.", call. = FALSE)
    subcluster_workspace <- normalizePath(path.expand(subcluster_workspace), mustWork = TRUE)
    project_path <- normalizePath(path.expand(project_dir), mustWork = FALSE)
    if (identical(project_path, subcluster_workspace) || startsWith(subcluster_workspace,paste0(project_path,"/")) || startsWith(project_path,paste0(subcluster_workspace,"/")))
      stop("subcluster_workspace must be separate from the parent project directory.", call. = FALSE)
    if (!dir.exists(subcluster_workspace)) stop("subcluster_workspace must be an existing separate directory.", call. = FALSE)
  }
  .sc_start_summary(setup, model_suggestions, reuse_processed)
  context_file <- tempfile("scagentkit-context-",fileext=".json")
  on.exit(unlink(context_file),add=TRUE)
  if (identical(context$notes,"")) context$notes <- NULL
  jsonlite::write_json(context,context_file,auto_unbox=TRUE,null="null")
  Sys.chmod(context_file,"0600")
  args <- c(shQuote(launcher), shQuote(input), "--project", shQuote(path.expand(project_dir)),
    "--species", shQuote(if (is.null(context$species)) "" else context$species), "--tissue", shQuote(if (is.null(context$tissue)) "" else context$tissue),
    "--research-goal", shQuote(if (is.null(context$research_goal)) "" else context$research_goal), "--notes", shQuote(if (is.null(context$notes)) "" else context$notes),
    "--rscript", shQuote(file.path(R.home("bin"), "Rscript")),
    "--r-library", shQuote(paste(.libPaths(), collapse=.Platform$path.sep)), "--background",
    "--context-file",shQuote(context_file),
    "--model-timeout", as.character(model_timeout),
    if (!is.null(checkout)) c("--source-checkout",shQuote(checkout)),
    "--cluster-column", shQuote(if (!existing && !reuse_processed && missing(cluster_column)) "sc_strategy_clusters" else cluster_column),
    if (!browse) "--no-browser", if (existing) "--reopen",
    if (project_only) "--project-only",
    if (!is.null(subcluster_workspace)) c("--subcluster-workspace", shQuote(subcluster_workspace)),
    if (!is.null(reference_tissue)) c("--reference-tissue", shQuote(reference_tissue)),
    if (imported$imported) "--tenx-import",
    if (model_suggestions == "configured") "--model-suggestions",
    if (model_suggestions == "simulate") "--model-mock")
  if (reuse_processed) {
    .sc_project_string(processed_reason, "processed_reason")
    args <- c(args, "--reuse-processed", "--processed-reason", shQuote(processed_reason))
  }
  if (!is.null(scientific_review) && !project_only) {
    if (reuse_processed) stop("Scientific diagnostics require a new raw entry.",call.=FALSE)
    science_file <- tempfile("scagentkit-science-",fileext=".json")
    on.exit(unlink(science_file),add=TRUE)
    jsonlite::write_json(scientific_review,science_file,auto_unbox=TRUE,null="null")
    Sys.chmod(science_file,"0600")
    args <- c(args,"--scientific-review-file",shQuote(science_file))
  }
  if (!existing) {
    args <- c(args, "--doublet-mode", shQuote(doublet))
    setup_file <- tempfile("scagentkit-provider-", fileext = ".json")
    on.exit(unlink(setup_file), add = TRUE)
    setup$react <- react
    setup$biological_diagnostics <- if (is.null(biology)) FALSE else
      biology[c("cluster_qc", "batch_assessment")]
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
