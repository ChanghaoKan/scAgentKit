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
  list(evidence = list(summary = list(start_stage = "qc", qc_mad = record$summary), qc = qc),
    validated = list(proposal = list(qc = proposal), qc_validated = .sc_run_qc_validate(proposal, qc)))
}


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
    expect_true(all(names(record) %in% c(expected,"sample_comparison","draft_preselection")))
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
test_that("QC draft preselection is bound, guarded and never replaces an explicit policy", {
  fixture <- recommend_qc_fixture()
  step <- .sc_run_recommend_qc(fixture$evidence,fixture$validated)
  expect_true(isTRUE(step$draft_preselection$draft_only))
  expect_true(step$draft_preselection$automatic)
  {
    expect_identical(step$draft_preselection$candidate_id,"any_quality3")
    candidate <- Filter(function(x) x$id=="any_quality3",step$candidates)[[1L]]
    expect_lte(candidate$impact$removed,.1*fixture$validated$qc_validated$retention$before)
    expect_true(all(vapply(candidate$impact$groups,function(group) group$retained>=.8*group$before,logical(1))))
  }
  fixture$validated$proposal$qc$rules[[2]]$preset_id <- "conservative_and3"
  changed <- .sc_run_recommend_qc(fixture$evidence,fixture$validated)
  expect_false(changed$draft_preselection$automatic)
  expect_null(changed$draft_preselection$candidate_id)
})
