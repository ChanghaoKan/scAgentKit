legacy_visual_object <- function() {
  counts <- matrix(seq_len(18), nrow = 3,
    dimnames = list(paste0("gene", 1:3), paste0("cell", 1:6)))
  seu <- SeuratObject::CreateSeuratObject(methods::as(counts, "dgCMatrix"))
  seu$sample <- rep(c("s1", "s2"), each = 3)
  seu$RNA_snn_res.0.2 <- rep(c("0", "1"), each = 3)
  seu$RNA_snn_res.0.4 <- rep(c("0", "1", "2"), each = 2)
  seu[["pca"]] <- SeuratObject::CreateDimReducObject(
    embeddings = matrix(seq_len(12), ncol = 2,
      dimnames = list(colnames(seu), c("PC_1", "PC_2"))),
    stdev = c(2, 1), key = "PC_", assay = "RNA")
  AgentSeurat(seu)
}

legacy_mock_plots <- function(env = parent.frame()) {
  testthat::local_mocked_bindings(
    RunUMAP = function(object, ...) object,
    DimPlot = function(...) ggplot2::ggplot(), .package = "Seurat", .env = env)
  testthat::local_mocked_bindings(
    ggsave = function(...) invisible(NULL), .package = "ggplot2", .env = env)
}

test_that("missing compositors never masquerade as multi-panel evidence", {
  real_require <- base::requireNamespace
  testthat::local_mocked_bindings(requireNamespace = function(package, ...) {
    if (package %in% c("magick", "png")) return(FALSE)
    real_require(package, ...)
  }, .package = "base")
  paths <- c(tempfile(), tempfile())
  writeLines("first panel", paths[1]); writeLines("second panel", paths[2])
  out <- tempfile()
  on.exit(unlink(c(paths, out)), add = TRUE)
  expect_error(scAgentKit:::.compose_panel_grid_safe(paths, out, 1, 1, 72),
    "Could not compose all PC panels")
  expect_false(file.exists(out))
  expect_error(scAgentKit:::.compose_resolution_grid(NULL, paths, out, 1, 1, 72),
    "Could not compose all resolution panels")
  expect_false(file.exists(out))
})

test_that("both rendering backends failing remove incomplete comparisons", {
  real_require <- base::requireNamespace
  testthat::local_mocked_bindings(requireNamespace = function(package, ...) {
    if (package == "magick") return(TRUE)
    real_require(package, ...)
  }, .package = "base")
  # A valid magick installation (if present) also rejects these corrupt inputs;
  # otherwise namespace loading fails. The png fallback rejects them too.
  paths <- c(tempfile(fileext = ".png"), tempfile(fileext = ".png"))
  writeLines("corrupt first image", paths[1]); writeLines("corrupt second image", paths[2])
  out <- tempfile(fileext = ".png")
  on.exit(unlink(c(paths, out)), add = TRUE)
  expect_error(scAgentKit:::.compose_panel_grid_safe(paths, out, 2, 2, 72), "Could not compose")
  expect_false(file.exists(out))
  expect_error(scAgentKit:::.compose_resolution_grid(NULL, paths, out, 2, 2, 72), "Could not compose")
  expect_false(file.exists(out))
})

test_that("resolution composition failure sends only accurately described numeric evidence", {
  obj <- legacy_visual_object()
  testthat::local_mocked_bindings(
    .build_resolution_vision_panel = function(...) {
      scAgentKit:::.compose_resolution_grid(NULL, c("missing-a", "missing-b"), tempfile(), 1, 1, 72)
    }, .package = "scAgentKit")
  seen <- NULL
  mock <- function(system_prompt, user_prompt, image_path = NULL) {
    seen <<- list(system = system_prompt, user = user_prompt, image = image_path)
    '{"chosen_resolution":0.4,"confidence":"low","alternatives":[],"reasoning":"Numeric evidence only."}'
  }
  out <- sc_resolution_recommend(obj, mock, tissue = "mock", max_retries = 0)
  expect_null(seen$image)
  expect_match(seen$user, "No image supplied; decide from the numeric table alone", fixed = TRUE)
  expect_false(grepl("An image is attached showing UMAP", seen$user, fixed = TRUE))
  expect_identical(out@params$resolution_recommendation$status, "ok")
  expect_identical(out@params$resolution_recommendation$mode, "numeric_only")
  expect_length(out@params$resolution_recommendation$panels_used, 0L)
})

test_that("latest failed PC choice invalidates historical automatic ndim", {
  legacy_mock_plots()
  testthat::local_mocked_bindings(
    .compose_panel_grid_safe = function(paths, out_path, ...) out_path,
    .package = "scAgentKit")
  out_dir <- tempfile()
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  good <- function(...) '{"chosen_ndim":2,"confidence":"medium","reasoning":"Mock second panel."}'
  bad <- function(...) stop("Mock provider unavailable")
  select <- function(obj, chat_fn) sc_select_pcs_visual(obj, chat_fn,
    candidates = c(1L, 2L), batch_var = "sample", out_dir = out_dir, max_retries = 0)
  first <- select(legacy_visual_object(), good)
  expect_identical(first@params$ndim, 2L)
  expect_warning(second <- select(first, bad), "median candidate")
  expect_null(second@params$ndim)
  expect_identical(second@params$pcs_visual_recommendation$previous_ndim, 2L)
  expect_identical(first@params$pcs_visual_recommendation$status, "ok")
  expect_error(sc_umap(second), "latest visual PC selection failed")
  expect_s4_class(sc_umap(second, ndim = 2L), "AgentSeurat")
  third <- select(second, good)
  expect_identical(third@params$ndim, 2L)
  expect_s4_class(sc_umap(third), "AgentSeurat")
})

test_that("PC composition failure stops before the model call", {
  legacy_mock_plots()
  testthat::local_mocked_bindings(.compose_panel_grid_safe = function(...) {
    stop("Could not compose all PC panels")
  }, .package = "scAgentKit")
  called <- FALSE
  out_dir <- tempfile()
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  expect_error(sc_select_pcs_visual(legacy_visual_object(), function(...) {
    called <<- TRUE
  }, candidates = c(1L, 2L), batch_var = "sample", out_dir = out_dir), "Could not compose")
  expect_false(called)
})

test_that("png fallback composes all supplied PC and resolution panels", {
  skip_if_not_installed("png")
  real_require <- base::requireNamespace
  testthat::local_mocked_bindings(requireNamespace = function(package, ...) {
    if (package == "magick") return(FALSE)
    real_require(package, ...)
  }, .package = "base")
  paths <- c(tempfile(fileext = ".png"), tempfile(fileext = ".png"))
  out <- tempfile(fileext = ".png")
  on.exit(unlink(c(paths, out)), add = TRUE)
  png::writePNG(array(c(rep(1, 100), rep(0, 200)), c(10, 10, 3)), paths[1])
  png::writePNG(array(c(rep(0, 200), rep(1, 100)), c(10, 10, 3)), paths[2])
  for (compose in list(
    function() scAgentKit:::.compose_panel_grid_safe(paths, out, 2, 2, 72),
    function() scAgentKit:::.compose_resolution_grid(NULL, paths, out, 2, 2, 72))) {
    compose()
    image <- png::readPNG(out)
    expect_equal(dim(image)[1:2], c(144, 288))
    expect_gt(image[72, 72, 1], 0.9)
    expect_lt(image[72, 72, 3], 0.1)
    expect_gt(image[72, 216, 3], 0.9)
    expect_lt(image[72, 216, 1], 0.1)
  }
})
