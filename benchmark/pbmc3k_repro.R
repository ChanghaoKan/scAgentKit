#!/usr/bin/env Rscript
# Local PBMC3k workflow smoke test and deterministic decision replay.
# No provider is constructed or called. Reference labels are evaluation-only.

parse_cli <- function(args) {
  defaults <- list(mode = "run", counts_dir = "", truth_csv = "", out_dir = "",
                   run_dir = "", library_dir = "", seed = "999", ncells = "800")
  if ("--help" %in% args) {
    cat(paste(
      "Run: Rscript benchmark/pbmc3k_repro.R --counts_dir PATH --out_dir PATH",
      "     [--truth_csv PATH] [--ncells 800] [--seed 999] [--library_dir PATH]",
      "Replay: Rscript benchmark/pbmc3k_repro.R --mode replay --run_dir PATH",
      "        --out_dir NEW_PATH [--library_dir PATH]",
      "Inputs must already be local. This script makes no network or LLM calls.",
      sep = "\n"), "\n")
    quit(status = 0L)
  }
  if (length(args) %% 2L) stop("Arguments must be --name value pairs; see --help.")
  if (length(args)) for (i in seq.int(1L, length(args), by = 2L)) {
    key <- sub("^--", "", args[[i]])
    if (!startsWith(args[[i]], "--") || !key %in% names(defaults)) {
      stop("Unknown argument: ", args[[i]])
    }
    defaults[[key]] <- args[[i + 1L]]
  }
  if (!defaults$mode %in% c("run", "replay")) stop("mode must be run or replay.")
  if (!nzchar(defaults$out_dir)) stop("--out_dir is required.")
  defaults
}

opt <- parse_cli(commandArgs(trailingOnly = TRUE))
if (nzchar(opt$library_dir)) .libPaths(c(normalizePath(opt$library_dir), .libPaths()))
if (dir.exists(opt$out_dir) && length(list.files(opt$out_dir, all.files = TRUE,
                                              no.. = TRUE))) {
  stop("Output directory must be empty; use a new directory to preserve prior runs.")
}
dir.create(opt$out_dir, recursive = TRUE, showWarnings = FALSE)
out_dir <- normalizePath(opt$out_dir)
writeLines(c("status: starting", paste("mode:", opt$mode),
             paste("started_utc:", format(Sys.time(), tz = "UTC", usetz = TRUE))),
           file.path(out_dir, "run_status.txt"))
options(error = function() {
  writeLines(c("status: failed", paste("error:", geterrmessage())),
             file.path(out_dir, "run_status.txt"))
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  quit(status = 1L)
})

required <- c("Seurat", "SeuratObject", "scAgentKit", "agentomicsCore", "Matrix", "jsonlite")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  writeLines(paste("status: failed; missing packages:", paste(missing, collapse = ", ")),
             file.path(out_dir, "run_status.txt"))
  stop("Missing packages in the selected R library: ", paste(missing, collapse = ", "),
       ". The harness never installs dependencies.")
}
if (utils::packageVersion("Seurat") < "5.0.0") stop("Seurat >= 5.0.0 is required.")
options(Seurat.object.assay.version = "v5", mc.cores = 1L, scAgentKit.verbose = FALSE)
if (requireNamespace("future", quietly = TRUE)) future::plan(future::sequential)
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1")
RNGkind("Mersenne-Twister", "Inversion", "Rejection")

write_csv <- function(x, name) utils::write.csv(x, file.path(out_dir, name), row.names = FALSE)
md5 <- function(path) unname(tools::md5sum(path))
versions <- function(packages = loadedNamespaces()) {
  packages <- sort(unique(packages))
  data.frame(package = packages,
             version = vapply(packages, function(p) as.character(utils::packageVersion(p)), character(1)),
             stringsAsFactors = FALSE)
}
package_code_manifest <- function() {
  do.call(rbind, lapply(c("scAgentKit", "agentomicsCore"), function(package) {
    root <- find.package(package)
    files <- c("DESCRIPTION", file.path("R", paste0(package, c(".rdb", ".rdx"))))
    # vapply would otherwise name hashes with absolute installed paths,
    # which data.frame inherits as row names and makes a relocated copy
    # fail identical() despite byte-identical package files.
    hashes <- unname(vapply(file.path(root, files), md5, character(1), USE.NAMES = FALSE))
    data.frame(package = package, file = files,
               md5 = hashes, stringsAsFactors = FALSE, row.names = NULL)
  }))
}
source_args <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", source_args[startsWith(source_args, "--file=")][1L])
script_path <- normalizePath(script_path, mustWork = TRUE)
writeLines(readLines(script_path, warn = FALSE), file.path(out_dir, "harness.R"))

check_input <- function(counts) {
  if (!inherits(counts, "sparseMatrix")) stop("Expected a sparse gene-by-cell count matrix.")
  if (is.null(rownames(counts)) || is.null(colnames(counts)) ||
      anyDuplicated(rownames(counts)) || anyDuplicated(colnames(counts))) {
    stop("Unique non-empty gene names and cell barcodes are required.")
  }
  if (any(!nzchar(rownames(counts))) || any(!nzchar(colnames(counts))) ||
      any(!is.finite(counts@x)) || any(counts@x < 0) || any(counts@x != round(counts@x))) {
    stop("Counts must be finite nonnegative integers with non-empty IDs.")
  }
  invisible(TRUE)
}

if (opt$mode == "run") {
  if (!nzchar(opt$counts_dir) || !dir.exists(opt$counts_dir)) stop("Local --counts_dir is required.")
  seed <- suppressWarnings(as.integer(opt$seed))
  ncells <- suppressWarnings(as.integer(opt$ncells))
  if (is.na(seed) || is.na(ncells) || ncells < 60L) stop("Use an integer seed and ncells >= 60.")
  counts_dir <- normalizePath(opt$counts_dir)
  raw_files <- sort(list.files(counts_dir, recursive = TRUE, full.names = TRUE))
  raw_files <- raw_files[!dir.exists(raw_files)]
  source_manifest <- data.frame(file = substring(raw_files, nchar(counts_dir) + 2L),
                                md5 = vapply(raw_files, md5, character(1)))
  write_csv(source_manifest, "raw_input_manifest.csv")
  counts <- Seurat::Read10X(counts_dir, gene.column = 2L, unique.features = TRUE)
  if (is.list(counts)) {
    if (!"Gene Expression" %in% names(counts)) stop("10X input has no Gene Expression matrix.")
    counts <- counts[["Gene Expression"]]
  }
  check_input(counts)
  set.seed(seed)
  barcodes <- sort(sample(sort(colnames(counts)), min(ncells, ncol(counts))))
  counts <- counts[, barcodes, drop = FALSE]
  saveRDS(counts, file.path(out_dir, "input_counts.rds"), version = 3L)
  # These choices are fixed before seeing reference labels or cluster results.
  decisions <- list(schema_version = 1L, decision_source = "fixed_analyst_baseline",
                    llm_calls = 0L, script_md5 = md5(script_path),
                    R_version = R.version.string, rng_kind = RNGkind(), seed = seed,
                    package_code_manifest = package_code_manifest(),
                    selected_barcodes = barcodes, input_md5 = md5(file.path(out_dir, "input_counts.rds")),
                    raw_input_manifest = source_manifest,
                    params = list(project = "PBMC3k_blind", min_cells_per_gene = 3L,
                                  min_ncount = 0, min_nfeature = 200, max_nfeature = 2500,
                                  max_percent_mt = 5, min_percent_mt = 0,
                                  normalization = "LogNormalize", scale_factor = 10000,
                                  hvg_method = "vst", nfeatures = 2000L,
                                  npcs = 30L, ndim = 10L, pca_seed = 42L,
                                  resolution = 0.5, clustering_algorithm = 1L,
                                  clustering_seed = 0L, umap_seed = 42L,
                                  marker_only_pos = FALSE, marker_min_pct = 0.25,
                                  marker_logfc = 0, marker_summary_top_n = 30L,
                                  marker_summary_log2fc_cut = 1,
                                  marker_summary_padj_cut = 0.05, tissue = "blood"))
  # Truth is deliberately neither read nor carried in this decision object.
} else {
  if (!nzchar(opt$run_dir) || !dir.exists(opt$run_dir)) stop("--run_dir must identify a prior run.")
  run_dir <- normalizePath(opt$run_dir)
  if (!any(readLines(file.path(run_dir, "run_status.txt"), warn = FALSE) == "status: success")) {
    stop("Replay requires a successful prior run; inspect its status and steps first.")
  }
  decisions <- readRDS(file.path(run_dir, "decisions.rds"))
  if (!identical(decisions$schema_version, 1L) || !identical(decisions$llm_calls, 0L) ||
      !identical(decisions$decision_source, "fixed_analyst_baseline")) {
    stop("Unsupported decision file; this harness replays only saved offline baseline decisions.")
  }
  if (!identical(decisions$R_version, R.version.string)) stop("R version differs from the saved run.")
  if (!identical(decisions$script_md5, md5(script_path))) stop("Harness source differs from the saved run.")
  if (!identical(decisions$package_code_manifest, package_code_manifest())) {
    stop("Installed scAgentKit/agentomicsCore code differs from the saved run.")
  }
  expected_versions <- decisions$package_versions
  for (i in seq_len(nrow(expected_versions))) {
    p <- expected_versions$package[[i]]
    if (!requireNamespace(p, quietly = TRUE) ||
        as.character(utils::packageVersion(p)) != expected_versions$version[[i]]) {
      stop("Replay package version mismatch: ", p)
    }
  }
  input_path <- file.path(run_dir, "input_counts.rds")
  if (!identical(decisions$input_md5, md5(input_path))) stop("Saved input checksum mismatch.")
  counts <- readRDS(input_path)
  check_input(counts)
  if (!identical(colnames(counts), decisions$selected_barcodes)) stop("Saved barcode order mismatch.")
  if (!file.copy(input_path, file.path(out_dir, "input_counts.rds"))) stop("Could not copy replay input.")
  do.call(RNGkind, as.list(decisions$rng_kind))
}
saveRDS(decisions, file.path(out_dir, "decisions.rds"), version = 3L)
jsonlite::write_json(decisions, file.path(out_dir, "decisions.json"), pretty = TRUE, auto_unbox = TRUE)
write_csv(data.frame(cell_id = decisions$selected_barcodes), "selected_barcodes.csv")
write_csv(decisions$raw_input_manifest, "raw_input_manifest.csv")
p <- decisions$params

# Both methods receive a fresh object built from raw counts and no labels.
new_input <- function() {
  seu <- Seurat::CreateSeuratObject(counts, project = p$project,
                                    min.cells = p$min_cells_per_gene, min.features = 0)
  if (!inherits(seu[["RNA"]], "Assay5")) stop("Expected a Seurat5 Assay5 input.")
  if (!identical(colnames(seu@meta.data), c("orig.ident", "nCount_RNA", "nFeature_RNA"))) {
    stop("Unexpected input metadata; refusing possible reference-label leakage.")
  }
  seu
}
saveRDS(new_input(), file.path(out_dir, "blind_input_seurat.rds"), version = 3L)
blind_meta <- new_input()@meta.data
write_csv(data.frame(cell_id = rownames(blind_meta), blind_meta), "blind_input_metadata.csv")

step_rows <- list()
step <- function(method, name, expr) {
  started <- Sys.time()
  warnings <- character()
  status <- "success"
  error <- ""
  result <- tryCatch(withCallingHandlers(force(expr), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) {
    status <<- "failed"
    error <<- conditionMessage(e)
    NULL
  })
  step_rows[[length(step_rows) + 1L]] <<- data.frame(
    method = method, step = name, status = status,
    started_utc = format(started, tz = "UTC", usetz = TRUE),
    elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    warnings = paste(unique(warnings), collapse = " | "), error = error)
  write_csv(do.call(rbind, step_rows), "steps.csv")
  if (status == "failed") stop(error, call. = FALSE)
  result
}
run_method <- function(method) {
  set.seed(decisions$seed)
  if (method == "seurat5_fixed") {
    seu <- step(method, "create_input", new_input())
    seu <- step(method, "qc_add_metrics", {
      seu[["percent.mt"]] <- Seurat::PercentageFeatureSet(seu, pattern = "^MT-")
      seu[["percent.ribo"]] <- Seurat::PercentageFeatureSet(seu, pattern = "^RP[SL]")
      seu[["percent.hb"]] <- Seurat::PercentageFeatureSet(seu, pattern = "^HB[AB]")
      seu
    })
    seu <- step(method, "qc_threshold", subset(seu, cells = colnames(seu)[
      seu$nCount_RNA > p$min_ncount & seu$nFeature_RNA > p$min_nfeature &
        seu$nFeature_RNA < p$max_nfeature & seu$percent.mt < p$max_percent_mt &
        seu$percent.mt >= p$min_percent_mt]))
    seu <- step(method, "normalize", Seurat::NormalizeData(seu,
      normalization.method = p$normalization, scale.factor = p$scale_factor, verbose = FALSE))
    seu <- step(method, "hvg", Seurat::FindVariableFeatures(seu,
      selection.method = p$hvg_method, nfeatures = p$nfeatures, verbose = FALSE))
    seu <- step(method, "scale", Seurat::ScaleData(seu, features = Seurat::VariableFeatures(seu), verbose = FALSE))
    seu <- step(method, "pca", Seurat::RunPCA(seu, features = Seurat::VariableFeatures(seu),
      npcs = p$npcs, seed.use = p$pca_seed, verbose = FALSE))
    seu <- step(method, "neighbors", Seurat::FindNeighbors(seu, reduction = "pca",
      dims = seq_len(p$ndim), verbose = FALSE))
    seu <- step(method, "cluster", Seurat::FindClusters(seu, resolution = p$resolution,
      algorithm = p$clustering_algorithm, random.seed = p$clustering_seed, verbose = FALSE))
    set.seed(decisions$seed)
    seu <- step(method, "umap", Seurat::RunUMAP(seu, reduction = "pca", dims = seq_len(p$ndim),
      seed.use = p$umap_seed, verbose = FALSE))
    markers <- step(method, "markers", Seurat::FindAllMarkers(seu,
      only.pos = p$marker_only_pos, min.pct = p$marker_min_pct,
      logfc.threshold = p$marker_logfc, verbose = FALSE))
    filtered <- step(method, "markers_summary", {
      markers |>
        dplyr::filter(avg_log2FC > p$marker_summary_log2fc_cut,
                      p_val_adj < p$marker_summary_padj_cut) |>
        dplyr::mutate(pct_diff = pct.1 - pct.2) |>
        dplyr::group_by(cluster) |>
        dplyr::arrange(dplyr::desc(pct_diff), .by_group = TRUE) |>
        dplyr::slice_head(n = p$marker_summary_top_n) |>
        dplyr::ungroup()
    })
    audit <- list(decision_source = decisions$decision_source, params = p)
  } else {
    obj <- step(method, "create_input", scAgentKit::AgentSeurat(new_input()))
    obj <- step(method, "qc_add_metrics", scAgentKit::qc_add_metrics(obj, species = "human"))
    obj <- step(method, "qc_threshold", scAgentKit::qc_threshold(obj,
      min_nCount = p$min_ncount, min_nFeature = p$min_nfeature,
      max_percent_mt = p$max_percent_mt, min_percent_mt = p$min_percent_mt))
    obj <- step(method, "qc_max_feature", {
      before <- ncol(scAgentKit::get_seurat(obj))
      seu <- scAgentKit::get_seurat(obj)
      obj@data <- subset(seu, cells = colnames(seu)[seu$nFeature_RNA < p$max_nfeature])
      agentomicsCore::record_step(obj, step_name = "qc_max_feature", function_name = "subset",
        params = list(max_nfeature = p$max_nfeature, n_before = before, n_after = ncol(obj@data)),
        rationale = "Fixed PBMC smoke-test upper feature cutoff; no model decision.",
        script_snippet = sprintf("seurat_obj <- subset(seurat_obj, subset = nFeature_RNA < %d)", p$max_nfeature))
    })
    obj <- step(method, "normalize", scAgentKit::sc_normalize(obj, method = p$normalization,
      scale_factor = p$scale_factor))
    obj <- step(method, "hvg", scAgentKit::sc_find_hvg(obj, method = p$hvg_method, nfeatures = p$nfeatures))
    obj <- step(method, "scale", scAgentKit::sc_scale(obj))
    obj <- step(method, "pca", scAgentKit::sc_pca(obj, npcs = p$npcs))
    obj <- step(method, "neighbors", scAgentKit::sc_find_neighbors(obj, reduction = "pca", ndim = p$ndim))
    obj <- step(method, "cluster", scAgentKit::sc_cluster(obj, resolution = p$resolution))
    obj <- step(method, "umap", scAgentKit::sc_umap(obj, reduction = "pca", ndim = p$ndim, seed = decisions$seed))
    obj <- step(method, "markers", scAgentKit::sc_find_markers(obj, only_pos = p$marker_only_pos,
      min_pct = p$marker_min_pct, logfc_threshold = p$marker_logfc))
    obj <- step(method, "markers_summary", scAgentKit::sc_markers_summary(obj,
      top_n = p$marker_summary_top_n, log2fc_cut = p$marker_summary_log2fc_cut,
      padj_cut = p$marker_summary_padj_cut,
      output_path = file.path(out_dir, paste0(method, "_markers_top30.txt"))))
    seu <- scAgentKit::get_seurat(obj)
    markers <- obj@params$all_markers
    filtered <- obj@params$markers_filtered
    audit <- scAgentKit::get_decisions(obj)
    saveRDS(obj, file.path(out_dir, paste0(method, "_agent.rds")), version = 3L)
    trace <- scAgentKit::get_script(obj)
    if (is.character(trace)) writeLines(trace, file.path(out_dir, paste0(method, "_audit_trace.R")))
  }
  if (ncol(seu) < 3L || length(unique(seu$seurat_clusters)) < 2L) {
    stop("Insufficient retained cells or clusters for a meaningful workflow check.")
  }
  if (!nrow(markers)) stop("FindAllMarkers returned no markers; inspect step warnings.")
  barcodes <- decisions$selected_barcodes
  retained <- barcodes %in% colnames(seu)
  labels <- data.frame(cell_id = barcodes, method = method,
                       status = ifelse(retained, "retained", "qc_filtered"),
                       cluster = as.character(seu$seurat_clusters[match(barcodes, colnames(seu))]),
                       label = "unknown", unknown = TRUE, stringsAsFactors = FALSE)
  # Biological annotation was not performed: do not give clusters author labels.
  write_csv(labels, paste0(method, "_labels.csv"))
  write_csv(markers, paste0(method, "_markers.csv"))
  write_csv(filtered, paste0(method, "_markers_filtered.csv"))
  marker_inputs <- lapply(sort(unique(as.character(seu$seurat_clusters))), function(cluster) {
    rows <- filtered[as.character(filtered$cluster) == cluster, , drop = FALSE]
    list(cluster = cluster, genes = as.character(rows$gene),
         evidence = as.data.frame(rows), reference_candidates = list(),
         tissue = p$tissue, annotation = "unknown", status = "not_run_no_authorization")
  })
  # Prepared inputs retain the user's shared top-30 evidence for both paths.
  # They contain no reference labels, expected class count, or vocabulary.
  for (reference_mode in c("guided", "independent")) {
    jsonlite::write_json(list(schema_version = 1L, reference_mode = reference_mode,
      tissue = p$tissue, marker_policy = "padj/logFC filter, pct.1-pct.2 descending, top30",
      reference_status = "missing_reference", llm_status = "not_run_no_authorization",
      expected_celltypes = NULL, expected_n_clusters = NULL, clusters = marker_inputs),
      file.path(out_dir, paste0(method, "_", reference_mode, "_input_manifest.json")),
      pretty = TRUE, auto_unbox = TRUE, null = "null")
  }
  saveRDS(audit, file.path(out_dir, paste0(method, "_audit_decisions.rds")), version = 3L)
  saveRDS(seu, file.path(out_dir, paste0(method, "_seurat.rds")), version = 3L)
  write_csv(data.frame(cell_id = colnames(seu), Seurat::Embeddings(seu, "umap")), paste0(method, "_umap.csv"))
  step(method, "plot", ggplot2::ggsave(file.path(out_dir, paste0(method, "_umap.png")),
    Seurat::DimPlot(seu, reduction = "umap", group.by = "seurat_clusters", label = TRUE),
    width = 7, height = 5, dpi = 150))
  list(seu = seu, labels = labels, markers = markers, filtered = filtered)
}

adjusted_rand <- function(a, b) {
  if (length(a) < 2L) return(NA_real_)
  tab <- table(a, b)
  pairs <- function(x) sum(x * (x - 1) / 2)
  total <- choose(sum(tab), 2)
  rows <- pairs(rowSums(tab)); cols <- pairs(colSums(tab)); observed <- pairs(tab)
  expected <- rows * cols / total
  denom <- (rows + cols) / 2 - expected
  if (abs(denom) < .Machine$double.eps) return(1)
  (observed - expected) / denom
}

results <- list()
method_status <- list()
for (method in c("seurat5_fixed", "scagentkit_fixed")) {
  started <- Sys.time()
  error <- ""
  result <- tryCatch(run_method(method), error = function(e) {
    error <<- conditionMessage(e)
    NULL
  })
  method_status[[method]] <- data.frame(method = method,
    status = if (is.null(result)) "failed" else "success", error = error,
    elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    n_input = ncol(counts), n_retained = if (is.null(result)) NA_integer_ else ncol(result$seu),
    n_clusters = if (is.null(result)) NA_integer_ else length(unique(result$seu$seurat_clusters)),
    annotation_status = "not_run", annotation_unknown = ncol(counts), llm_calls = 0L)
  if (!is.null(result)) results[[method]] <- result
  if (is.null(result)) write_csv(data.frame(cell_id = decisions$selected_barcodes,
    method = method, status = "failed", cluster = NA_character_, label = "unknown",
    unknown = TRUE), paste0(method, "_labels.csv"))
  write_csv(do.call(rbind, method_status), "method_status.csv")
}
for (annotation_method in c("ACT_reference", "llm_guided", "llm_independent")) {
  base_labels <- if (!is.null(results$scagentkit_fixed)) results$scagentkit_fixed$labels else
    data.frame(cell_id = decisions$selected_barcodes, status = "failed", cluster = NA_character_)
  write_csv(data.frame(cell_id = base_labels$cell_id, method = annotation_method,
    analysis_status = base_labels$status, cluster = base_labels$cluster,
    status = if (annotation_method == "ACT_reference") "missing_reference" else "not_run_no_authorization",
    label = "unknown", unknown = TRUE), paste0(annotation_method, "_labels.csv"))
}
write_csv(data.frame(method = c("ACT_reference", "llm_guided", "llm_independent", "SingleR", "CellTypist"),
  status = c("missing_reference", "not_run_no_authorization", "not_run_no_authorization", "not_run", "not_run"),
  reason = c("No valid human PBMC ACT reference supplied; demonstration template excluded",
             "No authorization; no provider calls or uploads; label unknown",
             "No authorization; no provider calls or uploads; label unknown",
             "Reference annotation deferred; harness does not install or download references",
             "Optional later baseline; not part of this Seurat5 workflow check")), "annotation_status.csv")

comparison_ok <- TRUE
if (length(results) == 2L) {
  a <- results$seurat5_fixed; b <- results$scagentkit_fixed
  same_cells <- identical(colnames(a$seu), colnames(b$seu))
  common <- intersect(colnames(a$seu), colnames(b$seu))
  ac <- as.character(a$seu$seurat_clusters[match(common, colnames(a$seu))])
  bc <- as.character(b$seu$seurat_clusters[match(common, colnames(b$seu))])
  pc_diff <- if (same_cells) max(abs(Seurat::Embeddings(a$seu, "pca") - Seurat::Embeddings(b$seu, "pca"))) else NA_real_
  umap_diff <- if (same_cells) max(abs(Seurat::Embeddings(a$seu, "umap") - Seurat::Embeddings(b$seu, "umap"))) else NA_real_
  ari <- adjusted_rand(ac, bc)
  comparison_ok <- same_cells && identical(ac, bc) && is.finite(pc_diff) && pc_diff < 1e-8 &&
    is.finite(umap_diff) && umap_diff < 1e-8
  write_csv(data.frame(method_a = "seurat5_fixed", method_b = "scagentkit_fixed",
    n_common = length(common), same_barcode_order = same_cells, cluster_ari = ari,
    exact_cluster_agreement = mean(ac == bc), pca_max_abs_difference = pc_diff,
    umap_max_abs_difference = umap_diff, annotation_agreement = NA_real_,
      annotation_status = "unknown; annotation not run", check_passed = comparison_ok), "method_comparison.csv")
}

# The first reference-label read happens after every analysis method is complete.
truth_path <- if (opt$mode == "run") opt$truth_csv else file.path(run_dir, "evaluation", "reference_labels.csv")
if (nzchar(truth_path) && file.exists(truth_path)) {
  truth <- utils::read.csv(truth_path, stringsAsFactors = FALSE, colClasses = "character")
  if (!all(c("cell_id", "label") %in% names(truth)) || anyDuplicated(truth$cell_id) ||
      any(is.na(truth$cell_id)) || any(!nzchar(truth$cell_id))) stop("Truth must have unique cell_id and label columns.")
  dir.create(file.path(out_dir, "evaluation"), showWarnings = FALSE)
  utils::write.csv(truth, file.path(out_dir, "evaluation", "reference_labels.csv"), row.names = FALSE)
  write_csv(data.frame(file = basename(truth_path), md5 = md5(truth_path)), "evaluation/reference_input_manifest.csv")
  reference_metrics <- lapply(names(results), function(method) {
    labels <- results[[method]]$labels
    matched <- truth$label[match(labels$cell_id, truth$cell_id)]
    keep <- labels$status == "retained" & !is.na(matched) & nzchar(matched) & matched != "unknown"
    data.frame(method = method, n_reference_matched_retained = sum(keep),
      n_retained_without_reference = sum(labels$status == "retained" & !keep),
      cluster_vs_reference_ari = adjusted_rand(labels$cluster[keep], matched[keep]),
      annotation_accuracy = NA_real_, annotation_status = "not_run")
  })
  if (length(reference_metrics)) write_csv(do.call(rbind, reference_metrics), "evaluation/reference_metrics.csv")
} else if (nzchar(opt$truth_csv)) {
  stop("Requested truth CSV does not exist.")
}

replay_ok <- TRUE
if (opt$mode == "replay") {
  replay_checks <- lapply(names(results), function(method) {
    original <- readRDS(file.path(run_dir, paste0(method, "_seurat.rds")))
    current <- results[[method]]$seu
    same_cells <- identical(colnames(original), colnames(current))
    same_clusters <- identical(as.character(original$seurat_clusters), as.character(current$seurat_clusters))
    pca_diff <- if (same_cells) max(abs(Seurat::Embeddings(original, "pca") - Seurat::Embeddings(current, "pca"))) else NA_real_
    umap_diff <- if (same_cells) max(abs(Seurat::Embeddings(original, "umap") - Seurat::Embeddings(current, "umap"))) else NA_real_
    same_labels <- identical(utils::read.csv(file.path(run_dir, paste0(method, "_labels.csv")),
      stringsAsFactors = FALSE), utils::read.csv(file.path(out_dir, paste0(method, "_labels.csv")), stringsAsFactors = FALSE))
    same_markers <- isTRUE(all.equal(utils::read.csv(file.path(run_dir, paste0(method, "_markers.csv"))),
      utils::read.csv(file.path(out_dir, paste0(method, "_markers.csv"))), tolerance = 1e-8))
    passed <- same_cells && same_clusters && same_labels && same_markers &&
      is.finite(pca_diff) && pca_diff < 1e-8 && is.finite(umap_diff) && umap_diff < 1e-8
    data.frame(method = method, same_barcode_order = same_cells, same_clusters = same_clusters,
      same_labels = same_labels, same_markers = same_markers, pca_max_abs_difference = pca_diff,
      umap_max_abs_difference = umap_diff, llm_calls = 0L, passed = passed)
  })
  if (length(replay_checks)) {
    replay_checks <- do.call(rbind, replay_checks)
    write_csv(replay_checks, "replay_checks.csv")
    replay_ok <- all(replay_checks$passed)
  } else replay_ok <- FALSE
}

decisions$package_versions <- versions()
saveRDS(decisions, file.path(out_dir, "decisions.rds"), version = 3L)
jsonlite::write_json(decisions, file.path(out_dir, "decisions.json"), pretty = TRUE, auto_unbox = TRUE)
write_csv(decisions$package_versions, "package_versions.csv")
writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
success <- length(results) == 2L && comparison_ok && replay_ok
writeLines(c(paste("status:", if (success) "success" else "failed"), paste("mode:", opt$mode),
             "decision_source: fixed_analyst_baseline", "llm_calls: 0",
             "annotation_accuracy: not evaluated", paste("completed_utc:", format(Sys.time(), tz = "UTC", usetz = TRUE))),
           file.path(out_dir, "run_status.txt"))
message("[pbmc3k_repro] ", if (success) "success" else "failed", "; artifacts: ", out_dir)
if (!success) quit(status = 1L)
