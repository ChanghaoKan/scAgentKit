#' LLM-assisted clustering resolution recommendation (vision-capable)
#'
#' After [sc_cluster_sweep()] has populated `RNA_snn_res.*` metadata and
#' saved a clustree plot, this function computes objective stability
#' metrics, packages them into a compact evidence bundle, and asks a
#' vision-capable LLM to recommend a resolution while looking at the
#' clustree image.
#'
#' The LLM receives:
#' \itemize{
#'   \item cluster count at every resolution
#'   \item stability (Adjusted Rand Index) between adjacent resolutions
#'   \item number of "small" clusters (< `small_cluster_pct` of cells)
#'     at every resolution -- a proxy for over-clustering
#'   \item the clustree PNG (when `vision = TRUE`) -- showing how clusters
#'     split and merge as resolution increases
#'   \item tissue context and (optionally) expected cell-type count
#' }
#' and must return a strict JSON naming the chosen resolution, confidence,
#' alternatives, and reasoning that explicitly references both the data
#' table and the clustree structure.
#'
#' Vision adds signal that pure numbers miss: resolution plateaus where
#' clusters are stable for several steps, "branching cascades" that
#' indicate a cluster fragmenting into dust, and the overall shape of the
#' tree. If your `chat_fn` does not support images, pass `vision = FALSE`
#' to fall back to numeric-only mode.
#'
#' The function does NOT commit to a resolution. Call [sc_cluster()]
#' afterwards with the recommended (or overridden) value.
#'
#' @section The `chat_fn` contract:
#' For vision mode the callable must accept an `image_path` argument:
#' \preformatted{
#'   chat_fn <- function(system_prompt, user_prompt, image_path = NULL) {
#'     # If image_path is NULL, text-only call.
#'     # If image_path is a character path, attach the image to the message.
#'     # Returns a character string (the JSON reply).
#'   }
#' }
#' All wrappers in `inst/examples/llm_wrappers.R` honour this contract.
#'
#' @param obj An AgentSeurat object after [sc_cluster_sweep()].
#' @param chat_fn A function(system_prompt, user_prompt, image_path) -> character.
#' @param tissue Character, tissue context (e.g. "mouse colon (Ca vs Ctrl)").
#' @param expected_n_celltypes Optional integer or length-2 integer vector.
#' @param small_cluster_pct Numeric. Default 0.005.
#' @param vision Logical. Default TRUE; if FALSE, sends numbers only.
#' @param image_path Optional path to an image for the LLM. If NULL and
#'   `vision = TRUE`, the function auto-picks the most recent
#'   `sc_cluster_sweep` figure from `@figures`.
#' @param max_retries Integer. Default 2.
#'
#' @return Updated AgentSeurat. Recommendation stored at
#'   `obj@params$resolution_recommendation`.
#' @param vision_panels Character vector of panel types to include in the
#'   vision input to the LLM. Default: all available panels (UMAP,
#'   clustree, marker dotplot, etc.). Pass a subset to constrain.
#' @param max_panels Integer. Hard cap on the number of panels sent in
#'   one request, to control token usage. Default 9.
#' @param panel_dpi Integer. Rasterization DPI for each panel. Lower
#'   reduces base64 payload size. Default 100.
#' @param panel_width Numeric. Panel width in inches. Default 6.
#' @param panel_height Numeric. Panel height in inches. Default 4.
#' @export
sc_resolution_recommend <- function(obj,
                                    chat_fn,
                                    tissue,
                                    expected_n_celltypes = NULL,
                                    small_cluster_pct    = 0.005,
                                    vision               = TRUE,
                                    image_path           = NULL,
                                    vision_panels        = NULL,
                                    max_panels           = 3,
                                    panel_dpi            = 110,
                                    panel_width          = 5,
                                    panel_height         = 4.5,
                                    max_retries          = 2) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("sc_resolution_recommend expects a merged Seurat object.")
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required.")
  }

  # v0.2.0: snapshot token state at entry for per-step accounting
  .tok_before <- length(.token_state$records)

  # 1. Find the RNA_snn_res.* columns produced by sc_cluster_sweep()
  meta <- obj@data@meta.data
  res_cols <- grep("^RNA_snn_res\\.", colnames(meta), value = TRUE)
  if (length(res_cols) < 2) {
    stop("Need at least 2 resolution columns (RNA_snn_res.*). Run sc_cluster_sweep() first.")
  }
  res_values <- as.numeric(sub("RNA_snn_res\\.", "", res_cols))
  ord        <- order(res_values)
  res_cols   <- res_cols[ord]
  res_values <- res_values[ord]
  n_cells    <- nrow(meta)

  # v0.1.6: auto-detect expected_n_celltypes from existing author column,
  # if user didn't pass one explicitly. We allow some "wiggle room" around
  # the author's count: +/-50% in each direction (clamped to [3, 30]) so
  # the LLM can sub-divide a bit if marker evidence supports it.
  if (is.null(expected_n_celltypes)) {
    auto_col <- .detect_celltype_col(meta)
    if (!is.na(auto_col)) {
      n_author <- length(unique(meta[[auto_col]]))
      lo <- max(3,  floor(n_author * 0.6))
      hi <- min(30, ceiling(n_author * 1.5))
      expected_n_celltypes <- c(lo, hi)
      message(sprintf(
        "[sc_resolution_recommend] auto-detected expected_n_celltypes = c(%d, %d) from '%s' column (%d distinct values).",
        lo, hi, auto_col, n_author
      ))
    }
  }

  # 2. Per-resolution statistics
  stats_df <- data.frame(
    resolution      = res_values,
    n_clusters      = integer(length(res_values)),
    n_small         = integer(length(res_values)),
    smallest_pct    = numeric(length(res_values)),
    largest_pct     = numeric(length(res_values)),
    stringsAsFactors = FALSE
  )
  for (i in seq_along(res_cols)) {
    tab <- table(meta[[res_cols[i]]])
    pct <- as.numeric(tab) / n_cells
    stats_df$n_clusters[i]   <- length(tab)
    stats_df$n_small[i]      <- sum(pct < small_cluster_pct)
    stats_df$smallest_pct[i] <- min(pct)
    stats_df$largest_pct[i]  <- max(pct)
  }

  # 3. Adjusted Rand Index between adjacent resolutions
  ari_adjacent <- rep(NA_real_, length(res_cols))
  for (i in 2:length(res_cols)) {
    ari_adjacent[i] <- .adjusted_rand_index(
      meta[[res_cols[i - 1]]],
      meta[[res_cols[i]]]
    )
  }
  stats_df$ari_vs_prev <- ari_adjacent

  # 4. Resolve image to send
  # -------------------------------------------------------------------------
  # Two modes:
  #   - clustree-only (legacy v0.1.0-0.1.14): only the clustree dendrogram,
  #     used if user explicitly passes image_path.
  #   - multi-panel (v0.1.16+): render UMAPs at representative resolutions
  #     and (if available) prepend the clustree image. This gives the LLM
  #     both structure (clustree) and actual layout (UMAPs).
  img_to_send <- NULL
  panels_used <- numeric(0)
  if (isTRUE(vision)) {
    # User-supplied image_path overrides multi-panel rendering. This is
    # the legacy code path; keep it for backwards compatibility.
    if (!is.null(image_path) && file.exists(image_path)) {
      img_to_send <- image_path
    } else {
      # Build multi-panel image
      img_to_send <- tryCatch(
        .build_resolution_vision_panel(
          obj, res_cols, res_values, stats_df,
          expected_n_celltypes = expected_n_celltypes,
          vision_panels        = vision_panels,
          max_panels           = max_panels,
          panel_dpi            = panel_dpi,
          panel_width          = panel_width,
          panel_height         = panel_height
        ),
        error = function(e) {
          message("[sc_resolution_recommend] panel rendering failed (",
                  conditionMessage(e),
                  "); falling back to numeric-only mode.")
          NULL
        }
      )
      if (is.null(img_to_send)) {
        vision <- FALSE
      } else {
        # Read which resolutions ended up in the panel for the prompt
        panels_used <- attr(img_to_send, "panels_used") %||% numeric(0)
      }
    }
  }

  # 5. Build evidence string
  evidence_txt <- paste(
    c("resolution | n_clusters | n_small_clusters | smallest_pct | largest_pct | ARI_vs_prev",
      "-----------|------------|------------------|--------------|-------------|------------"),
    collapse = "\n"
  )
  rows <- apply(stats_df, 1, function(r) {
    sprintf("%s | %s | %s | %.3f | %.3f | %s",
            format(as.numeric(r["resolution"]), nsmall = 2),
            r["n_clusters"], r["n_small"],
            as.numeric(r["smallest_pct"]),
            as.numeric(r["largest_pct"]),
            if (is.na(r["ari_vs_prev"])) "NA"
            else sprintf("%.3f", as.numeric(r["ari_vs_prev"])))
  })
  evidence_txt <- paste(c(evidence_txt, rows), collapse = "\n")

  expected_line <- if (is.null(expected_n_celltypes)) {
    "Expected number of major cell types: unknown; use tissue knowledge."
  } else if (length(expected_n_celltypes) == 1) {
    sprintf("Expected number of major cell types: approximately %d.",
            expected_n_celltypes)
  } else {
    sprintf("Expected number of major cell types: between %d and %d.",
            expected_n_celltypes[1], expected_n_celltypes[2])
  }

  # 6. Prompts
  panels_str <- if (length(panels_used) > 0) {
    paste(sprintf("%.2f", panels_used), collapse = ", ")
  } else ""

  vision_panel_note <- if (isTRUE(vision) && length(panels_used) > 0) {
    paste0(
      "An image is attached showing UMAP layouts at resolutions: ",
      panels_str,
      ". Use BOTH the numeric table AND the visual evidence:\n",
      "  - UMAP panels: actual layouts at each resolution. Look for ",
      "over-fragmentation (a clearly continuous group split into multiple ",
      "colours), under-resolution (visually distinct groups merged into ",
      "one colour), and whether emerging small clusters look biologically ",
      "real or noise.\n",
      "  - Clustree (if shown above the UMAPs): the resolution where a ",
      "stable hierarchy emerges is a good candidate.\n\n",
      "STRICT CONSTRAINTS:\n",
      "  1. `chosen_resolution` MUST be one of the panel resolutions you ",
      "actually saw: ", panels_str, ". Pick the best of those three.\n",
      "  2. If you think a resolution OUTSIDE this panel set is better ",
      "(based on the numeric table), put it in `alternatives` -- never in ",
      "`chosen_resolution`. The chosen value must be defensible from ",
      "VISUAL evidence in the panels you saw.\n",
      "  3. `visual_notes` MUST be non-empty: describe what you observed ",
      "in EACH UMAP panel (e.g. 'res=0.20: 9 distinct clusters, T/NK and ",
      "Hepatocyte cleanly separated; res=0.30: cluster 5 splits into 5a/5b ",
      "with no visible density gap; res=0.40: ...'). Without this field ",
      "your response is rejected."
    )
  } else if (isTRUE(vision)) {
    "A clustree image has been attached. Use BOTH the numeric table and the clustree structure to reach a decision."
  } else {
    "No image supplied; decide from the numeric table alone."
  }

  system_prompt <- .build_resolution_system_prompt(vision = isTRUE(vision))
  user_prompt <- paste0(
    sprintf("Tissue context: %s.\n", tissue),
    expected_line, "\n\n",
    "Resolution sweep (sorted by resolution):\n",
    evidence_txt, "\n\n",
    "Small-cluster threshold used: <",
    sprintf("%.1f%%", 100 * small_cluster_pct), " of total cells.\n\n",
    vision_panel_note,
    "\n\nReturn the JSON object now."
  )

  # 7. Call LLM
  parsed <- .resolution_call_with_retry(
    chat_fn, system_prompt, user_prompt,
    image_path = img_to_send, max_retries = max_retries
  )

  # 7b. Vision-mode quality check: if `chosen_resolution` is outside the
  # panels we showed, OR `visual_notes` is empty, re-prompt once with an
  # explicit correction. Many models (especially Grok, Qwen) skip these
  # constraints on the first pass; one correction usually fixes it.
  if (isTRUE(vision) && length(panels_used) > 0) {
    chosen_raw <- suppressWarnings(as.numeric(
      parsed$chosen_resolution %||% NA))
    snapped <- if (!is.na(chosen_raw)) {
      panels_used[which.min(abs(panels_used - chosen_raw))]
    } else NA_real_
    out_of_panel <- is.na(chosen_raw) ||
      abs(chosen_raw - snapped) > 1e-6
    notes <- as.character(
      parsed$visual_notes %||% parsed$clustree_notes %||% "")
    notes_empty <- !nzchar(trimws(notes))
    if (out_of_panel || notes_empty) {
      problems <- c(
        if (out_of_panel) sprintf(
          "Your `chosen_resolution` was %s but it must be one of: %s.",
          format(chosen_raw), panels_str),
        if (notes_empty)
          "Your `visual_notes` field was empty; you must describe what you observed in EACH UMAP panel."
      )
      correction <- paste0(
        "Your previous response had problems:\n  - ",
        paste(problems, collapse = "\n  - "),
        "\n\nReturn a corrected JSON object now, fixing those issues. ",
        "Re-state ALL fields in your reply."
      )
      parsed2 <- tryCatch(
        .resolution_call_with_retry(
          chat_fn, system_prompt,
          paste0(user_prompt, "\n\n---\n\n", correction),
          image_path = img_to_send, max_retries = 1
        ),
        error = function(e) NULL
      )
      if (!is.null(parsed2) &&
          !is.null(parsed2$chosen_resolution) &&
          !is.na(suppressWarnings(as.numeric(parsed2$chosen_resolution)))) {
        parsed <- parsed2
      }
    }
  }

  # Snap to nearest swept resolution
  chosen <- parsed$chosen_resolution
  if (!is.numeric(chosen) || length(chosen) != 1) {
    chosen <- suppressWarnings(as.numeric(chosen[[1]]))
  }
  if (is.numeric(chosen) && !is.na(chosen)) {
    chosen <- res_values[which.min(abs(res_values - chosen))]
  }

  recommendation <- list(
    chosen         = chosen,
    confidence     = as.character(parsed$confidence %||% NA),
    alternatives   = as.numeric(parsed$alternatives %||% numeric(0)),
    reasoning      = as.character(parsed$reasoning %||% NA),
    visual_notes   = as.character(
      parsed$visual_notes %||% parsed$clustree_notes %||% NA),
    evidence       = stats_df,
    mode           = if (isTRUE(vision)) "vision" else "numeric_only",
    image_sent     = img_to_send
  )

  script <- sprintf(
'# ---- LLM resolution recommendation (%s mode) ----
# Evidence bundle %s
# sent to an LLM; chosen resolution stored at
# obj@params$resolution_recommendation$chosen.
# Recommendation: %s (confidence: %s).',
    recommendation$mode,
    if (isTRUE(vision)) "+ clustree image" else "(numeric only)",
    format(chosen), recommendation$confidence
  )

  rationale <- sprintf(
    "LLM recommended resolution = %s (confidence: %s, mode: %s). Alternatives: %s.",
    format(chosen), recommendation$confidence, recommendation$mode,
    paste(recommendation$alternatives, collapse = ", ")
  )

  obj <- .record_step(
    obj            = obj,
    step_name      = "sc_resolution_recommend",
    function_name  = "sc_resolution_recommend",
    params         = list(
      tissue                = tissue,
      expected_n_celltypes  = expected_n_celltypes,
      sweep_resolutions     = res_values,
      recommended           = chosen,
      confidence            = recommendation$confidence,
      alternatives          = recommendation$alternatives,
      mode                  = recommendation$mode,
      image_sent            = img_to_send
    ),
    rationale      = rationale,
    script_snippet = script
  )
  obj@params$resolution_recommendation <- recommendation
  obj <- .attach_step_tokens(obj, "sc_resolution_recommend", .tok_before)
  obj
}

# ---- Internal helpers ------------------------------------------------------

# Adjusted Rand Index between two clusterings.
.adjusted_rand_index <- function(a, b) {
  a <- as.character(a); b <- as.character(b)
  tab <- table(a, b)
  n <- sum(tab)
  if (n < 2) return(NA_real_)
  sum_comb <- function(x) sum(choose(x, 2))
  a_sum <- sum_comb(rowSums(tab))
  b_sum <- sum_comb(colSums(tab))
  t_sum <- sum_comb(as.vector(tab))
  expected <- a_sum * b_sum / choose(n, 2)
  max_val  <- (a_sum + b_sum) / 2
  if (max_val == expected) return(1)
  (t_sum - expected) / (max_val - expected)
}

# System prompt tailored for vision vs numeric-only mode.
.build_resolution_system_prompt <- function(vision) {
  base_schema <- paste0(
    "Return ONE JSON object with exactly these fields, no prose, no fences:\n\n",
    "{\n",
    '  "chosen_resolution": <number>,\n',
    '  "confidence": "<high|medium|low>",\n',
    '  "alternatives": [<number>, <number>],\n',
    if (vision) '  "visual_notes": "<1-2 sentences describing what you see in the image (clustree structure and/or UMAP layouts)>",\n' else "",
    '  "reasoning": "<2-4 sentences; cite specific resolutions and metrics',
    if (vision) ", and visual features you relied on" else "",
    '>"\n',
    "}\n\n"
  )

  heuristics <- paste0(
    "Decision heuristics:\n",
    "- Favor resolutions with HIGH ARI vs the adjacent lower resolution ",
    "(stability: the clustering does not flip with small parameter change).\n",
    "- Penalize resolutions with many small clusters (`n_small_clusters`): ",
    "usually over-clustering / fragmentation.\n",
    "- Cluster count should be broadly compatible with the expected ",
    "number of major cell types; modest over-segmentation into phenotypic ",
    "sub-states is fine.\n",
    "- If in doubt between two stable plateaus, prefer the lower resolution ",
    "(simpler story); downstream subclustering can refine.\n",
    "- Never pick a resolution outside the table.\n"
  )

  vision_addenda <- if (vision) {
    paste0(
      "\nVisual reading rules (the image may contain a clustree dendrogram ",
      "and/or UMAP panels at representative resolutions):\n",
      "- Clustree (if present): a good resolution sits just BELOW a point ",
      "  where a single cluster abruptly splits into several small branches ",
      "  (that split is usually noise, not biology). Look for 'plateaus' ",
      "  where most clusters have stable ancestry (edges mostly vertical). ",
      "  'Crossing edges' indicate instability -- avoid such resolutions.\n",
      "- UMAP panels (if present): each panel is one resolution colored by ",
      "  cluster ID. Look for: \n",
      "    (a) over-fragmentation -- a visually continuous group split into ",
      "        multiple colours with no clear visual boundary. This means ",
      "        the resolution is too high.\n",
      "    (b) under-resolution -- visually distinct islands or sub-blobs ",
      "        merged into one colour. Resolution is too low.\n",
      "    (c) good separation -- each colour corresponds to a visually ",
      "        cohesive region; boundaries align with density gaps.\n",
      "- Cross-validate: a resolution that looks stable in clustree AND ",
      "  produces visually clean separation in UMAP is a strong candidate.\n",
      "- Very thin branches (few cells) at high resolutions without ",
      "  confirming marker differences are usually artifacts.\n",
      "You MUST describe what you saw in `visual_notes` (which features ",
      "influenced your choice).\n"
    )
  } else ""

  paste0(
    "You are a single-cell clustering expert. You pick a Louvain ",
    "resolution based on stability metrics",
    if (vision) ", a clustree visualization, and UMAP panels showing ",
    if (vision) "the actual layout at representative resolutions" else "",
    ".\n\n",
    base_schema, heuristics, vision_addenda
  )
}

# Retry loop. image_path is forwarded to chat_fn when non-NULL.
.resolution_call_with_retry <- function(chat_fn, system_prompt, user_prompt,
                                        image_path = NULL,
                                        max_retries = 2) {
  last_err <- NULL
  for (i in seq_len(max_retries + 1)) {
    raw <- tryCatch(
      if (is.null(image_path)) {
        chat_fn(system_prompt, user_prompt)
      } else {
        chat_fn(system_prompt, user_prompt, image_path = image_path)
      },
      error = function(e) { last_err <<- e; NULL }
    )
    if (is.null(raw)) next
    raw <- sub("^```(?:json)?\\s*", "", raw)
    raw <- sub("\\s*```\\s*$", "", raw)
    raw <- trimws(raw)
    parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE),
                       error = function(e) { last_err <<- e; NULL })
    if (!is.null(parsed)) return(parsed)
    if (i <= max_retries) {
      user_prompt <- paste0(user_prompt,
        "\n\nYour previous response was not valid JSON. ",
        "Return ONLY the JSON object.")
    }
  }
  list(
    chosen_resolution = NA,
    confidence        = "low",
    alternatives      = numeric(0),
    visual_notes      = NA_character_,
    reasoning         = sprintf(
      "LLM call failed: %s",
      if (is.null(last_err)) "unknown" else conditionMessage(last_err)
    )
  )
}

# Null-coalescing operator (local copy for package independence)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a


# -------------------------------------------------------------------------
# v0.1.16: build a multi-panel image for vision = TRUE.
#
# Layout (when clustree is available):
#   Row 1: clustree.png (single, full-width)
#   Row 2: UMAP @ res_low | UMAP @ res_mid | UMAP @ res_high
#
# Layout (clustree unavailable):
#   Single row: UMAP panels only.
#
# The function attaches `panels_used` (numeric vector of resolutions
# rendered) as an attribute on the returned path so the caller can
# include them in the prompt.
# -------------------------------------------------------------------------
.build_resolution_vision_panel <- function(obj,
                                           res_cols, res_values, stats_df,
                                           expected_n_celltypes = NULL,
                                           vision_panels        = NULL,
                                           max_panels           = 3,
                                           panel_dpi            = 110,
                                           panel_width          = 5,
                                           panel_height         = 4.5) {

  if (!"umap" %in% names(obj@data@reductions)) {
    stop("UMAP not found. Run sc_umap() before sc_resolution_recommend(vision = TRUE).")
  }

  # Pick which resolutions to render.
  if (!is.null(vision_panels)) {
    picked <- as.numeric(vision_panels)
    picked <- picked[picked %in% res_values]
    if (length(picked) == 0) {
      stop("None of the supplied vision_panels are present in the swept resolutions.")
    }
  } else {
    picked <- .pick_panel_resolutions(
      res_values = res_values,
      stats_df   = stats_df,
      expected_n_celltypes = expected_n_celltypes,
      max_panels = max_panels
    )
  }
  picked <- sort(unique(picked))

  out_dir <- "figures/resolution_vision"
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Render UMAP per picked resolution
  panel_paths <- character(length(picked))
  for (i in seq_along(picked)) {
    r <- picked[i]
    col <- sprintf("RNA_snn_res.%s", format(r, trim = TRUE, drop0trailing = TRUE))
    if (!col %in% colnames(obj@data@meta.data)) {
      # Fallback: try the original swept column name based on res_cols
      col <- res_cols[which.min(abs(res_values - r))]
    }
    n_clust <- length(unique(obj@data@meta.data[[col]]))
    title <- sprintf("res = %.2f  (k = %d)", r, n_clust)
    p <- Seurat::DimPlot(obj@data,
                         reduction = "umap",
                         group.by  = col,
                         pt.size   = 0.3,
                         label     = TRUE) +
         ggplot2::theme_classic() +
         ggplot2::ggtitle(title) +
         ggplot2::theme(legend.position = "none")
    path <- file.path(out_dir, sprintf("umap_res_%s.png",
                                       gsub("\\.", "p", format(r, nsmall = 2))))
    ggplot2::ggsave(path, p,
                    width = panel_width, height = panel_height,
                    dpi = panel_dpi)
    panel_paths[i] <- path
  }

  # Find clustree image (if it exists in the figure registry)
  clustree_path <- NULL
  figs <- obj@figures
  if (!is.null(figs) && nrow(figs) > 0) {
    hits <- figs[figs$step == "sc_cluster_sweep", , drop = FALSE]
    if (nrow(hits) > 0) {
      cand <- tail(hits$path, 1)
      if (is.character(cand) && file.exists(cand)) clustree_path <- cand
    }
  }

  combined_path <- file.path(out_dir, "resolution_vision_panel.png")

  # Compose: optional clustree row on top, then UMAP row.
  .compose_resolution_grid(
    clustree_path = clustree_path,
    umap_paths    = panel_paths,
    out_path      = combined_path,
    panel_width   = panel_width,
    panel_height  = panel_height,
    dpi           = panel_dpi
  )

  attr(combined_path, "panels_used") <- picked
  combined_path
}


# Heuristic for picking representative resolutions to render as UMAP panels.
#
# Goal: show the LLM the DECISION REGION, not the extremes. The point of
# a vision panel is to disambiguate between candidate resolutions, so we
# focus on the anchor (best-guess answer) and its immediate neighbors.
# Showing 0.1 / 0.6 / 1.0 when the answer is 0.2 just wastes panel slots
# on options the LLM already knows are wrong from the numeric table.
#
# Strategy:
#   1. Identify anchor index:
#      a. If expected_n_celltypes provided, anchor = resolution whose
#         cluster count is nearest the midpoint.
#      b. Else, anchor = resolution with highest ARI vs prev (most
#         stable transition).
#   2. Take anchor and its immediate neighbors (anchor-1, anchor+1).
#   3. If max_panels > 3, expand outward by one step at a time.
#   4. Clamp to [1, n].
.pick_panel_resolutions <- function(res_values, stats_df,
                                    expected_n_celltypes = NULL,
                                    max_panels = 3) {
  n <- length(res_values)
  if (n <= max_panels) return(res_values)

  # Step 1: anchor index
  if (!is.null(expected_n_celltypes) && length(expected_n_celltypes) >= 1) {
    target <- if (length(expected_n_celltypes) == 1) {
      expected_n_celltypes
    } else {
      mean(expected_n_celltypes)
    }
    anchor_idx <- which.min(abs(stats_df$n_clusters - target))
  } else {
    middle <- stats_df[seq.int(2, n - 1), , drop = FALSE]
    if (nrow(middle) > 0 && any(!is.na(middle$ari_vs_prev))) {
      anchor_res <- middle$resolution[which.max(middle$ari_vs_prev)]
      anchor_idx <- which(res_values == anchor_res)
    } else {
      anchor_idx <- ceiling(n / 2)
    }
  }

  # Step 2-3: anchor +/- one, expand if more panels requested
  picked <- anchor_idx
  step <- 1L
  while (length(picked) < max_panels && step <= n) {
    candidates_left  <- anchor_idx - step
    candidates_right <- anchor_idx + step
    if (candidates_left  >= 1L && !candidates_left  %in% picked) {
      picked <- c(picked, candidates_left)
      if (length(picked) >= max_panels) break
    }
    if (candidates_right <= n  && !candidates_right %in% picked) {
      picked <- c(picked, candidates_right)
    }
    step <- step + 1L
  }
  picked <- sort(unique(picked))
  res_values[picked]
}


# Compose clustree + UMAP panels into one image. Three-tier fallback as
# in sc_select_pcs_visual: magick -> base R + png -> first panel only.
.compose_resolution_grid <- function(clustree_path, umap_paths, out_path,
                                     panel_width, panel_height, dpi) {

  has_clustree <- !is.null(clustree_path) && file.exists(clustree_path)
  n_umap <- length(umap_paths)
  if (n_umap == 0) {
    if (has_clustree) {
      file.copy(clustree_path, out_path, overwrite = TRUE)
      return(invisible(out_path))
    }
    stop("No panels to compose.")
  }

  # Attempt 1: magick
  if (requireNamespace("magick", quietly = TRUE)) {
    ok <- tryCatch({
      umap_imgs <- magick::image_read(umap_paths)
      umap_row <- magick::image_montage(
        umap_imgs,
        tile     = sprintf("%dx1", n_umap),
        geometry = "x600+10+10"
      )
      if (has_clustree) {
        clu <- magick::image_read(clustree_path)
        clu <- magick::image_scale(clu, sprintf("x%d",
          magick::image_info(umap_row)$height))
        # Vertical stack: clustree on top, umap row below
        stack <- magick::image_append(c(
          magick::image_scale(clu, sprintf("%d",
                                            magick::image_info(umap_row)$width)),
          umap_row
        ), stack = TRUE)
        magick::image_write(stack, out_path)
      } else {
        magick::image_write(umap_row, out_path)
      }
      TRUE
    }, error = function(e) {
      message("[sc_resolution_recommend] magick path failed (",
              conditionMessage(e),
              "); falling back to base R compositing.")
      FALSE
    })
    if (ok) return(invisible(out_path))
  }

  # Attempt 2: base R + png
  ok <- tryCatch({
    if (!requireNamespace("png", quietly = TRUE)) {
      stop("Package 'png' required as fallback. install.packages('png').")
    }
    rows <- if (has_clustree) 2L else 1L
    cols <- n_umap
    grDevices::png(out_path,
                   width  = panel_width  * cols * dpi,
                   height = panel_height * rows * dpi,
                   res    = dpi)
    op <- graphics::par(mfrow = c(rows, cols), mar = c(0, 0, 0, 0))
    on.exit({graphics::par(op); grDevices::dev.off()}, add = TRUE)
    if (has_clustree) {
      # Span the clustree across the top row by drawing it n_umap times
      # is ugly; better to just place it once and leave the rest blank.
      # Use a layout grid instead.
      graphics::par(op)
      grDevices::dev.off()
      grDevices::png(out_path,
                     width  = panel_width  * cols * dpi,
                     height = panel_height * rows * dpi,
                     res    = dpi)
      mat <- rbind(
        rep(1L, cols),                        # clustree on top, full row
        seq_len(cols) + 1L                    # UMAPs below
      )
      graphics::layout(mat)
      graphics::par(mar = c(0, 0, 0, 0))
      img <- png::readPNG(clustree_path)
      graphics::plot.new()
      graphics::plot.window(c(0, 1), c(0, 1))
      graphics::rasterImage(img, 0, 0, 1, 1)
      for (p in umap_paths) {
        u <- png::readPNG(p)
        graphics::plot.new()
        graphics::plot.window(c(0, 1), c(0, 1),
                              asp = panel_height / panel_width)
        graphics::rasterImage(u, 0, 0, 1, 1)
      }
    } else {
      for (p in umap_paths) {
        u <- png::readPNG(p)
        graphics::plot.new()
        graphics::plot.window(c(0, 1), c(0, 1),
                              asp = panel_height / panel_width)
        graphics::rasterImage(u, 0, 0, 1, 1)
      }
    }
    TRUE
  }, error = function(e) {
    message("[sc_resolution_recommend] base-R compositing failed (",
            conditionMessage(e), "); using first UMAP panel only.")
    FALSE
  })
  if (ok) return(invisible(out_path))

  file.copy(umap_paths[[1]], out_path, overwrite = TRUE)
  invisible(out_path)
}
