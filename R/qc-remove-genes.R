#' Remove mitochondrial, ribosomal, and hemoglobin genes
#'
#' These gene families frequently dominate variability and bias downstream
#' clustering. Standard practice is to drop them after QC metrics have been
#' computed (see [qc_add_metrics()]) but before normalization.
#'
#' @param obj An AgentSeurat object.
#' @param species Character, "mouse" or "human". Drives default patterns.
#' @param remove_mt Logical, remove mitochondrial genes. Default TRUE.
#' @param remove_ribo Logical, remove ribosomal genes. Default TRUE.
#' @param remove_hb Logical, remove hemoglobin genes. Default TRUE.
#' @param mt_pattern,ribo_pattern,hb_pattern Optional custom regex
#'   overrides (see [qc_add_metrics()]).
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat object with genes removed.
#' @export
qc_remove_genes <- function(obj,
                            species      = c("mouse", "human"),
                            remove_mt    = TRUE,
                            remove_ribo  = TRUE,
                            remove_hb    = TRUE,
                            mt_pattern   = NULL,
                            ribo_pattern = NULL,
                            hb_pattern   = NULL,
                            rationale    = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  species <- match.arg(species)

  if (is.null(mt_pattern))   mt_pattern   <- if (species == "mouse") "^mt-"   else "^MT-"
  if (is.null(ribo_pattern)) ribo_pattern <- if (species == "mouse") "^Rp[sl]" else "^RP[SL]"
  if (is.null(hb_pattern))   hb_pattern   <- if (species == "mouse") "^Hb[ab]" else "^HB[AB]"

  build_remove_set <- function(seu) {
    all_genes <- rownames(seu)
    to_remove <- character(0)
    if (remove_mt)   to_remove <- c(to_remove, grep(mt_pattern,   all_genes, value = TRUE))
    if (remove_ribo) to_remove <- c(to_remove, grep(ribo_pattern, all_genes, value = TRUE))
    if (remove_hb)   to_remove <- c(to_remove, grep(hb_pattern,   all_genes, value = TRUE))
    unique(to_remove)
  }

  remove_one <- function(seu) {
    # v5 safety: `subset(seu, features=...)` on an Assay5 object with
    # multiple counts layers can produce an inconsistent object; join
    # layers first so the subset applies to a single canonical matrix.
    seu <- .ensure_joined(seu, "counts")
    to_remove <- build_remove_set(seu)
    subset(seu, features = setdiff(rownames(seu), to_remove))
  }

  # Count genes removed (use first seurat for representative count)
  if (obj@data_type == "seurat") {
    n_removed <- length(build_remove_set(obj@data))
    n_before <- nrow(obj@data)
  } else {
    n_removed <- length(build_remove_set(obj@data[[1]]))
    n_before <- nrow(obj@data[[1]])
  }

  obj <- .apply_to_data(obj, remove_one)

  patterns <- list()
  if (remove_mt)   patterns[["mt"]]   <- mt_pattern
  if (remove_ribo) patterns[["ribo"]] <- ribo_pattern
  if (remove_hb)   patterns[["hb"]]   <- hb_pattern
  combined_pattern <- paste(unlist(patterns), collapse = "|")

  script <- sprintf(
'# ---- Remove mt / ribo / hb genes ----
remove_unwanted_genes <- function(seu) {
  genes_remove <- rownames(seu)[grepl("%s", rownames(seu))]
  subset(seu, features = setdiff(rownames(seu), genes_remove))
}
%s',
    combined_pattern,
    if (obj@data_type == "seurat_list") {
      "seurat_list <- lapply(seurat_list, remove_unwanted_genes)"
    } else {
      "seurat_obj <- remove_unwanted_genes(seurat_obj)"
    }
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Removed %d gene(s) matching %s patterns to reduce technical noise (%d -> %d).",
      n_removed,
      paste(names(patterns), collapse = "/"),
      n_before, n_before - n_removed
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "qc_remove_genes",
    function_name  = "qc_remove_genes",
    params         = list(
      species     = species,
      remove_mt   = remove_mt,
      remove_ribo = remove_ribo,
      remove_hb   = remove_hb,
      n_removed   = n_removed
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "genes_filtered"
  )
}
