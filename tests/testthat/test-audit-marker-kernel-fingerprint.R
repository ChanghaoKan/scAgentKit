for (kernel in c("presto", "limma", "callr", "processx")) test_that(paste(kernel,
  "execution dependency presence and version affect implementation fingerprint"), {
  require_original <- base::requireNamespace
  version_original <- utils::packageVersion
  present <- FALSE
  version <- "1.0.0"
  requested <- character()
  testthat::local_mocked_bindings(requireNamespace = function(package, ...) {
    if (identical(package, kernel)) {
      requested <<- c(requested, package)
      return(present)
    }
    require_original(package, ...)
  }, .package = "base")
  testthat::local_mocked_bindings(packageVersion = function(pkg, ...) {
    if (identical(pkg, kernel)) return(package_version(version))
    version_original(pkg, ...)
  }, .package = "utils")
  absent <- .sc_run_implementation()
  present <- TRUE
  first <- .sc_run_implementation()
  expect_false(identical(first, absent))
  version <- "1.0.1"
  expect_false(identical(.sc_run_implementation(), first))
  expect_true(kernel %in% requested)
})
