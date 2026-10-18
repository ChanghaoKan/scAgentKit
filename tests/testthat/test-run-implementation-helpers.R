implementation_mutation <- function(name, verify) {
  ns <- asNamespace("scAgentKit")
  original <- get(name, envir = ns, inherits = FALSE)
  locked <- bindingIsLocked(name, ns)
  if (locked) unlockBinding(name, ns)
  on.exit({
    assign(name, original, envir = ns)
    if (locked) lockBinding(name, ns)
  }, add = TRUE)
  changed <- original
  body(changed) <- substitute({
    stop("MUTATED helper must never execute")
    ORIGINAL
  }, list(ORIGINAL = body(original)))
  assign(name, changed, envir = ns)
  verify()
}

test_that("analysis checkpoint refuses changed reachable helpers before writing", {
  set.seed(81)
  counts <- matrix(rpois(80 * 100, 2), 80,
    dimnames = list(paste0("GENE", seq_len(80)), paste0("cell", seq_len(100))))
  counts[2:12, 1:50] <- counts[2:12, 1:50] + 15L
  counts[13:25, 51:100] <- counts[13:25, 51:100] + 15L
  input <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  root <- tempfile("helper-mutation-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  qc <- list(schema = "scagentkit.qc.v1", rationale = "Synthetic software control only.",
    risks = list("No biological threshold claim."),
    filters = list(list(op = "range", metric = "nCount", min = 1)))
  initial <- sc_run(input, root, context = list(species = "human", tissue = "synthetic"),
    qc_proposal = qc, analysis = list(nfeatures = 60, npcs = 5, run_umap = FALSE))
  pending_state <- .sc_run_load(root)
  expect_true(.sc_run_check_binding(pending_state, pending_state$pending))
  changed_artifact <- pending_state
  changed_artifact$files$input$sha256 <- strrep("0", 64)
  expect_false(.sc_run_check_binding(changed_artifact, pending_state$pending))
  sc_run_approve(root, initial$pending$hash, "test", "Approve synthetic control.")
  old_option <- getOption("scAgentKit.run_crash")
  on.exit(options(scAgentKit.run_crash = old_option), add = TRUE)
  options(scAgentKit.run_crash = "analysis:checkpoint")
  # The coordinator catches the injected stop after the durable checkpoint.
  suppressWarnings(sc_run_resume(root))
  options(scAgentKit.run_crash = old_option)
  saved <- .sc_run_load(root)
  expect_true("analysis" %in% saved$completed)
  expect_identical(saved$stage, "markers")
  expect_null(saved$files$markers)
  expect_identical(saved$approvals[[initial$pending$hash]]$input_hash, saved$input_hash)
  snapshot <- function() {
    paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE))
    paths <- paths[!dir.exists(paths)]
    stats::setNames(vapply(paths, .sc_project_sha_file, character(1)), paths)
  }
  before <- snapshot()
  for (name in c("sc_find_markers", "sc_markers_summary", "annot_match_reference", "AgentSeurat",
                 ".validate_marker_reference")) {
    implementation_mutation(name, function() {
      expect_false(identical(saved$implementation_hash, .sc_run_implementation()), info = name)
      expect_error(sc_run_resume(root, retry = TRUE), "[Ii]mplementation changed")
      expect_identical(snapshot(), before)
    })
  }
  expect_identical(.sc_run_implementation(), saved$implementation_hash)
  # An existing approval is still bound to its immutable input/artifacts.
  # This regression concerns future execution, not removal of approval checks.
  expect_identical(.sc_run_load(root), saved)
})

test_that("unreachable legacy workflow changes do not invalidate the coordinator", {
  before <- .sc_run_implementation()
  implementation_mutation("annot_subcluster", function() {
    expect_identical(.sc_run_implementation(), before)
  })
})

test_that("mocked coordinator environments cannot redirect helper discovery", {
  before <- .sc_run_implementation()
  testthat::local_mocked_bindings(.sc_run_drive = function(...) NULL,
    .package = "scAgentKit")
  mocked <- .sc_run_implementation()
  expect_match(mocked, "^[[:xdigit:]]{64}$")
  expect_false(identical(mocked, before))
  implementation_mutation("sc_find_markers", function() {
    expect_false(identical(.sc_run_implementation(), mocked))
  })
})

test_that("implementation fingerprint is independent of collation locale", {
  original <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", original), add = TRUE)
  Sys.setlocale("LC_COLLATE", "C")
  baseline <- .sc_run_implementation()
  available <- suppressWarnings(Sys.setlocale("LC_COLLATE", "C.UTF-8"))
  if (!nzchar(available)) skip("C.UTF-8 collation is unavailable on this platform")
  expect_identical(.sc_run_implementation(), baseline)
  implementation_mutation("sc_find_markers", function() {
    expect_false(identical(.sc_run_implementation(), baseline))
  })
})

test_that("default-only helper bodies are covered without evaluating missing arguments", {
  ns <- asNamespace("scAgentKit")
  marker <- get("sc_find_markers", envir = ns, inherits = FALSE)
  changed <- marker
  # obj remains a required/missing argument; inspecting defaults must not
  # evaluate it, or execute this deliberately unusable default expression.
  formals(changed)$rationale <- quote(annot_subcluster())
  testthat::local_mocked_bindings(sc_find_markers = changed, .package = "scAgentKit")
  baseline <- .sc_run_implementation()
  implementation_mutation("annot_subcluster", function() {
    expect_false(identical(.sc_run_implementation(), baseline))
  })
  expect_identical(.sc_run_implementation(), baseline)
})
