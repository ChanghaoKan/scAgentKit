# Production helper regression: aggregate facts survive, exact QC identifiers
# and per-cell numeric measurements never enter the unified display contract.
args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
source(args[[1L]], local = TRUE)
private <- "PRIVATE_QC_CELL_SENTINEL_DO_NOT_DISPLAY"
numeric.private <- 938471263
distribution <- list(n = 2L, missing = 0L, min = 10, q25 = 15, median = 20, q75 = 25, max = 30)
population <- list(cells = 2L, metrics = list(nCount = distribution, nFeature = distribution, percent_mt = distribution))
details <- list(schema = "scagentkit.qc.preview.v1", evidence_hash = strrep("a", 64),
  canonical_parameters = list(proposal = list(schema = "scagentkit.qc.v1", rationale = "Keep measured supported range",
    filters = list(list(metric = "nCount", min = 10, max = 300, group = list(sample = "literal sample"))))),
  retention = list(before = 2L, retained = 1L, removed = 1L, fraction_retained = .5),
  keep_cells = private, remove_cells = private, keep_cell_hash = strrep("b", 64), remove_cell_hash = strrep("c", 64),
  metrics = data.frame(cell_id = private, nCount = numeric.private, nFeature = numeric.private, percent_mt = numeric.private,
    sample = private, capture = private),
  filter_impacts = list(list(id = "filter1", filter = list(metric = "nCount", min = 10), scoped = 2L,
    low = 1L, high = 0L, unavailable = 0L, independently_removed = 1L, exclusively_removed = 1L,
    primary_retained_in_scope = 1L, primary_removed_in_scope = 1L,
    scope_cells = private, low_cells = private, high_cells = private, unavailable_cells = private,
    independently_removed_cells = private, exclusively_removed_cells = private)),
  patterns = list(list(filter_ids = "filter1", reason_ids = "filter1:low", count = 1L,
    cell_ids = private, retained = 0L, removed = 1L)),
  overlap = list(filter_ids = "filter1", counts = list(list(1L)), interpretation = "Overlapping counts"),
  distributions = list(global = list(before = population, retained = population, removed = population),
    groups = list(list(group_id = "group1", selector = list(sample = "literal sample"), before = population))),
  unavailable = list(metrics = list(list(metric = "nCount", count = 0L, cell_ids = private)),
    zero_count_cells = private, mitochondrial = list(status = "measured")),
  sensitivity = list(list(id = "wider", proposal = list(filters = list(list(metric = "nCount", min = 5))),
    retention = list(before = 2L, retained = 2L), keep_cell_hash = strrep("d", 64),
    remove_cells = private, intersection_cells = private, added_cells = private, removed_from_primary_cells = private,
    intersection = 1L, added = 1L, removed_from_primary = 0L, jaccard = .5,
    groups = list(list(group_id = "group1", selector = list(sample = "literal sample"),
      before = 2L, primary_retained = 1L, retained = 2L, added_cells = private, removed_from_primary_cells = private)))),
  mad_flags = data.frame(cell_id = private, nCount = numeric.private),
  mad_panel = list(schema = "scagentkit.qc.mad.evidence.v1", cohort = list(input_cells = 100L),
    groups = list(list(input_cells = 50L, metrics = list(nCount = distribution)))),
  interpretation = "Saved quality comparison")
record <- list(schema = "scagentkit.qc.review.v1", hash = strrep("e", 64), details = details)
native <- list(qc_preview = record, strategy_review = list(details = list(qc_impact = details)),
  cycle_diagnostics = list(cohort = list(input_cells = 100L)),
  doublet_diagnostics = list(cohort = list(input_cells = 50L), per_capture = list(list(input_cells = 25L))),
  subcluster = list(selected_cells = 20L, retained_cells = 18L),
  stage_counts = list(original_cells = 100L, pre_score_cells = 95L, statistics_cells = 90L,
    unknown_cells = 10L, zero_count_cells = 2L, post_qc_cells = 80L, final_selected_cells = 78L),
  unsafe = list(input_cells = private, selected_cells = c(private, private), input_cell_ids = private,
    cell_id = private, API_KEY = private, password = private))
before <- serialize(native, NULL)
projected <- .sc_wb_plain(native)
stopifnot(identical(before, serialize(native, NULL)))
text <- paste(capture.output(dput(projected)), collapse = "\n")
stopifnot(!grepl(private, text, fixed = TRUE), !grepl(as.character(numeric.private), text, fixed = TRUE))
qc <- projected$qc_preview$details
stopifnot(is.null(qc$metrics), is.null(qc$mad_flags), is.null(qc$remove_cells),
  is.null(qc$filter_impacts[[1L]]$scope_cells), is.null(qc$sensitivity[[1L]]$intersection_cells),
  is.null(projected$strategy_review$details$qc_impact$metrics),
  identical(qc$retention$retained, 1L), identical(qc$filter_impacts[[1L]]$independently_removed, 1L),
  identical(qc$patterns[[1L]]$count, 1L), identical(qc$sensitivity[[1L]]$jaccard, .5),
  identical(qc$sensitivity[[1L]]$groups[[1L]]$added, 1L),
  identical(qc$distributions$global$before$metrics$nCount, distribution),
  identical(qc$distributions$groups[[1L]]$selector$sample, "literal sample"),
  identical(qc$canonical_parameters, details$canonical_parameters),
  identical(qc$keep_cell_hash, details$keep_cell_hash), identical(qc$unavailable$zero_count_count, 1L),
  identical(qc$mad_panel$cohort$input_cells, 100L), identical(qc$mad_panel$groups[[1L]]$metrics$nCount, distribution),
  identical(projected$cycle_diagnostics$cohort$input_cells, 100L),
  identical(projected$doublet_diagnostics$cohort$input_cells, 50L),
  identical(projected$doublet_diagnostics$per_capture[[1L]]$input_cells, 25L),
  identical(projected$subcluster$selected_cells, 20L), identical(projected$subcluster$retained_cells, 18L),
  identical(projected$stage_counts, native$stage_counts),
  is.null(projected$unsafe$input_cells), is.null(projected$unsafe$selected_cells))
cat("Production QC schema projection, duplicated strategy impact, MAD privacy and scalar cohort counts: PASS\n")
