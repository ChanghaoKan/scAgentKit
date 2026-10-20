# Operational controls do not change scientific configuration or approvals.
.sc_run_control_read <- function(root) {
  path <- file.path(root, ".run-controls.json")
  if (!file.exists(path)) return(list(cancel_requested = FALSE, disk_limit_bytes = NULL))
  if (nzchar(Sys.readlink(path)) || file.info(path)$size > 16384)
    stop("Invalid project control file.", call. = FALSE)
  value <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (!is.logical(value$cancel_requested) || length(value$cancel_requested) != 1L ||
      is.na(value$cancel_requested)) stop("Invalid cancellation state.", call. = FALSE)
  if (!is.null(value$disk_limit_bytes))
    .sc_run_provider_number(value$disk_limit_bytes, "disk_limit_bytes", 1)
  value
}

.sc_run_disk_bytes <- function(root) {
  pending <- root; total <- 0
  while (length(pending)) {
    directory <- pending[[1L]]; pending <- pending[-1L]
    paths <- list.files(directory, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    paths <- paths[!nzchar(Sys.readlink(paths))]
    info <- file.info(paths)
    if (anyNA(info$isdir) || anyNA(info$size)) stop("Cannot measure project storage.", call. = FALSE)
    pending <- c(pending, paths[info$isdir])
    total <- total + sum(info$size[!info$isdir])
  }
  total
}

.sc_run_control_check <- function(root, incoming = 0, check_cancel = TRUE) {
  control <- .sc_run_control_read(root)
  if (check_cancel && isTRUE(control$cancel_requested))
    stop(structure(list(message = "Cancelled at a safe boundary. Saved results remain available; clear cancellation explicitly before resuming.",
      call = NULL), class = c("sc_run_cancelled", "error", "condition")))
  if (!is.null(control$disk_limit_bytes) &&
      .sc_run_disk_bytes(root) + incoming > control$disk_limit_bytes)
    stop(structure(list(message = "Project disk allowance reached. Saved results were preserved. Raise or remove the allowance before resuming.",
      call = NULL), class = c("sc_run_disk_limit", "error", "condition")))
  invisible(TRUE)
}

#' Set operational controls for one project
#'
#' Cancellation is cooperative: an active provider call finishes before the next
#' safe boundary. No process is killed and uncertain requests are never resent.
#' Disk limits apply at checkpoint/stage boundaries, not as a filesystem quota;
#' temporary files, audit records and an active computation can exceed the limit.
#' No saved result is deleted. Omitted arguments retain their current setting.
#' Clear cancellation with cancel=FALSE before explicitly resuming.
#' @param project_dir Existing coordinator project.
#' @param cancel TRUE requests cancellation; FALSE clears it.
#' @param disk_limit_bytes Optional project logical-byte allowance. NULL removes it.
#' @param reason Reason recorded in the control receipt.
#' @return Current operational settings, invisibly.
#' @export
sc_run_control <- function(project_dir, cancel, disk_limit_bytes, reason = "Operator request") {
  root <- .sc_run_root(project_dir)
  state <- .sc_run_load(root, verify = FALSE)
  .sc_project_string(reason, "reason")
  control <- .sc_run_control_read(root)
  if (!missing(cancel)) {
    if (!is.logical(cancel) || length(cancel) != 1L || is.na(cancel))
      stop("cancel must be TRUE or FALSE.", call. = FALSE)
    control$cancel_requested <- cancel
  }
  if (!missing(disk_limit_bytes)) {
    if (!is.null(disk_limit_bytes))
      disk_limit_bytes <- .sc_run_provider_number(disk_limit_bytes, "disk_limit_bytes", 1)
    control$disk_limit_bytes <- disk_limit_bytes
  }
  control$project_id <- state$project_id
  control$input_hash <- state$input_hash
  control$reason <- reason
  control$updated_at <- .sc_run_time()
  .sc_run_atomic(control, file.path(root, "controls", paste0(.sc_run_hash(control), ".json")), json = TRUE)
  .sc_run_atomic(control, file.path(root, ".run-controls.json"), json = TRUE)
  invisible(control)
}

.sc_run_control_audit <- function(root, state) {
  if (file.exists(file.path(root, ".run-controls.json"))) {
    control <- .sc_run_control_read(root)
    if (!identical(control$project_id, state$project_id) || !identical(control$input_hash, state$input_hash))
      stop("Operational controls belong to a different project.", call. = FALSE)
    control_hash <- .sc_run_hash(control)
    if (!identical(state$operational_control_hash, control_hash)) {
      state <- .sc_run_event(state, "operational_controls_observed", list(control = control, hash = control_hash,
        scientific_configuration_changed = FALSE))
      state$operational_control_hash <- control_hash
    }
  }
  state
}
