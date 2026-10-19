# A local software prerequisite, not a semantic or accuracy classifier. Keep
# response-schema status and raw proposals separate from evidence usability.
.annotation_evidence_validity <- function(parsed, cluster_genes, validation_enabled = TRUE) {
  clean <- function(x) {
    x <- trimws(as.character(x))
    unique(x[!is.na(x) & nzchar(x)])
  }
  support <- clean(parsed$supporting_markers)
  contradict <- clean(parsed$contradicting_markers)
  available <- toupper(clean(cluster_genes))
  valid_support <- support[toupper(support) %in% available]
  valid_contradict <- contradict[toupper(contradict) %in% available]
  unsupported <- clean(c(support[!toupper(support) %in% available],
    contradict[!toupper(contradict) %in% available], parsed$hallucinated_markers))
  reasons <- character()
  if (!isTRUE(validation_enabled)) reasons <- c(reasons, "citation_validation_disabled")
  if (!identical(parsed$annotation_status, "ok")) reasons <- c(reasons, "response_not_fully_valid")
  label <- clean(parsed$primary_annotation)
  if (length(label) != 1L || tolower(label) %in% c("unknown", "unannotated"))
    reasons <- c(reasons, "unresolved_label")
  if (!length(valid_support)) reasons <- c(reasons, "no_valid_same_cluster_support")
  if (length(unsupported)) reasons <- c(reasons, "unsupported_citations")
  rate <- parsed$hallucination_rate
  if (is.numeric(rate) && length(rate) == 1L && is.finite(rate) && rate > 0)
    reasons <- c(reasons, "recorded_unsupported_support")
  if (!identical(parsed$recommended_action, "accept")) reasons <- c(reasons, "action_requires_review")
  citation_status <- if (!isTRUE(validation_enabled)) "not_validated" else
    if (length(unsupported)) "invalid" else if (!length(valid_support)) "insufficient_support" else "valid"
  review_reasons <- c(reasons, if (length(valid_contradict)) "declared_counterevidence_requires_review")
  list(citation_status = citation_status, review_required = length(review_reasons) > 0L,
    review_reasons = review_reasons,
    status = if (identical(parsed$annotation_status, "failed")) "failed" else
      if (length(reasons)) "needs_review" else "usable",
    label_usable = !length(reasons), reasons = reasons, valid_support = valid_support,
    valid_contradict = valid_contradict, unsupported = unsupported,
    limitation = "Citation grounding is a minimum software prerequisite, not label semantic validation or calibrated confidence. One supplied marker can be weak evidence. Grounded declared counterevidence is a review hint, not an automatic veto; this gate grants no approval and infers no gene semantics or counterevidence from fold-change sign.")
}
