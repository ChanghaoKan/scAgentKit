#' Add standard QC metrics to the underlying Seurat data
#'
#' Computes `percent.mt`, `percent.ribo`, and `percent.hb` based on gene-name
#' regex patterns. Applies to either a single Seurat object or every element
#' of a Seurat list, depending on the current `data_type`. Species-specific
#' defaults are provided; pass `mt_pattern`, `ribo_pattern`, or `hb_pattern`
#' to override.
#'
#' @param obj An AgentSeurat object.
#' @param species Character, one of `"auto"`, `"mouse"`, or `"human"`.
#'   Defaults to `"auto"`, which infers mouse versus human from gene-name
#'   conventions and asks for an explicit choice when detection is ambiguous.
#'   Ignored if all three custom patterns are supplied.
#' @param mt_pattern Optional custom regex for mitochondrial genes.
#' @param ribo_pattern Optional custom regex for ribosomal genes.
#' @param hb_pattern Optional custom regex for hemoglobin genes.
#' @param rationale Optional LLM-supplied explanation of why this species
#'   choice was made. Defaults to a templated string.
#'
#' @return Updated AgentSeurat object with three new metadata columns on
#'   the underlying Seurat data and a new entry in the decision log.
#' @export
#'
#' @examples
#' \dontrun{
#'   obj <- AgentSeurat(seurat)
#'   obj <- qc_add_metrics(obj, species = "human")
#' }
qc_add_metrics <- function(obj,
                           species      = c("auto", "mouse", "human"),
                           mt_pattern   = NULL,
                           ribo_pattern = NULL,
                           hb_pattern   = NULL,
                           rationale    = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  species <- match.arg(species)

  # Auto-detect species from gene-name conventions (^MT- vs ^mt-).
  if (species == "auto") {
    detected <- .detect_species(obj@data)
    if (is.na(detected)) {
      stop("Could not auto-detect species from gene names. ",
           "Pass species = 'human' or 'mouse' explicitly.")
    }
    species <- detected
    message(sprintf("[qc_add_metrics] auto-detected species: %s", species))
  }

  if (is.null(mt_pattern))   mt_pattern   <- if (species == "mouse") "^mt-"   else "^MT-"
  if (is.null(ribo_pattern)) ribo_pattern <- if (species == "mouse") "^Rp[sl]" else "^RP[SL]"
  if (is.null(hb_pattern))   hb_pattern   <- if (species == "mouse") "^Hb[ab]" else "^HB[AB]"

  add_metrics <- function(seu) {
    seu[["percent.mt"]]   <- Seurat::PercentageFeatureSet(seu, pattern = mt_pattern)
    seu[["percent.ribo"]] <- Seurat::PercentageFeatureSet(seu, pattern = ribo_pattern)
    seu[["percent.hb"]]   <- Seurat::PercentageFeatureSet(seu, pattern = hb_pattern)
    seu
  }

  obj <- .apply_to_data(obj, add_metrics)

  # Generate reproducible script. If we are working with a list, wrap in
  # lapply to mirror the per-sample pattern.
  if (obj@data_type == "seurat") {
    script <- sprintf(
'# ---- Add QC metrics (species: %s) ----
seurat_obj[["percent.mt"]]   <- PercentageFeatureSet(seurat_obj, pattern = "%s")
seurat_obj[["percent.ribo"]] <- PercentageFeatureSet(seurat_obj, pattern = "%s")
seurat_obj[["percent.hb"]]   <- PercentageFeatureSet(seurat_obj, pattern = "%s")',
      species, mt_pattern, ribo_pattern, hb_pattern
    )
  } else {
    script <- sprintf(
'# ---- Add QC metrics per sample (species: %s) ----
seurat_list <- lapply(seurat_list, function(seu) {
  seu[["percent.mt"]]   <- PercentageFeatureSet(seu, pattern = "%s")
  seu[["percent.ribo"]] <- PercentageFeatureSet(seu, pattern = "%s")
  seu[["percent.hb"]]   <- PercentageFeatureSet(seu, pattern = "%s")
  seu
})',
      species, mt_pattern, ribo_pattern, hb_pattern
    )
  }

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Added mitochondrial / ribosomal / hemoglobin gene percentages using %s-species default patterns.",
      species
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "qc_add_metrics",
    function_name  = "qc_add_metrics",
    params         = list(species = species, mt_pattern = mt_pattern,
                          ribo_pattern = ribo_pattern, hb_pattern = hb_pattern),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "qc_metrics_added"
  )
}
