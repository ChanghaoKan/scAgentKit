make_clean_celltypes_fixture <- function() {
  counts <- matrix(
    c(2, 1, 3, 0, 1, 2, 0, 3, 2, 1, 1, 4), nrow = 2,
    dimnames = list(c("G1", "G2"), paste0("C", 1:6))
  )
  seu <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(counts, sparse = TRUE))
  seu$cell_type <- c("T cells", "T cells", "T cells", "B cells", "B cells", "Artifact")
  AgentSeurat(seu)
}

mock_clean_image <- function(env = parent.frame()) {
  testthat::local_mocked_bindings(
    .clean_celltypes_vision_image = function(...) "mock-umap.png",
    .package = "scAgentKit", .env = env
  )
}

clean_response <- function(decision, reasoning = "Review the small group.") {
  jsonlite::toJSON(list(decision = decision, reasoning = reasoning),
                   auto_unbox = TRUE)
}

test_that("keep is parsed from its field even when reasoning says do not remove", {
  mock_clean_image()
  out <- annot_clean_celltypes(
    make_clean_celltypes_fixture(), min_cells = 2, action = "remove", vision = TRUE,
    chat_fn = function(...) clean_response("keep", "Rare cells: do not remove.")
  )
  expect_identical(colnames(out@data), paste0("C", 1:6))
  expect_identical(unname(out@data$cell_type[6]), "Artifact")
  decision <- tail(out@decisions, 1)[[1]]$params
  expect_identical(decision$requested_action, "remove")
  expect_identical(decision$action, "keep")
  expect_identical(decision$vision_result$decision, "keep")
  expect_identical(decision$vision_result$status, "succeeded")
  expect_match(decision$vision_result$raw_response, "do not remove")
  expect_true(tail(out@decisions, 1)[[1]]$success)
})

test_that("vision cannot escalate the caller's retaining actions", {
  mock_clean_image()
  for (requested in c("flag", "keep")) {
    out <- annot_clean_celltypes(
      make_clean_celltypes_fixture(), min_cells = 2, action = requested, vision = TRUE,
      chat_fn = function(...) clean_response("remove")
    )
    expect_equal(ncol(out@data), 6)
    expect_identical(tail(out@decisions, 1)[[1]]$params$action, requested)
    expect_identical(tail(out@decisions, 1)[[1]]$params$vision_result$decision, "remove")
  }
  kept <- annot_clean_celltypes(
    make_clean_celltypes_fixture(), min_cells = 2, action = "keep", vision = TRUE,
    chat_fn = function(...) clean_response("flag")
  )
  expect_identical(unname(kept@data$cell_type[6]), "Artifact")
  expect_identical(unname(kept@data$cell_type_quality[6]), "candidate")
})

test_that("explicit removal honors a validated remove decision", {
  mock_clean_image()
  out <- annot_clean_celltypes(
    make_clean_celltypes_fixture(), min_cells = 2, action = "remove", vision = TRUE,
    chat_fn = function(...) clean_response("remove", "Independently review contamination.")
  )
  expect_identical(colnames(out@data), paste0("C", 1:5))
  expect_true(all(out@data$cell_type_quality == "normal"))
  decision <- tail(out@decisions, 1)[[1]]$params
  expect_identical(decision$action, "remove")
  expect_equal(decision$n_cells_before, 6)
  expect_equal(decision$n_cells_after, 5)
  expect_identical(decision$removed_cell_ids, "C6")
})

test_that("the vision schema rejects invalid action objects instead of scanning prose", {
  mock_clean_image()
  invalid <- c(
    "keep; do not remove",
    '```json\n{"decision":"remove","reasoning":"Review."}\n```',
    '[]',
    '{"decision":"remove"}',
    '{"decision":"REMOVE","reasoning":"Review."}',
    '{"decision":["remove"],"reasoning":"Review."}',
    '{"decision":"remove","reasoning":42}',
    '{"decision":"remove","reasoning":null}',
    '{"decision":"remove","reasoning":"  "}',
    '{"decision":"keep","decision":"remove","reasoning":"Review."}',
    '{"decision":"remove","reasoning":"Review.","unexpected":true}'
  )
  for (raw in invalid) {
    expect_warning(
      out <- annot_clean_celltypes(
        make_clean_celltypes_fixture(), min_cells = 2, action = "remove", vision = TRUE,
        chat_fn = function(...) raw
      ), "Vision judgment failed; keeping cells"
    )
    expect_equal(ncol(out@data), 6)
    expect_length(out@decisions, 1)
    audit <- out@decisions[[1]]$params
    expect_identical(audit$action, "keep")
    expect_identical(audit$vision_result$status, "failed")
    expect_identical(audit$vision_result$raw_response, raw)
    expect_type(audit$vision_result$error, "character")
    expect_false(out@decisions[[1]]$success)
  }
})

test_that("provider exceptions and non-string replies keep cells and retain failures", {
  mock_clean_image()
  providers <- list(
    function(...) stop("mock provider unavailable"),
    function(...) NULL,
    function(...) list(decision = "remove", reasoning = "Review."),
    function(...) c('{"decision":"remove","reasoning":"Review."}', "extra reply")
  )
  for (provider in providers) {
    expect_warning(
      out <- annot_clean_celltypes(
        make_clean_celltypes_fixture(), min_cells = 2, action = "remove", vision = TRUE,
        chat_fn = provider
      ), "Vision judgment failed; keeping cells"
    )
    expect_identical(colnames(out@data), paste0("C", 1:6))
    audit <- tail(out@decisions, 1)[[1]]$params
    expect_identical(audit$action, "keep")
    expect_identical(audit$vision_result$status, "failed")
    expect_true(nzchar(audit$vision_result$error))
    expect_false(tail(out@decisions, 1)[[1]]$success)
  }
})

test_that("plot failure is audited without contacting the provider or deleting cells", {
  testthat::local_mocked_bindings(
    .clean_celltypes_vision_image = function(...) stop("mock plot failure"),
    .package = "scAgentKit"
  )
  calls <- 0L
  expect_warning(
    out <- annot_clean_celltypes(
      make_clean_celltypes_fixture(), min_cells = 2, action = "remove", vision = TRUE,
      chat_fn = function(...) { calls <<- calls + 1L; clean_response("remove") }
    ), "mock plot failure"
  )
  expect_identical(calls, 0L)
  expect_equal(ncol(out@data), 6)
  expect_match(out@decisions[[1]]$params$vision_result$error, "mock plot failure")
})

test_that("no-candidate calls retain a complete audit and do not contact vision", {
  calls <- 0L
  out <- annot_clean_celltypes(
    make_clean_celltypes_fixture(), min_cells = 1, vision = TRUE,
    chat_fn = function(...) { calls <<- calls + 1L; stop("unexpected provider call") }
  )
  expect_identical(calls, 0L)
  expect_length(out@decisions, 1)
  expect_length(out@decisions[[1]]$params$candidate_types, 0)
  expect_identical(out@decisions[[1]]$params$vision_result$status, "no_candidates")
  expect_true(all(out@data$cell_type_quality == "normal"))
  expect_setequal(unique(out@data$cell_type), c("T cell", "B cell", "Artifact"))
})

test_that("manual operations preserve audit records and removal cannot empty the object", {
  fixture <- make_clean_celltypes_fixture()
  flagged <- annot_clean_celltypes(fixture, min_cells = 2)
  expect_equal(ncol(flagged@data), 6)
  expect_identical(unname(flagged@data$cell_type[6]), "Artifact (Low quality)")
  expect_identical(unname(flagged@data$cell_type_quality[6]), "flagged")
  expect_length(flagged@decisions, 1)
  expect_identical(flagged@decisions[[1]]$params$vision_result$status, "not_requested")

  removed <- annot_clean_celltypes(fixture, min_cells = 2, action = "remove")
  expect_identical(colnames(removed@data), paste0("C", 1:5))
  expect_identical(removed@decisions[[1]]$params$action, "remove")

  expect_warning(
    empty_attempt <- annot_clean_celltypes(fixture, min_cells = 4, action = "remove"),
    "would remove every cell"
  )
  expect_equal(ncol(empty_attempt@data), 6)
  expect_identical(empty_attempt@decisions[[1]]$params$action, "keep")
  expect_match(empty_attempt@decisions[[1]]$params$removal_error, "every cell")
  expect_false(empty_attempt@decisions[[1]]$success)
})

test_that("saved cleaning scripts replay final cell IDs and labels without a model", {
  mock_clean_image()
  fixture <- make_clean_celltypes_fixture()
  calls <- 0L
  out <- annot_clean_celltypes(
    fixture, min_cells = 2, action = "remove", vision = TRUE,
    chat_fn = function(...) { calls <<- calls + 1L; clean_response("remove") }
  )
  replay <- new.env(parent = globalenv())
  replay$seurat_obj <- fixture@data
  eval(parse(text = tail(out@scripts, 1)), envir = replay)
  expect_identical(calls, 1L)
  expect_identical(colnames(replay$seurat_obj), colnames(out@data))
  expect_identical(replay$seurat_obj$cell_type, out@data$cell_type)
  expect_identical(replay$seurat_obj$cell_type_quality, out@data$cell_type_quality)
  expect_identical(out@decisions[[1]]$params$cleaning_result$cell_id, colnames(out@data))
  expect_identical(out@decisions[[1]]$params$cleaning_result$cell_type,
                   unname(out@data$cell_type))
  expect_match(tail(out@scripts, 1), "no model call")
  replay$seurat_obj <- fixture@data[, 1:5]
  expect_error(eval(parse(text = tail(out@scripts, 1)), envir = replay),
               "Replay input cell IDs differ")
})

test_that("real Seurat UMAP rendering preserves metadata and uses the image contract", {
  work_dir <- tempfile("clean-celltypes-plot-")
  dir.create(work_dir)
  withr::local_dir(work_dir)
  withr::defer(unlink(work_dir, recursive = TRUE))
  fixture <- make_clean_celltypes_fixture()
  coordinates <- matrix(seq_len(12) / 12, nrow = 6,
                        dimnames = list(colnames(fixture@data), c("UMAP_1", "UMAP_2")))
  fixture@data[["umap"]] <- SeuratObject::CreateDimReducObject(
    embeddings = coordinates, key = "UMAP_", assay = "RNA"
  )
  calls <- 0L
  out <- annot_clean_celltypes(
    fixture, min_cells = 2, vision = TRUE,
    chat_fn = function(system_prompt, user_prompt, image_path) {
      calls <<- calls + 1L
      expect_true(file.exists(image_path))
      expect_match(system_prompt, "exactly two fields")
      clean_response("keep")
    }
  )
  expect_identical(calls, 1L)
  expect_identical(colnames(out@data), paste0("C", 1:6))
  expect_false("quality_highlight" %in% colnames(out@data@meta.data))
  expect_identical(out@decisions[[1]]$params$vision_result$status, "succeeded")
  expect_match(out@decisions[[1]]$params$vision_result$system_prompt, "exactly two fields")
  expect_match(out@decisions[[1]]$params$vision_result$user_prompt, "Artifact")
})

test_that("invalid configuration is rejected before making a vision call", {
  fixture <- make_clean_celltypes_fixture()
  expect_error(annot_clean_celltypes(fixture, min_cells = 0), "positive integer")
  expect_error(annot_clean_celltypes(fixture, min_cells = 1.5), "positive integer")
  expect_error(annot_clean_celltypes(fixture, min_cells = NA_real_), "positive integer")
  expect_error(annot_clean_celltypes(fixture, vision = NA), "logical values")
  expect_error(annot_clean_celltypes(fixture, merge_plural = c(TRUE, FALSE)), "logical values")
  expect_error(annot_clean_celltypes(fixture, vision = TRUE), "must be a function")
})
