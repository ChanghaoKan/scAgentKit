#' Two-step annotation: subset by broad type, recluster, sub-annotate
#'
#' Solves a fundamental limitation of single-resolution clustering:
#' the optimal resolution is lineage-dependent. T/NK and B cells need
#' fine resolution to resolve sub-types (CD8 vs CD4 vs Treg, naive vs
#' memory vs plasma); hepatocytes and fibroblasts are usually well
#' resolved at coarse resolution and over-fragment if pushed harder.
#'
#' This function takes an annotated `AgentSeurat` (with broad
#' `cell_type` already assigned by [annot_llm_annotate()] or similar),
#' subsets each requested broad type, runs a fresh per-lineage
#' analysis pipeline (HVG -> scale -> PCA -> UMAP -> clusters), then
#' calls the LLM to annotate sub-clusters with lineage-specific
#' vocabulary. Results are merged back into a new metadata column
#' `cell_type_fine`. The original `cell_type` is preserved.
#'
#' Resolution control:
#' \itemize{
#'   \item `subcluster_resolution = "adaptive"` (default): scale
#'     resolution by lineage size on a log10 cell-count curve, clamped
#'     to [0.2, 0.6]. Small subsets (1k cells) get ~0.30; large subsets
#'     (20k cells) get ~0.47. Avoids over-fragmenting small lineages.
#'   \item `subcluster_resolution = 0.5`: use a fixed numeric
#'     resolution for every lineage. Cheap and predictable.
#'   \item `subcluster_resolution = "auto"`: for each lineage, run
#'     [sc_cluster_sweep()] and [sc_resolution_recommend()] to let the
#'     LLM pick a per-lineage resolution. Costs ~6x more LLM calls but
#'     gives a per-lineage tailored sub-clustering.
#'   \item `subcluster_resolution = c(T_NK = 0.6, B = 0.4)`: per-target
#'     numeric mapping for full manual control. Targets not listed
#'     fall back to adaptive.
#' }
#'
#' @param obj An AgentSeurat with broad `cell_type` already set.
#' @param chat_fn Chat function (text-only is fine; vision unused).
#' @param target Character vector of broad types to subcluster, or
#'   NULL (default) for auto: subcluster every broad type with at
#'   least `min_cells_per_broad` cells.
#' @param subcluster_resolution Numeric, the string `"adaptive"`
#'   (default) or `"auto"`, or a named numeric vector (see Details).
#'   The "adaptive" curve was empirically calibrated on liver/HCC data
#'   (10-50k cells, broad types from cDC1 to hepatocytes). Other tissues
#'   (developing brain, organoids, very rare populations) may need a
#'   different curve; pass a fixed numeric to override.
#' @param min_cells_per_broad Integer. Skip broad types with fewer
#'   cells. Default 200.
#' @param min_cells_per_subcluster Integer. Sub-clusters smaller than
#'   this are not annotated by the LLM and labelled
#'   `"<broad>: too small to annotate"`. Default 30.
#' @param tissue Character. Tissue context to give the LLM.
#' @param top_n_markers Integer. Top markers per sub-cluster to send
#'   to the LLM. Default 15.
#' @param max_retries Integer. Retry count per LLM call.
#' @param verbose Logical. Default TRUE.
#'
#' @return Updated AgentSeurat. New columns in `obj@data@meta.data`:
#' \itemize{
#'   \item `cell_type_fine`: equal to `cell_type` for cells whose
#'     broad type was not sub-clustered, otherwise the sub-type label.
#'   \item `subcluster_id`: e.g. `"T_NK_sub3"` or NA for cells in
#'     untouched broad types.
#' }
#' Per-target results (sub-clusters, markers, LLM responses, UMAP
#' figures) are stored in `obj@params$subcluster_results`.
#'
#' @param n_hvg Integer or `"adaptive"`. Number of HVGs to recompute per
#'   subset. Default `"adaptive"`: scale with subset size on a log10
#'   curve, clamped to [800, 2000]. Pass a single integer for fixed
#'   behaviour. Prior to v0.1.24 the default was a fixed 1500.
#' @param n_pcs Integer or `"adaptive"`. Number of PCs to compute on
#'   the subset. UMAP and graph use all of them. Default `"adaptive"`:
#'   scale with subset size on a log10 curve, clamped to [10, 30].
#'   Pass a single integer for fixed behaviour. Prior to v0.1.24 the
#'   default was a fixed 20.
#'
#' @export
annot_subcluster <- function(obj,
                             chat_fn,
                             target                   = NULL,
                             subcluster_resolution    = "adaptive",
                             n_hvg                    = "adaptive",
                             n_pcs                    = "adaptive",
                             min_cells_per_broad      = 200,
                             min_cells_per_subcluster = 30,
                             tissue                   = "human tissue",
                             data_context             = NULL,
                             suggest_followups        = FALSE,
                             top_n_markers            = 15,
                             max_retries              = 1,
                             verbose                  = TRUE) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("annot_subcluster expects a single Seurat object.")
  }

  if (!"cell_type" %in% colnames(obj@data@meta.data)) {
    stop("`cell_type` column not found. Run annot_llm_annotate() first.")
  }

  # v0.2.0: snapshot token state at entry. annot_subcluster fans out to
  # many LLM calls across per-broad sub-pipelines and resolution
  # recommenders; we record the cumulative cost as a single step entry.
  .tok_before <- length(.token_state$records)

  # Diagnostic: catch checkpoint corruption (column length != row count)
  # before any mutation. This happened in v0.1.18 with one user's
  # 04_annotated.qs checkpoint where cell_type had 50404 entries but
  # meta.data had 48858 rows. Bail with a clear message instead of
  # erroring from inside `$<-.data.frame`.
  ct_len <- length(obj@data@meta.data$cell_type)
  md_n   <- nrow(obj@data@meta.data)
  if (ct_len != md_n) {
    stop(sprintf(
      "obj@data@meta.data$cell_type has %d entries but the data.frame has %d rows. ",
      ct_len, md_n),
      "This indicates a corrupted Seurat object. Likely fix:\n",
      "  obj@data@meta.data$cell_type <- obj@data@meta.data$cell_type[seq_len(nrow(obj@data@meta.data))]\n",
      "Or re-run annot_llm_annotate() / annot_apply() and re-save the checkpoint.")
  }

  # Resolve targets
  broad_counts <- table(obj@data@meta.data$cell_type)
  if (is.null(target)) {
    target <- names(broad_counts)[broad_counts >= min_cells_per_broad]
    if (verbose) {
      message(sprintf(
        "[annot_subcluster] auto-selected %d broad types with >= %d cells: %s",
        length(target), min_cells_per_broad,
        paste(target, collapse = ", ")
      ))
    }
  } else {
    missing <- setdiff(target, names(broad_counts))
    if (length(missing) > 0) {
      stop(sprintf("Targets not present in cell_type column: %s",
                   paste(missing, collapse = ", ")))
    }
    too_small <- target[broad_counts[target] < min_cells_per_broad]
    if (length(too_small) > 0) {
      warning(sprintf(
        "Skipping targets below min_cells_per_broad (%d): %s",
        min_cells_per_broad, paste(too_small, collapse = ", ")
      ))
      target <- setdiff(target, too_small)
    }
  }
  if (length(target) == 0) {
    stop("No targets remain after filtering. Lower min_cells_per_broad or pass `target`.")
  }

  # Resolve resolution per target. Default "adaptive": each lineage
  # gets a resolution scaled to its cell count (small subsets get
  # lower resolution to avoid over-fragmentation; large subsets
  # higher to surface real sub-structure). See
  # .resolve_subcluster_resolutions for the formula.
  res_per_target <- .resolve_subcluster_resolutions(
    target, subcluster_resolution, broad_counts
  )

  # Initialize fine columns. Use the live meta.data — never a captured
  # copy — to guarantee row counts match the data.frame we're writing
  # back into. Use rep() with the data.frame's actual nrow rather than
  # an arbitrary right-hand side, in case the assay/meta have drifted.
  n_meta <- nrow(obj@data@meta.data)
  if (!"cell_type_fine" %in% colnames(obj@data@meta.data)) {
    init_fine <- as.character(obj@data@meta.data$cell_type)
    if (length(init_fine) != n_meta) {
      stop(sprintf(
        "Internal inconsistency: cell_type has %d entries but meta.data has %d rows. ",
        length(init_fine), n_meta),
        "Re-run annot_llm_annotate() and re-save before subclustering.")
    }
    obj@data@meta.data$cell_type_fine <- init_fine
  }
  if (!"subcluster_id" %in% colnames(obj@data@meta.data)) {
    obj@data@meta.data$subcluster_id <- rep(NA_character_, n_meta)
  }

  results <- list()

  out_dir <- "figures/subcluster"
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  for (broad in target) {
    res_for_this <- res_per_target[[broad]]
    if (verbose) {
      message(sprintf(
        "\n[annot_subcluster] >>> %s (%d cells, resolution = %s)",
        broad, broad_counts[[broad]],
        if (is.character(res_for_this)) res_for_this
        else format(res_for_this)
      ))
    }
    res <- tryCatch(
      .subcluster_one_broad(
        obj                      = obj,
        broad                    = broad,
        chat_fn                  = chat_fn,
        resolution_spec          = res_for_this,
        n_hvg                    = n_hvg,
        n_pcs                    = n_pcs,
        min_cells_per_subcluster = min_cells_per_subcluster,
        tissue                   = tissue,
        data_context             = data_context,
        suggest_followups        = suggest_followups,
        top_n_markers            = top_n_markers,
        max_retries              = max_retries,
        out_dir                  = out_dir,
        verbose                  = verbose
      ),
      error = function(e) {
        warning(sprintf("[annot_subcluster] %s failed: %s",
                        broad, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(res)) next

    # Merge back using INTEGER row indices (never character names —
    # character indexing on an unnamed character vector silently
    # extends the vector if names don't match, which corrupts
    # meta.data without an error).
    cells     <- res$cells
    cell_idx  <- res$cell_idx
    if (length(cell_idx) != length(res$cell_type_fine)) {
      stop(sprintf(
        "[%s] internal length mismatch: %d cell indices vs %d fine labels.",
        broad, length(cell_idx), length(res$cell_type_fine)
      ))
    }
    obj@data@meta.data$cell_type_fine[cell_idx] <- res$cell_type_fine
    obj@data@meta.data$subcluster_id[cell_idx]  <- res$subcluster_id

    # Register figure
    if (!is.null(res$umap_path) && file.exists(res$umap_path)) {
      obj <- .record_figure(
        obj,
        step        = "annot_subcluster",
        path        = res$umap_path,
        description = sprintf(
          "Sub-clustering of broad type '%s' (n=%d cells, resolution=%s, %d sub-clusters).",
          broad, length(cells),
          format(res$resolution_used), length(unique(res$subcluster_id))
        )
      )
    }

    results[[broad]] <- res[setdiff(names(res),
                                    c("cells", "cell_type_fine", "subcluster_id"))]
  }

  if (length(results) == 0) {
    warning("No subcluster results produced.")
    return(obj)
  }

  obj@params$subcluster_results <- results

  # Decision log
  summary_str <- paste(
    vapply(names(results), function(b) {
      r <- results[[b]]
      sprintf("%s: %d sub-clusters at res=%s -> %s",
              b, nrow(r$annotations),
              format(r$resolution_used),
              paste(r$annotations$cell_type_fine, collapse = " | "))
    }, character(1)),
    collapse = "\n"
  )
  rationale <- paste0(
    "Two-step annotation: per-broad-type subset, fresh PCA/UMAP/clustering, ",
    "lineage-specific LLM annotation. ",
    sprintf("Targets: %s. Results:\n%s",
            paste(names(results), collapse = ", "), summary_str)
  )
  script <- paste0(
    "# ---- Sub-clustering / fine annotation ----\n",
    sprintf("# Targets: %s\n", paste(names(results), collapse = ", ")),
    "# Each broad type was subset, re-normalized for HVG, re-PCA'd,\n",
    "# re-UMAPped, re-clustered, then annotated by the LLM with lineage-\n",
    "# specific prompt constraints. See obj@params$subcluster_results.\n"
  )

  obj <- .record_step(
    obj           = obj,
    step_name     = "annot_subcluster",
    function_name = "annot_subcluster",
    params        = list(
      target                   = target,
      resolution_per_target    = res_per_target,
      n_hvg                    = n_hvg,
      n_pcs                    = n_pcs,
      min_cells_per_broad      = min_cells_per_broad,
      min_cells_per_subcluster = min_cells_per_subcluster
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "fine_annotated"
  )
  .attach_step_tokens(obj, "annot_subcluster", .tok_before)
}


# Resolve resolution spec into a per-target list. Each entry is either
# a numeric or the string "auto" (deferred decision).
.resolve_subcluster_resolutions <- function(target, spec, broad_counts) {
  # Adaptive default: scale resolution to log10(cell count). Larger
  # subsets need higher resolution to surface meaningful sub-structure;
  # smaller subsets over-fragment at high resolution.
  #
  # v0.1.22: curve tightened by 0.05 vs v0.1.21 — empirically v0.1.21
  # over-fragmented T/NK at 22k cells (23 clusters with many
  # sub-200-cell stress-state cluster fragments).
  #
  #   n=200    -> 0.20
  #   n=500    -> 0.22
  #   n=1000   -> 0.25
  #   n=2000   -> 0.28
  #   n=5000   -> 0.32
  #   n=10000  -> 0.35
  #   n=20000  -> 0.38
  #   n=50000  -> 0.42
  #
  # Clamped to [0.20, 0.55].
  adaptive_for <- function(n) {
    r <- 0.05 + 0.10 * log10(n)
    max(0.20, min(0.55, r))
  }

  # NULL -> default to adaptive (changed in v0.1.21; was 0.5)
  if (is.null(spec) ||
      (is.character(spec) && length(spec) == 1 && spec == "adaptive")) {
    return(stats::setNames(
      lapply(target, function(b) adaptive_for(broad_counts[[b]])),
      target
    ))
  }
  if (is.character(spec) && length(spec) == 1 && spec == "auto") {
    return(stats::setNames(as.list(rep("auto", length(target))), target))
  }
  if (is.numeric(spec) && length(spec) == 1) {
    return(stats::setNames(as.list(rep(spec, length(target))), target))
  }
  if (is.numeric(spec) && !is.null(names(spec))) {
    # Named numeric: per-target overrides; missing targets fall back to
    # adaptive.
    out <- stats::setNames(
      lapply(target, function(b) adaptive_for(broad_counts[[b]])),
      target
    )
    for (nm in intersect(target, names(spec))) {
      out[[nm]] <- unname(spec[nm])
    }
    return(out)
  }
  stop("Could not parse `subcluster_resolution`. Use a single number, ",
       "'adaptive', 'auto', or a named numeric vector.")
}


# Run the full per-lineage sub-pipeline for one broad type.
.subcluster_one_broad <- function(obj, broad, chat_fn,
                                  resolution_spec,
                                  n_hvg, n_pcs,
                                  min_cells_per_subcluster,
                                  tissue,
                                  data_context = NULL,
                                  suggest_followups = FALSE,
                                  top_n_markers = 15,
                                  max_retries = 1,
                                  out_dir, verbose) {

  if (!requireNamespace("Seurat", quietly = TRUE)) {
    stop("Seurat is required.")
  }
  meta <- obj@data@meta.data
  # `cell_idx` is derived from row position — this is what we'll use to
  # write back into meta.data. `cells` is the barcode set Seurat
  # operates on. They must stay in lock-step (same length, same order),
  # but we deliberately do NOT compare barcode *strings* between
  # `colnames(sub)` and `rownames(meta)` because Seurat v5 sometimes
  # decorates barcodes (suffixes like _1, _2) during subset/integration.
  # Length match is the real invariant.
  broad_mask <- meta$cell_type == broad
  cell_idx   <- which(broad_mask)
  cells      <- rownames(meta)[broad_mask]
  if (length(cells) < 50) {
    stop(sprintf("Only %d cells of broad type %s; cannot subcluster.",
                 length(cells), broad))
  }

  # 1. Subset
  if (verbose) message(sprintf("  [%s] subset %d cells", broad, length(cells)))
  sub <- subset(obj@data, cells = cells)

  # Defensive: confirm subset returned the expected number of cells.
  # We do NOT require setequal() of barcodes because Seurat v5 may
  # rewrite barcodes (e.g. add _1 suffix) — that's fine, we use
  # positional row indices for the merge.
  if (ncol(sub) != length(cells)) {
    stop(sprintf(
      "[%s] subset returned %d cells but expected %d. Seurat may not have matched barcodes correctly.",
      broad, ncol(sub), length(cells)
    ))
  }
  # Use whatever barcode strings Seurat now thinks the cells have, for
  # internal Seurat ops within this function. Order is preserved by
  # subset() in v5, so positional alignment with cell_idx still holds.
  cells <- colnames(sub)

  # v0.1.24: resolve adaptive n_hvg / n_pcs from subset size.
  # Static defaults (n_hvg=1500, n_pcs=20) over-spec small subsets
  # (500-cell cDC1 doesn't have power for 1500 HVG) and under-spec
  # large ones (22k T/NK can use more PCs).
  n_cells_sub <- length(cells)
  n_hvg_used <- if (is.character(n_hvg) && length(n_hvg) == 1 &&
                    n_hvg == "adaptive") {
    .adaptive_n_hvg(n_cells_sub, n_genes = nrow(sub))
  } else {
    as.integer(n_hvg)
  }
  n_pcs_used <- if (is.character(n_pcs) && length(n_pcs) == 1 &&
                    n_pcs == "adaptive") {
    .adaptive_n_pcs(n_cells_sub)
  } else {
    as.integer(n_pcs)
  }
  if (verbose) {
    message(sprintf("  [%s] n_hvg=%d, n_pcs=%d (cells=%d)",
                    broad, n_hvg_used, n_pcs_used, n_cells_sub))
  }

  # 2. Re-normalize / find HVGs (variance structure differs in lineage subset)
  sub <- Seurat::NormalizeData(sub, verbose = FALSE)
  sub <- Seurat::FindVariableFeatures(sub, nfeatures = n_hvg_used,
                                       verbose = FALSE)

  # 3. Scale on HVG only (S4-method-dispatch-safe pattern, see v0.1.8)
  hvg <- Seurat::VariableFeatures(sub)
  sub <- Seurat::ScaleData(sub, features = hvg, verbose = FALSE)

  # 4. PCA
  sub <- Seurat::RunPCA(sub, features = hvg, npcs = n_pcs_used,
                         verbose = FALSE)

  # 5. Resolve resolution
  res_used <- if (is.character(resolution_spec) && resolution_spec == "auto") {
    .auto_resolution_for_subset(sub, chat_fn = chat_fn,
                                broad = broad, tissue = tissue,
                                n_pcs = n_pcs_used, max_retries = max_retries,
                                verbose = verbose)
  } else {
    as.numeric(resolution_spec)
  }
  if (verbose) message(sprintf("  [%s] using resolution %.2f",
                               broad, res_used))

  # 6. Neighbors + cluster + UMAP
  sub <- Seurat::FindNeighbors(sub, dims = seq_len(n_pcs_used),
                                verbose = FALSE)
  sub <- Seurat::FindClusters(sub, resolution = res_used, verbose = FALSE)
  sub <- Seurat::RunUMAP(sub, dims = seq_len(n_pcs_used), verbose = FALSE)

  # Get cluster IDs aligned by name to `cells` (cell_idx order).
  # Seurat::Idents() returns a NAMED factor — names are barcodes — so
  # we can index by name to guarantee the cluster_ids vector is in the
  # same positional order as `cells` (and therefore `cell_idx`).
  ident_factor <- Seurat::Idents(sub)
  if (!is.null(names(ident_factor))) {
    cluster_ids <- as.character(ident_factor[cells])
    if (any(is.na(cluster_ids))) {
      stop(sprintf(
        "[%s] %d cells lost their cluster identity during sub-pipeline.",
        broad, sum(is.na(cluster_ids))
      ))
    }
  } else {
    # Idents() returned an unnamed vector — fall back to positional
    # alignment, but warn since this is unusual.
    cluster_ids <- as.character(ident_factor)
    if (length(cluster_ids) != length(cells)) {
      stop(sprintf(
        "[%s] cluster_ids length %d != cells length %d.",
        broad, length(cluster_ids), length(cells)
      ))
    }
  }
  unique_clu  <- sort(unique(cluster_ids))
  if (verbose) message(sprintf("  [%s] %d sub-clusters",
                               broad, length(unique_clu)))

  # 7. Markers per sub-cluster
  if (verbose) message(sprintf("  [%s] computing markers", broad))
  markers <- Seurat::FindAllMarkers(
    sub, only.pos = TRUE, min.pct = 0.25,
    logfc.threshold = 0.25, verbose = FALSE
  )
  if (nrow(markers) == 0) {
    warning(sprintf("No markers found for any sub-cluster of %s.", broad))
  }

  # 8. Build per-cluster marker summary, annotate
  annotations <- data.frame(
    subcluster   = unique_clu,
    n_cells      = vapply(unique_clu,
                          function(c) sum(cluster_ids == c), integer(1)),
    pct_of_broad = NA_real_,
    cell_type_fine  = NA_character_,
    confidence      = NA_character_,
    reasoning       = NA_character_,
    followup        = NA_character_,
    top_markers     = NA_character_,
    stringsAsFactors = FALSE
  )
  annotations$pct_of_broad <- annotations$n_cells / sum(annotations$n_cells)

  for (i in seq_len(nrow(annotations))) {
    cid <- annotations$subcluster[i]
    if (annotations$n_cells[i] < min_cells_per_subcluster) {
      annotations$cell_type_fine[i] <- sprintf("%s: too small to annotate",
                                                broad)
      annotations$confidence[i]     <- "low"
      annotations$reasoning[i]      <- sprintf("Only %d cells; below threshold %d.",
                                                annotations$n_cells[i],
                                                min_cells_per_subcluster)
      annotations$followup[i]       <- ""
      next
    }
    sub_markers <- markers[markers$cluster == cid, , drop = FALSE]
    sub_markers <- sub_markers[order(-sub_markers$avg_log2FC), , drop = FALSE]
    sub_markers <- utils::head(sub_markers, top_n_markers)
    annotations$top_markers[i] <- paste(sub_markers$gene, collapse = ", ")

    if (nrow(sub_markers) == 0) {
      annotations$cell_type_fine[i] <- sprintf("%s: no markers", broad)
      annotations$confidence[i]     <- "low"
      annotations$reasoning[i]      <- "No positive markers found."
      annotations$followup[i]       <- ""
      next
    }

    res <- .annotate_one_subcluster_with_llm(
      broad             = broad,
      cluster_id        = cid,
      n_cells           = annotations$n_cells[i],
      pct               = annotations$pct_of_broad[i],
      markers_df        = sub_markers,
      tissue            = tissue,
      data_context      = data_context,
      suggest_followups = suggest_followups,
      chat_fn           = chat_fn,
      max_retries       = max_retries
    )
    annotations$cell_type_fine[i] <- res$label
    annotations$confidence[i]     <- res$confidence
    annotations$reasoning[i]      <- res$reasoning
    annotations$followup[i]       <- res$followup
  }

  # 9. Apply annotation to cells
  cell_type_fine_vec <- annotations$cell_type_fine[
    match(cluster_ids, annotations$subcluster)
  ]
  subcluster_id_vec <- sprintf("%s_sub%s", broad, cluster_ids)

  # 10. UMAP figure (sub-UMAP coloured by sub-type)
  umap_path <- NULL
  ok <- tryCatch({
    sub$.cell_type_fine <- cell_type_fine_vec
    p <- Seurat::DimPlot(sub, reduction = "umap",
                         group.by = ".cell_type_fine",
                         pt.size = 0.4, label = TRUE, repel = TRUE) +
         ggplot2::theme_classic() +
         ggplot2::ggtitle(sprintf("Sub-clustering of %s (n=%d, res=%.2f)",
                                  broad, length(cells), res_used)) +
         ggplot2::theme(legend.position = "none")
    safe_broad <- gsub("[^A-Za-z0-9_]", "_", broad)
    umap_path <- file.path(out_dir,
                           sprintf("subcluster_%s.png", safe_broad))
    ggplot2::ggsave(umap_path, p, width = 7, height = 6, dpi = 150)
    TRUE
  }, error = function(e) {
    message("  UMAP figure failed: ", conditionMessage(e))
    FALSE
  })
  if (!isTRUE(ok)) umap_path <- NULL

  list(
    broad             = broad,
    cells             = cells,
    cell_idx          = cell_idx,
    cell_type_fine    = cell_type_fine_vec,
    subcluster_id     = subcluster_id_vec,
    annotations       = annotations,
    markers           = markers,
    resolution_used   = res_used,
    n_hvg_used        = n_hvg_used,
    n_pcs_used        = n_pcs_used,
    n_subclusters     = length(unique_clu),
    umap_path         = umap_path
  )
}


# v0.1.24: adaptive HVG count from subset size.
# Static 1500 over-specifies small subsets and under-specifies larger ones.
# Curve: 800 + 400 * log10(n / 100), clamped to [800, 2000].
#   n=200    -> 920
#   n=500    -> 1080
#   n=1500   -> 1270
#   n=5000   -> 1480
#   n=20000  -> 1720
#   n=50000  -> 1880
# Also caps at n_genes / 2 because nfeatures > total genes is nonsense.
.adaptive_n_hvg <- function(n_cells, n_genes = NULL) {
  raw <- 800 + 400 * log10(max(n_cells, 100) / 100)
  out <- max(800, min(2000, round(raw)))
  if (!is.null(n_genes) && n_genes > 0) {
    out <- min(out, max(500, floor(n_genes / 2)))
  }
  as.integer(out)
}


# v0.1.24: adaptive PC count from subset size.
# Static 20 is fine for medium subsets but under-counts large ones (50k+)
# and over-counts very small ones (500). Curve: 8 + 4 * log10(n), clamped
# to [10, 30].
#   n=200    -> 17
#   n=500    -> 19
#   n=1500   -> 21
#   n=5000   -> 23
#   n=20000  -> 25
#   n=50000  -> 27
.adaptive_n_pcs <- function(n_cells) {
  raw <- 8 + 4 * log10(max(n_cells, 100))
  as.integer(max(10, min(30, round(raw))))
}


# When subcluster_resolution = "auto": use existing sc_cluster_sweep +
# sc_resolution_recommend. Sweep at finer granularity than the global
# pipeline because lineage subsets benefit from sharper clustering.
.auto_resolution_for_subset <- function(sub, chat_fn, broad, tissue,
                                         n_pcs, max_retries, verbose) {
  if (verbose) message(sprintf("  [%s] sweeping resolution (auto mode)",
                               broad))
  sub <- Seurat::FindNeighbors(sub, dims = seq_len(n_pcs), verbose = FALSE)
  res_grid <- c(0.2, 0.4, 0.6, 0.8, 1.0, 1.2)
  for (r in res_grid) {
    sub <- Seurat::FindClusters(sub, resolution = r, verbose = FALSE)
  }
  meta <- sub@meta.data
  res_cols   <- grep("^RNA_snn_res\\.", colnames(meta), value = TRUE)
  res_values <- as.numeric(sub("RNA_snn_res\\.", "", res_cols))
  ord        <- order(res_values)
  res_cols   <- res_cols[ord]
  res_values <- res_values[ord]

  # Build minimal stats table
  n_cells <- nrow(meta)
  stats_df <- data.frame(
    resolution   = res_values,
    n_clusters   = vapply(res_cols, function(c) length(unique(meta[[c]])),
                          integer(1)),
    n_small      = vapply(res_cols, function(c) {
      pct <- as.numeric(table(meta[[c]])) / n_cells
      sum(pct < 0.01)
    }, integer(1)),
    smallest_pct = vapply(res_cols, function(c) {
      min(as.numeric(table(meta[[c]])) / n_cells)
    }, numeric(1)),
    largest_pct  = vapply(res_cols, function(c) {
      max(as.numeric(table(meta[[c]])) / n_cells)
    }, numeric(1)),
    ari_vs_prev  = NA_real_,
    stringsAsFactors = FALSE
  )
  for (i in 2:length(res_cols)) {
    stats_df$ari_vs_prev[i] <- .adjusted_rand_index(
      meta[[res_cols[i - 1]]], meta[[res_cols[i]]]
    )
  }

  # Build evidence text and call LLM (text-mode; vision adds little here)
  evidence_txt <- paste(
    c("resolution | n_clusters | n_small | smallest_pct | largest_pct | ARI_vs_prev",
      "-----------|------------|---------|--------------|-------------|------------"),
    collapse = "\n"
  )
  rows <- apply(stats_df, 1, function(r) {
    sprintf("%.2f | %s | %s | %.3f | %.3f | %s",
            as.numeric(r["resolution"]),
            r["n_clusters"], r["n_small"],
            as.numeric(r["smallest_pct"]),
            as.numeric(r["largest_pct"]),
            if (is.na(r["ari_vs_prev"])) "NA"
            else sprintf("%.3f", as.numeric(r["ari_vs_prev"])))
  })
  evidence_txt <- paste(c(evidence_txt, rows), collapse = "\n")

  system_prompt <- paste(
    sprintf("You are picking a sub-clustering resolution within the %s lineage from a %s tissue.",
            broad, tissue),
    "Respond with ONLY a JSON object: {\"chosen_resolution\": <number>, \"confidence\": \"<low|medium|high>\", \"reasoning\": \"<short>\"}.",
    "Heuristics: high ARI vs prev = stable; few small clusters = good;",
    "lineage-internal heterogeneity often supports 4-10 sub-clusters.",
    "If in doubt prefer the lower stable resolution.",
    sep = "\n"
  )
  user_prompt <- paste0(
    sprintf("Broad lineage: %s. Tissue: %s.\n\n", broad, tissue),
    "Resolution sweep:\n", evidence_txt,
    "\n\nReturn JSON only."
  )

  parsed <- .call_with_retry(chat_fn, system_prompt, user_prompt,
                             max_retries = max_retries)
  chosen <- suppressWarnings(as.numeric(parsed$chosen_resolution))
  if (is.na(chosen)) {
    warning(sprintf("auto-resolution for %s returned non-numeric; falling back to 0.5.",
                    broad))
    return(0.5)
  }
  res_values[which.min(abs(res_values - chosen))]
}


# Single sub-cluster annotation. The system prompt:
#   - Lists tissue-specific ambient genes (so LLM doesn't read those
#     as cross-lineage contamination)
#   - Lists stress / immediate-early genes (same reason)
#   - Names lineage-internal end-states that are NEVER contaminants
#     (plasma cell, NK in T/NK, Kupffer in myeloid, etc.)
#   - Has tightened contaminant criteria (≥3 canonical markers,
#     high logFC, not on the ambient/stress list)
#   - Has tissue/species-aware proportion guide
#   - Optionally requests a followup field with concrete next-step
#     analysis suggestions, anchored to user-supplied data_context.
.annotate_one_subcluster_with_llm <- function(broad, cluster_id, n_cells,
                                              pct, markers_df, tissue,
                                              data_context     = NULL,
                                              suggest_followups = FALSE,
                                              chat_fn, max_retries) {

  vocab_examples   <- .lineage_vocab_examples(broad)
  proportion_guide <- .lineage_proportion_guide_v2(broad, tissue)

  # Detect species from the marker gene symbols actually shown to LLM.
  species <- .detect_species_from_markers(markers_df$gene)

  # Tissue-specific ambient genes. Add mouse equivalents (sentence-case)
  # to cover both species since LLM may see either naming convention.
  ambient_human <- .tissue_ambient_genes(tissue)
  ambient_str <- if (length(ambient_human) > 0) {
    ambient_mouse <- paste0(
      substr(ambient_human, 1, 1),
      tolower(substring(ambient_human, 2))
    )
    sprintf(
      "  Ambient genes for %s tissue (DO NOT count as cross-lineage evidence):\n    %s\n  Mouse equivalents: %s",
      tissue,
      paste(ambient_human, collapse = ", "),
      paste(ambient_mouse, collapse = ", ")
    )
  } else {
    sprintf(
      "  No tissue-specific ambient list available for '%s'. As a general rule, transcripts from the dominant lineage of the tissue can leak into all droplets via free RNA — be skeptical of single high-abundance transcripts that match the tissue's dominant cell type.",
      tissue
    )
  }

  stress_genes <- .stress_genes_both_species()
  stress_str <- paste0(
    "  Stress / dissociation / immediate-early genes (DO NOT count as cross-lineage evidence):\n    ",
    paste(utils::head(stress_genes, 30), collapse = ", "),
    ", ..."
  )

  # data_context is the user's research framework — anchor followup
  # suggestions to it. If absent, suggestions are generic-but-concrete.
  data_context_str <- if (!is.null(data_context) && nzchar(data_context)) {
    sprintf("\n------ User research context ------\n%s\n", data_context)
  } else ""

  followup_block <- if (isTRUE(suggest_followups)) {
    paste(
      "",
      "------ Followup analysis suggestion ------",
      "BEYOND the label itself, suggest 1-2 concrete next-step analyses",
      "or scientific questions for THIS specific sub-cluster, anchored to",
      "this tissue/disease context (and the user research context above,",
      "if provided). Be specific to the cluster's markers — not generic",
      "advice. Examples of GOOD followups:",
      "  - 'TIM3/LAG3/TIGIT co-expression in this cluster suggests terminal",
      "     exhaustion; test correlation with clinical anti-PD-1 response.'",
      "  - 'IGHV repertoire skew in this plasma cluster could be tested',",
      "     'for clonal expansion via BCR analysis.'",
      "  - 'SPP1 dominance suggests pro-tumorigenic TAM; test correlation",
      "     with vascular invasion / metastasis status in matched samples.'",
      "Examples of BAD followups (do NOT write these):",
      "  - 'Validate with flow cytometry'",
      "  - 'Do more clustering at higher resolution'",
      "  - 'Compare with public datasets'",
      "If nothing concrete comes to mind for this cluster, return ''.",
      sep = "\n"
    )
  } else ""

  followup_schema_field <- if (isTRUE(suggest_followups)) {
    ',\n "followup": "<1-2 concrete sentences or empty string>"'
  } else ""

  system_prompt <- paste(
    sprintf("You are an expert single-cell biologist annotating a sub-cluster within the BROAD LINEAGE: %s.",
            broad),
    sprintf("Tissue context: %s. Detected gene-symbol convention in input: %s.",
            tissue, species),
    "Gene symbols may be human (CD8A) or mouse (Cd8a) — interpret accordingly.",
    data_context_str,
    "",
    "------ Approach ------",
    sprintf("This sub-cluster was carved out of a %s subset by re-clustering.", broad),
    "The markers below are FROM the lineage subset only — they describe",
    "how this sub-cluster differs from OTHER sub-clusters of the same",
    "broad lineage, NOT how it differs from all cells. So expect markers",
    "to look like fine-grained lineage-internal differences (cytotoxic",
    "vs naive vs proliferating), not lineage-defining markers.",
    "",
    "Your task is to identify the most likely SUB-TYPE within this lineage.",
    "",
    sprintf("Typical sub-types within '%s' (examples — not a whitelist):", broad),
    vocab_examples,
    "",
    "------ What is NOT contamination ------",
    "These are common sources of lineage-foreign-LOOKING markers that",
    "do NOT indicate true contamination:",
    "",
    ambient_str,
    "",
    stress_str,
    "",
    "Lineage-INTERNAL terminal differentiation states are NEVER contaminants:",
    "  - Plasma cell, plasmablast, GC B cell, regulatory B  → all are B sub-types,",
    "    label as themselves (e.g. 'plasma cell'), NEVER 'B (contaminant: plasma cell)'",
    "  - NK cell, NKT, MAIT, gamma-delta T  → all are T/NK members,",
    "    label as themselves, NEVER 'T/NK (contaminant: NK)'",
    "  - Kupffer cell (liver), alveolar macrophage (lung), microglia (brain)",
    "    → tissue-resident myeloid sub-types in the right tissue, NEVER contaminants",
    "  - Tumour-derived cells in their own broad lineage (e.g. dysplastic hepatocyte",
    "    in a hepatocyte subset) → just a sub-type, not contamination",
    "",
    "------ TRUE contamination ------",
    sprintf("Use the label format \"%s (contaminant: <true type>)\" ONLY when ALL of:", broad),
    "  - You can name >=3 canonical lineage-defining genes for the OTHER lineage",
    "  - Each is highly specific (avg_log2FC > 1.5, ideally pct.1 - pct.2 > 0.3)",
    "  - None of those genes are on the ambient OR stress lists above",
    "  - The OTHER lineage is genuinely a different broad cell type",
    "    (NOT just a sub-state of the current lineage).",
    "Examples of TRUE contamination evidence:",
    "  - Mast in T/NK: TPSAB1 + TPSB2 + KIT + CPA3 + HDC (all specific, none ambient/stress)",
    "  - Epithelial in immune: KRT8 + KRT18 + KRT19 + EPCAM (NOT just ALB/SERPINA1!)",
    "  - True erythroid (not just ambient HBB): GYPA + HBE1 + ALAS2 + KLF1",
    "If markers fail any criterion, STAY IN-LINEAGE. Use a generic sub-type",
    sprintf("name or '%s (unspecified)' rather than over-calling contamination.",
            broad),
    "",
    "------ Proportion sanity check ------",
    sprintf("This sub-cluster has %d cells (%.1f%% of the %s subset).",
            n_cells, 100 * pct, broad),
    "Cross-check your candidate label against typical proportions:",
    proportion_guide,
    "",
    "If proportion is wildly off (e.g. >2x typical upper bound for that",
    "sub-type), the markers should be UNAMBIGUOUS for that sub-type",
    "(canonical lineage-defining receptor genes, not just shared",
    "effector signatures). If you keep the label despite proportion",
    "mismatch, mention this in `reasoning` and lower confidence to medium.",
    "",
    followup_block,
    "",
    "------ Output ------",
    "Use lower-case English, standard nomenclature.",
    "Reply with ONLY a JSON object, no prose, no markdown fences:",
    paste0(
      '{"label": "<sub-type or contaminant label>",\n',
      ' "confidence": "<low|medium|high>",\n',
      ' "reasoning": "<2-3 sentences citing key markers AND, when relevant, proportion or ambient checks>"',
      followup_schema_field, "\n}"
    ),
    sep = "\n"
  )

  marker_lines <- paste(
    sprintf("  %s (avg_log2FC=%.2f, pct.1=%.2f, pct.2=%.2f)",
            markers_df$gene, markers_df$avg_log2FC,
            markers_df$pct.1, markers_df$pct.2),
    collapse = "\n"
  )
  user_prompt <- paste0(
    sprintf("Tissue: %s. Broad lineage: %s. Sub-cluster id: %s.\n",
            tissue, broad, cluster_id),
    sprintf("This sub-cluster has %d cells (%.1f%% of the %s subset).\n\n",
            n_cells, 100 * pct, broad),
    "Top positive markers (sub-cluster vs. other sub-clusters of the same lineage):\n",
    marker_lines,
    "\n\nReturn JSON only."
  )

  parsed <- .call_with_retry(chat_fn, system_prompt, user_prompt,
                             max_retries = max_retries)
  list(
    label      = as.character(parsed$label %||% sprintf("%s (unannotated)", broad)),
    confidence = as.character(parsed$confidence %||% "low"),
    reasoning  = as.character(parsed$reasoning %||% "no reasoning"),
    followup   = if (isTRUE(suggest_followups))
      as.character(parsed$followup %||% "")
    else
      ""
  )
}


# Lineage-aware sub-type *examples* for the prompt. Not a whitelist.
# The LLM is told these are examples and may use any reasonable
# sub-type. Examples are tilted toward HCC / liver context but generic
# enough for most tumour and immune contexts.
.lineage_vocab_examples <- function(broad) {
  b <- tolower(broad)
  if (grepl("t[._/ ]?nk|^t$|tcell|^nk$", b)) {
    paste("  - CD8 effector / cytotoxic (GZMB, GZMK, PRF1, NKG7)",
          "  - CD8 memory / central memory (IL7R, CCR7, SELL)",
          "  - CD8 exhausted (HAVCR2, LAG3, PDCD1, TOX)",
          "  - CD4 naive (CCR7, SELL, LEF1)",
          "  - CD4 helper / Tfh (CXCL13, CD200, ICOS)",
          "  - Treg (FOXP3, IL2RA, CTLA4)",
          "  - NK cytotoxic (NKG7, KLRD1, FCGR3A)",
          "  - NK regulatory / tissue-resident (CD160, XCL1, GNLY low)",
          "  - NKT / MAIT (KLRB1, NCR3)",
          "  - gamma-delta T (TRGV/TRDV, KLRG1)",
          "  - proliferating T (MKI67, TOP2A)",
          sep = "\n")
  } else if (grepl("^b$|bcell|plasma", b)) {
    paste("  - naive B (IGHD, IGHM, FCER2, IL4R)",
          "  - memory B (CD27+ AICDA-, IGHA/G)",
          "  - germinal-center B (AICDA, BCL6, MEF2B)",
          "  - plasmablast (MKI67, IRF4, low CD20)",
          "  - plasma cell (MZB1, XBP1, JCHAIN, IGH high)",
          "  - regulatory B (IL10, TGFB1)",
          sep = "\n")
  } else if (grepl("myeloid|macrophage|monocyte|dc|kupffer", b)) {
    paste("  - classical monocyte (CD14, S100A8/9, FCN1)",
          "  - non-classical monocyte (FCGR3A, MS4A7, CDKN1C)",
          "  - cDC1 (CLEC9A, XCR1, IRF8)",
          "  - cDC2 (CLEC10A, CD1C, FCER1A)",
          "  - pDC (LILRA4, IRF7, GZMB)",
          "  - Kupffer cell (CD163, MARCO, VSIG4 — liver-specific)",
          "  - TAM M1-like (TNF, IL1B, NOS2-low)",
          "  - TAM M2-like (CD163, CD206/MRC1, TGFB1)",
          "  - SPP1+ TAM (SPP1, MARCO, GPNMB — common in HCC)",
          "  - proliferating myeloid (MKI67, TOP2A)",
          "  - neutrophil (FCGR3B, CXCR2, S100A12)",
          sep = "\n")
  } else if (grepl("hepatocyte|hep_", b)) {
    paste("  - periportal hepatocyte (HAL, ARG1, SDS, CYP2F2-like)",
          "  - pericentral hepatocyte (CYP2E1, GLUL, OAT)",
          "  - mid-zonal hepatocyte (intermediate)",
          "  - proliferating hepatocyte (MKI67, TOP2A)",
          "  - dysplastic / tumour hepatocyte (AFP, GPC3, abnormal CYP)",
          "  - stress-response / interferon-responsive hepatocyte (ISG15, IFI6, MX1)",
          "  - cholangiocyte-like (KRT19, KRT7) if mixed",
          sep = "\n")
  } else if (grepl("endo|endothel|lsec|^ec$", b)) {
    paste("  - liver sinusoidal EC / LSEC (STAB2, CLEC4G, FCN3)",
          "  - portal vein EC (RBP7, EFNB2)",
          "  - central vein EC (RSPO3, WNT2)",
          "  - capillary EC (PLVAP, RAMP3)",
          "  - lymphatic EC (PROX1, LYVE1, PDPN)",
          "  - tip EC / angiogenic (DLL4, ESM1, ANGPT2)",
          sep = "\n")
  } else if (grepl("fibro|stellate|caf|stroma", b)) {
    paste("  - quiescent hepatic stellate cell (RGS5, DES, low ACTA2)",
          "  - activated stellate / myofibroblast (ACTA2, COL1A1, COL3A1)",
          "  - portal fibroblast (ELN, MFAP4)",
          "  - inflammatory CAF / iCAF (IL6, CXCL12, CXCL14)",
          "  - myofibroblastic CAF / myCAF (ACTA2 high, TAGLN, MMP11)",
          "  - antigen-presenting CAF / apCAF (HLA-DR genes, CD74)",
          sep = "\n")
  } else {
    sprintf("  - (no built-in examples for '%s'; use markers and tissue context)",
            broad)
  }
}


# Typical proportion ranges for sub-types within a broad lineage.
# Used in the LLM prompt as a sanity check — see the "PROPORTION SANITY
# CHECK" block. These are tumour-context defaults (HCC and similar
# solid tumours); biology varies by tissue and disease, so the prompt
# describes them as guides, not laws. A grossly-off proportion is a
# signal for the LLM to re-examine markers, not to silently rewrite
# the label.
.lineage_proportion_guide <- function(broad) {
  b <- tolower(broad)
  if (grepl("t[._/ ]?nk|^t$|tcell|^nk$", b)) {
    paste("  - CD8 effector / cytotoxic: 20-50% of T/NK",
          "  - CD8 memory / central memory: 5-25%",
          "  - CD8 exhausted (HAVCR2/LAG3/TOX+): 5-30% in tumour",
          "  - CD4 naive: 5-20%",
          "  - CD4 helper / Tfh: 2-15%",
          "  - Treg: 5-20%",
          "  - NK cytotoxic: 10-25%",
          "  - NK regulatory / tissue-resident: 1-10%",
          "  - NKT / MAIT: 1-10%",
          "  - gamma-delta T: usually 1-5% (rarely >10%)",
          "  - proliferating T: 2-10%",
          sep = "\n")
  } else if (grepl("^b$|bcell|plasma", b)) {
    paste("  - naive B: 30-60% of B subset",
          "  - memory B: 20-40%",
          "  - germinal-center B: variable, often 0-10%",
          "  - plasmablast: 1-15%",
          "  - plasma cell: 5-30% (higher in tumour-adjacent or inflamed tissue)",
          "  - regulatory B: usually <5%",
          sep = "\n")
  } else if (grepl("myeloid|macrophage|monocyte|dc|kupffer", b)) {
    paste("  - TAM (M2-like, SPP1+, CD163+): 30-60% in tumour",
          "  - classical monocyte: 10-30%",
          "  - non-classical monocyte: 2-15%",
          "  - cDC1: 0.5-3%",
          "  - cDC2: 2-10%",
          "  - pDC: 0.5-3%",
          "  - Kupffer cell: 5-30% in liver tissue (variable in HCC)",
          "  - neutrophil: 1-15%",
          "  - proliferating myeloid: 1-8%",
          sep = "\n")
  } else if (grepl("hepatocyte|hep_", b)) {
    paste("  - dysplastic / tumour hepatocyte: 30-90% in HCC tumour",
          "  - periportal hepatocyte: 5-30% (decreases in tumour)",
          "  - pericentral hepatocyte: 5-30% (decreases in tumour)",
          "  - mid-zonal: 5-20%",
          "  - proliferating hepatocyte: 2-15%",
          "  - stress / interferon-responsive: 1-15%",
          sep = "\n")
  } else if (grepl("endo|endothel|lsec|^ec$", b)) {
    paste("  - LSEC: 50-80% in liver tissue",
          "  - portal vein EC: 5-20%",
          "  - central vein EC: 5-15%",
          "  - capillary EC: 5-20%",
          "  - tip / angiogenic EC: 1-15% (higher in tumour)",
          "  - lymphatic EC: 0.5-5%",
          sep = "\n")
  } else if (grepl("fibro|stellate|caf|stroma", b)) {
    paste("  - quiescent stellate: 20-50% in non-tumour liver",
          "  - activated stellate / myofibroblast: 30-70% in HCC",
          "  - portal fibroblast: 5-25%",
          "  - iCAF: 10-30% in tumour",
          "  - myCAF: 10-40% in tumour",
          "  - apCAF: 1-10%",
          sep = "\n")
  } else {
    sprintf("  (no built-in proportion guide for '%s'; use markers as primary evidence)",
            broad)
  }
}


# ─────────────────────────────────────────────────────────────────────────
# v0.1.22: tissue-aware ambient gene lists. Added because v0.1.21 prompt
# baked HCC-specific ambient genes (ALB, SERPINA1, AFP) into the system
# prompt as global, which is wrong for non-liver tissue. With this
# helper, the prompt only flags as ambient those genes that are
# plausibly contaminating in the user's actual tissue.
#
# Returns a character vector of HUMAN gene symbols. Mouse equivalents
# (sentence case) are added by the prompt builder. Empty vector if the
# tissue string doesn't match any built-in pattern — in that case the
# prompt falls back to a generic "be cautious of dominant lineage
# transcripts" note.
# ─────────────────────────────────────────────────────────────────────────
.tissue_ambient_genes <- function(tissue) {
  t <- tolower(as.character(tissue %||% ""))

  # Tissue-specific abundant transcripts that frequently show up as
  # ambient RNA in tumour scRNA-seq and confuse downstream analysis.
  liver <- c("ALB","SERPINA1","APOA1","APOA2","APOB","APOC1","APOC3",
             "APOE","AFP","ORM1","ORM2","FGA","FGB","FGG","TF","TTR",
             "HP","HPX","GC","ITIH1","ITIH2","SAA1","SAA2","C3","C9")
  blood <- c("HBB","HBA1","HBA2","HBG1","HBG2","HBE1","HBM","ALAS2","BPGM")
  pancreas <- c("PRSS1","PRSS2","PRSS3","CTRB1","CTRB2","CELA1","CELA2A",
                "CELA3A","CELA3B","CPA1","CPA2","CPB1","AMY2A","AMY2B",
                "PNLIP","CLPS","REG1A","REG1B","REG3A")
  lung <- c("SFTPA1","SFTPA2","SFTPB","SFTPC","SFTPD","SCGB1A1","SCGB3A1",
            "SCGB3A2","NAPSA","SLPI")
  breast <- c("CSN1S1","CSN2","CSN3","LALBA","WAP","BTN1A1","MFGE8")
  stomach <- c("PGA3","PGA4","PGA5","PGC","GKN1","GKN2","LIPF","GIF",
               "MUC5AC","MUC6","TFF1","TFF2")
  intestine <- c("MUC2","TFF3","REG3A","REG3G","DEFA5","DEFA6","FABP1",
                 "FABP2","RBP2","KRT20","CA1","CA2")
  kidney <- c("SLC12A1","SLC12A3","UMOD","NPHS1","NPHS2","PODXL","ALB",
              "AQP1","AQP2","AQP3","AQP4")
  brain <- c("MBP","MOG","PLP1","GFAP","SNAP25","SYP","STMN2")
  prostate <- c("KLK3","KLK2","ACPP","NKX3-1","AR")
  skin <- c("KRT1","KRT5","KRT10","KRT14","LOR","FLG","DSG3","DSP","KRT15")

  hits <- character(0)
  if (grepl("liver|hcc|hepato|biliary|cholangi", t)) hits <- c(hits, liver)
  if (grepl("liver|spleen|bone[ _-]?marrow|blood|pbmc|lymph", t))
    hits <- c(hits, blood)
  if (grepl("pancrea", t)) hits <- c(hits, pancreas)
  if (grepl("lung|pulmonary|nsclc|airway|bronch", t)) hits <- c(hits, lung)
  if (grepl("breast|mamm|brca", t)) hits <- c(hits, breast)
  if (grepl("stomach|gastric", t)) hits <- c(hits, stomach)
  if (grepl("intestin|colon|gut|crc|ileum|cecum|rect", t))
    hits <- c(hits, intestine)
  if (grepl("kidney|renal|ccrcc", t)) hits <- c(hits, kidney)
  if (grepl("brain|glio|cortex|cereb", t)) hits <- c(hits, brain)
  if (grepl("prostate", t)) hits <- c(hits, prostate)
  if (grepl("skin|melan|epiderm", t)) hits <- c(hits, skin)
  unique(hits)
}


# Detect species from a sample of gene symbols. Human convention: all
# upper-case (CD8A); mouse convention: sentence case (Cd8a). Returns
# "human", "mouse", or "unknown".
.detect_species_from_markers <- function(markers_genes) {
  s <- markers_genes
  s <- s[!grepl("^ENS", s, ignore.case = FALSE)]   # drop Ensembl IDs
  s <- s[nchar(s) > 1]
  s <- utils::head(s, 200)
  if (length(s) == 0) return("unknown")
  n_upper <- sum(s == toupper(s))
  n_sentence <- sum(nchar(s) > 1 &
                    substr(s, 1, 1) == toupper(substr(s, 1, 1)) &
                    substring(s, 2) == tolower(substring(s, 2)))
  if (n_upper / length(s) > 0.7) "human"
  else if (n_sentence / length(s) > 0.5) "mouse"
  else "unknown"
}


# Cross-species, tissue-aware proportion guide. v0.1.22 supersedes the
# v0.1.21 version which had HCC-incorrect γδT range (1-5%) baked in.
.lineage_proportion_guide_v2 <- function(broad, tissue) {
  b <- tolower(broad)
  t <- tolower(as.character(tissue %||% ""))
  is_liver <- grepl("liver|hcc|hepato", t)
  if (grepl("t[._/ ]?nk|^t$|tcell|^nk$", b)) {
    gd_range <- if (is_liver) "5-25% (liver-resident enrichment)" else "1-5%"
    paste("  - CD8 effector / cytotoxic: 20-50% of T/NK",
          "  - CD8 memory / central memory: 5-25%",
          "  - CD8 exhausted (HAVCR2/LAG3/TOX+): 5-30% in tumour",
          "  - CD4 naive: 5-20%",
          "  - CD4 helper / Tfh: 2-15%",
          "  - Treg: 5-20% (often higher in tumour)",
          "  - NK cytotoxic: 10-25%",
          "  - NK regulatory / tissue-resident: 1-10%",
          "  - NKT / MAIT: 1-10%",
          sprintf("  - gamma-delta T: %s", gd_range),
          "  - proliferating T: 2-10%",
          sep = "\n")
  } else if (grepl("^b$|bcell|plasma", b)) {
    paste("  - naive B: 30-60% of B subset",
          "  - memory B: 20-40%",
          "  - germinal-center B: variable, often 0-10%",
          "  - plasmablast: 1-15%",
          "  - plasma cell: 5-30% (higher in tumour-adjacent or inflamed tissue)",
          "  - regulatory B: usually <5%",
          sep = "\n")
  } else if (grepl("myeloid|macrophage|monocyte|dc|kupffer", b)) {
    kc_line <- if (is_liver) "  - Kupffer cell: 5-30% (liver-resident)" else ""
    paste("  - TAM (M2-like, often SPP1+, CD163+): 20-60% in tumour",
          "  - classical monocyte: 5-30%",
          "  - non-classical monocyte: 2-15%",
          "  - cDC1: 0.5-3%",
          "  - cDC2: 2-10%",
          "  - pDC: 0.5-3%",
          kc_line,
          "  - neutrophil: 1-15%",
          "  - proliferating myeloid: 1-8%",
          sep = "\n")
  } else if (grepl("hepatocyte|hep_", b)) {
    paste("  - dysplastic / tumour hepatocyte: 30-90% of hepatocyte subset in HCC",
          "  - periportal hepatocyte: 5-30% (decreases in tumour)",
          "  - pericentral hepatocyte: 5-30% (decreases in tumour)",
          "  - mid-zonal: 5-20%",
          "  - proliferating hepatocyte: 2-15%",
          "  - stress / interferon-responsive: 1-15%",
          sep = "\n")
  } else if (grepl("endo|endothel|lsec|^ec$", b)) {
    lsec_line <- if (is_liver) "  - LSEC (STAB2/CLEC4G): 50-80% in liver" else ""
    paste(lsec_line,
          "  - tumour-associated EC / tip cell (DLL4, ESM1): 10-40% in tumour",
          "  - venous EC: 5-25%",
          "  - arterial EC: 5-15%",
          "  - capillary EC: 5-25%",
          "  - lymphatic EC: 0.5-5%",
          sep = "\n") |> sub("^\n", "", x = _)
  } else if (grepl("fibro|stellate|caf|stroma", b)) {
    qhsc_line <- if (is_liver) "  - quiescent stellate (RGS5+/DES+): 10-40% in non-tumour liver" else ""
    paste(qhsc_line,
          "  - activated stellate / myofibroblast: 30-70% in HCC",
          "  - portal fibroblast: 5-25%",
          "  - iCAF: 10-30% in tumour",
          "  - myCAF: 10-40% in tumour",
          "  - apCAF: 1-10%",
          sep = "\n") |> sub("^\n", "", x = _)
  } else {
    sprintf("  (no built-in proportion guide for '%s'; use markers as primary evidence)",
            broad)
  }
}


# Stress / dissociation / immediate-early signature genes. Both human
# and mouse symbols, since LLM may see either depending on the dataset.
# Used in the prompt as an "ambient/artifact" list — finding these in
# a sub-cluster's markers does NOT imply cross-lineage contamination,
# only stress.
.stress_genes_both_species <- function() {
  c(
    # Heat-shock - human
    "HSPA1A","HSPA1B","HSPA6","HSPB1","HSPH1","HSP90AA1","HSP90AB1",
    "HSPE1","HSPD1","DNAJB1","DNAJB6","FKBP4","CACYBP","BAG3",
    # Heat-shock - mouse
    "Hspa1a","Hspa1b","Hspb1","Hsph1","Hsp90aa1","Hspe1","Dnajb1",
    "Fkbp4","Cacybp",
    # Immediate early - human
    "FOS","JUN","JUNB","FOSB","EGR1","EGR2","EGR3",
    "NR4A1","NR4A2","NR4A3","DUSP1","DUSP2","ATF3","IER2","IER3",
    # Immediate early - mouse
    "Fos","Jun","Junb","Fosb","Egr1","Egr2","Nr4a1","Nr4a2",
    "Dusp1","Atf3","Ier2","Ier3"
  )
}
