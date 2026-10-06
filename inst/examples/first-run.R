#!/usr/bin/env Rscript
# Source this helper for your own matrix/Seurat/local-RDS input, or use its
# explicitly synthetic CLI: first-run.R PROJECT_DIR demo|inspect|revise-qc|approve|reject|resume|revise-annotation|output
# No secrets are saved here. A default provider=NULL run makes no model request.

suppressPackageStartupMessages(library(scAgentKit))
if (!"sc_run_review" %in% getNamespaceExports("scAgentKit") ||
    !exists(".sc_run_annotation_target", envir = asNamespace("scAgentKit"), inherits = FALSE))
  stop("Install this checkout's package and select its R library before starting a project.", call. = FALSE)

.first_run_brief <- function(current) {
  cat("Status:", current$status, "Stage:", current$stage, "Revision:", current$revision, "\n")
  if (identical(current$status, "awaiting_review"))
    cat("Checkpoint saved. Inspect the proposal and decide; R may exit normally here.\n")
  else if (identical(current$status, "awaiting_configuration"))
    cat("Checkpoint saved. Supply the missing manual proposal or provider configuration; no decision was invented.\n")
  else if (identical(current$status, "ready"))
    cat("Decision saved. Continue explicitly with first_run_resume(project_dir).\n")
  if (!is.null(current$diagnostics$provider_configuration_needed))
    cat("Provider configuration needed:", current$diagnostics$provider_configuration_needed,
        "\nConfigure the runtime environment/function and explicitly resume; no dispatch was sent.\n")
  if (!is.null(current$failure)) cat("Stopped:", current$failure$message, "\n")
  if (!is.null(current$output)) cat("Final object:", current$output$seurat, "\n")
  invisible(current)
}

# The single starting call forwards the existing coordinator's validated input
# and configuration contract. It does not infer metadata, rename IDs or tune QC.
first_run_start <- function(input, project_dir, context = list(), provider = NULL,
                            chat_fn = NULL, budget = 0, ...) {
  result <- sc_run(input, project_dir, context = context, provider = provider,
                   chat_fn = chat_fn, budget = budget, ...)
  .first_run_brief(result)
  invisible(result)
}

first_run_inspect <- function(project_dir, save_snapshot = TRUE) {
  current <- sc_run_inspect(project_dir)
  .first_run_brief(current)
  if (!is.null(current$pending) && identical(current$pending$kind, "external_transfer")) {
    cat("External-transfer preview: review this exact aggregate payload and provider before approving.\n")
    print(current$pending$proposal)
  } else if (current$stage %in% c("qc_propose", "qc_apply") &&
      !is.null(current$qc_preview) && !is.null(current$review_node) &&
      identical(current$review_node$kind, "qc")) {
    impact <- current$qc_preview$details
    cat("Actual declared sample/capture QC evidence (all groups):\n")
    print(do.call(rbind, lapply(current$evidence$groups, function(group) {
      label <- function(value) if (is.null(value)) "not declared" else value
      data.frame(group = group$group_id, sample = label(group$selector$sample),
        capture = label(group$selector$capture), cells = group$cells,
        count_p05 = group$metrics$nCount$p05, count_median = group$metrics$nCount$median,
        count_p95 = group$metrics$nCount$p95, feature_p05 = group$metrics$nFeature$p05,
        feature_median = group$metrics$nFeature$median, feature_p95 = group$metrics$nFeature$p95,
        mt_median = group$metrics$percent_mt$median, mt_unavailable = group$metrics$percent_mt$missing)
    })))
    cat("Primary rule and predicted retention:\n")
    print(impact$canonical_parameters$proposal); print(impact$retention)
    cat("Measured removal causes may overlap; unavailable values are separate:\n")
    print(do.call(rbind, lapply(impact$filter_impacts, function(item)
      data.frame(id = item$id, metric = item$filter$metric, scoped = item$scoped,
        low = item$low, high = item$high, unavailable = item$unavailable,
        independent = item$independently_removed, exclusive = item$exclusively_removed))))
    overlap <- do.call(rbind, lapply(impact$overlap$counts, unlist, use.names = FALSE))
    dimnames(overlap) <- list(impact$overlap$filter_ids, impact$overlap$filter_ids)
    cat("Measured exclusion overlap:\n"); print(overlap)
    cat("Unavailable metric counts:\n")
    print(do.call(rbind, lapply(impact$unavailable$metrics, function(item)
      data.frame(metric = item$metric, unavailable = item$count))))
    cat("Complete distributions and exact kept/removed IDs are available in current$qc_preview$details.\n")
  } else if (!is.null(current$annotation_review)) {
    review <- current$annotation_review
    cat("Current proposal source:", review$details$source$kind, "\n")
    cat("Exact cell scope:", review$details$cell_count, "cells;",
        review$details$cluster_count, "clusters.\n")
    for (row in review$details$annotations) {
      cat("\nLiteral cluster:", row$clusterId, "Cells:", row$cell_count, "\n")
      print(row$proposal)
      cat("Supplied marker statistics: first", min(5L, length(row$supplied_marker_stats)),
          "of", length(row$supplied_marker_stats), "saved rows:\n")
      if (length(row$supplied_marker_stats)) print(do.call(rbind, lapply(
        head(row$supplied_marker_stats, 5L), as.data.frame, stringsAsFactors = FALSE)))
      else cat("No marker rows supplied; this does not establish absent expression.\n")
      cat("Saved local-reference status:", row$local_reference$status,
          "; independent negative evidence assessed:", row$negative_evidence$assessed, "\n")
    }
    cat("Confidence is qualitative. Complete evidence/source/limitations are in current$annotation_review$details.\n")
  } else if (!is.null(current$evidence)) {
    cat("Saved evidence; no supported proposal is yet ready:\n"); print(current$evidence)
  }
  if (!is.null(current$review_node)) print(current$review_node)
  if (isTRUE(save_snapshot)) {
    # Convenience snapshot of what was displayed, not an authoritative state.
    # R revalidates its identities under the project lock when a decision is sent.
    path <- file.path(project_dir, "first-use-reviewed-snapshot.rds")
    tmp <- tempfile(".first-use-snapshot-", tmpdir = project_dir)
    on.exit(unlink(tmp), add = TRUE)
    saveRDS(current, tmp)
    if (!file.rename(tmp, path)) stop("Cannot save the inspected launcher snapshot.", call. = FALSE)
    cat("Displayed snapshot saved. Changed proposals require another inspection.\n")
  }
  invisible(current)
}

first_run_decide <- function(project_dir, action, reason, reviewer,
                             snapshot = NULL, proposal = NULL, decision_id = NULL) {
  if (is.null(snapshot)) {
    path <- file.path(project_dir, "first-use-reviewed-snapshot.rds")
    if (!file.exists(path)) stop("Inspect and review the project before deciding.", call. = FALSE)
    snapshot <- readRDS(path)
  }
  node <- snapshot$review_node
  if (!is.null(node)) {
    args <- c(list(project_dir = project_dir, action = action, reviewer = reviewer, reason = reason),
      node[c("kind", "project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision")])
    if (!is.null(proposal)) args$proposal <- proposal
    if (!is.null(decision_id)) args$decision_id <- decision_id
    result <- do.call(sc_run_review, args)
  } else if (!is.null(snapshot$pending) && identical(snapshot$pending$kind, "external_transfer")) {
    if (!action %in% c("approve", "reject") || !is.null(proposal) || !is.null(decision_id))
      stop("An external preview accepts explicit approve/reject only.", call. = FALSE)
    current <- sc_run_inspect(project_dir)
    if (!identical(snapshot$project_id, current$project_id) ||
        !identical(snapshot$input_hash, current$input_hash))
      stop("This external-transfer snapshot belongs to another project/input; inspect the configured project.", call. = FALSE)
    # The pending hash binds the complete payload/model/input/configuration;
    # expected_revision also rejects a newer unseen transfer checkpoint.
    result <- do.call(if (action == "approve") sc_run_approve else sc_run_reject,
      list(project_dir = project_dir, proposal_hash = snapshot$pending$hash,
           expected_revision = snapshot$revision, reviewer = reviewer, reason = reason))
  } else stop("No inspected proposal can be decided. Supply a typed initial proposal or configure the provider first.", call. = FALSE)
  .first_run_brief(result)
  invisible(result)
}

first_run_resume <- function(project_dir, chat_fn = NULL, retry = FALSE) {
  result <- sc_run_resume(project_dir, chat_fn = chat_fn, retry = retry)
  .first_run_brief(result)
  invisible(result)
}

first_run_unknown <- function(current, rationale = "Manual review retains unresolved identity; no specific type is accepted.") {
  clusters <- if (!is.null(current$annotation_review)) current$annotation_review$details$annotations
    else current$evidence$clusters
  if (is.null(clusters) || !length(clusters) || !identical(current$stage, "annotation_propose"))
    stop("Inspect saved annotation evidence before creating a manual Unknown proposal.", call. = FALSE)
  list(schema = "scagentkit.annotation.v1", annotations = lapply(clusters, function(cluster)
    list(clusterId = cluster$clusterId, label = "Unknown", confidence = "low",
         rationale = rationale, markers = list())))
}

# Configuration only: built-in factories read the key at dispatch. Only its
# environment variable NAME can enter this metadata. No key is returned/saved.
first_run_provider <- function(name = c("deepseek", "grok"), model = Sys.getenv("SC_MODEL_ID"),
                               pricing = NULL, reservation_usd = .05,
                               generation = list(temperature = 0, max_tokens = 4096L)) {
  name <- match.arg(name)
  key_env <- if (name == "deepseek") "DEEPSEEK_API_KEY" else "XAI_API_KEY"
  if (!nzchar(trimws(Sys.getenv(key_env)))) stop("The selected provider needs ", key_env,
    " in this R process. Configure it through your secret mechanism, or explicitly use provider=NULL for manual/offline work. No call was made.", call. = FALSE)
  if (!is.character(model) || length(model) != 1L || is.na(model) || !nzchar(model))
    stop("Supply the verified model ID or set SC_MODEL_ID. No call was made.", call. = FALSE)
  required <- c("input_per_million", "output_per_million", "cached_input_per_million")
  if (!is.list(pricing) || is.null(names(pricing)) || !setequal(names(pricing), required) ||
      anyDuplicated(names(pricing)) || any(!vapply(pricing, function(value)
        is.numeric(value) && length(value) == 1L && is.finite(value) && value >= 0, logical(1))))
    stop("Supply verified current USD-per-million input, output and cached-input rates in pricing. No call was made.", call. = FALSE)
  list(name = name, model = model, api_key_env = key_env, external = TRUE,
       reservation_usd = reservation_usd, pricing = pricing, generation = generation)
}

.first_run_shared <- function() {
  helper <- new.env(parent = globalenv())
  for (name in c("qc-review.R", "server_first.R")) {
    path <- system.file("examples", name, package = "scAgentKit")
    if (!nzchar(path)) stop("Install this package's bundled offline examples.", call. = FALSE)
    source(path, local = helper)
  }
  helper
}

.first_run_mock_calls <- 0L
first_run_demo_chat <- function(system_prompt, user_prompt) {
  .first_run_mock_calls <<- .first_run_mock_calls + 1L
  .first_run_shared()$server_demo_chat(system_prompt, user_prompt)
}

.first_run_demo_check <- function(project_dir, current) {
  path <- file.path(project_dir, "first-use-synthetic-demo.rds")
  if (!file.exists(path)) stop("Scripted toy decisions apply only to the synthetic demo. For your data, source the helper and supply your reviewed R decision and reason.", call. = FALSE)
  demo <- readRDS(path)
  if (!identical(demo$project_id, current$project_id) || !identical(demo$input_hash, current$input_hash))
    stop("The demo manifest belongs to a different project/input.", call. = FALSE)
  demo
}

first_run_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("demo", "inspect", "revise-qc", "approve", "reject", "resume", "revise-annotation", "output")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: first-run.R PROJECT_DIR demo|inspect|revise-qc|approve|reject|resume|revise-annotation|output", call. = FALSE)
  project_dir <- args[[1L]]; mode <- args[[2L]]
  if (mode == "demo") {
    shared <- .first_run_shared(); input <- shared$make_qc_review_input()
    source_hash <- digest::digest(input, algo = "sha256")
    counts <- SeuratObject::LayerData(input, assay = "RNA", layer = "counts")
    demo <- list(cells = colnames(input), genes = rownames(counts), old_annotation = input$old_annotation,
      count_hashes = stats::setNames(vapply(seq_len(ncol(counts)), function(i)
        digest::digest(counts[, i, drop = FALSE], algo = "sha256"), character(1)), colnames(counts)))
    result <- first_run_start(input, project_dir, context = list(species = "human",
      tissue = "synthetic epithelial/stromal/endothelial mixture",
      columns = list(sample = "sample_id", capture = "capture_id", condition = "condition"),
      notes = "Entirely synthetic mechanism example with planted modules and six deliberately low-depth cells. Captures are not donors, condition is not batch, no reference supplied. Mock thresholds are not study recommendations."),
      provider = shared$server_demo_provider(), chat_fn = first_run_demo_chat, budget = 0,
      review = list(allow_external = FALSE), annotation_column = "first_use_identity",
      analysis = list(nfeatures = 200L, npcs = 12L, dims = 1:10, resolution = .3,
                      seed = 73031L, umap_neighbors = 20L))
    stopifnot(identical(source_hash, digest::digest(input, algo = "sha256")),
              result$status == "awaiting_review", result$pending$kind == "qc")
    demo$project_id <- result$project_id; demo$input_hash <- result$input_hash
    saveRDS(demo, file.path(project_dir, "first-use-synthetic-demo.rds"))
    cat("Synthetic demo only. Initial mock requests in this R process:", .first_run_mock_calls, "\n")
  } else if (mode == "inspect") result <- first_run_inspect(project_dir)
  else if (mode == "resume") {
    current <- sc_run_inspect(project_dir)
    if (file.exists(file.path(project_dir, "first-use-synthetic-demo.rds"))) {
      .first_run_demo_check(project_dir, current)
      result <- first_run_resume(project_dir, chat_fn = first_run_demo_chat)
      cat("Offline mock requests in this R process:", .first_run_mock_calls, "\n")
    } else result <- first_run_resume(project_dir)
  } else if (mode == "output") {
    result <- sc_run_inspect(project_dir)
    if (!identical(result$status, "complete")) stop("No current final output. Inspect, decide and explicitly resume first.", call. = FALSE)
    final <- readRDS(result$output$seurat)
    if (file.exists(file.path(project_dir, "first-use-synthetic-demo.rds"))) {
      demo <- .first_run_demo_check(project_dir, result)
      cells <- colnames(final); counts <- SeuratObject::LayerData(final, assay = "RNA", layer = "counts")
      stopifnot(identical(cells, demo$cells[demo$cells %in% cells]),
        identical(final$old_annotation, demo$old_annotation[match(cells, demo$cells)]),
        identical(rownames(counts), demo$genes),
        identical(unname(vapply(seq_len(ncol(counts)), function(i)
          digest::digest(counts[, i, drop = FALSE], algo = "sha256"), character(1))), unname(demo$count_hashes[cells])))
      print(table(final$first_use_identity)); cat("Exact retained IDs, original raw counts and old annotations preserved.\n")
    }
    cat("Final object:", result$output$seurat, "\n")
  } else {
    current <- sc_run_inspect(project_dir); .first_run_demo_check(project_dir, current)
    path <- file.path(project_dir, "first-use-reviewed-snapshot.rds")
    if (!file.exists(path)) stop("Run inspect and review its output before a demo decision.", call. = FALSE)
    snapshot <- readRDS(path)
    if (is.null(snapshot$review_node) || !snapshot$review_node$kind %in% c("qc", "annotation"))
      stop("Toy decisions cannot approve external transfer or configuration nodes.", call. = FALSE)
    if (mode == "revise-qc") {
      if (!identical(snapshot$review_node$kind, "qc")) stop("Inspect the pending QC snapshot first.", call. = FALSE)
      replacement <- snapshot$qc_preview$details$canonical_parameters$proposal
      replacement$filters[[1L]]$min <- 1L
      replacement$rationale <- "Explicit toy-only revision to the first supplied group's lower feature bound; inspect its changed exact retention before approving."
      result <- first_run_decide(project_dir, "revise", reason = "Demonstrate a deliberate toy QC correction; no general threshold recommendation.",
        reviewer = "synthetic-example-analyst", snapshot = snapshot, proposal = replacement)
      cat("Inspect the fresh QC preview before approving.\n")
    } else if (mode == "revise-annotation") {
      if (!identical(snapshot$review_node$kind, "annotation")) stop("Inspect the pending annotation snapshot first.", call. = FALSE)
      replacement <- first_run_unknown(snapshot,
        "Manual toy correction retains Unknown; marker evidence alone does not establish the biological identity.")
      result <- first_run_decide(project_dir, "revise", reason = "Record manual uncertainty after inspecting the offline mock and supplied marker evidence.",
        reviewer = "synthetic-example-analyst", snapshot = snapshot, proposal = replacement)
      cat("Inspect the fresh manual annotation proposal before approving.\n")
    } else result <- first_run_decide(project_dir, mode,
      reason = if (mode == "approve") "Reviewed this exact synthetic snapshot and limitations; approve this mechanism example."
        else "Reject this inspected synthetic proposal without executing it.",
      reviewer = "synthetic-example-analyst", snapshot = snapshot)
  }
  if (identical(result$status, "failed")) stop(result$failure$message, call. = FALSE)
  invisible(result)
}

if (sys.nframe() == 0L) first_run_main()
