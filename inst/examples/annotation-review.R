#!/usr/bin/env Rscript
# Offline synthetic processed-entry review with one main run and few operations.
# Each CLI invocation can use a new R process. No provider, key or API is used.
# Rscript --vanilla annotation-review.R PROJECT_DIR run|inspect|revise|approve|reject|resume|output|undo|renew
# inspect displays AND saves a snapshot. Decisions use that saved snapshot.
# The scripted decisions are specific to this synthetic mechanism example.

suppressPackageStartupMessages(library(scAgentKit))
if (!"sc_run_review" %in% getNamespaceExports("scAgentKit"))
  stop("Install this checkout's unified-review package in the selected R library before starting a project.", call. = FALSE)

make_annotation_review_input <- function() {
  set.seed(73126)
  modules <- list(A = c("MARK-A1", "MARK-A2", "MARK-A3", "MARK-A4"),
                  B = c("MARK-B1", "MARK-B2", "MARK-B3", "MARK-B4"),
                  C = c("MARK-C1", "MARK-C2", "MARK-C3", "MARK-C4"))
  genes <- c(unlist(modules, use.names = FALSE), sprintf("feature%03d", 1:288))
  cells <- c("001", "1", "NA", "cell space", sprintf("toy-cell-%03d", 5:144))
  counts <- Matrix::rsparsematrix(length(genes), length(cells), density = .25,
    rand.x = function(n) 1 + stats::rpois(n, 1))
  dimnames(counts) <- list(genes, cells)
  groups <- rep(names(modules), each = 48)
  for (group in names(modules)) {
    counts[modules[[group]], groups == group] <- matrix(
      20 + stats::rpois(length(modules[[group]]) * sum(groups == group), 3),
      nrow = length(modules[[group]]))
  }
  raw <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  raw$sample_id <- rep(c("sample A", "sample B"), length.out = ncol(raw))
  raw$capture_id <- rep(rep(c("capture|1", "capture|2"), each = 24), 3)
  raw$condition <- rep(c("vehicle", "treatment"), length.out = ncol(raw))
  raw$old_annotation <- factor(rep(c("earlier-label", NA_character_), length.out = ncol(raw)))
  # Create an already processed toy before entering the coordinator. For an
  # existing study, give sc_run its verified object and omit this preparation.
  processed <- sc_project_prepare(raw, nfeatures = 150L, npcs = 10L, dims = 1:8,
    resolution = .3, seed = 73126L, umap_neighbors = 15L)
  # Explicit pre-existing synthetic cluster IDs test literal ID handling. They
  # describe planted toy programs, not accepted biological identities.
  processed$toy_cluster <- factor(rep(c("001", "1", "group C"), each = 48),
                                 levels = c("001", "1", "group C", "unused"))
  processed
}

annotation_review_unknown <- function(clusters) {
  list(schema = "scagentkit.annotation.v1", annotations = lapply(clusters,
    function(cluster) list(clusterId = cluster$clusterId, label = "Unknown",
      confidence = "low", rationale = "Manual toy placeholder; no biological identity accepted.",
      markers = list())))
}

annotation_review_snapshot <- function(current) {
  node <- current$review_node
  if (is.null(node) || !identical(node$kind, "annotation"))
    stop("No annotation snapshot is available for inspection.", call. = FALSE)
  list(binding = node[c("kind", "project_id", "input_hash", "proposal_hash",
                       "review_hash", "expected_revision")],
       decision_id = node$decision_id, can_undo = node$can_undo,
       proposal = current$annotation_review$details$canonical_proposal,
       rows = current$annotation_review$details$annotations)
}

annotation_review_print <- function(current) {
  cat("Status:", current$status, "Stage:", current$stage, "Revision:", current$revision, "\n")
  record <- current$annotation_review
  if (!is.null(record)) {
    cat("Source of current proposal:", record$details$source$kind, "\n")
    cat("Exact cell scope:", record$details$cell_count, "cells;",
        record$details$cluster_count, "clusters.\n")
    cat("Cell-scope fingerprint:", record$cell_scope_hash, "\n")
    cat("New output columns:\n"); print(record$details$output_columns)
    for (row in record$details$annotations) {
      cat("\nLiteral cluster:", row$clusterId, "Cells:", row$cell_count, "\n")
      print(row$proposal)
      cat("Supplied marker statistics only; showing first", min(5L, length(row$supplied_marker_stats)),
          "of", length(row$supplied_marker_stats), "saved rows:\n")
      if (length(row$supplied_marker_stats)) print(do.call(rbind, lapply(
        head(row$supplied_marker_stats, 5L), as.data.frame, stringsAsFactors = FALSE)))
      else cat("No supplied marker rows; absence here does not imply absent expression.\n")
      cat("Saved independent local-reference status:", row$local_reference$status, "\n")
      cat("Independent negative evidence assessed:", row$negative_evidence$assessed, "\n")
    }
    cat("\nLimitations:\n"); cat(paste("*", record$details$limitations), sep = "\n")
    cat("\nSnapshot bindings:\n"); print(current$review_node)
  }
  if (!is.null(current$output)) print(current$output)
  invisible(current)
}

annotation_review_decide <- function(project_dir, snapshot, action, reason,
                                      proposal = NULL, decision_id = NULL) {
  arguments <- c(list(project_dir = project_dir, action = action,
                      reviewer = "synthetic-example-analyst", reason = reason), snapshot$binding)
  if (!is.null(proposal)) arguments$proposal <- proposal
  if (!is.null(decision_id)) arguments$decision_id <- decision_id
  do.call(sc_run_review, arguments)
}

annotation_review_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("run", "inspect", "revise", "approve", "reject", "resume", "output", "undo", "renew")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: annotation-review.R PROJECT_DIR run|inspect|revise|approve|reject|resume|output|undo|renew", call. = FALSE)
  project_dir <- args[[1L]]; mode <- args[[2L]]
  snapshot_file <- file.path(project_dir, "example-reviewed-annotation.rds")
  integrity_file <- file.path(project_dir, "example-processed-integrity.rds")
  if (mode == "run") {
    original <- make_annotation_review_input()
    source_hash <- digest::digest(original, algo = "sha256")
    expected <- list(cells = colnames(original), clusters = original$toy_cluster,
      old_annotation = original$old_annotation,
      normalized_hash = digest::digest(SeuratObject::LayerData(original, assay = "RNA", layer = "data"), algo = "sha256"),
      pca_hash = digest::digest(original[["pca"]], algo = "sha256"),
      umap_hash = digest::digest(original[["umap"]], algo = "sha256"))
    result <- sc_run(original, project_dir, context = list(species = "human",
      tissue = "synthetic planted programs", columns = list(sample = "sample_id",
        capture = "capture_id", condition = "condition"),
      notes = "Synthetic mechanism example. Captures are not donors; condition is not batch; no reference supplied."),
      start_stage = "processed",
      processed_reason = "The synthetic toy was prepared before entry with sc_project_prepare; reuse normalized RNA, PCA, UMAP and its explicit planted-program toy_cluster membership.",
      cluster_column = "toy_cluster", annotation_column = "reviewed_identity",
      provider = NULL, budget = 0, review = list(allow_external = FALSE))
    stopifnot(identical(source_hash, digest::digest(original, algo = "sha256")),
      result$status == "awaiting_configuration", result$stage == "annotation_propose",
      all(c("qc_evidence", "qc_propose", "qc_apply", "analysis") %in% result$completed))
    saveRDS(expected, integrity_file)
    evidence <- sc_run_inspect(project_dir)$evidence
    sc_run_propose(project_dir, annotation_review_unknown(evidence$clusters),
      reviewer = "synthetic-example-analyst", reason = "Initial manual Unknown toy proposal; no model or external transmission.")
    result <- sc_run_inspect(project_dir)
  } else if (mode == "inspect") {
    result <- sc_run_inspect(project_dir)
    annotation_review_print(result)
    saveRDS(annotation_review_snapshot(result), snapshot_file)
    cat("Displayed snapshot saved. Decisions will use these exact bindings.\n")
    return(invisible(result))
  } else if (mode %in% c("revise", "approve", "reject", "undo", "renew")) {
    if (!file.exists(snapshot_file)) stop("Run inspect and review its output before deciding.", call. = FALSE)
    snapshot <- readRDS(snapshot_file)
    if (mode == "revise") {
      replacement <- snapshot$proposal
      first <- snapshot$rows[[1L]]
      if (length(first$supplied_marker_stats)) {
        replacement$annotations[[1L]]$label <- "Toy program-positive cells"
        replacement$annotations[[1L]]$confidence <- "medium"
        replacement$annotations[[1L]]$markers <- list(first$supplied_marker_stats[[1L]]$gene)
        replacement$annotations[[1L]]$rationale <- "Coarse toy-program label cites a supplied marker; no biological identity or subtype accepted."
      } else stop("No supplied marker supports the toy coarse-label demonstration; retain Unknown.", call. = FALSE)
      result <- annotation_review_decide(project_dir, snapshot, "revise",
        "Record an explicit coarse toy-program correction based on supplied local marker evidence.", proposal = replacement)
      cat("Replacement saved. Inspect its fresh snapshot before approval.\n")
    } else if (mode == "renew") {
      replacement <- annotation_review_unknown(snapshot$rows)
      result <- annotation_review_decide(project_dir, snapshot, "revise",
        "Fresh manual Unknown proposal after undo/rejection; reopen explicit toy review.", proposal = replacement)
      cat("Fresh proposal saved. Inspect before approval.\n")
    } else if (mode == "undo") {
      if (!isTRUE(snapshot$can_undo)) stop("The inspected annotation was not an executed current decision.", call. = FALSE)
      result <- annotation_review_decide(project_dir, snapshot, "undo",
        "Reopen executed toy labels for explicit review; preserve archived outputs and history.", decision_id = snapshot$decision_id)
    } else result <- annotation_review_decide(project_dir, snapshot, mode,
      if (mode == "approve") "Reviewed the exact synthetic annotation snapshot and its limitations; approve this mechanism demonstration."
      else "Reject the inspected toy annotation proposal; do not apply its labels.")
  } else if (mode == "resume") result <- sc_run_resume(project_dir)
  else {
    result <- sc_run_inspect(project_dir)
    if (!identical(result$status, "complete")) stop("No current completed output; approve then explicitly resume first.", call. = FALSE)
    final <- readRDS(result$output$seurat)
    expected <- readRDS(integrity_file)
    stopifnot(identical(colnames(final), expected$cells),
      identical(final$toy_cluster, expected$clusters),
      identical(final$old_annotation, expected$old_annotation),
      identical(digest::digest(SeuratObject::LayerData(final, assay = "RNA", layer = "data"), algo = "sha256"), expected$normalized_hash),
      identical(digest::digest(final[["pca"]], algo = "sha256"), expected$pca_hash),
      identical(digest::digest(final[["umap"]], algo = "sha256"), expected$umap_hash),
      all(c("reviewed_identity", "reviewed_identity_confidence", "reviewed_identity_rationale") %in% names(final[[]])))
    cat("Final:", result$output$seurat, "\n")
    print(table(final$reviewed_identity))
    cat("Exact IDs, prior annotation, normalized RNA, PCA and UMAP preserved; zero API requests.\n")
  }
  annotation_review_print(result)
  if (identical(result$status, "failed")) stop(result$failure$message, call. = FALSE)
  invisible(result)
}

if (sys.nframe() == 0L) annotation_review_main()
