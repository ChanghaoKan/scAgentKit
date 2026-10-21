format_snapshot <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
    no.. = TRUE, include.dirs = TRUE))
  info <- file.info(file.path(root, paths))
  list(root_modified = file.info(root)$mtime,
    paths = paths, directories = info$isdir, modified = info$mtime,
    bytes = lapply(file.path(root, paths[!info$isdir]), function(path)
      readBin(path, "raw", n = file.info(path)$size)))
}
format_fixture <- function(version = 2L, marker = TRUE) {
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
  for (version in list(NULL, 1L, 3L)) {
    root <- format_fixture(version, marker = !is.null(version))
    before <- format_snapshot(root)
    for (name in entries) {
      fn <- getExportedValue("scAgentKit", name)
      args <- names(formals(fn))
      target <- intersect(c("project_dir", "parent_project", "child_project", "output_dir"), args)
      expect_true(length(target) > 0L, info = name)
      expect_error(do.call(fn, stats::setNames(list(root), target[[1L]])),
        "请用原软件环境打开，或新建项目", info = paste(name, version))
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
  expect_error(sc_run_control(root, cancel = TRUE), "请用原软件环境打开，或新建项目")
  expect_error(.sc_run_lock(root), "请用原软件环境打开，或新建项目")
  expect_identical(format_snapshot(root), before)
  envelope$state$project_format_version <- 2L
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
    list(project_format_version = 2L))
  before <- format_snapshot(root)
  .sc_run_root(root, create = TRUE)
  expect_identical(format_snapshot(root), before)
  unlink(file.path(root, "project-format.json"))
  writeLines("existing project content", file.path(root, "status.json"))
  before <- format_snapshot(root)
  expect_error(.sc_run_root(root, create = TRUE), "请用原软件环境打开，或新建项目")
  expect_identical(format_snapshot(root), before)
})

test_that("child operations verify parent and destination format before locks", {
  parent <- format_fixture(); child <- format_fixture(1L)
  on.exit(unlink(c(parent, child), recursive = TRUE))
  before_parent <- format_snapshot(parent); before_child <- format_snapshot(child)
  expect_error(sc_run_subcluster(parent, child, "0", strrep("a", 64L), 0L,
    reviewer = "test", reason = "test", request_id = "format-test"),
    "请用原软件环境打开，或新建项目")
  expect_identical(format_snapshot(parent), before_parent)
  expect_identical(format_snapshot(child), before_child)
  envelope <- readRDS(file.path(parent, "state.rds"))
  envelope$state$config$subcluster_origin <- list(parent_project = child)
  envelope$hash <- .sc_run_hash(envelope$state)
  saveRDS(envelope, file.path(parent, "state.rds"))
  before_parent <- format_snapshot(parent)
  expect_error(sc_run_resume(parent), "请用原软件环境打开，或新建项目")
  expect_identical(format_snapshot(parent), before_parent)
  expect_identical(format_snapshot(child), before_child)
})

test_that("format helpers participate in runtime and scientific fingerprints", {
  before <- .sc_run_implementation()
  testthat::local_mocked_bindings(.sc_project_format_version = function() 3L,
    .package = "scAgentKit")
  expect_false(identical(before, .sc_run_implementation()))
})

test_that("exported bundle formats are checked after integrity without writing", {
  root <- tempfile("bundle-format-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE))
  for (version in list(NULL, 1L, 3L)) {
    .sc_project_write_json(file.path(root, "project.json"),
      list(schema = "scagentkit.project.v1", project_format_version = version))
    asset <- .sc_project_file_record(root, "project.json")
    .sc_project_write_json(file.path(root, "manifest.json"),
      list(schema = "scagentkit.project-bundle.v1", projectId = "old-bundle",
        sourceFingerprint = strrep("a", 64L), bundleDigest = asset$sha256,
        files = list(asset)))
    before <- format_snapshot(root)
    expect_error(.sc_review_load_project(root), "请用原软件环境打开，或新建项目")
    expect_identical(format_snapshot(root), before)
  }
})
