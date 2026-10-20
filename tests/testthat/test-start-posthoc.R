test_that("posthoc project calls record costs without monetary holds and never resend uncertain delivery", {
  f <- react_tool_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  state <- .sc_run_load(f$root); state$config$cost_mode <- "posthoc"
  state$config_hash <- .sc_run_hash(state$config); .sc_run_save(f$root, state)
  provider <- list(name = "testremote", model = "offline-fixture", external = TRUE, reservation_usd = .05)
  request <- function(text) {
    x <- list(system_prompt = "Return JSON.", user_prompt = text, purpose = "annotation",
      evidence_hash = strrep("a", 64), validator = function(x) x)
    x$approved_payload_hash <- .sc_run_request_hash(x, provider); x
  }
  calls <- 0L
  answer <- .sc_run_call(f$root, request("public aggregate 1"), provider,
    function(...) { calls <<- calls + 1L; list(content = '{"valid":true}', cost_usd = 2,
      usage = list(input_tokens = 10, output_tokens = 5)) }, budget = 0, allow_external = TRUE)
  expect_identical(answer$status, "ok")
  expect_identical(answer$cost_mode, "posthoc")
  expect_equal(answer$reservation_usd, 0)
  expect_equal(answer$cost_usd, 2)
  unknown <- .sc_run_call(f$root, request("public aggregate 2"), provider,
    function(...) { calls <<- calls + 1L; '{"valid":true}' }, budget = 0, allow_external = TRUE)
  expect_identical(unknown$status, "ok"); expect_identical(unknown$cost_state, "unknown")
  uncertain <- .sc_run_call(f$root, request("public aggregate 3"), provider,
    function(...) { calls <<- calls + 1L; stop("Offline transport exception") }, budget = 0, allow_external = TRUE)
  expect_identical(uncertain$delivery, "unknown")
  blocked <- .sc_run_call(f$root, request("public aggregate 4"), provider,
    function(...) { calls <<- calls + 1L; '{"valid":true}' }, budget = 0, allow_external = TRUE)
  expect_identical(blocked$status, "delivery_uncertain")
  expect_identical(calls, 3L)
})

test_that("default startup records auto and diagnostic options and reopens without replacing them", {
  skip_if(Sys.which("python3") == "")
  data("pbmc_small", package = "SeuratObject")
  folder <- tempfile("start-defaults-"); dir.create(folder)
  on.exit(unlink(folder, recursive = TRUE))
  path <- file.path(folder, "input.rds"); saveRDS(pbmc_small, path)
  root <- file.path(folder, "project")
  launch <- suppressMessages(suppressWarnings(sc_start(path, root,
    context = list(species = "human", tissue = "blood", research_goal = "Public software default test"),
    provider = "manual", browse = FALSE, doublet = "off")))
  on.exit(if (is.numeric(launch$pid)) tools::pskill(launch$pid), add = TRUE)
  state <- .sc_run_load(root)
  expect_identical(state$config$react$mode, "auto")
  expect_identical(state$config$cost_mode, "posthoc")
  expect_true(state$config$biological_diagnostics$cluster_qc)
  expect_true(state$config$biological_diagnostics$batch_assessment)
  before <- .sc_project_sha_file(file.path(root, "state.rds"))
  reopened <- suppressMessages(sc_start(path, root, browse = FALSE))
  expect_identical(.sc_project_sha_file(file.path(root, "state.rds")), before)
  expect_error(sc_start(path, root, react = "off", browse = FALSE), "saved ReAct")
  expect_error(sc_start(path, root, biological_diagnostics = FALSE, browse = FALSE), "saved biological")
})
