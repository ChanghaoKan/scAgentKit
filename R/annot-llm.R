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
#'   instructed to prefer these and to flag novel types.
#' @param clusters Optional integer or character vector restricting which
#'   clusters to annotate (for iterative review). Default NULL = all.
#' @param max_retries Integer, JSON-parse retries on malformed output.
#'   Default 2.
#' @param verbose Logical, print progress per cluster. Default TRUE.
#' @param rationale Optional LLM-supplied top-level rationale.
#'
#' @return Updated AgentSeurat. A data frame of annotations is stored at
#'   `obj@@params$llm_annotations` with columns: cluster,
#'   primary_annotation, confidence, supporting_markers,
#'   contradicting_markers, alternative_annotations,
#'   recommended_action, reasoning.
#' @export
annot_llm_annotate <- function(obj,
                               chat_fn,
                               tissue,
                               condition          = NULL,
                               expected_celltypes = NULL,
                               clusters           = NULL,
                               max_retries        = 2,
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

  filtered <- obj@params$markers_filtered
  matches  <- obj@params$reference_matches
  if (is.null(filtered)) {
    stop("No filtered markers; run sc_markers_summary() first.")
  }

  # v0.1.6: if expected_celltypes not supplied, try to auto-detect from
  # an existing author celltype column (e.g. GSE149614 ships with a
  # `celltype` column). Using the author's exact vocabulary makes
  # downstream confusion matrix interpretable without manual mapping.
  auto_detected_col <- NA_character_
  if (is.null(expected_celltypes)) {
    auto_detected_col <- .detect_celltype_col(obj@data@meta.data)
    if (!is.na(auto_detected_col)) {
      vals <- unique(as.character(obj@data@meta.data[[auto_detected_col]]))
      vals <- vals[!is.na(vals) & nzchar(vals)]
      if (length(vals) >= 2 && length(vals) <= 50) {
        expected_celltypes <- vals
        if (isTRUE(verbose)) {
          message(sprintf(
            "[annot_llm_annotate] auto-detected expected_celltypes from '%s' column: %s",
            auto_detected_col, paste(vals, collapse = ", ")
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
    strict_vocabulary = !is.na(auto_detected_col)
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

  annotations <- list()
  for (cid in all_clusters) {
    user_prompt <- .build_user_prompt(
      cid, filtered, matches, cluster_sizes, cluster_pcts,
      is_cycling = isTRUE(is_cycling[as.character(cid)]),
      cycling_rescue = cycling_rescue[[as.character(cid)]]
    )

    if (verbose) message(sprintf("  [annotate] cluster %s ...", cid))

    parsed <- .call_with_retry(chat_fn, system_prompt, user_prompt,
                               max_retries = max_retries)
    parsed$cluster <- cid
    annotations[[cid]] <- parsed
  }

  # Collapse into a data frame
  ann_df <- .annotations_to_df(annotations)

  # Build the script snippet (records configuration, not the LLM output)
  script <- sprintf(
'# ---- LLM annotation (tissue = %s%s) ----
# LLM reconciliation: for each cluster, marker list + reference candidates
# are sent to an LLM which returns a strict JSON with:
#   primary_annotation, confidence, supporting_markers,
#   contradicting_markers, alternative_annotations, reasoning.
# Per-cluster JSON output is stored in obj@params$llm_annotations.
# (Reproducibility caveat: LLM calls are non-deterministic; set the
#  seed/temperature on the provider side to improve reproducibility.)',
    tissue,
    if (is.null(condition)) "" else sprintf(", condition = %s", condition)
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "LLM-annotated %d clusters in tissue context '%s'. Strict JSON schema with contradicting_markers field for anti-hallucination.",
      length(all_clusters), tissue
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
      n_clusters          = length(all_clusters),
      clusters_annotated  = all_clusters
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "llm_annotated"
  )
  obj@params$llm_annotations <- ann_df
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
        "cell-type strings: %s. Use the SAME strings verbatim — do NOT ",
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
      "\nIMPORTANT — this cluster is CYCLING-DOMINANT. Its top markers ",
      "(by differential expression) are mostly cell-cycle genes (MKI67, ",
      "TOP2A, UBE2C, KIAA0101, BIRC5, CDK1, etc.). Cell-cycle markers are ",
      "STATE, not LINEAGE. Decision protocol for cycling clusters:\n",
      "  STEP 1 — Look at the LINEAGE RESCUE LIST above first. It contains ",
      "  the cluster's most-expressed non-CC genes. Lineage-specific ",
      "  markers there (ALB/KRT18=hepatocyte, CD3D=T cell, CD68=myeloid, ",
      "  CD79A=B cell, etc.) tell you the lineage even though differential ",
      "  filtering missed them.\n",
      "  STEP 2 — Cross-check with reference database candidates above.\n",
      "  STEP 3 — Choose ONE of these structured names ",
      "(MANDATORY format — do NOT use plain lineage names for cycling ",
      "clusters, do NOT use 'Unknown'):\n",
      "      A. 'Cycling cells (lineage candidate: <X>)'  ",
      "if rescue list shows clear lineage markers for <X>. Use confidence='medium' or 'high' depending on signal strength.\n",
      "      B. 'Cycling cells (lineage uncertain)'  ",
      "ONLY if neither rescue list nor reference candidates give a usable lineage signal. Use confidence='low'.\n",
      "  In the reasoning field, name the specific rescue-list genes that ",
      "drove your lineage assignment (e.g. 'rescue list shows ALB/KRT18/",
      "APOA1 → hepatocyte lineage despite cycling-dominant differential ",
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
      supporting_markers      = collapse(a$supporting_markers),
      contradicting_markers   = collapse(a$contradicting_markers),
      alternative_annotations = collapse(a$alternative_annotations),
      proportion_assessment   = as.character(a$proportion_assessment %||% NA),
      recommended_action      = as.character(a$recommended_action %||% NA),
      reasoning               = as.character(a$reasoning %||% NA),
      stringsAsFactors        = FALSE
    )
  })
  do.call(rbind, rows)
}

# Null-coalescing operator (used above).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Compute "lineage rescue" markers for a cycling-dominant cluster.
# Why: in a cycling cluster, the top markers ranked by pct_diff are almost
# entirely cell-cycle genes — because those genes really do separate the
# cluster from its neighbours. But the cluster's actual lineage markers
# (ALB / KRT18 for hepatocytes, CD3D for T cells, ...) are also present
# at high expression — they're just *also* highly expressed in adjacent
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
