#' Start a server-side, resumable single-cell analysis
#'
#' The first call diagnoses input and obtains a typed QC proposal, then returns
#' at review. It does not execute provider-generated R. Checkpoints, approvals,
#' aggregate request previews and the local annotation bundle stay in project_dir.
#' @param input Named raw counts matrix, Seurat object, or local RDS path.
#' @param project_dir New server-side project directory.
#' @param context Named list with species, tissue, columns and notes.
#' @param provider Provider configuration list, provider name, or NULL.
#' @param chat_fn Explicit provider function, retained only in caller memory.
#' @param budget Maximum reserved USD for this project. Default zero.
#' @param review Review policy; allow_external permits proposing an external
#'   transfer for exact-payload approval; preapprove_qc is an explicit typed rule.
#' @param start_stage 'qc' for raw counts or 'processed' to reuse analysis.
#' @param processed_reason Required provenance for skipping QC and analysis.
#' @param assay,counts_layer,normalized_layer,cluster_column Explicit source layers and membership.
#' @param analysis Named settings passed to sc_project_prepare.
#' @param reference Optional supplied local annotation reference.
#' @param annotation_column New annotation column; choose a fresh name to preserve existing labels.
#' @param qc_proposal,annotation_proposal Optional typed manual proposals.
#' @param qc_preview Named list with optional explicit sensitivity candidates and
#'   gene_panels for local availability disclosure. These do not change QC rules.
#' @param reference_review Explicit aliases, label mapping/relationships, candidate
#'   count and independent/guided reference mode for local evidence review.
#' @param annotation_history Explicit historical model rows and readonly response/
#'   source paths. Importing them never dispatches a model request.
#' @param strategy Enable one background-driven typed QC/analysis strategy review.
#' @param strategy_proposal Optional complete typed strategy; also enables strategy.
#'   User facts and proposed inferences are distinct. Only supported local methods
#'   run; manual batch handling stops durably, and annotation is reviewed later.
#' @param cycle_diagnostics Optional explicit gene set and scoring settings for
#'   nonfiltering full-input cycle evidence inside the central strategy review.
#'   Regression defaults to none and requires an exact approved cycle method.
#' @param doublet_diagnostics Optional explicit capture/loading-unit, input and
#'   expected-rate provenance for fixed full-input scDblFinder diagnostics.
#'   Cells are retained by default; typed removal needs the exact strategy review.
#' @param qc_mad Optional explicit QC grouping and finite deterministic MAD panel.
#'   A nested prefilter may declare an explicitly preapproved minimum-count rule;
#'   default prefilter and quality preset retain all cells.
#' @param subcluster_origin,subcluster_creation,.subcluster_lock_owner Internal immutable scope and
#'   creation receipts supplied by sc_run_subcluster, not analysis settings.
#' @return Durable run status. Use sc_run_inspect, sc_run_approve and sc_run_resume.
#' @export
sc_run <- function(input, project_dir, context = list(), provider = NULL, chat_fn = NULL,
                   budget = 0, review = list(), start_stage = c("qc", "processed"),
                   processed_reason = NULL, assay = "RNA", counts_layer = "counts",
                   normalized_layer = "data", cluster_column = "seurat_clusters",
                   analysis = list(), reference = NULL, annotation_column = "sc_annotation", qc_proposal = NULL,
                   annotation_proposal = NULL, qc_preview = list(),
                   reference_review = list(), annotation_history = NULL,
                   strategy = FALSE, strategy_proposal = NULL, cycle_diagnostics = NULL,
                   doublet_diagnostics = NULL, qc_mad = NULL,
                   subcluster_origin = NULL, subcluster_creation = NULL,
                   .subcluster_lock_owner = NULL) {
  start_stage <- match.arg(start_stage)
  if (!identical(strategy, TRUE) && !identical(strategy, FALSE)) stop("strategy must be TRUE or FALSE.", call. = FALSE)
  if (!is.null(strategy_proposal)) strategy <- TRUE
  if (!is.null(cycle_diagnostics) && !identical(cycle_diagnostics, FALSE) && !strategy)
    stop("Enable strategy=TRUE to review cycle diagnostics and any explicit regression centrally.", call. = FALSE)
  if (!is.null(doublet_diagnostics) && !identical(doublet_diagnostics, FALSE) && !strategy)
    stop("Enable strategy=TRUE to review doublet scores and any exact cell removal centrally.", call. = FALSE)
  mad_enabled <- !is.null(qc_mad) && !identical(qc_mad, FALSE)
  if (mad_enabled && (!strategy || start_stage != "qc"))
    stop("qc_mad requires raw strategy entry; processed analysis and legacy range QC are separate supported paths.", call. = FALSE)
  if (mad_enabled && (!is.list(qc_mad) || is.null(names(qc_mad)) ||
      anyNA(names(qc_mad)) || any(!nzchar(names(qc_mad))) || anyDuplicated(names(qc_mad))))
    stop("qc_mad requires an explicit named configuration, not TRUE.", call. = FALSE)
  if (strategy && (length(analysis) || !is.null(qc_proposal)))
    stop("Strategy mode owns QC and analysis together; use the complete strategy_proposal instead of competing analysis/qc_proposal arguments.", call. = FALSE)
  if (!is.null(subcluster_origin)) {
    .sc_run_subcluster_origin_verify(subcluster_origin)
    .sc_run_subcluster_check_parent(subcluster_origin)
    inherited_model <- isTRUE(subcluster_creation$model_policy$inherit_model)
    if (!strategy || start_stage != "qc" || !is.null(chat_fn) ||
        !is.numeric(budget) || length(budget) != 1L || !is.finite(budget) ||
        (!inherited_model && (!is.null(provider) || budget != 0 || isTRUE(review$allow_external))) ||
        !is.null(review$preapprove_qc) ||
        !is.null(doublet_diagnostics) || mad_enabled || !is.null(annotation_history))
      stop("Scoped children require raw typed strategy, explicit creation-time model inheritance or budget=0/no provider/external transfer, no preapproval, doublet refit, MAD/prefilter or parent annotation history.", call. = FALSE)
    if (!is.list(subcluster_creation) ||
        !identical(subcluster_creation$schema, "scagentkit.subcluster-creation.v1"))
      stop("Scoped child creation receipt is required.", call. = FALSE)
    .sc_run_subcluster_request_id(subcluster_creation$request_id)
    .sc_run_review_hash_string(subcluster_creation$request_hash, "subcluster creation request_hash")
    .sc_run_subcluster_choices(subcluster_creation$choices)
    if (inherited_model && (!identical(.sc_run_provider_spec(provider)$metadata, subcluster_creation$model_policy$provider) ||
        !identical(as.numeric(budget), as.numeric(subcluster_creation$model_policy$budget)) ||
        !identical(isTRUE(review$allow_external), subcluster_creation$model_policy$allow_external)))
      stop("Child provider, budget or transfer policy differ from its immutable creation receipt.", call. = FALSE)
  } else if (!is.null(subcluster_creation))
    stop("subcluster_creation requires its immutable subcluster_origin.", call. = FALSE)
  if (!is.null(.subcluster_lock_owner) && is.null(subcluster_origin))
    stop("An initialization lock is supported only for scoped child creation.", call. = FALSE)
  if (strategy && start_stage == "qc" && missing(cluster_column)) cluster_column <- "sc_strategy_clusters"
  if (!is.numeric(budget) || length(budget) != 1L || !is.finite(budget) || budget < 0) stop("budget must be nonnegative USD.", call. = FALSE)
  allowed_review <- c("allow_external", "preapprove_qc")
  if (!is.list(review) || any(!names(review) %in% allowed_review)) stop("Unsupported review policy.", call. = FALSE)
  if (!is.null(review$allow_external) && !identical(review$allow_external, TRUE) && !identical(review$allow_external, FALSE)) stop("allow_external must be logical.", call. = FALSE)
  qc_preview <- .sc_run_qc_preview_options(qc_preview)
  reference_review <- .sc_run_reference_options(reference_review)
  root <- .sc_run_root(project_dir, create = TRUE)
  if (is.null(.subcluster_lock_owner)) {
    owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  } else .sc_run_subcluster_lock_verify(root, .subcluster_lock_owner)
  if (file.exists(file.path(root, "state.rds"))) stop("Run already exists; use sc_run_resume or choose a new project_dir.", call. = FALSE)
  checked <- .sc_run_input(input, context, assay, counts_layer, start_stage, processed_reason,
                           cluster_column = cluster_column, normalized_layer = normalized_layer)
  if (!is.null(subcluster_origin) && !identical(colnames(checked$seu), subcluster_origin$selected_cells))
    stop("Scoped child raw input must have the exact frozen parent selection in literal cell order.", call. = FALSE)
  .sc_run_annotation_target(checked$seu, annotation_column, cluster_column)
  spec <- .sc_run_provider_spec(provider, chat_fn)
  config <- list(context = checked$context, assay = assay, counts_layer = counts_layer,
                 normalized_layer = normalized_layer, cluster_column = cluster_column,
                 analysis = analysis, markers = list(), annotation_column = annotation_column,
                 budget = budget, review = review, provider = spec$metadata, start_stage = start_stage,
                 processed_reason = processed_reason, qc_preview = qc_preview,
                 reference_review = reference_review)
  if (strategy) config$strategy <- TRUE
  if (!is.null(subcluster_origin)) {
    config$subcluster_origin <- subcluster_origin
    config$subcluster_creation <- subcluster_creation
    config$annotation_context <- .sc_run_child_context_initial(subcluster_creation$parent_annotation_context)
  }
  cycle_options <- .sc_run_cycle_options(checked$context, cycle_diagnostics)
  if (!is.null(cycle_options)) config$cycle_diagnostics <- cycle_options
  doublet_options <- .sc_run_doublet_options(checked$context, doublet_diagnostics)
  if (!is.null(doublet_options)) config$doublet_diagnostics <- doublet_options
  if (mad_enabled) {
    config$prefilter <- .sc_run_prefilter_options(qc_mad$prefilter)
    config$qc_mad <- .sc_run_mad_options(checked$context, qc_mad[setdiff(names(qc_mad), "prefilter")])
    if (length(qc_preview$sensitivity))
      stop("qc_mad uses its saved finite candidate panel; custom legacy sensitivity ranges cannot compete with it.", call. = FALSE)
  }
  .sc_project_json_check(config)
  state <- list(project_id = paste0("run-", substr(.sc_run_hash(list(root, Sys.time())), 1, 16)),
                status = "ready", stage = "qc_evidence", revision = 0L, history = list(),
                config = config, config_hash = .sc_run_hash(config), implementation_hash = .sc_run_implementation(),
                source = checked$source, diagnostics = checked$diagnostics, files = list(),
                approvals = list(), transfer_hashes = character(), pending = NULL, approved = NULL,
                completed = character(), nodes = list(qc_evidence = "PLANNED"), failure = NULL, output = NULL)
  state <- .sc_run_put(root, state, "input", checked$seu)
  state$input_hash <- state$files$input$sha256
  if (!is.null(subcluster_origin)) {
    state <- .sc_run_put(root, state, "subcluster_origin", subcluster_origin)
    state <- .sc_run_put(root, state, "subcluster_creation", subcluster_creation)
    state <- .sc_run_put(root, state, "child_annotation_context", config$annotation_context)
    state <- .sc_run_event(state, "subcluster_created", list(
      parent_project_id = subcluster_origin$parent$project_id,
      parent_scope_hash = subcluster_origin$parent_scope_hash,
      selected_scope_hash = subcluster_origin$scope_hash,
      creation_request_id = subcluster_creation$request_id,
      creation_request_hash = subcluster_creation$request_hash,
      choices = subcluster_creation$choices, selected_cells = length(subcluster_origin$selected_cells),
      plan_source = subcluster_creation$plan_source,
      boundary = "Fresh raw-count input; parent embeddings and cluster results are not reused. Whole child strategy requires exact approval."))
  }
  if (!is.null(reference)) state <- .sc_run_put(root, state, "reference", reference)
  if (!is.null(annotation_history)) state <- .sc_run_put(root, state, "annotation_history_input", annotation_history)
  if (!is.null(qc_proposal)) state <- .sc_run_put(root, state, "manual_qc", qc_proposal)
  if (!is.null(strategy_proposal)) state <- .sc_run_put(root, state, "manual_strategy", strategy_proposal)
  if (!is.null(annotation_proposal)) state <- .sc_run_put(root, state, "manual_annotation", annotation_proposal)
  state <- .sc_run_event(state, "planned", list(input_hash = state$input_hash, config_hash = state$config_hash,
                                              implementation_hash = state$implementation_hash))
  if (start_stage == "processed") {
    state$stage <- "markers"; state <- .sc_run_put(root, state, "analysis", checked$seu)
    state$completed <- c("qc_evidence", "qc_propose", "qc_apply", "analysis")
    state <- .sc_run_event(state, "processed_stage_reused", list(reason = processed_reason, source = checked$source,
                                                                skipped = state$completed))
  }
  if (strategy) {
    state$stage <- if (mad_enabled) "prefilter" else "strategy_evidence"
    state$nodes[[state$stage]] <- "PLANNED"
  }
  .sc_run_save(root, state)
  if (!is.null(subcluster_origin))
    return(.sc_run_drive(root, state, provider = NULL, chat_fn = NULL, retry = FALSE, local_only = TRUE))
  .sc_run_drive(root, state, provider, chat_fn, retry = FALSE)
}

.sc_run_implementation <- function() {
  ns <- environment(.sc_run_drive)
  selected <- sort(grep("^(sc_run|\\.sc_run_)", ls(ns, all.names = TRUE), value = TRUE))
  selected <- unique(c(selected, "sc_project_prepare", ".sc_project_layer", ".sc_project_identity", "sc_select_pcs", ".adjusted_rand_index", "sc_cycle_gene_set"))
  code <- lapply(selected, function(name) {
    fn <- get(name, envir = ns)
    list(name = name, formals = paste(deparse(formals(fn), width.cutoff = 500L), collapse = "\n"),
         body = paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n"))
  })
  # Optional diagnostic dependencies are fingerprinted in their immutable
  # evidence. Installing a missing scorer before evidence generation must not
  # invalidate a stopped project; completed fixed scores are reused, not refit.
  .sc_run_hash(list(code = code, versions = lapply(c("Seurat", "SeuratObject", "agentomicsCore", "Matrix", "irlba", "RcppAnnoy", "uwot"),
    function(p) if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else "unavailable")))
}

.sc_run_crash <- function(point) {
  if (identical(getOption("scAgentKit.run_crash"), point)) stop(paste0("Injected crash at ", point), call. = FALSE)
}
.sc_run_checkpoint <- function(root, state, stage, next_stage) {
  .sc_run_crash(paste0(stage, ":artifact"))
  # Artifacts are complete and checksummed before state references become visible.
  for (record in state$files) if (!identical(record$sha256, .sc_project_sha_file(file.path(root, record$path)))) stop("Artifact verification failed.", call. = FALSE)
  state$completed <- unique(c(state$completed, stage)); state$nodes[[stage]] <- "EXECUTED"
  if (next_stage != "complete") state$nodes[[next_stage]] <- "PLANNED"
  state$stage <- next_stage; state$status <- if (next_stage == "complete") "complete" else "ready"; state$failure <- NULL
  state <- .sc_run_event(state, "executed", list(stage = stage, files = state$files))
  .sc_run_save(root, state)
  .sc_run_crash(paste0(stage, ":checkpoint"))
  state
}

#' Resume a saved run in a new R process
#' @param project_dir Server-side project directory.
#' @param provider,chat_fn Provider configuration/function for new requests only.
#' @param retry Explicitly retry a failed computation; uncertain external requests
#'   remain held and require provider reconciliation rather than automatic replay.
#' @return Updated durable status.
#' @export
sc_run_resume <- function(project_dir, provider = NULL, chat_fn = NULL, retry = FALSE) {
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) || !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed. Existing approvals are stale; start a new project.", call. = FALSE)
  state <- .sc_run_cleanup(root, state)
  if (state$status == "complete" || state$status %in% c("awaiting_review", "rejected")) return(.sc_run_public(state))
  if (state$stage == "strategy_apply" && !isTRUE(.sc_run_get(root, state, "strategy_validated")$executable))
    return(.sc_run_public(.sc_run_strategy_manual_boundary(root, state)))
  if (state$status %in% c("failed", "running") && !isTRUE(retry)) return(.sc_run_public(state))
  if (is.null(provider)) provider <- state$config$provider
  if (!identical(.sc_run_provider_spec(provider, chat_fn)$metadata, state$config$provider)) stop("Provider/model/settings changed; start a new project or restore the approved provider configuration.", call. = FALSE)
  if (state$status %in% c("failed", "running")) {
    state <- .sc_run_event(state, "retry_requested", list(stage = state$stage))
    state$status <- "ready"; state$failure <- NULL; .sc_run_save(root, state)
  }
  .sc_run_drive(root, state, provider, chat_fn, retry)
}
.sc_run_request <- function(kind, evidence, config) {
  schema <- if (kind == "strategy") {
    paste("Return one JSON object with exactly schema='scagentkit.strategy.v1', rationale, risks (array), inferences (array), qc, analysis, pcs, batch, clustering, umap.",
      "User facts, missing facts and measured quantities are distinct. Put any model inference only in inferences; do not invent metadata, sample identities, design or goals.",
      if (is.null(config$qc_mad))
        "For raw entry qc may use legacy scagentkit.qc.v1 with filters, or scagentkit.qc.rules.v1 with exactly schema, rationale, risks (array), remove_if ('any' or 'all') and rules (1 to 32 operations). Derive concrete inclusive bounds from actual quality quantiles and disclose uncertainty. MAD operations are unavailable unless explicitly enabled." else
        "For raw entry qc may use scagentkit.qc.mad.v1 with exactly schema, rationale, risks (array), preset_id and panel_hash copied from the supplied deterministic MAD panel, or scagentkit.qc.rules.v1 with exactly schema, rationale, risks (array), remove_if ('any' or 'all') and rules (1 to 32 operations). A rules combination may include at most one mad_preset operation with the exact saved preset_id and panel_hash, plus measured range operations. Choose only available saved MAD predicates; do not invent multipliers, grouping or scores. Prefilter exclusions remain excluded independently of the chosen rule combination.",
      "Range operations contain op='range', metric='nCount'|'nFeature'|'percent_mt', optional inclusive min/max and optional group containing only literal sample and/or capture present in evidence. Count/feature bounds are nonnegative integers; percent bounds are between 0 and 100. For qc.rules.v1 remove_if='any' removes cells failing any rule; remove_if='all' removes cells failing every rule. A rule scoped to a different group does not fail that cell. Unsupported or unavailable measurements and a final empty retained set are rejected. No code, genes, invented groups or unsupported operations.",
      "analysis has normalization_method='LogNormalize', scale_factor, nfeatures, npcs, seed. pcs has method='fixed',ndim OR method='computed_variance',threshold (any value strictly between 0 and 1, measured against all actually computed PCs) OR method='computed_top50',threshold (.80 or .85 only, measured against first min(50,actually computed PCs)). A threshold of .80 is an editable reference, not an established optimum. Saved candidates are unavailable before approved PCA. Computed-PC variance is not total expression variance.",
      "batch defaults to method='none',reason; manual is a blocked analyst boundary. Explicit harmony requires exactly method,group_by_vars,theta,lambda,sigma,max_iter,nclust,reason. It requires declared technical provenance, crossed identifiable biological roles and explicit batch/sample/donor column names. Never infer a correction covariate from condition, treatment or capture; fully confounded designs cannot establish preservation of treatment signals. Harmony changes embedding only. Subcluster actions remain unsupported.",
      "clustering has resolution in (0,2] and optional diagnostic_resolutions (at most five). umap has run (boolean) and n_neighbors.",
      "At least 21 projected cells are required; npcs is strictly below requested HVGs/cells, fixed ndim<=npcs, UMAP neighbors<cells. Do not silently clip impossible choices.",
      "For processed entry qc, analysis, pcs, clustering and umap must all be null, explicitly reusing the provided processed analysis.",
      "No R code, arbitrary regressors, automatic biological batch choice or deletion of cycling/doublet cells. A proposal is a reviewable policy, not a claim of scientific optimality.")
  } else if (kind == "qc") {
    "Return only JSON: {\"schema\":\"scagentkit.qc.v1\",\"rationale\":\"...\",\"risks\":[\"...\"],\"filters\":[{\"op\":\"range\",\"metric\":\"nFeature\",\"min\":0,\"max\":5000,\"group\":null}]}. Supported metrics: nCount,nFeature,percent_mt. Optional group only literal sample and/or capture in evidence. Thresholds must follow actual quantiles and context; no arbitrary code, batch selection or unsupported actions. Acknowledge uncertainty; no fixed universal threshold."
  } else {
    "Return only complete JSON: {\"schema\":\"scagentkit.annotation.v1\",\"annotations\":[{\"clusterId\":\"literal ID\",\"label\":\"Unknown or type\",\"confidence\":\"low|medium|high\",\"rationale\":\"one short sentence\",\"markers\":[\"GENE\"]}]}. Include every supplied cluster exactly once, including uncertain clusters. Keep label at most 80 characters and rationale at most 240 characters. Cite at most 5 strongest marker genes actually supplied for that cluster; do not repeat the whole marker table. Use Unknown with low confidence when uncertain; its markers may be empty. Close every string, array and object. These are independent suggestions for human review, not automatic scientific acceptance."
  }
  if (kind == "strategy" && !is.null(config$cycle_diagnostics)) {
    schema <- sub("clustering, umap.", "clustering, umap, and optional cycle.", schema, fixed = TRUE)
    schema <- sub("Harmony, cycle, doublet and subcluster actions are unsupported.",
      "Harmony, doublet, subcluster and cycling-cell deletion remain unsupported.", schema, fixed = TRUE)
    schema <- paste(schema,
      "This explicitly enabled strategy also supports cycle={method:'none'|'full'|'difference',reason:'...'}; omission defaults to none.",
      "Use saved fixed-full-input score evidence and projected applicability. No inferred research goal is authorization to regress. Default to none when evidence is insufficient or preservation is uncertain; a whole exact human approval is required for full/difference.",
      "full regresses quantitative S/G2M scores; difference regresses S.Score-G2M.Score to reduce phase contrast while retaining cycling/noncycling signal. Neither deletes cells. Processed reuse supports only none.")
  }
  if (kind == "strategy" && !is.null(config$doublet_diagnostics)) {
    schema <- sub("Harmony, cycle, doublet and subcluster actions are unsupported.",
      "Harmony, cycle, subcluster and cycling-cell deletion remain unsupported.", schema, fixed = TRUE)
    schema <- sub("Harmony, doublet, subcluster and cycling-cell deletion remain unsupported.",
      "Harmony, subcluster and cycling-cell deletion remain unsupported.", schema, fixed = TRUE)
    schema <- sub("No R code, arbitrary regressors, automatic biological batch choice or deletion of cycling/doublet cells.",
      "No R code, arbitrary regressors, automatic biological batch choice or cycling-cell deletion.", schema, fixed = TRUE)
    schema <- paste(schema,
      "This explicitly enabled strategy supports doublet={method:'keep'|'remove_predicted',reason:'...'}; omission defaults to keep. Other doublet operations are unsupported.",
      if (is.null(config$qc_mad))
        "Use saved fixed-full-input capture-specific scDblFinder aggregates. Scores are classifier outputs, not calibrated probabilities; classes are predictions, not truth, and homotypic doublets can be missed." else
        "Use the saved capture-specific scoring cohort after the explicit minimal prefilter, before later quality filtering. Excluded cells are unscored Unknown. Expected-rate provenance remains the original full called-cell capture; predictions are not calibrated probabilities or biological truth.",
      "No inferred sample, donor or condition is a capture. Only the declared loading units and expected-rate provenance are valid. No free score cutoff or automatic deletion is authorized. remove_predicted requires exact joint QC/cell-scope human approval; processed entry supports keep only.")
  }
  if (kind == "strategy" && !is.null(config$qc_mad)) schema <- paste(schema,
    "The immutable prefilter has already been explicitly declared; capture scoring precedes these later quality filters. Original cohort, prefilter eligibility, actual scoring and projected post-QC counts are separate facts.",
    "QC grouping is independently declared from capture/sample/donor; use the supplied grouping provenance only. Counts/features use log10(x+1), median and 1.4826-scaled MAD; mitochondrial upper tails use original percentages.",
    "Available presets are keep_all, conservative_and3, low_counts3, low_features3, high_mt3 and any_quality3. keep_all is the low-risk default. AND/OR and single-indicator candidates have different measured consequences; no candidate is a universal optimum.",
    "MAD zero/near-zero, small groups, missing values and mixed distributions can make candidates unavailable. Explain uncertainties; do not treat Unknown as zero or optimize against retained cell number or cluster labels.",
    "High RNA is flag-only; ribosomal/hemoglobin percentages are diagnostic only. Only one complete human-approved strategy authorizes exact preset execution; no background rule switching or per-group approvals.")
  schema <- sub("These are independent suggestions", "These are suggestions", schema, fixed = TRUE)
  dependency <- if (kind != "annotation") "" else if (identical(evidence$reference_mode, "guided"))
    "Database candidates were supplied as guidance. This suggestion depends on that reference; agreement is not independent replication." else
    "Database candidates are excluded from this evidence branch. Label agreement still does not establish biological correctness."
  if (kind == "annotation" && !is.null(evidence$child_context)) dependency <- paste(dependency,
    "child_context records frozen parent annotations and optional analyst-corrected hypotheses. Parent approved labels, Unknown, mixed and unreviewed statuses are provenance, never child ground truth or a label whitelist.",
    "parent_snapshot.source.source_kind discloses the saved parent annotation origin (manual/model/mock/provider response/unknown); approval does not turn a parent model label into independent evidence or biological truth.",
    "Use enabled resolved hints only as soft context; current supplied expression/marker evidence may override them, including a different lineage. Explain discrepancies for human review rather than forcing a parent label. Disabled hints are provenance only.",
    "Absence from the supplied top-marker list (including a top-30 list) is not absent or low expression. Do not invent negative expression or cross-lineage facts; cross-lineage warnings require explicit lineage declarations.",
    "Local database scoring/ranking is expression-marker coverage only and is not reranked or restricted by parent labels. Agreement between branches sharing parent context is not independent biological replication.")
  payload_evidence <- evidence
  if (kind == "strategy" && !is.null(payload_evidence$cycle_diagnostics)) {
    # Local review retains the declared lists/mapping; a remote suggestion only
    # needs aggregate coverage, scores and provenance, never the input symbols.
    for (name in c("s_genes", "g2m_genes", "canonical_s_genes", "canonical_g2m_genes", "symbol_mapping"))
      payload_evidence$cycle_diagnostics$gene_set[[name]] <- NULL
  }
  list(system_prompt = paste("You assist a single-cell analyst using only supplied aggregate evidence.", schema, dependency),
       user_prompt = .sc_project_json(list(context = if (kind == "annotation" && !is.null(evidence$child_context)) evidence$context else config$context, evidence = payload_evidence)),
       purpose = kind, evidence_hash = .sc_run_hash(evidence))
}
.sc_run_get_proposal <- function(root, state, kind, evidence, provider, chat_fn, retry, local_only = FALSE) {
  manual <- paste0("manual_", kind)
  if (!is.null(state$files[[manual]])) {
    state$diagnostics$local_continue_boundary <- NULL
    return(list(state = state, proposal = .sc_run_get(root, state, manual)))
  }
  if (isTRUE(local_only)) return(list(state = .sc_run_continue_boundary(root, state, kind), proposal = NULL))
  state$diagnostics$local_continue_boundary <- NULL
  spec <- .sc_run_provider_spec(provider, chat_fn)
  if (is.null(spec$metadata) || identical(spec$metadata$name, "manual")) {
    state$status <- "awaiting_configuration"
    state <- .sc_run_event(state, "manual_configuration_needed", list(stage = state$stage, kind = kind))
    .sc_run_save(root, state); return(list(state = state, proposal = NULL))
  }
  request <- .sc_run_request(kind, evidence, state$config)
  request_hash <- .sc_run_request_hash(request, provider, chat_fn)
  state <- .sc_run_put(root, state, paste0(kind, "_request"), request)
  external <- isTRUE(spec$metadata$external)
  if (external && !request_hash %in% state$transfer_hashes) {
    if (!isTRUE(state$config$review$allow_external)) {
      state$status <- "awaiting_configuration"
      state <- .sc_run_event(state, "external_transfer_disabled", list(request_hash = request_hash))
    } else {
      state <- .sc_run_pending(state, "external_transfer", list(request_hash = request_hash,
        payload = list(system_prompt = request$system_prompt, user_prompt = request$user_prompt),
        provider = spec$metadata, notice = "Aggregate QC/markers and supplied context leave this machine. Raw matrices, cell IDs and per-cell metadata are excluded; declared aggregate sample/capture labels and supplied context are transmitted."), request$evidence_hash)
    }
    .sc_run_save(root, state); return(list(state = state, proposal = NULL))
  }
  request$approved_payload_hash <- if (external) request_hash else NULL
  local_evidence <- .sc_run_get(root, state, paste0(kind, "_evidence"))
  request$validator <- if (kind == "strategy") function(x) .sc_run_strategy_validate(x, local_evidence)$proposal else if (kind == "qc") function(x) .sc_run_qc_validate(x, local_evidence)$proposal else function(x) { value <- .sc_run_annotation_response_validate(x, local_evidence); list(schema = value$schema, annotations = value$annotations) }
  .sc_run_save(root, state)
  answer <- .sc_run_call(root, request, provider, chat_fn, state$config$budget,
                         allow_external = external, retry = retry)
  if (identical(answer$status, "needs_provider")) {
    state$status <- "awaiting_configuration"; state$nodes[[state$stage]] <- "NEEDS_CONFIGURATION"
    state$diagnostics$provider_configuration_needed <- answer$error
    state <- .sc_run_event(state, "provider_configuration_needed",
      list(kind = kind, request_hash = request_hash, message = answer$error,
           dispatch = "not_sent", retry = "Configure the runtime provider, then explicitly resume."))
    .sc_run_save(root, state); return(list(state = state, proposal = NULL))
  }
  if (!identical(answer$status, "ok")) stop(paste0("Provider request stopped: ", answer$status), call. = FALSE)
  state$diagnostics$provider_configuration_needed <- NULL
  state <- .sc_run_put(root, state, paste0(kind, "_response"), answer)
  state <- .sc_run_event(state, "proposal_received", list(request_hash = request_hash,
                                                        provider = answer$provider, cost = answer$cost_usd))
  list(state = state, proposal = answer$content)
}
.sc_run_drive <- function(root, state, provider, chat_fn, retry, local_only = FALSE) {
  repeat {
    .sc_run_subcluster_guard(root, state)
    if (!is.null(state$config$subcluster_origin) && (!is.null(chat_fn) ||
        (!is.null(provider) && !identical(.sc_run_provider_spec(provider)$metadata$name, "manual"))))
      stop("Scoped child Continue/resume is local and provider-free in this version.", call. = FALSE)
    stage <- state$stage
    if (state$status %in% c("awaiting_review", "rejected", "complete")) return(.sc_run_public(state))
    before <- state
    state$status <- "running"; state$nodes[[stage]] <- "RUNNING"
    state <- .sc_run_event(state, "running", list(stage = stage)); .sc_run_save(root, state)
    result <- tryCatch({
      if (isTRUE(local_only)) .sc_run_continue_crash(paste0(stage, ":before"))
      if (stage == "prefilter") {
        record <- .sc_run_prefilter_evidence(.sc_run_get(root, state, "input"), state$config)
        state <- .sc_run_put(root, state, "prefilter", record)
        state <- .sc_run_event(state, "prefilter_declared", list(
          options = record$options, evidence_hash = record$evidence_hash,
          policy = "Immutable explicit pre-scoring eligibility; default none retains all. A minimum-count removal requires caller preapproval, source and reason.",
          counts = record$summary))
        state <- .sc_run_checkpoint(root, state, stage, "strategy_evidence")
      } else if (stage == "strategy_evidence") {
        seu <- .sc_run_get(root, state, "input")
        prefilter <- if (is.null(state$config$qc_mad)) NULL else .sc_run_get(root, state, "prefilter")
        # Save each local diagnostic independently. A later dependency failure or
        # disconnect must not discard already published input evidence.
        qc <- if (is.null(state$files$qc_evidence))
          .sc_run_qc_evidence(seu, state$config$context, state$config$assay, state$config$counts_layer) else
          .sc_run_get(root, state, "qc_evidence")
        state <- .sc_run_put(root, state, "qc_evidence", qc)
        .sc_run_save(root, state)
        cycle <- if (is.null(state$config$cycle_diagnostics)) NULL else
          if (is.null(state$files$cycle_diagnostics)) .sc_run_cycle_evidence(seu, state$config) else
            .sc_run_get(root, state, "cycle_diagnostics")
        if (!is.null(cycle)) {
          state <- .sc_run_put(root, state, "cycle_diagnostics", cycle)
          .sc_run_save(root, state)
        }
        doublet <- if (is.null(state$config$doublet_diagnostics)) NULL else
          if (is.null(state$files$doublet_diagnostics)) .sc_run_doublet_evidence(seu, state$config, prefilter_record = prefilter) else
            .sc_run_get(root, state, "doublet_diagnostics")
        if (!is.null(doublet)) {
          state <- .sc_run_put(root, state, "doublet_diagnostics", doublet)
          .sc_run_save(root, state)
        }
        mad <- NULL
        if (!is.null(state$config$qc_mad)) {
          mad <- if (is.null(state$files$qc_mad)) .sc_run_mad_evidence(seu, state$config, qc, prefilter_record = prefilter) else
            .sc_run_get(root, state, "qc_mad")
          .sc_run_mad_verify(mad)
          state <- .sc_run_put(root, state, "qc_mad", mad)
          qc$mad_record <- mad; qc$summary$mad <- mad$summary
          qc$evidence_hash <- .sc_run_qc_hash(qc)
          state <- .sc_run_put(root, state, "qc_evidence", qc)
          .sc_run_save(root, state)
        }
        evidence <- .sc_run_strategy_evidence(seu, state$config, qc, cycle_record = cycle,
          doublet_record = doublet, mad_record = mad, prefilter_record = prefilter)
        if (state$config$start_stage == "processed") {
          reused <- .sc_run_get(root, state, "input")
          if (!is.null(cycle)) reused <- .sc_run_cycle_attach(reused, cycle)
          if (!is.null(doublet)) reused <- .sc_run_doublet_attach(reused, doublet)
          state <- .sc_run_put(root, state, "analysis", reused)
        }
        state <- .sc_run_put(root, state, "strategy_evidence", evidence)
        state <- .sc_run_checkpoint(root, state, stage, "strategy_propose")
      } else if (stage == "strategy_propose") {
        evidence <- .sc_run_get(root, state, "strategy_evidence")
        proposed <- .sc_run_get_proposal(root, state, "strategy", evidence$summary, provider, chat_fn, retry, local_only)
        state <- proposed$state
        if (is.null(proposed$proposal)) return(.sc_run_public(state))
        validated <- .sc_run_strategy_validate(proposed$proposal, evidence)
        state <- .sc_run_strategy_review_publish(root, state, validated, evidence)
        state <- .sc_run_strategy_pending(root, state, validated, evidence)
        .sc_run_save(root, state)
      } else if (stage == "strategy_apply") {
        state <- .sc_run_strategy_apply_gate(root, state)
        if (state$status %in% c("awaiting_configuration", "awaiting_review", "rejected")) return(.sc_run_public(state))
      } else if (stage == "strategy_selection") {
        validated <- .sc_run_strategy_require(root, state)
        record <- .sc_run_get(root, state, "doublet_diagnostics")
        seu <- .sc_run_strategy_selection(.sc_run_get(root, state, "qc_object"), state$config, validated, record)
        state <- .sc_run_put(root, state, "strategy_selected", seu)
        state <- .sc_run_checkpoint(root, state, stage, "strategy_preprocess")
      } else if (stage == "strategy_preprocess") {
        plan <- .sc_run_strategy_require(root, state)$proposal
        source <- if (is.null(state$config$doublet_diagnostics)) "qc_object" else "strategy_selected"
        seu <- .sc_run_strategy_preprocess(.sc_run_get(root, state, source), state$config, plan)
        state <- .sc_run_put(root, state, "strategy_preprocess", seu)
        state <- .sc_run_checkpoint(root, state, stage, "strategy_basis")
      } else if (stage == "strategy_basis") {
        validated <- .sc_run_strategy_require(root, state)
        plan <- validated$proposal
        cycle <- if (is.null(state$config$cycle_diagnostics)) NULL else .sc_run_get(root, state, "cycle_diagnostics")
        preprocessed <- !is.null(cycle) || !is.null(state$config$doublet_diagnostics)
        seu <- .sc_run_strategy_basis(.sc_run_get(root, state, if (preprocessed) "strategy_preprocess" else "qc_object"),
          state$config, plan, preprocessed = preprocessed, cycle_record = cycle)
        seu@misc$strategy_execution$basis$dependency_hash <- validated$dependency_hashes$basis
        # A fresh raw foundation cannot inherit execution claims from the
        # supplied object's previous run. Its original object remains intact.
        seu@misc$strategy_execution$batch <- NULL
        state <- .sc_run_put(root, state, "strategy_basis", seu)
        state <- .sc_run_checkpoint(root, state, stage, if (identical(plan$batch$method, "harmony")) "strategy_batch" else "strategy_neighbors")
      } else if (stage == "strategy_batch") {
        validated <- .sc_run_strategy_require(root, state)
        seu <- .sc_run_strategy_batch(.sc_run_get(root, state, "strategy_basis"), state$config, validated$proposal)
        seu@misc$strategy_execution$batch$dependency_hash <- validated$dependency_hashes$batch
        seu@misc$strategy_execution$batch$basis_sha256 <- state$files$strategy_basis$sha256
        state <- .sc_run_put(root, state, "strategy_batch", seu)
        state <- .sc_run_checkpoint(root, state, stage, "strategy_neighbors")
      } else if (stage == "strategy_neighbors") {
        validated <- .sc_run_strategy_require(root, state)
        plan <- validated$proposal
        source <- if (identical(plan$batch$method, "harmony")) "strategy_batch" else "strategy_basis"
        seu <- .sc_run_get(root, state, source)
        if (identical(source, "strategy_batch") &&
            !identical(seu@misc$strategy_execution$batch$dependency_hash, validated$dependency_hashes$batch))
          stop("Harmony checkpoint dependency changed; its approval is stale.", call. = FALSE)
        seu <- .sc_run_strategy_neighbors(seu, state$config, plan)
        state <- .sc_run_put(root, state, "strategy_neighbors", seu)
        state <- .sc_run_checkpoint(root, state, stage, "strategy_cluster")
      } else if (stage == "strategy_cluster") {
        plan <- .sc_run_strategy_require(root, state)$proposal
        seu <- .sc_run_strategy_cluster(.sc_run_get(root, state, "strategy_neighbors"), state$config, plan)
        state <- .sc_run_put(root, state, "analysis", seu)
        state$completed <- unique(c(state$completed, "analysis")); state$nodes$analysis <- "EXECUTED"
        state <- .sc_run_checkpoint(root, state, stage, "markers")
      } else if (stage == "qc_evidence") {
        evidence <- .sc_run_qc_evidence(.sc_run_get(root, state, "input"), state$config$context, state$config$assay, state$config$counts_layer)
        state <- .sc_run_put(root, state, "qc_evidence", evidence)
        state <- .sc_run_checkpoint(root, state, stage, "qc_propose")
      } else if (stage == "qc_propose") {
        evidence <- .sc_run_get(root, state, "qc_evidence")
        proposed <- .sc_run_get_proposal(root, state, "qc", evidence$summary, provider, chat_fn, retry, local_only)
        state <- proposed$state
        if (is.null(proposed$proposal)) return(.sc_run_public(state))
        validated <- .sc_run_qc_validate(proposed$proposal, evidence)
        state <- .sc_run_put(root, state, "qc_validated", validated)
        state <- .sc_run_qc_preview_publish(root, state, validated, evidence)
        state$nodes[[stage]] <- "PROPOSED"
        state <- .sc_run_qc_pending(state, validated, evidence, root)
        if (!is.null(state$config$review$preapprove_qc) && identical(validated$proposal, .sc_run_qc_validate(state$config$review$preapprove_qc, evidence)$proposal)) {
          hash <- state$pending$hash
          state <- .sc_run_event(state, "approved", .sc_run_qc_decision_details(state, "explicit_preapproved_rule",
            "Explicit preapproved rule matched the validated proposal and impact preview.", root))
          state$approvals[[hash]] <- tail(state$history, 1)[[1]]$details
          state$approved <- state$pending; state$pending <- NULL; state$stage <- "qc_apply"; state$status <- "ready"
        }
        .sc_run_save(root, state)
      } else if (stage == "qc_apply") {
        if (isTRUE(state$config$strategy)) .sc_run_strategy_require(root, state) else .sc_run_require_approval(state, "qc")
        .sc_run_qc_preview_verify(root, state)
        seu <- .sc_run_qc_apply(.sc_run_get(root, state, "input"), .sc_run_get(root, state, "qc_validated"), .sc_run_get(root, state, "qc_evidence"))
        state <- .sc_run_put(root, state, "qc_object", seu)
        state <- .sc_run_checkpoint(root, state, stage, if (isTRUE(state$config$strategy))
          if (!is.null(state$config$doublet_diagnostics)) "strategy_selection" else
            if (is.null(state$config$cycle_diagnostics)) "strategy_basis" else "strategy_preprocess" else "analysis")
      } else if (stage == "analysis") {
        seu <- .sc_run_analyze(.sc_run_get(root, state, "qc_object"), state$config)
        state <- .sc_run_put(root, state, "analysis", seu)
        state <- .sc_run_checkpoint(root, state, stage, "markers")
      } else if (stage == "markers") {
        markers <- .sc_run_markers(.sc_run_get(root, state, "analysis"), state$config)
        state <- .sc_run_put(root, state, "markers", markers)
        state <- .sc_run_checkpoint(root, state, stage, "annotation_evidence")
      } else if (stage == "annotation_evidence") {
        reference <- if (is.null(state$files$reference)) NULL else .sc_run_get(root, state, "reference")
        evidence <- .sc_run_annotation_evidence(.sc_run_get(root, state, "analysis"), .sc_run_get(root, state, "markers"), state$config$context, reference,
          cluster_column = state$config$cluster_column, reference_review = state$config$reference_review,
          assay = state$config$assay, annotation_context = state$config$annotation_context)
        if (!is.null(state$files$annotation_history_input)) evidence$private$historical <-
          .sc_run_annotation_history_import(.sc_run_get(root, state, "annotation_history_input"), evidence)
        state <- .sc_run_put(root, state, "annotation_evidence", evidence)
        state <- .sc_run_checkpoint(root, state, stage, "annotation_propose")
      } else if (stage == "annotation_propose") {
        evidence <- .sc_run_get(root, state, "annotation_evidence")
        proposed <- .sc_run_get_proposal(root, state, "annotation", evidence$summary, provider, chat_fn, retry, local_only)
        state <- proposed$state
        if (is.null(proposed$proposal)) return(.sc_run_public(state))
        validated <- .sc_run_annotation_validate(proposed$proposal, evidence)
        state <- .sc_run_put(root, state, "annotation_validated", validated)
        state <- .sc_run_annotation_review_publish(root, state, validated, evidence)
        state$nodes[[stage]] <- "PROPOSED"
        state <- .sc_run_pending(state, "annotation", validated, .sc_run_hash(evidence), "annotation_apply")
        .sc_run_save(root, state)
      } else if (stage == "annotation_apply") {
        .sc_run_require_approval(state, "annotation")
        .sc_run_annotation_review_verify(root, state)
        seu <- .sc_run_annotation_apply(.sc_run_get(root, state, "analysis"), .sc_run_get(root, state, "annotation_validated"), state$config$annotation_column)
        state <- .sc_run_put(root, state, "annotated", seu)
        state <- .sc_run_checkpoint(root, state, stage, "finalize")
      } else if (stage == "finalize") {
        state <- .sc_run_finish(root, state)
        state <- .sc_run_checkpoint(root, state, stage, "complete")
        state$status <- "complete"; .sc_run_save(root, state)
      } else stop("Unknown coordinator stage.", call. = FALSE)
      list(ok = TRUE)
    }, error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    if (!result$ok) {
      # If publication succeeded before an injected crash, recover its committed state.
      published <- .sc_run_load(root)
      if (stage %in% published$completed && published$stage != stage) return(.sc_run_public(published))
      state <- if (stage == "strategy_evidence") published else before
      state$status <- "failed"; state$nodes[[stage]] <- "FAILED"
      state$failure <- list(stage = stage, message = result$error, retry = "Explicit retry only; external uncertain dispatches retain their reservations.")
      state <- .sc_run_event(state, "failed", state$failure); .sc_run_save(root, state)
      return(.sc_run_public(state))
    }
  }
}
.sc_run_require_approval <- function(state, kind) {
  if (is.null(state$approved) || state$approved$kind != kind || is.null(state$approvals[[state$approved$hash]]) || !isTRUE(.sc_run_check_binding(state, state$approved)))
    stop("Required exact proposal approval is absent.", call. = FALSE)
}
.sc_run_finish <- function(root, state) {
  nFeature <- NULL
  seu <- .sc_run_get(root, state, "annotated"); markers <- .sc_run_get(root, state, "markers")
  evidence <- .sc_run_get(root, state, "annotation_evidence")
  dir.create(file.path(root, "output"), showWarnings = FALSE)
  .sc_run_atomic(seu, file.path(root, "output", "seurat.rds"))
  utils::write.csv(markers$markers, file.path(root, "output", "markers.csv"), row.names = FALSE)
  utils::write.csv(seu[[]], file.path(root, "output", "metadata.csv"), row.names = TRUE)
  .sc_run_atomic(state$config, file.path(root, "output", "parameters.json"), json = TRUE)
  if (isTRUE(state$config$strategy)) {
    strategy_record <- .sc_run_strategy_review_verify(root, state)
    strategy_summary <- list(schema = "scagentkit.strategy.output.v1", review_hash = strategy_record$hash,
      input_hash = state$input_hash, evidence_hash = strategy_record$evidence_hash,
      proposal = strategy_record$details$canonical_proposal,
      applicability = strategy_record$details$applicability,
      authorizations = state$strategy_authorizations,
      execution = if (state$config$start_stage == "processed")
        list(processed_reuse = TRUE, foundation_executed = FALSE,
          source = "Explicitly supplied processed object; prior misc records describe its source history.") else
        seu@misc$strategy_execution,
      limitations = strategy_record$details$limitations,
      scientific_acceptance = "Execution verified; biological conclusions remain analyst-reviewed.")
    if (!is.null(state$config$cycle_diagnostics)) strategy_summary$cycle_diagnostics <- strategy_record$details$cycle_diagnostics
    if (!is.null(state$config$doublet_diagnostics)) strategy_summary$doublet_diagnostics <- strategy_record$details$doublet_diagnostics
    if (!is.null(state$config$qc_mad)) strategy_summary$qc_mad <- strategy_record$details$qc_mad
    .sc_run_atomic(strategy_summary, file.path(root, "output", "strategy_summary.json"), json = TRUE)
    if (!identical(state$config$start_stage, "processed")) {
      candidates <- seu@misc$strategy_execution$basis$pca$top50_candidates
      .sc_run_pc_verify(candidates)
      .sc_run_atomic(list(schema = "scagentkit.pc-output.v1", input_hash = state$input_hash,
        review_hash = strategy_record$hash, approved_policy = strategy_record$details$canonical_proposal$pcs,
        candidates = candidates, actual_selection = seu@misc$strategy_execution$neighbors$pcs),
        file.path(root, "output", "pc_diagnostics.json"), json = TRUE)
      utils::write.csv(.sc_run_pc_table(candidates), file.path(root, "output", "pc_diagnostics.csv"), row.names = FALSE)
      .sc_run_pc_plot(candidates, file.path(root, "output", "pc_diagnostics.png"))
      batch_execution <- if (identical(strategy_record$details$canonical_proposal$batch$method, "harmony"))
        .sc_run_get(root, state, "strategy_batch")@misc$strategy_execution$batch else NULL
      if (!is.null(batch_execution) &&
          (!identical(batch_execution$dependency_hash, strategy_record$details$dependency_hashes$batch) ||
           !identical(batch_execution$basis_sha256, state$files$strategy_basis$sha256) ||
           !identical(seu@misc$strategy_execution$batch, batch_execution)))
        stop("Final Harmony execution record differs from the approved current checkpoint.", call. = FALSE)
      .sc_run_atomic(list(schema = "scagentkit.batch-output.v1", input_hash = state$input_hash,
        review_hash = strategy_record$hash, approved_choice = strategy_record$details$canonical_proposal$batch,
        executed = !is.null(batch_execution), execution = batch_execution,
        active_reduction = seu@misc$strategy_execution$neighbors$reduction,
        unintegrated_reduction = "pca", expression_assay = state$config$assay,
        marker_expression = "Uncorrected declared RNA/data expression; new clusters can change marker results.",
        interpretation = "Technical mixing and biological label preservation are separate local diagnostics; neither establishes scientific correctness or preservation of unmeasured treatment effects."),
        file.path(root, "output", "batch_diagnostics.json"), json = TRUE)
      if (!is.null(batch_execution)) .sc_run_harmony_plot(batch_execution, file.path(root, "output", "batch_diagnostics.png"))
    }
    if (!is.null(state$config$qc_mad)) .sc_run_mad_outputs(root, state, seu, strategy_record)
    if (!is.null(state$config$cycle_diagnostics)) {
      cycle <- .sc_run_get(root, state, "cycle_diagnostics")
      .sc_run_cycle_verify(cycle)
      .sc_run_atomic(list(schema = "scagentkit.cycle-output.v1",
        input_hash = state$input_hash, review_hash = strategy_record$hash,
        evidence_hash = cycle$evidence_hash, diagnostic_reference = cycle$summary,
        choice = strategy_record$details$canonical_proposal$cycle,
        applicability = strategy_record$details$applicability$cycle,
        retained_cells = ncol(seu), execution = if (state$config$start_stage == "processed")
          list(processed_reuse = TRUE, cycle_method = "none", regressors = character(), scaling_executed = FALSE) else
          seu@misc$strategy_execution$basis,
        interpretation = "Scores were fixed on the full pre-QC input and subset by literal cell ID. Regression acts on scaled residuals only; none preserves the cycle signal. No cycling-cell deletion or biological acceptance is implied."),
        file.path(root, "output", "cycle_summary.json"), json = TRUE)
      .sc_run_cycle_plot(cycle, file.path(root, "output", "cycle_diagnostics.png"))
    }
    if (!is.null(state$config$doublet_diagnostics)) {
      doublet <- .sc_run_get(root, state, "doublet_diagnostics")
      validated <- .sc_run_get(root, state, "strategy_validated")
      .sc_run_doublet_verify(doublet)
      if (!identical(colnames(seu), validated$selected_cells))
        stop("Final cell scope differs from the exact approved doublet/QC selection.", call. = FALSE)
      .sc_run_atomic(list(schema = "scagentkit.doublet-output.v1",
        input_hash = state$input_hash, review_hash = strategy_record$hash,
        evidence_hash = doublet$evidence_hash, diagnostic_reference = doublet$summary,
        choice = validated$proposal$doublet, impact = validated$applicability$doublet,
        actual_retained_cell_ids = colnames(seu), actual_removed_cell_ids = validated$doublet$removed_cells,
        execution = if (state$config$start_stage == "processed")
          list(processed_reuse = TRUE, method = "keep", selection_executed = FALSE,
            scores_attached = TRUE, foundation_executed = FALSE) else seu@misc$strategy_execution$selection,
        interpretation = if (is.null(state$config$qc_mad))
          "Fixed full-input predictions were subset by exact literal cell ID, without refitting. Scores are not calibrated probabilities; classes are not truth. Only approved remove_predicted cells surviving QC were removed; homotypic doublets may be missed." else
          "Predictions use the saved prefilter-eligible cohort before quality filtering. Prefilter-excluded cells are unscored Unknown; original called-cohort rate provenance is preserved. Exact reviewed quality survivors receive fixed predictions without refitting; no calibrated probability or biological truth is claimed."),
        file.path(root, "output", "doublet_summary.json"), json = TRUE)
      .sc_run_doublet_plot(doublet, file.path(root, "output", "doublet_diagnostics.png"))
      utils::write.csv(doublet$scores, file.path(root, "output", "doublet_scores.csv"), row.names = FALSE)
      selection <- data.frame(cell_id = doublet$cell_ids,
        capture = unname(doublet$capture_map),
        passed_qc = if (is.null(validated$qc_validated)) TRUE else doublet$cell_ids %in% validated$qc_validated$keep_cells,
        removed_by_approved_doublet_choice = doublet$cell_ids %in% validated$doublet$removed_cells,
        retained = doublet$cell_ids %in% colnames(seu), stringsAsFactors = FALSE)
      utils::write.csv(selection, file.path(root, "output", "doublet_selection.csv"), row.names = FALSE)
    }
  }
  # Publish bundle provenance only after the actual execution records have been
  # verified and saved. A processed input must not inherit a new execution claim
  # merely because its source misc or reviewed proposal names a batch method.
  reused <- identical(state$config$start_stage, "processed")
  bundle_execution <- list(analysis = if (reused) list() else state$config$analysis,
    batch_integration = if (reused) "processed/reused" else "skip/manual",
    provenance = list(schema = "scagentkit.bundle-execution.v1",
      inputHash = state$input_hash, configHash = state$config_hash,
      implementationHash = state$implementation_hash,
      startStage = state$config$start_stage, foundationExecuted = !reused,
      activeReduction = if (reused) "reused/unspecified" else "pca"))
  if (isTRUE(state$config$strategy)) {
    summary_path <- file.path(root, "output", "strategy_summary.json")
    bundle_execution$provenance$strategySummary <- list(path = "output/strategy_summary.json",
      sha256 = .sc_project_sha_file(summary_path), reviewHash = strategy_record$hash,
      evidenceHash = strategy_record$evidence_hash)
    if (!reused) {
      bundle_execution$analysis <- strategy_record$details$canonical_proposal$analysis
      bundle_execution$batch_integration <- if (!is.null(batch_execution)) "harmony" else "none"
      bundle_execution$provenance$activeReduction <- seu@misc$strategy_execution$neighbors$reduction
      bundle_execution$provenance$batchDiagnostics <- list(path = "output/batch_diagnostics.json",
        sha256 = .sc_project_sha_file(file.path(root, "output", "batch_diagnostics.json")))
    }
  }
  bundle <- .sc_run_bundle(seu, markers, evidence$private$candidates, root, state$config, bundle_execution)
  review <- .sc_run_annotation_review_verify(root, state)
  joint <- lapply(review$details$annotations, function(row) {
    out <- row$joint_evidence
    out$database$all_candidates <- NULL
    out$database$candidates <- lapply(out$database$candidates, function(candidate) {
      candidate$referenceGenes <- NULL
      candidate
    })
    out
  })
  .sc_run_atomic(list(schema = "scagentkit.joint-annotation-output.v1",
    review_hash = review$hash, cell_scope_hash = review$cell_scope_hash,
    evidence_hash = review$evidence_hash, cell_count = review$details$cell_count,
    source = review$details$source, clusters = joint,
    notice = "Approved local evidence summary, not a database export or a new model call. Full immutable review remains in project checkpoints."),
    file.path(root, "output", "annotation_evidence_summary.json"), json = TRUE)
  if ("umap" %in% names(seu@reductions)) ggplot2::ggsave(file.path(root, "output", "umap.png"), Seurat::DimPlot(seu, reduction = "umap", group.by = state$config$annotation_column), width = 7, height = 5)
  if (!is.null(state$files$qc_evidence)) {
    qc <- .sc_run_get(root, state, "qc_evidence")$metrics
    plot <- ggplot2::ggplot(qc, ggplot2::aes(x = nFeature)) + ggplot2::geom_histogram(bins = 40) + ggplot2::theme_minimal()
    ggplot2::ggsave(file.path(root, "output", "qc.png"), plot, width = 7, height = 4)
  }
  writeLines(c("library(scAgentKit)", sprintf("project_dir <- %s", deparse(root)), "sc_run_inspect(project_dir)", "# Reattach your provider only if new calls are needed.", "sc_run_resume(project_dir)"), file.path(root, "resume.R"))
  report <- c("# scAgentKit server-side analysis", paste("Project:", state$project_id), paste("Input SHA256:", state$input_hash), paste("Config SHA256:", state$config_hash), paste("Implementation SHA256:", state$implementation_hash),
              paste("Cells:", ncol(seu), "Features:", nrow(seu)), "QC and annotation approvals are recorded in decision_history.json.",
              "Computed artifacts are EXECUTED; overall scientific conclusions require separate analyst acceptance.",
              if (isTRUE(state$config$strategy)) paste("Supported strategy settings and reused authorization/checkpoints are in strategy_summary.json.",
                if (!is.null(state$config$cycle_diagnostics)) "The approved cycle choice, fixed pre-QC diagnostic reference and actual scaling regressors are in cycle_summary.json; no cycling cells were deleted." else "Cycle diagnostics were not enabled.",
                if (!is.null(state$config$doublet_diagnostics))
                  "Approved fixed capture-specific doublet predictions and exact joint QC selection are recorded in doublet_summary.json, doublet_scores.csv and doublet_selection.csv. Keep is the default; predictions are not biological truth." else
                  "Doublet diagnostics were not enabled.",
                "Batch defaults to none. Explicit approved Harmony changes embedding only; unintegrated PCA and RNA counts/data remain. Actual PC candidates and batch execution are in pc_diagnostics.json and batch_diagnostics.json for raw entry. Processed entry reuses its supplied foundation.") else "Batch integration skipped. Condition and capture were not inferred as batch/donor.",
              if (is.null(state$config$subcluster_origin))
                "After completion, sc_run_subcluster explicitly selects parent clusters for an independently approved raw-count child; the parent files remain unchanged." else
                "This independently reviewed child can apply approved labels by exact cell ID into a new parent-derived object using sc_run_subcluster_apply. Nested children are not supported.",
              "Local annotation evidence bundle is in bundle/. No manual archive transfer is required.",
              "Approved scoped database/AI/history comparison, source hashes and dependency declarations are in annotation_evidence_summary.json; coverage is not a probability and absent top markers are not negative evidence.",
              "External request and usage accounting is in provider/ when a provider was used.")
  writeLines(report, file.path(root, "output", "report.md"))
  paths <- list.files(file.path(root, "output"), full.names = TRUE)
  for (path in c(paths, file.path(root, "resume.R"), list.files(file.path(root, "bundle"), recursive = TRUE, full.names = TRUE))) {
    relative <- substring(path, nchar(root) + 2L)
    state$files[[paste0("output:", relative)]] <- list(path = relative, sha256 = .sc_project_sha_file(path))
  }
  state$output <- list(seurat = file.path(root, "output", "seurat.rds"), bundle = bundle$path,
                       report = file.path(root, "output", "report.md"), scientific_result = "EXECUTED")
  state
}

#' Supply or replace a typed manual QC/annotation proposal
#' @param project_dir Run directory.
#' @param proposal Typed QC or annotation proposal, never executable code.
#' @param reviewer,reason Analyst identity and rationale.
#' @return Updated status, awaiting exact proposal approval.
#' @export
sc_run_propose <- function(project_dir, proposal, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_cleanup(root, .sc_run_load(root))
  .sc_run_propose_locked(root, state, proposal, reviewer, reason)
}
.sc_run_propose_locked <- function(root, state, proposal, reviewer, reason, drive = TRUE, review_binding = NULL) {
  if (is.character(proposal) && length(proposal) == 1L) {
    raw <- rawToChar(.sc_review_read(proposal, limit = 100000L))
    parsed <- .sc_run_provider_parse(raw)
    if (parsed$status != "ok") stop("Invalid typed proposal file.", call. = FALSE)
    proposal <- parsed$content
  }
  if (isTRUE(state$config$strategy) && identical(proposal$schema, "scagentkit.strategy.v1"))
    return(.sc_run_strategy_propose_locked(root, state, proposal, reviewer, reason))
  if (!state$stage %in% c("qc_propose", "annotation_propose")) stop("Manual proposals are only accepted at a proposal stage.", call. = FALSE)
  kind <- if (state$stage == "qc_propose") "qc" else "annotation"
  evidence <- .sc_run_get(root, state, paste0(kind, "_evidence"))
  if (kind == "qc") {
    if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
        !identical(state$implementation_hash, .sc_run_implementation()))
      stop("Configuration or implementation changed; proposal review is stale.", call. = FALSE)
    proposal <- .sc_run_qc_validate(proposal, evidence)$proposal
    options <- .sc_run_qc_current_options(state)
    .sc_run_qc_preview_build(proposal, evidence, options$sensitivity, options$gene_panels)
  } else {
    if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
        !identical(state$implementation_hash, .sc_run_implementation()))
      stop("Configuration or implementation changed; proposal review is stale.", call. = FALSE)
    .sc_run_annotation_validate(proposal, evidence)
  }
  state <- .sc_run_put(root, state, paste0("manual_", kind), proposal)
  previous_proposal_hash <- state$pending$hash
  previous_preview_hash <- if (kind == "qc" && !is.null(state$files$qc_preview)) .sc_run_get(root, state, "qc_preview")$hash else NULL
  state$pending <- NULL; state$approved <- NULL; state$status <- "ready"
  state <- .sc_run_event(state, "manual_proposal", c(list(kind = kind, reviewer = reviewer, reason = reason,
    hash = .sc_run_hash(proposal), previous_proposal_hash = previous_proposal_hash,
    previous_preview_hash = previous_preview_hash), review_binding))
  if (!drive) {
    if (kind == "qc") {
      validated <- .sc_run_qc_validate(proposal, evidence)
      state <- .sc_run_put(root, state, "qc_validated", validated)
      state <- .sc_run_qc_preview_publish(root, state, validated, evidence)
      state$nodes$qc_propose <- "PROPOSED"
      state <- .sc_run_qc_pending(state, validated, evidence, root)
    } else {
      validated <- .sc_run_annotation_validate(proposal, evidence)
      state <- .sc_run_put(root, state, "annotation_validated", validated)
      state <- .sc_run_annotation_review_publish(root, state, validated, evidence)
      state$nodes$annotation_propose <- "PROPOSED"
      state <- .sc_run_pending(state, "annotation", validated, .sc_run_hash(evidence), "annotation_apply")
    }
    .sc_run_save(root, state)
    return(.sc_run_public(state))
  }
  .sc_run_save(root, state)
  .sc_run_drive(root, state, state$config$provider, NULL, FALSE)
}

#' Undo accepted annotation writeback while retaining decision history
#' @param project_dir Run directory.
#' @param decision_id Annotation approval ID returned in decision history.
#' @param reviewer,reason Analyst identity and reason.
#' @return Status ready for a new annotation proposal. Previous versioned artifacts remain.
#' @export
sc_run_undo <- function(project_dir, decision_id, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  .sc_run_undo_locked(root, state, decision_id, reviewer, reason)
}
.sc_run_undo_locked <- function(root, state, decision_id, reviewer, reason, review_binding = NULL) {
  matches <- Filter(function(x) identical(x$decision_id, decision_id) && identical(x$kind, "annotation"), state$approvals)
  if (!length(matches) || !"annotation_apply" %in% state$completed) stop("No executed annotation decision matches this ID.", call. = FALSE)
  if (any(vapply(state$history, function(e) e$action == "annotation_undone" && identical(e$details$decision_id, decision_id), logical(1)))) stop("Decision already undone.", call. = FALSE)
  state <- .sc_run_event(state, "annotation_undone", c(list(decision_id = decision_id, reviewer = reviewer, reason = reason), review_binding))
  # Archive convenience outputs; immutable checkpoint versions and history remain.
  archive <- file.path(root, "versions", paste0("undo-", state$revision)); dir.create(archive, recursive = TRUE, showWarnings = FALSE)
  for (name in c("output", "bundle")) if (dir.exists(file.path(root, name))) {
    if (!file.copy(file.path(root, name), archive, recursive = TRUE)) stop("Cannot archive previous outputs.", call. = FALSE)
    original <- list.files(file.path(root, name), recursive = TRUE, full.names = TRUE)
    for (file in original) {
      copy <- file.path(archive, substring(file, nchar(root) + 2L))
      if (!identical(.sc_project_sha_file(file), .sc_project_sha_file(copy))) stop("Archive checksum mismatch.", call. = FALSE)
    }
  }
  .sc_run_crash("undo:archive")
  state$cleanup <- c("output", "bundle")
  state$files <- state$files[!startsWith(names(state$files), "output:")]
  state$files$annotated <- NULL; state$files$annotation_validated <- NULL; state$files$manual_annotation <- NULL
  state$stage <- "annotation_propose"; state$status <- "awaiting_configuration"; state$pending <- NULL; state$approved <- NULL; state$output <- NULL
  state$completed <- setdiff(state$completed, c("annotation_apply", "finalize"))
  .sc_run_save(root, state)
  .sc_run_crash("undo:checkpoint")
  state <- .sc_run_cleanup(root, state)
  .sc_run_public(state)
}

.sc_run_cleanup <- function(root, state) {
  if (length(state$cleanup)) {
    for (name in state$cleanup) unlink(file.path(root, name), recursive = TRUE)
    state$cleanup <- NULL; .sc_run_save(root, state)
  }
  state
}

#' Record analyst acceptance of the completed scientific result
#' @param project_dir Run directory.
#' @param reviewer,reason Analyst identity and scientific assessment.
#' @return Completed run status with RESULT_ACCEPTED.
#' @export
sc_run_accept <- function(project_dir, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (state$status != "complete") stop("Only a completed result can be accepted.", call. = FALSE)
  state$output$scientific_result <- "RESULT_ACCEPTED"
  state <- .sc_run_event(state, "result_accepted", list(reviewer = reviewer, reason = reason, output = state$output))
  .sc_run_save(root, state); .sc_run_public(state)
}
