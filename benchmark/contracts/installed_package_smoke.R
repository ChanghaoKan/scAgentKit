# Run only after installing the source archive into a NEW library. Dependencies
# may be resolved from existing libraries; this is not a clean-machine claim.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
private_library <- normalizePath(args[[1L]], mustWork = TRUE)
receipt <- file.path(normalizePath(dirname(args[[2L]]), mustWork = TRUE), basename(args[[2L]]))
.libPaths(c(private_library, .libPaths()))
options(scAgentKit.checkout = NULL)
suppressPackageStartupMessages(library(scAgentKit))
package <- normalizePath(find.package("scAgentKit"))
stopifnot(identical(dirname(package), private_library))
runtime <- normalizePath(system.file("workbench", package = "scAgentKit"))
stopifnot(identical(dirname(runtime), package))
getFromNamespace(".sc_start_runtime_check", "scAgentKit")(runtime)
local({
  root <- tempfile("installed-runtime-contract-")
  dir.create(root)
  old <- setwd(root)
  on.exit({setwd(old); unlink(root, recursive = TRUE)}, add = TRUE)
  stopifnot(!dir.exists("R"), !dir.exists("inst"), !dir.exists("workbench"))
  cells <- paste0("C", seq_len(30L))
  counts <- matrix(as.numeric((seq_len(300L * 30L) %% 5L) + 1L), 300L, 30L,
    dimnames = list(paste0("G", seq_len(300L)), cells))
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  saveRDS(object, "a.rds")
  first <- sc_start("a.rds", "project", context = list(species = "human",
    tissue = "Synthetic fixture", research_goal = "Check installed runtime wiring only"),
    browse = FALSE)
  on.exit(tools::pskill(as.integer(first$pid), signal = 15L), add = TRUE)
  initial <- sc_run_inspect("project")
  stopifnot(identical(initial$status, "awaiting_review"))
  files <- c("state.rds", "manifest.json")
  # Record existing authority files without assuming an optional export exists.
  files <- files[file.exists(file.path("project", files))]
  stopifnot("state.rds" %in% files)
  before <- tools::md5sum(file.path("project", files))
  again <- sc_start("a.rds", "project", browse = FALSE)
  stopifnot(isTRUE(again$reused), identical(first$pid, again$pid),
    identical(before, tools::md5sum(file.path("project", files))))
  jsonlite::write_json(list(status = "passed", role = "installed initial-boundary/reopen smoke",
    completed_analysis = FALSE, source_checkout_argument = FALSE, runtime = runtime,
    working_directory_role = "fresh temporary directory outside source checkout",
    dependency_libraries = .libPaths(), R = R.version.string, platform = R.version$platform,
    Python = unname(Sys.which("python3")), package_version = as.character(packageVersion("scAgentKit")),
    initial_status = initial$status, reused = again$reused, provider_calls = 0L,
    session_info = capture.output(sessionInfo())), receipt, auto_unbox = TRUE, pretty = TRUE)
})
