# Independent coordinator acceptance tests. Literal IDs, scope and original
# metadata are deliberately unlike the public PBMC fixture.
qc_binding_fixture <- function() {
  counts <- Matrix::Matrix(matrix(c(0, 1, 2, 0, 1, 4, 0, 0, 3, 6, 4, 0,
                                    0, 1, 1, 2, 1, 0, 1, 0, 0, 0, 0, 0), nrow = 4,
                                   dimnames = list(c("MT-CO1", "GeneA", "GeneB", "GeneC"),
                                                   c("001", "1", "NA", "cell space", "Ca", "zero"))), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  seu$sample_id <- c("sample a", "sample a", "sample a", "sample b", "sample b", "sample b")
  seu$capture_id <- c("cap1", "cap1", "cap2", "cap2", "cap2", "cap2")
  seu$condition <- rep(c("Ca", "Ctrl"), 3)
  seu$old_annotation <- factor(c("T", "T", NA, "B", "B", "unassigned"),
                               levels = c("T", "B", "unassigned", "unused"))
  seu[["literal prior column"]] <- c("old 001", "old 1", "old NA", "old space", "old Ca", "old zero")
  seu
}

qc_binding_context <- function() list(species = "human", tissue = "synthetic acceptance",
  columns = list(sample = "sample_id", capture = "capture_id", condition = "condition"),
  notes = "Offline acceptance only; positive expression is not quality truth.")

qc_binding_rule <- function(minimum = 1, scoped = TRUE) {
  filters <- list(list(op = "range", metric = "nCount", min = minimum))
  if (scoped) filters[[2]] <- list(op = "range", metric = "nCount", max = 10,
                                 group = list(sample = "sample a", capture = "cap2"))
  list(schema = "scagentkit.qc.v1", rationale = "Explicit synthetic count scope.",
       risks = list("No biological optimality or cell identity claim."), filters = filters)
}

qc_binding_begin <- function(path, input = qc_binding_fixture(), rule = qc_binding_rule(), review = list()) {
  sc_run(input, path, context = qc_binding_context(), qc_proposal = rule, review = review,
         analysis = list(run_umap = FALSE))
}

qc_binding_files <- function(path) {
  files <- sort(list.files(path, recursive = TRUE, full.names = TRUE, all.files = TRUE,
                           no.. = TRUE))
  files <- files[!dir.exists(files)]
  stats::setNames(vapply(files, .sc_project_sha_file, character(1)),
                  substring(files, nchar(path) + 2L))
}

qc_binding_approve <- function(path, status = sc_run_inspect(path)) {
  sc_run_approve(path, status$pending$hash, reviewer = "offline acceptance",
    reason = "Reviewed exact synthetic cell scope and impact preview.",
    preview_hash = status$qc_preview$hash, expected_revision = status$revision)
}

qc_binding_after_qc <- function(path) {
  before <- getOption("scAgentKit.run_crash")
  on.exit(options(scAgentKit.run_crash = before), add = TRUE)
  options(scAgentKit.run_crash = "qc_apply:checkpoint")
  sc_run_resume(path)
}

test_that("QC review exposes one immutable exact-scope preview before computation", {
  path <- tempfile(); input <- qc_binding_fixture(); before <- .sc_run_hash(input)
  status <- qc_binding_begin(path, input)
  expect_identical(status$status, "awaiting_review")
  expect_identical(status$pending$kind, "qc")
  inspected <- sc_run_inspect(path)
  preview <- sc_run_qc_preview(path)
  expect_identical(preview, inspected$qc_preview)
  expect_identical(preview$schema, "scagentkit.qc.review.v1")
  for (field in c("hash", "input_hash", "config_hash", "implementation_hash", "evidence_hash",
                  "rules_hash", "parameters_hash", "cell_scope_hash")) {
    expect_match(preview[[field]], "^[0-9a-f]{64}$", info = field)
    expect_identical(inspected$pending$proposal$preview[[field]], preview[[field]], info = field)
  }
  expect_identical(preview$details$keep_cells, c("001", "1", "cell space", "Ca"))
  expect_identical(preview$details$remove_cells, c("NA", "zero"))
  expect_equal(preview$details$retention$retained, 4)
  expect_equal(preview$details$retention$removed, 2)
  expect_null(.sc_run_load(path)$files$qc_object)
  expect_null(.sc_run_load(path)$files$analysis)
  files <- qc_binding_files(path)
  expect_identical(sc_run_qc_preview(path), preview)
  expect_identical(sc_run_inspect(path)$qc_preview, preview)
  expect_identical(sc_run_resume(path)$status, "awaiting_review")
  expect_identical(qc_binding_files(path), files)
  expect_identical(.sc_run_hash(input), before)
  expect_false(dir.exists(file.path(path, "provider")))
})

test_that("approval binds preview and revision, is idempotent and does not compute", {
  path <- tempfile(); qc_binding_begin(path); status <- sc_run_inspect(path)
  before <- qc_binding_files(path)
  expect_error(sc_run_approve(path, status$pending$hash, "test", preview_hash = strrep("0", 64),
                              expected_revision = status$revision), "[Pp]review|[Ss]tale")
  expect_error(sc_run_approve(path, status$pending$hash, "test", preview_hash = status$qc_preview$hash,
                              expected_revision = status$revision + 1L), "[Rr]evision|[Ss]tale")
  expect_identical(qc_binding_files(path), before)
  approved <- qc_binding_approve(path, status)
  expect_identical(approved$status, "ready")
  expect_identical(approved$stage, "qc_apply")
  expect_null(.sc_run_load(path)$files$qc_object)
  after <- qc_binding_files(path)
  repeated <- qc_binding_approve(path, status)
  expect_identical(repeated$status, "ready")
  expect_identical(qc_binding_files(path), after)
  decisions <- Filter(function(e) e$action == "approved" && e$details$kind == "qc", .sc_run_load(path)$history)
  expect_length(decisions, 1)
  expect_identical(decisions[[1]]$details$preview_hash, status$qc_preview$hash)
})

test_that("changing preview parameters and proposing a revised rule invalidate old approval", {
  path <- tempfile(); qc_binding_begin(path); old <- sc_run_inspect(path)
  expect_error(sc_run_qc_preview(path, gene_panels = list(test_panel = c("GeneA", "MISSING"))),
               "reviewer|reason|[Rr]eview")
  revised <- sc_run_qc_preview(path, gene_panels = list(test_panel = c("GeneA", "MISSING")),
    reviewer = "offline acceptance", reason = "Disclose an explicitly missing gene in the impact review.",
    proposal_hash = old$pending$hash, preview_hash = old$qc_preview$hash, expected_revision = old$revision)
  status <- sc_run_inspect(path)
  expect_false(identical(old$pending$hash, status$pending$hash))
  expect_false(identical(old$qc_preview$hash, status$qc_preview$hash))
  expect_false(identical(old$qc_preview$parameters_hash, status$qc_preview$parameters_hash))
  expect_identical(status$qc_preview$details$keep_cells, old$qc_preview$details$keep_cells)
  expect_error(qc_binding_approve(path, old), "[Ss]tale|[Rr]evision|[Pp]review")
  new <- sc_run_propose(path, qc_binding_rule(4), "offline acceptance", "Review higher synthetic lower bound.")
  expect_false(identical(new$pending$hash, status$pending$hash))
  expect_identical(sc_run_qc_preview(path)$details$keep_cells, c("1", "cell space"))
  expect_error(qc_binding_approve(path, status), "[Ss]tale|[Rr]evision|[Pp]review")
  history <- .sc_run_load(path)$history
  expect_true(any(vapply(history, function(e) identical(e$details$reason,
    "Disclose an explicitly missing gene in the impact review."), logical(1))))
  expect_true(any(vapply(history, function(e) identical(e$details$reason,
    "Review higher synthetic lower bound."), logical(1))))
  expect_null(.sc_run_load(path)$files$qc_object)
})

test_that("atomic headless review rejects stale submissions and records reject or revise", {
  path <- tempfile(); qc_binding_begin(path); old <- sc_run_inspect(path)
  new <- sc_run_qc_review(path, action = "revise", proposal_hash = old$pending$hash,
    preview_hash = old$qc_preview$hash, expected_revision = old$revision,
    reviewer = "offline acceptance", reason = "Change only the approved typed synthetic scope.",
    proposal = qc_binding_rule(4))
  current <- sc_run_inspect(path)
  expect_false(identical(current$pending$hash, old$pending$hash))
  expect_identical(current$qc_preview$details$keep_cells, c("1", "cell space"))
  expect_error(sc_run_qc_review(path, action = "approve", proposal_hash = old$pending$hash,
    preview_hash = old$qc_preview$hash, expected_revision = old$revision,
    reviewer = "offline acceptance", reason = "Old browser submission."), "[Ss]tale|[Rr]evision|[Pp]review")
  rejected <- sc_run_qc_review(path, action = "reject", proposal_hash = current$pending$hash,
    preview_hash = current$qc_preview$hash, expected_revision = current$revision,
    reviewer = "offline acceptance", reason = "Synthetic rejection acceptance.")
  expect_identical(rejected$status, "rejected")
  before <- qc_binding_files(path)
  expect_identical(sc_run_resume(path)$status, "rejected")
  expect_identical(qc_binding_files(path), before)
  expect_null(.sc_run_load(path)$files$qc_object)
})

test_that("edited input, preview checkpoint and decision route fail closed", {
  path <- tempfile(); qc_binding_begin(path); state <- .sc_run_load(path)
  saved <- file.path(path, state$files$qc_preview$path)
  record <- readRDS(saved); record$details$keep_cells <- "001"; saveRDS(record, saved)
  expect_error(sc_run_inspect(path), "changed|checksum|[Pp]review")
  expect_error(sc_run_approve(path, state$pending$hash, "test"), "changed|checksum|[Pp]review")
  path <- tempfile(); qc_binding_begin(path); status <- sc_run_inspect(path); qc_binding_approve(path, status)
  state <- .sc_run_load(path); saved <- file.path(path, state$files$input$path)
  input <- readRDS(saved); input$capture_id[1] <- "new capture"; saveRDS(input, saved)
  expect_error(sc_run_resume(path), "changed")
  path <- tempfile(); source <- tempfile(fileext = ".rds"); input <- qc_binding_fixture(); saveRDS(input, source)
  qc_binding_begin(path, source); status <- sc_run_inspect(path)
  counts <- SeuratObject::LayerData(input, assay = "RNA", layer = "counts"); counts[2, 1] <- counts[2, 1] + 1
  SeuratObject::LayerData(input, assay = "RNA", layer = "counts") <- counts; saveRDS(input, source)
  expect_error(qc_binding_approve(path, status), "Original input RDS changed")
  path <- tempfile(); qc_binding_begin(path); state <- .sc_run_load(path)
  state$pending$next_stage <- "analysis"; .sc_run_save(path, state)
  expect_error(sc_run_approve(path, state$pending$hash, "test"), "hashes changed|[Ss]tale|[Bb]inding")
})

test_that("an existing coordinator lock prevents preview updates and all decisions", {
  path <- tempfile(); qc_binding_begin(path); status <- sc_run_inspect(path); before <- qc_binding_files(path)
  owner <- .sc_run_lock(path); on.exit(.sc_run_release(path, owner), add = TRUE)
  expect_error(sc_run_qc_preview(path, gene_panels = list(test_panel = "GeneA"), reviewer = "test",
    reason = "Cannot mutate while another coordinator owns this project."), "locked")
  expect_error(qc_binding_approve(path, status), "locked")
  expect_error(sc_run_qc_review(path, "reject", status$pending$hash, status$qc_preview$hash,
    status$revision, "test", "Cannot reject under another owner."), "locked")
  .sc_run_release(path, owner)
  expect_identical(qc_binding_files(path), before)
})

test_that("review mutations reject changed configuration or implementation without writing", {
  path <- tempfile(); qc_binding_begin(path); status <- sc_run_inspect(path)
  state <- .sc_run_load(path); state$config$analysis$npcs <- 4; .sc_run_save(path, state)
  before <- qc_binding_files(path)
  expect_error(sc_run_qc_preview(path, gene_panels = list(test_panel = "GeneA"), reviewer = "test",
    reason = "A changed configuration requires a new valid project."), "[Cc]onfiguration|[Ss]tale")
  expect_error(sc_run_qc_review(path, "revise", status$pending$hash, status$qc_preview$hash,
    status$revision, "test", "Cannot revise under a changed configuration.", proposal = qc_binding_rule(4)),
    "[Cc]onfiguration|[Ss]tale")
  expect_identical(qc_binding_files(path), before)
  path <- tempfile(); qc_binding_begin(path); status <- sc_run_inspect(path); before <- qc_binding_files(path)
  verify_changed_implementation <- function() {
    testthat::local_mocked_bindings(.sc_run_implementation = function() strrep("0", 64), .package = "scAgentKit")
    expect_error(sc_run_qc_preview(path, gene_panels = list(test_panel = "GeneA"), reviewer = "test",
      reason = "A new implementation cannot republish using the previous fingerprint."), "[Ii]mplementation|[Ss]tale")
    expect_error(sc_run_qc_review(path, "preview", status$pending$hash, status$qc_preview$hash,
      status$revision, "test", "Cannot revise review settings under a changed implementation.",
      gene_panels = list(test_panel = "GeneA")), "[Ii]mplementation|[Ss]tale")
    expect_identical(qc_binding_files(path), before)
  }
  verify_changed_implementation()
})

test_that("a new R process applies only the approved preview cells and leaves input unchanged", {
  path <- tempfile(); source <- tempfile(fileext = ".rds"); original <- qc_binding_fixture(); saveRDS(original, source)
  input_sha <- .sc_project_sha_file(source); qc_binding_begin(path, source); status <- sc_run_inspect(path)
  arguments <- tempfile(fileext = ".rds"); script <- tempfile(fileext = ".R"); result <- tempfile(fileext = ".rds")
  stdout <- tempfile(fileext = ".log")
  on.exit(unlink(c(arguments, script, result, stdout)), add = TRUE)
  saveRDS(list(path = path, status = status, result = result, libraries = .libPaths(),
    package = getNamespaceInfo(asNamespace("scAgentKit"), "path")), arguments)
  writeLines(c(
    "Sys.unsetenv(c('DEEPSEEK_API_KEY', 'XAI_API_KEY', 'OPENAI_API_KEY'))",
    "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "if (file.exists(file.path(args$package, 'R', 'run.R'))) pkgload::load_all(args$package, quiet = TRUE, helpers = FALSE) else library(scAgentKit, lib.loc = dirname(args$package))",
    "status <- args$status",
    "sc_run_approve(args$path, status$pending$hash, 'independent R process', 'Reviewed the exact saved preview before restart.', preview_hash = status$qc_preview$hash, expected_revision = status$revision)",
    "options(scAgentKit.run_crash = 'qc_apply:checkpoint')",
    "saveRDS(sc_run_resume(args$path), args$result)"
  ), script)
  code <- system2(file.path(R.home('bin'), 'Rscript'), c('--vanilla', shQuote(script), shQuote(arguments)),
                   stdout = stdout, stderr = stdout)
  expect_identical(as.integer(code), 0L, info = paste(readLines(stdout, warn = FALSE), collapse = '\n'))
  if (!identical(as.integer(code), 0L)) return(invisible(NULL))
  resumed <- readRDS(result)
  expect_identical(resumed$status, "ready")
  expect_identical(resumed$stage, "analysis")
  state <- .sc_run_load(path); output <- .sc_run_get(path, state, "qc_object")
  expect_true("qc_apply" %in% state$completed)
  expect_null(state$files$analysis)
  expect_identical(colnames(output), status$qc_preview$details$keep_cells)
  expect_identical(colnames(output), c("001", "1", "cell space", "Ca"))
  expected <- original[, c("001", "1", "cell space", "Ca")]
  expect_identical(SeuratObject::LayerData(output, assay = "RNA", layer = "counts"),
                   SeuratObject::LayerData(expected, assay = "RNA", layer = "counts"))
  expect_identical(output$old_annotation, expected$old_annotation)
  expect_identical(output[["literal prior column"]], expected[["literal prior column"]])
  expect_identical(output$condition, expected$condition)
  expect_identical(.sc_project_sha_file(source), input_sha)
  expect_identical(readRDS(source), original)
  after <- qc_binding_files(path)
  sc_run_approve(path, status$pending$hash, 'independent R process', preview_hash = status$qc_preview$hash,
                 expected_revision = status$revision)
  expect_identical(qc_binding_files(path), after)
  expect_false(dir.exists(file.path(path, "provider")))
})

test_that("a separate R process cannot approve while another process owns the project lock", {
  path <- tempfile(); qc_binding_begin(path); status <- sc_run_inspect(path)
  before <- qc_binding_files(path); owner <- .sc_run_lock(path)
  on.exit(.sc_run_release(path, owner), add = TRUE)
  arguments <- tempfile(fileext = ".rds"); script <- tempfile(fileext = ".R")
  result <- tempfile(fileext = ".rds"); stdout <- tempfile(fileext = ".log")
  on.exit(unlink(c(arguments, script, result, stdout)), add = TRUE)
  saveRDS(list(path = path, status = status, result = result, libraries = .libPaths(),
    package = getNamespaceInfo(asNamespace("scAgentKit"), "path")), arguments)
  writeLines(c(
    "Sys.unsetenv(c('DEEPSEEK_API_KEY', 'XAI_API_KEY', 'OPENAI_API_KEY'))",
    "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "if (file.exists(file.path(args$package, 'R', 'run.R'))) pkgload::load_all(args$package, quiet = TRUE, helpers = FALSE) else library(scAgentKit, lib.loc = dirname(args$package))",
    "status <- args$status",
    "error <- tryCatch({sc_run_approve(args$path, status$pending$hash, 'competing R process', 'Attempt while another process owns the lock.', preview_hash = status$qc_preview$hash, expected_revision = status$revision); NULL}, error = conditionMessage)",
    "saveRDS(list(error = error, pid = Sys.getpid()), args$result)"
  ), script)
  code <- system2(file.path(R.home('bin'), 'Rscript'), c('--vanilla', shQuote(script), shQuote(arguments)),
                   stdout = stdout, stderr = stdout)
  expect_identical(as.integer(code), 0L, info = paste(readLines(stdout, warn = FALSE), collapse = '\n'))
  if (!identical(as.integer(code), 0L)) return(invisible(NULL))
  blocked <- readRDS(result)
  expect_false(identical(blocked$pid, Sys.getpid()))
  expect_match(blocked$error, "locked")
  .sc_run_release(path, owner)
  expect_identical(qc_binding_files(path), before)
})

test_that("explicit preapproval binds the same preview and records the full review evidence", {
  path <- tempfile(); before <- getOption("scAgentKit.run_crash")
  on.exit(options(scAgentKit.run_crash = before), add = TRUE)
  options(scAgentKit.run_crash = "qc_apply:checkpoint")
  out <- qc_binding_begin(path, review = list(preapprove_qc = qc_binding_rule()))
  expect_identical(out$status, "ready")
  expect_identical(out$stage, "analysis")
  state <- .sc_run_load(path); preview <- sc_run_qc_preview(path)
  events <- Filter(function(e) e$action == "approved" && e$details$kind == "qc", state$history)
  expect_length(events, 1)
  decision <- events[[1]]$details
  expect_identical(decision$reviewer, "explicit_preapproved_rule")
  expect_identical(decision$preview_hash, preview$hash)
  expect_identical(decision$input_hash, preview$input_hash)
  expect_identical(decision$implementation_hash, preview$implementation_hash)
  expect_match(decision$decision_id, "^decision-")
  expect_identical(colnames(.sc_run_get(path, state, "qc_object")), preview$details$keep_cells)
})

test_that("web revision matching a preapproved rule waits for explicit approval without driving analysis", {
  path <- tempfile(); input <- qc_binding_fixture(); input_hash <- .sc_run_hash(input)
  preapproved <- qc_binding_rule(4)
  begun <- qc_binding_begin(path, input, review = list(preapprove_qc = preapproved))
  expect_identical(begun$status, "awaiting_review")
  old <- sc_run_inspect(path); prior_history_length <- length(.sc_run_load(path)$history)
  revised <- sc_run_qc_review(path, "revise", old$pending$hash, old$qc_preview$hash, old$revision,
    "offline web reviewer", "Matching a preapproved rule still requires reviewing this new web snapshot.",
    proposal = preapproved)
  expect_identical(revised$status, "awaiting_review")
  expect_identical(revised$stage, "qc_propose")
  expect_identical(revised$pending$kind, "qc")
  expect_false(identical(revised$pending$hash, old$pending$hash))
  expect_identical(revised$qc_preview$details$keep_cells, c("1", "cell space"))
  state <- .sc_run_load(path)
  expect_null(state$approved)
  expect_length(state$approvals, 0)
  expect_null(state$files$qc_object)
  expect_null(state$files$analysis)
  expect_false(any(c("qc_apply", "analysis") %in% state$completed))
  new_events <- state$history[seq.int(prior_history_length + 1L, length(state$history))]
  expect_false(any(vapply(new_events, function(e) e$action %in% c("running", "executed", "approved"), logical(1))))
  expect_false(dir.exists(file.path(path, "provider")))
  unchanged <- qc_binding_files(path)
  expect_identical(sc_run_resume(path)$status, "awaiting_review")
  expect_identical(qc_binding_files(path), unchanged)
  expect_identical(.sc_run_hash(input), input_hash)
  expect_error(qc_binding_approve(path, old), "[Ss]tale|[Rr]evision|[Pp]review")
  ready <- qc_binding_approve(path, revised)
  expect_identical(ready$status, "ready")
  expect_identical(ready$stage, "qc_apply")
  expect_null(.sc_run_load(path)$files$qc_object)
  resumed <- qc_binding_after_qc(path)
  expect_identical(resumed$status, "ready")
  expect_identical(resumed$stage, "analysis")
  state <- .sc_run_load(path)
  expect_null(state$files$analysis)
  expect_identical(colnames(.sc_run_get(path, state, "qc_object")), c("1", "cell space"))
  expect_identical(.sc_run_hash(input), input_hash)
  expect_false(dir.exists(file.path(path, "provider")))
})
