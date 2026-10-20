# Session-local worker: verified bytes are decoded once and retained in memory.
# Filesystem status is an alarm, never a replacement for publication-time SHA.
.sc_run_react_worker_close <- function(runtime) {
  if (is.environment(runtime) && !is.null(runtime$process) && runtime$process$is_alive())
    runtime$process$kill_tree()
  invisible(NULL)
}

.sc_run_react_stamp <- function(context) {
  paths <- vapply(context$binding$files, function(record)
    file.path(context$root, record$path), character(1))
  if (!all(vapply(paths, .sc_run_react_safe_path, logical(1), root = context$root)))
    .sc_run_react_error("invalid_binding", "A bound checkpoint path changed.")
  info <- file.info(paths)
  if (anyNA(info$size) || any(info$isdir))
    .sc_run_react_error("invalid_binding", "A bound checkpoint is unavailable.")
  args <- if (identical(unname(Sys.info()["sysname"]), "Darwin")) c("-f", "%d:%i") else c("-c", "%d:%i", "--")
  inode <- suppressWarnings(system2("stat", c(args, shQuote(paths)), stdout = TRUE, stderr = FALSE))
  if (length(inode) != length(paths) || !is.null(attr(inode, "status")) ||
      any(!grepl("^[0-9]+:[0-9]+$", inode)))
    .sc_run_react_error("invalid_binding", "Checkpoint file identity could not be checked.")
  list(size = unname(info$size), mtime = as.numeric(info$mtime), inode = unname(inode))
}

.sc_run_react_snapshot <- function(context) {
  schemas <- lapply(.sc_run_react_tools(), function(x) x[setdiff(names(x), "execute")])
  if (!identical(context$binding$implementation_hash, .sc_run_implementation()) ||
      !identical(context$binding$tool_schema_hash, .sc_run_hash(schemas)))
    .sc_run_react_error("invalid_binding", "Worker implementation differs from the authorized session.")
  before <- .sc_run_react_stamp(context)
  objects <- new.env(parent = emptyenv())
  for (name in names(context$binding$files)) {
    record <- context$binding$files[[name]]
    path <- file.path(context$root, record$path)
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    if (!identical(digest::digest(bytes, algo = "sha256", serialize = FALSE), record$sha256))
      .sc_run_react_error("invalid_binding", "A bound checkpoint changed before loading.")
    if (identical(name, "input")) next
    con <- gzcon(rawConnection(bytes))
    value <- tryCatch(readRDS(con), finally = close(con))
    assign(name, value, envir = objects)
  }
  if (!identical(before, .sc_run_react_stamp(context)))
    .sc_run_react_error("invalid_binding", "A checkpoint changed during verified loading.")
  seu <- get("analysis", objects)
  cfg <- context$config
  identity <- .sc_project_identity(seu, cfg$assay, cfg$counts_layer,
    cfg$normalized_layer, cfg$cluster_column)
  membership <- list(cell_id = identity$cells, cluster = unname(identity$membership))
  saved <- get("annotation_evidence", objects)$private$input_cells
  saved <- saved[match(identity$cells, saved$cell_id), , drop = FALSE]
  if (!identical(context$binding$membership_hash, .sc_run_hash(membership)) ||
      !identical(membership$cell_id, saved$cell_id) ||
      !identical(membership$cluster, saved$cluster))
    .sc_run_react_error("invalid_binding", "Verified checkpoint membership differs from the session.")
  lockEnvironment(objects, bindings = TRUE)
  context$objects <- objects
  list(context = context, stamp = before, cache = new.env(parent = emptyenv()))
}

.sc_run_react_worker_start <- function(context, timeout = 60) {
  process <- callr::r_session$new(options = callr::r_session_options(
    libpath = .libPaths(), stdout = "|", stderr = "|", supervise = TRUE))
  ready <- FALSE
  on.exit(if (!ready) process$kill_tree(), add = TRUE)
  process$call(function(context) {
    tryCatch({
      worker <- getFromNamespace(".sc_run_react_snapshot", "scAgentKit")(context)
      assign(".scagentkit_react_worker", worker, envir = .GlobalEnv)
      list(stamp = worker$stamp)
    }, sc_run_react_error = function(e) list(worker_error = TRUE, code = e$code),
      error = function(e) list(worker_error = TRUE, code = "worker_unavailable"))
  }, list(context = context))
  started <- proc.time()[["elapsed"]]
  repeat {
    if (identical(process$poll_process(50), "ready")) result <- process$read()
    if (!process$is_alive() || proc.time()[["elapsed"]] - started >= timeout)
      .sc_run_react_error("timeout", "The evidence worker could not start within its time limit.")
    if (process$get_state() == "idle") break
  }
  if (!is.null(result$error))
    .sc_run_react_error("worker_unavailable", "The evidence worker could not load its session.")
  if (isTRUE(result$result$worker_error))
    .sc_run_react_error(result$result$code, "The evidence worker could not validate its session.")
  stamp <- result$result$stamp
  if (!identical(stamp, .sc_run_react_stamp(context)))
    .sc_run_react_error("invalid_binding", "Checkpoint status changed during worker startup.")
  runtime <- new.env(parent = emptyenv())
  runtime$context <- context; runtime$stamp <- stamp; runtime$process <- process
  lockEnvironment(runtime, bindings = TRUE)
  ready <- TRUE
  runtime
}

.sc_run_react_worker_check <- function(runtime, final = FALSE) {
  if (!is.environment(runtime) || !environmentIsLocked(runtime))
    .sc_run_react_error("invalid_binding", "The evidence worker scope is unavailable.")
  context <- runtime$context
  state <- .sc_run_load(context$root, verify = FALSE)
  if (!identical(state$project_id, context$binding$project_id) ||
      !identical(state$input_hash, context$binding$input_hash) ||
      !identical(state$config_hash, context$binding$config_hash) ||
      !identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, context$binding$implementation_hash) ||
      !identical(state$files[names(context$binding$files)], context$binding$files) ||
      !identical(.sc_run_react_stamp(context), runtime$stamp))
    .sc_run_react_error("invalid_binding", "The session's bound scientific inputs changed.")
  if (final) .sc_run_react_verify_context(context)
  invisible(TRUE)
}

.sc_run_react_worker_call <- function(runtime, tool, arguments, timeout = 60) {
  .sc_run_react_worker_check(runtime)
  failure <- function(code, message) list(schema = "scagentkit.react-tool-result.v1",
    ok = FALSE, tool = if (is.character(tool) && length(tool) == 1L &&
      tool %in% names(.sc_run_react_tools())) tool else NULL,
    input_hash = runtime$context$input_hash, result = NULL, result_hash = NULL,
    cached = FALSE, error = list(code = code, message = message))
  if (!is.character(tool) || length(tool) != 1L || is.na(tool) ||
      !tool %in% names(.sc_run_react_tools()))
    return(failure("unknown_tool", "This tool is not in the read-only registry."))
  if (!is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) ||
      timeout <= 0 || timeout > 60)
    return(failure("invalid_timeout", "Tool timeout must be positive and no greater than 60 seconds."))
  definition <- .sc_run_react_tools()[[tool]]
  if (is.null(definition)) return(failure("unknown_tool", "This tool is not in the read-only registry."))
  arguments <- tryCatch(.sc_run_react_arguments(definition, arguments), error = identity)
  if (inherits(arguments, "error")) return(failure("invalid_arguments", "Arguments do not match the tool schema."))
  checked <- tryCatch(.sc_run_react_public_check(arguments, runtime$context,
    definition$max_argument_bytes, arguments = TRUE), sc_run_react_error = identity)
  if (inherits(checked, "sc_run_react_error")) return(failure(checked$code, conditionMessage(checked)))
  process <- runtime$process
  if (!process$is_alive()) return(failure("worker_unavailable", "The evidence worker is no longer available."))
  process$call(function(tool, arguments) {
    tryCatch({
    worker <- get(".scagentkit_react_worker", envir = .GlobalEnv)
    ns <- asNamespace("scAgentKit")
    definition <- get(".sc_run_react_tools", ns)()[[tool]]
    key <- get(".sc_run_hash", ns)(list(tool = tool, arguments = arguments,
      input_hash = worker$context$input_hash, schema_hash = worker$context$binding$tool_schema_hash))
    cached <- exists(key, worker$cache, inherits = FALSE)
    result <- if (cached) get(key, worker$cache) else definition$execute(worker$context, arguments)
    get(".sc_run_react_public_check", ns)(result, worker$context, definition$max_result_bytes)
    if (!cached) assign(key, result, worker$cache)
    list(result = result, result_hash = get(".sc_run_hash", ns)(result), cached = cached)
    }, sc_run_react_error = function(e) list(worker_error = TRUE, code = e$code),
      error = function(e) list(worker_error = TRUE, code = "execution_failed"))
  }, list(tool = tool, arguments = arguments))
  started <- proc.time()[["elapsed"]]
  repeat {
    if (identical(process$poll_process(25), "ready")) result <- process$read()
    if (!process$is_alive() || proc.time()[["elapsed"]] - started >= timeout) {
      process$kill_tree()
      return(failure("timeout", "The tool reached its time limit; the worker was stopped."))
    }
    if (process$get_state() == "idle") break
  }
  .sc_run_react_worker_check(runtime)
  if (isTRUE(result$result$worker_error)) {
    if (result$result$code %in% c("invalid_binding", "invalid_evidence"))
      .sc_run_react_error(result$result$code, "The saved scientific evidence failed validation.")
    return(failure(result$result$code, "The read-only tool result was unavailable or withheld."))
  }
  if (!is.null(result$error)) {
    error <- result$error
    # Scientific integrity errors are never converted into a usable fallback.
    if (inherits(error, "sc_run_react_error") && error$code %in% c("invalid_binding", "invalid_evidence"))
      stop(error)
    return(failure("execution_failed", "The read-only tool could not complete."))
  }
  out <- c(list(schema = "scagentkit.react-tool-result.v1", ok = TRUE, tool = tool,
    arguments = arguments, input_hash = runtime$context$input_hash), result$result, list(error = NULL))
  if (nchar(.sc_project_json(out), type = "bytes") > definition$max_result_bytes)
    return(failure("result_too_large", "The complete tool response exceeds its size limit."))
  out
}
