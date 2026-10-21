#!/usr/bin/env Rscript
# Offline session benchmark using only the synthetic stage-1 performance fixture.
# This is fixture reconstruction, never migration of a research project.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: benchmark-react-session.R SYNTHETIC_FIXTURE_DIR NEW_OUTPUT_DIR")
source_dir <- normalizePath(args[[1L]], mustWork = TRUE)
output <- args[[2L]]
if (file.exists(output)) stop("Output directory must be new.")
internal <- function(name) getFromNamespace(name, "scAgentKit")
write_json <- function(x, path) jsonlite::write_json(x, path, auto_unbox = TRUE,
  pretty = TRUE, null = "null", na = "null", digits = NA)
source_root <- file.path(source_dir, "project")
state <- internal(".sc_run_load")(source_root, verify = FALSE)
if (!identical(state$project_id, "react-tools-synthetic-performance") ||
    length(state$approvals) || !is.null(state$approved) || !is.null(state$pending))
  stop("Only the unapproved synthetic benchmark fixture is accepted.")
dir.create(output, recursive = TRUE)
output <- normalizePath(output)
root <- internal(".sc_run_root")(file.path(output, "project"), create = TRUE)
for (record in state$files) {
  from <- file.path(source_root, record$path)
  stopifnot(identical(internal(".sc_project_sha_file")(from), record$sha256))
  to <- file.path(root, record$path); dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  stopifnot(file.copy(from, to))
}
state$implementation_hash <- internal(".sc_run_implementation")()
state$history <- list(); state$revision <- 0L
state <- internal(".sc_run_event")(state, "synthetic_session_benchmark_reconstructed",
  list(scientific_approval = FALSE, source_file_hashes = state$files))
internal(".sc_run_save")(root, state)
environment <- jsonlite::read_json(file.path(source_dir, "environment.json"))
command_value <- function(command, arguments) {
  if (!nzchar(Sys.which(command))) return("unknown")
  value <- tryCatch(suppressWarnings(system2(command, arguments, stdout = TRUE, stderr = FALSE)),
    error = function(e) character())
  if (!length(value) || !is.null(attr(value, "status"))) "unknown" else paste(value, collapse = " ")
}
environment$machine$os <- as.list(Sys.info()[c("sysname", "release", "version", "machine")])
environment$machine$macos_version <- command_value("sw_vers", "-productVersion")
environment$machine$cpu <- command_value("sysctl", c("-n", "machdep.cpu.brand_string"))
environment$machine$memory_bytes <- command_value("sysctl", c("-n", "hw.memsize"))
environment$machine$logical_cpus <- parallel::detectCores(logical = TRUE)
environment$machine$r <- R.version.string
environment$machine$package_versions <- lapply(names(environment$machine$package_versions), function(p)
  as.character(utils::packageVersion(p))) |>
  stats::setNames(names(environment$machine$package_versions))
environment$dataset$implementation_hash <- state$implementation_hash
write_json(environment, file.path(output, "environment.json"))
calls <- readRDS(file.path(source_dir, "calls.rds"))
elapsed <- function() unname(proc.time()[["elapsed"]])
start <- elapsed(); context <- internal(".sc_run_react_context")(root)
context_seconds <- elapsed() - start
start <- elapsed(); runtime <- internal(".sc_run_react_worker_start")(context)
startup_seconds <- elapsed() - start
rows <- list()
tryCatch({
  for (tool in names(calls)) for (i in 1:4) {
    start <- elapsed()
    value <- internal(".sc_run_react_worker_call")(runtime, tool, calls[[tool]])
    rows[[length(rows) + 1L]] <- data.frame(tool = tool,
      phase = if (i == 1L) "cold" else "hot", repetition = i,
      elapsed_seconds = elapsed() - start, ok = isTRUE(value$ok), cached = isTRUE(value$cached),
      result_hash = if (is.null(value$result_hash)) NA_character_ else value$result_hash)
    if (!isTRUE(value$ok)) stop("Tool failed: ", tool)
  }
  start <- elapsed(); internal(".sc_run_react_worker_check")(runtime, final = TRUE)
  final_verify_seconds <- elapsed() - start
}, finally = internal(".sc_run_react_worker_close")(runtime))
rows <- do.call(rbind, rows)
utils::write.csv(rows, file.path(output, "timings.csv"), row.names = FALSE)
passed <- all(rows$ok) && all(rows$elapsed_seconds <= 60) &&
  all(!rows$cached[rows$phase == "cold"]) && all(rows$cached[rows$phase == "hot"]) &&
  all(vapply(split(rows$result_hash, rows$tool), function(x) length(unique(x)) == 1L, logical(1)))
write_json(list(schema = "scagentkit.react-session-benchmark.v1", passed = passed,
  context_seconds = context_seconds, startup_seconds = startup_seconds,
  final_verify_seconds = final_verify_seconds, timings = rows,
  scope = "Synthetic saved counts and statistics only. No biological validation or provider calls. One worker; cold means empty application cache, not flushed OS cache. Hot includes file-state alarms. Full checkpoint SHA checks measured separately; no research project migration."),
  file.path(output, "benchmark.json"))
stopifnot(passed)
