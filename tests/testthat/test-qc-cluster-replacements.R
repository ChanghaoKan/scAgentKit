replacement_fixture <- function() {
  genes <- c("MT-CO1", "F1", "F2", "F3", "RPL3", "FOS")
  counts <- matrix(rep(1:12, each = 6), nrow = 6,
    dimnames = list(genes, paste0("fixture", 1:12)))
  counts[1, ] <- 1; counts[6, 1] <- 0
  object <- SeuratObject::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  qc <- .sc_run_qc_evidence(object, list(species = "human"))
  membership <- stats::setNames(rep(c("0", "1"), each = 6), colnames(object))
  record <- list(schema = "scagentkit.biology-diagnostic.v1",
    options = .sc_run_biology_options(TRUE), qc_evidence_hash = qc$evidence_hash,
    counts_hash = qc$counts_hash, cell_ids = colnames(object), diagnostic_cells = colnames(object),
    membership = membership, membership_hash = .sc_run_hash(membership),
    minimum_counts = 0,
    embedding = matrix(1:24, ncol = 2, dimnames = list(colnames(object), c("PC1", "PC2"))),
    markers = data.frame(cluster = rep(c("0", "1"), each = 5),
      gene = rep(genes[-1], 2), avg_log2FC = rep(5:1, 2), pct.1 = .8, pct.2 = .1, p_val_adj = .001),
    exclusions = .sc_run_biology_exclusions("human", genes),
    summary = list(status = "available", membership_hash = .sc_run_hash(membership)))
  record$hash <- .sc_run_hash(record)
  qc$biology_record <- record; qc$summary$biology <- record$summary
  qc$evidence_hash <- .sc_run_qc_hash(qc)
  proposal <- list(schema = "scagentkit.qc.rules.v2", rationale = "Software threshold replacement.",
    risks = list("Synthetic fixture; markers are not biological evidence."), remove_if = "any",
    rules = list(list(op = "range", metric = "nCount", min = 25),
      list(op = "range", metric = "nFeature", min = 6)),
    diagnostic_hash = record$hash, membership_hash = record$membership_hash,
    replacements = list(list(cluster_id = "0", metric = "nCount", min = 1,
      reason = "Review this specific software-control cluster's count threshold.")))
  list(qc = qc, proposal = proposal)
}

test_that("replacement removes the old bound but preserves other baseline metrics", {
  f <- replacement_fixture()
  x <- .sc_run_qc_validate(f$proposal, f$qc)
  expect_true(all(paste0("fixture", 2:6) %in% x$keep_cells))
  expect_false("fixture1" %in% x$keep_cells) # unrelated nFeature rule remains
  expect_true(all(paste0("fixture", 7:12) %in% x$keep_cells))
  expect_gt(x$summary$replacement_impact[[1]]$difference, 0)
  expect_identical(x$proposal$schema, "scagentkit.qc.rules.v2")
  tightened <- f$proposal; tightened$replacements[[1]]$min <- 30
  y <- .sc_run_qc_validate(tightened, f$qc)
  expect_false("fixture5" %in% y$keep_cells)
  expect_identical(y$summary$effective_thresholds[[1]]$direction, "tightening_or_equal")
})

test_that("replacement rejects overlap, unknown groups, stale membership and unqualified rescue", {
  f <- replacement_fixture()
  duplicated <- f$proposal
  duplicated$replacements <- rep(duplicated$replacements, 2)
  expect_error(.sc_run_qc_validate(duplicated, f$qc), "Overlapping")
  foreign <- f$proposal; foreign$replacements[[1]]$cluster_id <- "other"
  expect_error(.sc_run_qc_validate(foreign, f$qc), "unknown")
  stale <- f$proposal; stale$membership_hash <- strrep("0", 64)
  expect_error(.sc_run_qc_validate(stale, f$qc), "membership")
  missing <- f$proposal; missing$replacements[[1]]$reason <- ""
  expect_error(.sc_run_qc_validate(missing, f$qc))
  record <- f$qc$biology_record
  record$markers$p_val_adj[1] <- .05
  record$hash <- .sc_run_hash(record[setdiff(names(record), "hash")])
  f$qc$biology_record <- record; f$qc$evidence_hash <- .sc_run_qc_hash(f$qc)
  f$proposal$diagnostic_hash <- record$hash
  expect_error(.sc_run_qc_validate(f$proposal, f$qc), "Relaxation")
  f$proposal$replacements[[1]]$min <- 30
  expect_silent(.sc_run_qc_validate(f$proposal, f$qc)) # tightening needs no rescue eligibility
})

test_that("replacement cannot cross the minimum prefilter or target an absent baseline metric", {
  f <- replacement_fixture()
  record <- f$qc$biology_record; record$minimum_counts <- 5
  record$hash <- .sc_run_hash(record[setdiff(names(record), "hash")])
  f$qc$biology_record <- record; f$qc$evidence_hash <- .sc_run_qc_hash(f$qc)
  f$proposal$diagnostic_hash <- record$hash
  expect_error(.sc_run_qc_validate(f$proposal, f$qc), "minimum")
  f <- replacement_fixture()
  f$proposal$replacements[[1]] <- list(cluster_id = "0", metric = "percent_mt", max = 80,
    reason = "No baseline mitochondrial rule exists in this fixture.")
  expect_error(.sc_run_qc_validate(f$proposal, f$qc), "baseline coverage")
})
