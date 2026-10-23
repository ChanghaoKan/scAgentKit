test_that("bounded loop produces tested citations and risk records without approval", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  out <- .sc_run_react_refine(f$root, f$baseline, react_mock())
  expect_identical(out$status, "completed")
  expect_equal(out$tool_calls, 2)
  expect_identical(out$completed, c("0", "1"))
  expect_identical(out$proposal$annotations[[1]]$markers, list("G31"))
  state <- .sc_run_load(f$root)
  expect_null(state$approved); expect_null(state$pending)
  trace <- readRDS(file.path(f$root, out$traces[["0"]]$path))
  expect_identical(trace$result$citations[[1]]$source, "tool:1")
  expect_length(trace$result$risk_flags$fields, 5)
  expect_identical(.sc_run_react_refine(f$root, f$baseline, function(...) stop("no repeat")), out)
})

test_that("unknown tools return errors for a bounded correction", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  out <- .sc_run_react_refine(f$root, f$baseline, react_mock("unknown_then_retry"))
  expect_identical(out$proposal$annotations[[1]]$label, "T cell")
  trace <- readRDS(file.path(f$root, out$traces[["0"]]$path))
  expect_false(trace$tools[[1]]$response$ok)
  expect_identical(trace$result$citations[[1]]$source, "tool:2")
})

test_that("invalid statistics and exhausted steps preserve baseline rows", {
  for (mode in c("invalid", "forever")) {
    f <- react_loop_fixture(list(mode = "all", max_steps_per_cluster = 2L))
    out <- .sc_run_react_refine(f$root, f$baseline, react_mock(mode))
    expect_identical(out$proposal, f$baseline)
    trace <- readRDS(file.path(f$root, out$traces[["0"]]$path))
    expect_identical(trace$status, "fallback")
    expect_identical(trace$fallback_reason, if (mode == "invalid") "invalid_draft" else "step_limit")
    unlink(f$root, recursive = TRUE)
  }
})

test_that("completed clusters are skipped after coordinator interruption", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  withr::local_options(scAgentKit.run_crash = "react:cluster")
  expect_error(.sc_run_react_refine(f$root, f$baseline, react_mock()), "Injected crash")
  options(scAgentKit.run_crash = NULL)
  next_call <- react_mock(); clusters <- character()
  out <- .sc_run_react_refine(f$root, f$baseline, function(messages, ...) {
    cluster <- jsonlite::fromJSON(messages[[2]]$content, simplifyVector = FALSE)$cluster_id
    clusters <<- c(clusters, cluster); next_call(messages, ...)
  })
  expect_true(all(clusters == "1"))
  expect_identical(out$completed, c("0", "1"))
})

test_that("manual label edits retain sources but deleted citations cannot be re-added", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  out <- .sc_run_react_refine(f$root, f$baseline, react_mock())
  state <- .sc_run_load(f$root)
  evidence <- .sc_run_react_review_evidence(f$root, state)
  edited <- out$proposal
  edited$annotations[[1]]$label <- "Lymphocyte"
  expect_silent(.sc_run_annotation_validate(edited, evidence))
  expect_identical(.sc_run_react_retain_citations(f$root, state, edited), state)
  removed <- edited
  removed$annotations[[1]]$label <- "Unknown"
  removed$annotations[[1]]$markers <- list()
  state <- .sc_run_react_retain_citations(f$root, state, removed)
  evidence <- .sc_run_react_review_evidence(f$root, state)
  expect_error(.sc_run_annotation_validate(edited, evidence), "absent")
  expect_silent(.sc_run_annotation_validate(removed, evidence))
})

test_that("missing baseline risk evidence is explicitly unassessed", {
  risks <- .sc_run_react_baseline_risk(list(baseline_risks = NULL), "0")
  expect_identical(risks, .sc_run_react_unassessed_risks("0"))
  expect_identical(risks$cluster_id, "0")
  values <- stats::setNames(vapply(risks$fields, `[[`, character(1), "value"),
    vapply(risks$fields, `[[`, character(1), "name"))
  expect_identical(values[["batch_status"]], "insufficient_evidence")
  expect_true(all(values[setdiff(names(values), "batch_status")] == "not_assessed"))
  expect_true(all(vapply(risks$fields, function(field)
    identical(field$assessment_status, "not_assessed") &&
      identical(field$source, "unassessed") && identical(field$evidence_ids, list()), logical(1))))
  expect_error(.sc_run_react_risks(risks, "0", character()), class = "sc_run_react_error")

  model_risks <- react_final("0")$risk_flags
  expect_identical(.sc_run_react_baseline_risk(
    list(baseline_risks = list(risk_flags = list(model_risks))), "0"), model_risks)
})

test_that("model risk records reject local provenance", {
  risks <- react_final("0")$risk_flags
  expect_silent(.sc_run_react_risks(risks, "0", character()))
  for (source in c("unassessed", "rule", "human")) {
    risks$fields[[1L]]$source <- source
    expect_error(.sc_run_react_risks(risks, "0", character()), class = "sc_run_react_error")
  }
})

test_that("risk enums require all fields and matching current evidence", {
  risks <- react_final("0")$risk_flags
  expect_silent(.sc_run_react_risks(risks, "0", "tool:1"))
  risks$fields[[1]]$value <- "suspected"
  expect_error(.sc_run_react_risks(risks, "0", "tool:1"), class = "sc_run_react_error")
  risks$fields[[1]]$assessment_status <- "assessed"
  risks$fields[[1]]$evidence_ids <- list("tool:1")
  expect_silent(.sc_run_react_risks(risks, "0", "tool:1"))
  expect_error(.sc_run_react_risks(risks, "1", "tool:1"), class = "sc_run_react_error")
  expect_error(.sc_run_react_risks(risks, "0", "tool:2"), class = "sc_run_react_error")
  risks$fields <- risks$fields[-1]
  expect_error(.sc_run_react_risks(risks, "0", "tool:1"), class = "sc_run_react_error")
})

test_that("baseline outer risk envelope preserves the annotation schema", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  evidence <- .sc_run_get(f$root, .sc_run_load(f$root), "annotation_evidence")
  outer <- list(schema = "scagentkit.annotation-draft.v1", proposal = f$baseline,
    risk_flags = lapply(c("0", "1"), function(cluster) react_final(cluster)$risk_flags))
  expect_identical(.sc_run_react_baseline(outer, evidence)$proposal, f$baseline)
  outer$risk_flags[[2]]$cluster_id <- "0"
  expect_error(.sc_run_react_baseline(outer, evidence), class = "sc_run_react_error")
})

test_that("coordinator stages a mock ReAct draft with baseline risks and no approval", {
  data("pbmc_small", package = "SeuratObject", envir = environment())
  pbmc_small$seurat_clusters <- as.character(SeuratObject::Idents(pbmc_small))
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  baseline_fn <- function(system_prompt, user_prompt) {
    evidence <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)$evidence
    ids <- vapply(evidence$clusters, `[[`, character(1), "clusterId")
    proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(ids,
      function(id) list(clusterId = id, label = "Unknown", confidence = "low",
        rationale = "Synthetic baseline control.", markers = list())))
    .sc_project_json(list(schema = "scagentkit.annotation-draft.v1", proposal = proposal,
      risk_flags = lapply(ids, function(id) react_final(id)$risk_flags)))
  }
  out <- suppressWarnings(sc_run(pbmc_small, root, provider = "mock", chat_fn = baseline_fn,
    context = list(species = "human", tissue = "blood"), start_stage = "processed",
    processed_reason = "Public software fixture; not biological validation.", react = list(mode = "all")))
  expect_identical(out$status, "awaiting_review", info = out$failure$message)
  state <- .sc_run_load(root)
  expect_identical(state$pending$kind, "annotation")
  expect_null(state$approved)
  expect_false(is.null(state$files$annotation_baseline_risks))
  run <- .sc_run_get(root, state, "annotation_react_run")
  expect_identical(run$status, "completed")
  expect_equal(run$tool_calls, 3)
  expect_silent(.sc_run_annotation_review_verify(root, state))
})

test_that("a durable tool turn resumes without repeating its provider request", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  withr::local_options(scAgentKit.run_crash = "react:turn")
  expect_error(.sc_run_react_refine(f$root, f$baseline, react_mock()), "Injected crash")
  options(scAgentKit.run_crash = NULL)
  calls <- list(); next_call <- react_mock()
  out <- .sc_run_react_refine(f$root, f$baseline, function(messages, ...) {
    calls[[length(calls) + 1L]] <<- messages
    next_call(messages, ...)
  })
  expect_identical(out$status, "completed")
  expect_identical(tail(calls[[1]], 1L)[[1]]$role, "tool")
  expect_length(calls, 3L)
})

test_that("provider delivery uncertainty falls back and cannot auto resend", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  count <- 0L
  uncertain <- function(...) {
    count <<- count + 1L
    stop(structure(list(message = "Delivery is unknown", call = NULL,
      code = "transport_error", delivery = "unknown"),
      class = c("agentomics_turn_error", "error", "condition")))
  }
  out <- .sc_run_react_refine(f$root, f$baseline, uncertain)
  expect_identical(out$proposal, f$baseline)
  before <- count
  expect_identical(.sc_run_react_refine(f$root, f$baseline, uncertain), out)
  expect_identical(count, before)
  trace <- readRDS(file.path(f$root, out$traces[["0"]]$path))
  expect_identical(trace$status, "fallback")
  expect_identical(trace$turns[[1]]$delivery, "unknown")
})

test_that("late responses cannot become drafts and disabled mode makes no calls", {
  f <- react_loop_fixture(list(mode = "all", cluster_timeout_seconds = 1))
  on.exit(unlink(f$root, recursive = TRUE))
  out <- .sc_run_react_refine(f$root, f$baseline, function(...) {
    Sys.sleep(1.1); turn_reply()
  })
  expect_identical(out$proposal, f$baseline)
  trace <- readRDS(file.path(f$root, out$traces[["0"]]$path))
  expect_identical(trace$fallback_reason, "cluster_timeout")
  off <- react_loop_fixture(list(mode = "off")); on.exit(unlink(off$root, recursive = TRUE), add = TRUE)
  out <- .sc_run_react_refine(off$root, off$baseline, function(...) stop("must not send"))
  expect_identical(out$proposal, off$baseline)
  expect_identical(out$tool_calls, 0L)
  expect_length(out$targets, 0L)
})

test_that("missing baselines are explicit and scientific changes block recovery", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  expect_identical(.sc_run_react_refine(f$root, NULL)$status, "baseline_unavailable")
  .sc_run_react_refine(f$root, f$baseline, react_mock())
  state <- .sc_run_load(f$root)
  path <- file.path(f$root, state$files$analysis$path)
  cat("changed", file = path, append = TRUE)
  expect_error(.sc_run_react_refine(f$root, f$baseline, react_mock()))
})

test_that("outside-pool support cannot be borrowed, fabricated or supplied by expression", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  run <- .sc_run_react_refine(f$root, f$baseline, react_mock())
  trace <- readRDS(file.path(f$root, run$traces[["0"]]$path))
  evidence <- .sc_run_get(f$root, .sc_run_load(f$root), "annotation_evidence")
  check <- function(value = react_final("0"), t = trace) .sc_run_react_validate(
    value, f$baseline, evidence, "0", t, run$session)
  expect_silent(check())
  fabricated <- react_final("0"); fabricated$citations[[1]]$avg_log2FC <- 999
  expect_error(check(fabricated), class = "sc_run_react_error")
  foreign <- trace; foreign$session_id <- "another-session"
  expect_error(check(t = foreign), class = "sc_run_react_error")
  foreign <- trace; foreign$tools[[1]]$response$arguments$cluster_id <- "1"
  expect_error(check(t = foreign), class = "sc_run_react_error")
  expression <- trace; expression$tools[[1]]$response$tool <- "gene_expression"
  expect_error(check(t = expression), class = "sc_run_react_error")
  altered <- trace
  altered$tools[[1]]$response$result$markers[[1]]$avg_log2FC <- 999
  expect_error(check(t = altered), class = "sc_run_react_error")
})

test_that("ACT ablation hides product reference evidence and automatic triggering", {
  f <- react_loop_fixture(list(mode = "auto", act_enabled = FALSE))
  on.exit(unlink(f$root, recursive = TRUE))
  state <- .sc_run_load(f$root)
  evidence <- .sc_run_react_review_evidence(f$root, state)
  expect_null(evidence$private$candidates)
  expect_identical(evidence$private$reference_evidence$per_cluster[[1]]$status, "unassessed")
  expect_false("act_lookup" %in% unlist(state$config$react$tools))
  baseline <- f$baseline
  baseline$annotations <- lapply(baseline$annotations, function(row) {
    row$label <- "T cell"; row$confidence <- "high"; row
  })
  expect_length(.sc_run_react_targets(baseline, evidence, state$config$react, NULL), 0L)
})

test_that("strict sessions persist the exact unsent payload for explicit approval", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  state <- .sc_run_load(f$root)
  state$config$provider <- .sc_run_provider_spec("deepseek")$metadata
  state$config$review <- list(allow_external = TRUE)
  state$config_hash <- .sc_run_hash(state$config)
  .sc_run_save(f$root, state)
  count <- 0L
  fn <- function(...) { count <<- count + 1L; react_mock()(...) }
  run <- .sc_run_react_refine(f$root, f$baseline, fn)
  expect_identical(run$status, "awaiting_external_approval")
  expect_identical(count, 0L)
  trace <- readRDS(file.path(f$root, run$traces[["0"]]$path))
  request <- trace$pending_request
  expect_true(is.list(request))
  turn_approve_fixture(f$root, request, "fixture-reviewer", "Exact synthetic payload reviewed.",
    .sc_run_load(f$root)$revision)
  run <- .sc_run_react_refine(f$root, f$baseline, fn)
  expect_identical(count, 1L)
  expect_identical(run$status, "awaiting_external_approval")
  trace <- readRDS(file.path(f$root, run$traces[["0"]]$path))
  expect_length(trace$tools, 1L)
  expect_identical(trace$pending_request$ordinal, 2L)
})

test_that("illegal tool arguments can be corrected in a subsequent bounded turn", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  next_call <- react_mock("unknown_then_retry")
  out <- .sc_run_react_refine(f$root, f$baseline, function(messages, ...) {
    reply <- next_call(messages, ...)
    if (identical(reply$message$tool_calls[[1]]$`function`$name, "unknown_tool")) {
      reply$message$tool_calls[[1]]$`function`$name <- "cluster_markers"
      cluster <- jsonlite::fromJSON(messages[[2]]$content, simplifyVector = FALSE)$cluster_id
      reply$message$tool_calls[[1]]$`function`$arguments <- .sc_project_json(list(cluster_id = cluster, n = 51L))
    }
    reply
  })
  trace <- readRDS(file.path(f$root, out$traces[["0"]]$path))
  expect_identical(trace$tools[[1]]$response$error$code, "invalid_arguments")
  expect_identical(trace$status, "completed")
  expect_identical(trace$result$citations[[1]]$source, "tool:2")
})

test_that("the total session turn limit preserves later baseline clusters", {
  f <- react_loop_fixture(list(mode = "all", max_steps = 2L, max_steps_per_cluster = 2L))
  on.exit(unlink(f$root, recursive = TRUE))
  out <- .sc_run_react_refine(f$root, f$baseline, react_mock())
  first <- readRDS(file.path(f$root, out$traces[["0"]]$path))
  second <- readRDS(file.path(f$root, out$traces[["1"]]$path))
  expect_identical(first$status, "completed")
  expect_identical(second$fallback_reason, "step_limit")
  expect_identical(second$result$row, f$baseline$annotations[[2]])
  expect_length(second$turns, 0L)
})
