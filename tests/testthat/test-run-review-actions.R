# Independent acceptance fixtures for the unified durable review actions.
review_actions_fixture <- function() {
  set.seed(912)
  cells <- c("001", "1", "NA", "cell space", paste0("cell-", 5:32))
  counts <- matrix(stats::rpois(24 * 32, 2), nrow = 24,
    dimnames = list(c("MARK-A", "MARK-B", "MARK-C", "MARK-D", paste0("Gene", 5:24)), cells))
  counts[1:2, 1:16] <- counts[1:2, 1:16] + 30L
  counts[3:4, 17:32] <- counts[3:4, 17:32] + 30L
  counts <- Matrix::Matrix(counts, sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- log1p(counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <- counts * 2
  object$chosen_cluster <- factor(rep(c("001", "1"), each = 16), levels = c("001", "1", "unused"))
  object$condition <- rep(c("Ca", "Ctrl"), 16)
  object$old_annotation <- factor(c(NA, rep("old program A", 15), rep("old program B", 16)),
    levels = c("old program A", "old program B", "unused"))
  object[["literal old column"]] <- paste0("prior ", seq_len(32))
  object
}

review_actions_unknown <- function(evidence) {
  list(schema = "scagentkit.annotation.v1", annotations = lapply(evidence$clusters, function(row)
    list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
      rationale = "The synthetic type has not been scientifically accepted.", markers = list())))
}

review_actions_coarse <- function(evidence) {
  value <- review_actions_unknown(evidence)
  first <- evidence$clusters[[1]]
  stopifnot(length(first$markers) > 0)
  value$annotations[[1]] <- list(clusterId = first$clusterId, label = "Program-positive cells",
    confidence = "medium", rationale = "A coarse synthetic program label is supported by the supplied marker.",
    markers = list(first$markers[[1]]$gene))
  value
}

review_actions_begin <- function(path, input = review_actions_fixture(), counter = NULL) {
  provider <- chat <- NULL
  if (!is.null(counter)) {
    counter$calls <- 0L
    provider <- list(name = "mock", external = FALSE)
    chat <- function(system_prompt, user_prompt) {
      counter$calls <- counter$calls + 1L
      evidence <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)$evidence
      as.character(jsonlite::toJSON(review_actions_unknown(evidence), auto_unbox = TRUE, null = "null"))
    }
  }
  out <- suppressWarnings(sc_run(input, path, context = list(species = "human", tissue = "synthetic QA"),
    provider = provider, chat_fn = chat, start_stage = "processed",
    processed_reason = "Synthetic sparse normalized layers and exact externally supplied clusters.",
    cluster_column = "chosen_cluster", annotation_column = "reviewed_type"))
  if (is.null(counter)) {
    stopifnot(identical(out$status, "awaiting_configuration"))
    evidence <- sc_run_inspect(path)$evidence
    sc_run_propose(path, review_actions_unknown(evidence), "offline QA", "Initial explicit Unknown proposal.")
  }
  sc_run_inspect(path)
}

review_actions_payload <- function(path, action, snapshot = sc_run_inspect(path), reason = "Offline synthetic acceptance.") {
  node <- snapshot$review_node
  list(project_dir = path, action = action, kind = node$kind, project_id = snapshot$project_id,
    input_hash = snapshot$input_hash, proposal_hash = node$proposal_hash, review_hash = node$review_hash,
    expected_revision = node$expected_revision, reviewer = "offline QA", reason = reason)
}

review_actions_submit <- function(path, action, snapshot = sc_run_inspect(path),
                                    reason = "Offline synthetic acceptance.", ...) {
  values <- review_actions_payload(path, action, snapshot, reason)
  extras <- list(...)
  for (field in names(extras)) values[field] <- extras[field]
  do.call(sc_run_review, values)
}

review_actions_files <- function(path) {
  files <- sort(list.files(path, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  files <- files[!dir.exists(files)]
  stats::setNames(vapply(files, .sc_project_sha_file, character(1)), substring(files, nchar(path) + 2L))
}

review_actions_complete <- function(path, input = review_actions_fixture()) {
  initial <- review_actions_begin(path, input)
  review_actions_submit(path, "revise", initial, proposal = review_actions_coarse(initial$evidence))
  current <- sc_run_inspect(path)
  review_actions_submit(path, "approve", current)
  out <- suppressWarnings(sc_run_resume(path))
  stopifnot(identical(out$status, "complete"))
  sc_run_inspect(path)
}

test_that("annotation inspection binds exact literal scope and supplied evidence without writing", {
  path <- tempfile(); object <- review_actions_fixture(); before <- .sc_run_hash(object)
  status <- review_actions_begin(path, object)
  expect_identical(status$status, "awaiting_review")
  expect_identical(status$pending$kind, "annotation")
  expect_identical(status$review_node$kind, "annotation")
  expect_identical(status$review_node$proposal_hash, status$pending$hash)
  expect_identical(status$review_node$review_hash, status$annotation_review$hash)
  expect_equal(status$review_node$expected_revision, status$revision)
  expect_false(status$review_node$can_undo)
  expect_identical(status$annotation_review$details$input_cells$cell_id, colnames(object))
  expect_identical(status$annotation_review$details$input_cells$cluster, as.character(object$chosen_cluster))
  expect_identical(vapply(status$annotation_review$details$annotations, `[[`, character(1), "clusterId"), c("001", "1"))
  expect_equal(status$annotation_review$details$cell_count, 32)
  expect_equal(status$annotation_review$details$cluster_count, 2)
  expect_null(.sc_run_load(path)$files$annotated)
  expect_identical(.sc_run_hash(object), before)
  snapshot <- review_actions_files(path)
  expect_identical(sc_run_inspect(path), status)
  expect_identical(sc_run_resume(path)$status, "awaiting_review")
  expect_identical(review_actions_files(path), snapshot)
  expect_false(dir.exists(file.path(path, "provider")))
})

test_that("project kind input proposal review and revision must all match before any action", {
  path <- tempfile(); status <- review_actions_begin(path); before <- review_actions_files(path)
  invalid <- list(list(project_id = "another-project"), list(input_hash = strrep("0", 64)),
    list(kind = "qc"), list(proposal_hash = strrep("0", 64)), list(review_hash = strrep("0", 64)),
    list(expected_revision = status$revision + 1L))
  for (overrides in invalid) {
    payload <- review_actions_payload(path, "approve", status)
    for (field in names(overrides)) payload[field] <- overrides[field]
    expect_error(do.call(sc_run_review, payload), "[Pp]roject|[Ii]nput|[Kk]ind|[Ss]tale|[Rr]eview|[Rr]evision|[Mm]ismatch")
    expect_identical(review_actions_files(path), before)
  }
  other <- tempfile(); review_actions_begin(other); other_before <- review_actions_files(other)
  payload <- review_actions_payload(other, "approve", status)
  expect_error(do.call(sc_run_review, payload), "[Pp]roject|[Ii]nput|[Ss]tale|[Mm]ismatch")
  expect_identical(review_actions_files(other), other_before)
  for (action in c("resume", "execute_R", "dispatch_provider")) {
    expect_error(review_actions_submit(path, action, status), "[Uu]nsupported|action")
    expect_identical(review_actions_files(path), before)
  }
})

test_that("the generic QC route retains preview binding and never applies a revised preapproved rule", {
  path <- tempfile(); input <- review_actions_fixture(); before <- .sc_run_hash(input)
  rule <- function(minimum) list(schema = "scagentkit.qc.v1", rationale = "Synthetic count-positive acceptance only.",
    risks = list("These thresholds are not biologically validated."),
    filters = list(list(op = "range", metric = "nCount", min = minimum)))
  sc_run(input, path, context = list(species = "human", tissue = "synthetic QA"),
    qc_proposal = rule(1), review = list(preapprove_qc = rule(2)), analysis = list(run_umap = FALSE))
  old <- sc_run_inspect(path)
  expect_identical(old$review_node$kind, "qc")
  expect_identical(old$review_node$review_hash, old$qc_preview$hash)
  expect_null(old$annotation_review)
  previewed <- review_actions_submit(path, "preview", old,
    gene_panels = list(availability = c("MARK-A", "UNAVAILABLE-GENE")))
  expect_identical(previewed$status, "awaiting_review")
  expect_false(identical(previewed$review_node$review_hash, old$review_node$review_hash))
  expect_error(review_actions_submit(path, "approve", old), "[Ss]tale|[Rr]evision|[Rr]eview")
  revised <- review_actions_submit(path, "revise", previewed, proposal = rule(2))
  expect_identical(revised$status, "awaiting_review")
  expect_identical(revised$stage, "qc_propose")
  expect_null(.sc_run_load(path)$files$qc_object)
  expect_null(.sc_run_load(path)$files$analysis)
  expect_length(.sc_run_load(path)$approvals, 0)
  ready <- review_actions_submit(path, "approve", revised)
  expect_identical(ready$stage, "qc_apply")
  expect_null(.sc_run_load(path)$files$qc_object)
  previous <- getOption("scAgentKit.run_crash"); on.exit(options(scAgentKit.run_crash = previous), add = TRUE)
  options(scAgentKit.run_crash = "qc_apply:checkpoint")
  resumed <- sc_run_resume(path)
  expect_identical(resumed$stage, "analysis")
  state <- .sc_run_load(path)
  expect_identical(colnames(.sc_run_get(path, state, "qc_object")), revised$qc_preview$details$keep_cells)
  expect_null(state$files$analysis)
  expect_identical(.sc_run_hash(input), before)
  expect_false(dir.exists(file.path(path, "provider")))
})

test_that("coarse and Unknown revision creates a fresh snapshot and cannot silently drive", {
  path <- tempfile(); counter <- new.env(); input <- review_actions_fixture(); before <- .sc_run_hash(input)
  old <- review_actions_begin(path, input, counter); expect_equal(counter$calls, 1)
  history_before <- length(.sc_run_load(path)$history)
  proposal <- review_actions_coarse(old$evidence)
  revised <- review_actions_submit(path, "revise", old,
    reason = "Use a coarse program label and explicit Unknown without subtype overclaim.", proposal = proposal)
  expect_identical(revised$status, "awaiting_review")
  expect_identical(revised$stage, "annotation_propose")
  expect_false(identical(revised$review_node$proposal_hash, old$review_node$proposal_hash))
  expect_false(identical(revised$review_node$review_hash, old$review_node$review_hash))
  expect_identical(revised$annotation_review$details$canonical_proposal, proposal)
  state <- .sc_run_load(path)
  events <- state$history[seq.int(history_before + 1L, length(state$history))]
  expect_false(any(vapply(events, function(e) e$action %in% c("running", "executed", "approved", "proposal_received"), logical(1))))
  expect_true(any(vapply(events, function(e) identical(e$details$reason,
    "Use a coarse program label and explicit Unknown without subtype overclaim."), logical(1))))
  expect_null(state$approved)
  expect_null(state$files$annotated)
  expect_equal(counter$calls, 1)
  expect_identical(.sc_run_hash(input), before)
  snapshot <- review_actions_files(path)
  expect_error(review_actions_submit(path, "approve", old), "[Ss]tale|[Rr]evision|[Rr]eview")
  expect_identical(sc_run_resume(path)$status, "awaiting_review")
  expect_identical(review_actions_files(path), snapshot)
  expect_equal(counter$calls, 1)
})

test_that("typed revisions reject missing foreign duplicate and hallucinated annotation scope", {
  path <- tempfile(); status <- review_actions_begin(path); proposal <- review_actions_coarse(status$evidence)
  before <- review_actions_files(path)
  invalid <- list()
  invalid[[1]] <- proposal; invalid[[1]]$annotations <- proposal$annotations[1]
  invalid[[2]] <- proposal; invalid[[2]]$annotations[[1]]$clusterId <- "foreign cluster"
  invalid[[3]] <- proposal; invalid[[3]]$annotations[[2]] <- proposal$annotations[[1]]
  invalid[[4]] <- proposal; invalid[[4]]$annotations[[1]]$markers <- list("HALLUCINATED-GENE")
  invalid[[5]] <- proposal; invalid[[5]]$annotations[[1]]$code <- "system('unsupported')"
  invalid[[6]] <- proposal; invalid[[6]]$execute <- "arbitrary R"
  invalid[[7]] <- proposal; invalid[[7]]$annotations[[1]]$markers <- list()
  invalid[[8]] <- proposal; invalid[[8]]$annotations[[1]]$confidence <- "certain"
  other <- status$evidence$clusters[[2]]$markers
  own_genes <- vapply(status$evidence$clusters[[1]]$markers, `[[`, character(1), "gene")
  other_genes <- setdiff(vapply(other, `[[`, character(1), "gene"), own_genes)
  expect_gt(length(other_genes), 0)
  invalid[[9]] <- proposal; invalid[[9]]$annotations[[1]]$markers <- list(other_genes[[1]])
  for (bad in invalid) {
    expect_error(review_actions_submit(path, "revise", status, proposal = bad))
    expect_identical(review_actions_files(path), before)
  }
  expect_error(review_actions_submit(path, "approve", status, proposal = proposal), "[Cc]annot|[Pp]arameter|[Pp]roposal|[Ss]ilent")
  expect_identical(review_actions_files(path), before)
})

test_that("approve and reject are idempotent decisions and never write annotations", {
  path <- tempfile(); status <- review_actions_begin(path)
  ready <- review_actions_submit(path, "approve", status)
  expect_identical(ready$status, "ready")
  expect_identical(ready$stage, "annotation_apply")
  expect_null(.sc_run_load(path)$files$annotated)
  snapshot <- review_actions_files(path)
  expect_identical(review_actions_submit(path, "approve", status)$status, "ready")
  expect_identical(review_actions_files(path), snapshot)
  approvals <- Filter(function(e) e$action == "approved" && e$details$kind == "annotation", .sc_run_load(path)$history)
  expect_length(approvals, 1)
  expect_identical(approvals[[1]]$details$review_hash, status$review_node$review_hash)
  path <- tempfile(); status <- review_actions_begin(path)
  rejected <- review_actions_submit(path, "reject", status, reason = "Synthetic rejection acceptance.")
  expect_identical(rejected$status, "rejected")
  snapshot <- review_actions_files(path)
  expect_identical(review_actions_submit(path, "reject", status)$status, "rejected")
  expect_identical(review_actions_files(path), snapshot)
  expect_identical(sc_run_resume(path)$status, "rejected")
  expect_null(.sc_run_load(path)$files$annotated)
  expect_identical(review_actions_files(path), snapshot)
})

test_that("one project lock covers generic decisions revisions and undo", {
  path <- tempfile(); status <- review_actions_begin(path); before <- review_actions_files(path)
  owner <- .sc_run_lock(path); on.exit(.sc_run_release(path, owner), add = TRUE)
  expect_error(review_actions_submit(path, "approve", status), "locked")
  expect_error(review_actions_submit(path, "revise", status, proposal = review_actions_coarse(status$evidence)), "locked")
  expect_error(review_actions_submit(path, "reject", status), "locked")
  .sc_run_release(path, owner)
  expect_identical(review_actions_files(path), before)
  done <- review_actions_complete(tempfile())
  complete_path <- dirname(dirname(done$output$seurat)); before <- review_actions_files(complete_path)
  owner <- .sc_run_lock(complete_path); on.exit(.sc_run_release(complete_path, owner), add = TRUE)
  expect_error(review_actions_submit(complete_path, "undo", done, decision_id = done$review_node$decision_id), "locked")
  .sc_run_release(complete_path, owner)
  expect_identical(review_actions_files(complete_path), before)
})

test_that("approved annotation resumes in a new process with exact ID scope and unchanged source layers", {
  path <- tempfile(); source <- tempfile(fileext = ".rds"); input <- review_actions_fixture(); saveRDS(input, source)
  source_hash <- .sc_project_sha_file(source)
  initial <- review_actions_begin(path, source)
  review_actions_submit(path, "revise", initial, proposal = review_actions_coarse(initial$evidence))
  status <- sc_run_inspect(path)
  arguments <- tempfile(fileext = ".rds"); script <- tempfile(fileext = ".R")
  result <- tempfile(fileext = ".rds"); stdout <- tempfile(fileext = ".log")
  on.exit(unlink(c(arguments, script, result, stdout)), add = TRUE)
  saveRDS(list(path = path, payload = review_actions_payload(path, "approve", status), result = result,
    libraries = .libPaths(), package = getNamespaceInfo(asNamespace("scAgentKit"), "path")), arguments)
  writeLines(c(
    "Sys.unsetenv(c('DEEPSEEK_API_KEY', 'XAI_API_KEY', 'OPENAI_API_KEY'))",
    "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "if (file.exists(file.path(args$package, 'R', 'run.R'))) pkgload::load_all(args$package, quiet=TRUE, helpers=FALSE) else library(scAgentKit, lib.loc=dirname(args$package))",
    "do.call(sc_run_review, args$payload)",
    "saveRDS(suppressWarnings(sc_run_resume(args$path)), args$result)"
  ), script)
  code <- system2(file.path(R.home('bin'), 'Rscript'), c('--vanilla', shQuote(script), shQuote(arguments)), stdout = stdout, stderr = stdout)
  expect_identical(as.integer(code), 0L, info = paste(readLines(stdout, warn = FALSE), collapse = '\n'))
  if (!identical(as.integer(code), 0L)) return(invisible(NULL))
  complete <- readRDS(result); expect_identical(complete$status, "complete")
  object <- readRDS(complete$output$seurat)
  expect_identical(colnames(object), colnames(input))
  expect_identical(object$chosen_cluster, input$chosen_cluster)
  expect_identical(object$old_annotation, input$old_annotation)
  expect_identical(object[["literal old column"]], input[["literal old column"]])
  expect_identical(object$condition, input$condition)
  expect_identical(SeuratObject::Layers(object[["RNA"]]), SeuratObject::Layers(input[["RNA"]]))
  for (layer in SeuratObject::Layers(input[["RNA"]]))
    expect_identical(SeuratObject::LayerData(object, assay = "RNA", layer = layer), SeuratObject::LayerData(input, assay = "RNA", layer = layer))
  expected_labels <- stats::setNames(ifelse(as.character(input$chosen_cluster) == "001", "Program-positive cells", "Unknown"), colnames(input))
  expect_identical(object$reviewed_type, expected_labels)
  expect_identical(.sc_project_sha_file(source), source_hash)
  expect_identical(readRDS(source), input)
  snapshot <- review_actions_files(path)
  expect_identical(sc_run_resume(path)$status, "complete")
  expect_identical(review_actions_files(path), snapshot)
  expect_false(dir.exists(file.path(path, "provider")))
})

test_that("review evidence source and exact annotation scope edits fail closed", {
  path <- tempfile(); status <- review_actions_begin(path); state <- .sc_run_load(path)
  file <- file.path(path, state$files$annotation_review$path); record <- readRDS(file)
  record$details$input_cells$cluster[1] <- "1"; saveRDS(record, file)
  expect_error(review_actions_submit(path, "approve", status), "changed|checksum|[Ss]tale|[Rr]eview")
  path <- tempfile(); source <- tempfile(fileext = ".rds"); input <- review_actions_fixture(); saveRDS(input, source)
  status <- review_actions_begin(path, source); review_actions_submit(path, "approve", status)
  input$chosen_cluster[1] <- "1"; saveRDS(input, source)
  expect_error(sc_run_resume(path), "Original input RDS changed")
  path <- tempfile(); status <- review_actions_begin(path); review_actions_submit(path, "approve", status)
  state <- .sc_run_load(path); file <- file.path(path, state$files$analysis$path); input <- readRDS(file)
  input$chosen_cluster[1] <- "1"; saveRDS(input, file)
  expect_error(sc_run_resume(path), "changed")
})

test_that("undo binds an executed decision archives its object and cannot reactivate old approval", {
  path <- tempfile(); input <- review_actions_fixture(); complete <- review_actions_complete(path, input)
  expect_true(complete$review_node$can_undo)
  expect_match(complete$review_node$decision_id, "^decision-")
  old_output_hash <- .sc_project_sha_file(complete$output$seurat); before <- review_actions_files(path)
  expect_error(review_actions_submit(path, "undo", complete, decision_id = "wrong-decision"), "[Dd]ecision|[Ss]tale|[Ee]xecuted|[Uu]ndo")
  expect_identical(review_actions_files(path), before)
  undone <- review_actions_submit(path, "undo", complete,
    reason = "Review the scientific uncertainty again.", decision_id = complete$review_node$decision_id)
  expect_identical(undone$status, "awaiting_configuration")
  expect_identical(undone$stage, "annotation_propose")
  expect_false(undone$review_node$can_undo)
  state <- .sc_run_load(path)
  expect_null(state$files$annotated)
  expect_null(state$files$annotation_validated)
  expect_null(state$output)
  expect_false("annotation_apply" %in% state$completed)
  versions <- list.files(file.path(path, "versions"), pattern = "seurat\\.rds$", recursive = TRUE, full.names = TRUE)
  expect_length(versions, 1)
  expect_identical(.sc_project_sha_file(versions[[1]]), old_output_hash)
  snapshot <- review_actions_files(path)
  expect_error(review_actions_submit(path, "approve", complete), "[Ss]tale|[Rr]evision|[Rr]eview|[Uu]ndo|[Nn]o current")
  tryCatch(review_actions_submit(path, "undo", complete, decision_id = complete$review_node$decision_id), error = function(e) invisible(NULL))
  expect_identical(review_actions_files(path), snapshot)
  expect_length(Filter(function(e) e$action == "annotation_undone", .sc_run_load(path)$history), 1)
  current <- sc_run_inspect(path)
  fresh <- review_actions_submit(path, "revise", current, proposal = review_actions_unknown(current$evidence),
    reason = "Fresh explicit Unknown proposal after undo.")
  expect_identical(fresh$status, "awaiting_review")
  expect_false(identical(fresh$review_node$proposal_hash, complete$review_node$proposal_hash))
  expect_null(.sc_run_load(path)$files$annotated)
  expect_identical(.sc_run_get(path, .sc_run_load(path), "analysis"), input)
})

test_that("mock provider is not dispatched by generic revision approval reject or undo", {
  path <- tempfile(); counter <- new.env(); initial <- review_actions_begin(path, counter = counter)
  expect_equal(counter$calls, 1)
  review_actions_submit(path, "revise", initial, proposal = review_actions_coarse(initial$evidence))
  current <- sc_run_inspect(path); review_actions_submit(path, "approve", current)
  expect_equal(counter$calls, 1)
  expect_null(.sc_run_load(path)$files$annotated)
  complete <- suppressWarnings(sc_run_resume(path)); expect_identical(complete$status, "complete")
  complete <- sc_run_inspect(path)
  review_actions_submit(path, "undo", complete, decision_id = complete$review_node$decision_id)
  expect_equal(counter$calls, 1)
  current <- sc_run_inspect(path)
  review_actions_submit(path, "revise", current, proposal = review_actions_unknown(current$evidence))
  current <- sc_run_inspect(path); review_actions_submit(path, "reject", current)
  expect_equal(counter$calls, 1)
  expect_null(.sc_run_load(path)$files$annotated)
})

test_that("undo archive and checkpoint interruption retain recoverable single-decision state", {
  for (point in c("undo:archive", "undo:checkpoint")) {
    path <- tempfile(); complete <- review_actions_complete(path)
    old_option <- getOption("scAgentKit.run_crash")
    options(scAgentKit.run_crash = point)
    expect_error(review_actions_submit(path, "undo", complete, decision_id = complete$review_node$decision_id), "Injected crash")
    options(scAgentKit.run_crash = old_option)
    if (identical(point, "undo:archive"))
      review_actions_submit(path, "undo", complete, decision_id = complete$review_node$decision_id)
    else sc_run_resume(path)
    status <- sc_run_inspect(path)
    expect_identical(status$status, "awaiting_configuration")
    expect_false(status$review_node$can_undo)
    expect_null(.sc_run_load(path)$files$annotated)
    expect_length(Filter(function(e) e$action == "annotation_undone", .sc_run_load(path)$history), 1)
  }
})
