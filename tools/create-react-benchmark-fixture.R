#!/usr/bin/env Rscript
# Create the synthetic fixture for the current session-worker benchmark.
# Synthetic matrices and synthetic saved marker statistics are not biological data.
args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  hit <- which(args == paste0("--", name))
  if (!length(hit)) return(default)
  if (length(hit) != 1L || hit == length(args)) stop("Invalid --", name)
  args[[hit + 1L]]
}
output <- option("output")
if (is.null(output)) stop("Provide --output with a new directory outside the package.")
dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output, mustWork = TRUE)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required.")
write_json <- function(value, path) jsonlite::write_json(value, path,
  auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)
internal <- function(name) getFromNamespace(name, "scAgentKit")
elapsed <- function() unname(proc.time()[["elapsed"]])

if (file.exists(file.path(output, "project", "state.rds")))
  stop("Use a new output directory: existing projects/caches are never removed.")
required <- c("scAgentKit", "Seurat", "SeuratObject", "Matrix", "digest", "callr")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install the current package and dependencies first: ", paste(missing, collapse = ", "))
cells_n <- as.integer(option("cells", "50000"))
features_n <- as.integer(option("features", "20000"))
density <- as.numeric(option("density", "0.05"))
if (is.na(cells_n) || cells_n < 50000L || is.na(features_n) || features_n < 2000L ||
    !is.finite(density) || density <= 0 || density > 0.1)
  stop("Require >=50000 cells, >=2000 features and density in (0, 0.1].")
seed <- 20261020L
set.seed(seed)
setup_start <- elapsed()
reference <- scAgentKit::annot_act_reference("human", "Blood")
act_genes <- unique(as.character(reference$marker))
act_genes <- act_genes[!is.na(act_genes) & nzchar(act_genes) & !grepl("[_|]", act_genes)]
genes <- c(head(act_genes, 100L), paste0("BENCHGENE", seq_len(features_n)))
genes <- unique(genes)[seq_len(features_n)]
cells <- sprintf("SYNTHETIC_PRIVATE_CELL_%06d", seq_len(cells_n))
counts <- Matrix::rsparsematrix(features_n, cells_n, density = density,
  rand.x = function(n) stats::rpois(n, lambda = 1) + 1L)
dimnames(counts) <- list(genes, cells)
object <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
stopifnot(identical(rownames(object), genes), identical(colnames(object), cells))
totals <- Matrix::colSums(counts)
normal <- counts %*% Matrix::Diagonal(x = ifelse(totals > 0, 10000 / totals, 0))
normal@x <- log1p(normal@x)
SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- normal
object$seurat_clusters <- sprintf("cluster_%02d", (seq_len(cells_n) - 1L) %% 20L + 1L)
object$sample <- sprintf("sample_%02d", ((seq_len(cells_n) - 1L) %/% 20L) %% 8L + 1L)
object$percent.mt <- 100 * Matrix::colSums(counts[seq_len(50L), , drop = FALSE]) / pmax(totals, 1)
clusters <- sort(unique(object$seurat_clusters), method = "radix")
marker_table <- do.call(rbind, lapply(seq_along(clusters), function(i) {
  index <- ((seq_len(1000L) - 1L + (i - 1L) * 997L) %% features_n) + 1L
  data.frame(cluster = clusters[[i]], gene = genes[index],
    avg_log2FC = seq(4, 0.01, length.out = 1000L),
    pct.1 = 0.6, pct.2 = 0.1, p_val = 0.001, p_val_adj = 0.01,
    stringsAsFactors = FALSE)
}))
marker_summary <- marker_table[unlist(lapply(clusters, function(id)
  head(which(marker_table$cluster == id), 30L))), , drop = FALSE]
parameters <- list(only_pos = FALSE, min_pct = 0.25, logfc_threshold = 0,
  top_n = 30L, log2fc_cut = 1, padj_cut = 0.05, exclude_shared = TRUE,
  exclude_genes = character())
attr(marker_summary, "marker_pool") <- list(status = "recorded", parameters = parameters,
  exclusions = list(explicit_genes = list(), excluded_genes = list()),
  limitation = "Synthetic saved statistics for read-only tool performance; no differential expression was run.")
markers <- list(markers = marker_table, marker_summary = marker_summary,
  cluster_column = "seurat_clusters", parameters = parameters)
study <- list(species = "human", tissue = "Blood",
  description = "Offline synthetic performance fixture; no biological inference.",
  columns = list(sample = "sample"))
config <- list(context = study, assay = "RNA", counts_layer = "counts",
  normalized_layer = "data", cluster_column = "seurat_clusters",
  annotation_column = "sc_annotation", analysis = list(), markers = list(),
  review = list(allow_external = FALSE),
  start_stage = "processed", reference_review = list(),
  processed_reason = "Synthetic benchmark fixture, not approved scientific analysis.")
root <- internal(".sc_run_root")(file.path(output, "project"), create = TRUE)
hash <- internal(".sc_run_hash")
state <- list(project_format_version = internal(".sc_project_format_version")(),
  project_id = "react-tools-synthetic-performance",
  status = "ready", stage = "annotation_propose", revision = 0L, history = list(),
  config = config, config_hash = hash(config),
  implementation_hash = internal(".sc_run_implementation")(),
  source = list(path = NULL), diagnostics = list(), files = list(),
  approvals = list(), transfer_hashes = character(), pending = NULL, approved = NULL,
  completed = c("analysis", "markers", "annotation_evidence"),
  nodes = list(), failure = NULL, output = NULL)
put <- internal(".sc_run_put")
state <- put(root, state, "input", object)
state$input_hash <- state$files$input$sha256
state <- put(root, state, "analysis", object)
state <- put(root, state, "markers", markers)
state <- put(root, state, "reference", reference)
state <- put(root, state, "doublet_diagnostics", list(cell_ids = cells,
  scores = data.frame(cell_id = cells, synthetic_doublet_score = (seq_len(cells_n) %% 101) / 100),
  summary = list(columns = c(score = "synthetic_doublet_score"),
    provenance = "Synthetic saved scores; no classifier was run.")))
cycle_s <- sin(seq_len(cells_n) / 100)
cycle_g2m <- cos(seq_len(cells_n) / 100)
state <- put(root, state, "cycle_diagnostics", list(cell_ids = cells,
  scores = data.frame(cell_id = cells, synthetic_s_score = cycle_s,
    synthetic_g2m_score = cycle_g2m, synthetic_difference = cycle_s - cycle_g2m),
  summary = list(columns = c(s_score = "synthetic_s_score", g2m_score = "synthetic_g2m_score",
    difference = "synthetic_difference"), provenance = "Synthetic saved scores; no cycle scorer was run.")))
evidence <- internal(".sc_run_annotation_evidence")(object, markers, study, reference,
  cluster_column = "seurat_clusters", assay = "RNA")
state <- put(root, state, "annotation_evidence", evidence)
state <- internal(".sc_run_event")(state, "synthetic_benchmark_fixture_created",
  list(seed = seed, biological_data = FALSE, differential_expression_executed = FALSE))
internal(".sc_run_save")(root, state)
calls <- list(
  cluster_markers = list(cluster_id = clusters[[1L]], n = 50L),
  gene_expression = list(cluster_id = clusters[[1L]], genes = as.list(head(genes, 20L))),
  act_lookup = list(genes = as.list(head(genes, 20L))),
  cluster_context = list(cluster_id = clusters[[1L]]))
saveRDS(calls, file.path(output, "calls.rds"))
command_value <- function(command, arguments) {
  if (!nzchar(Sys.which(command))) return("unknown")
  value <- tryCatch(suppressWarnings(system2(command, arguments, stdout = TRUE, stderr = FALSE)),
    error = function(e) character())
  if (!length(value) || !is.null(attr(value, "status"))) "unknown" else paste(value, collapse = " ")
}
packages <- unique(c(required, "agentomicsCore", "jsonlite", "processx", "ps"))
machine <- list(os = as.list(Sys.info()[c("sysname", "release", "version", "machine")]),
  macos_version = command_value("sw_vers", "-productVersion"),
  cpu = command_value("sysctl", c("-n", "machdep.cpu.brand_string")),
  memory_bytes = command_value("sysctl", c("-n", "hw.memsize")),
  logical_cpus = parallel::detectCores(logical = TRUE),
  r = R.version.string, package_versions = stats::setNames(lapply(packages,
    function(p) as.character(utils::packageVersion(p))), packages))
dataset <- list(kind = "synthetic_sparse_Seurat", seed = seed, cells = cells_n,
  implementation_hash = state$implementation_hash,
  features = features_n, target_density = density, actual_density = length(counts@x) / (cells_n * features_n),
  nonzero_counts = length(counts@x), clusters = length(clusters), samples = 8L,
  detected_features_per_cell = as.list(stats::quantile(Matrix::colSums(counts > 0),
    probs = c(0, .25, .5, .75, 1), names = FALSE)),
  markers_per_cluster = 1000L, saved_marker_statistics = "synthetic; FindAllMarkers was not executed",
  normalization = "log1p(counts / cell_total * 10000)",
  optional_doublet_cycle = "synthetic saved per-cell scores; no classifier or cycle scorer was run",
  act = list(snapshot = attr(reference, "source_version"), tissue = "Blood", rows = nrow(reference)),
  checkpoint_bytes = sum(file.info(file.path(root, vapply(state$files, `[[`, "", "path")))$size),
  setup_seconds = elapsed() - setup_start)
write_json(list(machine = machine, dataset = dataset), file.path(output, "environment.json"))
cat("Synthetic fixture: ", output, "\n", sep = "")
