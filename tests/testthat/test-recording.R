test_that("AgentSeurat constructor works on a minimal Seurat-like list input", {
  # Use a named list to exercise the seurat_list path. We don't need a
  # real Seurat object for the constructor itself; it only checks
  # list-vs-Seurat dispatch.
  fake_list <- list(s1 = "stub", s2 = "stub")
  obj <- AgentSeurat(fake_list,
                     initial_script = '# initial load')
  expect_s4_class(obj, "AgentSeurat")
  expect_equal(obj@data_type, "seurat_list")
  expect_equal(obj@stage, "initialized")
  expect_equal(length(obj@decisions), 0)
  expect_equal(obj@scripts, "# initial load")
  expect_true(inherits(obj@created_at, "POSIXct"))
})

test_that(".record_step accumulates decisions, scripts, and params", {
  fake_list <- list(s1 = "stub")
  obj <- AgentSeurat(fake_list)

  obj <- scAgentKit:::.record_step(
    obj,
    step_name      = "qc_threshold",
    function_name  = "qc_threshold",
    params         = list(min_nCount = 1000, min_nFeature = 500),
    rationale      = "Initial hard filter.",
    script_snippet = "# qc_threshold(min_nCount = 1000, ...)",
    new_stage      = "qc_filtered"
  )
  expect_equal(length(obj@decisions), 1)
  expect_equal(obj@decisions[[1]]$step, "qc_threshold")
  expect_equal(obj@stage, "qc_filtered")
  expect_equal(obj@params$min_nCount, 1000)
  expect_match(tail(obj@scripts, 1), "qc_threshold")
})

test_that(".record_step merges params instead of overwriting", {
  obj <- AgentSeurat(list(s1 = "stub"))
  obj <- scAgentKit:::.record_step(
    obj,
    step_name = "step1", function_name = "f1",
    params    = list(ndim = 30, foo = "a"),
    rationale = "", script_snippet = "", new_stage = NULL
  )
  obj <- scAgentKit:::.record_step(
    obj,
    step_name = "step2", function_name = "f2",
    params    = list(bar = 99),     # different key — must NOT wipe ndim
    rationale = "", script_snippet = "", new_stage = NULL
  )
  expect_equal(obj@params$ndim, 30)
  expect_equal(obj@params$foo, "a")
  expect_equal(obj@params$bar, 99)
})

test_that(".find_in_decisions retrieves most recent value", {
  obj <- AgentSeurat(list(s1 = "stub"))
  obj <- scAgentKit:::.record_step(
    obj,
    step_name = "sc_pca", function_name = "sc_pca",
    params    = list(ndim = 25),
    rationale = "", script_snippet = "", new_stage = NULL
  )
  obj <- scAgentKit:::.record_step(
    obj,
    step_name = "sc_select_pcs", function_name = "sc_select_pcs",
    params    = list(ndim = 30),
    rationale = "", script_snippet = "", new_stage = NULL
  )
  # Most recent wins
  expect_equal(scAgentKit:::.find_in_decisions(obj, "ndim"), 30)
  # Step-scoped lookup
  expect_equal(scAgentKit:::.find_in_decisions(obj, "ndim",
                                               from_step = "sc_pca"), 25)
  # Missing param
  expect_null(scAgentKit:::.find_in_decisions(obj, "no_such_param"))
})

test_that("get_decisions / get_script / get_figures accessors work", {
  obj <- AgentSeurat(list(s1 = "stub"), initial_script = "# load")
  obj <- scAgentKit:::.record_step(
    obj,
    step_name = "step1", function_name = "f1",
    params    = list(x = 1),
    rationale = "Step 1 rationale",
    script_snippet = "x <- 1",
    new_stage = NULL
  )
  expect_length(get_decisions(obj), 1)
  expect_match(get_script(obj), "x <- 1")
  expect_match(get_script(obj), "# load")
  expect_s3_class(get_figures(obj), "data.frame")
})
