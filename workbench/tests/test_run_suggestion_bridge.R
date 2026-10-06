#!/usr/bin/env Rscript
# Pure IPC regression: mock the coordinator return, execute the production
# answer expression, and never load scAgentKit or run scientific computation.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Supply the production run_review_bridge.R path.")
bridge <- normalizePath(args[[1L]], mustWork = TRUE)
expressions <- parse(bridge)
is_answer <- function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
  identical(x[[2L]], as.name("answer"))
answer_expression <- Filter(is_answer, as.list(expressions))
stopifnot(length(answer_expression) == 1L)
replace_coordinator <- function(x) {
  if (missing(x)) return(quote(expr = ))
  if (is.call(x) && identical(x[[1L]], as.name("::")) &&
      identical(x[[2L]], as.name("scAgentKit")) && identical(x[[3L]], as.name("sc_run_suggest")))
    return(as.name("mock_suggest"))
  if (is.call(x)) {
    # [[<- NULL removes a call element and shifts subsequent indices. List
    # mapping preserves explicit NULL arguments and missing argument slots.
    return(as.call(lapply(as.list(x), replace_coordinator)))
  }
  x
}
production_answer <- replace_coordinator(answer_expression[[1L]])
request_file <- tempfile(fileext = ".json")
writeLines("{}", request_file)
suggestion <- list(schema = "scagentkit.run-suggestion.v1", project_id = "literal-project",
  input_hash = strrep("a", 64L), revision = 44L, suggestion_hash = strrep("b", 64L),
  status = "adopted", available = TRUE, can_adopt = FALSE, can_request = FALSE,
  preview = list(simulated = TRUE, provider = list(name = "mock", external = FALSE)),
  candidate = list(schema = "explicitly-simulated-typed-proposal"))
full_view <- list(schema = "scagentkit.run.v1", project_id = suggestion$project_id,
  input_hash = suggestion$input_hash, revision = suggestion$revision,
  status = "awaiting_review", suggestion = suggestion,
  scientific_evidence = list(markers = strrep("x", 5L * 1024L * 1024L)))
stopifnot(nchar(as.character(jsonlite::toJSON(full_view, auto_unbox = TRUE)), type = "bytes") > 4L * 1024L * 1024L)
run_answer <- function(view, operation = "suggestion_adopt") {
  environment <- new.env(parent = baseenv())
  environment$operation <- operation
  environment$project_dir <- "operator-selected-mock-project"
  environment$request_file <- request_file
  environment$mock_suggest <- function(...) view
  eval(production_answer, environment)
  environment$answer
}
answer <- run_answer(full_view)
stopifnot(isTRUE(answer$ok), identical(answer$result, suggestion), is.null(answer$error),
  nchar(as.character(jsonlite::toJSON(answer, auto_unbox = TRUE, null = "null")), type = "bytes") < 4L * 1024L * 1024L)
for (field in c("project_id", "input_hash", "revision")) {
  changed <- full_view
  changed$suggestion[[field]] <- if (field == "revision") 45L else "different-literal-binding"
  rejected <- run_answer(changed)
  stopifnot(identical(rejected$ok, FALSE), is.null(rejected$result),
    identical(rejected$error, "Suggestion coordinator rejected this action; inspect the saved state and exact preview binding."))
}
missing <- full_view
missing$suggestion <- NULL
stopifnot(identical(run_answer(missing)$ok, FALSE))
stopifnot(identical(run_answer(suggestion, "suggestion_preview")$result, suggestion))
unlink(request_file)
cat("PASS: >5 MiB full scientific view projects to bounded suggestion; exact project/input/revision guards and descriptor-only preview preserved. Mock coordinator only; no scientific R or API.\n")
