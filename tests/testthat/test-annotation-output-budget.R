# Independent offline fixtures: no provider factory, credential or HTTP call.
annotation_budget_fixture <- function() {
  ids <- c("0", "01", "1", "7", "NA", "alpha", "beta")
  genes <- unlist(lapply(seq_along(ids), function(i) paste0("Marker", i, "Gene", 1:6)),
                  use.names = FALSE)
  cells <- c("001", "1", "NA", "cell space", sprintf("offline-cell-%02d", 5:21))
  counts <- Matrix::Matrix(matrix(1, nrow = length(genes), ncol = length(cells),
    dimnames = list(genes, cells)), sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  object$seurat_clusters <- rep(ids, each = 3)
  object$prior_annotation <- rep(c("prior label", NA_character_, "another prior label"), 7)
  table <- data.frame(cluster = rep(ids, each = 6), gene = genes,
    avg_log2FC = 2, pct.1 = 0.8, pct.2 = 0.1, p_val_adj = 0.01,
    stringsAsFactors = FALSE)
  evidence <- scAgentKit:::.sc_run_annotation_evidence(object, table,
    context = list(species = "human", tissue = "offline synthetic fixture"))
  proposal <- list(schema = "scagentkit.annotation.v1",
    annotations = lapply(evidence$summary$clusters, function(cluster) list(
      clusterId = cluster$clusterId, label = paste("Synthetic group", cluster$clusterId),
      confidence = "low", rationale = "Offline marker evidence requires analyst review.",
      markers = lapply(utils::head(cluster$markers, 3), function(marker) marker$gene))))
  # Abstention is explicit and still covers the literal cluster ID "NA".
  index <- match("NA", vapply(proposal$annotations, function(x) x$clusterId, character(1)))
  proposal$annotations[[index]]$label <- "Unknown"
  proposal$annotations[[index]]$markers <- list()
  list(object = object, evidence = evidence, proposal = proposal)
}

annotation_budget_json <- function(value) {
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null",
                               na = "null", digits = NA))
}

annotation_budget_plain_validator <- function(evidence) {
  function(value) {
    checked <- scAgentKit:::.sc_run_annotation_response_validate(value, evidence)
    list(schema = checked$schema, annotations = checked$annotations)
  }
}

annotation_budget_truncated_fixture <- function(fixture) {
  proposal <- fixture$proposal
  for (i in seq_along(proposal$annotations)) {
    proposal$annotations[[i]]$label <- strrep("L", 80)
    proposal$annotations[[i]]$rationale <- "R"
    proposal$annotations[[i]]$markers <- lapply(
      utils::head(fixture$evidence$summary$clusters[[i]]$markers, 5),
      function(marker) marker$gene)
  }
  last_gene <- tail(proposal$annotations, 1)[[1]]$markers[[1]]
  token <- paste0('"', last_gene, '"')
  quote_position <- function(text) as.integer(regexpr(token, text, fixed = TRUE))
  # Put the final cluster's opening marker quote at byte 2693. The 2696-byte
  # prefix then ends in the unfinished marker string "Mar, as a truncated
  # provider response might. The complete synthetic response stays in bounds.
  padding <- 2693L - quote_position(annotation_budget_json(proposal))
  if (padding < 0L || padding > 7L * 239L) stop("Unexpected synthetic fixture size.")
  for (i in seq_along(proposal$annotations)) {
    added <- min(padding, 239L)
    proposal$annotations[[i]]$rationale <- strrep("R", 1L + added)
    padding <- padding - added
  }
  complete <- annotation_budget_json(proposal)
  if (padding != 0L || quote_position(complete) != 2693L)
    stop("Synthetic marker truncation did not land at the expected byte.")
  list(complete = complete, truncated = substr(complete, 1L, 2696L))
}

test_that("a 2696-byte seven-cluster truncation is rejected without repair", {
  fixture <- annotation_budget_fixture()
  response <- annotation_budget_truncated_fixture(fixture)
  expect_equal(nchar(response$truncated, type = "bytes"), 2696L)
  expect_identical(substr(response$truncated, 2694L, 2696L), "Mar")
  calls <- 0L
  parsed <- scAgentKit:::.sc_run_provider_parse(response$truncated,
    validator = function(value) { calls <<- calls + 1L; value })
  expect_identical(parsed$status, "invalid_response")
  expect_null(parsed$content)
  expect_identical(calls, 0L)
  expect_true(is.character(parsed$error) && nzchar(parsed$error))
  complete <- scAgentKit:::.sc_run_provider_parse(response$complete,
    validator = annotation_budget_plain_validator(fixture$evidence))
  expect_identical(complete$status, "ok")
  expect_length(complete$content$annotations, 7L)
})

test_that("compact seven-cluster JSON retains Unknown and exact cell writeback", {
  fixture <- annotation_budget_fixture()
  source <- fixture$object
  source_hash <- scAgentKit:::.sc_run_hash(source)
  raw <- annotation_budget_json(fixture$proposal)
  expect_lt(nchar(raw, type = "bytes"), 2696L)
  parsed <- scAgentKit:::.sc_run_provider_parse(raw,
    validator = annotation_budget_plain_validator(fixture$evidence))
  expect_identical(parsed$status, "ok")
  expect_length(parsed$content$annotations, 7L)
  checked <- scAgentKit:::.sc_run_annotation_validate(parsed$content, fixture$evidence)
  expect_identical(vapply(checked$annotations, function(x) x$clusterId, character(1)),
    vapply(fixture$evidence$summary$clusters, function(x) x$clusterId, character(1)))
  unknown <- Filter(function(x) x$clusterId == "NA", checked$annotations)[[1]]
  expect_identical(unknown$label, "Unknown")
  expect_identical(unknown$markers, list())
  out <- scAgentKit:::.sc_run_annotation_apply(source, checked,
                                              column = "compact_review")
  expect_identical(fixture$object, source)
  expect_identical(scAgentKit:::.sc_run_hash(fixture$object), source_hash)
  expect_identical(colnames(out), colnames(source))
  expect_identical(out$seurat_clusters, source$seurat_clusters)
  expect_identical(out$prior_annotation, source$prior_annotation)
  expect_true(all(out$compact_review[source$seurat_clusters == "NA"] == "Unknown"))
  expect_false(anyNA(out$compact_review))
  expect_equal(SeuratObject::LayerData(out, assay = "RNA", layer = "counts"),
               SeuratObject::LayerData(source, assay = "RNA", layer = "counts"))
})

test_that("compact AI responses reject hallucinations and incomplete cluster sets", {
  fixture <- annotation_budget_fixture()
  proposal <- fixture$proposal
  proposal$annotations[[1]]$markers <- list("NotInSuppliedEvidence")
  expect_error(scAgentKit:::.sc_run_annotation_response_validate(proposal, fixture$evidence),
               "absent.*evidence")
  cross_cluster <- fixture$proposal
  cross_cluster$annotations[[1]]$markers <- list(
    fixture$evidence$summary$clusters[[2]]$markers[[1]]$gene)
  expect_error(scAgentKit:::.sc_run_annotation_response_validate(cross_cluster, fixture$evidence),
               "absent.*evidence")
  missing <- fixture$proposal
  missing$annotations <- missing$annotations[-7]
  expect_error(scAgentKit:::.sc_run_annotation_response_validate(missing, fixture$evidence),
               "every evidence cluster")
  duplicate <- fixture$proposal
  duplicate$annotations[[7]] <- duplicate$annotations[[1]]
  expect_error(scAgentKit:::.sc_run_annotation_response_validate(duplicate, fixture$evidence),
               "Duplicate")
})

test_that("AI response length limits accept boundaries and reject overflow", {
  fixture <- annotation_budget_fixture()
  bounded <- fixture$proposal
  bounded$annotations[[1]]$label <- strrep("L", 80)
  bounded$annotations[[1]]$rationale <- strrep("R", 240)
  bounded$annotations[[1]]$markers <- lapply(
    fixture$evidence$summary$clusters[[1]]$markers[1:5], function(marker) marker$gene)
  expect_s3_class(scAgentKit:::.sc_run_annotation_response_validate(bounded, fixture$evidence),
                  "sc_run_annotation_proposal")
  unicode <- bounded
  unicode$annotations[[1]]$label <- strrep("\u6807", 80)
  unicode$annotations[[1]]$rationale <- strrep("\u7406", 240)
  expect_s3_class(scAgentKit:::.sc_run_annotation_response_validate(unicode, fixture$evidence),
                  "sc_run_annotation_proposal")
  unicode$annotations[[1]]$label <- strrep("\u6807", 81)
  expect_error(scAgentKit:::.sc_run_annotation_response_validate(unicode, fixture$evidence),
               "80|label")
  over_label <- bounded
  over_label$annotations[[1]]$label <- strrep("L", 81)
  expect_error(scAgentKit:::.sc_run_annotation_response_validate(over_label, fixture$evidence),
               "80|label")
  over_rationale <- bounded
  over_rationale$annotations[[1]]$rationale <- strrep("R", 241)
  expect_error(scAgentKit:::.sc_run_annotation_response_validate(over_rationale, fixture$evidence),
               "240|rationale")
  over_markers <- bounded
  over_markers$annotations[[1]]$markers <- lapply(
    fixture$evidence$summary$clusters[[1]]$markers, function(marker) marker$gene)
  expect_error(scAgentKit:::.sc_run_annotation_response_validate(over_markers, fixture$evidence),
               "5|markers")
})

test_that("manual annotation retains richer explanations and marker compatibility", {
  fixture <- annotation_budget_fixture()
  manual <- fixture$proposal
  manual$annotations[[1]]$label <- strrep("L", 81)
  manual$annotations[[1]]$rationale <- strrep("R", 241)
  manual$annotations[[1]]$markers <- lapply(
    fixture$evidence$summary$clusters[[1]]$markers, function(marker) marker$gene)
  checked <- scAgentKit:::.sc_run_annotation_validate(manual, fixture$evidence)
  expect_s3_class(checked, "sc_run_annotation_proposal")
  expect_equal(nchar(checked$annotations[[1]]$label), 81L)
  expect_equal(nchar(checked$annotations[[1]]$rationale), 241L)
  expect_length(checked$annotations[[1]]$markers, 6L)
})

test_that("provider output defaults to 4096 and explicit caps keep distinct fingerprints", {
  for (name in c("mock", "deepseek", "grok")) {
    metadata <- scAgentKit:::.sc_run_provider_spec(name)$metadata
    expect_equal(metadata$generation$max_tokens, 4096)
  }
  explicit <- list(name = "mock", generation = list(max_tokens = 3072L))
  expect_equal(scAgentKit:::.sc_run_provider_spec(explicit)$metadata$generation$max_tokens, 3072)
  request <- list(system_prompt = "Return one complete typed annotation JSON object.",
    user_prompt = "Offline seven-cluster aggregate fixture.", purpose = "annotation")
  expect_false(identical(scAgentKit:::.sc_run_request_hash(request, "mock"),
                         scAgentKit:::.sc_run_request_hash(request, explicit)))
})
