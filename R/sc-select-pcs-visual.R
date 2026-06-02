#' Pick the number of PCs by visually comparing UMAPs (LLM with vision)
#'
#' Generates UMAP panels at several candidate dimensionalities, asks a
#' vision-capable LLM which one gives the cleanest cluster separation,
#' and writes the chosen `ndim` to `obj@@params$ndim` so downstream
#' steps (Harmony, UMAP, FindNeighbors) consume it automatically.
#'
#' Two ways to specify candidates (mutually exclusive):
#' \itemize{
#'   \item \strong{Variance-driven (recommended)}: pass
#'     `variance_thresholds = c(0.80, 0.85, 0.90)`. The function
#'     computes the smallest `ndim` whose cumulative explained variance
#'     reaches each threshold, deduplicates, and uses those. Panel
#'     titles read "variance >= 80% (ndim=27)" -- meaningful to a
#'     biologist thinking in signal-to-noise terms.
#'   \item \strong{Manual}: pass `candidates = c(20, 30, 40, 50)`.
#'     Panel titles read "ndim = 30".
#' }
#' If neither argument is given, defaults to
#' `variance_thresholds = c(0.80, 0.85, 0.90)`.
#'
#' Requires a vision-capable `chat_fn` ([chat_grok()], [chat_claude()],
#' [chat_openai()] with a 4o-class model). Text-only chat_fn (DeepSeek)
#' will silently ignore the image and the LLM will be guessing.
#'
#' @param obj An AgentSeurat with PCA computed (stage >= "pca_done").
#' @param chat_fn A vision-capable chat_fn.
#' @param variance_thresholds Numeric vector in (0, 1). Cumulative
#'   variance fractions to convert into ndim values. Default
#'   `c(0.80, 0.85, 0.90)`.
#' @param candidates Optional integer vector of explicit ndim values.
#'   If provided, overrides `variance_thresholds`.
#' @param tissue Optional tissue/condition string to give the LLM
#'   biological context. Recommended.
#' @param batch_var Optional metadata column to colour panels by. If
#'   NULL, uses `obj@@params$batch_recommendation$recommended` if set,
#'   otherwise computes a temporary leiden clustering at res 0.5.
#' @param out_dir Where to save panels. Default
#'   `"figures/select_pcs_visual"`.
#' @param panel_width,panel_height,panel_dpi PNG sizing per-panel.
#' @param max_retries Integer. JSON-parse retry count.
#' @param rationale Optional override.
#'
#' @return Updated AgentSeurat. Recommendation lives at
#'   `obj@@params$pcs_visual_recommendation` with fields:
#'   `chosen` (integer ndim),
#'   `chosen_variance` (cumulative variance fraction at chosen ndim),
#'   `confidence`, `reasoning`, `candidates_compared` (data frame of
#'   ndim and variance for each panel),
#'   `panel_path`. Chosen ndim is also written to `obj@@params$ndim`.
#' @export
sc_select_pcs_visual <- function(obj,
                                 chat_fn,
                                 variance_thresholds = NULL,
                                 candidates          = NULL,
                                 tissue              = "single-cell RNA-seq dataset",
                                 batch_var           = NULL,
                                 out_dir             = "figures/select_pcs_visual",
                                 panel_width         = 6,
                                 panel_height        = 5,
                                 panel_dpi           = 130,
                                 max_retries         = 1,
                                 rationale           = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("sc_select_pcs_visual expects a single Seurat object.")
  }
  if (!"pca" %in% names(obj@data@reductions)) {
    stop("PCA not found. Run sc_pca() first.")
  }

  # v0.2.0: snapshot token state at entry for per-step accounting
  .tok_before <- length(.token_state$records)

  # Pull stdev to compute cumulative variance
  pca_obj <- obj@data[["pca"]]
  stdev   <- pca_obj@stdev
  if (length(stdev) == 0) stop("PCA stdev empty; rerun sc_pca().")
  var_each <- stdev^2 / sum(stdev^2)
  cum_var  <- cumsum(var_each)
  max_pc   <- length(stdev)

  # Resolve candidate ndim values
  variance_mode <- FALSE
  if (!is.null(variance_thresholds) && !is.null(candidates)) {
    stop("Pass either `variance_thresholds` or `candidates`, not both.")
  }
  if (is.null(variance_thresholds) && is.null(candidates)) {
    variance_thresholds <- c(0.80, 0.85, 0.90)
  }
  if (!is.null(variance_thresholds)) {
    variance_mode <- TRUE
    if (any(variance_thresholds <= 0 | variance_thresholds >= 1)) {
      stop("variance_thresholds must be in (0, 1).")
    }
    variance_thresholds <- sort(unique(variance_thresholds))
    candidates_int <- vapply(variance_thresholds, function(t) {
      idx <- which(cum_var >= t)
      if (length(idx) == 0) max_pc else idx[1]
    }, integer(1))
    # Dedup: if 80% and 85% land on the same ndim, only run UMAP once
    keep <- !duplicated(candidates_int)
    candidates_int        <- candidates_int[keep]
    variance_thresholds   <- variance_thresholds[keep]
    candidates_actual_var <- cum_var[candidates_int]
    if (length(candidates_int) < 2) {
      stop("After deduplication only 1 candidate ndim remains. ",
           "Spread your variance_thresholds wider, or pass `candidates` directly.")
    }
  } else {
    candidates_int <- sort(unique(as.integer(candidates)))
    if (length(candidates_int) < 2) {
      stop("Need at least 2 candidate ndim values to compare.")
    }
    if (max(candidates_int) > max_pc) {
      stop(sprintf("Largest candidate ndim (%d) exceeds available PCs (%d). ",
                   max(candidates_int), max_pc),
           "Re-run sc_pca(npcs = ...) with more components, or trim `candidates`.")
    }
    candidates_actual_var <- cum_var[candidates_int]
    variance_thresholds   <- candidates_actual_var
  }

  panels_meta <- data.frame(
    ndim     = candidates_int,
    variance = round(candidates_actual_var, 3),
    label    = if (variance_mode) {
      sprintf("variance >= %d%% (ndim=%d)",
              round(100 * variance_thresholds), candidates_int)
    } else {
      sprintf("ndim=%d (variance=%d%%)",
              candidates_int, round(100 * candidates_actual_var))
    },
    stringsAsFactors = FALSE
  )

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Decide colour-by group
  meta <- obj@data@meta.data
  if (is.null(batch_var)) {
    batch_var <- obj@params$batch_recommendation$recommended
  }
  if (!is.null(batch_var) && !batch_var %in% colnames(meta)) {
    warning(sprintf("batch_var '%s' not in metadata; falling back to a temporary pre-cluster.",
                    batch_var))
    batch_var <- NULL
  }

  # If no group column, do a one-shot louvain at res 0.5 (temp, on side copy)
  side <- obj@data
  if (is.null(batch_var)) {
    side <- Seurat::FindNeighbors(side, dims = seq_len(min(30, max_pc)),
                                  verbose = FALSE)
    side <- Seurat::FindClusters(side, resolution = 0.5, verbose = FALSE)
    color_col <- "seurat_clusters"
  } else {
    color_col <- batch_var
  }

  # Build per-panel UMAP PNGs
  panel_paths <- character(nrow(panels_meta))
  for (i in seq_len(nrow(panels_meta))) {
    n <- panels_meta$ndim[i]
    label <- panels_meta$label[i]
    seu <- Seurat::RunUMAP(side, dims = seq_len(n),
                           reduction.name = sprintf("umap_%d", n),
                           verbose = FALSE)
    p <- Seurat::DimPlot(seu,
                         reduction = sprintf("umap_%d", n),
                         group.by  = color_col,
                         pt.size   = 0.3,
                         label     = (color_col == "seurat_clusters")) +
         ggplot2::theme_classic() +
         ggplot2::ggtitle(label)
    path <- file.path(out_dir, sprintf("umap_panel_%d.png", n))
    ggplot2::ggsave(path, p,
                    width = panel_width, height = panel_height,
                    dpi = panel_dpi)
    panel_paths[[i]] <- path
  }

  # Compose into one combined image
  combined_path <- file.path(out_dir, "umap_panel_compare.png")
  .compose_panel_grid_safe(panel_paths, combined_path,
                           panel_width = panel_width,
                           panel_height = panel_height,
                           dpi = panel_dpi)

  # ---- LLM call ----
  axis_word <- if (variance_mode) "variance threshold" else "number of PCs"
  system_prompt <- paste(
    "You are an expert single-cell RNA-seq analyst evaluating UMAP",
    "embeddings produced from different PCA dimensionalities.",
    sprintf("The panels vary by %s, with each panel labeled.", axis_word),
    "Your job: pick the option that gives the cleanest cluster structure",
    "for downstream analysis (graph clustering, annotation).",
    "",
    "Criteria, in priority order:",
    "(1) Major cell-type clusters are tightly grouped, with little stringy",
    "    'bridging' between unrelated populations.",
    "(2) Clusters are biologically separable: visually distinct groups,",
    "    neither over-merged nor over-fragmented.",
    "(3) Information vs. noise tradeoff: a higher variance threshold (or",
    "    more PCs) keeps more signal but may introduce noisy elongated",
    "    tendrils or unsupported micro-structure; a lower threshold may",
    "    under-resolve real subpopulations. Pick the one where this",
    "    tradeoff visually looks best.",
    "(4) If two candidates look comparably clean, prefer the LOWER one",
    "    (more parsimonious; faster downstream).",
    "",
    "Reply with ONLY a JSON object. No prose, no markdown, no commentary.",
    "Schema:",
    sprintf('{"chosen_ndim": <one of %s>,',
            paste(panels_meta$ndim, collapse = " | ")),
    ' "confidence": "low" | "medium" | "high",',
    ' "reasoning": "<2-4 sentences referencing what you see in each panel>"}',
    sep = "\n"
  )

  panel_summary <- paste(
    sprintf("  - Panel '%s' -> ndim = %d",
            panels_meta$label, panels_meta$ndim),
    collapse = "\n"
  )
  user_prompt <- sprintf(paste(
    "Tissue context: %s.",
    "Compare these UMAPs and return JSON only.",
    "Panels you are looking at (in order shown):",
    "%s",
    "",
    "Pick the BEST panel and report its ndim integer in `chosen_ndim`.",
    sep = "\n"
  ), tissue, panel_summary)

  if (isTRUE(getOption("scAgentKit.verbose", TRUE))) {
    message(sprintf("[sc_select_pcs_visual] sending %d-panel comparison to LLM (image: %s)",
                    nrow(panels_meta), combined_path))
  }

  parsed <- .call_with_retry(chat_fn, system_prompt, user_prompt,
                             max_retries = max_retries,
                             image_path  = combined_path)

  chosen <- as.integer(parsed$chosen_ndim %||% parsed$chosen %||% NA_integer_)
  if (is.na(chosen) || !chosen %in% panels_meta$ndim) {
    warning(sprintf("LLM returned chosen=%s which is not in candidates (%s). ",
                    parsed$chosen_ndim %||% parsed$chosen,
                    paste(panels_meta$ndim, collapse = ",")),
            "Falling back to median candidate.")
    chosen <- panels_meta$ndim[ceiling(nrow(panels_meta) / 2)]
  }
  chosen_var <- panels_meta$variance[panels_meta$ndim == chosen][1]

  recommendation <- list(
    chosen              = chosen,
    chosen_variance     = chosen_var,
    confidence          = parsed$confidence,
    reasoning           = parsed$reasoning,
    candidates_compared = panels_meta,
    panel_path          = combined_path
  )

  obj@params$ndim                       <- chosen
  obj@params$pcs_visual_recommendation  <- recommendation

  obj <- .record_figure(
    obj,
    step        = "sc_select_pcs_visual",
    path        = combined_path,
    description = sprintf("UMAP panels at %s; LLM chose ndim=%d (variance %.0f%%, %s confidence).",
                          paste(panels_meta$label, collapse = " | "),
                          chosen, 100 * chosen_var, parsed$confidence)
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Visual ndim selection: panels at %s. LLM chose ndim=%d (variance %.1f%%; %s confidence). %s",
      paste(panels_meta$label, collapse = ", "),
      chosen, 100 * chosen_var, parsed$confidence, parsed$reasoning
    )
  }
  script <- sprintf(
'# ---- Visual PC selection (LLM compared UMAPs at %s) ----
# Chosen ndim = %d (variance = %.1f%%). See obj@params$pcs_visual_recommendation.',
    paste(panels_meta$label, collapse = ", "),
    chosen, 100 * chosen_var
  )

  obj <- .record_step(
    obj            = obj,
    step_name      = "sc_select_pcs_visual",
    function_name  = "sc_select_pcs_visual",
    params         = list(
      mode                = if (variance_mode) "variance" else "manual",
      candidates_compared = panels_meta$ndim,
      variance_at_each    = panels_meta$variance,
      chosen              = chosen,
      chosen_variance     = chosen_var,
      confidence          = parsed$confidence
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "pcs_selected"
  )
  .attach_step_tokens(obj, "sc_select_pcs_visual", .tok_before)
}

# Helper: NULL-coalesce
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# Robust panel composition that does NOT require ImageMagick.
#
# Strategy:
# 1. Try `magick::image_read` + `image_montage` (highest quality).
# 2. If that fails for ANY reason, fall back to grDevices::png + base
#    graphics rasterImage (always works as long as the png package is
#    available, which it is in base R).
# 3. If even that fails (vanishingly unlikely), fall back to copying
#    the first panel as the "combined" image so the LLM at least sees
#    one panel.
.compose_panel_grid_safe <- function(paths, out_path,
                                     panel_width, panel_height, dpi) {
  n <- length(paths)
  if (n == 1) {
    file.copy(paths[[1]], out_path, overwrite = TRUE)
    return(invisible(out_path))
  }

  cols <- if (n <= 2) n else 2L
  rows <- as.integer(ceiling(n / cols))

  # Attempt 1: magick (best quality if it works)
  if (requireNamespace("magick", quietly = TRUE)) {
    ok <- tryCatch({
      imgs <- magick::image_read(paths)        # vector input avoids image_join
      grid <- magick::image_montage(
        imgs,
        tile     = sprintf("%dx%d", cols, rows),
        geometry = "x600+10+10"
      )
      magick::image_write(grid, out_path)
      TRUE
    }, error = function(e) {
      message("[sc_select_pcs_visual] magick path failed (",
              conditionMessage(e),
              "); falling back to base R compositing.")
      FALSE
    })
    if (ok) return(invisible(out_path))
  }

  # Attempt 2: png + base graphics
  ok <- tryCatch({
    if (!requireNamespace("png", quietly = TRUE)) {
      stop("Package 'png' is required as a fallback. install.packages('png').")
    }
    grDevices::png(out_path,
                   width  = panel_width  * cols * dpi,
                   height = panel_height * rows * dpi,
                   res    = dpi)
    op <- graphics::par(mfrow = c(rows, cols), mar = c(0, 0, 0, 0))
    on.exit({graphics::par(op); grDevices::dev.off()}, add = TRUE)
    for (p in paths) {
      img <- png::readPNG(p)
      graphics::plot.new()
      graphics::plot.window(c(0, 1), c(0, 1),
                            asp = panel_height / panel_width)
      graphics::rasterImage(img, 0, 0, 1, 1)
    }
    TRUE
  }, error = function(e) {
    message("[sc_select_pcs_visual] base-R compositing also failed (",
            conditionMessage(e), "); using first panel as fallback.")
    FALSE
  })
  if (ok) return(invisible(out_path))

  # Attempt 3: copy first panel
  file.copy(paths[[1]], out_path, overwrite = TRUE)
  invisible(out_path)
}
