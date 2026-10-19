# One fallback policy shared by project creation and review recommendations.
# It is a draft, never a scientific approval or a claim of an optimal cutoff.
.sc_run_default_mad_choice <- function(panel) {
  summary <- if (!is.null(panel$summary)) panel$summary else panel
  fail <- function(reason) list(preset_id = "keep_all", eligible = FALSE,
    reason = paste("QC remains unassessed; keep all cells in the fallback draft.", reason))
  if (is.null(summary) || !length(summary$groups)) return(fail("No complete grouped MAD panel is available."))
  complete <- vapply(summary$groups, function(group) {
    all(vapply(c("nCount", "nFeature", "percent_mt"), function(metric) isTRUE(group$metrics[[metric]]$available), logical(1))) &&
      !any(grepl("large-gap|separated subpopulations|multimodal", unlist(group$warnings), ignore.case = TRUE))
  }, logical(1))
  candidate <- Filter(function(row) identical(row$preset_id, "conservative_and3"), summary$presets)
  if (!all(complete) || length(candidate) != 1L || !isTRUE(candidate[[1L]]$available))
    return(fail("Some group, metric, distribution guard or conservative AND3 predicate is unavailable; no global or OR substitution is made."))
  list(preset_id = "conservative_and3", eligible = TRUE,
    reason = paste("Complete grouped count, feature and MT MAD evidence permits a conservative AND3 starting draft.",
      "The analyst must review exact impacts and approve the full strategy; this is not biological validation."))
}
