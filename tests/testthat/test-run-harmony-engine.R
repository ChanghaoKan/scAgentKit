# Deterministic software fixtures establish the operation's mechanics and
# bounds. Their factor labels and shifted embeddings are not biological truth.
harmony_engine_roles <- function(n = 64L) {
  list(batch = rep(c("batch A", "batch B"), each = n / 2L),
    sample = rep(c("sample A", "sample B"), length.out = n),
    donor = rep(c("donor A", "donor B"), each = 2L, length.out = n),
    condition = rep(rep(c("Ctrl", "Ca"), each = n / 4L), 2L),
    capture = rep(c("physical capture 1", "physical capture 2"), each = n / 2L))
}

harmony_engine_choice <- function(columns = "batch") list(method = "harmony",
  group_by_vars = columns, theta = 2, lambda = 1, sigma = .1, max_iter = 3L,
  nclust = 4L, reason = "Explicitly review a sourced technical correction on a crossed software-control design.")

harmony_engine_evidence <- function(roles = harmony_engine_roles(), technical = TRUE) {
  columns <- as.list(stats::setNames(names(roles), names(roles)))
  list(summary = list(declared_roles = columns,
    background_facts = list(columns = columns, design = list(technical_batch = technical,
      notes = "Authored crossed software controls; labels do not establish correct integration."))))
}

harmony_engine_fixture <- function() {
  roles <- harmony_engine_roles()
  cells <- c("001", "1", "NA", "cell space", paste0("literal ", 5:64))
  genes <- paste0("LiteralGene", 1:30)
  counts <- matrix((seq_len(30L * 64L) %% 7L) + 1, 30L, 64L, dimnames = list(genes, cells))
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- log1p(Matrix::Matrix(counts, sparse = TRUE))
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <- Matrix::Matrix(counts * 2, sparse = TRUE)
  for (name in names(roles)) object[[name]] <- roles[[name]]
  object$old_annotation <- factor(rep(c("prior label", NA_character_), 32L), levels = c("prior label", "unused label"))
  embeddings <- matrix(sin(seq_len(64L * 6L) / 7), 64L, 6L,
    dimnames = list(cells, paste0("PC_", 1:6)))
  object[["pca"]] <- SeuratObject::CreateDimReducObject(embeddings = embeddings,
    stdev = seq(2, 1, length.out = 6L), assay = "RNA", key = "PC_")
  other <- embeddings[, 1:2, drop = FALSE]; colnames(other) <- paste0("OTHER_", 1:2)
  object[["caller_projection"]] <- SeuratObject::CreateDimReducObject(embeddings = other, assay = "RNA", key = "OTHER_")
  context <- list(species = "human", columns = as.list(stats::setNames(names(roles), names(roles))),
    design = list(technical_batch = TRUE, notes = "Crossed synthetic metadata; no inference about donors or capture."))
  config <- list(context = context, assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    cluster_column = "seurat_clusters", start_stage = "qc")
  plan <- list(analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 10L, npcs = 6L, seed = 77L),
    pcs = list(method = "fixed", ndim = 3L), batch = harmony_engine_choice(),
    clustering = list(resolution = .4, diagnostic_resolutions = numeric()),
    umap = list(run = FALSE, n_neighbors = 10L))
  list(object = object, roles = roles, config = config, plan = plan)
}

harmony_engine_mock <- function(env = parent.frame(), failure = NULL) {
  calls <- new.env(parent = emptyenv()); calls$count <- 0L; calls$args <- NULL
  mocked <- function(...) {
    args <- list(...); calls$count <- calls$count + 1L; calls$args <- args[names(args) != "object"]
    object <- args$object
    # The local fixture intentionally uses RNG to verify the executor's
    # fixed seed and restoration, without executing the Harmony algorithm.
    shift <- stats::runif(1, .01, .02)
    embeddings <- SeuratObject::Embeddings(object[[args$reduction.use]])[, args$dims.use, drop = FALSE] + shift
    colnames(embeddings) <- paste0("HARMONY_", seq_len(ncol(embeddings)))
    if (identical(failure, "ids")) rownames(embeddings) <- rev(rownames(embeddings))
    if (identical(failure, "nonfinite")) embeddings[1, 1] <- Inf
    object[[args$reduction.save]] <- SeuratObject::CreateDimReducObject(embeddings = embeddings,
      assay = "RNA", key = "HARMONY_")
    if (identical(failure, "metadata")) object$old_annotation <- "changed"
    if (identical(failure, "counts")) {
      counts <- SeuratObject::LayerData(object, assay = "RNA", layer = "counts")
      counts[1, 1] <- counts[1, 1] + 1
      SeuratObject::LayerData(object, assay = "RNA", layer = "counts") <- counts
    }
    if (identical(failure, "pca")) {
      changed <- SeuratObject::Embeddings(object[["pca"]]); changed[1, 1] <- changed[1, 1] + 1
      object[["pca"]] <- SeuratObject::CreateDimReducObject(embeddings = changed,
        stdev = seq(2, 1, length.out = 6L), assay = "RNA", key = "PC_")
    }
    if (identical(failure, "error")) stop("Deliberate software-fixture runtime failure.")
    if (identical(failure, "warning")) warning("Explicit diagnostic warning from the software fixture.")
    object
  }
  testthat::local_mocked_bindings(RunHarmony = mocked, .package = "harmony", .env = env)
  calls
}

test_that("typed Harmony parameters reject unsupported fields and canonicalize numeric JSON representations", {
  parameters <- scAgentKit:::.sc_run_harmony_parameters
  none <- list(method = "none", reason = "Retain the computed PCA without technical correction.")
  manual <- list(method = "manual", reason = "Wait for an analyst to resolve batch design.")
  expect_identical(parameters(none), none); expect_identical(parameters(manual), manual)
  base <- harmony_engine_choice(c("batch", "sample"))
  expect_identical(parameters(base, 64), base)
  json <- jsonlite::fromJSON(jsonlite::toJSON(base, auto_unbox = TRUE), simplifyVector = FALSE)
  expect_identical(parameters(json, 64L), base)
  for (name in c("code", "genes", "harmony_options", "max.iter.harmony", "reduction", "project.dim")) {
    bad <- base; bad[[name]] <- "unsupported"
    expect_error(parameters(bad), "supported named fields")
  }
  for (value in list(NULL, character(), c("batch", "batch"), c("batch", "sample", "donor", "fourth"),
                     c(batch = "batch"), list(column = "batch"))) {
    bad <- base; bad$group_by_vars <- value
    expect_error(parameters(bad), "requires exactly|group_by_vars")
  }
  for (field in c("theta", "lambda")) for (value in list(NULL, NA_real_, Inf, c(1, 2, 3), list(x = 2), c(x = 2))) {
    bad <- base; bad[[field]] <- value
    expect_error(parameters(bad), "supported named fields|requires exactly|numeric|Harmony")
  }
  bad <- base; bad$theta <- -1; expect_error(parameters(bad), "nonnegative")
  bad <- base; bad$lambda <- 0; expect_error(parameters(bad), "positive")
  good <- base; good$theta <- c(0, 2); good$lambda <- c(1, 3)
  expect_identical(parameters(good), good)
  for (field in c("sigma", "max_iter", "nclust")) {
    bad <- base; bad[[field]] <- 0
    expect_error(parameters(bad, 64), "Invalid Harmony")
    bad[[field]] <- Inf; expect_error(parameters(bad, 64), "Invalid Harmony")
  }
  bad <- base; bad$sigma <- 1.1; expect_error(parameters(bad), "sigma")
  bad <- base; bad$max_iter <- 51; expect_error(parameters(bad), "max_iter")
  bad <- base; bad$max_iter <- 1.5; expect_error(parameters(bad), "max_iter")
  bad <- base; bad$nclust <- 64; expect_error(parameters(bad, 64), "nclust")
  bad <- base; bad$reason <- " "; expect_error(parameters(bad), "nonempty")
})

test_that("none always executes and manual/processed Harmony remain explicit analyst boundaries", {
  validate <- scAgentKit:::.sc_run_harmony_choice
  none <- list(method = "none", reason = "No correction requested on this processed source.")
  result <- validate(none, list(), list(), processed = TRUE)
  expect_true(result$executable); expect_identical(result$choice, none)
  expect_identical(result$blockers, list())
  manual <- list(method = "manual", reason = "Resolve biological confounding first.")
  result <- validate(manual, list(), list(), processed = TRUE)
  expect_false(result$executable); expect_identical(result$choice, manual)
  expect_identical(result$blockers[[1L]]$code, "manual_required")
  roles <- harmony_engine_roles(); result <- validate(harmony_engine_choice(), harmony_engine_evidence(), roles, TRUE)
  expect_false(result$executable)
  expect_true("processed_harmony_unsupported" %in% vapply(result$blockers, `[[`, character(1), "code"))
})

test_that("crossed declared factors produce full-rank local audit and dependency absence is not a static selector", {
  roles <- harmony_engine_roles(); evidence <- harmony_engine_evidence()
  evidence$summary$dependencies <- list(harmony = list(available = FALSE))
  result <- scAgentKit:::.sc_run_harmony_choice(harmony_engine_choice(c("batch", "sample", "donor")), evidence, roles)
  expect_true(result$executable); expect_true(result$audit$joint_rank$full_rank)
  expect_true(result$audit$joint_rank$sparse)
  expect_identical(result$audit$joint_rank$rank, 5L)
  expect_identical(result$applicability$selected_roles, c("batch", "sample", "donor"))
  expect_identical(result$applicability$selected_columns, c("batch", "sample", "donor"))
  expect_identical(length(result$audit$per_factor_biology), 3L)
  expect_identical(length(result$audit$factor_pairs), 3L)
  for (i in seq_along(result$audit$selected_factors)) {
    factor <- result$audit$selected_factors[[i]]
    expect_identical(factor$role, c("batch", "sample", "donor")[i])
    expect_identical(factor$value_hash, scAgentKit:::.sc_run_hash(roles[[factor$role]]))
    expect_identical(factor$level_count, 2L)
  }
  expect_match(paste(result$audit$warnings, collapse = " "), "not proof|can attenuate biology")
  changed <- harmony_engine_choice(); changed$reason <- "Another explanation of exactly the same scientific operation."
  prior <- scAgentKit:::.sc_run_harmony_choice(harmony_engine_choice(), evidence, roles)
  revised <- scAgentKit:::.sc_run_harmony_choice(changed, evidence, roles)
  expect_identical(prior$audit, revised$audit)
  expect_identical(prior$applicability, revised$applicability)
})

test_that("provenance, missing values, single levels, nesting, aliases and biological confounding block correction", {
  validate <- scAgentKit:::.sc_run_harmony_choice
  roles <- harmony_engine_roles(); evidence <- harmony_engine_evidence()
  missing <- harmony_engine_evidence(technical = FALSE)
  expect_false(validate(harmony_engine_choice(), missing, roles)$executable)
  for (value in list(rep("single", 64L), c(NA_character_, roles$batch[-1L]), c("", roles$batch[-1L]),
                     c(Inf, rep(1, 63L)))) {
    bad <- roles; bad$batch <- value
    result <- validate(harmony_engine_choice(), evidence, bad)
    expect_false(result$executable); expect_identical(result$audit$status, "manual_boundary")
  }
  bad <- roles; bad$condition <- rep("one condition", 64L)
  result <- validate(harmony_engine_choice(), evidence, bad)
  expect_false(result$executable)
  expect_true("biological_roles_missing" %in% vapply(result$blockers, `[[`, character(1), "code"))
  confounded <- roles; confounded$batch <- confounded$condition
  result <- validate(harmony_engine_choice(), evidence, confounded)
  expect_false(result$executable); expect_true(result$audit$per_factor_biology[[1L]]$alias)
  nested <- roles; nested$sample <- paste0(nested$condition, ":", rep(1:2, length.out = 64L))
  result <- validate(harmony_engine_choice("sample"), evidence, nested)
  expect_false(result$executable)
  expect_match(paste(result$audit$warnings, collapse = " "), "sample is nested.*No preservation claim")
  alias <- roles; alias$sample <- alias$batch
  result <- validate(harmony_engine_choice(c("batch", "sample")), evidence, alias)
  expect_false(result$executable); expect_true(result$audit$factor_pairs[[1L]]$alias)
  for (column in c("capture", "condition", "invented batch"))
    expect_error(validate(harmony_engine_choice(column), evidence, roles), "cannot directly|map uniquely")
  ambiguity <- evidence; ambiguity$summary$declared_roles$sample <- "batch"
  expect_error(validate(harmony_engine_choice(), ambiguity, roles), "map uniquely")
  aliased_biology <- evidence; aliased_biology$summary$declared_roles$condition <- "batch"
  expect_error(validate(harmony_engine_choice(), aliased_biology, roles), "cannot directly")
  treatment <- roles; treatment$treatment <- treatment$condition; treatment$condition <- NULL
  result <- validate(harmony_engine_choice(), harmony_engine_evidence(treatment), treatment)
  expect_true(result$executable); expect_identical(result$audit$biological_roles[[1L]]$role, "treatment")
})

test_that("mocked public Harmony call uses exact arguments and preserves raw layers, PCA, metadata, IDs and RNG", {
  skip_if_not_installed("harmony")
  f <- harmony_engine_fixture(); f$plan$batch <- harmony_engine_choice(c("batch", "sample"))
  calls <- harmony_engine_mock()
  saved <- serialize(f$object, NULL, version = 2L); before_layers <- scAgentKit:::.sc_run_harmony_layers(f$object, "RNA")
  set.seed(777); before_rng <- .Random.seed; before_kind <- RNGkind()
  output <- scAgentKit:::.sc_run_strategy_batch(f$object, f$config, f$plan)
  expect_identical(.Random.seed, before_rng); expect_identical(RNGkind(), before_kind)
  expect_identical(serialize(f$object, NULL, version = 2L), saved)
  expect_identical(output[[]], f$object[[]]); expect_identical(colnames(output), colnames(f$object))
  expect_identical(scAgentKit:::.sc_run_harmony_layers(output, "RNA"), before_layers)
  expect_identical(output[["pca"]], f$object[["pca"]])
  expect_identical(output[["caller_projection"]], f$object[["caller_projection"]])
  expect_identical(calls$count, 1L)
  expect_identical(calls$args$reduction.use, "pca"); expect_false(calls$args$project.dim)
  expect_identical(calls$args$reduction.save, "harmony"); expect_identical(calls$args$dims.use, 1:3)
  expect_identical(calls$args$theta, c(2, 2)); expect_identical(calls$args$lambda, 1)
  expect_identical(calls$args$max_iter, 3L); expect_identical(calls$args$nclust, 4L)
  expect_identical(calls$args$ncores, 1L); expect_true(calls$args$early_stop)
  expect_s3_class(calls$args$.options, "harmony_options")
  expect_false(any(c("reduction", "max.iter.harmony", "max_iter_harmony") %in% names(calls$args)))
  record <- output@misc$strategy_execution$batch
  expect_identical(record$choice, f$plan$batch); expect_identical(record$reduction, "harmony")
  expect_true(record$corrected); expect_identical(record$layers_before, record$layers_after)
  expect_identical(record$pca_hash, scAgentKit:::.sc_run_hash(f$object[["pca"]]))
  expect_identical(record$source_hash, scAgentKit:::.sc_run_hash(record$source))
  expect_identical(record$effective_parameters$options, record$source$fixed_options)
  expect_identical(record$source$fixed_options_hash, scAgentKit:::.sc_run_hash(record$source$fixed_options))
  expect_identical(record$diagnostics$subset$cells, 64L)
  expect_identical(length(record$diagnostics$technical_mixing), 2L)
  expect_identical(length(record$diagnostics$biological_same_label), 1L)
  expect_match(paste(record$diagnostics$interpretation, collapse = " "), "not.*truth|does not prove")
  expect_true(all(vapply(record$diagnostics$technical_mixing, function(row)
    row$before$mean >= 0 && row$before$mean <= 1 && row$after$mean >= 0 && row$after$mean <= 1, logical(1))))
  # Repeating the leaf on the original copy is only a deterministic software
  # test. The coordinator's checkpoint tests separately forbid repeat calls.
  repeated <- scAgentKit:::.sc_run_strategy_batch(f$object, f$config, f$plan)
  expect_identical(SeuratObject::Embeddings(output[["harmony"]]), SeuratObject::Embeddings(repeated[["harmony"]]))
  expect_identical(.Random.seed, before_rng)
  expect_error(scAgentKit:::.sc_run_strategy_batch(output, f$config, f$plan), "already contains")
})

test_that("runtime does not invoke Harmony for none and preserves recoverable errors without a silent fallback", {
  skip_if_not_installed("harmony")
  f <- harmony_engine_fixture(); calls <- harmony_engine_mock()
  plan <- f$plan; plan$batch <- list(method = "none", reason = "Retain the uncorrected PCA explicitly.")
  output <- scAgentKit:::.sc_run_strategy_batch(f$object, f$config, plan)
  expect_identical(calls$count, 0L); expect_false(output@misc$strategy_execution$batch$corrected)
  expect_identical(output@misc$strategy_execution$batch$reduction, "pca")
  expect_false("harmony" %in% names(output@reductions))
  plan$batch <- list(method = "manual", reason = "Resolve the design first.")
  expect_error(scAgentKit:::.sc_run_strategy_batch(f$object, f$config, plan), "Manual batch")
  for (failure in c("metadata", "counts", "pca", "nonfinite", "error")) {
    local({
      failed_calls <- harmony_engine_mock(failure = failure)
      set.seed(33); prior <- .Random.seed
      expect_error(scAgentKit:::.sc_run_strategy_batch(f$object, f$config, f$plan),
        "protected|finite dimensions|runtime failure")
      expect_identical(.Random.seed, prior); expect_identical(failed_calls$count, 1L)
    })
  }
})

test_that("bounded neighborhood diagnostics separate technical mixing from biological labels without selecting parameters", {
  cells <- paste0("literal", 1:600)
  before <- cbind(seq_len(600), sin(seq_len(600)))
  rownames(before) <- cells; colnames(before) <- c("PC_1", "PC_2")
  roles <- list(batch = rep(c("A", "B"), 300L), condition = rep(c("Ca", "Ctrl"), each = 300L))
  after <- before + .01
  record <- scAgentKit:::.sc_run_harmony_diagnostics(before, after, roles, "batch")
  expect_identical(record$subset$cells, 512L); expect_identical(record$subset$full_cells, 600L)
  expect_identical(record$subset$k, 20L)
  expect_identical(record$technical_mixing[[1L]]$role, "batch")
  expect_identical(record$biological_same_label[[1L]]$role, "condition")
  expect_equal(record$technical_mixing[[1L]]$delta_mean, 0, tolerance = 0)
  expect_equal(record$biological_same_label[[1L]]$delta_mean, 0, tolerance = 0)
  expect_match(record$subset$limitation, "unrepresentative")
  expect_match(paste(record$interpretation, collapse = " "), "No diagnostic automatically selects")
})
