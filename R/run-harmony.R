# Reviewed Harmony corrects only a derived cell embedding. Typed choices,
# source design, and all preserved assay/metadata identities are audited.
.sc_run_harmony_parameters <- function(choice, retained = NULL) {
  if (!is.list(choice) || is.null(choice$method))
    .sc_project_fail("Batch choice requires a typed method and explicit reason.")
  method <- .sc_run_strategy_text(choice$method, "strategy$batch$method", 80L)
  if (!method %in% c("none", "manual", "harmony"))
    .sc_project_fail("Unsupported batch method; choose none, manual, or the constrained Harmony operation.")
  required <- if (method == "harmony")
    c("method", "group_by_vars", "theta", "lambda", "sigma", "max_iter", "nclust", "reason") else c("method", "reason")
  choice <- .sc_run_strategy_fields(choice, required, name = "Batch choice")
  reason <- .sc_run_strategy_text(choice$reason, "strategy$batch$reason")
  if (method != "harmony") return(list(method = method, reason = reason))
  columns <- choice$group_by_vars
  if (is.list(columns)) {
    if (!is.null(names(columns)) || !all(vapply(columns,
      function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x)), logical(1))))
      .sc_project_fail("Harmony group_by_vars must be an unnamed array of literal metadata columns.")
    columns <- unlist(columns, use.names = FALSE)
  }
  if (!is.character(columns) || !is.null(names(columns)) || length(columns) < 1L ||
      length(columns) > 3L || anyNA(columns) || any(!nzchar(trimws(columns))) || anyDuplicated(columns))
    .sc_project_fail("Harmony group_by_vars requires one to three unique literal metadata columns; no variable is guessed.")
  vector_parameter <- function(value, name, positive) {
    if (is.list(value)) {
      if (!is.null(names(value)) || !all(vapply(value, function(x) is.numeric(x) && length(x) == 1L, logical(1))))
        .sc_project_fail(paste0("Harmony ", name, " requires an unnamed numeric scalar or per-factor vector."))
      value <- unlist(value, use.names = FALSE)
    }
    if (!is.numeric(value) || !is.null(names(value)) ||
        !length(value) %in% c(1L, length(columns)) || any(!is.finite(value)) ||
        any(if (positive) value <= 0 else value < 0))
      .sc_project_fail(paste0("Harmony ", name, " requires a finite ", if (positive) "positive" else "nonnegative",
        " numeric scalar or one value per selected factor; automatic NULL and unsupported values are rejected."))
    unname(as.numeric(value))
  }
  theta <- vector_parameter(choice$theta, "theta", FALSE)
  lambda <- vector_parameter(choice$lambda, "lambda", TRUE)
  sigma <- .sc_run_strategy_number(choice$sigma, "Harmony sigma", 0, 1, open_min = TRUE)
  max_iter <- .sc_run_strategy_number(choice$max_iter, "Harmony max_iter", 1, 50, integer = TRUE)
  maximum <- 100L
  if (!is.null(retained)) {
    retained <- .sc_run_strategy_number(retained, "retained cells for Harmony", 3, .Machine$integer.max, integer = TRUE)
    maximum <- min(100L, retained - 1L)
  }
  nclust <- .sc_run_strategy_number(choice$nclust, "Harmony nclust", 2, maximum, integer = TRUE)
  list(method = "harmony", group_by_vars = unname(columns), theta = theta, lambda = lambda,
    sigma = sigma, max_iter = max_iter, nclust = nclust, reason = reason)
}

.sc_run_harmony_complete_values <- function(values, n) {
  (is.character(values) || is.factor(values) || is.numeric(values) || is.logical(values)) &&
    length(values) == n && !anyNA(values) && !any(!nzchar(trimws(as.character(values)))) &&
    !(is.numeric(values) && any(!is.finite(values)))
}

.sc_run_harmony_rank <- function(factors) {
  n <- length(factors[[1L]])
  data <- as.data.frame(stats::setNames(lapply(factors, function(x)
    factor(as.character(x), levels = sort(unique(enc2utf8(as.character(x))), method = "radix"))),
    paste0("factor", seq_along(factors))), stringsAsFactors = FALSE)
  design <- Matrix::sparse.model.matrix(stats::reformulate(names(data)), data = data,
    contrasts.arg = stats::setNames(rep(list("contr.treatment"), ncol(data)), names(data)))
  rank <- as.integer(Matrix::rankMatrix(design, method = "qr", tol = 1e-7)[1L])
  list(cells = n, rank = rank, columns = ncol(design), full_rank = rank == ncol(design),
    sparse = inherits(design, "sparseMatrix"), tolerance = 1e-7,
    design_hash = .sc_run_hash(design),
    interpretation = "Rank of the observed additive factor-indicator design; full rank does not establish scientific benefit or preserved biology.")
}

.sc_run_harmony_relation <- function(left, right, left_name, right_name) {
  pairs <- .sc_run_strategy_pairs(left, right, "left", "right")
  left_levels <- unique(as.character(left)); right_levels <- unique(as.character(right))
  l <- match(pairs$left, left_levels); r <- match(pairs$right, right_levels)
  left_nested <- all(tabulate(l, nbins = length(left_levels)) == 1L)
  right_nested <- all(tabulate(r, nbins = length(right_levels)) == 1L)
  audit <- .sc_run_strategy_batch_audit(list(batch = as.character(left), group = as.character(right)))
  list(left = left_name, right = right_name, left_levels = length(left_levels), right_levels = length(right_levels),
    left_nested_in_right = left_nested, right_nested_in_left = right_nested,
    alias = left_nested && right_nested, complete_confounding = audit$complete_confounding,
    full_rank = audit$full_rank, rank = audit$design_rank, columns = audit$design_columns,
    status = audit$status, table = pairs$rows)
}

.sc_run_harmony_choice <- function(choice, evidence, projected_roles, processed = FALSE) {
  if (!is.list(projected_roles)) .sc_project_fail("Harmony design requires the actual projected declared metadata roles.")
  if (!identical(processed, FALSE) && !identical(processed, TRUE))
    .sc_project_fail("Harmony processed entry declaration must be logical.")
  sizes <- lengths(projected_roles)
  nonzero <- unique(sizes[sizes > 0L])
  retained <- if (length(nonzero) == 1L) nonzero else NULL
  canonical <- .sc_run_harmony_parameters(choice, if (!is.null(retained) && retained >= 3L) retained else NULL)
  columns <- evidence$summary$declared_roles
  if (is.null(columns)) columns <- evidence$summary$background_facts$columns
  if (is.null(columns)) columns <- list()
  design <- evidence$summary$background_facts$design
  technical <- isTRUE(design$technical_batch)
  blockers <- list(); warnings <- character()
  block <- function(code, message) {
    blockers[[length(blockers) + 1L]] <<- list(code = code, operation = "batch", message = message)
  }
  audit <- list(schema = "scagentkit.harmony.design.v1", method = canonical$method,
    technical_batch_declared = technical, retained_cells = retained, selected_factors = list(),
    biological_roles = list(), per_factor_biology = list(), factor_pairs = list(), joint_rank = NULL,
    warnings = character(), interpretation = "Declared quality groups, capture/loading units, donors and biological conditions are distinct roles; no relationship is inferred.")
  if (canonical$method == "none") {
    audit$status <- "not_requested"; audit$executable <- TRUE
    return(list(choice = canonical, audit = audit, executable = TRUE, blockers = list(),
      applicability = list(method = "none", executable = TRUE, selected_columns = character(),
        selected_roles = character(), warnings = character(), blockers = list())))
  }
  if (canonical$method == "manual") {
    block("manual_required", "The reviewed strategy explicitly defers batch handling to the analyst; execution remains blocked. Supply a supported revised strategy before execution.")
    audit$status <- "manual_required"; audit$executable <- FALSE
    return(list(choice = canonical, audit = audit, executable = FALSE, blockers = blockers,
      applicability = list(method = "manual", executable = FALSE, selected_columns = character(),
        selected_roles = character(), warnings = character(), blockers = blockers)))
  }
  if (isTRUE(processed)) block("processed_harmony_unsupported", "Processed entry reuses its existing analysis foundation; choose none/manual or explicitly begin a raw entry before Harmony.")
  if (!technical) block("technical_provenance_missing", "Harmony requires context$design$technical_batch=TRUE as explicit technical provenance; a sample/donor label alone is insufficient.")
  if (is.null(retained) || retained < 3L) block("retained_metadata_missing", "Projected role metadata do not supply one complete retained-cell scope.")
  selected_roles <- vapply(canonical$group_by_vars, function(column) {
    if (column %in% unlist(columns[intersect(c("capture", "group", "condition", "treatment"), names(columns))], use.names = FALSE))
      .sc_project_fail("Harmony cannot directly correct capture, group, condition or treatment, including a selected column aliasing one of those declared roles.")
    matched <- intersect(c("batch", "sample", "donor"), names(columns))[vapply(
      columns[intersect(c("batch", "sample", "donor"), names(columns))], identical, logical(1), column)]
    if (length(matched) != 1L)
      .sc_project_fail("Every Harmony group_by_vars column must map uniquely to an explicitly declared batch/sample/donor metadata role.")
    matched
  }, character(1), USE.NAMES = FALSE)
  selected <- list()
  for (i in seq_along(selected_roles)) {
    role <- selected_roles[i]; values <- projected_roles[[role]]
    valid <- !is.null(retained) && .sc_run_harmony_complete_values(values, retained)
    levels <- if (valid) sort(unique(enc2utf8(as.character(values))), method = "radix") else character()
    audit$selected_factors[[i]] <- list(column = canonical$group_by_vars[i], role = role,
      measured = valid, levels = levels, level_count = if (valid) length(levels) else NULL,
      level_sizes = if (valid) .sc_run_strategy_group_counts(as.character(values)) else list(),
      value_hash = if (valid) .sc_run_hash(unname(as.character(values))) else NULL)
    if (!valid) block("factor_values_missing", paste0("Selected factor `", canonical$group_by_vars[i], "` is missing, nonfinite, empty or incomplete on retained cells.")) else
      if (length(levels) < 2L) block("single_factor_level", paste0("Selected factor `", canonical$group_by_vars[i], "` has one retained level; between-factor correction is not applicable.")) else
        selected[[role]] <- as.character(values)
  }
  biological <- list()
  seen_columns <- character()
  for (role in intersect(c("group", "condition", "treatment"), names(columns))) {
    if (columns[[role]] %in% seen_columns) next
    seen_columns <- c(seen_columns, columns[[role]])
    values <- projected_roles[[role]]
    valid <- !is.null(retained) && .sc_run_harmony_complete_values(values, retained)
    levels <- if (valid) sort(unique(enc2utf8(as.character(values))), method = "radix") else character()
    audit$biological_roles[[length(audit$biological_roles) + 1L]] <- list(role = role, column = columns[[role]],
      measured = valid, levels = levels, level_count = if (valid) length(levels) else NULL,
      level_sizes = if (valid) .sc_run_strategy_group_counts(as.character(values)) else list(),
      value_hash = if (valid) .sc_run_hash(unname(as.character(values))) else NULL)
    if (valid && length(levels) >= 2L) biological[[role]] <- as.character(values)
  }
  if (!length(biological)) block("biological_roles_missing", "At least one explicitly declared group/condition/treatment role with complete metadata and two retained levels is required to audit biological confounding.")
  for (role in names(selected)) for (bio in names(biological)) {
    relation <- .sc_run_harmony_relation(selected[[role]], biological[[bio]], role, bio)
    audit$per_factor_biology[[length(audit$per_factor_biology) + 1L]] <- relation
    if (isTRUE(relation$complete_confounding) || identical(relation$full_rank, FALSE))
      block("factor_biology_confounded", paste0("Selected ", role, " and biological ", bio,
        " are completely confounded or rank deficient in the retained additive design; technical and biological effects are not independently estimable."))
    if (role %in% c("sample", "donor") && (isTRUE(relation$left_nested_in_right) || isTRUE(relation$right_nested_in_left)))
      warnings <- c(warnings, paste0("Selected ", role, " is nested with biological ", bio,
        "; correcting it may erase biological variation. No preservation claim follows from omitting treatment as a covariate."))
  }
  if (length(selected) > 1L) for (i in seq_len(length(selected) - 1L)) for (j in seq.int(i + 1L, length(selected))) {
    relation <- .sc_run_harmony_relation(selected[[i]], selected[[j]], names(selected)[i], names(selected)[j])
    audit$factor_pairs[[length(audit$factor_pairs) + 1L]] <- relation
    if (isTRUE(relation$alias) || isTRUE(relation$left_nested_in_right) || isTRUE(relation$right_nested_in_left) || identical(relation$full_rank, FALSE))
      block("selected_factors_not_identifiable", paste0("Selected factors ", names(selected)[i], " and ", names(selected)[j],
        " are aliased, nested or rank deficient; jointly correcting redundant factors is blocked."))
  }
  if (length(selected) == length(selected_roles) && length(biological)) {
    audit$joint_rank <- .sc_run_harmony_rank(c(selected, biological))
    if (!isTRUE(audit$joint_rank$full_rank))
      block("joint_design_rank_deficient", "The joint additive design of all selected technical factors and declared biological roles is rank deficient; no automatic correction is executed.")
  }
  warnings <- unique(c(warnings,
    "Harmony changes an embedding and can attenuate biology even in a full-rank design; diagnostic improvement is not proof of benefit.",
    "Technical neighbor mixing and biological same-label neighborhood fractions are separate descriptive diagnostics, never optimization targets or acceptance rules.",
    "No cells, samples, assay values or biological metadata are deleted or relabeled by this operation."))
  executable <- !length(blockers)
  audit$status <- if (executable) "reviewed_design_supported" else "manual_boundary"
  audit$executable <- executable; audit$warnings <- warnings; audit$blockers <- blockers
  list(choice = canonical, audit = audit, executable = executable, blockers = blockers,
    applicability = list(method = "harmony", executable = executable,
      selected_columns = canonical$group_by_vars, selected_roles = selected_roles,
      technical_batch_declared = technical, factor_levels = lapply(audit$selected_factors, `[[`, "levels"),
      factor_value_hashes = lapply(audit$selected_factors, `[[`, "value_hash"),
      biological_roles = audit$biological_roles, joint_rank = audit$joint_rank,
      warnings = warnings, blockers = blockers))
}

.sc_run_harmony_function_hash <- function(fn) {
  .sc_run_hash(list(formals = paste(deparse(formals(fn), width.cutoff = 500L), collapse = "\n"),
    body = paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n")))
}

.sc_run_harmony_source <- function() {
  .sc_run_strategy_runtime_dependencies(c("harmony", "Seurat", "SeuratObject", "Matrix"))
  version <- as.character(utils::packageVersion("harmony"))
  if (!grepl("^2\\.0\\.[0-9]+$", version))
    .sc_project_fail("Harmony runtime supports the explicitly audited 2.0.x public API only; another release requires adapter verification before retry.")
  generic <- getExportedValue("harmony", "RunHarmony")
  # The accepted release registers these public S3 methods without separately
  # exporting their symbols. Fetch the exact namespace bindings used by those
  # registrations rather than following a generic's lexical environment (a
  # provider-free test can replace only the generic). No upstream namespace or
  # S3 registration is modified, and no alternate method is accepted.
  namespace <- asNamespace("harmony")
  seurat <- get("RunHarmony.Seurat", envir = namespace, inherits = FALSE)
  default <- get("RunHarmony.default", envir = namespace, inherits = FALSE)
  options_function <- getExportedValue("harmony", "harmony_options")
  expected_seurat <- c("object", "group.by.vars", "reduction.use", "dims.use", "reduction.save", "project.dim", "...")
  expected_default <- c("data_mat", "meta_data", "vars_use", "theta", "sigma", "lambda", "nclust", "max_iter", "early_stop", "ncores", "plot_convergence", "return_object", "verbose", ".options", "...")
  if (!is.function(generic) || !is.function(seurat) || !is.function(default) || !is.function(options_function) ||
      !identical(names(formals(generic)), "...") ||
      !identical(names(formals(seurat)), expected_seurat) ||
      !identical(names(formals(default)), expected_default))
    .sc_project_fail("Harmony public method signatures differ from the supported exact modern API; reduction partial matching and legacy iteration arguments are not accepted.")
  fixed_options <- options_function()
  if (!inherits(fixed_options, "harmony_options") || !is.list(fixed_options))
    .sc_project_fail("Harmony default advanced options did not resolve to the supported public options object.")
  list(versions = list(harmony = version, Seurat = as.character(utils::packageVersion("Seurat")),
    SeuratObject = as.character(utils::packageVersion("SeuratObject")), Matrix = as.character(utils::packageVersion("Matrix")),
    R = as.character(getRversion())),
    source_hashes = list(generic = .sc_run_harmony_function_hash(generic),
      seurat = .sc_run_harmony_function_hash(seurat), default = .sc_run_harmony_function_hash(default),
      options = .sc_run_harmony_function_hash(options_function)),
    signatures = list(generic = names(formals(generic)), seurat = names(formals(seurat)),
      default = names(formals(default)), options = names(formals(options_function))),
    fixed_options = fixed_options, fixed_options_hash = .sc_run_hash(fixed_options),
    api = "harmony::RunHarmony(object=Seurat, reduction.use='pca', project.dim=FALSE, max_iter=...)")
}

.sc_run_harmony_layers <- function(seu, assay) {
  layers <- SeuratObject::Layers(seu[[assay]], search = NA)
  if (anyNA(layers) || anyDuplicated(layers) || !all(c("counts", "data") %in% layers))
    .sc_project_fail("Harmony requires exact public counts/data layers and an unambiguous assay layer inventory.")
  stats::setNames(lapply(layers, function(layer) {
    value <- .sc_project_layer(seu, assay, layer, raw_counts = identical(layer, "counts"))
    list(dim = dim(value), feature_hash = .sc_run_hash(rownames(value)), cell_hash = .sc_run_hash(colnames(value)),
      value_hash = .sc_project_sparse_hash(value))
  }), layers)
}

.sc_run_harmony_invoke <- function(seu, choice, dims, seed, fixed_options = NULL) {
  theta <- if (length(choice$theta) == 1L) rep(choice$theta, length(choice$group_by_vars)) else choice$theta
  if (is.null(fixed_options)) fixed_options <- harmony::harmony_options()
  .sc_run_doublet_rng(seed, function() harmony::RunHarmony(object = seu,
    group.by.vars = choice$group_by_vars, reduction.use = "pca", dims.use = dims,
    reduction.save = "harmony", project.dim = FALSE, theta = theta, lambda = choice$lambda,
    sigma = choice$sigma, max_iter = choice$max_iter, nclust = choice$nclust,
    ncores = 1L, early_stop = TRUE, plot_convergence = FALSE, verbose = FALSE, .options = fixed_options))
}

.sc_run_harmony_neighbors <- function(embedding, cells, k) {
  distances <- as.matrix(stats::dist(embedding[cells, , drop = FALSE], method = "euclidean"))
  diag(distances) <- Inf
  indices <- vapply(seq_along(cells), function(i)
    order(distances[i, ], seq_along(cells), method = "radix")[seq_len(k)], integer(k))
  if (k == 1L) indices <- matrix(indices, nrow = 1L)
  indices
}

.sc_run_harmony_diagnostics <- function(before, after, roles, selected_roles) {
  all_cells <- rownames(before)
  cells <- sort(enc2utf8(all_cells), method = "radix")
  cells <- cells[seq_len(min(length(cells), 512L))]
  k <- min(20L, length(cells) - 1L)
  prior <- .sc_run_harmony_neighbors(before, cells, k)
  next_neighbors <- .sc_run_harmony_neighbors(after, cells, k)
  lookup <- match(cells, all_cells)
  fraction <- function(neighbors, values, same) {
    means <- vapply(seq_along(cells), function(i) mean(if (same)
      values[neighbors[, i]] == values[i] else values[neighbors[, i]] != values[i]), numeric(1))
    list(mean = mean(means), median = stats::median(means), measured_cells = length(means))
  }
  diagnostic <- function(role, same) {
    values <- roles[[role]]
    if (!.sc_run_harmony_complete_values(values, length(all_cells)))
      return(list(role = role, measured = FALSE, before = NULL, after = NULL, delta_mean = NULL,
        reason = "Declared label values are unavailable on the exact diagnostic scope."))
    values <- as.character(values)[lookup]
    one <- fraction(prior, values, same); two <- fraction(next_neighbors, values, same)
    list(role = role, measured = TRUE, levels_in_subset = length(unique(values)),
      before = one, after = two, delta_mean = two$mean - one$mean)
  }
  shift <- sqrt(rowSums((before[cells, , drop = FALSE] - after[cells, , drop = FALSE])^2))
  list(schema = "scagentkit.harmony.embedding-diagnostics.v1", metric = "Euclidean neighbors in selected raw PCA/Harmony coordinates; no additional scaling",
    subset = list(method = "First up to 512 literal cell IDs in UTF-8 radix order", cells = length(cells),
      full_cells = length(all_cells), k = k, cell_hash = .sc_run_hash(cells),
      limitation = "A bounded deterministic subset can be unrepresentative; these diagnostics do not establish whole-dataset preservation."),
    technical_mixing = lapply(selected_roles, diagnostic, same = FALSE),
    biological_same_label = lapply(intersect(c("group", "condition", "treatment"), names(roles)), diagnostic, same = TRUE),
    embedding_shift = list(mean_l2 = mean(shift), median_l2 = stats::median(shift), max_l2 = max(shift)),
    interpretation = c("Technical mixing measures neighbors with different selected-factor labels.",
      "Biological same-label measures neighbors sharing declared biological labels, not marker-defined cell identities or truth.",
      "Before/after fractions are descriptive and separate. Higher mixing does not prove preserved biology or correct integration.",
      "No diagnostic automatically selects parameters, changes the approved strategy, or drops samples."))
}

.sc_run_strategy_batch <- function(seu, config, plan) {
  settings <- .sc_run_strategy_runtime_settings(plan)
  .sc_run_strategy_runtime_dependencies(c("Seurat", "SeuratObject", "Matrix"))
  .sc_run_strategy_runtime_object(seu, config)
  cells <- colnames(seu); metadata <- seu[[]]
  choice <- .sc_run_harmony_parameters(settings$batch, length(cells))
  if (choice$method == "manual") .sc_project_fail("Manual batch handling remains an analyst boundary; no automatic correction was executed.")
  pca <- .sc_run_strategy_pca_evidence(seu, settings)
  if (choice$method == "none")
    return(.sc_run_strategy_record(seu, "batch", list(choice = choice, pca = pca,
      reduction = "pca", cell_ids = cells, corrected = FALSE,
      notice = "Explicit reviewed no-correction choice; Harmony was not invoked.")))
  columns <- config$context$columns
  roles <- lapply(columns, function(column) {
    if (sum(names(metadata) == column) != 1L) return(NULL)
    metadata[cells, column]
  })
  evidence <- list(summary = list(declared_roles = columns,
    background_facts = list(columns = columns, design = config$context$design)))
  checked <- .sc_run_harmony_choice(choice, evidence, roles, processed = identical(config$start_stage, "processed"))
  if (!checked$executable) .sc_project_fail(paste0("Harmony is blocked at the reviewed design boundary: ",
    paste(vapply(checked$blockers, `[[`, character(1), "message"), collapse = " ")))
  if ("harmony" %in% names(seu@reductions))
    .sc_project_fail("The protected source already contains a harmony reduction; use a fresh raw-analysis basis checkpoint rather than overwriting it.")
  source <- .sc_run_harmony_source()
  layers <- .sc_run_harmony_layers(seu, config$assay)
  pca_hash <- .sc_run_hash(seu[["pca"]])
  original_reductions <- names(seu@reductions)
  original_reduction_hashes <- lapply(original_reductions, function(name) .sc_run_hash(seu[[name]]))
  names(original_reduction_hashes) <- original_reductions
  before <- SeuratObject::Embeddings(seu[["pca"]])[, seq_len(pca$ndim), drop = FALSE]
  warnings <- character(); messages <- character()
  result <- withCallingHandlers(.sc_run_harmony_invoke(seu, choice, seq_len(pca$ndim), settings$analysis$seed, source$fixed_options),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") },
    message = function(m) { messages <<- c(messages, conditionMessage(m)); invokeRestart("muffleMessage") })
  if (!inherits(result, "Seurat") || !identical(colnames(result), cells) ||
      !identical(result[[]], metadata) || !identical(.sc_run_harmony_layers(result, config$assay), layers) ||
      !identical(.sc_run_hash(result[["pca"]]), pca_hash) ||
      !all(original_reductions %in% names(result@reductions)) ||
      !identical(lapply(original_reductions, function(name) .sc_run_hash(result[[name]])), unname(original_reduction_hashes)))
    .sc_project_fail("Harmony changed protected raw/normalized assay layers, original reductions, PCA, metadata or literal cell IDs; no output was returned.")
  if (!"harmony" %in% names(result@reductions)) .sc_project_fail("Harmony did not return the explicitly requested derived reduction.")
  after <- SeuratObject::Embeddings(result[["harmony"]])
  if (!identical(rownames(after), cells) || ncol(after) != pca$ndim || any(!is.finite(after)))
    .sc_project_fail("Harmony output must contain exactly the approved finite dimensions and original literal cell order.")
  if (!identical(.sc_run_harmony_source(), source))
    .sc_project_fail("Harmony dependency versions or canonical public function signatures/bodies changed during execution.")
  diagnostics <- .sc_run_harmony_diagnostics(before, after, roles, checked$applicability$selected_roles)
  .sc_run_strategy_record(result, "batch", list(choice = choice, pca = pca, reduction = "harmony",
    corrected = TRUE, cell_ids = cells, cell_hash = .sc_run_hash(cells), source = source,
    source_hash = .sc_run_hash(source), layers_before = layers, layers_after = .sc_run_harmony_layers(result, config$assay),
    pca_hash = pca_hash, harmony_hash = .sc_run_hash(result[["harmony"]]),
    metadata_hash = .sc_run_hash(metadata), design = checked$audit,
    effective_parameters = list(theta = if (length(choice$theta) == 1L) rep(choice$theta, length(choice$group_by_vars)) else choice$theta,
      lambda = choice$lambda, sigma = choice$sigma, max_iter = choice$max_iter, nclust = choice$nclust,
      ncores = 1L, early_stop = TRUE, project_dim = FALSE, seed = settings$analysis$seed,
      reduction_use = "pca", dims_use = seq_len(pca$ndim), reduction_save = "harmony",
      options = source$fixed_options, options_hash = source$fixed_options_hash),
    diagnostics = diagnostics, warnings = unique(warnings), messages = unique(messages),
    primitives = c("harmony::RunHarmony", "SeuratObject::Layers", "SeuratObject::LayerData", "SeuratObject::Embeddings"),
    limitation = "Embedding correction and neighborhood summaries do not establish biological preservation, remove technical confounding, or certify annotations."))
}

.sc_run_harmony_plot <- function(record, path) {
  .sc_project_string(path, "Harmony diagnostic plot path")
  .sc_run_strategy_runtime_dependencies("ggplot2")
  if (!is.list(record) || !is.list(record$choice)) .sc_project_fail("Harmony diagnostic plot requires an intact batch execution record.")
  rows <- list()
  diagnostics <- record$diagnostics
  if (is.list(diagnostics)) for (kind in c("technical_mixing", "biological_same_label")) {
    for (row in diagnostics[[kind]]) if (isTRUE(row$measured)) {
      for (stage in c("before", "after")) rows[[length(rows) + 1L]] <- data.frame(
        metric = if (kind == "technical_mixing") "Technical: different-label neighbors" else "Biological: same-label neighbors",
        role = row$role, stage = stage, fraction = row[[stage]]$mean, stringsAsFactors = FALSE)
    }
  }
  if (length(rows)) {
    data <- do.call(rbind, rows)
    data$stage <- factor(data$stage, levels = c("before", "after"))
    .data <- NULL
    plot <- ggplot2::ggplot(data, ggplot2::aes(x = .data$role, y = .data$fraction, fill = .data$stage)) +
      ggplot2::geom_col(position = "dodge") + ggplot2::facet_wrap(~metric, ncol = 1L, scales = "free_x") +
      ggplot2::coord_cartesian(ylim = c(0, 1)) + ggplot2::theme_bw() +
      ggplot2::labs(x = "Declared metadata role", y = "Mean neighbor fraction", fill = "Embedding",
        title = "Local PCA / Harmony diagnostics", subtitle = "Separate descriptive measures; neither is proof of biological preservation",
        caption = "Up to 512 literal cells, Euclidean coordinates, k up to 20; subset may be unrepresentative. No parameter selection is performed.")
  } else {
    plot <- ggplot2::ggplot() + ggplot2::annotate("text", x = 0, y = 0,
      label = "No Harmony correction requested; no before/after diagnostic is available.") + ggplot2::theme_void()
  }
  ggplot2::ggsave(filename = path, plot = plot, width = 8, height = 6, units = "in", dpi = 120)
  invisible(path)
}
