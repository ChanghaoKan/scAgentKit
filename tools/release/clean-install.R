# The container must supply only base/recommended R packages before this script.
local({
  secret_names <- grep("API_?KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL", names(Sys.getenv()),
    value=TRUE, ignore.case=TRUE)
  # The CI-managed read-only token is for remotes' public GitHub dependency API.
  # Provider credentials remain absent; public Release download uses no token.
  Sys.unsetenv(setdiff(secret_names,"GITHUB_PAT"))
  repositories <- readLines("container-repositories.txt", warn=FALSE)
  stopifnot(length(repositories)>0L, all(grepl("^https://",repositories)))
  options(repos=stats::setNames(repositories,
    if(length(repositories)==1L) "CRAN" else paste0("CRAN",seq_along(repositories))))
  lib <- path.expand("~/R/scagentkit-library")
  stopifnot(!dir.exists(lib) || !length(list.files(lib, all.files=TRUE, no..=TRUE)))
  initial <- as.data.frame(installed.packages(), stringsAsFactors=FALSE)
  cat("Initial library paths:\n"); print(.libPaths())
  cat("Initial packages:\n"); print(initial[,c("Package","Version","Priority","LibPath")])
  stopifnot(all(!is.na(initial$Priority) & initial$Priority %in% c("base","recommended")))
  for (path in setdiff(.libPaths(), .Library))
    stopifnot(!length(list.files(path, all.files=TRUE, no..=TRUE)))
  cat("PASS: no pre-existing non-base/recommended dependencies or restored R cache\n")
  cat("Repository configuration:\n"); print(getOption("repos"))
  # These bytes came directly from the README inside the downloaded archive.
  sys.source("README-install.R", envir=environment())
  stopifnot(as.character(packageVersion("scAgentKit")) == "0.8.0",
    identical(normalizePath(dirname(find.package("scAgentKit"))), normalizePath(lib)))
  installed <- as.data.frame(installed.packages(), stringsAsFactors=FALSE)
  external <- installed[is.na(installed$Priority),,drop=FALSE]
  stopifnot(nrow(external)>0L, all(normalizePath(external$LibPath)==normalizePath(lib)))
  cat("Installed non-base dependencies (all from the new library):\n")
  print(external[,c("Package","Version")])
  runtime <- system.file("workbench", package="scAgentKit", mustWork=TRUE)
  getFromNamespace(".sc_start_runtime_check", "scAgentKit")(runtime)
  cat("Running the README offline example from the installed package\n")
  sys.source("README-offline.R", envir=environment())
  stopifnot(inherits(result,"Seurat"), ncol(result)>0L)
  pid <- NULL
  on.exit(if(!is.null(pid))try(tools::pskill(pid,signal=15L),silent=TRUE),add=TRUE)
  options(scAgentKit.checkout=NULL)
  saveRDS(SeuratObject::pbmc_small,"installed-entry-input.rds")
  service <- sc_start("installed-entry-input.rds","installed-entry-project",browse=FALSE,
    context=list(species="human", tissue="Public software control",
      research_goal="Check public Release installation entry"))
  pid <- as.integer(service$pid)
  inspected <- sc_run_inspect("installed-entry-project")
  again <- sc_start("installed-entry-input.rds","installed-entry-project",browse=FALSE)
  stopifnot(inspected$status=="awaiting_review", again$reused,
    identical(service$pid,again$pid))
  download <- jsonlite::read_json("download-receipt.json", simplifyVector=TRUE)
  jsonlite::write_json(list(status="passed", package_version="0.8.0",
    initial_non_base_packages=0L, existing_dependency_library_reused=FALSE,
    restored_R_package_cache=FALSE, installed_dependencies=nrow(external),
    download=download, offline_example="passed", provider_calls=0L,
    runtime_manifest="passed", installed_entry="passed", service_reuse=TRUE,
    actual_browser=FALSE, R=R.version.string,
    package_versions=external[,c("Package","Version")]),
    "clean-install-receipt.json", auto_unbox=TRUE, pretty=TRUE)
  print(sessionInfo())
  cat("PASS: README dependency/package installation, offline example and installed entry\n")
})
