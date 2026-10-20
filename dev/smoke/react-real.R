# Source this file; nothing is downloaded, transmitted or approved on source.
# Public PBMC3k smoke only. This is not a truth-labelled accuracy benchmark.
react_real_smoke <- function(mex_dir, project_dir, provider, model = NULL,
                             confirmed = FALSE, accept_drafts = FALSE,
                             archive, source_manifest = 'benchmark/evaluation-v1/input-manifest.json') {
  stopifnot(provider %in% c('mock', 'deepseek', 'grok'))
  if (!isTRUE(accept_drafts)) stop('Explicitly select the benchmark accept_drafts policy before running this scripted smoke.')
  if (provider != 'mock' && !isTRUE(confirmed)) stop('Confirm public aggregate transfer to the chosen provider/model before running. Actual costs are recorded afterwards; no monetary cap.')
  if (dir.exists(project_dir)) stop('Use a fresh project. Interrupted requests are never automatically rerun by this driver.')
  manifest <- jsonlite::read_json(source_manifest, simplifyVector = FALSE)
  sha <- function(path) digest::digest(file = path, algo = 'sha256')
  if (!identical(sha(archive), manifest$sha256)) stop('PBMC3k archive differs from the existing evaluation-v1 manifest.')
  for (asset in manifest$members) {
    path <- file.path(mex_dir, basename(asset$name))
    if (!file.exists(path) || !identical(sha(path), asset$sha256)) stop('PBMC3k MEX member differs: ', basename(asset$name))
  }
  if (provider != 'mock') {
    if (!is.character(model) || length(model) != 1L || !nzchar(model)) stop('Supply an explicitly selected and qualified model ID.')
    key <- if (provider == 'deepseek') 'DEEPSEEK_API_KEY' else 'XAI_API_KEY'
    if (!nzchar(Sys.getenv(key))) stop('Configure ', key, ' in this R process; do not put credentials in arguments or reports.')
  }
  started <- Sys.time(); service <- NULL
  receipt <- list(schema = 'scagentkit.pbmc3k-react-smoke.v1',
    purpose = 'Public development smoke; no independent truth or accuracy claim',
    source = manifest$source, archive_sha256 = manifest$sha256,
    provider = provider, requested_model = model, policy = 'accept_drafts',
    reviewer = 'benchmark-policy:accept_drafts', react = 'all',
    status = 'started', gates = list(), real_api_calls = if (provider == 'mock') 0L else NULL)
  on.exit({
    if (!is.null(service) && is.numeric(service$pid)) tools::pskill(service$pid)
    receipt$elapsed_seconds <- as.numeric(difftime(Sys.time(), started, units = 'secs'))
    if (file.exists(file.path(project_dir, 'provider', 'ledger.json'))) {
      ledger <- jsonlite::read_json(file.path(project_dir, 'provider', 'ledger.json'), simplifyVector = FALSE)
      entries <- ledger$entries
      count <- function(field) sum(vapply(entries, function(x) {
        value <- x$usage[[field]]; if (is.null(value)) 0 else as.numeric(value)
      }, numeric(1)))
      receipt$usage <- list(input_tokens = count('input_tokens'), output_tokens = count('output_tokens'),
        unknown_usage_entries = sum(vapply(entries, function(x) is.null(x$usage$input_tokens) || is.null(x$usage$output_tokens), logical(1))))
      receipt$known_cost_usd <- sum(vapply(entries, function(x) if (identical(x$cost_state,'known')) as.numeric(x$cost_usd) else 0, numeric(1)))
      receipt$unknown_cost_entries <- sum(vapply(entries, function(x) !identical(x$cost_state,'known'), logical(1)))
      receipt$provider_entries <- lapply(entries, function(x) x[intersect(names(x), c('status','delivery','model_reported','cost_state','cost_usd','usage'))])
    }
    if (dir.exists(project_dir)) jsonlite::write_json(receipt,
      file.path(project_dir, 'smoke-receipt.json'), auto_unbox = TRUE, pretty = TRUE, null = 'null', digits = NA)
  }, add = TRUE)
  tryCatch({
    selected <- if (provider == 'mock') 'mock' else list(name = provider, model = model)
    consent <- list(mode = 'project', confirmed = TRUE,
      reviewer = 'benchmark-policy:accept_drafts',
      reason = 'Explicitly selected public PBMC3k smoke; aggregate-only transfer and separate scripted scientific reviews.',
      categories = c('study_context','aggregate_qc','aggregate_design','aggregate_markers','aggregate_expression'))
    service <- scAgentKit::sc_start(mex_dir, project_dir,
      context = list(species = 'human', tissue = 'blood',
        research_goal = 'Foundational analysis of public healthy PBMC3k; smoke-test the three review gates, evidence checks and audit. No accuracy claim.'),
      sample_id = 'PBMC3k', matrix_kind = 'filtered', provider = selected,
      react = 'all', browse = FALSE,
      review = list(allow_external = TRUE, transfer_consent = consent))
    simulated <- identical(provider, 'mock')
    for (gate in seq_len(3L)) {
      preview <- scAgentKit::sc_run_suggest(project_dir, simulate = simulated)
      if (!isTRUE(preview$can_request)) stop('No request is available at gate ', gate, '; inspect the preserved project.')
      candidate <- scAgentKit::sc_run_suggest(project_dir, 'request',
        project_id = preview$project_id, input_hash = preview$input_hash,
        expected_revision = preview$revision, suggestion_hash = preview$suggestion_hash,
        simulate = simulated)
      if (!identical(candidate$status, 'candidate')) stop('No valid model candidate at gate ', gate, '; preserved for manual review, without retry.')
      scAgentKit::sc_run_suggest(project_dir, 'adopt',
        project_id = candidate$project_id, input_hash = candidate$input_hash,
        expected_revision = candidate$revision, suggestion_hash = candidate$suggestion_hash,
        simulate = simulated, reviewer = 'benchmark-policy:accept_drafts',
        reason = 'Adopt this complete candidate unchanged for a separate scripted scientific review.')
      review <- scAgentKit::sc_review(project_dir)
      receipt$gates[[gate]] <- list(gate = gate, kind = candidate$kind,
        proposal_hash = review$view$review_node$proposal_hash, approval_policy = 'explicit_scripted_policy')
      final <- scAgentKit::sc_review(review, 'approve',
        reviewer = 'benchmark-policy:accept_drafts',
        reason = 'Explicit benchmark policy approval of the saved public-data draft; no claim of biological correctness.', continue = TRUE)
    }
    if (!identical(final$view$status, 'complete')) stop('Three gates did not reach a complete project.')
    object <- scAgentKit::sc_result(final)
    replay <- scAgentKit::sc_react_replay(project_dir)
    ns <- asNamespace('scAgentKit'); state <- get('.sc_run_load', ns)(project_dir)
    run <- get('.sc_run_get', ns)(project_dir, state, 'annotation_react_run')
    receipt$status <- if (isTRUE(replay$matches)) 'complete' else 'replay_mismatch'
    receipt$cells <- ncol(object); receipt$approval_count <- length(state$approvals)
    receipt$implementation_hash <- state$implementation_hash
    receipt$tool_calls <- run$tool_calls; receipt$react_status <- run$status
    receipt$replay_matches <- replay$matches
    receipt$react_summary <- get('.sc_run_react_audit', ns)(project_dir, state)$summary
    receipt$fallback_reasons <- receipt$react_summary$fallbacks
    receipt$generation <- state$config$provider$generation
    receipt$react_configuration <- state$config$react
    receipt$environment <- list(R = R.version.string, platform = R.version$platform,
      scAgentKit = as.character(utils::packageVersion('scAgentKit')),
      agentomicsCore = as.character(utils::packageVersion('agentomicsCore')),
      Seurat = as.character(utils::packageVersion('Seurat')))
    receipt$elapsed_seconds <- as.numeric(difftime(Sys.time(), started, units = 'secs'))
    invisible(receipt)
  }, error = function(error) {
    receipt$status <<- 'stopped'; receipt$error <<- conditionMessage(error)
    stop(error)
  })
}
