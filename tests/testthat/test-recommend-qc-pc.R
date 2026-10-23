recommend_qc_fixture <- function(joint = TRUE, mt = TRUE, n = 120L, smooth = FALSE, constant = FALSE) {
  genes <- c(if (mt) "MT-CO1" else "GeneNoMt", "RPS3", "HBA1", paste0("Gene", 4:80))
  counts <- matrix(0, 80, n, dimnames = list(genes, paste0("cell", seq_len(n))))
  for (i in seq_len(n)) {
    z <- (i - 1L) %% 60L + 1L
    counts[seq_len(20L + z %% 30L), i] <- if (smooth) 100L + z else 2L + z %% 9L
    counts[1, i] <- if (smooth) round(sum(counts[-1L, i]) * (.05 + .002 * z) / (1 - .05 - .002 * z)) else 1L + z %% 10L
  }
  if (constant) counts[,] <- 1
  if (joint) for (i in intersect(c(1L, 61L), seq_len(n))) {
    counts[, i] <- 0; counts[1, i] <- 1
  }
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  seu$sample <- rep(c("A", "B"), length.out = n)
  context <- list(species = "human", tissue = "synthetic diagnostics", columns = list(sample = "sample"))
  config <- list(context = context, assay = "RNA", counts_layer = "counts",
    qc_mad = .sc_run_mad_options(context, list(grouping = list(method = "column", column = "sample",
      declared_role = "sample", source = "Declared synthetic samples, not quality truth."))))
  qc <- .sc_run_qc_evidence(seu, context)
  record <- .sc_run_mad_evidence(seu, config, qc)
  qc$mad_record <- record; qc$summary$mad <- record$summary; qc$evidence_hash <- .sc_run_qc_hash(qc)
  proposal <- list(schema = "scagentkit.qc.rules.v1", rationale = "Reviewed ranges and comparison.",
    risks = list("Synthetic controls only."), remove_if = "any",
    rules = list(list(op = "range", metric = "nCount", min = 1),
      list(op = "mad_preset", preset_id = "keep_all", panel_hash = record$panel_hash)))
  list(input = seu, evidence = list(summary = list(start_stage = "qc", qc_mad = record$summary), qc = qc),
    validated = list(proposal = list(qc = proposal), qc_validated = .sc_run_qc_validate(proposal, qc)))
}

test_that("QC recommendations respond to actual joint flags and preserve full range logic", {
  fixture <- recommend_qc_fixture()
  before <- serialize(fixture, NULL)
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  expect_identical(step$id, "qc")
  expect_identical(step$assessment, "assessed")
  expect_identical(step$status, "recommend_execute")
  ids <- vapply(step$candidates, `[[`, "", "id")
  expect_true("conservative_and3" %in% ids)
  expect_true("keep_all" %in% ids)
  expect_lt(length(step$candidates), 7L)
  for (candidate in step$candidates) {
    choice <- candidate$changes$qc
    expect_identical(choice$remove_if, "any")
    expect_identical(choice$rules[[1]], fixture$validated$proposal$qc$rules[[1]])
    expect_identical(choice$rules[[2]]$panel_hash, fixture$evidence$summary$qc_mad$panel_hash)
    if (candidate$available) expect_equal(candidate$impact$retained,
      .sc_run_qc_validate(choice, fixture$evidence$qc)$retention$retained)
  }
  expect_identical(serialize(fixture, NULL), before)
  expect_match(paste(unlist(step$uncertainty), collapse = " "), "not.*quality truth|not.*biological")
  expect_false(any(grepl("quality assessment completed", unlist(step$completed))))
})

test_that("QC missing metrics and small groups remain incomplete rather than endorsing keep-all", {
  for (fixture in list(recommend_qc_fixture(mt = FALSE), recommend_qc_fixture(n = 24L))) {
    step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
    expect_identical(step$status, "insufficient_information")
    expect_true(length(step$missing) > 0L)
    expect_match(paste(unlist(step$uncertainty), collapse = " "), "incomplete|not completed")
  }
  absent <- .sc_run_recommend_qc(list(summary = list(start_stage = "qc")), list(proposal = list(qc = NULL)))
  expect_identical(absent$assessment, "unavailable")
  expect_identical(absent$status, "insufficient_information")
})

test_that("QC recommendations do not override AND scopes to manufacture removal", {
  fixture <- recommend_qc_fixture()
  fixture$validated$proposal$qc$remove_if <- "all"
  fixture$validated$qc_validated <- .sc_run_qc_validate(fixture$validated$proposal$qc, fixture$evidence$qc)
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  expect_identical(step$status, "insufficient_information")
  for (candidate in step$candidates) expect_identical(candidate$changes$qc$remove_if, "all")
  expect_true(length(step$conflicts) > 0L)
})

recommend_pc_validated <- function(npcs = 50L) list(proposal = list(
  analysis = list(npcs = npcs), pcs = list(method = "computed_top50", threshold = .8)))

test_that("PC pending state describes work still to compute and never claims measured rank", {
  step <- .sc_run_recommend_pc(list(status = "pending_computation"), recommend_pc_validated())
  expect_identical(step$id, "pcs")
  expect_identical(step$assessment, "pending_computation")
  expect_identical(step$status, "recommend_execute")
  expect_length(step$completed, 0L)
  expect_true(all(!vapply(step$candidates, `[[`, logical(1), "available")))
  expect_match(paste(unlist(step$reasons), collapse = " "), "not.*computed|pending")
})

test_that("PC measured candidates use the existing exact internal reference and preserve unsupported states", {
  record <- .sc_run_pc_candidates(rep(1, 50L))
  review <- list(status = "computed", actual = list(available_pcs = 50L, top50_candidates = record))
  before <- serialize(review, NULL)
  step <- .sc_run_recommend_pc(review, recommend_pc_validated())
  expect_identical(step$status, "recommend_execute")
  expect_identical(step$assessment, "assessed")
  expect_identical(step$candidates[[1]]$impact$ndim, 40L)
  expect_identical(step$candidates[[2]]$impact$ndim, 43L)
  expect_identical(step$candidates[[1]]$changes, list(pcs = list(method = "computed_top50", threshold = .8)))
  expect_match(paste(unlist(step$uncertainty), collapse = " "), "not total")
  expect_identical(serialize(review, NULL), before)
  record <- .sc_run_pc_candidates(c(2, 1))
  review <- list(status = "computed", actual = list(available_pcs = 2L, top50_candidates = record))
  step <- .sc_run_recommend_pc(review, recommend_pc_validated(2L))
  expect_false(step$candidates[[1]]$available)
  expect_true(step$candidates[[2]]$available)
  expect_identical(step$candidates[[1]]$impact$ndim, 1L)
  expect_true(step$candidates[[2]]$impact$shortfall)
  bad <- review; bad$actual$top50_candidates$hash <- "edited"
  expect_identical(.sc_run_recommend_pc(bad, recommend_pc_validated(2L))$status, "insufficient_information")
})


test_that("QC range-only intersections disclose outer-AND re-entry and redundant flags", {
  fixture <- recommend_qc_fixture()
  # A low-count range removes the joint outliers. Outer AND with keep_all
  # restores them, so no candidate may be described as range-first deletion.
  fixture$validated$proposal$qc$rules[[1]]$min <- 100
  fixture$validated$proposal$qc$remove_if <- "all"
  fixture$validated$qc_validated <- .sc_run_qc_validate(fixture$validated$proposal$qc, fixture$evidence$qc)
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  for (candidate in step$candidates) {
    expect_true(all(c("range_only_retained", "new_removed_within_range_keep", "reintroduced_range_failed") %in% names(candidate$impact)))
    if (candidate$impact$reintroduced_range_failed > 0L) {
      expect_false(candidate$available)
      expect_match(paste(unlist(candidate$conflicts), collapse = " "), "range-failed")
    }
    expect_identical(candidate$changes$qc$remove_if, "all")
  }
  fixture$validated$proposal$qc$remove_if <- "any"
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  for (candidate in step$candidates) {
    expect_equal(candidate$impact$reintroduced_range_failed, 0)
    if (candidate$id != "keep_all" && candidate$impact$new_removed_within_range_keep == 0L)
      expect_false(candidate$available)
  }
  corrupted <- fixture$evidence
  corrupted$summary$qc_mad$groups[[1]]$flags$low_count <- 0L
  expect_identical(.sc_run_recommend_qc(corrupted, fixture$validated)$assessment, "unavailable")
})

test_that("PC reports preserve explicit fixed choices and reject mismatched computed scope", {
  record <- .sc_run_pc_candidates(rep(1, 20L))
  review <- list(status = "computed", actual = list(available_pcs = 20L, top50_candidates = record))
  validated <- recommend_pc_validated(20L)
  validated$proposal$pcs <- list(method = "fixed", ndim = 5L)
  step <- .sc_run_recommend_pc(review, validated)
  expect_identical(step$status, "recommend_skip")
  expect_match(paste(unlist(step$reasons), collapse = " "), "explicit fixed")
  review$actual$available_pcs <- 50L
  expect_identical(.sc_run_recommend_pc(review, recommend_pc_validated())$assessment, "unavailable")
})


test_that("QC no-outlier advice requires all metrics assessed, while MAD-zero stays incomplete", {
  fixture <- recommend_qc_fixture(joint = FALSE, smooth = TRUE)
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  expect_identical(step$status, "recommend_skip")
  expect_length(step$missing, 0L)
  expect_identical(vapply(step$candidates, `[[`, "", "id"), "keep_all")
  expect_match(paste(unlist(step$reasons), collapse = " "), "not completed biological quality")
  fixture <- recommend_qc_fixture(joint = FALSE, constant = TRUE)
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  expect_identical(step$status, "insufficient_information")
  expect_true(length(step$missing) > 0L)
  expect_match(paste(vapply(step$missing, `[[`, "", "reason"), collapse = " "), "MAD is zero")
})

test_that("QC and PC recommendation records expose the complete plain-list contract", {
  fixture <- recommend_qc_fixture()
  records <- list(.sc_run_recommend_qc(fixture$evidence, fixture$validated),
    .sc_run_recommend_pc(list(status = "pending_computation"), recommend_pc_validated()),
    .sc_run_recommend_qc(list(summary = list(start_stage = "processed")), list()),
    .sc_run_recommend_pc(list(status = "processed_reuse"), list()))
  expected <- c("id", "status", "assessment", "title", "reasons", "completed", "candidates", "conflicts", "uncertainty", "missing", "next_decision")
  for (record in records) {
    expect_identical(names(record)[names(record) %in% expected], expected)
    expect_true(all(names(record) %in% c(expected,"sample_comparison")))
    expect_true(is.list(record$reasons) && is.list(record$completed) && is.list(record$missing))
    expect_true(record$status %in% c("recommend_execute", "recommend_skip", "insufficient_information"))
    for (candidate in record$candidates) {
      expect_identical(names(candidate), c("id", "label", "changes", "available", "reasons", "impact", "conflicts"))
      expect_true(is.list(candidate$changes) && length(names(candidate$changes)) > 0L)
      expect_true(is.logical(candidate$available) && length(candidate$available) == 1L)
    }
  }
})

test_that("identical range and MAD failures do not manufacture post-range benefit under AND", {
  fixture <- recommend_qc_fixture()
  fixture$validated$proposal$qc$rules[[1]]$min <- 2
  fixture$validated$proposal$qc$remove_if <- "all"
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  candidate <- Filter(function(item) identical(item$id, "low_counts3"), step$candidates)[[1L]]
  expect_gt(candidate$impact$additional_removed_vs_keep_all, 0)
  expect_equal(candidate$impact$reintroduced_range_failed, 0)
  expect_equal(candidate$impact$new_removed_within_range_keep, 0)
  expect_false(candidate$available)
})


test_that("a valid fixed PC policy does not inherit conflicts from unsupported empirical alternatives", {
  review <- list(status = "computed", actual = list(available_pcs = 2L,
    top50_candidates = .sc_run_pc_candidates(c(3, 1))))
  validated <- recommend_pc_validated(2L)
  validated$proposal$pcs <- list(method = "fixed", ndim = 2L)
  step <- .sc_run_recommend_pc(review, validated)
  expect_identical(step$status, "recommend_skip")
  expect_length(step$conflicts, 0L)
  expect_true(all(!vapply(step$candidates, `[[`, logical(1), "available")))
})
test_that("QC comparisons never request automatic draft replacement", {
  fixture <- recommend_qc_fixture()
  step <- .sc_run_recommend_qc(fixture$evidence,fixture$validated)
  expect_false("draft_preselection" %in% names(step))
  # OR remains an inspectable comparison when measured, never an automatic replacement.
  candidate <- Filter(function(x) x$id=="any_quality3",step$candidates)
  expect_true(length(candidate) <= 1L)
  fixture$validated$proposal$qc$rules[[2]]$preset_id <- "conservative_and3"
  changed <- .sc_run_recommend_qc(fixture$evidence,fixture$validated)
  expect_false("draft_preselection" %in% names(changed))
})


test_that("removing the only MAD selector evaluates an empty candidate against saved exclusions", {
  fixture <- recommend_qc_fixture()
  root <- .sc_run_root(tempfile("recommend-retained-scope-"), create = TRUE)
  on.exit(unlink(root, recursive = TRUE))
  state <- list(files = list(), history = list(), revision = 0L)
  state <- .sc_run_put(root, state, "input", fixture$input)
  state$input_hash <- state$files$input$sha256
  state <- .sc_run_put(root, state, "qc_evidence", fixture$evidence$qc)
  state <- .sc_run_put(root, state, "qc_object", fixture$input[, seq_len(90L)])
  state <- .sc_run_event(state, "executed", list(stage = "qc_apply", files = state$files))
  scope <- .sc_run_qc_retained_scope(root, state, fixture$evidence$qc)
  expect_invisible(.sc_run_qc_retained_scope_verify(root, state, scope, fixture$evidence$qc))
  proposal <- fixture$validated$proposal$qc
  proposal$rules <- proposal$rules[2L]
  fixture$validated$proposal$qc <- proposal
  fixture$validated$qc_validated <- .sc_run_qc_validate(proposal, fixture$evidence$qc, retained_scope = scope)
  empty <- proposal; empty$rules <- list()
  expected <- .sc_run_qc_validate(empty, fixture$evidence$qc, retained_scope = scope)
  expect_lt(expected$retention$retained, fixture$validated$qc_validated$retention$retained)
  before <- serialize(list(fixture, state, scope), NULL)
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  expect_gt(length(step$candidates), 0L)
  for (candidate in step$candidates) {
    expect_identical(candidate$impact$range_only_retained, expected$retention$retained)
    expect_identical(candidate$impact$range_only_policy, "no_additional_filtering")
    expect_match(candidate$impact$comparison, "prior exclusions")
    checked <- .sc_run_qc_validate(candidate$changes$qc, fixture$evidence$qc, retained_scope = scope)
    expect_identical(candidate$impact$retained, checked$retention$retained)
  }
  expect_identical(serialize(list(fixture, state, scope), NULL), before)
})

test_that("MAD recommendations retain v2 replacements and both diagnostic evidence hashes", {
  fixture <- recommend_qc_fixture()
  qc <- fixture$evidence$qc
  cells <- qc$metrics$cell_id
  membership <- stats::setNames(rep(c("0", "1"), each = length(cells) / 2L), cells)
  record <- list(schema = "scagentkit.biology-diagnostic.v1",
    options = .sc_run_biology_options(TRUE), qc_evidence_hash = qc$evidence_hash,
    counts_hash = qc$counts_hash, cell_ids = cells, diagnostic_cells = cells,
    membership = membership, membership_hash = .sc_run_hash(membership), minimum_counts = 0,
    embedding = matrix(seq_len(length(cells) * 2L), ncol = 2L, dimnames = list(cells, c("PC1", "PC2"))),
    markers = data.frame(), exclusions = .sc_run_biology_exclusions("human", qc$feature_ids),
    summary = list(status = "available", membership_hash = .sc_run_hash(membership)))
  record$hash <- .sc_run_hash(record)
  qc$biology_record <- record; qc$summary$biology <- record$summary
  qc$evidence_hash <- .sc_run_qc_hash(qc)
  proposal <- fixture$validated$proposal$qc
  proposal$schema <- "scagentkit.qc.rules.v2"
  proposal$diagnostic_hash <- record$hash; proposal$membership_hash <- record$membership_hash
  proposal$replacements <- list(list(cluster_id = "0", metric = "nCount", min = 1,
    reason = "Explicit equal-bound software replacement; no marker-supported relaxation."))
  fixture$evidence$qc <- qc
  fixture$validated$proposal$qc <- proposal
  fixture$validated$qc_validated <- .sc_run_qc_validate(proposal, qc)
  step <- .sc_run_recommend_qc(fixture$evidence, fixture$validated)
  expect_gt(length(step$candidates), 0L)
  for (candidate in step$candidates) {
    choice <- candidate$changes$qc
    expect_identical(choice$schema, "scagentkit.qc.rules.v2")
    expect_identical(choice$diagnostic_hash, proposal$diagnostic_hash)
    expect_identical(choice$membership_hash, proposal$membership_hash)
    expect_identical(choice$replacements, proposal$replacements)
    expect_identical(choice$rules[[1L]], proposal$rules[[1L]])
    expect_identical(choice$remove_if, proposal$remove_if)
  }
})
