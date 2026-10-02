#' Apply annotations to the Seurat object
#'
#' Takes either the LLM annotation table produced by [annot_llm_annotate()]
#' or a manual `cluster_id -> cell_type` mapping, and writes a `cell_type`
#' metadata column to the underlying Seurat object. It can optionally remove
#' clusters whose LLM-produced `recommended_action` is `"reject"`.
#'
#' Manual overrides always win: a cluster listed in `manual_overrides` will
#' get the supplied label even if the LLM gave a different one.
#'
#' @param obj An AgentSeurat object.
#' @param source Character, one of `"llm"` (default, use
#'   `obj@@params$llm_annotations`) or `"manual"` (require `manual_overrides`
#'   to contain the full mapping).
#' @param manual_overrides Named character vector, `c("0" = "T cell", ...)`,
#'   that overrides LLM output for listed clusters.
#' @param drop_rejected Logical. Default `FALSE`, so clusters whose LLM
#'   `recommended_action == "reject"` remain in the Seurat object for review.
#'   Set to `TRUE` only after independently validating the flagged clusters;
#'   doing so removes their cells from the returned object. Ignored when
#'   `source = "manual"`.
#' @param column_name Metadata column to write. Default `"cell_type"`.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat. The Seurat metadata gains `column_name`;
#'   the set of rejected clusters (if any) is recorded in the decision log.
#'   Generated scripts preserve labels and cluster IDs as R literals and
#'   require the original input cell-ID set and per-cell cluster assignments
#'   before replaying offline. Input cells may be reordered.
#' @export
annot_apply <- function(obj,
                        source           = c("llm", "manual"),
                        manual_overrides = NULL,
                        drop_rejected    = FALSE,
                        column_name      = "cell_type",
                        rationale        = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  source <- match.arg(source)

  if (!"seurat_clusters" %in% colnames(obj@data@meta.data)) {
    stop("No 'seurat_clusters' column; run sc_cluster() first.")
  }

  # ---- Build the mapping (cluster_id -> cell_type) --------------------
  if (source == "llm") {
    ann_df <- obj@params$llm_annotations
    if (is.null(ann_df)) {
      stop("No LLM annotations found; run annot_llm_annotate() first, or use source='manual'.")
    }
    mapping <- stats::setNames(ann_df$primary_annotation,
                               as.character(ann_df$cluster))
  } else {
    if (is.null(manual_overrides) || length(manual_overrides) == 0) {
      stop("`manual_overrides` must be supplied when source = 'manual'.")
    }
    mapping <- manual_overrides
  }

  # Apply manual overrides on top of LLM mapping
  if (source == "llm" && !is.null(manual_overrides)) {
    mapping[names(manual_overrides)] <- manual_overrides
  }

  # ---- Determine clusters to reject ----------------------------------
  rejected <- character(0)
  if (drop_rejected && source == "llm" && !is.null(obj@params$llm_annotations)) {
    rejected <- as.character(
      obj@params$llm_annotations$cluster[
        obj@params$llm_annotations$recommended_action == "reject"
      ]
    )
    # Manual overrides for rejected clusters take precedence (keep them)
    if (!is.null(manual_overrides)) {
      rejected <- setdiff(rejected, names(manual_overrides))
    }
  }

  # ---- Apply mapping to metadata --------------------------------------
  input_cell_ids <- colnames(obj@data)
  cluster_vec <- as.character(obj@data@meta.data$seurat_clusters)
  new_col <- unname(mapping[cluster_vec])
  # Any cluster not in mapping: label "Unannotated"
  new_col[is.na(new_col)] <- "Unannotated"
  obj@data@meta.data[[column_name]] <- new_col

  # ---- Drop rejected clusters ----------------------------------------
  n_before <- ncol(obj@data)
  if (length(rejected) > 0) {
    keep <- !(cluster_vec %in% rejected)
    obj@data <- obj@data[, keep]
  }
  n_after <- ncol(obj@data)

  # ---- Generated script trace ----------------------------------------
  # Labels and cluster IDs can contain arbitrary provider text. Serialize
  # them as data rather than interpolating them into executable R syntax.
  literal <- function(x) {
    paste(utils::capture.output(dput(x, control = c("keepNA", "keepInteger", "showAttributes"))),
          collapse = "\n")
  }
  drop_block <- if (length(rejected) > 0) {
    paste0(
      "\n# Drop rejected clusters by cell ID\n",
      "annotation_keep_cell_ids <- colnames(seurat_obj)[",
      "!(annotation_cluster_ids %in% rejected_clusters)]\n",
      "seurat_obj <- seurat_obj[, annotation_keep_cell_ids]"
    )
  } else ""

  script <- paste0(
    "# ---- Apply saved annotations (", source, "); no model call ----\n",
    "annotation_input_cell_ids <- ", literal(input_cell_ids), "\n",
    "if (!setequal(annotation_input_cell_ids, colnames(seurat_obj))) ",
    "stop(\"Replay input cell IDs differ from the saved input.\")\n",
    "annotation_saved_cluster_ids <- ",
    literal(stats::setNames(cluster_vec, input_cell_ids)), "\n",
    "annotation_cluster_ids <- as.character(seurat_obj[[\"seurat_clusters\", drop = TRUE]])\n",
    "if (!identical(annotation_cluster_ids, ",
    "unname(annotation_saved_cluster_ids[colnames(seurat_obj)]))) ",
    "stop(\"Replay input cluster assignments differ from the saved input.\")\n",
    "cell_type_map <- ", literal(mapping), "\n",
    "rejected_clusters <- ", literal(rejected), "\n",
    "annotation_values <- unname(cell_type_map[annotation_cluster_ids])\n",
    "annotation_values[is.na(annotation_values)] <- \"Unannotated\"\n",
    "seurat_obj[[", literal(column_name), "]] <- annotation_values",
    drop_block
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Applied %s annotations to '%s' (%d clusters mapped%s).",
      source, column_name, length(mapping),
      if (length(rejected) > 0) {
        sprintf("; dropped %d cluster(s) flagged 'reject': %s (%d -> %d cells)",
                length(rejected), paste(rejected, collapse = ","),
                n_before, n_after)
      } else ""
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "annot_apply",
    function_name  = "annot_apply",
    params         = list(
      source             = source,
      column_name        = column_name,
      drop_rejected      = drop_rejected,
      rejected_clusters  = rejected,
      n_mapped           = length(mapping),
      n_cells_before     = n_before,
      n_cells_after      = n_after,
      manual_overrides   = manual_overrides,
      annotation_mapping = mapping,
      input_cluster_assignments = stats::setNames(cluster_vec, input_cell_ids)
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "annotated"
  )
}
