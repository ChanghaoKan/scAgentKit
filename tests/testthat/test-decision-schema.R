decision_parse <- function(raw) jsonlite::fromJSON(raw, simplifyVector = FALSE)

decision_provider <- function(replies) {
  i <- 0L
  function(system_prompt, user_prompt, image_path = NULL) {
    i <<- i + 1L
    replies[[min(i, length(replies))]]
  }
}

test_that("PC decisions require an integer candidate and the full schema", {
  validate <- function(raw) scAgentKit:::.validate_pcs_decision(decision_parse(raw), c(10L, 20L))
  good <- '{"chosen_ndim":20,"confidence":"medium","reasoning":"The second panel separates major groups."}'
  expect_identical(validate(good)$chosen_ndim, 20L)
  invalid <- c(
    '{"chosen_ndim":"20","confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":20.9,"confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":15,"confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":[20],"confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":null,"confidence":"medium","reasoning":"x"}',
    '{"chosen_ndim":20,"confidence":"certain","reasoning":"x"}',
    '{"chosen_ndim":20,"confidence":"medium","reasoning":" "}',
    '{"chosen_ndim":20,"confidence":"medium"}',
    '{"chosen_ndim":20,"confidence":"medium","reasoning":"x","chosen":10}',
    '{"chosen_ndim":10,"chosen_ndim":20,"confidence":"medium","reasoning":"x"}',
    '[{"chosen_ndim":20,"confidence":"medium","reasoning":"x"}]'
  )
  for (raw in invalid) expect_error(validate(raw))
  for (bad in c(NA_real_, NaN, Inf, -Inf)) {
    parsed <- decision_parse(good)
    parsed$chosen_ndim <- bad
    expect_error(scAgentKit:::.validate_pcs_decision(parsed, c(10L, 20L)), "finite")
  }
})

test_that("PC retries validate schema and preserve successful and failed raw replies", {
  bad <- '{"chosen_ndim":"20","confidence":"high","reasoning":"bad type"}'
  good <- '{"chosen_ndim":20,"confidence":"medium","reasoning":"The second panel is clearer."}'
  out <- scAgentKit:::.pcs_call_with_retry(decision_provider(list(bad, good)), "system", "user",
                                          candidates = c(10L, 20L), max_retries = 1)
  expect_identical(out$chosen_ndim, 20L)
  expect_identical(out$status, "ok")
  expect_equal(out$attempts, 2)
  expect_identical(out$response_audit[[1]]$raw_response, bad)
  expect_identical(out$response_audit[[1]]$status, "failed")
  expect_match(out$response_audit[[1]]$error, "integer")
  expect_identical(out$response_audit[[2]]$raw_response, good)
  expect_warning(fallback <- scAgentKit:::.pcs_call_with_retry(
    decision_provider(list(bad)), "system", "user", candidates = c(10L, 20L, 30L), max_retries = 0
  ), "median candidate")
  expect_equal(fallback$chosen_ndim, 20L)
  expect_identical(fallback$status, "fallback")
  expect_identical(fallback$confidence, "low")
  expect_match(fallback$error, "integer")
})

test_that("resolution decisions are restricted to swept and visible candidates", {
  validate <- function(raw, panels = numeric(), vision = FALSE) {
    scAgentKit:::.validate_resolution_decision(decision_parse(raw), c(0.2, 0.4, 0.6), panels, vision)
  }
  good <- '{"chosen_resolution":0.4,"confidence":"high","alternatives":[0.2,0.6],"reasoning":"ARI is stable at 0.4."}'
  expect_equal(validate(good)$alternatives, c(0.2, 0.6))
  invalid <- c(
    '{"chosen_resolution":"0.4","confidence":"high","alternatives":[],"reasoning":"x"}',
    '{"chosen_resolution":0.35,"confidence":"high","alternatives":[],"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":["high"],"alternatives":[],"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":"high","alternatives":["0.2"],"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":"high","alternatives":[0.9],"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":"high","alternatives":0.2,"reasoning":"x"}',
    '{"chosen_resolution":0.4,"confidence":"high","alternatives":null,"reasoning":"x"}'
  )
  for (raw in invalid) expect_error(validate(raw))
  expect_error(validate(good, c(0.2, 0.6)), "supplied candidates")
  expect_error(validate(good, vision = TRUE), "Missing decision fields")
  with_notes <- sub('"reasoning":', '"visual_notes":"Panels show coherent groups.","reasoning":', good, fixed = TRUE)
  expect_equal(validate(with_notes, c(0.2, 0.4), TRUE)$chosen_resolution, 0.4)
  expect_error(validate(sub("Panels show coherent groups.", " ", with_notes, fixed = TRUE), vision = TRUE), "non-empty")
  for (bad in c(NA_real_, NaN, Inf, -Inf)) {
    parsed <- decision_parse(good)
    parsed$chosen_resolution <- bad
    expect_error(scAgentKit:::.validate_resolution_decision(parsed, c(0.2, 0.4, 0.6)), "finite")
  }
})

test_that("invalid resolution replies fail visibly without snapping or indexing errors", {
  bad <- '{"chosen_resolution":0.35,"confidence":"high","alternatives":[],"reasoning":"Invented resolution."}'
  expect_warning(out <- scAgentKit:::.resolution_call_with_retry(
    decision_provider(list(bad)), "system", "user", res_values = c(0.2, 0.4), max_retries = 0
  ), "no resolution recommended")
  expect_true(is.na(out$chosen_resolution))
  expect_identical(out$status, "failed")
  expect_identical(out$confidence, "low")
  expect_identical(out$response_audit[[1]]$raw_response, bad)
  expect_warning(failed <- scAgentKit:::.resolution_call_with_retry(
    function(...) stop("Mock provider unavailable"), "system", "user",
    res_values = c(0.2, 0.4), max_retries = 1
  ), "no resolution recommended")
  expect_true(is.na(failed$chosen_resolution))
  expect_equal(failed$attempts, 2)
  expect_match(failed$error, "Mock provider unavailable")
})

test_that("batch decisions validate all fields and refuse invented metadata columns", {
  validate <- function(raw) scAgentKit:::.validate_batch_decision(decision_parse(raw), c("sample", "donor"))
  good <- '{"recommended":"sample","confidence":"medium","alternatives":["donor"],"warnings":[],"reasoning":"Samples capture technical variation."}'
  expect_identical(validate(good)$alternatives, "donor")
  expect_identical(validate(good)$warnings, character())
  invalid <- c(
    '{"recommended":["sample"],"confidence":"medium","alternatives":[],"warnings":[],"reasoning":"x"}',
    '{"recommended":"invented","confidence":"medium","alternatives":[],"warnings":[],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"sure","alternatives":[],"warnings":[],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":["invented"],"warnings":[],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":"donor","warnings":[],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":[],"warnings":{"risk":"x"},"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":[],"warnings":[false],"reasoning":"x"}',
    '{"recommended":"sample","confidence":"medium","alternatives":[],"reasoning":"x"}'
  )
  for (raw in invalid) expect_error(validate(raw))
})

test_that("batch failure retains candidates and requires explicit integration selection", {
  scored <- data.frame(column = c("sample", "donor"), n_levels = c(2, 2),
                       median_size = c(50, 50), smallest_size = c(50, 50),
                       name_match = c(TRUE, TRUE), looks_biological = c(FALSE, FALSE), score = c(4, 4))
  bad <- '{"recommended":"sample","confidence":"high","alternatives":["invented"],"warnings":[],"reasoning":"x"}'
  expect_warning(out <- scAgentKit:::.llm_pick_batch_var(scored, decision_provider(list(bad)), max_retries = 0),
                 "no batch variable recommended")
  expect_null(out$recommended)
  expect_identical(out$status, "failed")
  expect_identical(out$response_audit[[1]]$raw_response, bad)
  expect_match(out$error, "alternatives")
  expect_match(out$prompts$user, "sample")
})

test_that("resolution and batch public workflows retain failure audits in decisions", {
  skip_if_not_installed("SeuratObject")
  counts <- matrix(seq_len(18), nrow = 3,
                   dimnames = list(paste0("gene", 1:3), paste0("cell", 1:6)))
  seu <- SeuratObject::CreateSeuratObject(methods::as(counts, "dgCMatrix"))
  seu$sample <- rep(c("s1", "s2"), each = 3)
  seu$RNA_snn_res.0.2 <- rep(c("0", "1"), each = 3)
  seu$RNA_snn_res.0.4 <- rep(c("0", "1", "2"), each = 2)
  obj <- AgentSeurat(seu)
  expect_warning(out <- sc_resolution_recommend(
    obj, decision_provider(list('{"chosen_resolution":0.3,"confidence":"high","alternatives":[],"reasoning":"x"}')),
    tissue = "PBMC", vision = FALSE, max_retries = 0
  ), "no resolution recommended")
  expect_true(is.na(out@params$resolution_recommendation$chosen))
  expect_identical(out@params$resolution_recommendation$status, "failed")
  expect_identical(tail(out@decisions, 1)[[1]]$params$decision_status, "failed")
  expect_identical(tail(out@decisions, 1)[[1]]$success, FALSE)
  expect_equal(out@data@meta.data, obj@data@meta.data)
  expect_warning(batch <- sc_select_batch_var(obj,
    chat_fn = decision_provider(list('{"recommended":"unknown"}')), max_retries = 0
  ), "no batch variable recommended")
  expect_identical(batch@params$batch_candidates$column, "sample")
  expect_null(batch@params$batch_recommendation$recommended)
  expect_identical(batch@params$batch_recommendation$status, "failed")
  expect_identical(tail(batch@decisions, 1)[[1]]$success, FALSE)
  expect_equal(batch@data@meta.data, obj@data@meta.data)
  good_resolution <- '{"chosen_resolution":0.4,"confidence":"medium","alternatives":[0.2],"reasoning":"Stable clustering."}'
  ok <- sc_resolution_recommend(obj, decision_provider(list(good_resolution)),
                                 tissue = "PBMC", vision = FALSE, max_retries = 0)
  expect_identical(tail(ok@decisions, 1)[[1]]$success, TRUE)
  good_batch <- '{"recommended":"sample","confidence":"medium","alternatives":[],"warnings":[],"reasoning":"Technical batches."}'
  batch_ok <- sc_select_batch_var(obj, chat_fn = decision_provider(list(good_batch)), max_retries = 0)
  expect_identical(tail(batch_ok@decisions, 1)[[1]]$success, TRUE)
  scored_only <- sc_select_batch_var(obj)
  expect_identical(tail(scored_only@decisions, 1)[[1]]$success, TRUE)
})

test_that("PC candidate inputs fail before running UMAP or requesting a model", {
  skip_if_not_installed("SeuratObject")
  counts <- matrix(seq_len(18), nrow = 3,
                   dimnames = list(paste0("gene", 1:3), paste0("cell", 1:6)))
  seu <- SeuratObject::CreateSeuratObject(methods::as(counts, "dgCMatrix"))
  embeddings <- matrix(seq_len(12), ncol = 2,
                       dimnames = list(colnames(seu), c("PC_1", "PC_2")))
  seu[["pca"]] <- SeuratObject::CreateDimReducObject(embeddings = embeddings,
                                                  stdev = c(2, 1), key = "PC_", assay = "RNA")
  obj <- AgentSeurat(seu)
  never_called <- function(...) stop("Unexpected model request")
  for (invalid in list(c(0, 1), c(1, 1.9), c(NA, 1), c(1, Inf), c("1", "2"))) {
    expect_error(sc_select_pcs_visual(obj, never_called, candidates = invalid), "positive finite integer")
  }
  for (invalid in list(NA_real_, Inf, "0.8", numeric(), c(0.8, 1))) {
    expect_error(sc_select_pcs_visual(obj, never_called, variance_thresholds = invalid), "finite numeric")
  }
})

test_that("PC public workflow records a model fallback as an unsuccessful decision", {
  skip_if_not_installed("SeuratObject")
  counts <- matrix(seq_len(18), nrow = 3,
                   dimnames = list(paste0("gene", 1:3), paste0("cell", 1:6)))
  seu <- SeuratObject::CreateSeuratObject(methods::as(counts, "dgCMatrix"))
  seu$sample <- rep(c("s1", "s2"), each = 3)
  embeddings <- matrix(seq_len(12), ncol = 2,
                       dimnames = list(colnames(seu), c("PC_1", "PC_2")))
  seu[["pca"]] <- SeuratObject::CreateDimReducObject(embeddings = embeddings,
                                                  stdev = c(2, 1), key = "PC_", assay = "RNA")
  obj <- AgentSeurat(seu)
  # This test checks the public decision/audit path. Plot rendering and UMAP
  # are independent, so stub them to keep the regression deterministic.
  testthat::local_mocked_bindings(
    RunUMAP = function(object, ...) object,
    DimPlot = function(...) ggplot2::ggplot(), .package = "Seurat"
  )
  testthat::local_mocked_bindings(ggsave = function(...) invisible(NULL), .package = "ggplot2")
  testthat::local_mocked_bindings(
    .compose_panel_grid_safe = function(paths, out_path, ...) out_path,
    .package = "scAgentKit"
  )
  out_dir <- tempfile("pcs-schema-")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  expect_warning(out <- sc_select_pcs_visual(
    obj, decision_provider(list('{"chosen_ndim":"2","confidence":"high","reasoning":"x"}')),
    candidates = c(1L, 2L), batch_var = "sample", out_dir = out_dir, max_retries = 0
  ), "median candidate")
  expect_identical(out@params$pcs_visual_recommendation$status, "fallback")
  expect_identical(tail(out@decisions, 1)[[1]]$params$decision_status, "fallback")
  expect_identical(tail(out@decisions, 1)[[1]]$success, FALSE)
  expect_identical(out@params$ndim, 1L)
  expect_equal(out@data@meta.data, obj@data@meta.data)
  ok <- sc_select_pcs_visual(
    obj, decision_provider(list('{"chosen_ndim":2,"confidence":"medium","reasoning":"The second panel is clearer."}')),
    candidates = c(1L, 2L), batch_var = "sample", out_dir = out_dir, max_retries = 0
  )
  expect_identical(tail(ok@decisions, 1)[[1]]$success, TRUE)
})
