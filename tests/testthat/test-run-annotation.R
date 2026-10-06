run_annotation_fixture <- function() {
  set.seed(483)
  genes <- c("ALB", "TTR", "CD3D", "CD3E", paste0("Gene", 5:60))
  cells <- c("001", "1", "NA", "cell space", paste0("cell", 5:60))
  counts <- matrix(stats::rpois(60 * 60, 1), nrow = 60,
                   dimnames = list(genes, cells))
  counts[1:2, 1:30] <- counts[1:2, 1:30] + 12L
  counts[3:4, 31:60] <- counts[3:4, 31:60] + 12L
  counts <- Matrix::Matrix(counts, sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- log1p(counts)
  object$seurat_clusters <- rep(c("01", "NA"), each = 30)
  object$prior_annotation <- rep(c("old liver", "old lymphoid"), each = 30)
  object$private_note <- "must stay local"
  object
}

run_annotation_marker_table <- function() {
  data.frame(cluster = c("01", "01", "NA", "NA"),
    gene = c("ALB", "TTR", "CD3D", "CD3E"), avg_log2FC = c(3, 2, 3, 2),
    pct.1 = rep(1, 4), pct.2 = rep(0.1, 4), p_val_adj = rep(0.001, 4),
    stringsAsFactors = FALSE)
}

run_annotation_evidence <- function(object = run_annotation_fixture()) {
  scAgentKit:::.sc_run_annotation_evidence(object, run_annotation_marker_table(),
    context = list(species = "human", tissue = "liver", description = "synthetic fixture"),
    reference = data.frame(cell_type = c("Hepatocyte", "Hepatocyte", "T cell", "T cell"),
      marker = c("ALB", "TTR", "CD3D", "CD3E"),
      tissue = "all", species = "human"))
}

run_annotation_proposal <- function() {
  list(schema = "scagentkit.annotation.v1", annotations = list(
    list(clusterId = "01", label = "Hepatocyte", confidence = "high",
         rationale = "ALB and TTR are supplied markers.", markers = list("ALB", "TTR")),
    list(clusterId = "NA", label = "T cell", confidence = "medium",
         rationale = "CD3D and CD3E are supplied markers.", markers = list("CD3D", "CD3E"))))
}

test_that("standard coordinator analysis reuses preparation and preserves its source", {
  object <- run_annotation_fixture()
  source <- object
  out <- suppressWarnings(scAgentKit:::.sc_run_analyze(object, list(
    analysis = list(nfeatures = 30, npcs = 3, dims = 1:3, run_umap = FALSE, seed = 483))))
  expect_identical(object, source)
  expect_identical(colnames(out), colnames(object))
  expect_identical(out$prior_annotation, object$prior_annotation)
  expect_true("pca" %in% names(out@reductions))
  expect_true("seurat_clusters" %in% names(out[[]]))
  expect_equal(out@misc$sc_project_prepare$effective$npcs, 3)
  expect_s4_class(SeuratObject::LayerData(out, assay = "RNA", layer = "counts"), "sparseMatrix")
  expect_error(scAgentKit:::.sc_run_analyze(object, list(analysis = list(eval = "system('id')"))), "Unsupported")
  expect_error(scAgentKit:::.sc_run_analyze(object, list(normalized_layer = "scale.data")), "writes.*data")
})

test_that("coordinator marker adapter uses exact selected layers and local wrappers", {
  object <- run_annotation_fixture()
  object$chosen_clusters <- object$seurat_clusters
  SeuratObject::LayerData(object, assay = "RNA", layer = "normalized") <-
    SeuratObject::LayerData(object, assay = "RNA", layer = "data")
  source <- object
  result <- suppressWarnings(scAgentKit:::.sc_run_markers(object, list(
    normalized_layer = "normalized", cluster_column = "chosen_clusters",
    markers = list(min_pct = 0.1, logfc_threshold = 0, top_n = 5,
                   log2fc_cut = 0.5, padj_cut = 0.05))))
  expect_identical(object, source)
  expect_gt(nrow(result$marker_summary), 0)
  expect_setequal(unique(result$markers$cluster), c("01", "NA"))
  expect_true(all(c("ALB", "TTR", "CD3D", "CD3E") %in% result$marker_summary$gene))
  expect_identical(result$cluster_column, "chosen_clusters")
  expect_error(scAgentKit:::.sc_run_markers(object, list(markers = list(min_pct = 2))), "Invalid")
  expect_error(scAgentKit:::.sc_run_markers(object, list(markers = list(code = "arbitrary"))), "Unsupported")
  split_object <- object
  split_object[["RNA"]] <- split(split_object[["RNA"]], f = rep(c("a", "b"), each = 30))
  expect_error(scAgentKit:::.sc_run_markers(split_object, list()), "Exact layer|Split")
})

test_that("annotation evidence keeps independent database results and IDs private", {
  object <- run_annotation_fixture()
  source <- object
  evidence <- run_annotation_evidence(object)
  expect_identical(object, source)
  expect_equal(vapply(evidence$summary$clusters, function(x) x$cellCount, integer(1)), c(30, 30))
  expect_setequal(evidence$private$candidates$cell_type, c("Hepatocyte", "T cell"))
  expect_identical(evidence$private$input_cells$cell_id, colnames(object))
  public <- scAgentKit:::.sc_project_json(evidence$summary)
  expect_false(grepl("private_note|must stay local|cell space|Hepatocyte|prior_annotation", public))
  # Database scoring mode and whether a model saw its candidates are separate.
  expect_identical(evidence$private$reference_provenance$mode, "local_marker_reference")
  expect_identical(evidence$summary$reference_mode, "independent")
  expect_null(evidence$summary$reference_candidates)
  no_database <- scAgentKit:::.sc_run_annotation_evidence(object,
    run_annotation_marker_table(), list(species = "human"))
  expect_equal(nrow(no_database$private$candidates), 0)
  expect_identical(no_database$private$reference_provenance$status, "not_supplied")
})

test_that("annotation proposals reject foreign IDs, hallucination genes and unsupported fields", {
  evidence <- run_annotation_evidence()
  proposal <- run_annotation_proposal()
  checked <- scAgentKit:::.sc_run_annotation_validate(proposal, evidence)
  expect_s3_class(checked, "sc_run_annotation_proposal")
  expect_identical(checked$annotations[[1]]$markers, list("ALB", "TTR"))
  foreign <- proposal
  foreign$annotations[[1]]$clusterId <- "1"
  expect_error(scAgentKit:::.sc_run_annotation_validate(foreign, evidence), "foreign cluster")
  hallucination <- proposal
  hallucination$annotations[[1]]$markers <- list("NOT-A-GENE")
  expect_error(scAgentKit:::.sc_run_annotation_validate(hallucination, evidence), "absent.*evidence")
  wrong_cluster_gene <- proposal
  wrong_cluster_gene$annotations[[1]]$markers <- list("CD3D")
  expect_error(scAgentKit:::.sc_run_annotation_validate(wrong_cluster_gene, evidence), "absent.*evidence")
  extra <- proposal
  extra$annotations[[1]]$code <- "arbitrary code"
  expect_error(scAgentKit:::.sc_run_annotation_validate(extra, evidence), "exactly")
  confidence <- proposal
  confidence$annotations[[1]]$confidence <- "very_high"
  expect_error(scAgentKit:::.sc_run_annotation_validate(confidence, evidence), "enum")
  scalar <- proposal
  scalar$annotations[[1]]$markers <- "ALB"
  expect_error(scAgentKit:::.sc_run_annotation_validate(scalar, evidence), "JSON array")
  duplicate <- proposal
  duplicate$annotations[[2]] <- duplicate$annotations[[1]]
  expect_error(scAgentKit:::.sc_run_annotation_validate(duplicate, evidence), "Duplicate")
  missing <- proposal
  missing$annotations <- missing$annotations[1]
  expect_error(scAgentKit:::.sc_run_annotation_validate(missing, evidence), "every evidence cluster")
  empty <- proposal
  empty$annotations <- list()
  expect_error(scAgentKit:::.sc_run_annotation_validate(empty, evidence), "nonempty")
})

test_that("unknown annotation remains explicit and requires no invented markers", {
  evidence <- run_annotation_evidence()
  proposal <- run_annotation_proposal()
  proposal$annotations[[1]]$markers <- list()
  expect_error(scAgentKit:::.sc_run_annotation_validate(proposal, evidence), "supporting marker")
  proposal$annotations[[1]]$label <- "Unknown"
  proposal$annotations[[1]]$confidence <- "low"
  checked <- scAgentKit:::.sc_run_annotation_validate(proposal, evidence)
  expect_identical(checked$annotations[[1]]$label, "Unknown")
  empty <- scAgentKit:::.sc_run_empty_markers()
  empty_evidence <- scAgentKit:::.sc_run_annotation_evidence(run_annotation_fixture(), empty, list())
  proposal$annotations[[2]]$label <- "Unknown"
  proposal$annotations[[2]]$confidence <- "low"
  proposal$annotations[[2]]$markers <- list()
  expect_s3_class(scAgentKit:::.sc_run_annotation_validate(proposal, empty_evidence), "sc_run_annotation_proposal")
})

test_that("annotation writeback is by exact cell IDs and preserves prior columns", {
  object <- run_annotation_fixture()
  source <- object
  checked <- scAgentKit:::.sc_run_annotation_validate(run_annotation_proposal(), run_annotation_evidence(object))
  reordered <- object[, rev(colnames(object))]
  out <- scAgentKit:::.sc_run_annotation_apply(reordered, checked)
  expect_identical(object, source)
  expect_identical(colnames(out), colnames(reordered))
  expect_identical(out$prior_annotation, reordered$prior_annotation)
  expect_identical(out$seurat_clusters, reordered$seurat_clusters)
  expect_identical(out$sc_annotation, ifelse(reordered$seurat_clusters == "01", "Hepatocyte", "T cell"))
  expect_identical(out$sc_annotation_confidence,
                   ifelse(reordered$seurat_clusters == "01", "high", "medium"))
  expect_equal(SeuratObject::LayerData(out, assay = "RNA", layer = "counts"),
               SeuratObject::LayerData(reordered, assay = "RNA", layer = "counts"))
  expect_error(scAgentKit:::.sc_run_annotation_apply(object, run_annotation_proposal()), "Validate")
  changed <- object
  changed$seurat_clusters[1] <- "NA"
  expect_error(scAgentKit:::.sc_run_annotation_apply(changed, checked), "cell IDs or cluster")
  expect_error(scAgentKit:::.sc_run_annotation_apply(object[, -1], checked), "cell IDs or cluster")
  expect_error(scAgentKit:::.sc_run_annotation_apply(out, checked), "already exist")
  next_version <- scAgentKit:::.sc_run_annotation_apply(out, checked, column = "sc_annotation_v2")
  expect_identical(next_version$sc_annotation, out$sc_annotation)
  expect_identical(next_version$sc_annotation_v2, out$sc_annotation)
})

test_that("managed bundle uses directory export and verifies repeated use", {
  object <- run_annotation_fixture()
  evidence <- run_annotation_evidence(object)
  checked <- scAgentKit:::.sc_run_annotation_validate(run_annotation_proposal(), evidence)
  annotated <- scAgentKit:::.sc_run_annotation_apply(object, checked)
  project <- tempfile("managed-bundle-")
  on.exit(unlink(project, recursive = TRUE), add = TRUE)
  export <- scAgentKit:::.sc_run_bundle(annotated, run_annotation_marker_table(), evidence, project, list())
  expect_identical(export$path, file.path(normalizePath(project), "bundle"))
  expect_null(export$archive)
  expect_false(file.exists(paste0(export$path, ".zip")))
  content <- paste(readLines(file.path(export$path, "project.json")), collapse = "\n")
  expect_false(grepl("must stay local|private_note", content))
  repeated <- scAgentKit:::.sc_run_bundle(annotated, run_annotation_marker_table(), evidence, project, list())
  expect_identical(repeated$bundleDigest, export$bundleDigest)
  changed_markers <- run_annotation_marker_table()
  changed_markers$avg_log2FC[1] <- 4
  expect_error(scAgentKit:::.sc_run_bundle(annotated, changed_markers, evidence, project, list()), "Existing bundle differs")
  expect_identical(paste(readLines(file.path(export$path, "project.json")), collapse = "\n"), content)
  cat("\n", file = file.path(export$path, "project.json"), append = TRUE)
  expect_error(scAgentKit:::.sc_run_bundle(annotated, run_annotation_marker_table(), evidence, project, list()), "corrupt")
  expect_false(any(grepl("^\\.sc-run-bundle-", list.files(project, all.files = TRUE))))
})
