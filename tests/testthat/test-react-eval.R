eval_ontology <- function() list(
  name = c("CL:0000000" = "cell", "CL:0000001" = "lymphocyte",
    "CL:0000002" = "T cell", "CL:0000003" = "B cell", "CL:0000004" = "naive T cell"),
  parents = list("CL:0000000" = character(), "CL:0000001" = "CL:0000000",
    "CL:0000002" = "CL:0000001", "CL:0000003" = "CL:0000001",
    "CL:0000004" = "CL:0000002"))

test_that("versioned scoring separates unmapped, Unknown and directed parents", {
  cl <- eval_ontology()
  truth <- data.frame(cluster_id = letters[1:4], cl_id = rep("CL:0000004", 4),
    status = "mapped")
  prediction <- data.frame(cluster_id = letters[1:4],
    cl_id = c("CL:0000002", NA, NA, "CL:0000004"),
    status = c("mapped", "unmapped", "unknown", "mapped"))
  score <- .sc_react_eval_score(truth, prediction, cl, "CL:0000002")
  expect_equal(score$denominator, 3)
  expect_equal(score$strict_denominator, 4)
  expect_equal(score$accuracy_exact, 1 / 3)
  expect_equal(score$accuracy_hierarchical, 2 / 3)
  expect_equal(score$strict_accuracy_hierarchical, .5)
  expect_equal(score$unknown_fraction, .25)
  expect_equal(.sc_react_eval_score(truth, prediction, cl, character())$accuracy_hierarchical, 1 / 3)
  expect_true(is.na(.sc_react_eval_score(truth[FALSE, ], prediction[FALSE, ], cl, character())$accuracy_exact))
})

test_that("cell labels use frozen 80/80 denominators and exact CL mapping", {
  cl <- eval_ontology()
  membership <- data.frame(cell_id = as.character(1:10), cluster = "0")
  labels <- data.frame(cell_id = as.character(1:10), label = c(rep("T cell", 8), "B cell", "unknown"))
  result <- .sc_react_eval_labels(labels, membership, NULL, cl, TRUE)
  expect_identical(result$cl_id, "CL:0000002")
  expect_equal(result$valid_fraction, .9)
  labels$label[8] <- "unmapped label"
  result <- .sc_react_eval_labels(labels, membership, NULL, cl, TRUE)
  expect_equal(result$majority_fraction, 7 / 8)
  labels$label[7] <- "unmapped label"
  expect_identical(.sc_react_eval_labels(labels, membership, NULL, cl, TRUE)$status, "unmapped")
  labels$cl_id <- "CL:0000003"
  expect_error(.sc_react_eval_labels(labels, membership, NULL, cl, TRUE), "contradict")
})

test_that("dual truth consensus excludes disagreements without consulting predictions", {
  cl <- eval_ontology()
  truth <- data.frame(cell_id = c("b", "a", "c"),
    label_author = c("T cell", "naive T cell", "unmapped"),
    label_independent = c("B cell", "T cell", "T cell"))
  result <- .sc_react_eval_truths(truth, NULL, cl, "CL:0000002")
  agreement <- attr(result, "agreement")
  expect_identical(agreement$cell_id, c("a", "b", "c"))
  expect_identical(agreement$hierarchical, c(TRUE, FALSE, FALSE))
  expect_identical(result$primary$status, c("truth", "annotator_disagreement", "annotator_disagreement"))
  expect_identical(result$author$label, truth$label_author)
  expect_identical(result$independent$label, truth$label_independent)
  expect_error(.sc_react_eval_truths(truth[, -3], NULL, cl, character()), "requires")
})

test_that("unknown usage never becomes a known zero measurement", {
  result <- .sc_react_eval_accounting(list(list(usage = list()), list(
    cost_usd = .01, usage = list(input_tokens = 10, output_tokens = 2))))
  expect_equal(result$cost$recorded, .01)
  expect_equal(result$cost$unknown_calls, 1)
  expect_equal(result$input_tokens$recorded, 10)
  expect_true(is.na(.sc_react_eval_accounting(list())$cost$recorded))
})

test_that("saved paired drafts export cell and cluster metrics without network or approval", {
  skip_if_not_installed("ontologyIndex")
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  .sc_run_react_refine(f$root, f$baseline, react_mock())
  obo <- tempfile(fileext = ".obo"); on.exit(unlink(obo), add = TRUE)
  writeLines(c("format-version: 1.2", "", "[Term]", "id: CL:0000002",
    "name: T cell", "", "[Term]", "id: CL:0000003", "name: B cell"), obo)
  truth <- data.frame(cell_id = f$cells, label_author = "T cell", label_independent = "T cell")
  truth$label_independent[1] <- "B cell"
  external <- data.frame(cell_id = f$cells, label = "not mapped")
  before <- .sc_project_sha_file(file.path(f$root, "state.rds"))
  testthat::local_mocked_bindings(req_perform = function(...) stop("No network"), .package = "httr2")
  result <- sc_react_eval(f$root, truth, external = list(other = external), obo_path = obo)
  select <- function(method, unit = "cluster") result$metrics[
    result$metrics$method == method & result$metrics$unit == unit &
      result$metrics$truth_source == "primary" & result$metrics$scope == "all", ]
  expect_equal(select("react")$accuracy_exact, 1)
  expect_equal(select("baseline")$accuracy_exact, 0)
  expect_true(is.na(select("other")$accuracy_exact))
  expect_equal(select("other")$strict_accuracy_exact, 0)
  expect_equal(select("react", "cell")$strict_denominator, 11)
  expect_equal(sum(result$annotator_agreement$disagreement), 1)
  expect_equal(nrow(result$steps), 2)
  expect_true(all(file.exists(file.path(result$output_dir,
    c("metrics.csv", "cells.csv", "steps.csv", "evaluation.json", "annotator_agreement.csv")))))
  expect_identical(.sc_project_sha_file(file.path(f$root, "state.rds")), before)
})
