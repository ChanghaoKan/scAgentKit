test_that("mixing reference follows the actual bounded candidate pool", {
  cells <- sprintf("cell%04d", seq_len(700))
  batch <- c(rep("A", 600), rep("B", 100))
  pool <- .sc_run_batch_pool(cells, batch)
  expect_length(pool, 512)
  selected <- match(pool, cells)
  embedding <- matrix(seq_len(1024), ncol = 2, dimnames = list(pool, c("PC1", "PC2")))
  x <- .sc_run_batch_mixing(embedding, batch[selected])
  frequencies <- table(batch[selected])
  reference <- sum(frequencies * (frequencies - 1)) / (512 * 511)
  expect_equal(x$random_reference, as.numeric(reference))
  expect_false(isTRUE(all.equal(x$random_reference, (600 * 599 + 100 * 99) / (700 * 699))))
  expect_identical(.sc_run_batch_pool(cells, batch), pool)
})

test_that("confounded batch never recommends correction and uses sample counts", {
  embedding <- cbind(rep(c(-10, 10), each = 30) + seq_len(60) / 100, seq_len(60) %% 3)
  rownames(embedding) <- paste0("cell", seq_len(60))
  roles <- list(batch = rep(c("A", "B"), each = 30),
    sample = rep(paste0("s", 1:4), each = 15),
    condition = rep(c("control", "treated"), each = 30))
  x <- .sc_run_batch_evidence(embedding, roles, rep("type", 60), design_supported = TRUE)
  expect_identical(x$status, "fully_confounded")
  expect_identical(x$recommendation, "none")
  expect_identical(x$design$independent_samples, 4L)
  expect_equal(vapply(x$design$condition_samples, `[[`, integer(1), "samples"), c(2L, 2L))
  expect_false(any(grepl('"s[1-4]"', .sc_project_json(x$design))))
  nested <- .sc_run_batch_design(rep(paste0("s", 1:4), each = 15),
    rep(paste0("b", 1:4), each = 15), roles$condition)
  expect_true(nested$fully_confounded) # multiple batches per condition still confounded
  expect_error(.sc_run_batch_evidence(embedding, roles, rep("type", 60),
    after = embedding[60:1, ]), "identical")
  roles$condition <- rep(c("control", "treated"), length.out = 60)
  x <- .sc_run_batch_evidence(embedding, roles, rep("type", 60), design_supported = TRUE)
  expect_identical(x$status, "insufficient_evidence")
  expect_identical(x$recommendation, "none")
})

test_that("batch evidence measures before and after without a composite score", {
  cells <- paste0("cell", 1:80)
  before <- cbind(rep(c(-10, 10), each = 40), seq_len(80) / 100)
  rownames(before) <- cells
  after <- cbind(seq_len(80) %% 7, seq_len(80) %% 5)
  rownames(after) <- cells
  roles <- list(batch = rep(c("A", "B"), each = 40),
    sample = rep(paste0("s", 1:8), each = 10),
    condition = rep(rep(c("C", "T"), each = 20), 2))
  x <- .sc_run_batch_evidence(before, roles, rep(c("one", "two"), each = 40),
    after = after, design_supported = TRUE)
  expect_identical(x$status, "effect_detected_design_supported")
  expect_identical(x$recommendation, "harmony")
  expect_lt(x$technical_mixing$after$excess, x$technical_mixing$before$excess)
  expect_lt(x$type_structure$after$mean, x$type_structure$before$mean)
  expect_null(x$score)
  y <- .sc_run_batch_evidence(after, roles, rep("one", 80), design_supported = TRUE)
  expect_identical(y$status, "no_effect_detected")
  expect_identical(y$recommendation, "none")
})

test_that("rule recommendation keeps none for absent effects or confounded design", {
  for (status in c("fully_confounded", "no_effect_detected", "insufficient_evidence")) {
    evidence <- list(summary = list(biology = list(batch = list(status = status))))
    result <- .sc_run_recommend_batch(evidence, list(),
      list(biological_diagnostics = list(batch_assessment = TRUE), context = list()))
    expect_identical(result$status, if (status == "insufficient_evidence")
      "insufficient_information" else "recommend_skip")
    expect_length(result$candidates, 1L)
    expect_identical(result$candidates[[1]]$changes$batch$method, "none")
  }
})

test_that("condition signal uses replicate centroids, and missing replication is unavailable", {
  sample <- rep(paste0("sample", 1:4), each = 6)
  condition <- rep(c("C", "T"), each = 12)
  embedding <- cbind(rep(c(0, 2, 10, 12), each = 6), 0)
  rownames(embedding) <- paste0("cell", seq_len(24))
  x <- .sc_run_batch_condition_signal(embedding, sample, condition, rep("type", 24))
  pair <- x$types[[1]]$pairs[[1]]
  expect_equal(pair$distance, 10)
  expect_equal(pair$within_sample_dispersion, 1)
  expect_equal(pair$ratio, 10)
  # Repeating a cell within one sample cannot change equal-sample weighting.
  more <- c(seq_len(24), rep(1:6, 5))
  y <- .sc_run_batch_condition_signal(embedding[more, ], sample[more],
    condition[more], rep("type", length(more)))
  expect_equal(y$types[[1]]$pairs[[1]]$ratio, 10)
  single <- .sc_run_batch_condition_signal(embedding, condition, condition, rep("type", 24))
  expect_identical(single$status, "unavailable")
  expect_match(single$reason, "two")
  zero <- embedding; zero[, 1] <- rep(c(0, 10), each = 12)
  z <- .sc_run_batch_condition_signal(zero, sample, condition, rep("type", 24))
  expect_identical(z$types[[1]]$pairs[[1]]$status, "unavailable")
  expect_null(z$types[[1]]$pairs[[1]]$ratio)
})

test_that("before and after use fixed labels rather than reclustering to prove preservation", {
  embedding <- cbind(rep(c(-5, 5), each = 30), seq_len(60) / 100)
  rownames(embedding) <- paste0("cell", seq_len(60))
  labels <- rep(c("one", "two"), each = 30)
  before <- .sc_run_batch_purity(embedding, labels)
  after_embedding <- cbind(seq_len(60) %% 2, seq_len(60) %% 7)
  rownames(after_embedding) <- rownames(embedding)
  after <- .sc_run_batch_purity(after_embedding, labels)
  expect_equal(before$mean, 1)
  expect_lt(after$mean, before$mean)
  expect_identical(after$label_hash, before$label_hash)
})

test_that("post-Harmony evidence uses the approved dimensions and saved diagnostic labels", {
  data("pbmc_small", package = "SeuratObject")
  before <- pbmc_small
  before$sample <- rep(paste0("s", 1:8), each = 10)
  before$batch <- rep(c("A", "B"), each = 40)
  before$condition <- rep(rep(c("C", "T"), each = 20), 2)
  after <- before
  coordinates <- SeuratObject::Embeddings(before, "pca")[, 1:3]
  coordinates <- coordinates[80:1, ]; rownames(coordinates) <- colnames(after)
  colnames(coordinates) <- paste0("harmony_", 1:3)
  after[["harmony"]] <- SeuratObject::CreateDimReducObject(
    embeddings = coordinates, assay = "RNA", key = "harmony_")
  after@misc$strategy_execution <- list(batch = list(pca = list(ndim = 3L)))
  record <- list(options = list(batch_assessment = TRUE),
    summary = list(status = "available", batch = list(design_supported = TRUE)),
    membership = stats::setNames(rep(c("one", "two"), each = 40), colnames(before)),
    hash = "diagnostic", membership_hash = "membership")
  config <- list(context = list(columns = list(sample = "sample", batch = "batch", condition = "condition")))
  result <- .sc_run_biology_post_batch(before, after, config, record, list())
  expect_identical(result$diagnostic_hash, "diagnostic")
  expect_identical(result$membership_hash, "membership")
  expect_match(result$embedding_scope, "Exact approved")
  pool <- .sc_run_batch_pool(colnames(after), after$batch)
  expect_identical(result$technical_mixing$after,
    .sc_run_batch_mixing(coordinates[pool, ], after$batch[match(pool, colnames(after))]))
  expect_identical(SeuratObject::LayerData(before, layer = "counts"),
    SeuratObject::LayerData(after, layer = "counts"))
})
