.sc_run_choice_reasons <- function(value, required = FALSE) {
  keys <- c("qc", "doublet", "cycle", "batch", "hvg", "pcs", "clustering", "umap")
  if (is.null(value)) {
    if (required) stop("Supply a reason for every strategy choice; the local draft remains available for manual review.", call. = FALSE)
    return(NULL)
  }
  value <- .sc_run_provider_plain(value)
  if (!is.list(value) || is.null(names(value)) || anyDuplicated(names(value)) || !setequal(names(value), keys))
    stop("choice_reasons needs exactly qc, doublet, cycle, batch, hvg, pcs, clustering and umap.", call. = FALSE)
  value <- lapply(value[keys], function(text) {
    if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(trimws(text)) || nchar(text) > 700L)
      stop("Each strategy choice needs one nonempty reason of at most 700 characters.", call. = FALSE)
    as.character(text)
  })
  if (.sc_run_provider_contains_secret(value)) stop("Credential-like strategy reasons are forbidden.", call. = FALSE)
  value
}

.sc_run_default_choice_reasons <- function(qc, doublet_mode = NULL) {
  list(qc = qc,
    doublet = if (identical(doublet_mode, "remove")) "Removal is only a draft after eligible fixed predictions; review exact projected cells and approve before any deletion." else
      "Keep cells by default. Called-cell, capture and dependency prerequisites must pass before diagnostic flags are available; predictions are not truth.",
    cycle = "Preserve cell-cycle biology with regression none. Eligible S/G2M scoring is evidence only; unavailable scoring is not a zero score.",
    batch = "Use none until technical provenance and design are explicitly declared and confounding/rank guards support an embedding-only correction.",
    hvg = "Use the selected variable-feature method on the saved LogNormalize data; do not infer that these software defaults are biologically optimal.",
    pcs = "Review the selected fixed or computed PC rule on actual saved components; a truncated PC reference is not total expression variance.",
    clustering = "The initial resolution is provisional. Final selection requires the actual measured scan and a second human review.",
    umap = "UMAP is a visualization choice on reviewed PCs and neighbors; its appearance does not establish cluster identity or quality.")
}
