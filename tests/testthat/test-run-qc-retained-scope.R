# Local synthetic history controls. The checkpoint helper tests provenance and
# commit boundaries; full strategy/doublet execution is covered separately.
scope_rule <- function(minimum = NULL, operator = "any") list(
  schema = "scagentkit.qc.rules.v1", rationale = "Synthetic exact-scope control.",
  risks = list("No biological quality claim."), remove_if = operator,
  rules = if (is.null(minimum)) list() else list(list(op = "range", metric = "nCount", min = minimum)))
scope_begin <- function() {
  root <- tempfile("retained-scope-")
  cells <- c("001", "1", "NA", "cell space", paste0("scope-cell-", 5:32))
  counts <- Matrix::Matrix(matrix(rep(seq_len(32), each = 8L), nrow = 8L,
    dimnames = list(c("MT-CO1", paste0("ScopeGene", 2:8)), cells)), sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  sc_run(object, root, context = list(species = "human", tissue = "scope software control"),
    qc_proposal = scope_rule(0), analysis = list(run_umap = FALSE))
  state <- .sc_run_load(root)
  state$pending <- NULL; state$approved <- NULL
  .sc_run_save(root, state)
  list(root = root, state = state, evidence = .sc_run_get(root, state, "qc_evidence"), cells = cells)
}
scope_checkpoint <- function(fixture, state, cells, stage, crash = NULL) {
  object <- .sc_run_get(fixture$root, state, "input")[, cells]
  key <- if (stage == "qc_apply") "qc_object" else "strategy_selected"
  state <- .sc_run_put(fixture$root, state, key, object)
  withr::local_options(list(scAgentKit.run_crash = crash))
  .sc_run_checkpoint(fixture$root, state, stage, "strategy_propose")
}

test_that("empty rules use the committed intersection and ignore uncommitted artifacts", {
  f <- scope_begin(); on.exit(unlink(f$root, recursive = TRUE))
  initial <- .sc_run_qc_retained_scope(f$root, f$state, f$evidence)
  expect_length(initial$sources, 0L)
  expect_identical(initial$cell_ids, f$cells)
  state <- scope_checkpoint(f, f$state, f$cells[-1L], "qc_apply")
  state <- scope_checkpoint(f, state, f$cells[-c(1L, 2L)], "strategy_selection")
  saved <- .sc_run_qc_retained_scope(f$root, state, f$evidence)
  for (operator in c("any", "all")) {
    checked <- .sc_run_qc_validate(scope_rule(operator = operator), f$evidence, retained_scope = saved)
    expect_identical(checked$keep_cells, f$cells[-c(1L, 2L)])
    expect_equal(checked$summary$quality_removed, 0)
    expect_equal(checked$summary$prior_removed, 2)
  }
  expect_identical(.sc_run_qc_validate(scope_rule(0), f$evidence, retained_scope = saved)$keep_cells, f$cells)
  # An invalidated active pointer or unapproved draft cannot erase history.
  state$files$qc_object <- NULL; state$files$strategy_selected <- NULL
  state <- .sc_run_event(state, "manual_proposal", list(kind = "strategy"))
  .sc_run_save(f$root, state)
  expect_identical(.sc_run_qc_retained_scope(f$root, state, f$evidence)$cell_ids, saved$cell_ids)
  expect_error(scope_checkpoint(f, state, f$cells, "qc_apply", "qc_apply:artifact"), "Injected crash")
  state <- .sc_run_load(f$root)
  expect_identical(.sc_run_qc_retained_scope(f$root, state, f$evidence)$cell_ids, saved$cell_ids)
  expect_error(scope_checkpoint(f, state, f$cells, "qc_apply", "qc_apply:checkpoint"), "Injected crash")
  state <- .sc_run_load(f$root)
  # New broader QC plus an interrupted selection still respects old selection.
  partial <- .sc_run_qc_retained_scope(f$root, state, f$evidence)
  expect_identical(partial$cell_ids, saved$cell_ids)
  expect_error(scope_checkpoint(f, state, f$cells, "strategy_selection", "strategy_selection:artifact"), "Injected crash")
  state <- .sc_run_load(f$root)
  expect_identical(.sc_run_qc_retained_scope(f$root, state, f$evidence)$cell_ids, saved$cell_ids)
  expect_error(scope_checkpoint(f, state, f$cells, "strategy_selection", "strategy_selection:checkpoint"), "Injected crash")
  state <- .sc_run_load(f$root)
  expect_identical(.sc_run_qc_retained_scope(f$root, state, f$evidence)$cell_ids, f$cells)
  # The old approval snapshot remains retrospective after later execution.
  expect_invisible(.sc_run_qc_retained_scope_verify(f$root, state, saved, f$evidence))
  expect_identical(.sc_run_qc_validate(scope_rule(), f$evidence, retained_scope = saved)$keep_cells, saved$cell_ids)
})

test_that("saved scope rejects altered sources, omitted events and forged cell identities", {
  f <- scope_begin(); on.exit(unlink(f$root, recursive = TRUE))
  state <- scope_checkpoint(f, f$state, f$cells[-1L], "qc_apply")
  state <- scope_checkpoint(f, state, f$cells[-c(1L, 2L)], "strategy_selection")
  context <- .sc_run_qc_retained_scope(f$root, state, f$evidence)
  mutations <- list(
    function(x) { x$sources <- x$sources[-1L]; x },
    function(x) { x$cell_ids <- x$cell_ids[-1L]; x },
    function(x) { x$cell_ids <- rev(x$cell_ids); x },
    function(x) { x$cell_ids <- c(x$cell_ids, x$cell_ids[1L]); x },
    function(x) { x$cell_ids[1L] <- "foreign"; x },
    function(x) { x$sources[[1L]]$event_sequence <- 1L; x },
    function(x) { x$sources[[1L]]$artifact$path <- "../foreign.rds"; x },
    function(x) { x$input_hash <- strrep("f", 64L); x },
    function(x) { x$evidence_hash <- strrep("f", 64L); x },
    function(x) { x$history$head_hash <- strrep("f", 64L); x })
  for (mutate in mutations) {
    changed <- mutate(context); changed$hash <- .sc_run_qc_scope_hash(changed)
    expect_error(.sc_run_qc_retained_scope_verify(f$root, state, changed, f$evidence), "Retained QC scope")
  }
  changed <- context; changed$hash <- strrep("f", 64L)
  expect_error(.sc_run_qc_retained_scope_cells(changed, f$evidence), "Retained QC scope")
  path <- file.path(f$root, context$sources[[1L]]$artifact$path)
  original <- readBin(path, "raw", n = file.info(path)$size)
  writeBin(as.raw(1:8), path)
  expect_error(.sc_run_qc_retained_scope_verify(f$root, state, context, f$evidence), "Retained QC scope")
  writeBin(original, path)
  moved <- paste0(path, ".saved"); expect_true(file.rename(path, moved))
  expect_error(.sc_run_qc_retained_scope_verify(f$root, state, context, f$evidence), "Retained QC scope")
  if (.Platform$OS.type != "windows") {
    expect_true(file.symlink(moved, path))
    expect_error(.sc_run_qc_retained_scope_verify(f$root, state, context, f$evidence), "Retained QC scope")
    unlink(path)
  }
  expect_true(file.rename(moved, path))
  expect_invisible(.sc_run_qc_retained_scope_verify(f$root, state, context, f$evidence))
})

test_that("same empty scientific policy reuses its scope and new policies capture committed exclusions", {
  f <- scope_begin(); on.exit(unlink(f$root, recursive = TRUE))
  original <- .sc_run_qc_retained_scope(f$root, f$state, f$evidence)
  old <- .sc_run_qc_validate(scope_rule(), f$evidence, retained_scope = original)
  state <- .sc_run_put(f$root, f$state, "qc_validated", old)
  state <- scope_checkpoint(f, state, f$cells[-1L], "qc_apply")
  revised <- scope_rule(operator = "all"); revised$rationale <- "Reworded same scientific policy."
  selected <- .sc_run_qc_retained_scope_for_proposal(f$root, state, revised, f$evidence, "qc")
  expect_identical(selected, original)
  expect_identical(.sc_run_qc_scientific_key(old$proposal), .sc_run_qc_scientific_key(revised))
  prospective <- .sc_run_qc_retained_scope_for_proposal(f$root, state, scope_rule(0), f$evidence, "qc")
  expect_identical(prospective$cell_ids, f$cells[-1L])
  state <- .sc_run_put(f$root, state, "qc_validated", .sc_run_qc_validate(scope_rule(0), f$evidence, retained_scope = prospective))
  selected <- .sc_run_qc_retained_scope_for_proposal(f$root, state, revised, f$evidence, "qc")
  expect_identical(selected$cell_ids, f$cells[-1L])
  validated <- .sc_run_qc_validate(revised, f$evidence, retained_scope = selected)
  expect_error(.sc_run_qc_preview_publish(f$root, state, validated, f$evidence, retained_scope = original), "Retained QC scope")
  for (invalid in list(NULL, structure(list(), names = character()))) {
    malformed <- revised; malformed["rules"] <- list(invalid)
    expect_false(.sc_run_qc_empty_rules(malformed))
    expect_error(.sc_run_qc_validate(malformed, f$evidence, retained_scope = selected))
  }
})

test_that("direct QC drive forwards one selected context and preview settings preserve it", {
  f <- scope_begin(); on.exit(unlink(f$root, recursive = TRUE))
  # Restore a real pending QC boundary before exercising the public edit route.
  state <- f$state; validated <- .sc_run_get(f$root, state, "qc_validated")
  state <- .sc_run_qc_pending(state, validated, f$evidence, f$root)
  .sc_run_save(f$root, state)
  selected <- .sc_run_qc_retained_scope_for_proposal(f$root, state, scope_rule(), f$evidence, "qc")
  forged <- selected; forged$input_hash <- strrep("f", 64L); forged$hash <- .sc_run_qc_scope_hash(forged)
  before <- sort(list.files(f$root, recursive = TRUE, all.files = TRUE))
  expect_error(.sc_run_propose_locked(f$root, state, scope_rule(), "scope QA", "Foreign context.", retained_scope = forged), "Retained QC scope")
  expect_identical(sort(list.files(f$root, recursive = TRUE, all.files = TRUE)), before)
  .sc_run_propose_locked(f$root, state, scope_rule(), "scope QA", "No additional filtering.", retained_scope = selected)
  state <- .sc_run_load(f$root)
  expect_identical(.sc_run_get(f$root, state, "qc_validated")$retained_scope, selected)
  previous <- .sc_run_get(f$root, state, "qc_preview")
  state <- .sc_run_qc_preview_update(f$root, state,
    list(list(id = "empty-all", proposal = scope_rule(operator = "all"))), NULL, "scope QA", "Compare the inert empty operator.")
  expect_identical(.sc_run_get(f$root, state, "qc_validated")$retained_scope, selected)
  expect_identical(.sc_run_qc_preview_verify(f$root, state)$details$keep_cells, previous$details$keep_cells)
  revisions <- Filter(function(event) identical(event$action, "qc_preview_revised"), state$history)
  expect_identical(tail(revisions, 1L)[[1L]]$details$previous_preview_hash, previous$hash)
  expect_false(dir.exists(file.path(f$root, "provider")))
})

test_that("review provenance hashes change without changing the scientific QC choice", {
  f <- scope_begin(); on.exit(unlink(f$root, recursive = TRUE))
  original <- .sc_run_qc_retained_scope(f$root, f$state, f$evidence)
  v1 <- .sc_run_qc_validate(scope_rule(0), f$evidence, retained_scope = original)
  state <- .sc_run_qc_preview_publish(f$root, f$state, v1, f$evidence)
  first <- .sc_run_get(f$root, state, "qc_preview")
  state <- .sc_run_event(state, "manual_proposal", list(reason = "A new prospective review."))
  refreshed <- .sc_run_qc_retained_scope(f$root, state, f$evidence)
  v2 <- .sc_run_qc_validate(scope_rule(0), f$evidence, retained_scope = refreshed)
  state <- .sc_run_qc_preview_publish(f$root, state, v2, f$evidence)
  second <- .sc_run_get(f$root, state, "qc_preview")
  expect_identical(v1$keep_cells, v2$keep_cells)
  expect_identical(.sc_run_qc_scientific_key(v1$proposal), .sc_run_qc_scientific_key(v2$proposal))
  expect_identical(first$details, second$details)
  expect_identical(first$retained_scope_hash, original$hash)
  expect_identical(second$retained_scope_hash, refreshed$hash)
  expect_false(identical(first$retained_scope_hash, second$retained_scope_hash))
  expect_false(identical(first$hash, second$hash))
})
