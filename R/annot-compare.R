#' Collapse fine cell type labels to broad categories
#'
#' Maps fine-grained cell type labels (e.g. "CD8 T cell", "Plasma cell",
#' "Hepatic stellate cell") to broad categories (e.g. "T/NK", "B",
#' "Fibroblast"). Uses a built-in mapping curated for common immune
#' / stromal / parenchymal lineages; users can extend it via `extra_map`.
#'
#' This is helpful when the LLM annotation produced finer labels than
#' the author's broad categories -- see [annot_compare_with_reference()]
#' which uses this internally.
#'
#' @param x Character vector of cell type labels.
#' @param extra_map Optional named character vector to extend / override
#'   the built-in map. Names are fine labels, values are broad labels.
#' @param keep_unmapped Logical. If TRUE (default), labels not in the
#'   map are returned as-is (e.g. "Fibroblast" stays "Fibroblast"
#'   because it's already broad). If FALSE, unmapped labels become
#'   `NA_character_`.
#'
#' @return Character vector of broad labels, same length as `x`.
#' @export
#'
#' @examples
#' \dontrun{
#'   broad <- annot_collapse_to_broad(c("CD8 T cell", "Plasma cell",
#'                                       "CAF", "LSEC"))
#'   #   "T/NK"  "B"  "Fibroblast"  "Endothelial"
#' }
annot_collapse_to_broad <- function(x,
                                    extra_map     = NULL,
                                    keep_unmapped = TRUE) {
  default_map <- .default_broad_map()
  if (!is.null(extra_map)) {
    if (is.null(names(extra_map))) {
      stop("`extra_map` must be a NAMED character vector.")
    }
    default_map[names(extra_map)] <- extra_map
  }

  out <- ifelse(x %in% names(default_map),
                default_map[x],
                if (isTRUE(keep_unmapped)) x else NA_character_)
  unname(out)
}


#' Compare LLM annotation against an author-supplied reference column
#'
#' Builds a confusion matrix between the LLM annotation
#' (`obj@@data$cell_type` after [annot_apply()]) and a reference
#' annotation column from the metadata (e.g. the `celltype` column
#' shipped by GSE149614). Computes per-class sensitivity / precision and
#' overall cell-level concordance.
#'
#' Two convenience features:
#' \itemize{
#'   \item Optional collapse of fine LLM labels to broad categories via
#'     [annot_collapse_to_broad()] (default ON when broad-vs-fine mismatch
#'     is detected).
#'   \item Cell-name alignment: handles double-prefix issues like
#'     "HCC01T_HCC01T_BARCODE" vs "HCC01T_BARCODE" by stripping common
#'     leading prefixes.
#' }
#'
#' Results are stored in `obj@@params$author_comparison` and rendered
#' in the HTML report.
#'
#' @param obj An AgentSeurat after [annot_apply()] (`cell_type` column
#'   present).
#' @param reference_col Character. The metadata column on `obj@@data`
#'   that holds the author / external reference annotation. If NULL
#'   (default), auto-detected via [.detect_celltype_col()].
#' @param author_celltype Optional named character vector keyed by cell
#'   name. Use this when the reference annotation lives outside
#'   `obj@@data` (e.g. you preserved it from a pre-QC Seurat object).
#'   Cell names will be aligned automatically.
#' @param collapse_llm Logical. Whether to apply
#'   [annot_collapse_to_broad()] to LLM labels before comparison.
#'   Default `"auto"`: enabled iff the LLM produced labels not present
#'   in the reference vocabulary.
#' @param extra_map Optional vocabulary extension passed to
#'   [annot_collapse_to_broad()].
#'
#' @return Updated AgentSeurat. The comparison block at
#'   `obj@@params$author_comparison` contains:
#'   `confusion`, `agreement`, `per_class`, `overall_concordance`,
#'   `n_cells_compared`, `collapse_used`.
#' @export
annot_compare_with_reference <- function(obj,
                                         reference_col   = NULL,
                                         author_celltype = NULL,
                                         collapse_llm    = "auto",
                                         extra_map       = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("annot_compare_with_reference expects a single Seurat object.")
  }
  meta <- obj@data@meta.data
  if (!"cell_type" %in% colnames(meta)) {
    stop("`cell_type` column not found. Run annot_apply() first.")
  }

  # -- Resolve the reference annotation vector --
  if (!is.null(author_celltype)) {
    # External vector -- align by cell name, handling double-prefix.
    ref_vec <- .align_external_celltype(obj, author_celltype)
    source_label <- "external"
  } else {
    if (is.null(reference_col)) {
      # Exclude `cell_type` since that is the LLM output we are comparing
      # against -- it can never be the reference.
      reference_col <- .detect_celltype_col(meta, exclude = "cell_type")
      if (is.na(reference_col)) {
        stop("Could not auto-detect a reference cell type column. ",
             "Pass reference_col or author_celltype explicitly.")
      }
      message(sprintf("[annot_compare] auto-detected reference column: '%s'",
                      reference_col))
    }
    if (!reference_col %in% colnames(meta)) {
      stop(sprintf("reference_col '%s' not found in metadata.", reference_col))
    }
    ref_vec <- as.character(meta[[reference_col]])
    names(ref_vec) <- rownames(meta)
    source_label <- reference_col
  }

  llm_call <- as.character(meta$cell_type)
  names(llm_call) <- rownames(meta)

  # v0.1.12: strip cycling-cluster decoration so the comparison aligns
  # with broad reference vocabularies. Examples handled:
  #   "Cycling cells (lineage candidate: Hepatocyte)"  -> "Hepatocyte"
  #   "Cycling cells (lineage candidate: T/NK)"        -> "T/NK"
  # Preserves "Cycling cells (lineage uncertain)" as-is so it stays
  # visible in the confusion matrix.
  cycling_prefix <- "Cycling cells \\(lineage candidate: (.+)\\)$"
  has_cycle_dec  <- grepl(cycling_prefix, llm_call)
  if (any(has_cycle_dec)) {
    n_decorated <- sum(has_cycle_dec)
    llm_call[has_cycle_dec] <- sub(cycling_prefix, "\\1",
                                   llm_call[has_cycle_dec])
    message(sprintf(
      "[annot_compare] simplified %d cycling-decorated labels for vocabulary alignment.",
      n_decorated
    ))
  }

  # Align by cell name (rownames of metadata == cell names of seurat)
  common <- intersect(rownames(meta), names(ref_vec))
  if (length(common) == 0) {
    stop("No cell names in common between LLM annotation and reference.")
  }
  llm_call    <- llm_call[common]
  author_call <- ref_vec[common]
  keep <- !is.na(llm_call) & !is.na(author_call) &
          nzchar(llm_call) & nzchar(author_call)
  llm_call    <- llm_call[keep]
  author_call <- author_call[keep]

  # -- Decide whether to collapse --
  if (identical(collapse_llm, "auto")) {
    n_llm_in_ref <- mean(llm_call %in% unique(author_call))
    do_collapse  <- n_llm_in_ref < 0.7
    if (do_collapse) {
      message("[annot_compare] LLM labels do not match reference vocabulary; ",
              "collapsing fine labels to broad via annot_collapse_to_broad().")
    }
  } else {
    do_collapse <- isTRUE(collapse_llm)
  }
  if (do_collapse) {
    llm_call <- annot_collapse_to_broad(llm_call, extra_map = extra_map)
  }

  # -- Confusion matrix --
  confusion <- table(LLM = llm_call, Author = author_call)

  # -- Per-LLM-call concordance --
  agreement <- data.frame(LLM_call = unique(llm_call),
                          stringsAsFactors = FALSE)
  agreement$author_majority <- vapply(agreement$LLM_call, function(x) {
    tab <- table(author_call[llm_call == x])
    if (length(tab) == 0) return(NA_character_)
    names(which.max(tab))
  }, character(1))
  agreement$pct_in_majority <- vapply(agreement$LLM_call, function(x) {
    tab <- table(author_call[llm_call == x])
    if (length(tab) == 0) return(NA_real_)
    round(100 * max(tab) / sum(tab), 1)
  }, numeric(1))
  agreement$n_cells <- vapply(agreement$LLM_call, function(x) {
    sum(llm_call == x)
  }, integer(1))
  agreement <- agreement[order(-agreement$n_cells), ]

  # -- Per-class sensitivity / precision (only on overlap of vocabularies) --
  shared <- intersect(rownames(confusion), colnames(confusion))
  if (length(shared) > 0) {
    sub_conf <- confusion[shared, shared, drop = FALSE]
    diag_vals <- diag(sub_conf)
    per_class <- data.frame(
      cell_type   = shared,
      n_author    = colSums(confusion)[shared],
      n_llm       = rowSums(confusion)[shared],
      correct     = diag_vals,
      sensitivity = round(100 * diag_vals / colSums(confusion)[shared], 1),
      precision   = round(100 * diag_vals / rowSums(confusion)[shared], 1),
      stringsAsFactors = FALSE
    )
    rownames(per_class) <- NULL
  } else {
    per_class <- data.frame()
  }

  overall <- mean(llm_call == author_call, na.rm = TRUE)

  comp <- list(
    confusion           = confusion,
    agreement           = agreement,
    per_class           = per_class,
    overall_concordance = round(100 * overall, 1),
    n_cells_compared    = length(llm_call),
    collapse_used       = isTRUE(do_collapse),
    reference_source    = source_label
  )

  obj@params$author_comparison <- comp

  rationale <- sprintf(
    "Compared %d cells against '%s'. Overall concordance: %.1f%% (collapse_used = %s).",
    comp$n_cells_compared, source_label, comp$overall_concordance,
    comp$collapse_used
  )
  script <- sprintf(
'# ---- Compare LLM annotation vs %s ----
# overall concordance: %.1f%%; see obj@params$author_comparison',
    source_label, comp$overall_concordance
  )

  .record_step(
    obj            = obj,
    step_name      = "annot_compare_with_reference",
    function_name  = "annot_compare_with_reference",
    params         = list(
      reference_source    = source_label,
      collapse_used       = comp$collapse_used,
      n_cells_compared    = comp$n_cells_compared,
      overall_concordance = comp$overall_concordance
    ),
    rationale      = rationale,
    script_snippet = script
  )
}

# ---- Internal: cell-name alignment for external reference vectors ----------
# Handles common patterns:
#   - "HCC01T_HCC01T_BARCODE" (double-prefixed by qc_split + add.cell.ids
#     when the source already had <sample>_<barcode>)
#   - leading-prefix mismatch
#   - barcode-only matching when sample info is unique enough
.align_external_celltype <- function(obj, author_celltype) {
  cell_names_obj <- colnames(obj@data)
  cell_names_ref <- names(author_celltype)
  if (is.null(cell_names_ref)) {
    stop("`author_celltype` must be a NAMED vector (names = cell names).")
  }

  # Try direct match first
  if (mean(cell_names_obj %in% cell_names_ref) > 0.95) {
    return(author_celltype[cell_names_obj])
  }

  # Strategy 1: strip ONE leading prefix from obj cell names
  stripped <- sub("^[^_]+_", "", cell_names_obj)
  if (mean(stripped %in% cell_names_ref) > 0.95) {
    out <- author_celltype[stripped]
    names(out) <- cell_names_obj
    message("[annot_compare] aligned by stripping one prefix from obj cell names.")
    return(out)
  }

  # Strategy 2: strip leading prefix from ref instead
  stripped_ref <- sub("^[^_]+_", "", cell_names_ref)
  ref2 <- author_celltype
  names(ref2) <- stripped_ref
  if (mean(cell_names_obj %in% stripped_ref) > 0.95) {
    out <- ref2[cell_names_obj]
    message("[annot_compare] aligned by stripping one prefix from ref cell names.")
    return(out)
  }

  # Strategy 3: stripping ONE prefix from BOTH
  stripped_obj <- sub("^[^_]+_", "", cell_names_obj)
  stripped_ref <- sub("^[^_]+_", "", cell_names_ref)
  ref3 <- author_celltype
  names(ref3) <- stripped_ref
  if (mean(stripped_obj %in% stripped_ref) > 0.95) {
    out <- ref3[stripped_obj]
    names(out) <- cell_names_obj
    message("[annot_compare] aligned by stripping one prefix from both sides.")
    return(out)
  }

  stop("Could not align cell names between AgentSeurat and external author_celltype. ",
       "Match rate too low. Inspect head(colnames(obj@data)) and ",
       "head(names(author_celltype)) and align manually.")
}
