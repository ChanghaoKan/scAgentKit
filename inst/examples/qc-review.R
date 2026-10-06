#!/usr/bin/env Rscript
# Offline, non-PBMC synthetic QC review. Install this package version first.
# Rscript --vanilla qc-review.R /durable/path/to/new-project run
# Rscript --vanilla qc-review.R /durable/path/to/new-project inspect
# Rscript --vanilla qc-review.R /durable/path/to/new-project approve
# Rscript --vanilla qc-review.R /durable/path/to/new-project resume
# Rscript --vanilla qc-review.R /durable/path/to/new-project inspect
# The last step stops at manual annotation configuration, with no API request.
# The approve command is for this deliberately synthetic mechanism example.
# For a study, make the decision and give its actual rationale in R as in the guide.

suppressPackageStartupMessages(library(scAgentKit))

make_qc_review_input <- function() {
  set.seed(62026)
  modules <- list(
    epithelial = c("EPCAM", "KRT8", "KRT18", "KRT19", "KRT7", "MUC1", "TACSTD2", "CLDN3"),
    stromal = c("COL1A1", "COL1A2", "COL3A1", "DCN", "LUM", "COL6A1", "COL6A2", "PDGFRA"),
    endothelial = c("PECAM1", "VWF", "KDR", "EMCN", "ENG", "RAMP2", "ESAM", "CDH5"))
  genes <- c(unlist(modules, use.names = FALSE), "MT-CO1", sprintf("feature%03d", 1:575))
  cells <- c("001", "1", "NA", "cell space", sprintf("toy-cell-%03d", 5:180))
  counts <- Matrix::rsparsematrix(length(genes), length(cells), density = .15,
    rand.x = function(n) 1 + stats::rpois(n, 1))
  dimnames(counts) <- list(genes, cells)
  population <- rep(names(modules), each = 60)
  for (name in names(modules)) {
    selected <- population == name
    counts[modules[[name]], selected] <- matrix(
      8 + stats::rpois(length(modules[[name]]) * sum(selected), 4),
      nrow = length(modules[[name]]))
  }
  counts["MT-CO1", ] <- 1
  # Deliberate toy controls: one zero-count cell and five sparse low-depth cells.
  # Their planted origin is not a biological QC benchmark.
  counts[, 1:6] <- 0
  counts["feature001", 2:6] <- 3
  counts["feature002", 2:6] <- 2
  toy <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  toy$sample_id <- rep(rep(c("sample A", "sample B"), each = 30), 3)
  toy$capture_id <- rep(c("capture|1", "capture|2"), length.out = ncol(toy))
  toy$condition <- rep(c("vehicle", "treatment"), length.out = ncol(toy))
  toy$old_annotation <- factor(rep(c("earlier-label", NA_character_), length.out = ncol(toy)))
  toy
}

qc_review_rules <- function(feature_min = 30, count_min = 25) list(
  schema = "scagentkit.qc.v1",
  rationale = "Explicit fixed toy cutoffs for testing review mechanics; not optimized for biology.",
  risks = c("Low-depth cells may be real; these synthetic cutoffs are not study recommendations.",
            "Positive expression and gene availability do not establish QC validity."),
  filters = list(list(op = "range", metric = "nFeature", min = feature_min),
                 list(op = "range", metric = "nCount", min = count_min),
                 list(op = "range", metric = "percent_mt", max = 10),
                 list(op = "range", metric = "nCount", max = 500,
                      group = list(sample = "sample A", capture = "capture|1"))))

qc_review_print <- function(current) {
  cat("Status:", current$status, "Stage:", current$stage, "Revision:", current$revision, "\n")
  if (!is.null(current$qc_preview)) {
    record <- current$qc_preview
    details <- record$details
    print(as.data.frame(details$retention[c("before", "retained", "removed", "fraction_retained")]))
    print(do.call(rbind, lapply(details$filter_impacts, function(item)
      data.frame(id = item$id, metric = item$filter$metric, scoped = item$scoped,
        low = item$low, high = item$high, unavailable = item$unavailable,
        independent = item$independently_removed, exclusive = item$exclusively_removed))))
    cat("Exact removed cells:\n"); print(details$remove_cells)
    overlap <- do.call(rbind, lapply(details$overlap$counts, unlist, use.names = FALSE))
    dimnames(overlap) <- list(details$overlap$filter_ids, details$overlap$filter_ids)
    cat("Measured exclusion overlap matrix:\n"); print(overlap)
    cat("Unavailable metric counts:\n")
    print(do.call(rbind, lapply(details$unavailable$metrics, function(item)
      data.frame(metric = item$metric, unavailable = item$count))))
    cat("Zero-count cells:\n"); print(details$unavailable$zero_count_cells)
    cat("Gene availability only, not expression or quality:\n")
    print(lapply(details$unavailable$gene_panels, function(item)
      item[c("id", "unavailable_genes", "unknown_genes", "expression_assessed")]))
    if (length(details$sensitivity)) print(do.call(rbind, lapply(details$sensitivity, function(item)
      data.frame(id = item$id, retained = item$retention$retained,
                 added = item$added, removed_from_primary = item$removed_from_primary))))
    cat("Local before/retained/removed distributions:\n")
    print(do.call(rbind, lapply(names(details$distributions$global), function(population)
      do.call(rbind, lapply(c("nCount", "nFeature", "percent_mt"), function(metric) {
        values <- details$distributions$global[[population]]$metrics[[metric]]
        data.frame(population = population, metric = metric, measured = values$measured,
                   missing = values$missing, median = values$median)
      })))))
    cat("Local QC plot:", if (is.null(current$project_dir)) record$plots$distributions
      else file.path(current$project_dir, record$plots$distributions), "\n")
  }
  if (identical(current$stage, "annotation_propose")) {
    cat("Annotation evidence is ready. Supply a typed manual annotation proposal or explicitly configure a provider.\n")
    cat("This example supplies neither, so it makes no model request and stops here.\n")
  }
  invisible(current)
}

qc_review_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (length(args) != 2L || !args[[2L]] %in% c("run", "inspect", "approve", "reject", "resume"))
    stop("Usage: qc-review.R PROJECT_DIR run|inspect|approve|reject|resume", call. = FALSE)
  project_dir <- args[[1L]]
  mode <- args[[2L]]
  snapshot_file <- file.path(project_dir, "example-reviewed-snapshot.rds")
  if (mode == "run") {
    toy <- make_qc_review_input()
    input_hash <- digest::digest(toy, algo = "sha256")
    result <- sc_run(toy, project_dir = project_dir,
      context = list(species = "human", tissue = "synthetic epithelial/stromal/endothelial mixture",
        columns = list(sample = "sample_id", capture = "capture_id", condition = "condition"),
        notes = "Synthetic mechanism test. Literal captures are not donors; condition is not a batch. Integration is skipped."),
      provider = NULL, budget = 0, review = list(allow_external = FALSE),
      qc_proposal = qc_review_rules(),
      qc_preview = list(sensitivity = list(
        list(id = "feature lower bound 1", proposal = qc_review_rules(feature_min = 1)),
        list(id = "both lower bounds 1", proposal = qc_review_rules(feature_min = 1, count_min = 1))),
        gene_panels = list(epithelial = c("EPCAM", "KRT8"),
                           endothelial = c("PECAM1", "VWF", "UNMEASURED_GENE"))),
      analysis = list(nfeatures = 200L, npcs = 12L, dims = 1:10, resolution = .3,
                      seed = 62026L, umap_neighbors = 20L),
      annotation_column = "reviewed_annotation")
    stopifnot(identical(input_hash, digest::digest(toy, algo = "sha256")))
    result <- sc_run_inspect(project_dir)
  } else if (mode == "inspect") {
    result <- sc_run_inspect(project_dir)
    if (result$status == "awaiting_review" && identical(result$pending$kind, "qc"))
      saveRDS(list(proposal_hash = result$pending$hash, preview_hash = result$qc_preview$hash,
                   expected_revision = result$revision), snapshot_file)
  } else if (mode %in% c("approve", "reject")) {
    if (!file.exists(snapshot_file)) stop("Run inspect and review its output before deciding.", call. = FALSE)
    snapshot <- readRDS(snapshot_file)
    # Use the inspected snapshot, not a newly fetched unseen proposal. Revision
    # or hash changes make the decision stale and require another inspection.
    result <- do.call(if (mode == "approve") sc_run_approve else sc_run_reject,
      c(list(project_dir = project_dir, reviewer = "synthetic-example-analyst",
        reason = if (mode == "approve") "Reviewed the exact fixed synthetic rule and impact; approve this mechanism demonstration."
          else "Reject the fixed synthetic rule after inspecting its impact."), snapshot))
  } else result <- sc_run_resume(project_dir)
  result$project_dir <- normalizePath(project_dir, mustWork = TRUE)
  qc_review_print(result)
  if (identical(result$status, "failed")) stop(result$failure$message, call. = FALSE)
  invisible(result)
}

if (sys.nframe() == 0L) qc_review_main()
