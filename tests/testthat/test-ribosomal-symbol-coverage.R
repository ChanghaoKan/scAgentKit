ribo_symbol_cases <- function(species) {
  positive <- c("RPSA", "RPLP0", "RPLP1", "RPLP2", "RPL36AL", "RPL22L1",
    "RPL39L", "RPS3", "RPL10", "RPL36A")
  negative <- c("RPS6KA1", "RPS6KB1", "RPS6KC1", "RPS6KL1", "RPSAP1",
    "RPLP0P6", "RPL36ALP1", "MRPL12", "MRPS18A", "XRPS3", "OTHER")
  if (species == "mouse") {
    sentence <- function(x) paste0(substr(x, 1, 1), tolower(substring(x, 2)))
    positive <- sentence(positive); negative <- sentence(negative)
    negative <- c(negative, "Rpsa-ps10", "Rplp2-ps1", "RPSA")
  } else negative <- c(negative, "Rpsa")
  list(positive = positive, negative = negative)
}

test_that("literal ribosomal defaults include named protein families and exclude kinases and pseudogenes", {
  for (species in c("human", "mouse")) {
    genes <- ribo_symbol_cases(species)
    pattern <- .sc_run_ribo_pattern(species)
    expect_true(all(grepl(pattern, genes$positive)), info = species)
    expect_false(any(grepl(pattern, genes$negative)), info = species)
  }
})

test_that("standalone measurements and reviewed diagnostics agree without gene deletion", {
  withr::local_options(lifecycle_verbosity = "quiet")
  for (species in c("human", "mouse")) {
    cases <- ribo_symbol_cases(species)
    genes <- c(cases$positive, cases$negative)
    counts <- Matrix::Matrix(matrix(seq_along(genes), length(genes), 4L,
      dimnames = list(genes, paste0("cell", 1:4))), sparse = TRUE)
    obj <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
    original <- .sc_run_hash(obj)
    measured <- qc_add_metrics(obj, species = species)
    expected <- rep(100 * sum(seq_along(cases$positive)) / sum(seq_along(genes)), 4L)
    expect_equal(unname(measured$percent.ribo), expected, tolerance = 1e-10)
    diagnostic <- .sc_run_mad_diagnostic_percent(counts, colnames(counts), species, "ribo")
    expect_equal(diagnostic$values, expected, tolerance = 1e-10)
    expect_identical(diagnostic$provenance$matched_gene_count, length(cases$positive))
    expect_identical(diagnostic$provenance$pattern, .sc_run_ribo_pattern(species))
    expect_identical(diagnostic$provenance$action, "diagnostic only; never used for candidate deletion")
    expect_identical(rownames(measured),rownames(obj))
    expect_identical(.sc_run_hash(obj),original)
    expect_identical(measured@misc$qc_metric_source$patterns$percent.ribo,.sc_run_ribo_pattern(species))
  }
})
