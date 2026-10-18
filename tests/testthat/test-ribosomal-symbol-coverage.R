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

test_that("all three QC consumers agree on the expanded literal symbols", {
  withr::local_options(lifecycle_verbosity = "quiet")
  for (species in c("human", "mouse")) {
    cases <- ribo_symbol_cases(species)
    genes <- c(cases$positive, cases$negative)
    counts <- Matrix::Matrix(matrix(seq_along(genes), length(genes), 4L,
      dimnames = list(genes, paste0("cell", 1:4))), sparse = TRUE)
    obj <- AgentSeurat(Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0))
    original <- .sc_run_hash(obj)
    measured <- qc_add_metrics(obj, species = species)
    expected <- rep(100 * sum(seq_along(cases$positive)) / sum(seq_along(genes)), 4L)
    expect_equal(unname(measured@data$percent.ribo), expected, tolerance = 1e-10)
    diagnostic <- .sc_run_mad_diagnostic_percent(counts, colnames(counts), species, "ribo")
    expect_equal(diagnostic$values, expected, tolerance = 1e-10)
    expect_identical(diagnostic$provenance$matched_gene_count, length(cases$positive))
    expect_identical(diagnostic$provenance$pattern, .sc_run_ribo_pattern(species))
    expect_identical(diagnostic$provenance$action, "diagnostic only; never used for candidate deletion")
    removed <- qc_remove_genes(obj, species = species, remove_mt = FALSE, remove_hb = FALSE)
    expect_setequal(rownames(removed@data), cases$negative)
    expect_identical(.sc_run_hash(obj), original)
    expect_true(any(grepl(.sc_run_ribo_pattern(species), measured@scripts, fixed = TRUE)))
    expect_true(any(grepl(.sc_run_ribo_pattern(species), removed@scripts, fixed = TRUE)))
  }
})

test_that("species RP fallback uses the same expanded family rather than passing through case fallback", {
  base <- c("RPL3", "RPL4", "RPL5", "RPL6", "RPL7", "RPL8", "RPL9", "RPL10",
    "RPL11", "RPL12", "RPL13", "RPL14", "RPL15", "RPL17", "RPL18", "RPL19",
    "RPL21", "RPL22", "RPL23", "RPL24", "RPL26", "RPL27", "RPL28", "RPL29", "RPL30", "RPL31")
  symbols <- c(base, "RPSA", "RPLP0", "RPLP1", "RPLP2", "RPL36AL")
  for (species in c("human", "mouse")) {
    genes <- if (species == "human") c(symbols, paste0("NeutralGene", 1:100)) else
      c(paste0(substr(symbols, 1, 1), tolower(substring(symbols, 2))), paste0("NEUTRALGENE", 1:100))
    upper <- mean(genes == toupper(genes))
    expect_true(upper > .1 && upper < .9)
    counts <- Matrix::Matrix(matrix(1, length(genes), 3L,
      dimnames = list(genes, paste0("cell", 1:3))), sparse = TRUE)
    seu <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
    expect_identical(.detect_species(seu), species)
    expect_identical(.detect_species(list(seu)), species)
  }
})
