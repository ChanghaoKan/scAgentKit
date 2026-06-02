#' LLM-driven cell type annotation with anti-hallucination structure
#'
#' For each cluster, assembles an evidence bundle (top markers, reference
#' matches, cluster size and proportion, tissue context) and asks an LLM
#' to annotate. The LLM is *forced* to return a strict JSON object
#' including a `contradicting_markers` field, which substantially reduces
#' hallucination: a model that must also list evidence *against* its own
#' choice is much less willing to confabulate.
#'
#' The function is LLM-provider-agnostic. The caller supplies a `chat_fn`
#' of signature `function(system_prompt, user_prompt) -> character` that
#' returns a raw JSON string. Any provider (OpenAI, Anthropic, DeepSeek,
#' Qwen, local Ollama, ...) can be plugged in; see details for example
#' wrappers.
#'
#' @section Building `chat_fn`:
#' A minimal `ellmer`-based wrapper:
#' \preformatted{
#'   chat_fn <- function(system_prompt, user_prompt) {
#'     chat <- ellmer::chat_openai(
#'       model = "gpt-4o-mini",
#'       system_prompt = system_prompt
#'     )
#'     chat$chat(user_prompt)
#'   }
#' }
#' A minimal `httr2`-based wrapper for a local vLLM / Ollama server is in
#' `inst/examples/llm_wrappers.R`.
#'
#' @param obj An AgentSeurat object after [annot_match_reference()].
#' @param chat_fn A function(system_prompt, user_prompt) that returns a
#'   character string containing a single JSON object matching the
#'   schema described in the system prompt.
#' @param tissue Character, the tissue / organ context (e.g. "mouse colon",
#'   "HCC tumor + adjacent", "PBMC"). Passed to the LLM as context.
#' @param condition Optional character describing the experimental condition
#'   (e.g. "Ca vs Ctrl"). Helps the model reason about expected populations.
#' @param expected_celltypes Optional character vector of cell types that
#'   should plausibly be present in this tissue. If supplied, the LLM is
#'   instructed to prefer these and to flag novel types. If NULL,
#'   `annot_llm_annotate()` will attempt to auto-detect a celltype column
#'   in the Seurat metadata and use those values as a *prior* (see
#'   `strict_vocabulary`).
#' @param strict_vocabulary Logical, default FALSE. When TRUE, the LLM is
#'   forced to match `expected_celltypes` *verbatim* (no sub-division, no
#'   renaming). Useful when you want output that aligns one-to-one with
#'   a published annotation. When FALSE (default), `expected_celltypes`
#'   acts as a prior -- the LLM is told to prefer these but may use other
#'   names if marker evidence warrants. **Changed in v0.1.24**: prior to
#'   v0.1.24, auto-detection of a celltype column silently engaged strict
#'   mode. This silently locked the LLM to the author's labels and could
#'   propagate annotation errors.
#' @param clusters Optional integer or character vector restricting which
#'   clusters to annotate (for iterative review). Default NULL = all.
#' @param max_retries Integer, JSON-parse retries on malformed output.
#'   Default 2.
#' @param n_samples Integer, number of independent LLM calls per cluster.
#'   Default 1 (no ensembling, backwards compatible). When > 1, the LLM
#'   is queried `n_samples` times per cluster and majority vote is taken
#'   on `primary_annotation`. Ensemble agreement is reported as
#'   `ensemble_agreement` (fraction of calls that agreed with the
#'   majority) and `ensemble_n` (number of valid calls). For the
#'   ensemble to be meaningful, build your chat_fn with
#'   `temperature > 0`; with `temperature = 0` all samples will be
#'   identical and the ensemble adds no information.
#' @param validate_markers Logical, default TRUE. When TRUE, the
#'   `supporting_markers` and `contradicting_markers` returned by the LLM
#'   are checked against the actual top-marker list. Any genes not in
#'   the evidence are flagged as `hallucinated_markers`. The hallucination
#'   rate also feeds into the hybrid confidence score.
#' @param parallel Logical, default `FALSE`. When `TRUE` and the
#'   `future.apply` package is installed, per-cluster annotation calls
#'   run in parallel under whatever execution `future::plan()` is
#'   active. For multi-core parallelism set the plan beforehand:
#'   \preformatted{future::plan(future::multisession, workers = 8)}
#'   Token usage from parallel workers is collected back into the
#'   parent's accumulator on completion. With `temperature = 0` and
#'   `n_samples = 1` parallel runs are reproducible across re-runs.
#' @param verbose Logical, print progress per cluster. Default TRUE.
#' @param rationale Optional LLM-supplied top-level rationale.
#'
#' @return Updated AgentSeurat. A data frame of annotations is stored at
#'   `obj@@params$llm_annotations` with columns: cluster,
#'   primary_annotation, confidence (LLM self-reported),
#'   hybrid_confidence (objective score; see Details),
#'   hybrid_confidence_label, confidence_disagreement,
#'   supporting_markers, contradicting_markers, hallucinated_markers,
#'   alternative_annotations, recommended_action, ensemble_agreement,
#'   ensemble_n, reasoning.
#'
#' @section Hybrid confidence:
#' The hybrid confidence score is a weighted combination of four
#' objective signals, each in [0, 1]:
#' \itemize{
#'   \item `ref_overlap` (weight 0.30): the cluster's best reference
#'     overlap score from `annot_match_reference`, capped at 1.
#'   \item `specificity` (weight 0.30): median `pct.1 - pct.2` of the
#'     cluster's top markers.
#'   \item `non_hallucination` (weight 0.20): fraction of the LLM's
#'     `supporting_markers` that actually appear in the cluster's
#'     top-marker list.
#'   \item `proportion_plausibility` (weight 0.20): 1 if the LLM
#'     reported `reasonable`, 0.5 for `suspicious`, 0 for `abnormal`
#'     or missing.
#' }
#' The resulting score is mapped to a label: `high` (>= 0.7),
#' `medium` (0.4-0.7), `low` (< 0.4). `confidence_disagreement` is
#' TRUE when the LLM's self-reported confidence and the hybrid label
#' fall in non-adjacent bands.
#' @export
annot_llm_annotate <- function(obj,
                               chat_fn,
                               tissue,
                               condition          = NULL,
                               expected_celltypes = NULL,
                               strict_vocabulary  = FALSE,
                               clusters           = NULL,
                               max_retries        = 2,
                               n_samples          = 1,
                               validate_markers   = TRUE,
                               parallel           = FALSE,
                               verbose            = TRUE,
                               rationale          = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (missing(chat_fn) || !is.function(chat_fn)) {
    stop("`chat_fn` must be a function(system_prompt, user_prompt) -> character.")
  }
  if (missing(tissue)) {
    stop("`tissue` is required (e.g. 'mouse colon', 'HCC tumor').")
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required for annot_llm_annotate.")
  }
  if (!is.numeric(n_samples) || n_samples < 1) {
    stop("`n_samples` must be a positive integer.")
  }
  n_samples <- as.integer(n_samples)
  if (n_samples > 1 && isTRUE(verbose)) {
    message(sprintf(
      "[annot_llm_annotate] ensemble mode: n_samples = %d. ",
      n_samples),
      "Make sure your chat_fn was built with temperature > 0; with temperature = 0 ",
      "all samples will be identical and the ensemble adds no information."
    )
  }

  filtered <- obj@params$markers_filtered
  matches  <- obj@params$reference_matches
  if (is.null(filtered)) {
    stop("No filtered markers; run sc_markers_summary() first.")
  }

  # v0.1.6 / v0.1.24: if expected_celltypes not supplied, try to auto-detect
  # from an existing author celltype column. The detected vocabulary is now
  # used as a *prior* (told to the LLM as "prefer these") rather than a
  # strict constraint. To recover the v0.1.6-v0.1.23 strict-match behaviour,
  # pass `strict_vocabulary = TRUE` explicitly.
  auto_detected_col <- NA_character_
  if (is.null(expected_celltypes)) {
    auto_detected_col <- .detect_celltype_col(obj@data@meta.data)
    if (!is.na(auto_detected_col)) {
      vals <- unique(as.character(obj@data@meta.data[[auto_detected_col]]))
      vals <- vals[!is.na(vals) & nzchar(vals)]
      if (length(vals) >= 2 && length(vals) <= 50) {
        expected_celltypes <- vals
        if (isTRUE(verbose)) {
          mode_msg <- if (isTRUE(strict_vocabulary)) {
            "(strict mode: LLM forced to match these exactly)"
          } else {
            "(prior only; LLM may refine -- pass strict_vocabulary=TRUE to force exact match)"
          }
          message(sprintf(
            "[annot_llm_annotate] auto-detected expected_celltypes from '%s' column %s: %s",
            auto_detected_col, mode_msg, paste(vals, collapse = ", ")
          ))
        }
      }
    }
  }

  all_clusters <- sort(unique(as.character(filtered$cluster)))
  if (!is.null(clusters)) {
    all_clusters <- intersect(all_clusters, as.character(clusters))
  }

  # Cluster proportions (global context)
  cell_meta <- obj@data@meta.data
  if (!"seurat_clusters" %in% colnames(cell_meta)) {
    stop("seurat_clusters not found in metadata.")
  }
  total_cells <- nrow(cell_meta)
  cluster_sizes <- table(as.character(cell_meta$seurat_clusters))
  cluster_pcts  <- 100 * as.numeric(cluster_sizes) / total_cells
  names(cluster_pcts) <- names(cluster_sizes)

  system_prompt <- .build_system_prompt(
    tissue, condition, expected_celltypes,
    strict_vocabulary = isTRUE(strict_vocabulary)
  )

  # Cycling-dominance map (from sc_markers_summary)
  cycling_map <- obj@params$cluster_cycling_score
  is_cycling <- if (!is.null(cycling_map)) {
    setNames(cycling_map$cycling_dominant, as.character(cycling_map$cluster))
  } else {
    setNames(logical(0), character(0))
  }

  # v0.1.12: for cycling clusters, the regular marker filter (which selects
  # by pct_diff vs other clusters) misses lineage markers like ALB / KRT18
  # that ARE highly expressed in the cluster but ALSO highly expressed in a
  # neighbouring same-lineage cluster (so the cluster-vs-rest comparison
  # gives low log2FC). We rescue those here by looking at high-expression
  # genes within the cluster, regardless of differential significance.
  cycling_rescue <- list()
  cycling_clusters <- names(is_cycling)[is_cycling]
  if (length(cycling_clusters) > 0) {
    if (isTRUE(verbose)) {
      message(sprintf("  [annotate] computing lineage rescue markers for %d cycling cluster(s): %s",
                      length(cycling_clusters),
                      paste(cycling_clusters, collapse = ", ")))
    }
    for (cid in cycling_clusters) {
      cycling_rescue[[cid]] <- .compute_lineage_rescue(obj@data, cid,
                                                       n_top = 30)
    }
  }

  # Per-cluster worker: builds the prompt, calls the LLM (single or
  # ensemble), validates marker citations, computes hybrid confidence.
  # Returns a list(parsed, token_records). The token_records are pulled
  # off the local .token_state at return time so the parent can merge
  # them even when this worker ran in a separate R process under
  # future_lapply.
  worker <- function(cid) {
    rec_before <- length(.token_state$records)

    user_prompt <- .build_user_prompt(
      cid, filtered, matches, cluster_sizes, cluster_pcts,
      is_cycling = isTRUE(is_cycling[as.character(cid)]),
      cycling_rescue = cycling_rescue[[as.character(cid)]]
    )

    if (verbose) {
      if (n_samples == 1) {
        message(sprintf("  [annotate] cluster %s ...", cid))
      } else {
        message(sprintf("  [annotate] cluster %s (n_samples=%d) ...",
                        cid, n_samples))
      }
    }

    parsed <- if (n_samples == 1) {
      out <- .call_with_retry(chat_fn, system_prompt, user_prompt,
                              max_retries = max_retries)
      out$ensemble_agreement <- 1.0
      out$ensemble_n          <- 1L
      out
    } else {
      .ensemble_annotate(chat_fn, system_prompt, user_prompt,
                         n_samples = n_samples,
                         max_retries = max_retries)
    }
    parsed$cluster <- cid

    if (isTRUE(validate_markers)) {
      cluster_top <- as.character(
        filtered$gene[as.character(filtered$cluster) == as.character(cid)]
      )
      val <- .validate_cited_markers(parsed, cluster_top)
      parsed$hallucinated_markers <- val$hallucinated
      parsed$hallucination_rate   <- val$rate
    } else {
      parsed$hallucinated_markers <- character(0)
      parsed$hallucination_rate   <- NA_real_
    }

    cluster_rows <- filtered[as.character(filtered$cluster) == as.character(cid),
                              , drop = FALSE]
    ref_rows <- if (!is.null(matches)) {
      matches[as.character(matches$cluster) == as.character(cid), ,
              drop = FALSE]
    } else NULL
    hc <- .compute_hybrid_confidence(
      parsed              = parsed,
      cluster_markers     = cluster_rows,
      reference_rows      = ref_rows
    )
    parsed$hybrid_confidence       <- hc$score
    parsed$hybrid_confidence_label <- hc$label
    parsed$confidence_disagreement <- hc$disagreement

    rec_after <- length(.token_state$records)
    local_records <- if (rec_after > rec_before) {
      .token_state$records[(rec_before + 1L):rec_after]
    } else list()

    list(parsed = parsed, token_records = local_records)
  }

  # Decide on execution strategy. Parallel mode requires future.apply.
  exec_strategy <- if (isTRUE(parallel) &&
                       requireNamespace("future.apply", quietly = TRUE)) {
    "parallel"
  } else {
    if (isTRUE(parallel)) {
      message(
        "[annot_llm_annotate] `parallel = TRUE` requested but ",
        "'future.apply' is not installed; falling back to sequential. ",
        "Install with install.packages('future.apply') and set ",
        "`future::plan(future::multisession, workers = N)` to enable."
      )
    }
    "sequential"
  }

  results <- if (exec_strategy == "parallel") {
    future.apply::future_lapply(all_clusters, worker, future.seed = TRUE)
  } else {
    lapply(all_clusters, worker)
  }
  names(results) <- as.character(all_clusters)

  annotations <- lapply(results, `[[`, "parsed")

  # Merge parallel-worker token records back into the global accumulator
  # and capture this step's local token summary for AgentSeurat@token_usage.
  step_records <- unlist(lapply(results, `[[`, "token_records"),
                         recursive = FALSE)
  if (exec_strategy == "parallel" && length(step_records) > 0) {
    # In parallel mode workers' .token_state was isolated; backfill
    # records into the parent process so token_usage_summary() sees them.
    .token_state$records <- c(.token_state$records, step_records)
  }
  token_summary <- .token_records_summarise(step_records)

  # Collapse into a data frame
  ann_df <- .annotations_to_df(annotations)

  # Build the script snippet (records configuration, not the LLM output)
  script <- sprintf(
'# ---- LLM annotation (tissue = %s%s; n_samples = %d; strict_vocabulary = %s) ----
# LLM reconciliation: for each cluster, marker list + reference candidates
# are sent to an LLM which returns a strict JSON with:
#   primary_annotation, confidence, supporting_markers,
#   contradicting_markers, alternative_annotations, reasoning.
# Per-cluster JSON output is stored in obj@params$llm_annotations,
# augmented with hybrid_confidence (objective), hallucinated_markers,
# ensemble_agreement.
# (Reproducibility caveat: LLM calls are non-deterministic; set the
#  seed/temperature on the provider side to improve reproducibility.)',
    tissue,
    if (is.null(condition)) "" else sprintf(", condition = %s", condition),
    n_samples,
    as.character(isTRUE(strict_vocabulary))
  )

  if (is.null(rationale)) {
    n_disagree <- sum(ann_df$confidence_disagreement, na.rm = TRUE)
    n_halluc   <- sum(nzchar(ann_df$hallucinated_markers), na.rm = TRUE)
    rationale <- sprintf(
      paste0(
        "LLM-annotated %d clusters in tissue context '%s' (n_samples=%d). ",
        "Anti-hallucination: contradicting_markers required; marker citations ",
        "validated against input list (%d clusters had hallucinated markers); ",
        "hybrid confidence cross-checked against LLM self-report ",
        "(%d clusters in disagreement)."
      ),
      length(all_clusters), tissue, n_samples, n_halluc, n_disagree
    )
  }

  obj <- .record_step(
    obj            = obj,
    step_name      = "annot_llm_annotate",
    function_name  = "annot_llm_annotate",
    params         = list(
      tissue              = tissue,
      condition           = condition,
      expected_celltypes  = expected_celltypes,
      strict_vocabulary   = isTRUE(strict_vocabulary),
      n_samples           = n_samples,
      validate_markers    = isTRUE(validate_markers),
      parallel            = isTRUE(parallel),
      n_clusters          = length(all_clusters),
      clusters_annotated  = all_clusters
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "llm_annotated"
  )
  obj@params$llm_annotations <- ann_df
  obj@token_usage$annot_llm_annotate <- token_summary
  obj
}

# ---- Internal helpers ------------------------------------------------------

# Construct the system prompt with the strict JSON schema.
.build_system_prompt <- function(tissue, condition, expected_celltypes,
                                 strict_vocabulary = FALSE) {

  expected_line <- if (is.null(expected_celltypes)) {
    "No prior cell type list supplied; use your knowledge of the tissue."
  } else if (isTRUE(strict_vocabulary)) {
    # Auto-detected from author's metadata column. Use the exact strings.
    sprintf(
      paste0(
        "VOCABULARY (strict): the dataset author already used these exact ",
        "cell-type strings: %s. Use the SAME strings verbatim -- do NOT ",
        "subdivide (e.g. don't split T/NK into T cell + NK cell), do NOT ",
        "rename (e.g. don't return 'Macrophage' if the author uses 'Myeloid'). ",
        "Pick the closest match from this list."
      ),
      paste(sprintf('"%s"', expected_celltypes), collapse = ", ")
    )
  } else {
    sprintf(
      "Expected cell types in this tissue (prefer these; flag unfamiliar ones): %s.",
      paste(expected_celltypes, collapse = ", ")
    )
  }

  condition_line <- if (is.null(condition)) "" else sprintf(
    "Experimental condition: %s.\n", condition
  )

  # NOTE: the contradicting_markers field is deliberate. Requiring the
  # model to produce counter-evidence forces it to hedge instead of
  # hallucinate with false confidence.
  paste0(
    "You are a single-cell RNA-seq cell type annotation expert.\n",
    sprintf("Tissue context: %s.\n", tissue),
    condition_line,
    expected_line, "\n\n",
    "For each cluster, you will receive:\n",
    "  - Top marker genes ranked by specificity (pct.1 - pct.2)\n",
    "  - Candidate cell types from a reference database with overlap scores\n",
    "  - Cluster size and percentage of the dataset\n\n",
    "Return ONE JSON object with this exact shape. Do not include markdown\n",
    "fences, comments, or any text outside the JSON.\n\n",
    "{\n",
    '  "primary_annotation": "<cell type name>",\n',
    '  "confidence": "<high|medium|low>",\n',
    '  "supporting_markers": ["gene1","gene2", ...],\n',
    '  "contradicting_markers": ["gene1","gene2", ...],\n',
    '  "alternative_annotations": ["<alt1>","<alt2>"],\n',
    '  "proportion_assessment": "<reasonable|suspicious|abnormal>",\n',
    '  "recommended_action": "<accept|flag_for_review|reject|mark_unknown>",\n',
    '  "reasoning": "<1-3 sentences; cite markers explicitly>"\n',
    "}\n\n",
    "Rules:\n",
    "1. If top markers do not clearly support any single cell type, set\n",
    "   primary_annotation to \"Unknown\" and confidence to \"low\".\n",
    "2. contradicting_markers MUST list any markers in the top list that are\n",
    "   inconsistent with your primary_annotation. If truly none, return\n",
    "   an empty list, not a fabricated match.\n",
    "3. If markers suggest a doublet / mixed population (markers of two\n",
    "   distinct lineages at comparable strength), set recommended_action\n",
    "   to \"flag_for_review\".\n",
    "4. If markers suggest stressed cells (high mt / heat shock / ribosomal\n",
    "   dominance) or tissue contamination, set recommended_action to\n",
    "   \"flag_for_review\" or \"reject\".\n",
    "5. proportion_assessment: comment on whether the cluster's % of the\n",
    "   dataset is biologically plausible for the assigned cell type in the\n",
    "   given tissue. Major lineages in tumor samples are typically 5-40%,\n",
    "   rare populations <2%; evaluate accordingly.\n"
  )
}

# Construct the per-cluster user prompt.
.build_user_prompt <- function(cid, filtered, matches,
                               cluster_sizes, cluster_pcts,
                               is_cycling = FALSE,
                               cycling_rescue = NULL) {

  cluster_rows <- filtered[as.character(filtered$cluster) == cid, , drop = FALSE]
  cluster_genes <- cluster_rows$gene

  # Reference candidates for this cluster
  ref_rows <- if (!is.null(matches)) {
    matches[as.character(matches$cluster) == cid, , drop = FALSE]
  } else NULL
  ref_block <- if (is.null(ref_rows) || nrow(ref_rows) == 0) {
    "  (no reference candidates)"
  } else {
    paste(sprintf("  - %s (overlap=%d/%d, score=%.2f; markers: %s)",
                  ref_rows$cell_type, ref_rows$overlap_count,
                  ref_rows$celltype_size, ref_rows$score,
                  ref_rows$matched_markers),
          collapse = "\n")
  }

  size <- cluster_sizes[[as.character(cid)]]
  pct  <- cluster_pcts[[as.character(cid)]]

  # v0.1.12: cycling cluster handling.
  # Two improvements over v0.1.11:
  #   (1) Render the rescue markers list (genes highly expressed in the
  #       cluster, EXCLUDING cell-cycle genes) so LLM can see lineage
  #       signal that the differential filter missed.
  #   (2) Force structured naming: "Cycling cells (lineage candidate: X)"
  #       or "Cycling cells (lineage uncertain)". NEVER allow "Unknown".
  rescue_block <- ""
  if (!is.null(cycling_rescue) && nrow(cycling_rescue) > 0) {
    top <- head(cycling_rescue, 30)
    lines <- sprintf("  %s (pct.exp=%.0f%%, mean=%.2f)",
                     top$gene, 100 * top$pct_exp, top$mean_exp)
    rescue_block <- paste0(
      "\n\nLineage rescue list (top ", nrow(top), " non-cell-cycle, ",
      "non-housekeeping genes ranked by within-cluster expression dominance ",
      "(pct.exp * mean.exp); these may be DIAGNOSTIC of lineage even if ",
      "they did NOT pass the differential filter, because they may also ",
      "be expressed in adjacent same-lineage clusters):\n",
      paste(lines, collapse = "\n")
    )
  } else if (isTRUE(is_cycling)) {
    rescue_block <- "\n\nLineage rescue list: (no qualifying non-CC, non-housekeeping genes; cluster may genuinely lack lineage signal)\n"
  }

  cycling_note <- if (isTRUE(is_cycling)) {
    paste0(
      "\nIMPORTANT -- this cluster is CYCLING-DOMINANT. Its top markers ",
      "(by differential expression) are mostly cell-cycle genes (MKI67, ",
      "TOP2A, UBE2C, KIAA0101, BIRC5, CDK1, etc.). Cell-cycle markers are ",
      "STATE, not LINEAGE. Decision protocol for cycling clusters:\n",
      "  STEP 1 -- Look at the LINEAGE RESCUE LIST above first. It contains ",
      "  the cluster's most-expressed non-CC genes. Lineage-specific ",
      "  markers there (ALB/KRT18=hepatocyte, CD3D=T cell, CD68=myeloid, ",
      "  CD79A=B cell, etc.) tell you the lineage even though differential ",
      "  filtering missed them.\n",
      "  STEP 2 -- Cross-check with reference database candidates above.\n",
      "  STEP 3 -- Choose ONE of these structured names ",
      "(MANDATORY format -- do NOT use plain lineage names for cycling ",
      "clusters, do NOT use 'Unknown'):\n",
      "      A. 'Cycling cells (lineage candidate: <X>)'  ",
      "if rescue list shows clear lineage markers for <X>. Use confidence='medium' or 'high' depending on signal strength.\n",
      "      B. 'Cycling cells (lineage uncertain)'  ",
      "ONLY if neither rescue list nor reference candidates give a usable lineage signal. Use confidence='low'.\n",
      "  In the reasoning field, name the specific rescue-list genes that ",
      "drove your lineage assignment (e.g. 'rescue list shows ALB/KRT18/",
      "APOA1 -> hepatocyte lineage despite cycling-dominant differential ",
      "markers').\n"
    )
  } else ""

  paste0(
    sprintf("Cluster %s\n", cid),
    sprintf("Size: %d cells (%.2f%% of dataset)\n", size, pct),
    sprintf("Top %d differential markers (ranked by pct.1 - pct.2):\n  %s\n",
            length(cluster_genes), paste(cluster_genes, collapse = ", ")),
    "Reference database candidates:\n", ref_block, "\n",
    rescue_block,
    cycling_note,
    "\nReturn the JSON object now."
  )
}

# Call chat_fn with JSON-parse retry. Returns a named list (parsed JSON).
.call_with_retry <- function(chat_fn, system_prompt, user_prompt, max_retries,
                             image_path = NULL) {
  last_err <- NULL
  for (i in seq_len(max_retries + 1)) {
    raw <- tryCatch(
      chat_fn(system_prompt, user_prompt, image_path = image_path),
      error = function(e) { last_err <<- e; NULL }
    )
    if (is.null(raw)) next

    # Strip markdown fences if any (defensive)
    raw <- sub("^```(?:json)?\\s*", "", raw)
    raw <- sub("\\s*```\\s*$", "", raw)
    raw <- trimws(raw)

    parsed <- tryCatch(
      jsonlite::fromJSON(raw, simplifyVector = TRUE),
      error = function(e) { last_err <<- e; NULL }
    )
    if (!is.null(parsed)) return(parsed)

    if (i <= max_retries) {
      user_prompt <- paste0(
        user_prompt,
        "\n\nYour previous response could not be parsed as JSON. ",
        "Return ONLY the JSON object, no prose, no fences."
      )
    }
  }
  # Return a structured failure row rather than crashing the batch
  list(
    primary_annotation      = NA_character_,
    confidence              = "low",
    supporting_markers      = character(0),
    contradicting_markers   = character(0),
    alternative_annotations = character(0),
    proportion_assessment   = NA_character_,
    recommended_action      = "flag_for_review",
    reasoning               = sprintf("LLM call failed: %s",
                                      if (is.null(last_err)) "unknown" else conditionMessage(last_err))
  )
}

# Collapse a list of per-cluster annotations into a data frame.
# Character-vector fields are collapsed with ";" for tabular storage.
.annotations_to_df <- function(annotations) {
  collapse <- function(x) {
    if (is.null(x)) return(NA_character_)
    if (length(x) == 0) return("")
    paste(as.character(x), collapse = ";")
  }
  rows <- lapply(annotations, function(a) {
    data.frame(
      cluster                 = a$cluster,
      primary_annotation      = as.character(a$primary_annotation %||% NA),
      confidence              = as.character(a$confidence %||% NA),
      hybrid_confidence       = as.numeric(a$hybrid_confidence %||% NA),
      hybrid_confidence_label = as.character(a$hybrid_confidence_label %||% NA),
      confidence_disagreement = as.logical(a$confidence_disagreement %||% NA),
      supporting_markers      = collapse(a$supporting_markers),
      contradicting_markers   = collapse(a$contradicting_markers),
      hallucinated_markers    = collapse(a$hallucinated_markers),
      hallucination_rate      = as.numeric(a$hallucination_rate %||% NA),
      alternative_annotations = collapse(a$alternative_annotations),
      proportion_assessment   = as.character(a$proportion_assessment %||% NA),
      recommended_action      = as.character(a$recommended_action %||% NA),
      ensemble_n              = as.integer(a$ensemble_n %||% NA),
      ensemble_agreement      = as.numeric(a$ensemble_agreement %||% NA),
      reasoning               = as.character(a$reasoning %||% NA),
      stringsAsFactors        = FALSE
    )
  })
  do.call(rbind, rows)
}

# Null-coalescing operator (used above).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a


# ---- v0.1.24 helpers: marker validation, hybrid confidence, ensemble ----

# Validate that the LLM's cited supporting / contradicting markers come from
# the actual input list. Anything outside is flagged as hallucinated.
# Matching is case-insensitive (genes appear in mixed case across organisms).
#
# Returns a list:
#   hallucinated : character vector of cited genes not in input
#   rate         : hallucination rate over supporting_markers (NA if empty)
.validate_cited_markers <- function(parsed, cluster_top_genes) {
  cited_support     <- as.character(parsed$supporting_markers    %||% character(0))
  cited_contradict  <- as.character(parsed$contradicting_markers %||% character(0))
  all_cited         <- unique(c(cited_support, cited_contradict))

  if (length(cluster_top_genes) == 0 || length(all_cited) == 0) {
    return(list(hallucinated = character(0), rate = NA_real_))
  }

  input_upper  <- toupper(trimws(cluster_top_genes))
  cited_upper  <- toupper(trimws(all_cited))
  is_halluc    <- !(cited_upper %in% input_upper)
  hallucinated <- all_cited[is_halluc]

  # Rate is over supporting_markers (the affirmative claims that matter
  # most). Contradicting hallucinations are still recorded but not
  # counted in the rate.
  rate <- if (length(cited_support) == 0) {
    NA_real_
  } else {
    sup_upper <- toupper(trimws(cited_support))
    mean(!(sup_upper %in% input_upper))
  }

  list(hallucinated = hallucinated, rate = rate)
}


# Compute a hybrid confidence score from objective signals.
#
# Inputs:
#   parsed          : per-cluster parsed LLM JSON (with hallucination_rate
#                     already attached)
#   cluster_markers : rows of obj@params$markers_filtered for this cluster
#                     (must contain pct.1, pct.2)
#   reference_rows  : rows of obj@params$reference_matches for this cluster
#                     (may be NULL); must contain `score` column
#
# Returns list(score, label, disagreement):
#   score        : numeric in [0, 1]
#   label        : "high" (>=0.7), "medium" (0.4-0.7), "low" (<0.4)
#   disagreement : TRUE when LLM-reported label and hybrid label fall in
#                  non-adjacent bands (high<->low)
.compute_hybrid_confidence <- function(parsed,
                                       cluster_markers,
                                       reference_rows) {
  # Signal 1: best reference overlap score for this cluster (cap at 1).
  ref_overlap <- if (!is.null(reference_rows) && nrow(reference_rows) > 0) {
    max(0, min(1, suppressWarnings(max(as.numeric(reference_rows$score),
                                        na.rm = TRUE))))
  } else 0

  # Signal 2: marker specificity = median pct.1 - pct.2 of cluster's top
  # markers. Already in [-1, 1] but in practice mostly [0, 1] after the
  # log2FC > 1 filter in sc_markers_summary.
  specificity <- if (!is.null(cluster_markers) && nrow(cluster_markers) > 0) {
    pct_diff <- as.numeric(cluster_markers$pct.1) -
                as.numeric(cluster_markers$pct.2)
    pct_diff <- pct_diff[is.finite(pct_diff)]
    if (length(pct_diff) == 0) 0
    else max(0, min(1, stats::median(pct_diff, na.rm = TRUE)))
  } else 0

  # Signal 3: non-hallucination rate.
  halluc_rate <- as.numeric(parsed$hallucination_rate %||% NA)
  non_halluc <- if (is.na(halluc_rate)) 0.5 else 1 - halluc_rate

  # Signal 4: proportion plausibility from the LLM's own assessment.
  # Used as a secondary signal -- the LLM tends to flag obvious mismatches.
  prop_str <- tolower(as.character(parsed$proportion_assessment %||% ""))
  proportion <- if (prop_str == "reasonable") 1
                else if (prop_str == "suspicious") 0.5
                else if (prop_str == "abnormal") 0
                else 0.5  # missing / unknown

  score <- 0.30 * ref_overlap +
           0.30 * specificity +
           0.20 * non_halluc +
           0.20 * proportion
  score <- max(0, min(1, score))

  label <- if (score >= 0.7) "high"
           else if (score >= 0.4) "medium"
           else "low"

  llm_label <- tolower(as.character(parsed$confidence %||% ""))
  disagreement <- if (llm_label %in% c("high", "low") &&
                       label %in% c("high", "low")) {
    llm_label != label   # only flag opposite bands; high vs medium OK
  } else FALSE

  list(score = round(score, 3), label = label,
       disagreement = disagreement)
}


# Run n_samples independent LLM calls per cluster, take majority vote
# on primary_annotation (case-insensitive), and aggregate evidence
# fields from the modal response.
#
# For aggregation:
#   primary_annotation        : modal label across samples
#   confidence                : modal response's confidence
#   supporting_markers        : union across all majority samples
#   contradicting_markers     : union across all majority samples
#   alternative_annotations   : union across all samples
#   proportion_assessment     : modal response's value
#   recommended_action        : worst-case (flag/reject > accept) across samples
#   reasoning                 : modal response's reasoning, prefixed with
#                               ensemble note
#   ensemble_agreement        : fraction of samples that matched majority
#   ensemble_n                : number of valid samples
.ensemble_annotate <- function(chat_fn, system_prompt, user_prompt,
                                n_samples, max_retries) {

  samples <- vector("list", n_samples)
  for (i in seq_len(n_samples)) {
    samples[[i]] <- .call_with_retry(
      chat_fn, system_prompt, user_prompt,
      max_retries = max_retries
    )
  }
  # Drop fully-failed calls (NA primary_annotation)
  valid_idx <- vapply(samples, function(s) {
    !is.null(s$primary_annotation) &&
      !is.na(s$primary_annotation) &&
      nzchar(as.character(s$primary_annotation))
  }, logical(1))
  if (!any(valid_idx)) {
    # All failed: return one failure record
    fail <- samples[[1]]
    fail$ensemble_agreement <- 0
    fail$ensemble_n          <- 0L
    return(fail)
  }
  valid <- samples[valid_idx]
  labels <- vapply(valid, function(s) {
    tolower(trimws(as.character(s$primary_annotation)))
  }, character(1))

  tab <- table(labels)
  top_label <- names(tab)[which.max(tab)]
  agreement <- as.numeric(tab[top_label]) / length(labels)
  modal_idx <- which(labels == top_label)
  modal     <- valid[[modal_idx[1]]]   # representative response

  # Worst-case action escalation
  actions <- vapply(valid, function(s) {
    tolower(as.character(s$recommended_action %||% "accept"))
  }, character(1))
  action_priority <- c("reject" = 4, "flag_for_review" = 3,
                       "mark_unknown" = 2, "accept" = 1)
  ranked <- action_priority[actions]
  ranked[is.na(ranked)] <- 1
  worst_action <- names(action_priority)[match(max(ranked), action_priority)]

  union_chars <- function(field) {
    vals <- unlist(lapply(valid[modal_idx], function(s) {
      as.character(s[[field]] %||% character(0))
    }))
    unique(vals[nzchar(vals)])
  }
  union_alts <- unique(unlist(lapply(valid, function(s) {
    as.character(s$alternative_annotations %||% character(0))
  })))
  union_alts <- union_alts[nzchar(union_alts)]

  out <- list(
    primary_annotation      = as.character(modal$primary_annotation),
    confidence              = as.character(modal$confidence %||% NA),
    supporting_markers      = union_chars("supporting_markers"),
    contradicting_markers   = union_chars("contradicting_markers"),
    alternative_annotations = union_alts,
    proportion_assessment   = as.character(modal$proportion_assessment %||% NA),
    recommended_action      = worst_action,
    reasoning               = sprintf(
      "[ensemble %d/%d agreed on '%s'] %s",
      sum(labels == top_label), length(labels),
      modal$primary_annotation,
      as.character(modal$reasoning %||% "")
    ),
    ensemble_agreement      = round(agreement, 3),
    ensemble_n              = length(valid)
  )
  # If disagreement is high, push action toward flag_for_review
  if (agreement < 0.6 && out$recommended_action == "accept") {
    out$recommended_action <- "flag_for_review"
    out$reasoning <- paste0(out$reasoning,
                            " (ensemble disagreement < 60%: escalated to flag_for_review.)")
  }
  out
}

# Compute "lineage rescue" markers for a cycling-dominant cluster.
# Why: in a cycling cluster, the top markers ranked by pct_diff are almost
# entirely cell-cycle genes -- because those genes really do separate the
# cluster from its neighbours. But the cluster's actual lineage markers
# (ALB / KRT18 for hepatocytes, CD3D for T cells, ...) are also present
# at high expression -- they're just *also* highly expressed in adjacent
# same-lineage clusters, so cluster-vs-rest log2FC isn't significant.
#
# This helper returns the top genes (excluding cell-cycle genes) ranked
# by within-cluster expression rate (pct.exp) and mean expression. It
# tells the LLM "here's what this cluster *expresses*, not just what's
# *different* about it".
.compute_lineage_rescue <- function(seu, cid, n_top = 30,
                                    min_pct = 0.30) {
  cells <- colnames(seu)[as.character(seu$seurat_clusters) == as.character(cid)]
  if (length(cells) < 5) return(NULL)

  # Get expression matrix for this cluster
  data_layer <- tryCatch(
    Seurat::GetAssayData(seu, assay = "RNA", layer = "data"),
    error = function(e) Seurat::GetAssayData(seu, assay = "RNA", slot = "data")
  )
  cluster_mat <- data_layer[, cells, drop = FALSE]

  # Per-gene: % cells expressing, mean expression
  pct_expr  <- Matrix::rowMeans(cluster_mat > 0)
  mean_expr <- Matrix::rowMeans(cluster_mat)

  # Filter: must be above min_pct AND not a cell cycle gene
  cc_genes <- .cell_cycle_marker_set()
  keep <- pct_expr >= min_pct & !(toupper(names(pct_expr)) %in% cc_genes)
  if (sum(keep) == 0) return(NULL)

  # Also drop housekeeping-like ubiquitous genes that don't help with lineage
  # (these light up in every cluster).
  ubiq_pattern <- "^(MT-|MTRNR|RPS|RPL|MALAT1$|XIST$|NEAT1$|EEF1|ACTB$|GAPDH$|B2M$)"
  is_ubiq <- grepl(ubiq_pattern, names(pct_expr))
  keep <- keep & !is_ubiq

  scored <- data.frame(
    gene     = names(pct_expr)[keep],
    pct_exp  = round(pct_expr[keep], 3),
    mean_exp = round(mean_expr[keep], 3),
    stringsAsFactors = FALSE
  )

  # Rank by mean_exp * pct_exp (a simple "expression dominance" score).
  scored$score <- scored$mean_exp * scored$pct_exp
  scored <- scored[order(-scored$score), ]
  head(scored, n_top)
}
