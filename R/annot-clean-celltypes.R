#' Clean and filter cell type annotations (with optional vision judgment)
#'
#' Merges singular/plural variants and marks small cell-type groups for review.
#' Small size alone does not establish contamination. Optional vision advice
#' can reduce the caller's requested action, but cannot authorize deletion.
#'
#' @param obj An AgentSeurat object after [annot_apply()].
#' @param merge_plural Logical. Merge singular/plural names
#'   (Macrophages -> Macrophage, T cells -> T cell, etc.). Default TRUE.
#' @param min_cells Integer. Clusters with fewer than this many cells
#'   are considered low-quality. Default 50.
#' @param action Character. What to do with low-quality clusters:
#'   `"flag"` (default), `"remove"`, or `"keep"`. Only an explicit
#'   `action = "remove"` permits cell removal. Vision advice cannot escalate
#'   `"keep"` to `"flag"` or either retaining action to `"remove"`.
#' @param vision Logical. If TRUE, generate UMAP and ask vision-capable LLM
#'   to judge whether small clusters are real or contaminants.
#' @param chat_fn Vision-capable function accepting `system_prompt`,
#'   `user_prompt`, and `image_path` (required when `vision = TRUE`). It must
#'   return a JSON object with exactly two fields: `decision` (one of
#'   `"flag"`, `"remove"`, `"keep"`) and nonempty string `reasoning`.
#' @param tissue Tissue context passed to LLM (e.g. "mouse colorectal cancer").
#' @param rationale Optional custom rationale string.
#'
#' @details `cell_type_quality` is `"normal"` for groups meeting the size
#'   threshold, `"candidate"` for retained small groups, and `"flagged"` when
#'   the final action is `"flag"`. These are review states, not validated
#'   biological quality labels. A vision recommendation applies to all small
#'   groups; heterogeneous groups should be reviewed individually.
#'
#' @return Updated AgentSeurat with cleaned `cell_type` and
#'   `cell_type_quality` columns. Calls and their final actions are recorded
#'   in the decision log, including raw vision responses and validation
#'   failures. Vision or removal failures keep all cells. Generated scripts
#'   replay the saved result without another model call.
#' @export
annot_clean_celltypes <- function(obj,
                                  merge_plural = TRUE,
                                  min_cells    = 50,
                                  action       = c("flag", "remove", "keep"),
                                  vision       = FALSE,
                                  chat_fn      = NULL,
                                  tissue       = NULL,
                                  rationale    = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  action <- match.arg(action)
  requested_action <- action
  if (!is.numeric(min_cells) || length(min_cells) != 1L ||
      is.na(min_cells) || !is.finite(min_cells) || min_cells < 1 ||
      min_cells != floor(min_cells)) {
    stop("`min_cells` must be a positive integer.")
  }
  if (!is.logical(merge_plural) || length(merge_plural) != 1L ||
      is.na(merge_plural) || !is.logical(vision) || length(vision) != 1L ||
      is.na(vision)) {
    stop("`merge_plural` and `vision` must be single, nonmissing logical values.")
  }
  if (vision && !is.function(chat_fn)) {
    stop("`chat_fn` must be a function when vision = TRUE.")
  }

  if (!"cell_type" %in% colnames(obj@data@meta.data)) {
    stop("`cell_type` column not found. Run annot_apply() first.")
  }

  meta <- obj@data@meta.data
  ct   <- as.character(meta$cell_type)
  n_before <- ncol(obj@data)
  input_cell_ids <- colnames(obj@data)
  vision_result <- list(status = if (vision) "no_candidates" else "not_requested",
                        raw_response = NULL, decision = NULL,
                        reasoning = NULL, error = NULL, image_path = NULL,
                        system_prompt = NULL, user_prompt = NULL)
  removal_error <- NULL

  # ====================== 1. Merge singular/plural naming ======================
  if (isTRUE(merge_plural)) {
    ct <- gsub("s$", "", ct)
    ct <- gsub(" cells$", " cell", ct)
    ct <- gsub("Macrophages", "Macrophage", ct)
    ct <- gsub("T cells", "T cell", ct)
    ct <- gsub("B cells", "B cell", ct)
    ct <- gsub("Neutrophils", "Neutrophil", ct)
    ct <- gsub("Fibroblasts", "Fibroblast", ct)
    message("[annot_clean_celltypes] Merged singular/plural names.")
  }

  # ====================== 2. Identify low-quality cluster ======================
  cell_counts <- table(ct)
  small_types <- names(cell_counts[cell_counts < min_cells])

  if (length(small_types) == 0) {
    message("[annot_clean_celltypes] No low-quality clusters found.")
  }

  # ====================== 3. Vision judgment (core new addition) ======================
  if (vision && length(small_types) > 0L) {
    message("[annot_clean_celltypes] Generating UMAP for vision judgment...")
    # Build prompt
    system_prompt <- paste(
      "You are an expert single-cell analyst. Look at the UMAP image.",
      "Red points are small cell-type groups requiring review.",
      "Small size and UMAP geometry alone do not establish contamination.",
      "Give one conservative recommendation for all highlighted groups.",
      "Use keep for real or uncertain rare groups; flag for further review.",
      "Removal remains subject to the analyst's explicit action setting.",
      "Return ONLY a JSON object with exactly two fields:",
      '"decision": a string, one of "flag", "remove", "keep";',
      '"reasoning": a nonempty string explaining the recommendation.'
    )

    user_prompt <- sprintf(
      "Tissue: %s. There are %d small cell-type groups (red): %s.",
      tissue %||% "unknown", length(small_types), paste(small_types, collapse = ", ")
    )

    # Validate the task-specific object; never inspect reasoning for actions.
    vision_result$status <- "failed"
    vision_result$system_prompt <- system_prompt
    vision_result$user_prompt <- user_prompt
    parsed <- tryCatch(
      {
        vision_result$image_path <- .clean_celltypes_vision_image(obj, ct, small_types)
        raw <- chat_fn(system_prompt, user_prompt,
                       image_path = vision_result$image_path)
        vision_result$raw_response <- raw
        .parse_clean_celltypes_decision(raw)
      },
      error = function(e) {
        vision_result$error <<- conditionMessage(e)
        warning("Vision judgment failed; keeping cells: ", conditionMessage(e),
                call. = FALSE)
        NULL
      }
    )

    if (is.null(parsed)) {
      action <- "keep"
    } else {
      vision_result$status <- "succeeded"
      vision_result$decision <- parsed$decision
      vision_result$reasoning <- parsed$reasoning
      # The caller controls the maximum severity, including the deletion gate.
      severity <- c("keep", "flag", "remove")
      action <- severity[min(match(requested_action, severity),
                             match(parsed$decision, severity))]
      message(sprintf("[annot_clean_celltypes] LLM vision decision: %s", action))
    }
  }

  # ====================== 4. Execute final operation ======================
  quality <- ifelse(ct %in% small_types, "candidate", "normal")
  if (action == "flag") {
    quality[ct %in% small_types] <- "flagged"
    ct[ct %in% small_types] <- paste0(ct[ct %in% small_types], " (Low quality)")
    message(sprintf("[annot_clean_celltypes] Flagged %d low-quality types.", length(small_types)))
  } else if (action == "remove") {
    keep <- !(ct %in% small_types)
    retained <- tryCatch(
      {
        if (!any(keep)) stop("The requested action would remove every cell.")
        obj@data[, keep]
      },
      error = function(e) {
        removal_error <<- conditionMessage(e)
        warning("Cell removal failed; keeping cells: ", conditionMessage(e),
                call. = FALSE)
        NULL
      }
    )
    if (is.null(retained)) {
      action <- "keep"
    } else {
      obj@data <- retained
      ct <- ct[keep]
      quality <- quality[keep]
      message(sprintf("[annot_clean_celltypes] Removed %d low-quality types.", length(small_types)))
    }
  }

  obj@data@meta.data$cell_type <- ct
  obj@data@meta.data$cell_type_quality <- quality

  # Save cell IDs and final labels so exported scripts can replay offline.
  cell_ids <- colnames(obj@data)
  literal <- function(x) {
    paste(utils::capture.output(dput(x, control = c("keepNA", "keepInteger", "showAttributes"))),
          collapse = "\n")
  }
  script <- paste0(
    "# ---- Replay saved cell-type cleaning; no model call ----\n",
    "clean_input_cell_ids <- ", literal(input_cell_ids), "\n",
    "clean_cell_ids <- ", literal(cell_ids), "\n",
    "if (!setequal(clean_input_cell_ids, colnames(seurat_obj))) ",
    "stop(\"Replay input cell IDs differ from the saved input.\")\n",
    "seurat_obj <- seurat_obj[, clean_cell_ids]\n",
    "seurat_obj$cell_type <- ", literal(ct), "\n",
    "seurat_obj$cell_type_quality <- ", literal(quality)
  )

  # ====================== 5. Record decision ======================
  if (is.null(rationale)) {
    rationale <- sprintf(
      "Cleaned cell type names (merge_plural=%s). %s clusters with < %d cells (vision=%s).",
      merge_plural, action, min_cells, vision
    )
  }

  obj <- .record_step(
    obj            = obj,
    step_name      = "annot_clean_celltypes",
    function_name  = "annot_clean_celltypes",
    params         = list(merge_plural = merge_plural,
                          min_cells    = min_cells,
                          action       = action,
                          requested_action = requested_action,
                          vision       = vision,
                          vision_result = vision_result,
                          removal_error = removal_error,
                          candidate_types = small_types,
                          removed_cell_ids = setdiff(input_cell_ids, cell_ids),
                          retained_cell_ids = cell_ids,
                          cleaning_result = data.frame(
                            cell_id = cell_ids, cell_type = ct,
                            cell_type_quality = quality, stringsAsFactors = FALSE
                          ),
                          n_cells_before = n_before,
                          n_cells_after = ncol(obj@data)),
    rationale      = rationale,
    script_snippet = script,
    success        = vision_result$status != "failed" && is.null(removal_error)
  )

  obj
}

# Strict schema for this task. Keep explanatory text separate from the action.
.parse_clean_celltypes_decision <- function(raw) {
  if (!is.character(raw) || length(raw) != 1L || is.na(raw) ||
      !nzchar(trimws(raw)) || !startsWith(trimws(raw), "{")) {
    stop("Vision response must be a single JSON object string.")
  }
  parsed <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
  if (!is.list(parsed) || is.null(names(parsed)) ||
      length(parsed) != 2L || anyDuplicated(names(parsed)) ||
      !setequal(names(parsed), c("decision", "reasoning"))) {
    stop("Vision JSON must contain exactly `decision` and `reasoning`.")
  }
  is_string <- function(x) {
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
  }
  if (!is_string(parsed$decision) ||
      !parsed$decision %in% c("flag", "remove", "keep")) {
    stop("Vision `decision` must be one of `flag`, `remove`, or `keep`.")
  }
  if (!is_string(parsed$reasoning)) {
    stop("Vision `reasoning` must be a nonempty string.")
  }
  parsed
}

# Plot a temporary metadata view without leaving helper columns in the result.
.clean_celltypes_vision_image <- function(obj, ct, small_types) {
  seu <- obj@data
  seu$quality_highlight <- ifelse(ct %in% small_types,
                                 "Low quality candidate", "Normal")
  p <- Seurat::DimPlot(seu, reduction = "umap", group.by = "quality_highlight",
                       pt.size = 0.4,
                       cols = c("Low quality candidate" = "red", "Normal" = "grey80")) +
    ggplot2::ggtitle("Small cell-type groups (red) for review") +
    ggplot2::theme_classic()
  dir.create("figures", showWarnings = FALSE)
  vision_path <- tempfile("low_quality_clusters_", tmpdir = "figures", fileext = ".png")
  ggplot2::ggsave(vision_path, p, width = 8, height = 6, dpi = 150)
  vision_path
}
