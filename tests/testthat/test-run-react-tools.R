test_that("the initial registry contains only four bounded read-only tools", {
  registry <- .sc_run_react_tools()
  expect_identical(names(registry), c("cluster_markers", "gene_expression", "act_lookup", "cluster_context"))
  for (tool in registry) {
    expect_false(tool$parameters$additionalProperties)
    expect_true(is.function(tool$execute))
    expect_lte(tool$timeout_seconds, 60)
    expect_lte(tool$max_result_bytes, 32768)
  }
})

test_that("arguments reject unknown fields, malformed scalars, duplicates and limits", {
  registry <- .sc_run_react_tools()
  marker_bad <- list(list(cluster_id = "0", n = 51), list(cluster_id = "0", n = 1.5),
    list(cluster_id = "0", n = "3"), list(cluster_id = "0", n = NA_real_),
    list(cluster_id = "0", n = Inf), list(cluster_id = "0", n = 0),
    list(cluster_id = "0", approve = TRUE), list(cluster_id = c("0", "1")),
    list(cluster_id = " "), list(cluster_id = NULL), list(cluster_id = "0", n = NULL),
    list(cluster_id = paste(rep("x", 129), collapse = "")), list(cluster_id = "bad\nvalue"),
    structure(list("0", "1"), names = c("cluster_id", "cluster_id")))
  for (args in marker_bad) expect_error(.sc_run_react_arguments(registry$cluster_markers, args), class = "sc_run_react_error")
  expression_bad <- list(list(cluster_id = "0", genes = as.list(rep("G01", 21))),
    list(cluster_id = "0", genes = c("G01", "G01")), list(cluster_id = "0", genes = character()),
    list(cluster_id = "0", genes = list("G01", 1)), list(cluster_id = "0", genes = c(a = "G01")),
    list(cluster_id = "0", genes = list(list("G01"))))
  for (args in expression_bad) expect_error(.sc_run_react_arguments(registry$gene_expression, args), class = "sc_run_react_error")
  expect_identical(.sc_run_react_arguments(registry$cluster_markers, list(cluster_id = "0")), list(cluster_id = "0", offset = 0L, n = 30L))
  expect_identical(.sc_run_react_arguments(registry$gene_expression, list(genes = c("G02", "G01"), cluster_id = "0")),
    list(cluster_id = "0", genes = list("G01", "G02")))
})

test_that("marker tools read the full table and preserve exclusions and statistical eligibility", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  out <- react_local(fixture, "cluster_markers", list(cluster_id = "0", n = 50))$result
  expect_length(out$markers, 50)
  rows <- stats::setNames(out$markers, vapply(out$markers, `[[`, character(1), "gene"))
  expect_true(rows$G31$support_eligible)
  expect_false(rows$G32$support_eligible)
  expect_false(rows$G33$support_eligible)
  expect_true(rows$G35$excluded)
  expect_true(rows$G36$excluded)
  expect_false(rows$G35$support_eligible)
  expect_identical(rows$G31$padj, .001)
  expect_true(out$truncated)
  expect_error(react_local(fixture, "cluster_markers", list(cluster_id = "foreign")), "absent")
  context <- fixture$context
  saved <- .sc_run_react_read(context, "markers")
  saved$markers <- saved$markers[saved$markers$gene %in% c("RPL3", "MT-CO1", "G34"), ]
  state <- .sc_run_put(fixture$root, fixture$state, "markers", saved); fixture$commit(state)
  fixture$context <- .sc_run_react_context(fixture$root)
  out <- react_local(fixture, "cluster_markers", list(cluster_id = "0"))$result
  expect_true(all(vapply(out$markers, function(x) !x$support_eligible, logical(1))))
  expect_equal(sum(vapply(out$markers, `[[`, logical(1), "excluded")), 2)
})

test_that("expression returns exact aggregate means and explicit missing untested evidence", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  before <- .sc_project_sha_file(file.path(fixture$root, "state.rds"))
  out <- react_local(fixture, "gene_expression", list(cluster_id = "0", genes = c("G01", "absent_gene")))$result
  expect_identical(out$test_status, "not_tested")
  expect_false(out$support_eligible)
  expect_identical(out$genes[[2]]$status, "missing")
  data <- SeuratObject::LayerData(fixture$seu, assay = "RNA", layer = "data")
  expected <- mean(data["G01", fixture$cells[1:6]])
  expect_equal(out$genes[[1]]$mean_inside, expected)
  expect_false(any(c("avg_log2FC", "padj", "cell_id") %in% names(out$genes[[1]])))
  expect_identical(.sc_project_sha_file(file.path(fixture$root, "state.rds")), before)
})

test_that("real annotation evidence binds independently of data-frame attribute order", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  markers <- .sc_run_react_read(fixture$context, "markers")
  reference <- .sc_run_react_read(fixture$context, "reference")
  evidence <- .sc_run_annotation_evidence(fixture$seu, markers,
    fixture$state$config$context, reference = reference, cluster_column = "seurat_clusters")
  state <- .sc_run_put(fixture$root, fixture$state, "annotation_evidence", evidence)
  fixture$commit(state); fixture$context <- .sc_run_react_context(fixture$root)
  expect_silent(.sc_run_react_verify_context(fixture$context))
  expect_identical(react_local(fixture, "cluster_context", list(cluster_id = "0"))$result$cells, 6L)
  evidence$private$input_cells$cluster[1] <- "foreign"
  state <- .sc_run_put(fixture$root, state, "annotation_evidence", evidence); fixture$commit(state)
  expect_error(.sc_run_react_context(fixture$root), "membership differs")
})

test_that("an absent outside comparison is unavailable rather than zero", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  seu <- fixture$seu; seu$seurat_clusters <- rep("0", ncol(seu))
  state <- .sc_run_put(fixture$root, fixture$state, "analysis", seu)
  evidence <- .sc_run_get(fixture$root, state, "annotation_evidence")
  evidence$private$input_cells$cluster <- rep("0", ncol(seu))
  state <- .sc_run_put(fixture$root, state, "annotation_evidence", evidence)
  fixture$commit(state); fixture$context <- .sc_run_react_context(fixture$root)
  out <- react_local(fixture, "gene_expression", list(cluster_id = "0", genes = "G01"))$result$genes[[1]]
  expect_identical(out$outside_status, "unavailable")
  expect_null(out$mean_outside); expect_null(out$detection_outside)
  expect_identical(out$test_status, "not_tested")
})

test_that("ACT uses exact saved species/tissue and omits private provenance", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  out <- react_local(fixture, "act_lookup", list(genes = c("G01", "G02")))$result
  expect_identical(out$status, "matched")
  expect_identical(vapply(out$entries, `[[`, character(1), "cell_type"), c("T cell", "B cell"))
  expect_identical(out$snapshot_version, "test-snapshot")
  expect_false(grepl("/private/", .sc_project_json(out), fixed = TRUE))
  expect_identical(react_local(fixture, "act_lookup", list(genes = "absent_gene"))$result$status, "zero_matches")
  state <- fixture$state; state$files$reference <- NULL; fixture$commit(state)
  fixture$context <- .sc_run_react_context(fixture$root)
  expect_identical(react_local(fixture, "act_lookup", list(genes = "G01"))$result$status, "unavailable")
})

test_that("context aggregates existing metadata, suppresses rare samples and preserves missingness", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  out <- react_local(fixture, "cluster_context", list(cluster_id = "0"))$result
  expect_identical(out$cells, 6L)
  expect_identical(out$samples$composition[[1]]$sample, "sample_1")
  expect_identical(out$qc$source, "saved_analysis_metadata")
  expect_identical(out$qc$mitochondrial_percent$status, "partial")
  expect_equal(out$qc$mitochondrial_percent$median, 3)
  expect_identical(out$doublet$status, "unavailable")
  expect_identical(out$cell_cycle$status, "unavailable")
  seu <- fixture$seu; seu$sample_label[1] <- "rare_identifier"
  state <- .sc_run_put(fixture$root, fixture$state, "analysis", seu); fixture$commit(state)
  fixture$context <- .sc_run_react_context(fixture$root)
  out <- react_local(fixture, "cluster_context", list(cluster_id = "0"))$result
  expect_identical(out$samples$status, "suppressed")
  expect_length(out$samples$composition, 0)
  expect_false(grepl("rare_identifier", .sc_project_json(out), fixed = TRUE))
})

test_that("diagnostic summaries align literal saved cell IDs including numeric score row names", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  scores <- data.frame(cell_id = fixture$cells, s = seq_len(12), g2m = NA_real_, difference = 1)
  record <- list(cell_ids = fixture$cells, scores = scores,
    summary = list(columns = c(s_score = "s", g2m_score = "g2m", difference = "difference")))
  state <- .sc_run_put(fixture$root, fixture$state, "cycle_diagnostics", record); fixture$commit(state)
  fixture$context <- .sc_run_react_context(fixture$root)
  out <- react_local(fixture, "cluster_context", list(cluster_id = "0"))$result
  expect_equal(out$cell_cycle$scores$s_score$median, 3.5)
  expect_null(out$cell_cycle$scores$g2m_score$median)
  record$scores$cell_id[1] <- "foreign-cell"
  state <- .sc_run_put(fixture$root, state, "cycle_diagnostics", record); fixture$commit(state)
  fixture$context <- .sc_run_react_context(fixture$root)
  expect_error(react_local(fixture, "cluster_context", list(cluster_id = "0")), "identity binding")
})

test_that("normalized arguments retain result identity and reject stale context", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  first <- react_local(fixture, "gene_expression", list(cluster_id = "0", genes = c("G02", "G01")))
  second <- react_local(fixture, "gene_expression", list(genes = c("G01", "G02"), cluster_id = "0"))
  expect_identical(first$result_hash, second$result_hash)
  old_hash <- fixture$context$input_hash
  state <- fixture$state; state$config$context$tissue <- "lung"; state$config_hash <- .sc_run_hash(state$config); fixture$commit(state)
  expect_error(react_local(fixture, "cluster_context", list(cluster_id = "0")), "no longer matches")
  fixture$context <- .sc_run_react_context(fixture$root)
  expect_false(identical(old_hash, fixture$context$input_hash))
})

test_that("scientific checkpoint mutation, context mutation and symlinks fail closed", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  original <- fixture$context
  fixture$context$config$normalized_layer <- "counts"
  expect_error(react_local(fixture, "gene_expression", list(cluster_id = "0", genes = "G01")), "binding changed")
  fixture$context$binding$normalized_config_hash <- .sc_run_hash(fixture$context$config)
  fixture$context$input_hash <- .sc_run_hash(fixture$context$binding)
  expect_error(react_local(fixture, "gene_expression", list(cluster_id = "0", genes = "G01")), "committed")
  fixture$context <- original
  fixture$context$binding$files$annotation_evidence <- NULL
  fixture$context$input_hash <- .sc_run_hash(fixture$context$binding)
  expect_error(react_local(fixture, "cluster_context", list(cluster_id = "0")), "no longer matches")
  fixture$context <- original
  outside <- tempfile(); dir.create(outside); on.exit(unlink(outside, recursive = TRUE), add = TRUE)
  linked <- file.path(fixture$root, "linked-cache")
  if (file.symlink(outside, linked)) expect_false(.sc_run_react_safe_path(file.path(linked, "file"), fixture$root))
  expect_false(.sc_run_react_safe_path(outside, fixture$root))
  path <- file.path(fixture$root, fixture$state$files$markers$path)
  saveRDS(list(changed = TRUE), path)
  expect_error(react_local(fixture, "cluster_markers", list(cluster_id = "0")), "checkpoint changed")
})

test_that("the public boundary rejects cells, paths, matrices, unknown fields and oversized results", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  for (value in list(list(gene = fixture$cells[1]), list(reason = paste("Observed", fixture$cells[1])),
      list(reason = "/tmp/local-file"), list(reason = "source=/tmp/local-file"),
      list(reason = "(../relative/local-file)"), list(reason = "file:///tmp/local-file"),
      list(reason = "data/sample.rds"),
      list(reason = "C:\\private\\local-file")))
    expect_error(.sc_run_react_public_check(value, fixture$context, 32768), class = "sc_run_react_error")
  for (gene in c("TRAV14/DV4", "TRAV38-2/DV8", "CD4/CD8", "HLA-DRA"))
    expect_silent(.sc_run_react_public_check(list(gene = gene), fixture$context, 32768))
  expect_error(.sc_run_react_public_check(list(cell_id = "x"), fixture$context, 32768), "outside")
  expect_error(.sc_run_react_public_check(list(genes = matrix(1, 2, 2)), fixture$context, 32768), "JSON summaries")
  expect_error(.sc_run_react_public_check(list(reason = paste(rep("x", 32769), collapse = "")), fixture$context, 32768), "byte limit")
  for (tool in names(.sc_run_react_tools())) {
    arguments <- switch(tool, cluster_markers = list(cluster_id = "0"),
      gene_expression = list(cluster_id = "0", genes = "G01"), act_lookup = list(genes = "G01"),
      cluster_context = list(cluster_id = "0"))
    out <- react_local(fixture, tool, arguments)$result
    expect_silent(.sc_run_react_public_check(out, fixture$context, .sc_run_react_tools()[[tool]]$max_result_bytes))
    expect_false(any(vapply(fixture$cells, grepl, logical(1), x = .sc_project_json(out), fixed = TRUE)))
  }
})

test_that("session worker rejects malformed and private arguments without changing state", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive = TRUE))
  runtime <- .sc_run_react_worker_start(fixture$context)
  on.exit(.sc_run_react_worker_close(runtime), add = TRUE)
  before <- .sc_project_sha_file(file.path(fixture$root, "state.rds"))
  out <- .sc_run_react_worker_call(runtime, "delete_cells", list(path = "/private/file"))
  expect_false(out$ok); expect_identical(out$error$code, "unknown_tool")
  out <- .sc_run_react_worker_call(runtime, "gene_expression", list(cluster_id = "0", genes = rep("x", 21)))
  expect_false(out$ok); expect_identical(out$error$code, "invalid_arguments")
  expect_false(grepl("/private/", .sc_project_json(out), fixed = TRUE))
  out <- .sc_run_react_worker_call(runtime, "cluster_context", list(cluster_id = "0"))
  expect_true(out$ok, info = paste(out$error$code, out$error$message))
  expect_identical(out$result$cells, 6L)
  hit <- .sc_run_react_worker_call(runtime, "cluster_context", list(cluster_id = "0"))
  expect_true(hit$cached)
  for (gene in c(fixture$cells[1], "/tmp/a", "source=/tmp/a")) {
    private <- .sc_run_react_worker_call(runtime, "act_lookup", list(genes = gene))
    expect_false(private$ok)
    expect_identical(private$error$code, "private_output")
    expect_false(grepl(gene, .sc_project_json(private), fixed = TRUE))
  }
  expect_silent(.sc_run_react_worker_check(runtime, final = TRUE))
  expect_identical(.sc_project_sha_file(file.path(fixture$root, "state.rds")), before)
})

test_that("ACT tools honor an explicit reference scope without replacing study tissue", {
  fixture <- react_tool_fixture(); on.exit(unlink(fixture$root, recursive=TRUE))
  state <- fixture$state
  state$config$context$tissue <- "Peripheral blood study"
  state$config$reference_review <- list(tissue="blood")
  state$config_hash <- .sc_run_hash(state$config)
  fixture$commit(state)
  fixture$context <- .sc_run_react_context(fixture$root)
  before <- .sc_project_sha_file(file.path(fixture$root,"state.rds"))
  out <- react_local(fixture,"act_lookup",list(genes="G01"))$result
  expect_identical(out$status,"matched")
  expect_identical(out$tissue,"blood")
  expect_identical(fixture$context$config$context$tissue,"Peripheral blood study")
  expect_null(out$study_tissue) # Retain the existing bounded public tool projection.
  expect_true(all(vapply(out$entries,function(row)row$tissue=="blood",logical(1))))
  expect_identical(.sc_project_sha_file(file.path(fixture$root,"state.rds")),before)
})
