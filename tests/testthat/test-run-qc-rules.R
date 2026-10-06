# Publicly reproducible synthetic mechanism controls; no biological threshold
# or cell identity is established by these fixtures.
qc_rules_proposal <- function(rules, remove_if = "any") list(
  schema = "scagentkit.qc.rules.v1", rationale = "Explicit synthetic failure-rule control.",
  risks = list("Software mechanism only; threshold appropriateness is unvalidated."),
  remove_if = remove_if, rules = rules)

qc_rules_small <- function() {
  counts <- Matrix::Matrix(matrix(c(0,1,2,0, 1,4,0,0, 3,6,4,0,
    0,1,1,2, 1,0,1,0, 0,0,0,0), nrow = 4L,
    dimnames = list(c("MT-CO1", "GeneA", "GeneB", "GeneC"), c("001", "1", "NA", "cell space", "Ca", "zero"))), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  seu$sample <- c("sample a", "sample a", "sample a", "sample b", "sample b", "sample b")
  seu$capture <- c("cap1", "cap1", "cap2", "cap2", "cap2", "cap2")
  seu$old_annotation <- factor(c("old", "old", NA, "other", "other", "old"))
  context <- list(species = "human", columns = list(sample = "sample", capture = "capture"))
  list(seu = seu, context = context, qc = scAgentKit:::.sc_run_qc_evidence(seu, context))
}

qc_rules_mad <- function(unavailable_mt = FALSE) {
  cells <- sprintf("RULE-LOCAL-%03d", 1:120)
  values <- outer(1:100, 1:120, function(g, cell)
    as.numeric(((g + 3 * cell) %% 80) < (35 + cell %% 24)) * (1 + (g * cell + cell^2) %% 13))
  values[, 61:120] <- values[, 61:120] * 4
  values[1, ] <- 1 + (1:120) %% 3
  values[, c(1, 61)] <- 0; values[1:3, c(1, 61)] <- c(10, 1, 1)
  values[, c(2, 62)] <- 0
  if (unavailable_mt) values[1, ] <- 0
  counts <- Matrix::Matrix(values, sparse = TRUE)
  dimnames(counts) <- list(c("MT-CO1", "RPL3", "HBB", paste0("RuleGene", 4:100)), cells)
  seu <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  seu$sample <- rep(c("sample-A", "sample-B"), each = 60)
  seu$quality <- factor(rep(c("quality-A", "quality-B"), each = 60))
  seu$capture <- rep(c("capture-1", "capture-2"), length.out = 120)
  seu$old_annotation <- factor(rep(c("old A", NA), each = 60), levels = c("old A", "unused"))
  context <- scAgentKit:::.sc_run_context(list(species = "human", tissue = "synthetic",
    columns = list(sample = "sample", capture = "capture", qc_group = "quality")), seu)
  mad_options <- list(grouping = list(method = "column", column = "quality", declared_role = "qc_group",
    source = "Explicit quality units; no inferred capture or donor"),
    prefilter = list(method = "min_counts", min_counts = 1L, preapproved = TRUE,
      source = "Preapproved planted zero-count exclusions for a software control"))
  config <- list(context = context, assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    cluster_column = "sc_strategy_clusters", start_stage = "qc",
    prefilter = scAgentKit:::.sc_run_prefilter_options(mad_options$prefilter),
    qc_mad = scAgentKit:::.sc_run_mad_options(context, mad_options["grouping"]))
  baseline <- scAgentKit:::.sc_run_qc_evidence(seu, context)
  prefilter <- scAgentKit:::.sc_run_prefilter_evidence(seu, config)
  mad <- scAgentKit:::.sc_run_mad_evidence(seu, config, baseline, prefilter)
  qc <- baseline; qc$mad_record <- mad; qc$summary$mad <- mad$summary
  qc$evidence_hash <- scAgentKit:::.sc_run_qc_hash(qc)
  evidence <- scAgentKit:::.sc_run_strategy_evidence(seu, config, qc, mad_record = mad, prefilter_record = prefilter)
  list(seu = seu, context = context, config = config, qc = qc, baseline = baseline,
    mad = mad, prefilter = prefilter, evidence = evidence, mad_options = mad_options)
}

qc_rules_plan <- function(qc) list(schema = "scagentkit.strategy.v1",
  rationale = "Review the complete synthetic software control.", risks = character(), inferences = character(), qc = qc,
  analysis = list(normalization_method = "LogNormalize", scale_factor = 10000, nfeatures = 32L, npcs = 8L, seed = 11L),
  pcs = list(method = "computed_variance", threshold = .8),
  batch = list(method = "none", reason = "No integration in this mechanism test"),
  clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .6)), umap = list(run = FALSE, n_neighbors = 10L))

test_that("fixed failure OR and AND preserve inclusive bounds and exact literal cell order", {
  f <- qc_rules_small(); before <- f$seu
  rules <- list(list(op = "range", metric = "nCount", min = 3L), list(op = "range", metric = "nFeature", min = 3L))
  any <- scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(rules), f$qc)
  all <- scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(rules, "all"), f$qc)
  expect_identical(any$keep_cells, c("NA", "cell space"))
  expect_identical(all$keep_cells, c("001", "1", "NA", "cell space"))
  expect_equal(any$retention$removed, 4L); expect_equal(all$retention$removed, 2L)
  output <- scAgentKit:::.sc_run_qc_apply(f$seu, all, f$qc)
  expect_identical(f$seu, before); expect_identical(colnames(output), all$keep_cells)
  expect_identical(output[[]][, names(before[[]]), drop = FALSE], before[[]][all$keep_cells, , drop = FALSE])
  expect_s4_class(SeuratObject::LayerData(output, layer = "counts"), "sparseMatrix")
  numeric_rules <- rules; numeric_rules[[1]]$min <- 3
  expect_identical(any, scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(numeric_rules), f$qc))
})

test_that("component empty sets can participate in AND while final empty sets are rejected", {
  f <- qc_rules_small()
  empty <- list(op = "range", metric = "nCount", min = 100L)
  other <- list(op = "range", metric = "nCount", min = 3L)
  expect_identical(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(empty, other), "all"), f$qc)$keep_cells,
    c("001", "1", "NA", "cell space"))
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(empty, other), "any"), f$qc), "every cell")
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(empty), "all"), f$qc), "every cell")
})

test_that("groups are literal sample/capture intersections and unavailable measurements fail closed", {
  f <- qc_rules_small()
  scoped <- list(op = "range", metric = "nCount", max = 10L, group = list(capture = "cap2", sample = "sample a"))
  result <- scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(scoped)), f$qc)
  expect_identical(result$keep_cells, c("001", "1", "cell space", "Ca", "zero"))
  expect_identical(result$proposal$rules[[1]]$group, list(sample = "sample a", capture = "cap2"))
  bad <- scoped; bad$group$sample <- "invented"
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(bad)), f$qc), "does not match")
  bad$group <- list(condition = "Ca")
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(bad)), f$qc), "sample/capture")
  mt <- list(op = "range", metric = "percent_mt", max = 30)
  count <- list(op = "range", metric = "nCount", min = 1)
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(mt)), f$qc), "unavailable")
  expect_identical(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(mt, count)), f$qc)$keep_cells,
    c("001", "1", "NA", "cell space"))
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(mt, count), "all"), f$qc), "unavailable")
})

test_that("new typed rules reject unsupported fields operations and parameters", {
  f <- qc_rules_small(); good <- qc_rules_proposal(list(list(op = "range", metric = "nCount", min = 1)))
  for (change in c("code", "filters", "prefilter")) {
    p <- good; p[[change]] <- "unsupported"
    expect_error(scAgentKit:::.sc_run_qc_validate(p, f$qc), "supported named fields")
  }
  for (value in list("and", TRUE, NA_character_, c("any", "all"))) {
    p <- good; p$remove_if <- value
    expect_error(scAgentKit:::.sc_run_qc_validate(p, f$qc), "remove_if")
  }
  for (rules in list(list(), rep(good$rules, 33), list(rule1 = good$rules[[1]]),
      list(list(op = "code", metric = "nCount", min = 1)), list(list(op = "range", metric = "nCount", min = .5)),
      list(list(op = "range", metric = "percent_mt", max = 101)), list(list(op = "range", metric = "nCount", min = Inf))))
    expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(rules), f$qc))
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(list(op = "mad_preset", preset_id = "keep_all", panel_hash = strrep("0", 64)))), f$qc), "explicitly enabled")
})

test_that("saved MAD predicates combine with ranges without restoring prefilter exclusions", {
  f <- qc_rules_mad(); cells <- colnames(f$seu)
  mad_rule <- list(op = "mad_preset", preset_id = "conservative_and3", panel_hash = f$mad$panel_hash)
  range <- list(op = "range", metric = "nCount", min = 0)
  one <- scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(mad_rule)), f$qc)
  expect_identical(one$keep_cells, f$mad$selections$conservative_and3)
  all <- scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(mad_rule, range), "all"), f$qc)
  expect_identical(all$keep_cells, f$prefilter$keep_cells)
  expect_false(any(f$prefilter$excluded_cells %in% all$keep_cells))
  range_only <- scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(range)), f$qc)
  expect_identical(range_only$keep_cells, f$prefilter$keep_cells)
  expect_equal(all$summary$prefilter_removed, 2L)
  expect_null(range_only$summary$preset_id)
  p <- qc_rules_plan(qc_rules_proposal(list(mad_rule, range), "all"))
  valid <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_identical(valid$applicability$qc_mad$preset_id, "conservative_and3")
  expect_equal(valid$applicability$qc_mad$stage_counts$post_qc_cells, 118L)
  p$qc <- qc_rules_proposal(list(range))
  expect_null(scAgentKit:::.sc_run_strategy_validate(p, f$evidence)$applicability$qc_mad$preset_id)
  stale <- mad_rule; stale$panel_hash <- strrep("0", 64)
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(stale)), f$qc), "panel hash.*stale")
  hallucinated <- mad_rule; hallucinated$preset_id <- "automatic_optimum"
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(hallucinated)), f$qc), "Unsupported MAD")
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(mad_rule, mad_rule)), f$qc), "at most one")
  unavailable <- qc_rules_mad(unavailable_mt = TRUE)
  bad <- mad_rule; bad$panel_hash <- unavailable$mad$panel_hash
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(bad)), unavailable$qc), "unavailable")
  changed <- f$qc; changed$mad_record$flags$low_count[3] <- !changed$mad_record$flags$low_count[3]
  expect_error(scAgentKit:::.sc_run_qc_validate(qc_rules_proposal(list(mad_rule)), changed), "changed")
  changed <- all; changed$proposal$remove_if <- "any"
  expect_error(scAgentKit:::.sc_run_qc_apply(f$seu, changed, f$qc), "result was changed")
  changed <- f$seu; changed$quality <- unname(rev(as.character(changed$quality)))
  expect_error(scAgentKit:::.sc_run_qc_apply(changed, all, f$qc), "grouping metadata changed")
  applied <- scAgentKit:::.sc_run_qc_apply(f$seu, all, f$qc)
  expect_identical(applied[[]][, names(f$seu[[]]), drop = FALSE], f$seu[[]][all$keep_cells, , drop = FALSE])
})

test_that("preview reports independent failures intersections and final deduplicated OR/AND sets", {
  f <- qc_rules_small()
  rules <- list(list(op = "range", metric = "nCount", min = 3), list(op = "range", metric = "nFeature", min = 3))
  p <- qc_rules_proposal(rules)
  any <- scAgentKit:::.sc_run_qc_preview_build(p, f$qc,
    sensitivity = list(list(id = "AND", proposal = qc_rules_proposal(rules, "all"))))
  all <- scAgentKit:::.sc_run_qc_preview_build(qc_rules_proposal(rules, "all"), f$qc)
  expect_identical(any$overlap$filter_ids, c("rule1", "rule2"))
  expect_equal(vapply(any$filter_impacts, `[[`, numeric(1), "independently_removed"), c(2, 4))
  expect_equal(vapply(any$filter_impacts, `[[`, numeric(1), "exclusively_removed"), c(0, 2))
  expect_equal(vapply(all$filter_impacts, `[[`, numeric(1), "exclusively_removed"), c(0, 0))
  expect_equal(unlist(any$overlap$counts[[1]]), c(2, 2))
  expect_equal(unlist(any$overlap$counts[[2]]), c(2, 4))
  expect_equal(sum(vapply(any$patterns, `[[`, integer(1), "count")), 6L)
  expect_equal(sum(vapply(any$patterns, `[[`, numeric(1), "removed")), any$retention$removed)
  expect_identical(any$rule_logic$remove_if, "any")
  expect_identical(any$sensitivity[[1]]$added_cells, c("001", "1"))
  f <- qc_rules_mad()
  mixed <- qc_rules_proposal(list(list(op = "range", metric = "nCount", min = 20),
    list(op = "mad_preset", preset_id = "conservative_and3", panel_hash = f$mad$panel_hash)))
  preview <- scAgentKit:::.sc_run_qc_preview_build(mixed, f$qc)
  expect_identical(preview$rule_logic$prefilter_excluded_cells, f$prefilter$excluded_cells)
  expect_equal(preview$rule_logic$prefilter_removed, 2L)
  expect_equal(preview$rule_logic$quality_removed, 2L)
  expect_equal(preview$retention$removed, 4L)
  expect_equal(unlist(preview$overlap$counts[[1]]), c(2L, 2L))
  expect_equal(sum(vapply(preview$patterns, `[[`, numeric(1), "removed")), 4L)
  expect_identical(preview$mad_panel, f$mad$summary)
})

test_that("exact rule parameters and failure logic bind dependencies even when retained cells coincide", {
  f <- qc_rules_mad()
  p <- qc_rules_plan(qc_rules_proposal(list(list(op = "range", metric = "nCount", min = 0))))
  before <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  p$qc$rules[[1]]$min <- 1
  changed <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_identical(before$qc_validated$keep_cells, changed$qc_validated$keep_cells)
  expect_false(identical(before$dependency_hashes$qc, changed$dependency_hashes$qc))
  p$qc$remove_if <- "all"
  logic <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_identical(changed$qc_validated$keep_cells, logic$qc_validated$keep_cells)
  expect_false(identical(changed$dependency_hashes$qc, logic$dependency_hashes$qc))
  p$qc$rationale <- "Change the explanatory text, not the executable rules"
  p$qc$risks <- "New uncertainty wording"
  expect_identical(logic$dependency_hashes, scAgentKit:::.sc_run_strategy_validate(p, f$evidence)$dependency_hashes)
})

qc_rules_continue_process <- function(root, retry = FALSE) {
  work <- tempfile("qc-rules-process-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  script <- file.path(work, "resume.R"); args_file <- file.path(work, "args.rds")
  result <- file.path(work, "result.rds"); log <- file.path(work, "stdout.log")
  snapshot <- sc_run_inspect(root)
  saveRDS(list(root = root, project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    revision = snapshot$revision, retry = retry, libraries = .libPaths(), result = result,
    source = getNamespaceInfo(asNamespace("scAgentKit"), "path"),
    implementation = scAgentKit:::.sc_run_implementation()), args_file)
  writeLines(c("local({", "args <- readRDS(commandArgs(TRUE)[1])", ".libPaths(args$libraries)",
    "Sys.unsetenv(c('DEEPSEEK_API_KEY','XAI_API_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY','GROK_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','AZURE_OPENAI_API_KEY','COHERE_API_KEY','MISTRAL_API_KEY','OPENROUTER_API_KEY','HF_TOKEN','HUGGINGFACEHUB_API_TOKEN'))",
    "if (file.exists(file.path(args$source,'R','run.R'))) pkgload::load_all(args$source,quiet=TRUE,helpers=FALSE,export_all=FALSE) else suppressPackageStartupMessages(library(scAgentKit,lib.loc=dirname(args$source)))",
    "stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('scAgentKit'),'path')),normalizePath(args$source)),identical(scAgentKit:::.sc_run_implementation(),args$implementation))",
    "calls <- new.env(); calls$factory <- 0L; calls$http <- 0L",
    "factory <- function(...) {calls$factory <- calls$factory+1L; stop('No remote provider in QC rule mechanism tests')}",
    "testthat::local_mocked_bindings(chat_deepseek=factory,chat_grok=factory,.package='agentomicsCore',.env=environment())",
    "testthat::local_mocked_bindings(req_perform=function(...) {calls$http <- calls$http+1L; stop('No HTTP in QC rule mechanism tests')},.package='httr2',.env=environment())",
    "out <- suppressWarnings(sc_run_continue(args$root,args$project_id,args$input_hash,args$revision,retry=args$retry))",
    "stopifnot(calls$factory==0L,calls$http==0L)", "saveRDS(out,args$result)", "})"), script)
  code <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(script), shQuote(args_file)), stdout = log, stderr = log)
  if (code != 0L || !file.exists(result)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  readRDS(result)
}

test_that("headless rule review rejects stale decisions and restarts without repeating QC or PCA", {
  root <- tempfile("qc-rules-run-"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- qc_rules_mad(); source <- serialize(f$seu, NULL, version = 2)
  rules <- list(list(op = "range", metric = "nCount", min = 20),
    list(op = "mad_preset", preset_id = "keep_all", panel_hash = f$mad$panel_hash))
  plan <- qc_rules_plan(qc_rules_proposal(rules, "all"))
  # Fix dimensions for this restart mechanism test; arbitrary fraction support
  # is separately verified against actually computed PC variances.
  plan$pcs <- list(method = "fixed", ndim = 5L)
  first <- suppressWarnings(sc_run(f$seu, root, context = f$context, strategy = TRUE,
    strategy_proposal = plan, qc_mad = f$mad_options, annotation_column = "rule_reviewed_type", budget = 0))
  expect_identical(first$status, "awaiting_review")
  old <- sc_run_inspect(root)
  expect_equal(old$strategy_review$details$qc_impact$retention$retained, 118L)
  expect_identical(old$strategy_review$details$capabilities$qc_rules$remove_if, c("any", "all"))
  plan$qc$remove_if <- "any"
  sc_run_strategy_revise(root, plan, old$project_id, old$input_hash, old$revision,
    "offline rules QA", "Explicitly change failure combination and rebuild review")
  decide <- function(snapshot, action = "approve") {
    node <- snapshot$review_node
    sc_run_review(root, action, node$kind, node$project_id, node$input_hash,
      node$proposal_hash, node$review_hash, node$expected_revision,
      reviewer = "offline rules QA", reason = "Approve exactly this saved synthetic scope")
  }
  expect_error(decide(old), "[Ss]tale|changed|revision")
  current <- sc_run_inspect(root)
  expect_equal(current$strategy_review$details$qc_impact$retention$retained, 116L)
  approve <- decide(current); expect_identical(approve$stage, "strategy_apply")
  before <- scAgentKit:::.sc_run_load(root)
  expect_identical(decide(current)$stage, "strategy_apply")
  expect_identical(scAgentKit:::.sc_run_load(root), before)
  withr::local_options(list(scAgentKit.continue_crash = "strategy_neighbors:before"))
  snap <- sc_run_inspect(root)
  failed <- suppressWarnings(sc_run_continue(root, snap$project_id, snap$input_hash, snap$revision))
  expect_identical(failed$status, "failed"); expect_identical(failed$stage, "strategy_neighbors")
  state <- scAgentKit:::.sc_run_load(root)
  caches <- state$files[c("qc_object", "strategy_basis")]
  expect_true(all(c("qc_apply", "strategy_basis") %in% state$completed))
  options(scAgentKit.continue_crash = NULL)
  resumed <- qc_rules_continue_process(root, retry = TRUE)
  expect_identical(resumed$status, "awaiting_configuration")
  expect_identical(resumed$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[c("qc_object", "strategy_basis")], caches)
  for (stage in c("qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster"))
    expect_length(Filter(function(event) identical(event$action, "executed") && identical(event$details$stage, stage), state$history), 1L)
  evidence <- sc_run_inspect(root)$evidence
  annotation <- list(schema = "scagentkit.annotation.v1", annotations = lapply(evidence$clusters, function(row)
    list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
      rationale = "Synthetic mechanism control; identity remains unresolved", markers = list())))
  sc_run_propose(root, annotation, "offline rules QA", "Review Unknown controls separately")
  decide(sc_run_inspect(root)); completed <- qc_rules_continue_process(root)
  expect_identical(completed$status, "complete")
  final <- readRDS(sc_run_inspect(root)$output$seurat)
  expect_identical(serialize(f$seu, NULL, version = 2), source)
  expect_identical(colnames(final), f$prefilter$keep_cells[!f$prefilter$keep_cells %in% colnames(f$seu)[c(1,61)]])
  expect_identical(final[[]][, names(f$seu[[]]), drop = FALSE], f$seu[[]][colnames(final), , drop = FALSE])
  expect_true(all(final$rule_reviewed_type == "Unknown"))
  expect_false(dir.exists(file.path(root, "provider")))
})

test_that("rule QC and independent saved doublet removal deduplicate overlapping cells without rescoring", {
  cells <- sprintf("RULE-DOUBLET-LOCAL-%03d", 1:202)
  genes <- paste0("RuleDoubletGene", 1:240)
  values <- outer(1:240, 1:202, function(g, cell) 1 + (g*g + 3*g*cell + cell*cell) %% 19)
  qc_outliers <- c(1:4, 102:105); predicted <- c(1:8, 102:109)
  values[240, qc_outliers] <- values[240, qc_outliers] + 5000
  counts <- Matrix::Matrix(values, sparse = TRUE); dimnames(counts) <- list(genes, cells)
  seu <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  seu$capture <- rep(c("literal capture-A", "literal capture-B"), each = 101)
  seu$old_annotation <- factor(rep(c("old", NA), each = 101), levels = c("old", "unused"))
  context <- scAgentKit:::.sc_run_context(list(species = "human", columns = list(capture = "capture")), seu)
  config <- list(context = context, assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    start_stage = "qc", cluster_column = "sc_strategy_clusters",
    doublet_diagnostics = scAgentKit:::.sc_run_doublet_options(context,
      list(data_type = "scrna_droplet", input_source = "Authored synthetic called-cell counts, not biological validation",
        empty_droplets_removed = TRUE, capture = list(method = "column", column = "capture", source = "Explicit physical loading units in the synthetic fixture"),
        rate = list(method = "manual", value = .1, source = "Authored software control rate"), nfeatures = 200L)))
  calls <- 0L
  testthat::local_mocked_bindings(.sc_run_doublet_dependencies = function() invisible(TRUE),
    .sc_run_doublet_versions = function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
      fixture_scope = "Authored accepted-version software record only; no classifier execution"),
    .sc_run_doublet_detect_one = function(counts, options, rate, seed) {
      calls <<- calls + 1L; ids <- colnames(counts); called <- ids %in% cells[predicted]
      list(scores = data.frame(cell_id = ids, score = ifelse(called, .8, .2), class = ifelse(called, "doublet", "singlet"),
        row.names = ids, stringsAsFactors = FALSE), threshold = .5, warnings = character(),
        messages = "Authored predictions for mechanism tests; no classifier executed",
        classifier_audit = list(train_attempts = 3L, train_successes = 3L, predict_attempts = 3L, predict_successes = 3L,
          training_errors = character(), prediction_errors = character(), test_only_mock = TRUE),
        adapter_source_hashes = scAgentKit:::.sc_run_doublet_classifier_source_hashes())
    }, .package = "scAgentKit", .env = environment())
  qc <- scAgentKit:::.sc_run_qc_evidence(seu, context)
  record <- scAgentKit:::.sc_run_doublet_evidence(seu, config)
  expect_equal(calls, 2L)
  saved <- record$evidence_hash
  evidence <- scAgentKit:::.sc_run_strategy_evidence(seu, config, qc, doublet_record = record)
  plan <- qc_rules_plan(qc_rules_proposal(list(list(op = "range", metric = "nCount", max = 5000),
    list(op = "range", metric = "nFeature", min = 1))))
  plan$doublet <- list(method = "remove_predicted", reason = "Explicit reviewed synthetic predicted-doublet deletion")
  validated <- scAgentKit:::.sc_run_strategy_validate(plan, evidence)
  expect_identical(validated$qc_validated$keep_cells, cells[-qc_outliers])
  expect_identical(validated$selected_cells, cells[-predicted])
  expect_equal(validated$doublet$impact$predicted_input, 16L)
  expect_equal(validated$doublet$impact$predicted_qc_excluded, 8L)
  expect_equal(validated$doublet$impact$removed_cells, 8L)
  expect_equal(validated$doublet$impact$retained_cells, 186L)
  expect_equal(length(cells) - length(validated$selected_cells), 16L)
  plan$doublet$method <- "keep"
  marked <- scAgentKit:::.sc_run_strategy_validate(plan, evidence)
  expect_identical(marked$selected_cells, marked$qc_validated$keep_cells)
  expect_equal(marked$doublet$impact$removed_cells, 0L)
  qc_object <- scAgentKit:::.sc_run_qc_apply(seu, validated$qc_validated, qc)
  marked_object <- scAgentKit:::.sc_run_doublet_attach(qc_object, record)
  expect_identical(marked_object[[]][, names(qc_object[[]]), drop = FALSE], qc_object[[]])
  selected_object <- scAgentKit:::.sc_run_strategy_selection(qc_object, config, validated, record)
  expect_identical(colnames(selected_object), validated$selected_cells)
  expect_identical(selected_object[[]][, names(seu[[]]), drop = FALSE], seu[[]][validated$selected_cells, , drop = FALSE])
  expect_identical(record$evidence_hash, saved); expect_equal(calls, 2L)
})
