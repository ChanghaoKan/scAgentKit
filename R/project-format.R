# The project format is independent of individual JSON schema names. Increment
# it whenever persisted execution contracts change; old projects are rejected.
.sc_project_format_version <- function() 2L
.sc_project_format_fail <- function() {
  stop("Project format is not supported. \u8bf7\u7528\u539f\u8f6f\u4ef6\u73af\u5883\u6253\u5f00\uff0c\u6216\u65b0\u5efa\u9879\u76ee\u3002", call. = FALSE)
}
.sc_project_format_valid <- function(version) {
  is.numeric(version) && length(version) == 1L && !is.na(version) &&
    identical(as.numeric(version), as.numeric(.sc_project_format_version()))
}
.sc_project_format_check <- function(root, seen = character()) {
  root <- normalizePath(root, mustWork = TRUE)
  if (root %in% seen) .sc_project_format_fail()
  marker <- file.path(root, "project-format.json")
  if (!file.exists(marker) || dir.exists(marker) || nzchar(Sys.readlink(marker)) ||
      is.na(file.info(marker)$size) || file.info(marker)$size > 4096L)
    .sc_project_format_fail()
  format <- tryCatch(jsonlite::read_json(marker, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(format) || !identical(names(format), "project_format_version") ||
      !.sc_project_format_valid(format$project_format_version)) .sc_project_format_fail()
  state_path <- file.path(root, "state.rds")
  if (file.exists(state_path)) {
    if (nzchar(Sys.readlink(state_path)) || dir.exists(state_path)) .sc_project_format_fail()
    envelope <- tryCatch(readRDS(state_path), error = function(e) .sc_project_format_fail())
    if (!is.list(envelope) || !is.list(envelope$state) ||
        !.sc_project_format_valid(envelope$state$project_format_version)) .sc_project_format_fail()
    if (!identical(envelope$schema, "scagentkit.run-state.v1") ||
        !identical(envelope$hash, .sc_run_hash(envelope$state)))
      stop("State checksum mismatch; no operation was performed.", call. = FALSE)
    parent <- envelope$state$config$subcluster_origin$parent_project
    if (!is.null(parent)) .sc_project_format_check(parent, c(seen, root))
  }
  invisible(TRUE)
}
.sc_project_format_create <- function(root) {
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    .sc_project_format_check(root)
    return(invisible(root))
  }
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  .sc_project_write_json(file.path(root, "project-format.json"),
    list(project_format_version = .sc_project_format_version()))
  invisible(root)
}
.sc_project_format_entry <- function(project_dir, allow_new = FALSE) {
  .sc_project_string(project_dir, "project_dir")
  path <- path.expand(project_dir)
  if (allow_new && (!dir.exists(path) ||
      !length(list.files(path, all.files = TRUE, no.. = TRUE)))) return(invisible(TRUE))
  .sc_project_format_check(path)
}
