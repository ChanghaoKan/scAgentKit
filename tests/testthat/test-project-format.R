format_snapshot <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
    no.. = TRUE, include.dirs = TRUE))
  info <- file.info(file.path(root, paths))
  links <- Sys.readlink(file.path(root, paths))
  regular <- !is.na(info$isdir) & !info$isdir & !nzchar(links)
  list(root_modified = file.info(root)$mtime,
    paths = paths, directories = info$isdir, modified = info$mtime, links = links,
    bytes = lapply(file.path(root, paths[regular]), function(path)
      readBin(path, "raw", n = file.info(path)$size)))
}
format_fixture <- function(version = 3L, marker = TRUE) {
  root <- tempfile("project-format-"); dir.create(root)
  if (marker) .sc_project_write_json(file.path(root, "project-format.json"),
    list(project_format_version = version))
  state <- list(project_format_version = version, config = list(), history = list(),
    revision = 0L, files = list())
  saveRDS(list(schema = "scagentkit.run-state.v1", hash = .sc_run_hash(state), state = state),
    file.path(root, "state.rds"), version = 2L)
  writeLines("Do not modify", file.path(root, "evidence.txt"))
  root
}

test_that("every exported project entry rejects old projects without writes", {
  exports <- getNamespaceExports("scAgentKit")
  entries <- sort(c("sc_analyze", "sc_start", "sc_open", grep("^sc_run($|_)", exports, value = TRUE)))
  expect_true(length(entries) >= 28L)
  for (version in list(NULL, 1L, 2L, 4L)) {
    root <- format_fixture(version, marker = !is.null(version))
    before <- format_snapshot(root)
    for (name in entries) {
      fn <- getExportedValue("scAgentKit", name)
      args <- names(formals(fn))
      target <- intersect(c("project_dir", "parent_project", "child_project", "output_dir"), args)
      expect_true(length(target) > 0L, info = name)
      expect_error(do.call(fn, stats::setNames(list(root), target[[1L]])),
        "Open it with its original software environment or create a new project", info = paste(name, version))
      expect_identical(format_snapshot(root), before, info = paste(name, version))
    }
    unlink(root, recursive = TRUE)
  }
})

test_that("a current marker cannot authorize old state or a changed checksum", {
  root <- format_fixture(); on.exit(unlink(root, recursive = TRUE))
  envelope <- readRDS(file.path(root, "state.rds"))
  envelope$state$project_format_version <- NULL
  envelope$hash <- .sc_run_hash(envelope$state)
  saveRDS(envelope, file.path(root, "state.rds"))
  before <- format_snapshot(root)
  expect_error(sc_run_control(root, cancel = TRUE), "Open it with its original software environment or create a new project")
  expect_error(.sc_run_lock(root), "Open it with its original software environment or create a new project")
  expect_identical(format_snapshot(root), before)
  envelope$state$project_format_version <- 3L
  saveRDS(envelope, file.path(root, "state.rds"))
  before <- format_snapshot(root)
  expect_error(sc_run_resume(root), "State checksum mismatch")
  expect_error(.sc_run_lock(root), "State checksum mismatch")
  expect_identical(format_snapshot(root), before)
})

test_that("new roots receive one marker and existing unversioned content is refused", {
  root <- tempfile("new-format-"); on.exit(unlink(root, recursive = TRUE))
  expect_identical(.sc_run_root(root, create = TRUE), normalizePath(root))
  expect_identical(jsonlite::read_json(file.path(root, "project-format.json")),
    list(project_format_version = 3L))
  before <- format_snapshot(root)
  .sc_run_root(root, create = TRUE)
  expect_identical(format_snapshot(root), before)
  unlink(file.path(root, "project-format.json"))
  writeLines("existing project content", file.path(root, "status.json"))
  before <- format_snapshot(root)
  expect_error(.sc_run_root(root, create = TRUE), "Open it with its original software environment or create a new project")
  expect_identical(format_snapshot(root), before)
})

test_that("child operations verify parent and destination format before locks", {
  parent <- format_fixture(); child <- format_fixture(1L)
  on.exit(unlink(c(parent, child), recursive = TRUE))
  before_parent <- format_snapshot(parent); before_child <- format_snapshot(child)
  expect_error(sc_run_subcluster(parent, child, "0", strrep("a", 64L), 0L,
    reviewer = "test", reason = "test", request_id = "format-test"),
    "Open it with its original software environment or create a new project")
  expect_identical(format_snapshot(parent), before_parent)
  expect_identical(format_snapshot(child), before_child)
  envelope <- readRDS(file.path(parent, "state.rds"))
  envelope$state$config$subcluster_origin <- list(parent_project = child)
  envelope$hash <- .sc_run_hash(envelope$state)
  saveRDS(envelope, file.path(parent, "state.rds"))
  before_parent <- format_snapshot(parent)
  expect_error(sc_run_resume(parent), "Open it with its original software environment or create a new project")
  expect_identical(format_snapshot(parent), before_parent)
  expect_identical(format_snapshot(child), before_child)
})

test_that("format helpers participate in runtime and scientific fingerprints", {
  before <- .sc_run_implementation()
  testthat::local_mocked_bindings(.sc_project_format_version = function() 4L,
    .package = "scAgentKit")
  expect_false(identical(before, .sc_run_implementation()))
})

test_that("exported bundle formats are checked after integrity without writing", {
  root <- tempfile("bundle-format-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE))
  for (version in list(NULL, 1L, 2L, 4L)) {
    .sc_project_write_json(file.path(root, "project.json"),
      list(schema = "scagentkit.project.v1", project_format_version = version))
    asset <- .sc_project_file_record(root, "project.json")
    .sc_project_write_json(file.path(root, "manifest.json"),
      list(schema = "scagentkit.project-bundle.v1", projectId = "old-bundle",
        sourceFingerprint = strrep("a", 64L), bundleDigest = asset$sha256,
        files = list(asset)))
    before <- format_snapshot(root)
    expect_error(.sc_review_load_project(root), "Open it with its original software environment or create a new project")
    expect_identical(format_snapshot(root), before)
  }
})

format_installed_bridge <- function(root) {
  bridge <- system.file("workbench", "project_format_bridge.R", package = "scAgentKit")
  stopifnot(nzchar(bridge), file.exists(bridge))
  output <- tempfile("format-bridge-output-"); error <- tempfile("format-bridge-error-")
  on.exit(unlink(c(output, error)), add = TRUE)
  libraries <- unique(c(dirname(find.package("scAgentKit")), .libPaths()))
  environment <- paste0("R_LIBS_USER=", shQuote(paste(libraries, collapse = .Platform$path.sep)))
  status <- system2(file.path(R.home("bin"), "Rscript"),
    args = shQuote(c("--vanilla", bridge, root)), env = environment,
    stdout = output, stderr = error)
  list(status = as.integer(status), output = readLines(output, warn = FALSE))
}

test_that("installed format bridge verifies serialized authority without writing", {
  root <- format_fixture(); on.exit(unlink(root, recursive = TRUE))
  before <- format_snapshot(root)
  expect_identical(format_installed_bridge(root),
    list(status = 0L, output = "scagentkit.project-format.ok"))
  expect_identical(format_snapshot(root), before)
  original <- readRDS(file.path(root, "state.rds"))
  for (version in list(NULL, 1L, 2L, 4L)) {
    envelope <- original
    envelope$state$project_format_version <- version
    envelope$hash <- .sc_run_hash(envelope$state)
    saveRDS(envelope, file.path(root, "state.rds"), version = 2L)
    before <- format_snapshot(root)
    expect_identical(format_installed_bridge(root), list(status = 1L, output = character()))
    expect_identical(format_snapshot(root), before)
  }
  original$hash <- strrep("0", 64L)
  saveRDS(original, file.path(root, "state.rds"), version = 2L)
  before <- format_snapshot(root)
  expect_identical(format_installed_bridge(root), list(status = 1L, output = character()))
  expect_identical(format_snapshot(root), before)
})

test_that("installed format bridge rechecks a parent's authoritative format", {
  parent <- format_fixture(); child <- format_fixture()
  on.exit(unlink(c(parent, child), recursive = TRUE))
  envelope <- readRDS(file.path(child, "state.rds"))
  envelope$state$config$subcluster_origin <- list(parent_project = parent)
  envelope$hash <- .sc_run_hash(envelope$state)
  saveRDS(envelope, file.path(child, "state.rds"), version = 2L)
  expect_identical(format_installed_bridge(child),
    list(status = 0L, output = "scagentkit.project-format.ok"))
  envelope <- readRDS(file.path(parent, "state.rds"))
  envelope$state$project_format_version <- 2L
  envelope$hash <- .sc_run_hash(envelope$state)
  saveRDS(envelope, file.path(parent, "state.rds"), version = 2L)
  before_parent <- format_snapshot(parent); before_child <- format_snapshot(child)
  expect_identical(format_installed_bridge(child), list(status = 1L, output = character()))
  expect_identical(format_snapshot(parent), before_parent)
  expect_identical(format_snapshot(child), before_child)
})


test_that("referenced parents require regular nonsymlink state while new roots may be marker-only", {
  parent <- format_fixture(); child <- format_fixture()
  on.exit(unlink(c(parent, child), recursive = TRUE))
  envelope <- readRDS(file.path(child, "state.rds"))
  envelope$state$config$subcluster_origin <- list(parent_project = parent)
  envelope$hash <- .sc_run_hash(envelope$state)
  saveRDS(envelope, file.path(child, "state.rds"), version = 2L)
  state_path <- file.path(parent, "state.rds")
  saved_state <- readBin(state_path, "raw", n = file.info(state_path)$size)
  unlink(state_path)
  before <- format_snapshot(parent)
  expect_true(.sc_project_format_check(parent))
  expect_identical(format_snapshot(parent), before)
  for (kind in c("missing", "dangling", "directory")) {
    unlink(state_path, recursive = TRUE)
    if (identical(kind, "dangling")) expect_true(file.symlink(file.path(parent, "absent-state.rds"), state_path))
    if (identical(kind, "directory")) dir.create(state_path)
    before_parent <- format_snapshot(parent); before_child <- format_snapshot(child)
    expect_error(.sc_project_format_check(child), "Open it with its original software environment or create a new project", info = kind)
    expect_error(.sc_run_lock(child), "Open it with its original software environment or create a new project", info = kind)
    expect_identical(format_installed_bridge(child), list(status = 1L, output = character()), info = kind)
    expect_identical(format_snapshot(parent), before_parent, info = kind)
    expect_identical(format_snapshot(child), before_child, info = kind)
  }
  unlink(state_path, recursive = TRUE)
  writeBin(saved_state, state_path)
  before_parent <- format_snapshot(parent); before_child <- format_snapshot(child)
  expect_true(.sc_project_format_check(child))
  expect_identical(format_installed_bridge(child), list(status = 0L, output = "scagentkit.project-format.ok"))
  expect_identical(format_snapshot(parent), before_parent)
  expect_identical(format_snapshot(child), before_child)
})
