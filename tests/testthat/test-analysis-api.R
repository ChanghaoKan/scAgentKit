ui_input <- function() {
  e <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = e)
  e$pbmc_small
}
ui_context <- function() list(species = "human", tissue = "Public PBMC software fixture",
  notes = "No donor/capture metadata or established identity is inferred.")
ui_plan <- function() list(rationale = "Reviewed software-control settings; not study recommendations.",
  analysis = list(nfeatures = 100L, npcs = 6L), pcs = 4L, diagnostic_resolutions = NULL, umap = FALSE)
ui_review <- function(...) {
  text <- capture.output(out <- sc_review(...))
  attr(out, "display") <- text
  out
}
ui_labels <- function(snapshot) {
  table <- snapshot$annotations
  for (i in seq_len(nrow(table))) {
    cl <- Filter(function(cl) identical(cl$clusterId, table$clusterId[[i]]), snapshot$view$evidence$clusters)[[1]]
    gene <- if (length(cl$markers)) cl$markers[[1]]$gene else ""
    table$label[[i]] <- if (nzchar(gene)) paste(gene, "enriched candidate") else "Unknown"
    table$confidence[[i]] <- "low"
    table$rationale[[i]] <- "Provisional expression description for software testing; no identity established."
    table$markers[[i]] <- gene
  }
  table[rev(seq_len(nrow(table))), , drop = FALSE]
}

test_that("high-level manual review binds drafts and preserves source and authority", {
  input <- ui_input(); before <- .sc_run_hash(input); root <- tempfile()
  x <- sc_analyze(input, root, ui_context(), plan = ui_plan())
  expect_identical(x$view$status, "awaiting_review")
  expect_error(sc_review(root, "approve", reviewer = "test", reason = "No displayed snapshot"), "snapshot")
  shown <- ui_review(x)
  expect_true(any(grepl("Strategy and local impact", attr(shown, "display"))))
  statefile <- file.path(root, "state.rds"); original <- .sc_project_sha_file(statefile)
  sc_open(root); sc_result_error <- try(sc_result(root), silent = TRUE)
  expect_s3_class(sc_result_error, "try-error")
  expect_identical(.sc_project_sha_file(statefile), original)
  rejected <- ui_review(shown, "reject", reviewer = "test", reason = "Review parameter choice first")
  expect_identical(rejected$view$status, "rejected")
  expect_null(.sc_run_load(root)$files$analysis)
  revised <- ui_review(rejected, "revise", plan = list(resolution = .4), reviewer = "test", reason = "Explicit resolution change")
  expect_identical(revised$plan$analysis, shown$plan$analysis)
  expect_identical(revised$plan$clustering$resolution, .4)
  expect_error(sc_review(shown, "approve", reviewer = "test", reason = "Stale"), "Stale")
  changed <- revised; changed$view$revision <- 0L
  expect_error(sc_review(changed, "approve", reviewer = "test", reason = "Edited"), "edited")
  ready <- ui_review(revised, "approve", reviewer = "test", reason = "Reviewed complete draft")
  bytes <- .sc_project_sha_file(statefile)
  expect_error(sc_review(revised, "approve", reviewer = "test", reason = "Double click", continue = TRUE), "Stale")
  expect_identical(.sc_project_sha_file(statefile), bytes)
  annotation <- suppressWarnings(ui_review(ready, "continue"))
  expect_identical(annotation$view$stage, "annotation_propose")
  expect_true(all(annotation$annotations$label == ""))
  expect_s4_class(sc_result(annotation, "analysis"), "Seurat")
  expect_error(sc_result(annotation), "until completion")
  blank <- annotation$annotations
  expect_error(ui_review(annotation, "revise", annotations = blank, reviewer = "test", reason = "Blank labels"))
  labels <- ui_labels(annotation)
  bad <- labels; bad$clusterId[1] <- "not-a-cluster"
  expect_error(ui_review(annotation, "revise", annotations = bad, reviewer = "test", reason = "Wrong scope"))
  file <- tempfile(fileext = ".tsv")
  utils::write.table(labels, file, sep = "\t", quote = TRUE, qmethod = "double", row.names = FALSE)
  proposed <- ui_review(annotation, "revise", annotations = file, reviewer = "test", reason = "Reviewed supplied markers")
  expect_true(any(grepl("supplied marker evidence", attr(proposed, "display"))))
  expect_error(ui_review(annotation, "revise", annotations = labels, reviewer = "test", reason = "Old evidence"), "Stale")
  done <- suppressWarnings(ui_review(proposed, "approve", reviewer = "test", reason = "Retain provisional descriptions", continue = TRUE))
  expect_identical(done$view$status, "complete")
  result <- sc_result(sc_open(root))
  expect_identical(colnames(result), colnames(input))
  expect_identical(.sc_run_hash(input), before)
  expect_identical(names(result$sc_annotation), colnames(input))
  expect_identical(unname(result$sc_annotation), unname(setNames(labels$label, labels$clusterId)[as.character(result$sc_strategy_clusters)]))
  expect_error(sc_review(proposed, "approve", reviewer = "test", reason = "Repeated finalize", continue = TRUE), "Stale")
  output <- done$view$output$seurat
  original <- readBin(output, "raw", n = file.info(output)$size)
  writeBin(c(original, as.raw(0)), output)
  expect_error(sc_result(done), "checkpoint changed")
  writeBin(original, output)
})

test_that("offline external callbacks preserve separate exact transfer consent and science", {
  input <- ui_input(); calls <- 0L
  callback <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    payload <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
    proposal <- if (grepl("strategy.v1", system_prompt, fixed = TRUE))
      .sc_ui_plan(ui_plan(), dimensions = dim(input), mad = payload$evidence$qc_mad) else
      list(schema = "scagentkit.annotation.v1", annotations = lapply(payload$evidence$clusters,
        function(cl) list(clusterId = cl$clusterId, label = "Unknown", confidence = "low",
          rationale = "Offline fixture abstention; no scientific identity claim.", markers = list())))
    list(content = as.character(jsonlite::toJSON(proposal, auto_unbox = TRUE, null = "null")),
      cost_usd = .0001, usage = list(input_tokens = 10, output_tokens = 10))
  }
  provider <- list(name = "custom", model = "offline-callback-only", external = TRUE, reservation_usd = .001)
  blocked <- sc_analyze(input, tempfile(), ui_context(), provider = provider, chat_fn = callback, budget = .01)
  expect_identical(blocked$view$status, "awaiting_configuration"); expect_identical(calls, 0L)
  x <- sc_analyze(input, tempfile(), ui_context(), provider = provider, chat_fn = callback,
    budget = .01, review = list(allow_external = TRUE))
  transfer <- ui_review(x)
  expect_identical(transfer$view$pending$kind, "external_transfer")
  expect_identical(calls, 0L)
  expect_error(sc_review(transfer, "approve", reviewer = "test", reason = "Payload only", continue = TRUE), "separate")
  approved <- ui_review(transfer, "approve", reviewer = "test", reason = "Reviewed exact offline payload")
  expect_identical(calls, 0L)
  expect_error(sc_review(transfer, "approve", reviewer = "test", reason = "Double consent"), "Stale")
  strategy <- ui_review(approved, "request", chat_fn = callback)
  expect_identical(calls, 1L)
  expect_identical(strategy$view$pending$kind, "strategy")
  expect_null(.sc_run_load(strategy$project_dir)$files$analysis)
  annotation <- suppressWarnings(ui_review(strategy, "approve", reviewer = "test", reason = "Reviewed strategy", continue = TRUE))
  expect_identical(calls, 1L)
  next_transfer <- ui_review(annotation, "request", chat_fn = callback)
  expect_identical(next_transfer$view$pending$kind, "external_transfer")
  expect_identical(calls, 1L)
  consent <- ui_review(next_transfer, "approve", reviewer = "test", reason = "Reviewed second payload")
  science <- ui_review(consent, "request", chat_fn = callback)
  expect_identical(calls, 2L)
  done <- suppressWarnings(ui_review(science, "approve", reviewer = "test", reason = "Keep unresolved fixture labels", continue = TRUE))
  expect_identical(done$view$status, "complete")
  expect_identical(calls, 2L)
  expect_true(all(sc_result(done)$sc_annotation == "Unknown"))
})

test_that("facade changes leave kernel fingerprint intact while real kernel changes invalidate", {
  before <- .sc_run_implementation()
  x <- sc_analyze(ui_input(), tempfile(), ui_context(), plan = ui_plan())
  shown <- ui_review(x)
  local_mocked_bindings(.sc_ui_plan = function(...) stop("changed adapter"), .package = "scAgentKit")
  expect_identical(.sc_run_implementation(), before)
  local_mocked_bindings(.sc_run_drive = function(...) stop("changed kernel"), .package = "scAgentKit")
  expect_false(identical(.sc_run_implementation(), before))
  expect_error(sc_review(shown, "approve", reviewer = "test", reason = "Cannot bypass upgrade"), "implementation changed")
})

test_that("annotation TSV preserves literal IDs and quoted study text across reordered rows", {
  input <- ui_input()
  input$seurat_clusters <- rep(c("01", "NA", "1e3"), length.out = ncol(input))
  root <- tempfile()
  suppressWarnings(sc_run(input, root, context = ui_context(), start_stage = "processed",
    processed_reason = "Reuse public fixture solely to test literal cluster IDs"))
  shown <- ui_review(sc_open(root))
  labels <- ui_labels(shown)
  labels$rationale <- paste(labels$rationale, 'quoted "text"', "tabs\tand\nnewlines; 中文")
  table <- tempfile(fileext = ".tsv")
  utils::write.table(labels, table, sep = "\t", quote = TRUE, qmethod = "double",
    row.names = FALSE, fileEncoding = "UTF-8")
  proposed <- ui_review(shown, "revise", annotations = table, reviewer = "test", reason = "Reviewed exact literal IDs")
  actual <- proposed$annotations
  expect_setequal(actual$clusterId, c("01", "NA", "1e3"))
  expect_identical(actual$rationale, labels$rationale[match(actual$clusterId, labels$clusterId)])
  missing <- labels[-1, ]
  expect_error(ui_review(proposed, "revise", annotations = missing, reviewer = "test", reason = "Missing scope"))
})

test_that("failed callbacks cannot be retried by opening or requesting again", {
  calls <- 0L
  callback <- function(system_prompt, user_prompt) {calls <<- calls + 1L; stop("Offline injected request failure")}
  x <- sc_analyze(ui_input(), tempfile(), ui_context(),
    provider = list(name = "mock", external = FALSE), chat_fn = callback)
  expect_identical(x$view$status, "failed"); expect_identical(calls, 1L)
  reopened <- sc_open(x); shown <- ui_review(reopened)
  expect_error(sc_review(shown, "request", chat_fn = callback), "nonfailed")
  expect_identical(calls, 1L)
  expect_identical(sc_open(x)$view$status, "failed")
})
