#' Reopen saved project results in the local browser
#'
#' Starts or reuses a read-only localhost viewer. No analysis is resumed and no
#' model is called. Uses the current R executable and library paths.
#' @param project_dir Existing saved sc_run directory.
#' @param checkout Source checkout containing workbench/open_results.py. Supply
#'   once, or run from the checkout; subsequent calls remember its location.
#' @param python Existing Python 3 executable, automatically detected by default.
#' @param browse Open the URL in a browser; FALSE prints and returns the URL.
#' @return Invisibly, the URL, process ID and whether a service was reused.
#' @export
sc_run_open <- function(project_dir, checkout = NULL, python = NULL, browse = interactive()) {
  .sc_project_format_entry(project_dir)
  root <- .sc_run_root(project_dir)
  .sc_run_load(root)
  preferences <- file.path(root, ".workbench-launcher", "preferences.json")
  saved <- if (file.exists(preferences)) tryCatch(jsonlite::fromJSON(preferences), error = function(e) list()) else list()
  if (is.null(checkout)) checkout <- getOption("scAgentKit.checkout", saved$checkout)
  if (is.null(checkout)) {
    candidate <- normalizePath(getwd(), mustWork = TRUE)
    repeat {
      if (file.exists(file.path(candidate, "workbench", "open_results.py"))) { checkout <- candidate; break }
      parent <- dirname(candidate)
      if (identical(parent, candidate)) break
      candidate <- parent
    }
  }
  if (is.null(checkout) || !file.exists(file.path(checkout, "workbench", "open_results.py")))
    stop("Supply checkout='/path/to/scAgentKit' once to locate the saved result viewer.", call. = FALSE)
  checkout <- normalizePath(checkout, mustWork = TRUE)
  if (is.null(python)) python <- unname(Sys.which("python3"))
  if (length(python) != 1L || !nzchar(python)) stop("An existing Python 3 executable is required.", call. = FALSE)
  rscript <- file.path(R.home("bin"), "Rscript")
  library <- paste(.libPaths(), collapse = .Platform$path.sep)
  args <- c(shQuote(file.path(checkout, "workbench", "open_results.py")), shQuote(root),
    "--rscript", shQuote(rscript), "--r-library", shQuote(library), if (!isTRUE(browse)) "--no-browser")
  response <- suppressWarnings(system2(python, args, stdout = TRUE, stderr = FALSE))
  if (!is.null(attr(response, "status")) && attr(response, "status") != 0L)
    stop("Result viewer failed to open. Inspect .workbench-launcher/server.log and verify the saved R library.", call. = FALSE)
  result <- jsonlite::fromJSON(paste(response, collapse = "\n"))
  dir.create(dirname(preferences), showWarnings = FALSE, mode = "0700")
  jsonlite::write_json(list(checkout = checkout), preferences, auto_unbox = TRUE)
  cat(result$url, "\n")
  invisible(result)
}
