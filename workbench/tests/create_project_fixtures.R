#!/usr/bin/env Rscript
# Pure synthetic fixtures and an independent, ID-based journal/writeback oracle.
# Source objects and reports belong outside Git. No provider or credential access.
# Rscript --vanilla create_project_fixtures.R --output /fresh/private/dir --sources-only true
# Rscript --vanilla create_project_fixtures.R --output /private/dir --projects-only true
# Optional --pbmc-rds /local/processed.rds; --r-library /local/library
# Verification: --verify-journal /journal.json --project /project --object /object.rds

args <- commandArgs(trailingOnly = TRUE)
"%||%" <- function(x, y) if (is.null(x)) y else x
if (length(args) %% 2L) stop("Use --name value argument pairs.", call. = FALSE)
opts <- list()
if (length(args)) for (i in seq.int(1L, length(args), 2L)) {
  if (!startsWith(args[i], "--")) stop("Use --name value argument pairs.", call. = FALSE)
  opts[[substring(args[i], 3L)]] <- args[i + 1L]
}
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script <- normalizePath(sub("^--file=", "", script_arg[1L]), mustWork = TRUE)
repo <- normalizePath(opts[["repo"]] %||% file.path(dirname(script), "../.."), mustWork = TRUE)
if (!is.null(opts[["r-library"]])) .libPaths(c(normalizePath(opts[["r-library"]], mustWork = TRUE), .libPaths()))
suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(Matrix))
if (!requireNamespace("jsonlite", quietly = TRUE) || !requireNamespace("digest", quietly = TRUE))
  stop("Existing jsonlite and digest installations are required.", call. = FALSE)

write_json <- function(value, file) {
  if (file.exists(file)) stop("Refusing to overwrite a QA artifact: ", file, call. = FALSE)
  writeLines(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", na = "null",
                             pretty = TRUE, digits = NA, force = TRUE), file, useBytes = TRUE)
}
save_new <- function(value, file) {
  if (file.exists(file)) stop("Refusing to overwrite a fixture: ", file, call. = FALSE)
  saveRDS(value, file)
}
load_api <- function(files) {
  for (name in files) {
    file <- file.path(repo, "R", name)
    if (!file.exists(file)) stop("Implementation is not ready: ", file, call. = FALSE)
    source(file, local = .GlobalEnv)
  }
}
reject <- function(name, fn) {
  error <- tryCatch({fn(); NULL}, error = identity)
  if (is.null(error)) stop("Negative fixture unexpectedly accepted: ", name, call. = FALSE)
  list(case = name, outcome = "rejected", message = conditionMessage(error))
}

make_sources <- function(output) {
  if (dir.exists(output) && length(list.files(output, all.files = TRUE, no.. = TRUE)))
    stop("Use a fresh output directory, or --projects-only true.", call. = FALSE)
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  sources <- file.path(output, "sources")
  dir.create(sources)
  set.seed(24017)
  # TRAC is deliberately unavailable; measured NK anchors are zero in the T group.
  # These are synthetic observations, not a biological benchmark.
  panel <- c("CD3D", "CD3E", "CD3G", "TRBC1", "TRBC2", "CD8A", "CD8B",
             "KLRD1", "KLRF1", "NCR1", "NCAM1", "FCGR3A", "NKG7", "GNLY",
             "PRF1", "GZMB", "GZMH", "GZMK", "CTSW", "CST7", "MS4A1",
             "CD79A", "CD79B", "LST1", "S100A8", "S100A9", "MT-CO1")
  genes <- c(panel, sprintf("feature%04d", seq_len(1000L - length(panel))))
  cells <- c("001", "1", "NA", "cell alpha", "cell 中文", sprintf("cell-%04d", 6:120))
  groups <- rep(c("001", "1", "NA", "B alpha", "中文"), each = 24L)
  counts <- matrix(0, nrow = 1000L, ncol = 120L, dimnames = list(genes, cells))
  counts[setdiff(genes, panel), ] <- matrix(rpois((1000L - length(panel)) * 120L, 1), ncol = 120L)
  activate <- function(features, selected, lambda = 3) {
    counts[features, selected] <<- matrix(1L + rpois(length(features) * sum(selected), lambda),
                                         nrow = length(features))
  }
  activate(c("CD3D", "CD3E", "CD3G", "TRBC1", "TRBC2"), groups == "001")
  activate(c("KLRD1", "KLRF1", "NCR1", "NCAM1"), groups == "1")
  activate(c("CD8A", "NKG7", "GNLY", "PRF1", "GZMB"), groups %in% c("001", "1", "NA"), 1)
  activate(c("MS4A1", "CD79A", "CD79B"), groups == "B alpha")
  activate(c("LST1", "S100A8", "S100A9", "FCGR3A"), groups == "中文")
  counts["MT-CO1", ] <- rpois(120L, 2)
  obj <- CreateSeuratObject(Matrix(counts, sparse = TRUE), project = "Synthetic QA", min.cells = 0, min.features = 0)
  obj <- NormalizeData(obj, normalization.method = "LogNormalize", scale.factor = 10000, verbose = FALSE)
  obj$seurat_clusters <- factor(groups, levels = c("001", "1", "NA", "B alpha", "中文"))
  obj$factor_with_na <- factor(rep(c("level A", "level B", NA_character_), length.out = 120L),
                             levels = c("level A", "level B", "unused level"))
  obj$original_annotation <- factor(rep(c("Original A", NA_character_, "Original B"), length.out = 120L))
  obj$unrelated_text <- rep(c("literal NA", "untouched", NA_character_), length.out = 120L)
  obj$percent.mt <- as.numeric(counts["MT-CO1", ] / colSums(counts) * 100)
  Idents(obj) <- factor(rep(c("old identity A", "old identity B", "old identity C"), length.out = 120L))
  angles <- seq(0, 2 * pi, length.out = 121L)[1:120]
  embedding <- cbind(UMAP_1 = cos(angles) + as.integer(obj$seurat_clusters),
                     UMAP_2 = sin(angles))
  rownames(embedding) <- cells
  obj[["umap"]] <- CreateDimReducObject(embeddings = embedding, key = "UMAP_", assay = "RNA")
  stopifnot(ncol(obj) == 120L, nrow(obj) == 1000L, identical(colnames(obj), cells))
  save_new(obj, file.path(sources, "synthetic-processed.rds"))

  changed <- obj
  changed_counts <- LayerData(changed, assay = "RNA", layer = "counts")
  changed_counts[1L, 1L] <- changed_counts[1L, 1L] + 1
  LayerData(changed, assay = "RNA", layer = "counts") <- changed_counts
  save_new(changed, file.path(sources, "same-barcodes-changed-counts.rds"))
  changed <- obj
  membership <- as.character(changed$seurat_clusters); membership[1L] <- "1"
  changed$seurat_clusters <- membership
  save_new(changed, file.path(sources, "same-barcodes-changed-membership.rds"))
  changed <- obj
  changed_data <- LayerData(changed, assay = "RNA", layer = "data")
  changed_data[1L, 1L] <- changed_data[1L, 1L] + 0.25
  LayerData(changed, assay = "RNA", layer = "data") <- changed_data
  save_new(changed, file.path(sources, "same-barcodes-changed-data.rds"))
  save_new(obj[rev(rownames(obj)), rev(colnames(obj))], file.path(sources, "permuted-equivalent.rds"))
  dense <- obj
  LayerData(dense, assay = "RNA", layer = "counts") <- as.matrix(LayerData(dense, assay = "RNA", layer = "counts"))
  LayerData(dense, assay = "RNA", layer = "data") <- as.matrix(LayerData(dense, assay = "RNA", layer = "data"))
  save_new(dense, file.path(sources, "dense-equivalent.rds"))
  save_new(obj[, -1L], file.path(sources, "missing-cell.rds"))
  missing_membership <- obj
  membership <- as.character(obj$seurat_clusters); membership[1L] <- NA_character_
  missing_membership$seurat_clusters <- membership
  save_new(missing_membership, file.path(sources, "actual-missing-membership.rds"))
  if (requireNamespace("scAgentKit", quietly = TRUE))
    save_new(scAgentKit::AgentSeurat(obj), file.path(sources, "synthetic-agentseurat.rds"))

  set.seed(24018)
  raw <- matrix(rpois(500L * 60L, 1), nrow = 500L,
                dimnames = list(sprintf("rawgene%04d", 1:500), sprintf("rawcell%03d", 1:60)))
  raw[, 1L] <- 0; raw[1L, 1L] <- 1
  raw[, 2L] <- 0; raw[2L, 2L] <- 2
  save_new(Matrix(raw, sparse = TRUE), file.path(sources, "counts-only.rds"))
  negatives <- list(
    negative = replace(raw, 1L, -1), fractional = replace(raw, 1L, 1.5),
    nonfinite = replace(raw, 1L, Inf), missing_value = replace(raw, 1L, NA_real_),
    empty_cells = raw[, FALSE, drop = FALSE], empty_features = raw[FALSE, , drop = FALSE])
  duplicated_features <- raw; rownames(duplicated_features)[2L] <- rownames(duplicated_features)[1L]
  duplicated_cells <- raw; colnames(duplicated_cells)[2L] <- colnames(duplicated_cells)[1L]
  empty_id <- raw; rownames(empty_id)[1L] <- ""
  negatives$duplicate_features <- duplicated_features
  negatives$duplicate_cells <- duplicated_cells
  negatives$empty_feature_id <- empty_id
  for (name in names(negatives)) save_new(negatives[[name]], file.path(sources, paste0("invalid-", name, ".rds")))
  write_json(list(schema = "scagentkit.qa-fixtures.v1", seed = 24017L,
                  synthetic = list(cells = 120L, features = 1000L, clusters = as.list(unique(groups)),
                                   missingPanelGene = "TRAC", lowDepthClaims = FALSE),
                  countsOnly = list(cells = 60L, features = 500L, retainedLowCountCells = as.list(colnames(raw)[1:2])),
                  sourceDirectory = sources, originalInputsSynthetic = TRUE), file.path(output, "fixture-sources.json"))
}

export_projects <- function(output) {
  load_api(c("project-identity.R", "project-prepare.R", "project-export.R"))
  sources <- file.path(output, "sources")
  if (!file.exists(file.path(sources, "synthetic-processed.rds"))) stop("Generate source fixtures first.", call. = FALSE)
  object <- readRDS(file.path(sources, "synthetic-processed.rds"))
  identity <- .sc_project_identity(object)
  for (name in c("permuted-equivalent", "dense-equivalent"))
    stopifnot(identical(.sc_project_identity(readRDS(file.path(sources, paste0(name, ".rds"))))$fingerprint, identity$fingerprint))
  projects <- file.path(output, "projects")
  dir.create(projects, showWarnings = FALSE)
  authored_markers <- data.frame(clusterId = c("001", "1", "B alpha"), gene = c("CD3D", "KLRD1", "MS4A1"),
                                avgLog2FC = c(1.2, 1.4, 1.8), pct1 = c(1, 1, 1), pct2 = c(0, 0, 0),
                                pAdj = c(0.01, 0.02, 0.03), source = "Synthetic authored QA table", stringsAsFactors = FALSE)
  result <- list()
  result$synthetic <- sc_project_export(object, file.path(projects, "synthetic"),
    project_id = "synthetic-independent", display_name = "Synthetic independent 120 cells",
    marker_table = authored_markers, source_annotation = "original_annotation",
    metadata_allowlist = c("nCount_RNA", "nFeature_RNA", "percent.mt", "factor_with_na"),
    directed_clusters = c("001", "1"), archive = TRUE,
    provenance = list(origin = "Pure deterministic synthetic QA data; not a biological benchmark"))
  raw <- readRDS(file.path(sources, "counts-only.rds"))
  prepared <- sc_project_prepare(raw, nfeatures = 250L, npcs = 10L, dims = 1:8,
                                resolution = 0.4, seed = 24018L, run_umap = TRUE, umap_neighbors = 15L)
  stopifnot(ncol(prepared) == 60L, setequal(colnames(prepared), colnames(raw)),
            identical(.sc_project_matrix(LayerData(prepared, assay = "RNA", layer = "counts"), "prepared counts", TRUE),
                      .sc_project_matrix(raw, "original counts", TRUE)))
  save_new(prepared, file.path(sources, "counts-prepared.rds"))
  result$prepared <- sc_project_export(prepared, file.path(projects, "prepared-counts"), "prepared-counts",
                                      display_name = "Explicitly prepared 60 cells", archive = TRUE)
  no_embedding <- object
  result$noEmbedding <- sc_project_export(no_embedding, file.path(projects, "no-embedding"), "synthetic-no-embedding",
    display_name = '<img src=x onerror="window.__projectXss=1"> Synthetic text',
    reduction = NULL, normalized_layer = NULL, archive = TRUE)
  pbmc <- opts[["pbmc-rds"]] %||% Sys.getenv("SCAGENTKIT_QA_PBMC_RDS", unset = "")
  if (nzchar(pbmc)) {
    pbmc_object <- readRDS(normalizePath(pbmc, mustWork = TRUE))
    result$pbmc <- sc_project_export(pbmc_object, file.path(projects, "pbmc"), "pbmc-research",
      display_name = "PBMC processed local project", directed_clusters = "6", archive = TRUE)
  }
  invalid <- lapply(list.files(sources, pattern = "^invalid-.*\\.rds$", full.names = TRUE), function(file)
    reject(basename(file), function() sc_project_prepare(readRDS(file), run_umap = FALSE)))
  invalid <- c(invalid, list(reject("actual missing membership", function()
    sc_project_export(readRDS(file.path(sources, "actual-missing-membership.rds")),
                      file.path(output, "must-not-exist"), "invalid-membership"))))
  write_json(list(schema = "scagentkit.qa-projects.v1", projects = result,
                  preparedCellsRetained = 60L, preparedLowCountCellsRetained = as.list(colnames(raw)[1:2]),
                  representationEquivalent = TRUE, negatives = invalid), file.path(output, "fixture-projects.json"))
}

verify_writeback <- function(journal_file, project, object_file, report_file) {
  if (requireNamespace("scAgentKit", quietly = TRUE)) invisible(getNamespace("scAgentKit"))
  load_api(c("project-identity.R", "project-review.R"))
  original <- readRDS(object_file)
  baseline <- original
  original_seurat <- .sc_project_unwrap(original)
  columns <- c(type = "qa_review_type", state = "qa_review_state", QC = "qa_review_qc")
  validated <- sc_review_validate(original, journal_file, project, columns)
  if (!isTRUE(validated$valid)) stop("Valid GUI journal rejected: ", paste(validated$errors$message, collapse = "; "), call. = FALSE)
  journal <- jsonlite::fromJSON(journal_file, simplifyVector = FALSE)
  events <- lapply(journal$events, function(envelope) jsonlite::fromJSON(envelope$payload, simplifyVector = FALSE))
  # Independent oracle: latest non-undone decision per literal cluster/dimension.
  undone <- vapply(Filter(function(e) identical(e$kind, "undo"), events), function(e) e$targetEventId, character(1))
  expected <- list()
  for (event in events) if (identical(event$kind, "decision") && !event$id %in% undone)
    expected[[paste(event$scope$clusterId, event$scope$dimension, sep = "\r")]] <- event
  applied <- sc_review_apply(original, journal_file, project, columns)
  target <- .sc_project_unwrap(applied)
  cluster_column <- jsonlite::fromJSON(file.path(project, "project.json"), simplifyVector = FALSE)$identity$clusterColumn
  stopifnot(identical(class(applied), class(original)), identical(original, baseline), identical(Idents(target), Idents(original_seurat)),
            identical(target@assays, original_seurat@assays), identical(target@reductions, original_seurat@reductions),
            identical(target@meta.data[, names(original_seurat@meta.data), drop = FALSE], original_seurat@meta.data))
  observed <- list()
  for (cell in colnames(original_seurat)) for (dimension in names(columns)) {
    cluster <- as.character(original_seurat@meta.data[cell, cluster_column])
    event <- expected[[paste(cluster, dimension, sep = "\r")]]
    workflow <- if (is.null(event)) NA_character_ else event$status
    state <- if (is.null(event)) "unreviewed" else if (!identical(event$status, "accepted")) "deferred" else if (tolower(event$label) == "unknown") "abstained" else "labeled"
    label <- if (is.null(event) || !identical(event$status, "accepted")) NA_character_ else event$label
    decision_id <- if (is.null(event)) NA_character_ else event$id
    column <- columns[[dimension]]
    row <- target@meta.data[cell, , drop = FALSE]
    stopifnot(identical(as.character(row[[column]]), label),
              identical(as.character(row[[paste0(column, "_review_state")]]), state),
              identical(as.character(row[[paste0(column, "_workflow_status")]]), workflow),
              identical(as.character(row[[paste0(column, "_decision_id")]]), decision_id),
              identical(as.character(row[[paste0(column, "_source_fingerprint")]]), journal$sourceFingerprint),
              identical(as.character(row[[paste0(column, "_bundle_digest")]]), journal$bundleDigest))
    observed[[length(observed) + 1L]] <- list(cellId = cell, clusterId = cluster, dimension = dimension,
                                           label = label, reviewState = state, workflowStatus = workflow,
                                           decisionId = decision_id, sourceFingerprint = journal$sourceFingerprint,
                                           bundleDigest = journal$bundleDigest)
  }
  negatives <- list()
  source_dir <- dirname(object_file)
  for (name in c("same-barcodes-changed-counts", "same-barcodes-changed-membership", "same-barcodes-changed-data", "missing-cell")) {
    file <- file.path(source_dir, paste0(name, ".rds"))
    if (file.exists(file)) {
      candidate <- readRDS(file); frozen <- candidate
      rejection <- sc_review_validate(candidate, journal_file, project, columns)
      stopifnot(!isTRUE(rejection$valid))
      negatives[[name]] <- reject(name, function() sc_review_apply(candidate, journal_file, project, columns))
      stopifnot(identical(candidate, frozen))
    }
  }
  negatives$collision <- reject("requested column collision", function()
    sc_review_apply(original, journal_file, project, stats::setNames(names(original_seurat@meta.data)[1L], "type")))
  companion_collision <- original_seurat
  companion_collision$qa_review_type_decision_id <- "Original companion guard"
  companion_baseline <- companion_collision
  negatives$companionCollision <- reject("requested companion column collision", function()
    sc_review_apply(companion_collision, journal_file, project, columns))
  stopifnot(identical(companion_collision, companion_baseline))
  stopifnot(identical(original, baseline))
  equivalents <- list()
  for (name in c("permuted-equivalent", "dense-equivalent")) {
    file <- file.path(source_dir, paste0(name, ".rds"))
    if (file.exists(file)) {
      equivalent <- readRDS(file)
      check <- sc_review_validate(equivalent, journal_file, project, columns)
      stopifnot(isTRUE(check$valid))
      corrected <- .sc_project_unwrap(sc_review_apply(equivalent, journal_file, project, columns))
      output_columns <- unlist(lapply(unname(columns), function(column) paste0(column,
        c("", "_review_state", "_workflow_status", "_decision_id", "_source_fingerprint", "_bundle_digest"))), use.names = FALSE)
      for (column in output_columns) stopifnot(identical(
        corrected@meta.data[rownames(target@meta.data), column], target@meta.data[, column]))
      equivalents[[name]] <- "accepted; every cell matched by literal ID"
    }
  }
  write_json(list(schema = "scagentkit.qa-writeback.v1", outcome = "passed", cells = ncol(original_seurat),
                  eventCount = length(events), originalPreserved = TRUE, perCellColumnsChecked = 6L, perCellOracle = observed,
                  coverage = validated$coverage, negatives = negatives, equivalents = equivalents), report_file)
  invisible(applied)
}

if (!is.null(opts[["verify-journal"]])) {
  stopifnot(!is.null(opts[["project"]]), !is.null(opts[["object"]]), !is.null(opts[["report-file"]]))
  verify_writeback(opts[["verify-journal"]], opts[["project"]], opts[["object"]], opts[["report-file"]])
} else {
  if (is.null(opts[["output"]])) stop("--output is required.", call. = FALSE)
  output <- normalizePath(opts[["output"]], mustWork = FALSE)
  if (!identical(opts[["projects-only"]], "true")) make_sources(output)
  if (!identical(opts[["sources-only"]], "true")) export_projects(output)
  cat("Local QA fixtures:", output, "\n")
}
