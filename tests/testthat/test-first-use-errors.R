# First-use mistakes exercise the public coordinator transaction, rather than
# reimplementing its input validator. All payloads and metadata are synthetic.
first_use_counts <- function() {
  set.seed(9073)
  genes <- c("ALB", "TTR", "CD3D", "CD3E", "MT-CO1", paste0("Gene", 6:60))
  cells <- c("001", "1", "NA", "cell space", paste0("cell", 5:60))
  counts <- matrix(stats::rpois(60 * 60, 1), nrow = 60,
                   dimnames = list(genes, cells))
  counts[1:2, 1:30] <- counts[1:2, 1:30] + 12L
  counts[3:4, 31:60] <- counts[3:4, 31:60] + 12L
  Matrix::Matrix(counts, sparse = TRUE)
}
first_use_seurat <- function(processed = FALSE) {
  counts <- first_use_counts()
  object <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  object$old_annotation <- factor(rep(c("earlier label", NA_character_), length.out = ncol(object)))
  object$condition <- rep(c("Ca", "Ctrl"), length.out = ncol(object))
  object$sample_id <- rep(c("sample A", "sample B"), each = 30)
  if (processed) {
    SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- log1p(counts)
    object$seurat_clusters <- rep(c("01", "NA"), each = 30)
  }
  object
}
first_use_unknown_annotation <- function() list(schema = "scagentkit.annotation.v1",
  annotations = lapply(c("01", "NA"), function(id) list(clusterId = id, label = "Unknown",
    confidence = "low", rationale = "Synthetic input: no biological conclusion is claimed.", markers = list())))
first_use_context <- function() list(species = "human", tissue = "synthetic liver/lymphoid test",
  columns = list(condition = "condition"), notes = "Synthetic mechanism input, not a biological benchmark.")

first_use_failed_start <- function(input, root, pattern, extra = list(), corrected = first_use_counts()) {
  before <- digest::digest(input, algo = "sha256")
  error <- tryCatch(do.call(sc_run, c(list(input = input, project_dir = root,
    provider = NULL, budget = 0, review = list(allow_external = FALSE)), extra)), error = function(error) error)
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), pattern)
  expect_identical(digest::digest(input, algo = "sha256"), before)
  expect_false(file.exists(file.path(root, "state.rds")))
  expect_false(file.exists(file.path(root, "decision_history.json")))
  expect_false(dir.exists(file.path(root, ".run-lock")))
  # A validation error must not strand an unusable project directory.
  result <- sc_run(corrected, project_dir = root, context = list(species = "human"),
    provider = NULL, budget = 0, review = list(allow_external = FALSE))
  expect_identical(result$status, "awaiting_configuration")
  expect_identical(result$stage, "qc_propose")
  expect_false(dir.exists(file.path(root, ".run-lock")))
  invisible(conditionMessage(error))
}

test_that("wrong paths types and unreadable RDS leave source untouched and allow corrected restart", {
  work <- tempfile("first-use-paths-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  first_use_failed_start(file.path(work, "missing.rds"), file.path(work, "missing-project"), "existing local file")
  corrupt <- file.path(work, "not-rds.rds")
  writeLines("Synthetic plain text, deliberately not RDS.", corrupt)
  before <- digest::digest(corrupt, file = TRUE, algo = "sha256")
  first_use_failed_start(corrupt, file.path(work, "corrupt-project"), "RDS")
  expect_identical(digest::digest(corrupt, file = TRUE, algo = "sha256"), before)
  wrong <- file.path(work, "wrong-object.rds")
  saveRDS(list(synthetic = "not a Seurat or counts matrix"), wrong)
  before <- digest::digest(wrong, file = TRUE, algo = "sha256")
  first_use_failed_start(wrong, file.path(work, "wrong-object-project"), "Seurat")
  expect_identical(digest::digest(wrong, file = TRUE, algo = "sha256"), before)
  first_use_failed_start(data.frame(gene = "ALB", count = 3),
    file.path(work, "data-frame-project"), "Seurat")
})

test_that("duplicate literal IDs and normalized values are rejected before any saved run", {
  work <- tempfile("first-use-counts-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  counts <- first_use_counts()
  duplicate_cells <- counts; colnames(duplicate_cells)[2] <- "001"
  first_use_failed_start(duplicate_cells, file.path(work, "duplicate-cells"), "cell IDs.*unique")
  duplicate_genes <- counts; rownames(duplicate_genes)[2] <- "ALB"
  first_use_failed_start(duplicate_genes, file.path(work, "duplicate-genes"), "feature IDs.*unique")
  first_use_failed_start(log1p(counts), file.path(work, "normalized-matrix"), "integer counts")
})

test_that("missing split normalized and incomplete processed layers fail without repair or mutation", {
  work <- tempfile("first-use-layers-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  object <- first_use_seurat()
  counts <- SeuratObject::LayerData(object, assay = "RNA", layer = "counts")
  data_only <- object
  expect_warning(data_only[["RNA"]] <- SeuratObject::CreateAssay5Object(data = log1p(counts)),
    "No layers found matching search pattern provided")
  first_use_failed_start(data_only, file.path(work, "missing-counts"), "Exact layer.*counts.*Available layers.*data")
  ambiguous <- object
  SeuratObject::LayerData(ambiguous, assay = "RNA", layer = "counts.extra") <- counts
  first_use_failed_start(ambiguous, file.path(work, "ambiguous-counts"), "Split.*counts.*JoinLayers")
  normalized <- object
  SeuratObject::LayerData(normalized, assay = "RNA", layer = "data") <- log1p(counts)
  first_use_failed_start(normalized, file.path(work, "data-as-counts"), "normalized.*cannot.*counts",
    extra = list(counts_layer = "data"))
  object$seurat_clusters <- rep(c("01", "NA"), each = 30)
  first_use_failed_start(object, file.path(work, "processed-no-data"), "Exact layer.*data.*unavailable",
    extra = list(start_stage = "processed", processed_reason = "Synthetic processed-start mistake."))
})

test_that("no provider remains a diagnosable local plan and preserves factor NA metadata", {
  root <- tempfile("first-use-local-plan-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- first_use_seurat()
  before <- digest::digest(object, algo = "sha256")
  result <- sc_run(object, root, context = first_use_context(), provider = NULL,
                   budget = 0, review = list(allow_external = FALSE))
  expect_identical(result$status, "awaiting_configuration")
  expect_identical(result$stage, "qc_propose")
  expect_identical(digest::digest(object, algo = "sha256"), before)
  expect_match(paste(result$diagnostics$warnings, collapse = " "), "No sample.*No capture")
  expect_identical(result$batch_integration, "skipped; choose and validate integration separately")
  saved <- readRDS(file.path(root, "state.rds"))$state
  input <- readRDS(file.path(root, saved$files$input$path))
  expect_identical(input$old_annotation, object$old_annotation)
  expect_true(is.factor(input$old_annotation))
  expect_true(anyNA(input$old_annotation))
  expect_identical(colnames(input), colnames(object))
  expect_identical(result$context$columns, list(condition = "condition"))
  expect_false(file.exists(file.path(root, "provider", "ledger.json")))
  expect_false(dir.exists(file.path(root, ".run-lock")))
})

test_that("missing built-in keys pause after approved payload without HTTP charge or hold and resume explicitly", {
  expect_identical(unname(Sys.getenv(c("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY"))), rep("", 3L))
  http_calls <- 0L
  testthat::local_mocked_bindings(req_perform = function(...) {
    http_calls <<- http_calls + 1L
    stop("Synthetic HTTP sentinel: real networking is forbidden in this test.")
  }, .package = "httr2")
  root <- tempfile("first-use-missing-key-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  counts <- first_use_counts()
  before <- digest::digest(counts, algo = "sha256")
  started <- sc_run(counts, root, context = list(species = "human"), provider = "deepseek",
                    budget = .05, review = list(allow_external = TRUE))
  expect_identical(started$status, "awaiting_review")
  expect_identical(started$pending$kind, "external_transfer")
  expect_identical(http_calls, 0L)
  sc_run_approve(root, started$pending$hash, reviewer = "synthetic first-use analyst",
    reason = "Approve synthetic aggregate scope; HTTP sentinel still forbids transmission.")
  state <- readRDS(file.path(root, "state.rds"))$state
  input_hash <- state$files$input$sha256
  resumed <- sc_run_resume(root)
  expect_identical(resumed$status, "awaiting_configuration")
  expect_identical(resumed$stage, "qc_propose")
  expect_null(resumed$failure)
  expect_identical(http_calls, 0L)
  expect_identical(digest::digest(counts, algo = "sha256"), before)
  state <- readRDS(file.path(root, "state.rds"))$state
  expect_identical(state$files$input$sha256, input_hash)
  ledger <- scAgentKit:::.sc_run_provider_read(file.path(root, "provider", "ledger.json"))
  expect_length(ledger$entries, 0L)
  expect_true(any(vapply(state$history, function(event)
    grepl("provider|configuration", event$action) &&
      grepl("key|provider", paste(unlist(event$details), collapse = " "), ignore.case = TRUE), logical(1))))
  # An explicit offline callback demonstrates recovery without retry=TRUE or
  # a real endpoint. It is a mock transport, not a DeepSeek API validation.
  mock_calls <- 0L
  mock <- function(system_prompt, user_prompt) {
    mock_calls <<- mock_calls + 1L
    proposal <- list(schema = "scagentkit.qc.v1", rationale = "Explicit offline recovery test.",
      risks = list("Synthetic typed rule, not biological validation."),
      filters = list(list(op = "range", metric = "nCount", min = 1L)))
    list(content = as.character(jsonlite::toJSON(proposal, auto_unbox = TRUE)),
         usage = list(input_tokens = 0, output_tokens = 0, cached_tokens = 0), cost_usd = 0,
         model = "offline-recovery-test")
  }
  recovered <- sc_run_resume(root, chat_fn = mock)
  expect_identical(recovered$status, "awaiting_review")
  expect_identical(recovered$pending$kind, "qc")
  expect_identical(mock_calls, 1L)
  expect_identical(http_calls, 0L)
  expect_identical(digest::digest(counts, algo = "sha256"), before)
  ledger <- scAgentKit:::.sc_run_provider_read(file.path(root, "provider", "ledger.json"))
  expect_length(ledger$entries, 1L)
  expect_equal(ledger$entries[[1]]$charged_or_held_usd, 0)
  # The saved aggregate response remains inspectable after credentials and the
  # runtime callback disappear; cache retrieval cannot create a new dispatch.
  state <- readRDS(file.path(root, "state.rds"))$state
  request <- scAgentKit:::.sc_run_get(root, state, "qc_request")
  evidence <- scAgentKit:::.sc_run_get(root, state, "qc_evidence")
  request$validator <- function(value) scAgentKit:::.sc_run_qc_validate(value, evidence)$proposal
  cached <- scAgentKit:::.sc_run_call(root, request, provider = "deepseek", budget = 0)
  expect_identical(cached$status, "ok")
  expect_true(cached$cached)
  expect_identical(http_calls, 0L)
  expect_identical(mock_calls, 1L)
  expect_length(scAgentKit:::.sc_run_provider_read(file.path(root, "provider", "ledger.json"))$entries, 1L)
  expect_false(dir.exists(file.path(root, "provider", ".dispatch-lock")))

  # Exercise the other built-in environment configuration without constructing
  # a factory or a paid request. Approval and budget still precede credential
  # preflight; all three pauses release the dispatch lock and preserve no charge.
  grok_root <- tempfile("first-use-missing-grok-key-"); dir.create(grok_root)
  on.exit(unlink(grok_root, recursive = TRUE), add = TRUE)
  grok_request <- list(system_prompt = "Synthetic no-network credential preflight.",
    user_prompt = "Aggregate fixture only.", purpose = "qc")
  unapproved <- scAgentKit:::.sc_run_call(grok_root, grok_request, provider = "grok", budget = .05)
  expect_identical(unapproved$status, "awaiting_external_approval")
  grok_request$approved_payload_hash <- scAgentKit:::.sc_run_request_hash(grok_request, "grok")
  stopped <- scAgentKit:::.sc_run_call(grok_root, grok_request, provider = "grok", budget = 0, allow_external = TRUE)
  expect_identical(stopped$status, "budget_stop")
  absent <- scAgentKit:::.sc_run_call(grok_root, grok_request, provider = "grok", budget = .05, allow_external = TRUE)
  expect_identical(absent$status, "needs_provider")
  expect_match(absent$error, "XAI_API_KEY")
  expect_identical(http_calls, 0L)
  expect_length(scAgentKit:::.sc_run_provider_read(file.path(grok_root, "provider", "ledger.json"))$entries, 0L)
  expect_false(dir.exists(file.path(grok_root, "provider", ".dispatch-lock")))
})

test_that("all annotation writeback column collisions are caught before state and preserve old factors", {
  work <- tempfile("first-use-columns-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  for (column in c("new_annotation", "new_annotation_confidence", "new_annotation_rationale")) {
    object <- first_use_seurat(processed = TRUE)
    object[[column]] <- factor(rep(c("old value", NA_character_), length.out = ncol(object)))
    before <- digest::digest(object, algo = "sha256")
    root <- file.path(work, column)
    expect_error(sc_run(object, root, context = first_use_context(), start_stage = "processed",
      processed_reason = "Synthetic complete raw/data layers and exact clusters already exist.",
      annotation_column = "new_annotation", annotation_proposal = first_use_unknown_annotation()),
      "already exist|preserve|conflict")
    expect_false(file.exists(file.path(root, "state.rds")))
    expect_false(dir.exists(file.path(root, ".run-lock")))
    expect_identical(digest::digest(object, algo = "sha256"), before)
    expect_true(is.factor(object[[column]][, 1]))
    expect_true(anyNA(object[[column]][, 1]))
  }
  object <- first_use_seurat(processed = TRUE)
  root <- file.path(work, "safe-columns")
  before <- digest::digest(object, algo = "sha256")
  started <- sc_run(object, root, context = first_use_context(), start_stage = "processed",
    processed_reason = "Synthetic processed fixture: reuse exact raw/data layers and literal memberships.",
    annotation_column = "safe_annotation", annotation_proposal = first_use_unknown_annotation())
  expect_identical(started$status, "awaiting_review")
  expect_identical(started$pending$kind, "annotation")
  expect_true(all(c("qc_evidence", "qc_propose", "qc_apply", "analysis") %in% started$completed))
  sc_run_approve(root, started$pending$hash, reviewer = "synthetic first-use analyst",
    reason = "Review fresh output columns and exact synthetic Unknown annotation scope.")
  completed <- sc_run_resume(root)
  expect_identical(completed$status, "complete")
  final <- readRDS(completed$output$seurat)
  expect_identical(digest::digest(object, algo = "sha256"), before)
  expect_identical(final$old_annotation, object$old_annotation)
  expect_identical(final$condition, object$condition)
  expect_identical(final$seurat_clusters, object$seurat_clusters)
  expect_identical(colnames(final), colnames(object))
  expect_true(all(c("safe_annotation", "safe_annotation_confidence", "safe_annotation_rationale") %in% names(final[[]])))
  expect_identical(unname(final$safe_annotation), rep("Unknown", ncol(final)))
  expect_identical(SeuratObject::LayerData(final, layer = "counts"),
                   SeuratObject::LayerData(object, layer = "counts"))
})
