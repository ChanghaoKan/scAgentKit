# Stage-only model suggestions. This channel never changes a scientific approval
# or executes analysis. Its exact transfer authority is separate from pending.
.sc_run_suggestion_scan <- function(scan) {
  science <- scan$scientific_diagnostics
  if (!is.null(science)) {
    # The saved diagnostic artifact includes literal per-cell evidence. Only
    # explicitly selected aggregate fields belong in a provider preview.
    aggregate <- science[intersect(names(science), c("schema", "status", "reason", "hash",
      "approved_pc_count", "approved_resolution", "default_changed", "provider_calls",
      "pc_sensitivity", "resolution_extension"))]
    if (!is.null(science$resampling)) {
      resampling <- science$resampling
      resampling$replicates <- lapply(resampling$replicates, function(row)
        row[intersect(names(row), c("seed", "shared_cells", "ari", "clusters", "per_cluster", "interpretation"))])
      aggregate$resampling <- resampling
    }
    if (!is.null(science$expression)) {
      expression <- science$expression
      aggregate$expression <- expression[intersect(names(expression), c("status", "panels",
        "measured_genes", "missing_genes", "clusters", "common_marker_review", "ambient_status", "interpretation"))]
      aggregate$expression$mixed_lineage <- lapply(expression$mixed_lineage, function(row)
        list(panels = row$panels, status = row$status,
          coexpressing_cell_count = if (identical(row$status, "measured")) length(row$coexpressing_cells) else NULL,
          lineage_relationship = row$lineage_relationship, threshold = row$threshold))
    }
    scan$scientific_diagnostics <- aggregate
  }
  .sc_run_cluster_scan_payload(scan)
}

.sc_run_suggestion_context <- function(root, state, simulate = FALSE) {
  if (!identical(simulate, TRUE) && !identical(simulate, FALSE))
    stop("simulate must be TRUE or FALSE.", call. = FALSE)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed; suggestion is stale.", call. = FALSE)
  if (is.null(state$files$input) || !identical(state$input_hash, state$files$input$sha256))
    stop("Saved input fingerprint changed; suggestion is stale.", call. = FALSE)
  kind <- switch(state$stage, strategy_propose = "strategy", qc_propose = "qc",
    annotation_propose = "annotation", NULL)
  provider <- .sc_run_provider_spec(state$config$provider)$metadata
  if (simulate && !identical(provider$name, "mock"))
    stop("Explicit simulation requires the project's immutable mock provider.", call. = FALSE)
  blocked <- if (is.null(kind)) "Suggestions are available only at a saved strategy, QC or annotation proposal stage." else
    if (identical(provider$name, "manual")) "This project has no configured provider. Create a configured project in R; browser configuration is unavailable." else
    if (provider$external && !isTRUE(state$config$review$allow_external)) "External transfer is disabled in this project's immutable review policy." else NULL
  if (!is.null(blocked)) return(list(kind = kind, provider = provider, blocked_reason = blocked))
  evidence_name <- paste0(kind, "_evidence")
  if (is.null(state$files[[evidence_name]]))
    stop("Saved aggregate suggestion evidence is missing.", call. = FALSE)
  evidence <- .sc_run_get(root, state, evidence_name)
  scan <- if (kind == "strategy") .sc_run_cluster_scan_get(root, state) else NULL
  summary <- evidence$summary
  if (!is.null(scan)) {
    summary$cluster_diagnostics <- .sc_run_suggestion_scan(scan)
    if(identical(summary$cluster_diagnostics$status,"unavailable_essential_aggregates_exceed_bound"))
      return(list(kind=kind,provider=provider,blocked_reason=paste("No model request was sent.",summary$cluster_diagnostics$reason)))
  }
  guidance<-NULL
  if(kind=="annotation") {
    guided<-.sc_run_annotation_guidance(root,state,evidence,summary)
    summary<-guided$summary;guidance<-guided$guidance
  }
  request <- tryCatch({
    value<-.sc_run_request(kind,summary,state$config)
    .sc_run_transfer_check_literal_ids(value,evidence)
    value
  }, sc_run_transfer_privacy_unavailable=function(error)error)
  if (inherits(request, "sc_run_transfer_privacy_unavailable")) return(list(kind = kind, provider = provider,
    blocked_reason = conditionMessage(request)))
  # Simulated responses have their own cache identity and cannot be mistaken
  # for a real or previously supplied runtime model response.
  if (simulate) {
    request$purpose <- paste0("simulated_", kind)
    if (!is.null(request$transfer_scope)) request$transfer_scope <- .sc_run_transfer_scope(request$purpose)
  }
  request_hash <- tryCatch(.sc_run_request_hash(request, provider), error = function(e) {
    if (identical(conditionMessage(e), "Aggregate provider request exceeds 100,000 bytes."))
      return(NULL)
    stop(e)
  })
  if (is.null(request_hash)) return(list(kind = kind, provider = provider,
    blocked_reason = paste("Aggregate provider request exceeds 100,000 bytes.",
      "Suggestions are unavailable for this snapshot; review the complete local evidence manually.",
      "No evidence was truncated to force this request under the limit; the diagnostic projection separately declares its scope and omission accounting. No provider request was sent.")))
  binding <- list(stage = state$stage, input_hash = state$input_hash,
    config_hash = state$config_hash, implementation_hash = state$implementation_hash,
    evidence = state$files[[evidence_name]], cluster_scan = state$files$cluster_scan,
    scientific_proposal_hash = state$pending$hash,
    manual_proposal = state$files[[paste0("manual_", kind)]],
    human_draft_controls = state$files$human_draft_controls,
    scope_hash = state$config$subcluster_origin$scope_hash,
    parent_scope_hash = state$config$subcluster_origin$parent_scope_hash, guided_review_hash=guidance$hash)
  list(kind = kind, provider = provider, evidence = evidence, cluster_scan = scan, request = request,
    request_hash = request_hash, binding = binding, simulated = simulate,
    suggestion_hash = .sc_run_hash(list(schema = "scagentkit.suggestion-binding.v1",
      kind = kind, binding = binding, request_hash = request_hash, simulated = simulate)),
    reference_mode=if(kind=="annotation") summary$reference_mode else NULL, guidance=guidance, blocked_reason = NULL)
}

.sc_run_suggestion_response <- function(answer) {
  if (is.null(answer)) return(NULL)
  answer[intersect(c("status", "cached", "cost_state", "cost_usd", "usage", "raw_usage",
    "charged_or_held_usd", "reservation_usd", "accounting_issue", "error",
    "response_metadata", "response_audit", "request_hash", "attempt"), names(answer))]
}

.sc_run_suggestion_view <- function(root, state, simulate = NULL) {
  if (is.null(simulate)) simulate <- isTRUE(state$suggestion$simulated)
  context <- .sc_run_suggestion_context(root, state, simulate)
  result <- list(schema = "scagentkit.run-suggestion.v1", project_id = state$project_id,
    input_hash = state$input_hash, revision = state$revision, kind = context$kind,
    available = is.null(context$blocked_reason), blocked_reason = context$blocked_reason,
    suggestion_hash = context$suggestion_hash, status = "preview", preview = NULL,
    new_project_budget_default = .sc_run_new_budget("deepseek")$budget,
    candidate = NULL, response = NULL, can_approve = FALSE, can_request = FALSE,
    can_adopt = FALSE, can_discard = FALSE, can_auto_request = FALSE, can_review_conflicts = FALSE)
  if (!is.null(context$blocked_reason)) return(result)
  ledger <- .sc_run_provider_read(file.path(root, "provider", "ledger.json"))
  entries <- ledger$entries
  amount <- function(field, known = NULL) sum(vapply(entries, function(entry) {
    if (!is.null(known) && !identical(identical(entry$cost_state, "known"), known)) return(0)
    value <- entry[[field]]; if (is.null(value)) 0 else value
  }, numeric(1)))
  provider <- context$provider
  result$preview <- list(request_hash = context$request_hash, provider = provider,
    model = provider$model, generation = provider$generation,
    budget = state$config$budget, remaining_usd = max(0, state$config$budget - amount("charged_or_held_usd")),
    consent_mode = if (is.null(state$config$review$transfer_consent)) "strict" else "project",
    consent_hash = state$config$review$transfer_consent$hash,
    transfer_consent = state$config$review$transfer_consent,
    scope_authorized = .sc_run_transfer_authorized(context$request, state$config),
    reservation_usd = provider$reservation_usd,
    charged_or_held_usd = amount("charged_or_held_usd"),
    known_cost_usd = amount("charged_or_held_usd", TRUE),
    held_usd = amount("charged_or_held_usd", FALSE), external = provider$external,
    allow_external = isTRUE(state$config$review$allow_external), simulated = simulate,
    notice = if (simulate) "SIMULATED offline software-control response; no model request or biological inference." else
      if (.sc_run_transfer_authorized(context$request, state$config)) paste(
        "This aggregate request is within the explicitly confirmed creation-time categories, provider and USD cap.",
        "The exact payload below remains available. This consent does not approve a scientific plan or labels.") else
      if (provider$external) paste("The exact aggregate QC/marker/expression evidence and declared context below leave this machine.",
        "Raw matrices, cell IDs and per-cell metadata are excluded. Aggregate sample/capture labels and context may identify a study.") else
        "Local runtime provider; no external transfer is authorized by this preview.",
    system_prompt = context$request$system_prompt, user_prompt = context$request$user_prompt)
  controls <- .sc_run_draft_controls(root, state)
  result$preserved_human_fields <- if (context$kind == "strategy") controls$strategy_fields else
    if (context$kind == "annotation" && identical(controls$annotation_scope_hash, .sc_run_annotation_draft_scope(root, state))) controls$annotation_clusters else character()
  saved <- state$suggestion
  current <- !is.null(saved) && identical(saved$suggestion_hash, context$suggestion_hash)
  approved <- context$request_hash %in% state$suggestion_transfer_hashes ||
    context$request_hash %in% state$transfer_hashes ||
    .sc_run_transfer_authorized(context$request, state$config)
  result$status <- if (approved) "approved" else "preview"
  if (current) {
    result$status <- saved$status
    result$candidate <- saved$candidate
    result$response <- .sc_run_suggestion_response(saved$response)
  } else if (!is.null(saved) && saved$status == "adopted") {
    # Adoption changes the scientific proposal hash. Preserve its receipt for
    # display without offering authority against the new scientific snapshot.
    result$adopted_receipt <- list(suggestion_hash = saved$suggestion_hash,
      request_hash = saved$request_hash, simulated = saved$simulated)
  }
  result$can_approve <- !approved
  result$can_request <- approved && !( !is.null(context$guidance) && isTRUE(state$annotation_guided_attempted)) && !result$status %in% c("candidate", "adopted", "discarded")
  # Evidence identity excludes the editable pending proposal: adoption or saving
  # a reason must never start a second paid request on the same evidence.
  same_evidence <- !is.null(saved) && identical(saved$kind, context$kind) &&
    identical(saved$binding$evidence, context$binding$evidence) &&
    identical(saved$binding$cluster_scan, context$binding$cluster_scan) &&
    identical(saved$binding$guided_review_hash, context$binding$guided_review_hash)
  attempted <- same_evidence && saved$status %in% c("requesting", "candidate", "adopted", "discarded", "failed")
  held <- any(vapply(entries, function(entry) isTRUE(entry$provider$external) &&
    (!identical(entry$cost_state, "known") || isTRUE(entry$accounting_issue)), logical(1)))
  result$can_auto_request <- isTRUE(result$preview$scope_authorized) && result$can_request &&
    state$status %in% c("awaiting_review", "awaiting_configuration") && !attempted && !held &&
    result$preview$remaining_usd >= provider$reservation_usd
  result$auto_request_key <- .sc_run_hash(list(project_id = state$project_id,
    kind = context$kind, evidence = context$binding$evidence, cluster_scan = context$binding$cluster_scan, guided_review_hash=context$binding$guided_review_hash))
  if (same_evidence && !is.null(saved$fallback)) {
    result$fallback <- saved$fallback
    # A local draft may change the scientific proposal binding. The terminal
    # worker receipt still identifies the exact dispatched suggestion; it grants
    # no authority over the refreshed scientific draft.
    result$suggestion_hash <- saved$suggestion_hash
    result$can_approve <- FALSE
    result$can_discard <- FALSE
    result$status <- saved$status
    result$response <- .sc_run_suggestion_response(saved$response)
    result$can_request <- FALSE
    result$can_auto_request <- FALSE
  }
  result$can_adopt <- current && identical(saved$status, "candidate") && !is.null(saved$candidate)
  result$can_discard <- current && !saved$status %in% c("adopted", "discarded")
  result$reference_mode<-context$reference_mode
  result$guided_review_attempted<-isTRUE(state$annotation_guided_attempted)
  if(current&&identical(context$kind,"annotation")&&!is.null(saved$candidate)) {
    result$reference_comparison<-.sc_run_annotation_candidate_comparison(saved$candidate,context$evidence,state$config$reference_review)
    difference<-vapply(result$reference_comparison,function(row)row$status%in%c("unresolved_label_difference","lineage_disagreement")||identical(row$reason,"best_label_tie"),logical(1))
    result$can_review_conflicts<-identical(saved$status,"candidate")&&identical(saved$reference_mode,"independent")&&is.null(state$annotation_guidance)&&any(difference)
  }
  result
}

.sc_run_suggestion_validator <- function(kind, evidence, state, cluster_scan = NULL) {
  if (kind == "qc") return(function(value) .sc_run_qc_validate(value, evidence)$proposal)
  if (kind == "strategy") return(function(value) {
    validated <- .sc_run_strategy_validate(value, evidence)
    .sc_run_subcluster_strategy(state, validated, evidence)
    if (!is.null(cluster_scan)) .sc_run_cluster_selection(validated$proposal$clustering$resolution, cluster_scan)
    validated$proposal
  })
  function(value) {
    validated <- .sc_run_annotation_response_validate(value, evidence)
    list(schema = validated$schema, annotations = validated$annotations)
  }
}

.sc_run_suggestion_mock <- function(root, state, context) {
  kind <- context$kind
  if (kind == "annotation") {
    proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(
      context$evidence$summary$clusters, function(row) list(clusterId = row$clusterId,
        label = "Unknown", confidence = "low", markers = list(),
        rationale = "SIMULATED software control; biological identity is unresolved.")))
  } else {
    manual <- paste0("manual_", kind)
    if (is.null(state$files[[manual]])) {
      if (kind == "strategy") stop("Simulation requires an explicitly supplied typed starting strategy; it does not invent analysis choices.", call. = FALSE)
      proposal <- list(schema = "scagentkit.qc.v1", rationale = "SIMULATED keep-all software control; no quality threshold is inferred.",
        risks = list("Not a model-derived or biologically validated QC recommendation."),
        filters = list(list(op = "range", metric = "nCount", min = 0)))
    } else proposal <- .sc_run_get(root, state, manual)
    proposal$rationale <- "SIMULATED replay of a typed software-control proposal; no model inference."
    proposal$risks <- unique(c(proposal$risks, list("SIMULATED; requires independent scientific review.")))
  }
  # Fail before dispatch if a simulated template is not supported on this scope.
  .sc_run_suggestion_validator(kind, context$evidence, state, context$cluster_scan)(proposal)
  raw <- .sc_project_json(proposal)
  function(system_prompt, user_prompt) list(content = raw, cost_usd = 0,
    model = "SIMULATED-software-control", response_metadata = list(finish_reason = "stop"))
}

.sc_run_suggestion_source <- function(root, state, kind, proposal) {
  receipt_name <- paste0(kind, "_suggestion_adoption")
  if (is.null(state$files[[receipt_name]])) return(NULL)
  # Scientific provenance belongs to an immutable adoption checkpoint, never
  # the replaceable live suggestion panel. A later preview/cache request must
  # leave the already published scientific review valid.
  saved <- .sc_run_get(root, state, receipt_name)
  response_name <- paste0(kind, "_suggestion_response")
  if (!identical(saved$kind, kind) || saved$status != "adopted" ||
      is.null(state$files[[response_name]]))
    stop("Saved suggestion adoption receipt is incomplete.", call. = FALSE)
  answer <- .sc_run_get(root, state, response_name)
  if (!identical(answer, saved$response) || !identical(answer$status, "ok") ||
      !identical(answer$content, saved$candidate) || !identical(answer$request_hash, saved$request_hash))
    stop("Adopted suggestion response or candidate changed.", call. = FALSE)
  list(kind = if (isTRUE(saved$simulated)) "simulated_mock_suggestion" else "adopted_provider_suggestion",
    simulated = isTRUE(saved$simulated), reference_mode=saved$reference_mode, guided_review_hash=saved$binding$guided_review_hash, suggestion_hash = saved$suggestion_hash,
    matches_current = identical(if (is.null(saved$adopted_proposal)) saved$candidate else saved$adopted_proposal, proposal),
    provider_candidate_matches_current = identical(saved$candidate, proposal),
    preserved_human_fields = saved$preserved_human_fields,
    request_hash = saved$request_hash, artifact_sha256 = state$files[[response_name]]$sha256,
    provider = .sc_run_annotation_review_provider(answer$provider),
    response = .sc_run_suggestion_response(answer),
    interpretation = if (isTRUE(saved$simulated)) "SIMULATED software-control output; no model inference or biological conclusion." else
      "Typed provider candidate explicitly adopted by the analyst; scientific acceptance still requires exact central review.")
}

#' Preview, request and stage a typed model suggestion without computation
#'
#' The immutable project provider is the only permitted provider configuration.
#' Approving an outgoing preview authorizes that exact aggregate payload only.
#' Request saves a validated candidate and never runs analysis. Adopt retains saved
#' analyst edits and stages a revalidated proposal for fresh central review.
#' Failures are durable and repeated requests consult the existing usage ledger;
#' this API never automatically retries a dispatched request.
#' @param project_dir Durable local project directory.
#' @param action One of preview, approve, request, adopt or discard.
#' @param project_id,input_hash,expected_revision Exact inspected identities;
#'   required for every action except preview.
#' @param suggestion_hash Exact preview binding, required for mutations.
#' @param reviewer,reason Nonempty analyst identity/rationale for approve/adopt/discard.
#' @param chat_fn Runtime R-only callback for request; never stored or accepted by a browser.
#' @param simulate Explicit offline simulation for a configured mock project only.
#'   Annotation simulations produce Unknown; strategy simulations require a
#'   supplied typed starting plan. Simulated and ordinary caches are separate.
#' @return Safe suggestion view. Adopt returns a fresh run inspection with the
#'   central scientific review node; no action executes scientific computation.
#' @export
sc_run_suggest <- function(project_dir, action = c("preview", "approve", "request", "adopt", "discard", "review_conflicts"),
                           project_id = NULL, input_hash = NULL, expected_revision = NULL,
                           suggestion_hash = NULL, reviewer = NULL, reason = NULL,
                           chat_fn = NULL, simulate = FALSE) {
  action <- match.arg(action)
  if (!is.null(chat_fn) && (action != "request" || !is.function(chat_fn)))
    stop("Only request accepts an in-memory R chat_fn.", call. = FALSE)
  if (simulate && !is.null(chat_fn)) stop("Simulation cannot accept a runtime provider callback.", call. = FALSE)
  root <- .sc_run_root(project_dir)
  if (action == "preview") return(.sc_run_suggestion_view(root, .sc_run_load(root), simulate))
  .sc_project_string(project_id, "project_id")
  .sc_run_review_hash_string(input_hash, "input_hash")
  .sc_run_review_hash_string(suggestion_hash, "suggestion_hash")
  if (is.null(expected_revision)) stop("The exact expected_revision is required.", call. = FALSE)
  if (action %in% c("approve", "adopt", "discard", "review_conflicts")) {
    .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  }
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!identical(project_id, state$project_id) || !identical(input_hash, state$input_hash))
    stop("Foreign project or changed input; suggestion rejected.", call. = FALSE)
  .sc_run_qc_revision_check(state, expected_revision)
  context <- .sc_run_suggestion_context(root, state, simulate)
  if (!is.null(context$blocked_reason)) stop(context$blocked_reason, call. = FALSE)
  if (!identical(suggestion_hash, context$suggestion_hash))
    stop("Stale suggestion/proposal/evidence binding; inspect a new outgoing preview.", call. = FALSE)
  saved <- state$suggestion
  current <- !is.null(saved) && identical(saved$suggestion_hash, suggestion_hash)
  approved <- context$request_hash %in% state$suggestion_transfer_hashes ||
    context$request_hash %in% state$transfer_hashes ||
    .sc_run_transfer_authorized(context$request, state$config)
  if (action == "review_conflicts") {
    state<-.sc_run_annotation_guidance_prepare(root,state,context,reviewer,reason)
    .sc_run_save(root,state)
  } else if (action == "approve") {
    if (approved) return(.sc_run_suggestion_view(root, state, simulate))
    state$suggestion_transfer_hashes <- unique(c(state$suggestion_transfer_hashes, context$request_hash))
    state$suggestion <- list(schema = "scagentkit.suggestion.v1", suggestion_hash = suggestion_hash,
      request_hash = context$request_hash, binding = context$binding, kind = context$kind,
      status = "approved", simulated = simulate, candidate = NULL, response = NULL)
    state <- .sc_run_event(state, "suggestion_transfer_approved", list(
      suggestion_hash = suggestion_hash, request_hash = context$request_hash,
      reviewer = reviewer, reason = reason, external = context$provider$external, simulated = simulate,
      authority = "Exact outgoing aggregate payload only; scientific approval is unchanged."))
    .sc_run_save(root, state)
  } else if (action == "request") {
    if(!is.null(context$guidance)&&isTRUE(state$annotation_guided_attempted))
      stop("The one guided annotation request was already attempted. Inspect its saved response/accounting; no guided retry is allowed.",call.=FALSE)
    if (!approved) stop("Approve the exact outgoing suggestion preview before requesting.", call. = FALSE)
    if (current && saved$status %in% c("adopted", "discarded"))
      stop("This suggestion was already adopted or discarded; inspect a new scope.", call. = FALSE)
    if (simulate) chat_fn <- .sc_run_suggestion_mock(root, state, context)
    if(!is.null(context$guidance))state$annotation_guided_attempted<-TRUE
    request <- context$request
    request$approved_payload_hash <- context$request_hash
    request$validator <- .sc_run_suggestion_validator(context$kind, context$evidence, state, context$cluster_scan)
    state$suggestion <- list(schema = "scagentkit.suggestion.v1", suggestion_hash = suggestion_hash,
      request_hash = context$request_hash, binding = context$binding, kind = context$kind,
      status = "requesting", simulated = simulate, reference_mode=context$reference_mode, candidate = NULL, response = NULL)
    state <- .sc_run_event(state, "suggestion_request_started", list(
      suggestion_hash = suggestion_hash, request_hash = context$request_hash, simulated = simulate,
      retry = FALSE, guided_review_hash=context$guidance$hash, consent_hash = if (.sc_run_transfer_authorized(context$request, state$config)) state$config$review$transfer_consent$hash else NULL,
      prompt_version = context$request$transfer_scope$prompt_version,
      authority = "Stage a candidate only; no scientific computation."))
    .sc_run_save(root, state)
    answer <- tryCatch(.sc_run_call(root, request, state$config$provider, chat_fn,
      budget = state$config$budget, allow_external = isTRUE(state$config$review$allow_external), retry = FALSE),
      error = function(error) list(status = "interrupted", content = NULL, cached = FALSE,
        error = "Suggestion request interrupted; inspect the durable ledger. No automatic retry.",
        request_hash = context$request_hash))
    state$suggestion$response <- answer
    state$suggestion$candidate <- if (identical(answer$status, "ok")) answer$content else NULL
    state$suggestion$status <- if (identical(answer$status, "ok")) "candidate" else "failed"
    state <- .sc_run_event(state, "suggestion_request_finished", list(
      suggestion_hash = suggestion_hash, request_hash = context$request_hash,
      response_status = answer$status, cached = isTRUE(answer$cached), simulated = simulate,
      cost_state = answer$cost_state, charged_or_held_usd = answer$charged_or_held_usd))
    if (!identical(answer$status, "ok"))
      state <- .sc_run_suggestion_fallback(root, state, context, answer)
    .sc_run_save(root, state)
  } else if (action == "discard") {
    if (!current || saved$status %in% c("adopted", "discarded"))
      stop("No current staged suggestion can be discarded.", call. = FALSE)
    state$suggestion$status <- "discarded"
    state <- .sc_run_event(state, "suggestion_discarded", list(suggestion_hash = suggestion_hash,
      reviewer = reviewer, reason = reason, scientific_proposal_unchanged = TRUE))
    .sc_run_save(root, state)
  } else {
    if (!current || !identical(saved$status, "candidate") || is.null(saved$candidate))
      stop("No current validated suggestion candidate can be adopted.", call. = FALSE)
    merged <- .sc_run_merge_model_draft(root, state, context$kind, saved$candidate)
    proposal <- .sc_run_suggestion_validator(context$kind, context$evidence, state, context$cluster_scan)(merged$proposal)
    # Preserve the response as scientific evidence of its actual provenance.
    # Ordinary manual edits can subsequently override it via the normal API.
    state <- .sc_run_put(root, state, paste0(context$kind, "_suggestion_response"), saved$response)
    state$suggestion$status <- "adopted"
    state$suggestion$adopted_proposal <- proposal
    state$suggestion$preserved_human_fields <- merged$preserved
    state <- .sc_run_put(root, state, paste0(context$kind, "_suggestion_adoption"), state$suggestion)
    state <- .sc_run_event(state, "suggestion_adopted", list(suggestion_hash = suggestion_hash,
      request_hash = context$request_hash, reviewer = reviewer, reason = reason,
      simulated = simulate, scientific_approval_required = TRUE,
      preserved_human_fields = merged$preserved,
      raw_candidate_hash = .sc_run_hash(saved$candidate), adopted_proposal_hash = .sc_run_hash(proposal)))
    .sc_run_propose_locked(root, state, proposal, reviewer, reason, drive = FALSE,
      review_binding = list(suggestion_hash = suggestion_hash, request_hash = context$request_hash,
        simulated = simulate, source = "adopted_typed_suggestion"))
    return(sc_run_inspect(root))
  }
  .sc_run_suggestion_view(root, state, simulate)
}
