auto_diagnostic_input <- function() {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  env$pbmc_small
}
auto_diagnostic_start <- function(species = "human", mode = "auto", cycle_off = FALSE) {
  root <- tempfile("auto-diagnostic-")
  args <- list(input = auto_diagnostic_input(), project_dir = root,
    context = list(species = species, tissue = "Public PBMC software fixture", research_goal = "Preserve cell-cycle biology in this offline software control."),
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4, diagnostic_resolutions = NULL, umap = FALSE), doublet = mode)
  if (cycle_off) args$cycle_diagnostics <- FALSE
  do.call(sc_analyze, args)
  root
}

test_that("modern human entry attempts S/G2M evidence and leaves unsupported doublets unassessed", {
  input <- auto_diagnostic_input(); before <- .sc_run_hash(input)
  root <- auto_diagnostic_start(); on.exit(unlink(root, recursive = TRUE))
  state <- .sc_run_load(root); details <- sc_run_inspect(root)$strategy_review$details
  expect_false(is.null(state$config$cycle_diagnostics))
  expect_identical(state$config$cycle_diagnostics$species, "human")
  expect_identical(details$automatic_diagnostics$cycle$status, details$cycle_diagnostics$status)
  expect_identical(details$canonical_proposal$cycle$method, "none")
  expect_identical(details$automatic_diagnostics$doublet$status, "unavailable")
  expect_false(details$automatic_diagnostics$doublet$assessed)
  expect_null(state$config$doublet_diagnostics)
  expect_length(state$approvals, 0L); expect_null(state$files$analysis)
  expect_identical(.sc_run_hash(input), before)
})

test_that("mouse gene-set limitations and explicit off settings remain visible", {
  root <- auto_diagnostic_start("mouse"); on.exit(unlink(root, recursive = TRUE))
  state <- .sc_run_load(root); details <- sc_run_inspect(root)$strategy_review$details
  expect_null(state$config$cycle_diagnostics)
  expect_identical(details$automatic_diagnostics$cycle$status, "unavailable")
  expect_match(details$automatic_diagnostics$cycle$reason, "Mouse|mouse")
  off <- auto_diagnostic_start(mode = "off", cycle_off = TRUE); on.exit(unlink(off, recursive = TRUE), add = TRUE)
  state <- .sc_run_load(off); details <- sc_run_inspect(off)$strategy_review$details
  expect_null(state$config$cycle_diagnostics); expect_null(state$config$doublet_diagnostics)
  expect_identical(details$automatic_diagnostics$cycle$status, "disabled")
  expect_identical(details$automatic_diagnostics$doublet$status, "disabled")
  doublet <- Filter(function(step) identical(step$id, "doublet"), details$recommendations$steps)[[1L]]
  expect_identical(doublet$assessment, "unavailable")
  expect_identical(doublet$status, "recommend_skip")
})

test_that("remove cannot manufacture predictions from missing calling/capture facts", {
  root <- auto_diagnostic_start(mode = "remove"); on.exit(unlink(root, recursive = TRUE))
  state <- .sc_run_load(root); details <- sc_run_inspect(root)$strategy_review$details
  expect_identical(details$automatic_diagnostics$doublet$status, "unavailable")
  expect_null(state$config$doublet_diagnostics)
  expect_null(details$canonical_proposal$doublet)
  expect_identical(.sc_run_get(root, state, "strategy_validated")$qc_validated$keep_cells,
    colnames(.sc_run_get(root, state, "input")))
  expect_length(state$approvals, 0L)
})

test_that("automatic cycle scores use a fresh prefix instead of overwriting prior metadata", {
  seu <- auto_diagnostic_input()
  for (field in .sc_run_cycle_columns("sc_cycle")) seu[[field]] <- "prior-input-value"
  config <- list(context = list(species = "human"), assay = "RNA", counts_layer = "counts",
    input_policy = list(automatic_cycle = TRUE, doublet_mode = "off"))
  before <- .sc_run_hash(seu)
  options <- .sc_run_automatic_diagnostics(seu, config, NULL, NULL)
  expect_identical(options$cycle$column_prefix, "sc_cycle_auto1")
  expect_identical(.sc_run_hash(seu), before)
  expect_null(options$doublet)
})

test_that("automatic cycle scoring can use existing exact Ensembl symbol annotations", {
  genes <- sc_cycle_gene_set("human")
  symbols <- unique(c(head(genes$canonical_s_genes, 12), head(genes$canonical_g2m_genes, 15)))
  ids <- paste0("ENSG", sprintf("%011d", seq_along(symbols)))
  counts <- matrix(2, nrow = length(ids), ncol = 30,
    dimnames = list(ids, paste0("cell-", seq_len(30))))
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  seu[["RNA"]] <- SeuratObject::AddMetaData(seu[["RNA"]],
    data.frame(sc_feature_name = symbols, row.names = ids))
  mapped <- .sc_run_automatic_cycle_genes(seu, "RNA", "human")
  expect_identical(unname(mapped$symbol_mapping[symbols]), ids)
  expect_identical(mapped$canonical_s_genes, genes$canonical_s_genes)
  expect_identical(mapped$canonical_g2m_genes, genes$canonical_g2m_genes)
  expect_true(all(ids %in% c(mapped$s_genes, mapped$g2m_genes)))
})
