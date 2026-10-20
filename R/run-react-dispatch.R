# Local orchestration for read-only tools. This layer owns caches and hard wall
# time limits; callers must never put the context itself in a model request.
.sc_run_react_context <- function(root, state = NULL) {
  root <- .sc_run_root(root); current <- .sc_run_load(root)
  if (!is.null(state) && !identical(state, current))
    .sc_run_react_error("stale_context", "Use the current committed project state.")
  state <- current
  if (!state$stage %in% c("annotation_propose", "annotation_apply") ||
      !identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    .sc_run_react_error("invalid_binding", "The annotation configuration or implementation binding is unavailable or changed.")
  required <- c("analysis", "markers", "annotation_evidence")
  if (!all(required %in% names(state$files)))
    .sc_run_react_error("invalid_binding", "The annotation checkpoints are incomplete.")
  names <- intersect(c("input", required, "reference", "doublet_diagnostics", "cycle_diagnostics"), names(state$files))
  cfg <- state$config
  cfg$assay <- .sc_run_annotation_option(cfg, "assay", "RNA")
  cfg$counts_layer <- .sc_run_annotation_option(cfg, "counts_layer", "counts")
  cfg$normalized_layer <- .sc_run_annotation_option(cfg, "normalized_layer", "data")
  cfg$cluster_column <- .sc_run_annotation_option(cfg, "cluster_column", "seurat_clusters")
  seu <- .sc_run_get(root, state, "analysis")
  identity <- .sc_project_identity(seu, cfg$assay, cfg$counts_layer,
    cfg$normalized_layer, cfg$cluster_column)
  evidence <- .sc_run_get(root, state, "annotation_evidence")
  observed <- data.frame(cell_id = identity$cells, cluster = unname(identity$membership), stringsAsFactors = FALSE)
  saved <- evidence$private$input_cells
  if (!is.data.frame(saved) || !all(c("cell_id", "cluster") %in% names(saved)) ||
      anyDuplicated(saved$cell_id) || !setequal(observed$cell_id, saved$cell_id))
    .sc_run_react_error("invalid_binding", "Analysis cluster membership differs from the annotation evidence.")
  saved <- saved[match(observed$cell_id, saved$cell_id), c("cell_id", "cluster"), drop = FALSE]
  rownames(saved) <- NULL
  if (!identical(observed, saved))
    .sc_run_react_error("invalid_binding", "Analysis cluster membership differs from the annotation evidence.")
  clusters <- sort(unique(unname(identity$membership)), method = "radix")
  private_ids <- unique(c(identity$cells, sub("^.*::", "", identity$cells)))
  binding <- list(schema = "scagentkit.react-input.v1", project_id = state$project_id,
    input_hash = state$input_hash, config_hash = state$config_hash,
    implementation_hash = state$implementation_hash, tool_version = "scagentkit.react-tools.v1",
    files = state$files[names], assay = cfg$assay, counts_layer = cfg$counts_layer,
    normalized_layer = cfg$normalized_layer, cluster_column = cfg$cluster_column,
    membership_hash = .sc_run_hash(list(cell_id = observed$cell_id, cluster = observed$cluster)),
    private_ids_hash = .sc_run_hash(private_ids),
    clusters_hash = .sc_run_hash(clusters), normalized_config_hash = .sc_run_hash(cfg),
    tool_schema_hash = .sc_run_hash(lapply(.sc_run_react_tools(), function(x) x[setdiff(names(x), "execute")])))
  list(root = root, binding = binding, input_hash = .sc_run_hash(binding), config = cfg,
    clusters = clusters, private_ids = private_ids)
}

.sc_run_react_verify_context <- function(context) {
  if (!is.list(context) || !identical(context$input_hash, .sc_run_hash(context$binding)) ||
      !identical(context$binding$normalized_config_hash, .sc_run_hash(context$config)) ||
      !identical(context$binding$private_ids_hash, .sc_run_hash(context$private_ids)) ||
      !identical(context$binding$clusters_hash, .sc_run_hash(context$clusters)))
    .sc_run_react_error("invalid_binding", "The tool context binding changed.")
  state <- .sc_run_load(context$root, verify = FALSE)
  binding <- context$binding
  if (!identical(state$project_id, binding$project_id) ||
      !identical(state$input_hash, binding$input_hash) ||
      !identical(state$config_hash, binding$config_hash) ||
      !identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, binding$implementation_hash) ||
      !identical(state$implementation_hash, .sc_run_implementation()) ||
      !identical(names(binding$files), intersect(c("input", "analysis", "markers",
        "annotation_evidence", "reference", "doublet_diagnostics", "cycle_diagnostics"), names(state$files))) ||
      !identical(state$files[names(binding$files)], binding$files))
    .sc_run_react_error("invalid_binding", "The current project no longer matches this tool input binding.")
  for (record in binding$files) {
    path <- file.path(context$root, record$path)
    if (!.sc_run_react_safe_path(path, context$root) || !file.exists(path) ||
        !identical(.sc_project_sha_file(path), record$sha256))
      .sc_run_react_error("invalid_binding", "A bound scientific checkpoint changed or is unavailable.")
  }
  cfg <- state$config
  for (field in c("assay", "counts_layer", "normalized_layer", "cluster_column")) {
    default <- switch(field, assay = "RNA", counts_layer = "counts",
      normalized_layer = "data", cluster_column = "seurat_clusters")
    cfg[[field]] <- .sc_run_annotation_option(cfg, field, default)
    if (!identical(binding[[field]], cfg[[field]]))
      .sc_run_react_error("invalid_binding", "The tool layer binding differs from committed configuration.")
  }
  evidence <- .sc_run_get(context$root, state, "annotation_evidence")$private$input_cells
  observed <- evidence[order(evidence$cell_id, method = "radix"), c("cell_id", "cluster"), drop = FALSE]
  rownames(observed) <- NULL
  ids <- unique(c(observed$cell_id, sub("^.*::", "", observed$cell_id)))
  schemas <- lapply(.sc_run_react_tools(), function(x) x[setdiff(names(x), "execute")])
  if (!identical(context$config, cfg) || !identical(context$private_ids, ids) ||
      !identical(context$clusters, sort(unique(observed$cluster), method = "radix")) ||
      !identical(binding$membership_hash, .sc_run_hash(list(cell_id = observed$cell_id, cluster = observed$cluster))) ||
      !identical(binding$tool_version, "scagentkit.react-tools.v1") ||
      !identical(binding$tool_schema_hash, .sc_run_hash(schemas)))
    .sc_run_react_error("invalid_binding", "The tool context differs from its committed evidence.")
  invisible(TRUE)
}

.sc_run_react_safe_path <- function(path, root) {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !startsWith(path, paste0(root, "/")) || grepl("(^|/)\\.\\.?(/|$)", substring(path, nchar(root) + 2L))) return(FALSE)
  current <- path
  while (!identical(current, root)) {
    link <- Sys.readlink(current)
    if (!is.na(link) && nzchar(link)) return(FALSE)
    parent <- dirname(current)
    if (identical(parent, current)) return(FALSE)
    current <- parent
  }
  link <- Sys.readlink(root)
  is.na(link) || !nzchar(link)
}

.sc_run_react_public_check <- function(value, context, max_bytes, arguments = FALSE) {
  allowed <- c("status", "cluster_id", "source", "comparison", "rows_available", "returned", "truncated", "markers",
    "interpretation", "gene", "avg_log2FC", "pct1", "pct2", "padj", "excluded", "support_eligible", "test_status",
    "mean_definition", "detection_definition", "genes", "mean_inside", "detection_inside", "outside_status", "mean_outside",
    "detection_outside", "reason", "entries", "snapshot_version", "species", "tissue", "cell_type", "pmid", "cells",
    "samples", "qc", "doublet", "cell_cycle", "composition", "sample", "proportion", "label_policy", "total_counts",
    "detected_features", "mitochondrial_percent", "measured_cells", "missing_cells", "median", "scores", "score",
    "s_score", "g2m_score", "difference")
  if (isTRUE(arguments)) allowed <- c("cluster_id", "genes", "n")
  strings <- character()
  walk <- function(x) {
    if (is.null(x)) return(invisible(NULL))
    if (is.object(x) || !is.null(dim(x))) .sc_run_react_error("invalid_result", "Tool results must contain only bounded JSON summaries.")
    if (is.list(x)) {
      if (!is.null(names(x)) && (anyDuplicated(names(x)) || anyNA(names(x)) || any(!names(x) %in% allowed)))
        .sc_run_react_error("invalid_result", "A tool returned a field outside its public projection.")
      lapply(x, walk); return(invisible(NULL))
    }
    if ((!is.character(x) && !is.numeric(x) && !is.logical(x)) || length(x) != 1L ||
        !is.null(names(x)) || anyNA(x) || (is.numeric(x) && !is.finite(x)))
      .sc_run_react_error("invalid_result", "Tool results must contain finite JSON scalar values.")
    if (is.character(x)) strings <<- c(strings, x)
    invisible(NULL)
  }
  walk(value)
  tokens <- unlist(strsplit(strings, "[^[:alnum:]_.:-]+"), use.names = FALSE)
  tokens <- sub("[.:-]+$", "", tokens)
  if (any(strings %in% context$private_ids) ||
      any(tokens %in% context$private_ids[nchar(context$private_ids) >= 4L]) ||
      any(grepl("(^|[^[:alnum:]_])(/[^/[:space:]]|~/|\\.{1,2}/|[A-Za-z]:[\\\\/]|file://)", strings)) ||
      any(grepl("(^|[^[:alnum:]_])[[:alnum:]_.-]+(/[[:alnum:]_.-]+)+\\.[[:alnum:]]{1,8}($|[^[:alnum:]_])", strings)) ||
      any(grepl(context$root, strings, fixed = TRUE)))
    .sc_run_react_error("private_output", "The tool output contains a private identifier or local path and was withheld.")
  if (nchar(.sc_project_json(value), type = "bytes") > max_bytes)
    .sc_run_react_error("result_too_large", "The bounded tool response exceeds its byte limit and was withheld.")
  invisible(TRUE)
}

.sc_run_react_dispatch_local <- function(context, tool, arguments, cache_dir) {
  .sc_run_react_verify_context(context)
  definition <- .sc_run_react_tools()[[tool]]
  .sc_run_react_public_check(arguments, context, definition$max_argument_bytes, arguments = TRUE)
  key <- .sc_run_hash(list(tool = tool, arguments = arguments, input_hash = context$input_hash,
    tool_schema_version = definition$schema_version, tool_schema_hash = context$binding$tool_schema_hash))
  path <- NULL
  if (!identical(cache_dir, FALSE)) {
    if (is.null(cache_dir)) cache_dir <- file.path(context$root, "annotation", "react", "cache")
    if (!.sc_run_react_safe_path(cache_dir, context$root))
      .sc_run_react_error("invalid_cache", "Cache must use a nonsymlink directory inside the current project.")
    path <- file.path(cache_dir, paste0(key, ".rds"))
    if (!.sc_run_react_safe_path(path, context$root))
      .sc_run_react_error("invalid_cache", "Cache path is not a regular local project path.")
    if (file.exists(path)) {
      if (is.na(file.info(path)$size) || file.info(path)$size > definition$max_result_bytes * 4L)
        .sc_run_react_error("invalid_cache", "The cache record exceeds its storage limit.")
      cached <- tryCatch(readRDS(path), error = function(e) NULL)
      if (!is.list(cached) || !identical(cached$schema, "scagentkit.react-cache.v1") ||
          !identical(cached$key, key) || !identical(cached$result_hash, .sc_run_hash(cached$result)))
        .sc_run_react_error("invalid_cache", "The cache record is invalid or changed.")
      .sc_run_react_public_check(cached$result, context, definition$max_result_bytes)
      .sc_run_react_verify_context(context)
      return(list(result = cached$result, result_hash = cached$result_hash, cached = TRUE))
    }
  }
  result <- definition$execute(context, arguments)
  .sc_run_react_public_check(result, context, definition$max_result_bytes)
  .sc_run_react_verify_context(context)
  hash <- .sc_run_hash(result)
  if (!is.null(path)) {
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
    if (!.sc_run_react_safe_path(path, context$root))
      .sc_run_react_error("invalid_cache", "The cache directory changed before publication.")
    .sc_run_atomic(list(schema = "scagentkit.react-cache.v1", key = key, result_hash = hash, result = result), path)
  }
  list(result = result, result_hash = hash, cached = FALSE)
}

.sc_run_react_dispatch <- function(context, tool, arguments, cache_dir = NULL, timeout = 60) {
  started <- proc.time()[["elapsed"]]
  failure <- function(code, message) list(schema = "scagentkit.react-tool-result.v1", ok = FALSE,
    tool = if (is.character(tool) && length(tool) == 1L && tool %in% names(.sc_run_react_tools())) tool else NULL,
    input_hash = if (is.list(context) && is.character(context$input_hash) &&
      length(context$input_hash) == 1L && !is.na(context$input_hash) &&
      grepl("^[0-9a-f]{64}$", context$input_hash)) context$input_hash else NULL,
    result = NULL, result_hash = NULL, cached = FALSE,
    error = list(code = code, message = message))
  tryCatch({
    if (!is.character(tool) || length(tool) != 1L || is.na(tool) || !tool %in% names(.sc_run_react_tools()))
      return(failure("unknown_tool", "The requested tool is not in the read-only registry."))
    if (!is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) || timeout <= 0 || timeout > 60)
      return(failure("invalid_timeout", "Tool timeout must be positive and no greater than 60 seconds."))
    definition <- .sc_run_react_tools()[[tool]]
    arguments <- .sc_run_react_arguments(definition, arguments)
    # No callback supplied by a caller or model is executed. Only the installed,
    # version-bound registry runs in the terminable process.
    process <- callr::r_bg(function(context, tool, arguments, cache_dir) {
      tryCatch(getFromNamespace(".sc_run_react_dispatch_local", "scAgentKit")(
        context, tool, arguments, cache_dir), error = function(e) list(worker_error = TRUE,
          code = if (inherits(e, "sc_run_react_error")) e$code else "execution_failed",
          message = if (inherits(e, "sc_run_react_error")) conditionMessage(e) else "The read-only tool could not complete; no scientific state was changed."))
    }, args = list(context = context, tool = tool, arguments = arguments, cache_dir = cache_dir),
      libpath = .libPaths(), stdout = "|", stderr = "|", supervise = TRUE)
    on.exit(if (process$is_alive()) process$kill_tree(), add = TRUE)
    remaining <- timeout - (proc.time()[["elapsed"]] - started)
    if (remaining > 0) process$wait(timeout = ceiling(remaining * 1000))
    if (process$is_alive() || proc.time()[["elapsed"]] - started > timeout) {
      if (process$is_alive()) process$kill_tree()
      return(failure("timeout", "The tool reached its wall-time limit; its worker was stopped."))
    }
    output <- process$get_result()
    if (isTRUE(output$worker_error)) return(failure(output$code, output$message))
    result <- c(list(schema = "scagentkit.react-tool-result.v1", ok = TRUE, tool = tool,
      arguments = arguments, input_hash = context$input_hash), output, list(error = NULL))
    if (nchar(.sc_project_json(result), type = "bytes") > definition$max_result_bytes)
      return(failure("result_too_large", "The complete tool response exceeds its byte limit and was withheld."))
    result
  }, sc_run_react_error = function(e) failure(e$code, conditionMessage(e)),
    error = function(e) failure("execution_failed", "The read-only tool could not complete; no scientific state was changed."))
}
