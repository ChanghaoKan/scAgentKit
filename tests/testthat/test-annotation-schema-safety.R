annotation_safety_json <- function() {
  '{"primary_annotation":"T cell","confidence":"high","supporting_markers":["CD3D"],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"CD3D supports the T lineage."}'
}

annotation_safety_response <- function(...) {
  value <- jsonlite::fromJSON(annotation_safety_json(), simplifyVector = FALSE)
  updates <- list(...)
  for (name in names(updates)) value[name] <- updates[name]
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null"))
}

make_annotation_safety_fixture <- function(cycling = FALSE) {
  counts <- matrix(rep(c(3, 7, 4), 10), nrow = 3,
                   dimnames = list(c("CD3D", "MKI67", "TOP2A"), paste0("C", 1:10)))
  seu <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(counts, sparse = TRUE))
  seu <- Seurat::NormalizeData(seu, verbose = FALSE)
  seu$seurat_clusters <- rep("0", 10)
  seu$celltype <- rep(c("AUTHOR_ALPHA", "AUTHOR_BETA"), 5)
  obj <- AgentSeurat(seu)
  obj@params$markers_filtered <- data.frame(
    cluster = "0", gene = if (cycling) c("MKI67", "TOP2A") else "CD3D",
    pct.1 = 0.9, pct.2 = 0.1, stringsAsFactors = FALSE
  )
  obj@params$reference_matches <- data.frame(
    cluster = "0", cell_type = "ACT_SECRET_LABEL", overlap_count = 1L,
    celltype_size = 2L, score = 0.5, matched_markers = "ACT_SECRET_MARKER",
    stringsAsFactors = FALSE
  )
  if (cycling) {
    obj@params$cluster_cycling_score <- data.frame(cluster = "0", cycling_dominant = TRUE)
  }
  obj
}

test_that("annotation validator preserves arrays and checks an optional cluster echo", {
  parse <- function(raw, ...) scAgentKit:::.validate_annotation_response(
    jsonlite::fromJSON(raw, simplifyVector = FALSE), ...
  )
  out <- parse(annotation_safety_json())
  expect_identical(out$supporting_markers, "CD3D")
  expect_identical(out$contradicting_markers, character(0))
  expect_equal(parse(annotation_safety_response(cluster = "0"), expected_cluster = "0")$cluster, "0")
  expect_error(parse(annotation_safety_response(cluster = "9"), expected_cluster = "0"), "cluster ID")
  expect_error(parse(annotation_safety_response(cluster = 0), expected_cluster = "0"), "scalar string")
  expect_error(parse(annotation_safety_response(primary_annotation = "NK cell"), vocabulary = "T cell"), "strict vocabulary")
  expect_equal(parse(annotation_safety_response(primary_annotation = "Unknown"), vocabulary = "T cell")$primary_annotation, "Unknown")
})

test_that("parseable JSON with wrong fields, types, or cardinality fails safely", {
  invalid <- c(
    "null", "[]", "1", '"T cell"',
    paste0("[", annotation_safety_json(), "]"),
    paste0("```json\n", annotation_safety_json(), "\n```"),
    paste0("Decision: ", annotation_safety_json()),
    annotation_safety_response(primary_annotation = list("T cell", "B cell")),
    annotation_safety_response(primary_annotation = list("T cell")),
    annotation_safety_response(confidence = "certain"),
    annotation_safety_response(recommended_action = "remove"),
    annotation_safety_response(proportion_assessment = "normal"),
    annotation_safety_response(reasoning = ""),
    annotation_safety_response(supporting_markers = "CD3D"),
    annotation_safety_response(supporting_markers = NULL),
    sub('"supporting_markers":["CD3D"]', '"supporting_markers":{}',
        annotation_safety_json(), fixed = TRUE),
    annotation_safety_response(supporting_markers = list(7)),
    annotation_safety_response(supporting_markers = list(list("CD3D"))),
    annotation_safety_response(extra_decision = "remove"),
    sub('"confidence":"high",', "", annotation_safety_json(), fixed = TRUE),
    sub('"confidence":"high"', '"confidence":"high","confidence":"low"',
        annotation_safety_json(), fixed = TRUE)
  )
  for (raw in invalid) {
    out <- scAgentKit:::.call_with_retry(function(system_prompt, user_prompt) raw,
      "system", "user", max_retries = 0, validator = scAgentKit:::.validate_annotation_response)
    expect_identical(out$annotation_status, "failed", info = raw)
    expect_true(is.na(out$primary_annotation), info = raw)
    expect_identical(out$recommended_action, "flag_for_review", info = raw)
    expect_length(attr(out, "response_audit"), 1L)
    expect_identical(attr(out, "response_audit")[[1]]$raw_response, raw)
  }
})

test_that("a two-argument provider can recover from a schema error and records both attempts", {
  calls <- 0L
  provider <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    if (calls == 1L) annotation_safety_response(primary_annotation = list("T cell", "B cell"))
    else annotation_safety_json()
  }
  out <- scAgentKit:::.call_with_retry(provider, "system", "user", 1L,
                                      validator = scAgentKit:::.validate_annotation_response)
  expect_identical(out$annotation_status, "ok")
  expect_equal(out$annotation_attempts, 2L)
  audit <- attr(out, "response_audit")
  expect_equal(vapply(audit, `[[`, character(1), "status"), c("failed", "ok"))
  expect_match(audit[[2]]$user_prompt, "previous response was invalid", fixed = TRUE)
  expect_true(nzchar(audit[[1]]$error))
})

test_that("provider errors and invalid return cardinality produce auditable failures", {
  providers <- list(function(system_prompt, user_prompt) stop("mock transport error"),
                    function(system_prompt, user_prompt) rep(annotation_safety_json(), 2),
                    function(system_prompt, user_prompt) NULL)
  for (provider in providers) {
    out <- scAgentKit:::.call_with_retry(provider, "sys", "user", 0L,
                                        validator = scAgentKit:::.validate_annotation_response)
    expect_identical(out$annotation_status, "failed")
    expect_true(nzchar(out$annotation_error))
    expect_length(attr(out, "response_audit"), 1L)
  }
})

test_that("ensemble counts valid schemas and preserves failed samples for review", {
  calls <- 0L
  provider <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    if (calls == 1L) "[]" else annotation_safety_json()
  }
  out <- scAgentKit:::.ensemble_annotate(provider, "sys", "user", n_samples = 2L, max_retries = 0L)
  expect_equal(out$ensemble_n, 1L)
  expect_identical(out$annotation_status, "partial")
  expect_identical(out$recommended_action, "flag_for_review")
  expect_equal(out$annotation_attempts, 2L)
  expect_length(attr(out, "response_audit"), 2L)
})

test_that("citation evidence includes only differential and displayed rescue genes", {
  filtered <- data.frame(cluster = "0", gene = "MKI67")
  rescue <- data.frame(gene = paste0("RESCUE", 1:31), pct_exp = 0.5, mean_exp = 1)
  bundle <- scAgentKit:::.annotation_marker_evidence("0", filtered, rescue)
  prompt <- scAgentKit:::.build_user_prompt("0", filtered, NULL,
    c("0" = 10), c("0" = 100), cycling_rescue = rescue, marker_evidence = bundle)
  expect_match(prompt, "RESCUE30", fixed = TRUE)
  expect_no_match(prompt, "RESCUE31", fixed = TRUE)
  val <- scAgentKit:::.validate_cited_markers(
    list(supporting_markers = c("RESCUE30", "RESCUE31")), bundle$citation_genes)
  expect_identical(val$hallucinated, "RESCUE31")
  expect_equal(val$rate, 0.5)
})

test_that("cycling rescue citations pass the same evidence used by the real prompt", {
  obj <- make_annotation_safety_fixture(cycling = TRUE)
  out <- annot_llm_annotate(obj, function(system_prompt, user_prompt) annotation_safety_json(),
                           "PBMC", max_retries = 0L, verbose = FALSE)
  expect_identical(out@params$llm_annotations$hallucinated_markers, "")
  expect_equal(out@params$llm_annotations$hallucination_rate, 0)
  evidence <- out@params$llm_annotation_responses[["0"]]$marker_evidence
  expect_false("CD3D" %in% evidence$differential$gene)
  expect_true("CD3D" %in% evidence$lineage_rescue$gene)
  expect_match(out@params$llm_annotation_responses[["0"]]$user_prompt, "CD3D", fixed = TRUE)
})

test_that("independent mode omits reference candidates and automatic author priors", {
  obj <- make_annotation_safety_fixture()
  seen <- NULL
  provider <- function(system_prompt, user_prompt) {
    seen <<- paste(system_prompt, user_prompt)
    annotation_safety_json()
  }
  out <- annot_llm_annotate(obj, provider, "PBMC", reference_mode = "independent",
                           max_retries = 0L, verbose = FALSE)
  expect_no_match(seen, "ACT_SECRET", fixed = TRUE)
  expect_no_match(seen, "AUTHOR_", fixed = TRUE)
  expect_no_match(seen, "Reference database candidates", fixed = TRUE)
  expect_match(seen, "CD3D", fixed = TRUE)
  audit <- out@params$llm_annotation_responses[["0"]]
  expect_identical(audit$reference_mode, "independent")
  expect_identical(audit$source_reference_candidates, obj@params$reference_matches)
  expect_identical(out@params$reference_matches, obj@params$reference_matches)
  expect_identical(audit$samples[[1]][[1]]$raw_response, annotation_safety_json())
  expect_identical(out@params$llm_annotation_input_cells$cell_id, colnames(obj@data))
  expect_identical(out@params$llm_annotation_input_cells$cluster, as.character(obj@data$seurat_clusters))
  expect_null(tail(out@decisions, 1)[[1]]$params$expected_celltypes)
  expect_true(is.na(tail(out@decisions, 1)[[1]]$params$metadata_prior_column))
  expect_identical(out@params$llm_annotations$annotation_status, "ok")
  cache_path <- tempfile(fileext = ".rds")
  saveRDS(out, cache_path)
  cached <- readRDS(cache_path)
  unlink(cache_path)
  expect_identical(cached@params$llm_annotation_responses, out@params$llm_annotation_responses)
  expect_identical(cached@params$llm_annotations, out@params$llm_annotations)

  guided <- annot_llm_annotate(obj, provider, "PBMC", max_retries = 0L, verbose = FALSE)
  expect_match(seen, "ACT_SECRET_LABEL", fixed = TRUE)
  expect_match(seen, "AUTHOR_ALPHA", fixed = TRUE)
  expect_identical(guided@params$llm_annotation_responses[["0"]]$reference_mode, "guided")
})

test_that("independent mode still accepts explicit caller priors", {
  seen <- NULL
  out <- annot_llm_annotate(make_annotation_safety_fixture(),
    function(system_prompt, user_prompt) { seen <<- system_prompt; annotation_safety_json() },
    "PBMC", expected_celltypes = "T cell", strict_vocabulary = TRUE,
    reference_mode = "independent", max_retries = 0L, verbose = FALSE)
  expect_match(seen, "VOCABULARY (strict)", fixed = TRUE)
  expect_no_match(seen, "AUTHOR_", fixed = TRUE)
  expect_identical(out@params$llm_annotations$annotation_status, "ok")
})

test_that("a mismatched model cluster echo yields a single failed cluster row", {
  out <- annot_llm_annotate(make_annotation_safety_fixture(),
    function(system_prompt, user_prompt) annotation_safety_response(cluster = "9"),
    "PBMC", max_retries = 0L, verbose = FALSE)
  expect_equal(nrow(out@params$llm_annotations), 1L)
  expect_identical(out@params$llm_annotations$cluster, "0")
  expect_identical(out@params$llm_annotations$annotation_status, "failed")
  expect_equal(out@params$llm_annotations$ensemble_n, 0L)
  expect_true(is.na(out@params$llm_annotations$hybrid_confidence))
  expect_false(tail(out@decisions, 1)[[1]]$success)
  expect_identical(out@stage, "llm_annotation_failed")
  expect_identical(out@params$llm_annotation_summary$status, "failed")
})

test_that("all-invalid public annotation calls preserve failure rows and audits", {
  out <- annot_llm_annotate(make_annotation_safety_fixture(),
    function(system_prompt, user_prompt) "{}", "PBMC", max_retries = 0L, verbose = FALSE)
  expect_identical(out@params$llm_annotations$annotation_status, "failed")
  expect_true(is.na(out@params$llm_annotations$primary_annotation))
  expect_identical(out@params$llm_annotations$recommended_action, "flag_for_review")
  expect_false(tail(out@decisions, 1)[[1]]$success)
  expect_identical(out@params$llm_annotation_responses[["0"]]$samples[[1]][[1]]$raw_response, "{}")
})

test_that("strict cycling vocabulary preserves literal labels while recording state", {
  seen <- NULL
  out <- annot_llm_annotate(make_annotation_safety_fixture(cycling = TRUE),
    function(system_prompt, user_prompt) { seen <<- user_prompt; annotation_safety_json() },
    "PBMC", expected_celltypes = "T cell", strict_vocabulary = TRUE,
    reference_mode = "independent", max_retries = 0L, verbose = FALSE)
  expect_match(seen, "strict vocabulary takes precedence", fixed = TRUE)
  expect_no_match(seen, "MANDATORY format", fixed = TRUE)
  expect_no_match(seen, "do NOT use 'Unknown'", fixed = TRUE)
  expect_identical(out@params$llm_annotations$primary_annotation, "T cell")
  expect_identical(out@params$llm_annotations$annotation_status, "ok")
  expect_true(out@params$llm_annotation_responses[["0"]]$marker_evidence$cycling_dominant)
})

test_that("exported annotation snippets replay saved outcomes without provider calls", {
  for (raw in c(annotation_safety_json(), "{}")) {
    obj <- make_annotation_safety_fixture()
    out <- annot_llm_annotate(obj, function(system_prompt, user_prompt) raw,
      "PBMC", reference_mode = "independent", max_retries = 0L, verbose = FALSE)
    script <- tail(out@scripts, 1)[[1]]
    replay <- new.env(parent = globalenv())
    replay$obj <- obj
    replay$chat_fn <- function(...) stop("offline replay must not call providers")
    eval(parse(text = script), envir = replay)
    expect_identical(replay$obj@params$llm_annotations, out@params$llm_annotations)
    expect_identical(replay$obj@params$llm_annotation_responses, out@params$llm_annotation_responses)
    expect_identical(replay$obj@params$llm_annotation_input_cells, out@params$llm_annotation_input_cells)
    expect_identical(replay$obj@params$llm_annotation_summary, out@params$llm_annotation_summary)
    expect_identical(replay$obj@stage, out@stage)
    pure <- new.env(parent = baseenv())
    pure$seurat_obj <- obj@data
    pure$chat_fn <- function(...) stop("offline replay must not call providers")
    eval(parse(text = script), envir = pure)
    expect_identical(pure$.scagentkit_annotation_cache$annotations, out@params$llm_annotations)
    expect_identical(pure$.scagentkit_annotation_cache$input_cells, out@params$llm_annotation_input_cells)
    expect_false(exists("obj", envir = pure, inherits = FALSE))
    replay$obj@data$seurat_clusters <- rep("9", 10)
    expect_error(eval(parse(text = script), envir = replay), "cell IDs/order and per-cell cluster IDs", fixed = TRUE)
    replay$obj <- AgentSeurat(Seurat::RenameCells(obj@data, new.names = paste0("OTHER", 1:10)))
    expect_error(eval(parse(text = script), envir = replay), "cell IDs/order and per-cell cluster IDs", fixed = TRUE)
  }
})

test_that("partial public ensembles cannot claim full step success", {
  calls <- 0L
  out <- annot_llm_annotate(make_annotation_safety_fixture(),
    function(system_prompt, user_prompt) {
      calls <<- calls + 1L
      if (calls == 1L) "{}" else annotation_safety_json()
    }, "PBMC", n_samples = 2L, max_retries = 0L, verbose = FALSE)
  expect_identical(out@params$llm_annotation_summary$status, "partial")
  expect_identical(out@stage, "llm_annotation_review")
  expect_false(tail(out@decisions, 1)[[1]]$success)
})

test_that("annotation replay preserves arbitrary real marker and reference doubles bitwise", {
  obj <- make_annotation_safety_fixture()
  obj@params$markers_filtered$p_val <- 1.234567891234567e-124
  obj@params$markers_filtered$p_val_adj <- 3.0451197119418794e-12
  obj@params$markers_filtered$avg_log2FC <- 1.0641129340914346
  obj@params$markers_filtered$pct.1 <- 2 / 3
  obj@params$markers_filtered$pct.2 <- 1 / 3
  obj@params$markers_filtered$pct_diff <- 2 / 3 - 1 / 3
  obj@params$reference_matches$score <- 1 / 3
  out <- annot_llm_annotate(obj, function(system_prompt, user_prompt) annotation_safety_json(),
    "PBMC", max_retries = 0L, verbose = FALSE)
  script <- tail(out@scripts, 1L)[[1L]]
  expect_match(script, "0x", fixed = TRUE)
  replay <- new.env(parent = baseenv())
  replay$obj <- obj
  eval(parse(text = script), envir = replay)
  expect_identical(replay$obj@params$llm_annotations, out@params$llm_annotations)
  expect_identical(replay$obj@params$llm_annotation_responses, out@params$llm_annotation_responses)
  expect_identical(replay$obj@params$llm_annotation_responses[["0"]]$marker_evidence$differential,
                   obj@params$markers_filtered)
  expect_identical(replay$obj@params$llm_annotation_responses[["0"]]$source_reference_candidates,
                   obj@params$reference_matches)
})

test_that("input cardinality and missing cluster IDs fail before any provider call", {
  obj <- make_annotation_safety_fixture()
  provider <- function(system_prompt, user_prompt) stop("provider must not be called")
  for (value in list(NA_real_, Inf, 1.5, c(1, 2))) {
    expect_error(annot_llm_annotate(obj, provider, "PBMC", n_samples = value), "positive integer")
  }
  expect_error(annot_llm_annotate(obj, provider, "PBMC", max_retries = -1), "non-negative integer")
  expect_error(annot_llm_annotate(obj, provider, "PBMC", clusters = "9", verbose = FALSE), "present in the filtered")
  obj@params$markers_filtered$cluster <- "9"
  expect_error(annot_llm_annotate(obj, provider, "PBMC", verbose = FALSE), "must be present in seurat_clusters")
})
