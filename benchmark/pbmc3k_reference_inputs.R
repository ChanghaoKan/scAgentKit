#!/usr/bin/env Rscript
# Prepare database candidates and exact guided/independent annotation prompts
# from a saved blind PBMC run. No provider, network call, or truth-label read.

parse_cli <- function(args) {
  opt <- list(run_dir = "", reference_csv = "", out_dir = "", library_dir = "")
  if ("--help" %in% args) {
    cat("Rscript benchmark/pbmc3k_reference_inputs.R --run_dir PATH --reference_csv PATH\n",
        "  --out_dir NEW_PATH [--library_dir PATH]\n",
        "Reference CSV must already be restricted to normal human blood tissues.\n",
        "This script prepares inputs only: no LLM calls, downloads, or truth reads.\n", sep = "")
    quit(status = 0L)
  }
  if (length(args) %% 2L) stop("Use --name value pairs; see --help.")
  if (length(args)) for (i in seq.int(1L, length(args), by = 2L)) {
    key <- sub("^--", "", args[[i]])
    if (!startsWith(args[[i]], "--") || !key %in% names(opt)) stop("Unknown argument: ", args[[i]])
    opt[[key]] <- args[[i + 1L]]
  }
  if (!all(vapply(opt[c("run_dir", "reference_csv", "out_dir")], nzchar, logical(1)))) {
    stop("--run_dir, --reference_csv, and --out_dir are required.")
  }
  opt
}

opt <- parse_cli(commandArgs(trailingOnly = TRUE))
if (nzchar(opt$library_dir)) .libPaths(c(normalizePath(opt$library_dir), .libPaths()))
if (!dir.exists(opt$run_dir) || !file.exists(opt$reference_csv)) stop("Saved run and reference CSV must be local.")
if (dir.exists(opt$out_dir) && length(list.files(opt$out_dir, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be empty to preserve previous results.")
}
dir.create(opt$out_dir, recursive = TRUE, showWarnings = FALSE)
out_dir <- normalizePath(opt$out_dir)
run_dir <- normalizePath(opt$run_dir)
reference_path <- normalizePath(opt$reference_csv)
started <- Sys.time()
writeLines("status: starting", file.path(out_dir, "prepare_status.txt"))
options(error = function() {
  writeLines(c("status: failed", paste("error:", geterrmessage())),
             file.path(out_dir, "prepare_status.txt"))
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  quit(status = 1L)
})
for (p in c("scAgentKit", "agentomicsCore", "Seurat", "jsonlite")) {
  if (!requireNamespace(p, quietly = TRUE)) stop("Missing dependency: ", p)
}
if (!"annot_review_evidence" %in% getNamespaceExports("scAgentKit")) {
  stop("Install the corrected local scAgentKit build containing annot_review_evidence first.")
}
md5 <- function(path) unname(tools::md5sum(path))
write_csv <- function(x, name) utils::write.csv(x, file.path(out_dir, name), row.names = FALSE)
write_json <- function(x, name) jsonlite::write_json(x, file.path(out_dir, name),
  auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
status_path <- file.path(run_dir, "run_status.txt")
if (!file.exists(status_path) || !any(readLines(status_path, warn = FALSE) == "status: success")) {
  stop("A successful saved blind PBMC run is required.")
}
agent_path <- file.path(run_dir, "scagentkit_fixed_agent.rds")
obj <- readRDS(agent_path)
if (!methods::is(obj, "AgentSeurat") || !inherits(scAgentKit::get_seurat(obj), "Seurat")) {
  stop("Saved object must be an AgentSeurat with Seurat data.")
}
if (!is.null(obj@params$llm_annotations)) stop("Expected an unannotated saved input; LLM annotations already exist.")
meta <- scAgentKit::get_seurat(obj)@meta.data
allowed_metadata <- c("orig.ident", "nCount_RNA", "nFeature_RNA", "percent.mt",
                      "percent.ribo", "percent.hb", "seurat_clusters")
unexpected <- setdiff(names(meta), c(allowed_metadata, names(meta)[grepl("^RNA_snn_res\\.", names(meta))]))
if (length(unexpected)) stop("Unexpected input metadata; refusing possible reference-label leakage: ",
                             paste(unexpected, collapse = ", "))
if (!"seurat_clusters" %in% names(meta) || anyNA(meta$seurat_clusters)) stop("Saved cluster IDs are required.")
filtered <- obj@params$markers_filtered
if (!is.data.frame(filtered) || !nrow(filtered) ||
    !all(c("cluster", "gene", "pct.1", "pct.2") %in% names(filtered))) {
  stop("Saved filtered marker evidence is missing or incomplete.")
}
input_cells <- data.frame(cell_id = rownames(meta), cluster = as.character(meta$seurat_clusters),
                           stringsAsFactors = FALSE)
write_csv(input_cells, "input_cells.csv")
write_csv(filtered, "markers_filtered.csv")

# The source preparation already selected Blood/Peripheral blood/Venous blood.
# Reapplying exact tissue='blood' here would discard valid peripheral rows.
reference <- scAgentKit::annot_load_reference(reference_path, tissue_filter = NULL, species = "human")
if (!nrow(reference)) stop("Prepared human blood reference is empty.")
if ("tissue" %in% names(reference) &&
    any(!tolower(trimws(reference$tissue)) %in% c("blood", "peripheral blood", "venous blood"))) {
  stop("Reference has tissues outside the prepared human blood allowlist.")
}
prepared_manifest_path <- sub("\\.csv$", "_manifest.json", reference_path, ignore.case = TRUE)
prepared_manifest <- if (file.exists(prepared_manifest_path)) {
  jsonlite::fromJSON(prepared_manifest_path, simplifyVector = FALSE)
} else NULL
if (!is.null(prepared_manifest)) {
  if (!is.null(prepared_manifest$download_url)) attr(reference, "source_url") <- prepared_manifest$download_url
  if (!is.null(prepared_manifest$database)) attr(reference, "source_version") <- prepared_manifest$database
  if (!is.null(prepared_manifest$normalization$marker_column)) {
    attr(reference, "marker_column") <- prepared_manifest$normalization$marker_column
  }
  file.copy(prepared_manifest_path, file.path(out_dir, "prepared_reference_manifest.json"))
}
write_csv(reference, "used_reference.csv")
saveRDS(reference, file.path(out_dir, "used_reference.rds"), version = 3L)
obj <- scAgentKit::annot_match_reference(obj, reference, top_n_candidates = 5L,
  rationale = "Offline match against prepared normal human blood gene-symbol reference; no truth-label input.")
obj <- scAgentKit::annot_review_evidence(obj,
  rationale = "Offline database branch review; LLM branch is not run without authorization, so outcomes remain unknown and pending.")
all_candidates <- obj@params$reference_matches_all
matches <- obj@params$reference_matches
review <- obj@params$annotation_evidence_review
write_csv(all_candidates, "database_all_candidates.csv")
write_csv(matches, "database_top5_candidates.csv")
write_csv(review, "annotation_evidence_review.csv")
write_json(obj@params$reference_provenance, "reference_provenance.json")
saveRDS(obj@params$annotation_evidence_review_inputs,
        file.path(out_dir, "annotation_evidence_review_inputs.rds"), version = 3L)

# A unique highest positive score is an unreviewed heuristic candidate.
# Different labels tied at that score remain unknown. No majority vote or
# mapping to the independently stored PBMC truth classes is performed.
best <- data.frame(cluster = as.character(review$cluster),
  candidate_annotation = ifelse(is.na(review$reference_annotation), "unknown", review$reference_annotation),
  candidate_status = ifelse(review$reference_ambiguous, "unknown_reference_tie",
    ifelse(is.na(review$reference_annotation), "unknown_no_reference_support", "heuristic_candidate_unreviewed")),
  reference_score = review$reference_score,
  tied_candidates = review$reference_best_candidates,
  supporting_markers = review$reference_supporting_markers,
  reviewed_annotation = "unknown", review_status = "pending", stringsAsFactors = FALSE)
write_csv(best, "database_best_candidates.csv")
idx <- match(input_cells$cluster, best$cluster)
write_csv(data.frame(input_cells, method = "database_reference",
  candidate_annotation = best$candidate_annotation[idx], candidate_status = best$candidate_status[idx],
  reference_score = best$reference_score[idx], tied_candidates = best$tied_candidates[idx],
  label = best$candidate_annotation[idx], unknown = best$candidate_annotation[idx] == "unknown",
  reviewed_annotation = "unknown", review_status = "pending"), "database_cell_labels.csv")
for (mode in c("guided", "independent")) {
  write_csv(data.frame(input_cells, method = paste0("llm_", mode), label = "unknown",
    unknown = TRUE, status = "not_run_no_authorization", reviewed_annotation = "unknown",
    review_status = "pending"), paste0("llm_", mode, "_cell_labels.csv"))
}

# Use the actual installed builders rather than a mock provider or copied
# prompt text. The cycling selection matches annot_llm_annotate exactly.
helpers <- c(".build_system_prompt", ".build_user_prompt", ".annotation_marker_evidence",
             ".compute_lineage_rescue")
builder <- stats::setNames(lapply(helpers, function(name) getFromNamespace(name, "scAgentKit")), helpers)
capture <- unlist(lapply(helpers, function(name) {
  c(paste0("# ", name), capture.output(dput(builder[[name]])), "")
}), use.names = FALSE)
writeLines(capture, file.path(out_dir, "installed_prompt_builders.R"))
clusters <- sort(unique(as.character(filtered$cluster)))
cluster_sizes <- table(input_cells$cluster)
cluster_pcts <- 100 * as.numeric(cluster_sizes) / nrow(input_cells)
names(cluster_pcts) <- names(cluster_sizes)
cycling_map <- obj@params$cluster_cycling_score
is_cycling <- if (!is.null(cycling_map)) {
  stats::setNames(cycling_map$cycling_dominant, as.character(cycling_map$cluster))
} else stats::setNames(logical(0), character(0))
cycling_rescue <- list()
cycling_clusters <- names(is_cycling)[!is.na(is_cycling) & is_cycling & names(is_cycling) %in% clusters]
for (cid in cycling_clusters) {
  cycling_rescue[[cid]] <- builder[[".compute_lineage_rescue"]](scAgentKit::get_seurat(obj), cid, n_top = 30L)
}
prompt_audit <- list()
budget_rows <- list()
dir.create(file.path(out_dir, "prompts"), showWarnings = FALSE)
for (mode in c("guided", "independent")) {
  system_prompt <- builder[[".build_system_prompt"]](
    tissue = "human PBMC / blood", condition = "normal peripheral blood",
    expected_celltypes = NULL, strict_vocabulary = FALSE, reference_mode = mode)
  mode_audit <- list()
  for (i in seq_along(clusters)) {
    cid <- clusters[[i]]
    marker_evidence <- builder[[".annotation_marker_evidence"]](cid, filtered, cycling_rescue[[cid]])
    marker_evidence$cycling_dominant <- isTRUE(is_cycling[cid])
    user_prompt <- builder[[".build_user_prompt"]](
      cid, filtered, matches, cluster_sizes, cluster_pcts,
      is_cycling = isTRUE(is_cycling[cid]), cycling_rescue = cycling_rescue[[cid]],
      marker_evidence = marker_evidence, reference_mode = mode, strict_vocabulary = FALSE)
    prefix <- file.path("prompts", sprintf("%s_%02d_cluster_%s", mode, i,
                                           gsub("[^[:alnum:]_-]", "_", cid)))
    writeLines(system_prompt, file.path(out_dir, paste0(prefix, "_system.txt")), useBytes = TRUE)
    writeLines(user_prompt, file.path(out_dir, paste0(prefix, "_user.txt")), useBytes = TRUE)
    record <- list(cluster = cid, reference_mode = mode,
      system_prompt = system_prompt, user_prompt = user_prompt, marker_evidence = marker_evidence,
      source_reference_candidates = matches[as.character(matches$cluster) == cid, , drop = FALSE],
      reference_candidates_in_prompt = mode == "guided",
      cell_ids = input_cells$cell_id[input_cells$cluster == cid],
      llm_status = "not_run_no_authorization", raw_response = NULL, n_samples = 1L, max_retries = 0L)
    mode_audit[[cid]] <- record
    write_json(record, paste0(prefix, "_input.json"))
    budget_rows[[length(budget_rows) + 1L]] <- data.frame(
      reference_mode = mode, cluster = cid, n_cells = as.integer(cluster_sizes[[cid]]),
      n_differential_markers = nrow(marker_evidence$differential),
      n_rescue_markers = if (is.null(marker_evidence$lineage_rescue)) 0L else nrow(marker_evidence$lineage_rescue),
      cycling_dominant = marker_evidence$cycling_dominant,
      system_chars = nchar(system_prompt, type = "chars"), user_chars = nchar(user_prompt, type = "chars"),
      input_chars = nchar(system_prompt, type = "chars") + nchar(user_prompt, type = "chars"),
      system_bytes = nchar(enc2utf8(system_prompt), type = "bytes"),
      user_bytes = nchar(enc2utf8(user_prompt), type = "bytes"),
      input_bytes = nchar(enc2utf8(system_prompt), type = "bytes") + nchar(enc2utf8(user_prompt), type = "bytes"),
      planned_calls_if_authorized = 1L, n_samples = 1L, max_retries = 0L,
      status = "not_run_no_authorization", stringsAsFactors = FALSE)
  }
  prompt_audit[[mode]] <- mode_audit
}
stopifnot(identical(lapply(prompt_audit$guided, `[[`, "marker_evidence"),
                    lapply(prompt_audit$independent, `[[`, "marker_evidence")))
if (!all(review$review_outcome == "unknown") || !all(review$review_status == "pending")) {
  stop("Missing LLM branch must produce only unknown, pending evidence reviews.")
}
budget <- do.call(rbind, budget_rows)
write_csv(budget, "prompt_budget_inputs.csv")
saveRDS(prompt_audit, file.path(out_dir, "prompt_inputs.rds"), version = 3L)
write_json(prompt_audit, "prompt_inputs.json")
saveRDS(obj, file.path(out_dir, "reference_review_agent.rds"), version = 3L)
saveRDS(scAgentKit::get_decisions(obj), file.path(out_dir, "audit_decisions.rds"), version = 3L)
source_args <- commandArgs(trailingOnly = FALSE)
script_path <- normalizePath(sub("^--file=", "", source_args[startsWith(source_args, "--file=")][1L]))
file.copy(script_path, file.path(out_dir, "prepare_inputs.R"))
write_json(list(schema_version = 1L, status = "prepared_no_llm",
  role = "database heuristic candidates and actual provider inputs; not truth or accuracy evidence",
  source_run = run_dir, saved_agent_md5 = md5(agent_path), reference_csv = reference_path,
  reference_md5 = md5(reference_path), reference_provenance = obj@params$reference_provenance,
  prepared_reference_manifest = prepared_manifest,
  tissue_policy = "CSV already prepared for human normal Blood/Peripheral blood/Venous blood; no repeated exact blood filter",
  tissue = "human PBMC / blood", condition = "normal peripheral blood",
  expected_celltypes = NULL, expected_n_clusters = NULL, strict_vocabulary = FALSE,
  n_cells = nrow(input_cells), n_clusters_in_data = length(unique(input_cells$cluster)),
  n_prompt_clusters_per_mode = length(clusters), clusters_without_filtered_markers = setdiff(unique(input_cells$cluster), clusters),
  reference_modes = c("guided", "independent"), identical_marker_evidence = TRUE,
  llm_status = "not_run_no_authorization", llm_calls = 0L, network_calls = 0L,
  truth_labels_read = FALSE, n_samples = 1L, max_retries = 0L,
  planned_calls_if_authorized = 2L * length(clusters), planned_retry_calls = 0L,
  second_review = "manual analyst review pending; no second LLM call planned",
  input_chars_total = sum(budget$input_chars), input_bytes_total = sum(budget$input_bytes),
  token_counts = "not estimated by this script; budget inputs report actual chars and UTF-8 bytes",
  script_md5 = md5(script_path), package_version = as.character(utils::packageVersion("scAgentKit")),
  elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))), "manifest.json")
writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
writeLines(c("status: success", "llm_status: not_run_no_authorization", "llm_calls: 0",
             "network_calls: 0", "truth_labels_read: FALSE",
             paste("planned_calls_if_authorized:", 2L * length(clusters)),
             "review_outcomes: unknown; all pending", "annotation_accuracy: not evaluated"),
           file.path(out_dir, "prepare_status.txt"))
message("[pbmc3k_reference_inputs] prepared ", 2L * length(clusters),
        " prompt inputs with zero LLM calls; artifacts: ", out_dir)
