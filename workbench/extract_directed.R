#!/usr/bin/env Rscript
# Offline, read-only RNA evidence extraction. Never normalize or export a full matrix.
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(digest))

SCHEMA_VERSION <- "scAgentKit.directed_expression.v1"
RULE_VERSION <- "rna-observed-panel-v1"
PANEL <- list(
  t_identity = c("CD3D", "CD3E", "CD3G", "TRAC", "TRBC1", "TRBC2"),
  cd8_subtype = c("CD8A", "CD8B"),
  nk_identity = c("KLRD1", "KLRF1", "NCR1", "NCAM1"),
  nk_nonexclusive = "FCGR3A",
  shared_cytotoxic = c("NKG7", "GNLY", "PRF1", "GZMB", "GZMA", "GZMH", "CTSW", "CST7"),
  b_candidate_control = c("MS4A1", "CD79A", "CD79B")
)
GENES <- unname(unlist(PANEL))
QC_FIELDS <- c("nCount_RNA", "nFeature_RNA", "percent.mt", "orig.ident")
DEPTH_CONFIGS <- list(
  list(id = "lower", nCount_RNA_lt = 500, nFeature_RNA_lt = 250),
  list(id = "primary", nCount_RNA_lt = 1000, nFeature_RNA_lt = 500),
  list(id = "higher", nCount_RNA_lt = 1500, nFeature_RNA_lt = 750)
)

fail <- function(message) stop(message, call. = FALSE)
sha_text <- function(text) digest(enc2utf8(text), algo = "sha256", serialize = FALSE)
sha_file <- function(path) digest(path, algo = "sha256", file = TRUE)
as_json <- function(value, pretty = FALSE) {
  toJSON(value, auto_unbox = TRUE, null = "null", na = "null", digits = NA,
         pretty = pretty, force = TRUE)
}
cell_hash <- function(ids) sha_text(toJSON(sort(ids), auto_unbox = FALSE))

distribution <- function(values) {
  values <- as.numeric(values)
  if (!length(values)) return(list(n = 0L, mean = NULL, q0 = NULL, q25 = NULL,
                                  q50 = NULL, q75 = NULL, q90 = NULL, max = NULL))
  if (any(!is.finite(values))) fail("Non-finite normalized expression or QC value")
  q <- quantile(values, probs = c(0, .25, .5, .75, .9, 1), names = FALSE, type = 7)
  list(n = length(values), mean = mean(values), q0 = q[1], q25 = q[2], q50 = q[3],
       q75 = q[4], q90 = q[5], max = q[6])
}

validate_layer <- function(matrix, label, raw_counts = FALSE) {
  if (is.null(rownames(matrix)) || is.null(colnames(matrix)) ||
      anyNA(rownames(matrix)) || anyNA(colnames(matrix)) ||
      any(!nzchar(rownames(matrix))) || any(!nzchar(colnames(matrix))) ||
      anyDuplicated(rownames(matrix)) || anyDuplicated(colnames(matrix)))
    fail(paste("Duplicate, missing or empty gene/cell ID in", label))
  if (!nrow(matrix) || !ncol(matrix)) fail(paste("Zero denominator in", label))
  values <- if (inherits(matrix, "sparseMatrix")) matrix@x else as.numeric(matrix)
  if (any(!is.finite(values)) || any(values < 0)) fail(paste("Invalid values in", label))
  if (raw_counts && any(values != floor(values))) fail("RNA counts must be genuine nonnegative integers")
  invisible(TRUE)
}

project_csv <- function(path, required, nullable = character()) {
  header <- names(read.csv(path, nrows = 0, check.names = FALSE))
  if (anyDuplicated(header) || !all(required %in% header)) fail("Missing or duplicated source CSV columns")
  classes <- setNames(ifelse(header %in% required, "character", "NULL"), header)
  value <- read.csv(path, check.names = FALSE, colClasses = classes, stringsAsFactors = FALSE)
  strict <- value[setdiff(required, nullable)]
  if (!nrow(value) || anyNA(strict) || any(!nzchar(as.matrix(strict)))) fail("Empty, missing or damaged source CSV values")
  value[required]
}

gene_summary <- function(counts, normalized, ids) {
  if (!length(ids)) fail("Zero denominator in gene summary")
  lapply(GENES, function(gene) {
    in_counts <- gene %in% rownames(counts)
    in_data <- gene %in% rownames(normalized)
    group <- names(PANEL)[vapply(PANEL, function(x) gene %in% x, logical(1))]
    count_values <- if (in_counts) as.numeric(counts[gene, ids]) else NULL
    norm_values <- if (in_data) as.numeric(normalized[gene, ids]) else NULL
    detected <- if (in_counts) count_values > 0 else NULL
    list(gene = gene, panel_group = group, assay = "RNA", detection_layer = "counts",
         normalized_layer = "data", n_cells = length(ids),
         measurement_status = if (in_counts) "measured" else "missing",
         counts_status = if (in_counts) "measured" else "missing",
         normalized_status = if (in_data) "measured" else "missing",
         detected_n = if (in_counts) sum(detected) else NULL,
         detected_fraction = if (in_counts) mean(detected) else NULL,
         raw_counts = if (in_counts) distribution(count_values) else NULL,
         normalized = list(all = if (in_data) distribution(norm_values) else NULL,
                           detected = if (in_data && in_counts) distribution(norm_values[detected]) else NULL))
  })
}

anchor_observations <- function(counts, ids, anchors) {
  measured <- anchors[anchors %in% rownames(counts)]
  missing <- setdiff(anchors, measured)
  observed_n <- if (length(measured)) colSums(counts[measured, ids, drop = FALSE] > 0) else rep(0L, length(ids))
  list(anchors = anchors, measured_anchors = measured, missing_anchors = missing,
       observed_n = as.integer(observed_n), missing_n = length(missing))
}

coexpression <- function(counts, ids, threshold = 2L) {
  if (!length(ids)) fail("Zero denominator in coexpression")
  t <- anchor_observations(counts, ids, PANEL$t_identity)
  nk <- anchor_observations(counts, ids, PANEL$nk_identity)
  b <- anchor_observations(counts, ids, PANEL$b_candidate_control)
  t_observed <- t$observed_n >= threshold
  nk_observed <- nk$observed_n >= threshold
  classes <- ifelse(t_observed & nk_observed, "both", ifelse(t_observed, "t_only", ifelse(nk_observed, "nk_only", "neither")))
  category_n <- as.list(setNames(as.integer(table(factor(classes, levels = c("t_only", "nk_only", "both", "neither")))), c("t_only", "nk_only", "both", "neither")))
  possible_gate <- function(value) ifelse(value$observed_n >= threshold, TRUE,
                                        ifelse(value$observed_n + value$missing_n < threshold, FALSE, NA))
  summary <- list(assay = "RNA", layer = "counts", n_cells = length(ids),
                  rule_version = RULE_VERSION, threshold_n = threshold,
                  threshold_status = "exploratory_uncalibrated",
                  anchors = list(t = t$anchors, nk = nk$anchors),
                  measured_anchors = list(t = t$measured_anchors, nk = nk$measured_anchors),
                  missing_anchors = list(t = t$missing_anchors, nk = nk$missing_anchors),
                  counts = category_n, fractions = lapply(category_n, function(n) n / length(ids)),
                  observed_t_gate_n = sum(t_observed), observed_nk_gate_n = sum(nk_observed),
                  observed_b_control_gate_n = sum(b$observed_n >= threshold),
                  t_anchor_detected_n_distribution = distribution(t$observed_n),
                  nk_anchor_detected_n_distribution = distribution(nk$observed_n),
                  n_complete_gate_coverage = if (t$missing_n == 0 && nk$missing_n == 0) length(ids) else 0L,
                  t_gate_indeterminate_due_missing_n = sum(is.na(possible_gate(t))),
                  nk_gate_indeterminate_due_missing_n = sum(is.na(possible_gate(nk))),
                  interpretation = "Counts describe observed anchor detection, not calibrated lineage calls. Below threshold is not negative lineage evidence; missing genes and low RNA depth remain limitations. Same-cell T/NK detection does not identify NKT cells or doublets.")
  list(summary = summary, t = t, nk = nk, b = b, t_gate = t_observed,
       nk_gate = nk_observed, t_possible = possible_gate(t), nk_possible = possible_gate(nk), classes = classes)
}

depth_mask <- function(metadata, ids, config) {
  if (!all(c("nCount_RNA", "nFeature_RNA") %in% names(metadata))) return(rep(NA, length(ids)))
  umi <- metadata[ids, "nCount_RNA"]
  features <- metadata[ids, "nFeature_RNA"]
  if (any(!is.finite(umi)) || any(!is.finite(features))) fail("Non-finite RNA depth metadata")
  umi < config$nCount_RNA_lt | features < config$nFeature_RNA_lt
}

qc_summary <- function(metadata, ids, counts) {
  fields <- lapply(QC_FIELDS, function(field) {
    present <- field %in% names(metadata)
    if (!present) return(list(field = field, measurement_status = "missing", n_cells = length(ids), distribution = NULL, values = NULL))
    values <- metadata[ids, field]
    if (anyNA(values)) fail(paste("Missing QC values in", field))
    if (field == "orig.ident") {
      tab <- table(as.character(values))
      return(list(field = field, measurement_status = "measured", n_cells = length(ids),
                  distribution = NULL, values = as.list(setNames(as.integer(tab), names(tab))),
                  interpretation = "Actual orig.ident metadata; not a verified donor or sample identity."))
    }
    if (!is.numeric(values)) fail(paste("Expected numeric actual QC field", field))
    list(field = field, measurement_status = "measured", n_cells = length(ids),
         distribution = distribution(values), values = NULL)
  })
  sensitivity <- lapply(DEPTH_CONFIGS, function(config) {
    low <- depth_mask(metadata, ids, config)
    adequate_ids <- ids[!is.na(low) & !low]
    list(config = config, n_cells = length(ids), n_evaluable = sum(!is.na(low)),
         low_depth_n = if (all(is.na(low))) NULL else sum(low, na.rm = TRUE),
         at_nCount_boundary_n = if ("nCount_RNA" %in% names(metadata)) sum(metadata[ids, "nCount_RNA"] == config$nCount_RNA_lt) else NULL,
         at_nFeature_boundary_n = if ("nFeature_RNA" %in% names(metadata)) sum(metadata[ids, "nFeature_RNA"] == config$nFeature_RNA_lt) else NULL,
         above_depth_threshold_n = length(adequate_ids),
         above_depth_observed_coexpression = if (length(adequate_ids)) coexpression(counts, adequate_ids)$summary else NULL)
  })
  list(n_cells = length(ids), fields = fields, low_depth_n = sensitivity[[2]]$low_depth_n,
       low_depth_config = DEPTH_CONFIGS[[2]], sensitivity = sensitivity,
       threshold_status = "exploratory_uncalibrated",
       interpretation = "Low-depth flags are descriptive; absence of detection in a low-depth cell is not negative lineage evidence. No cells are removed.")
}

write_immutable <- function(path, value) {
  bytes <- paste0(as.character(as_json(value, pretty = TRUE)), "\n")
  if (file.exists(path)) {
    prior <- paste0(readLines(path, warn = FALSE), collapse = "\n")
    if (!identical(paste0(prior, "\n"), bytes)) fail(paste("Refusing to overwrite different evidence:", path))
    return(invisible(path))
  }
  temporary <- tempfile(pattern = ".expression-", tmpdir = dirname(path))
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  writeChar(bytes, temporary, eos = NULL, useBytes = TRUE)
  if (!file.rename(temporary, path)) fail("Could not atomically write evidence")
  invisible(path)
}

self_test <- function() {
  measured <- matrix(c(0, 1, 2, 3), nrow = 1, dimnames = list("CD3D", paste0("cell", 1:4)))
  summary <- gene_summary(measured, measured, colnames(measured))
  stopifnot(summary[[1]]$measurement_status == "measured", summary[[1]]$detected_n == 3L,
            summary[[2]]$measurement_status == "missing", is.null(summary[[2]]$detected_n))
  zero <- measured * 0
  zero_summary <- gene_summary(zero, zero, colnames(zero))
  stopifnot(zero_summary[[1]]$detected_n == 0, zero_summary[[1]]$detected_fraction == 0,
            zero_summary[[1]]$normalized$detected$n == 0L)
  mixed <- matrix(0, nrow = 4, ncol = 4, dimnames = list(c("CD3D", "CD3E", "KLRD1", "KLRF1"), paste0("cell", 1:4)))
  mixed[1:2, c(1, 3)] <- 1
  mixed[3:4, c(2, 3)] <- 1
  co <- coexpression(mixed, colnames(mixed))
  stopifnot(all(unlist(co$summary$counts) == 1), isTRUE(co$t_possible[1]), is.na(co$t_possible[2]))
  expect_failure <- function(code) {
    failed <- FALSE
    tryCatch(force(code), error = function(e) failed <<- TRUE)
    stopifnot(failed)
  }
  duplicated <- measured
  colnames(duplicated)[2] <- colnames(duplicated)[1]
  expect_failure(validate_layer(duplicated, "synthetic", TRUE))
  duplicated <- rbind(measured, measured)
  expect_failure(validate_layer(duplicated, "synthetic", TRUE))
  fraction <- measured; fraction[1, 1] <- .5
  expect_failure(validate_layer(fraction, "synthetic", TRUE))
  expect_failure(gene_summary(measured, measured, character()))
  qc <- data.frame(nCount_RNA = c(999, 1000, 1001, 2000), nFeature_RNA = c(700, 500, 499, 1000), row.names = colnames(measured))
  stopifnot(identical(depth_mask(qc, rownames(qc), DEPTH_CONFIGS[[2]]), c(TRUE, FALSE, TRUE, FALSE)))
  cat("extract_directed self-test: 9 cases passed\n")
}

args <- commandArgs(trailingOnly = TRUE)
if (identical(args, "--self-test")) { self_test(); quit(status = 0) }
if (!length(args) || length(args) %% 2 != 0 || any(!grepl("^--", args[seq(1, length(args), 2)])))
  fail("Usage: extract_directed.R --rds FILE --cells CSV --labels CSV --umap CSV --output-dir DIR --input-evidence-revision SHA256 [--cluster 6]")
options <- as.list(setNames(args[seq(2, length(args), 2)], sub("^--", "", args[seq(1, length(args), 2)])))
required <- c("rds", "cells", "labels", "umap", "output-dir", "input-evidence-revision")
if (anyDuplicated(names(options)) || !all(required %in% names(options)) ||
    any(!names(options) %in% c(required, "cluster"))) fail("Missing, duplicate or unsupported extraction option")
if (!grepl("^[a-f0-9]{64}$", options[["input-evidence-revision"]])) fail("Invalid input evidence revision")
cluster_id <- if (is.null(options$cluster)) "6" else options$cluster
if (cluster_id != "6") fail("This evidence protocol is scoped to cluster 6 only")
for (key in c("rds", "cells", "labels", "umap")) {
  if (!file.exists(options[[key]]) || dir.exists(options[[key]])) fail(paste("Missing source", key))
  options[[key]] <- normalizePath(options[[key]], mustWork = TRUE)
}
script_arg <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", script_arg[grepl("^--file=", script_arg)])
if (length(script_path) != 1 || !file.exists(script_path)) fail("Cannot establish extractor source hash")
source_hashes_before <- lapply(options[c("rds", "cells", "labels", "umap")], sha_file)

suppressPackageStartupMessages(library(SeuratObject))
suppressPackageStartupMessages(library(Matrix))
object <- readRDS(options$rds)
if (!inherits(object, "Seurat") || !"RNA" %in% names(object@assays)) fail("Source must contain an RNA Seurat assay")
layers <- Layers(object[["RNA"]])
if (!all(c("counts", "data") %in% layers) || sum(layers == "counts") != 1 || sum(layers == "data") != 1)
  fail("Required exact existing RNA counts and data layers are unavailable")
counts <- LayerData(object, assay = "RNA", layer = "counts")
normalized <- LayerData(object, assay = "RNA", layer = "data")
validate_layer(counts, "RNA counts", TRUE)
validate_layer(normalized, "RNA data")
if (!setequal(colnames(counts), colnames(normalized)) ||
    !setequal(rownames(counts), rownames(normalized))) fail("RNA counts/data cell or feature coverage differs")
input_cells <- project_csv(options$cells, c("cell_id", "cluster"))
labels <- project_csv(options$labels, c("cell_id", "status", "cluster"), nullable = "cluster")
if (anyDuplicated(input_cells$cell_id) || anyDuplicated(labels$cell_id) ||
    any(!labels$status %in% c("retained", "qc_filtered"))) fail("Duplicate cell ID or invalid retained-cell map")
retained <- labels[labels$status == "retained", c("cell_id", "cluster")]
if (anyNA(retained$cluster) || any(!nzchar(retained$cluster))) fail("Missing retained cluster ID")
if (!setequal(input_cells$cell_id, retained$cell_id) ||
    !identical(input_cells$cluster[match(retained$cell_id, input_cells$cell_id)], retained$cluster))
  fail("Provider input and retained cluster scope differ")
if (!setequal(colnames(counts), retained$cell_id)) fail("RNA cell IDs do not exactly match retained cells")
if (nrow(labels) != 2700 || nrow(retained) != 2638 || length(unique(retained$cluster)) != 9 ||
    !setequal(unique(retained$cluster), as.character(0:8))) fail("Expected PBMC3k 2700 input, 2638 retained, 9 clusters")
umap <- project_csv(options$umap, c("cell_id", "umap_1", "umap_2"))
if (anyDuplicated(umap$cell_id) || !setequal(umap$cell_id, retained$cell_id)) fail("UMAP and retained cell scopes differ")
umap$umap_1 <- as.numeric(umap$umap_1); umap$umap_2 <- as.numeric(umap$umap_2)
if (any(!is.finite(umap$umap_1)) || any(!is.finite(umap$umap_2))) fail("Invalid UMAP coordinates")
metadata <- object@meta.data[, intersect(QC_FIELDS, colnames(object@meta.data)), drop = FALSE]
if (anyDuplicated(rownames(metadata)) || !setequal(rownames(metadata), retained$cell_id)) fail("Metadata cell IDs differ")
# Check cluster IDs only; no author labels, truth, donor, doublet or VDJ data are read.
if ("seurat_clusters" %in% names(object@meta.data) &&
    !identical(as.character(object@meta.data[retained$cell_id, "seurat_clusters"]), retained$cluster))
  fail("Seurat clustering disagrees with exact retained-cell map")
groups <- lapply(as.character(0:8), function(id) sort(retained$cell_id[retained$cluster == id]))
names(groups) <- as.character(0:8)
ids <- groups[[cluster_id]]
if (length(ids) != 155L) fail("Cluster 6 must have exactly 155 retained cells")
co <- coexpression(counts, ids)
panel <- gene_summary(counts, normalized, ids)
qc <- qc_summary(metadata, ids, counts)
observed_status <- function(observed, missing_n) {
  if (observed >= 2) "observed_threshold_met" else if (missing_n > 0) "below_observed_threshold_missing_anchors" else "below_observed_threshold"
}
low <- depth_mask(metadata, ids, DEPTH_CONFIGS[[2]])
cells <- lapply(seq_along(ids), function(index) {
  id <- ids[index]
  count_values <- lapply(GENES, function(gene) if (gene %in% rownames(counts)) as.numeric(counts[gene, id]) else NULL)
  norm_values <- lapply(GENES, function(gene) if (gene %in% rownames(normalized)) as.numeric(normalized[gene, id]) else NULL)
  qc_values <- lapply(QC_FIELDS, function(field) if (field %in% names(metadata)) metadata[id, field] else NULL)
  point <- umap[match(id, umap$cell_id), ]
  list(cell_id = id, cluster_id = cluster_id, counts = setNames(count_values, GENES),
       normalized = setNames(norm_values, GENES), qc = setNames(qc_values, QC_FIELDS),
       umap = list(x = point$umap_1, y = point$umap_2),
       t_anchor_detected_n = co$t$observed_n[index], nk_anchor_detected_n = co$nk$observed_n[index],
       t_missing_anchor_n = co$t$missing_n, nk_missing_anchor_n = co$nk$missing_n,
       t_gate = co$t_gate[index], nk_gate = co$nk_gate[index],
       t_identity_gate_possible = co$t_possible[index], nk_identity_gate_possible = co$nk_possible[index],
       t_gate_status = observed_status(co$t$observed_n[index], co$t$missing_n),
       nk_gate_status = observed_status(co$nk$observed_n[index], co$nk$missing_n),
       coexpression_class = co$classes[index], low_depth = low[index])
})
controls <- lapply(setdiff(names(groups), cluster_id), function(id) {
  control_ids <- groups[[id]]
  control_co <- coexpression(counts, control_ids)
  union_gate <- control_co$t_gate | control_co$nk_gate | control_co$b$observed_n >= 2
  observed_fraction <- mean(union_gate)
  list(cluster_id = id, n_cells = length(control_ids), designation = "candidate_control_unverified_correlated",
       selection = list(rule = "observed >=2 T, NK or B anchors in >=20% of cells",
                        rule_status = "exploratory_uncalibrated", selected_candidate_lymphocyte = observed_fraction >= .2,
                        observed_lymphocyte_gate_n = sum(union_gate), observed_lymphocyte_gate_fraction = observed_fraction,
                        b_anchors = PANEL$b_candidate_control,
                        fraction_threshold_sensitivity = lapply(c(.1, .2, .3), function(threshold) list(threshold = threshold, selected = observed_fraction >= threshold))),
       panel = gene_summary(counts, normalized, control_ids), coexpression = control_co$summary,
       qc = qc_summary(metadata, control_ids, counts),
       limitation = "Selected from observed expression only; no independent identity verification. Clustering and comparisons reuse the same expression data and are correlated.")
})
selected_clusters <- vapply(controls[vapply(controls, function(c) c$selection$selected_candidate_lymphocyte, logical(1))], function(c) c$cluster_id, character(1))
selected_ids <- unlist(groups[selected_clusters], use.names = FALSE)
comparison <- list(all_rest = list(n_cells = 2638L - length(ids),
                                  panel = gene_summary(counts, normalized, setdiff(sort(retained$cell_id), ids))),
                   candidate_lymphocyte = list(cluster_ids = selected_clusters, n_cells = length(selected_ids),
                                              panel = if (length(selected_ids)) gene_summary(counts, normalized, selected_ids) else NULL),
                   interpretation = "Compare each gene against both denominators. An all-rest contrast can weaken or reverse against candidate lymphocyte controls; neither contrast confirms identity.")
commands <- object@commands
normalization <- if ("NormalizeData.RNA" %in% names(commands)) {
  params <- commands[["NormalizeData.RNA"]]@params
  list(method = params$normalization.method, scale_factor = params$scale.factor,
       provenance = "Existing saved Seurat NormalizeData command; no normalization recomputed")
} else list(method = NULL, scale_factor = NULL, provenance = "No saved normalization command available")
versions <- lapply(c("SeuratObject", "Matrix", "jsonlite", "digest"), function(package) as.character(packageVersion(package)))
names(versions) <- c("SeuratObject", "Matrix", "jsonlite", "digest")
source <- list(rds_sha256 = source_hashes_before$rds, cell_map_sha256 = source_hashes_before$cells,
               retained_labels_sha256 = source_hashes_before$labels, umap_sha256 = source_hashes_before$umap,
               extractor_sha256 = sha_file(script_path), input_evidence_revision = options[["input-evidence-revision"]],
               assay = "RNA", assay_class = class(object[["RNA"]])[1],
               layers = list(counts = "counts", data = "data"),
               n_features_counts = nrow(counts), n_features_data = nrow(normalized),
               counts_integer_nonnegative_validated = TRUE, cell_join = "Exact cell_id; no array-position joins",
               normalization = normalization, r_version = R.version.string, package_versions = versions)
coverage <- list(panel_gene_n = length(GENES), measured_gene_n = sum(GENES %in% rownames(counts)),
                 missing_genes = setdiff(GENES, rownames(counts)),
                 scope_n_cells = length(ids), denominator = "All exact retained cluster-6 cell IDs, including low-depth cells")
bundle <- list(schema_version = SCHEMA_VERSION, rule_version = RULE_VERSION, source = source,
               inventory = list(n_cells = 2638L, n_input_cells = 2700L, n_clusters = 9L,
                                counts_by_cluster = lapply(groups, length)),
               scope = list(cluster_id = cluster_id, n_cells = length(ids), cell_ids = ids,
                            cell_ids_sha256 = cell_hash(ids)),
               coverage = coverage, panel = panel, coexpression = co$summary,
               identity_threshold_sensitivity = lapply(1:3, function(threshold) coexpression(counts, ids, threshold)$summary),
               qc = qc, cells = cells, candidate_controls = controls, comparisons = comparison,
               limitations = c("Deterministic exploratory descriptive rules are uncalibrated; no biological probabilities.",
                               "Missing panel genes are null; top30 omission is not nonexpression.",
                               "Observed T/NK coexpression does not establish NKT identity, doublets or causal mechanisms.",
                               "Only actual QC/sample metadata are available; no donor, VDJ or doublet evidence.",
                               "No cells removed, clusters split or normalized values recomputed; full matrix stays local."))
bundle$package_id <- sha_text(as_json(bundle))
source_hashes_after <- lapply(options[c("rds", "cells", "labels", "umap")], sha_file)
if (!identical(source_hashes_before, source_hashes_after)) fail("Source changed during read-only extraction")
output <- options[["output-dir"]]
if (!dir.exists(output) && !dir.create(output, recursive = TRUE)) fail("Cannot create local evidence directory")
output <- normalizePath(output, mustWork = TRUE)
if (output %in% dirname(unlist(options[c("rds", "cells", "labels", "umap")], use.names = FALSE)))
  fail("Output directory must not be a source directory")
expression_path <- file.path(output, "expression.json")
write_immutable(expression_path, bundle)
manifest <- list(schema_version = "scAgentKit.directed_expression_manifest.v1", package_id = bundle$package_id,
                 files = list(list(id = "expression.json", bytes = file.info(expression_path)$size, sha256 = sha_file(expression_path))),
                 source = source, read_only_sources_unchanged = TRUE, network_calls = 0L, credentials_read = FALSE,
                 export_scope = "24 targeted genes: cluster6 local per-cell panel plus aggregates/QC; no whole matrix or truth labels")
write_immutable(file.path(output, "expression-manifest.json"), manifest)
cat(as_json(list(status = "extracted", schema_version = SCHEMA_VERSION, package_id = bundle$package_id,
                 n_cells = length(ids), panel_measured_n = coverage$measured_gene_n,
                 missing_genes = coverage$missing_genes, coexpression = co$summary$counts,
                 low_depth_n = qc$low_depth_n, output = expression_path)), "\n")
