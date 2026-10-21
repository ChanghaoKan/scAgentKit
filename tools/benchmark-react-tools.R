#!/usr/bin/env Rscript
# Manual, offline performance check of the installed stage-1 tool implementation.
# Synthetic matrices and synthetic saved marker statistics are not biological data.
args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  hit <- which(args == paste0("--", name))
  if (!length(hit)) return(default)
  if (length(hit) != 1L || hit == length(args)) stop("Invalid --", name)
  args[[hit + 1L]]
}
mode <- option("mode", "benchmark")
output <- option("output")
if (is.null(output)) stop("Provide --output with a new directory outside the package.")
dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output, mustWork = TRUE)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required.")
write_json <- function(value, path) jsonlite::write_json(value, path,
  auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)
internal <- function(name) getFromNamespace(name, "scAgentKit")
elapsed <- function() unname(proc.time()[["elapsed"]])

if (mode == "worker") {
  start <- elapsed()
  suppressPackageStartupMessages(library(scAgentKit))
  package_ready <- elapsed()
  context <- internal(".sc_run_react_context")(file.path(output, "project"))
  invisible(gc())
  context_ready <- elapsed()
  tool <- option("tool")
  phase <- option("phase", "cold")
  spec <- readRDS(file.path(output, "calls.rds"))[[tool]]
  cache <- file.path(output, "project", "annotation", "react", "cache", tool)
  dispatch <- internal(".sc_run_react_dispatch")
  count <- if (phase == "cold") 4L else 1L
  rows <- vector("list", count)
  for (i in seq_len(count)) {
    before <- elapsed()
    value <- dispatch(context, tool, spec, cache_dir = cache, timeout = 60)
    duration <- elapsed() - before
    rows[[i]] <- list(tool = tool,
      phase = if (phase == "restart") "warm_restart" else if (i == 1L) "cold" else "warm_same_process",
      repetition = if (phase == "restart" || i == 1L) 1L else i - 1L,
      elapsed_seconds = duration, ok = isTRUE(value$ok), cached = isTRUE(value$cached),
      result_hash = value$result_hash,
      result_bytes = nchar(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = NA), type = "bytes"),
      error = value$error)
    if (!isTRUE(value$ok)) break
  }
  rows <- Filter(Negate(is.null), rows)
  write_json(list(package_load_seconds = package_ready - start,
    context_load_seconds = context_ready - package_ready,
    in_process_total_seconds = elapsed() - start, rows = rows),
    file.path(output, paste0(tool, "-", phase, ".json")))
  quit(status = if (all(vapply(rows, function(x) x$ok, logical(1)))) 0L else 2L)
}

if (mode != "benchmark") stop("Unknown --mode.")
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
  value <- tryCatch(system2(command, arguments, stdout = TRUE, stderr = FALSE),
    error = function(e) "unknown")
  paste(value, collapse = " ")
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
rm(object, counts, normal, markers, marker_table, marker_summary, evidence, reference)
invisible(gc())
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]])
script <- normalizePath(script, mustWork = TRUE)
measurements <- list()
for (tool in names(calls)) for (phase in c("cold", "restart")) {
  before <- elapsed()
  logfile <- file.path(output, paste0(tool, "-", phase, ".log"))
  executable <- file.path(R.home("bin"), "Rscript")
  arguments <- c("--vanilla", shQuote(script), "--mode", "worker", "--output", shQuote(output),
    "--tool", tool, "--phase", phase)
  measured_rss <- identical(unname(Sys.info()[["sysname"]]), "Darwin") &&
    file.exists("/usr/bin/time")
  if (measured_rss) {
    arguments <- c("-l", shQuote(executable), arguments)
    executable <- "/usr/bin/time"
  }
  code <- system2(executable, arguments, stdout = logfile, stderr = logfile)
  wall <- elapsed() - before
  record_path <- file.path(output, paste0(tool, "-", phase, ".json"))
  record <- if (file.exists(record_path)) jsonlite::read_json(record_path, simplifyVector = FALSE) else list()
  record$tool <- tool
  record$process_phase <- phase
  record$process_wall_seconds <- wall
  record$exit_status <- code
  rss <- if (measured_rss) grep("maximum resident set size", readLines(logfile, warn = FALSE), value = TRUE) else character()
  record$process_maximum_resident_bytes <- if (length(rss) == 1L)
    as.numeric(sub("^\\s*([0-9]+).*$", "\\1", rss)) else NULL
  measurements[[length(measurements) + 1L]] <- record
}
rows <- do.call(rbind, lapply(measurements, function(run)
  do.call(rbind, lapply(run$rows, function(row) data.frame(
    tool = run$tool, phase = row$phase, repetition = row$repetition,
    dispatch_seconds = row$elapsed_seconds, package_load_seconds = run$package_load_seconds,
    context_load_seconds = run$context_load_seconds, process_wall_seconds = run$process_wall_seconds,
    process_maximum_resident_bytes = if (is.null(run$process_maximum_resident_bytes)) NA_real_ else run$process_maximum_resident_bytes,
    ok = row$ok, cached = row$cached,
    result_hash = if (is.null(row$result_hash)) NA_character_ else row$result_hash,
    error_code = if (is.null(row$error$code)) NA_character_ else row$error$code,
    result_bytes = row$result_bytes, stringsAsFactors = FALSE)))))
if (!is.null(rows)) utils::write.csv(rows, file.path(output, "timings.csv"), row.names = FALSE)
valid <- length(measurements) == 8L && all(vapply(measurements, function(run)
  identical(as.integer(run$exit_status), 0L) && length(run$rows) > 0 &&
    all(vapply(run$rows, function(row) isTRUE(row$ok) && row$elapsed_seconds <= 60, logical(1))),
  logical(1)))
cache_correct <- !is.null(rows) && all(!rows$cached[rows$phase == "cold"]) &&
  all(rows$cached[rows$phase != "cold"]) && all(vapply(split(rows$result_hash, rows$tool),
    function(x) length(unique(x)) == 1L, logical(1)))
report <- list(schema = "scagentkit.react-tools-benchmark.v1", machine = machine,
  dataset = dataset, passed = valid && cache_correct, cache_correct = cache_correct,
  timings = measurements,
  scope = paste("Offline synthetic performance only. Cold means new R process and empty application cache;",
    "OS disk cache is not flushed. Dispatch includes checksum validation, isolated worker startup,",
    "tool computation, privacy/size checks and cache writes. Context and package load are separately measured.",
    "No provider call, scientific annotation, DE, or biological accuracy validation was performed."))
write_json(report, file.path(output, "benchmark.json"))
cat("Benchmark results: ", file.path(output, "benchmark.json"), "\n", sep = "")
cat("Passed: ", report$passed, "\n", sep = "")
if (!report$passed) quit(status = 2L)
