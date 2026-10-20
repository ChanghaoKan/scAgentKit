# Creation-time provider selection never constructs a client or sends a request.
# Reopening uses the saved policy even when the operator's environment changes.
.sc_start_provider_setup <- function(provider = NULL, budget = NULL, review = NULL, saved = NULL, cost_mode = "legacy_cap", react = NULL) {
  if (!is.null(saved)) {
    if ((!is.null(provider) && !identical(.sc_run_provider_spec(provider)$metadata, saved$provider)) ||
        (!is.null(budget) && !identical(as.numeric(budget), as.numeric(saved$budget))) ||
        (!is.null(review) && !identical(review, saved$review)))
      stop("Reopening uses the saved provider, budget and transfer policy; omit these settings or create a new project.", call. = FALSE)
    out <- list(provider = saved$provider, budget = saved$budget, review = saved$review)
    if (identical(saved$cost_mode, "posthoc")) out$cost_mode <- "posthoc"
    return(out)
  }
  review_was_default <- is.null(review)
  budget_was_default <- is.null(budget)
  if (!is.null(budget)) budget <- .sc_run_provider_number(budget, "budget")
  if (is.null(review)) review <- list(allow_external = FALSE)
  if (!is.list(review) || (length(review) && (is.null(names(review)) || anyDuplicated(names(review)))) ||
      any(!names(review) %in% c("allow_external", "transfer_consent")) ||
      (!is.null(review$allow_external) && !identical(review$allow_external, TRUE) && !identical(review$allow_external, FALSE)))
    stop("Startup review accepts allow_external=TRUE/FALSE and explicit transfer_consent; scientific approvals remain separate.", call. = FALSE)
  if (is.null(provider)) {
    names <- c("deepseek", "grok")
    present <- nzchar(trimws(Sys.getenv(c("DEEPSEEK_API_KEY", "XAI_API_KEY"))))
    provider <- if (sum(present) == 1L) names[present] else "manual"
    if (sum(present) > 1L)
      message("More than one provider key is available. Starting manual mode; choose provider='deepseek' or 'grok' in a new project to enable suggestions.")
  }
  metadata <- .sc_run_provider_spec(provider)$metadata
  if (isTRUE(metadata$external) && (!is.null(metadata$api_key_env) &&
      !nzchar(trimws(Sys.getenv(metadata$api_key_env))))) {
    message("No key is available in ", metadata$api_key_env,
      "; starting manual mode. Set the key and select a new project to enable model suggestions.")
    metadata <- .sc_run_provider_spec("manual")$metadata
  }
  if (cost_mode == "posthoc") budget <- 0
  selected <- .sc_run_new_budget(metadata, budget)
  metadata <- selected$provider; budget <- selected$budget
  if (review_was_default && isTRUE(metadata$external) && cost_mode == "posthoc" && interactive()) {
    answer <- readline(paste0("Allow ", metadata$name, " / ", metadata$model,
      " to receive study context and aggregate QC, design, marker, expression and ACT evidence for drafts and bounded read-only checks? No cell IDs, matrices or paths. Actual costs are recorded afterwards; no monetary cap. Scientific decisions still require your approval. [yes/no]: "))
    if (tolower(trimws(answer)) %in% c("yes", "y")) review <- list(allow_external = TRUE,
      transfer_consent = list(mode = "project", confirmed = TRUE, reviewer = "startup-user",
        reason = "Confirmed aggregate transfer once at project creation.",
        categories = c("study_context", "aggregate_qc", "aggregate_design", "aggregate_markers", "aggregate_expression"), react = react))
  }
  if (!is.null(review$transfer_consent) && !is.null(react)) review$transfer_consent$react <- react
  if (identical(metadata$name, "manual")) {
    message("Manual mode: review and edit the local strategy and annotation drafts; no model request is sent.")
    budget <- 0; review <- list(allow_external = FALSE)
  } else if (isTRUE(metadata$external)) {
    if (!isTRUE(review$allow_external))
      message("Provider configured. External transfer is disabled; set review=list(allow_external=TRUE) for a new project to enable exact-payload transfer review.")
    if (budget == 0 && cost_mode != "posthoc")
      message("Provider budget is zero. No paid request can run; choose an explicit USD cap after reviewing provider pricing. This provider/model/settings combination has no calibrated default; supply an explicit cap.")
  }
  if (!is.null(review$transfer_consent)) {
    if (budget_was_default && cost_mode != "posthoc") stop("Project transfer consent requires an explicit USD cap. Review the default and data categories, then supply budget=1 or another chosen cap.", call. = FALSE)
    if (!isTRUE(review$allow_external)) stop("Enable allow_external before confirming project transfer scope.", call. = FALSE)
    consent <- .sc_run_transfer_options(review$transfer_consent, metadata, budget, cost_mode)
    scope <- consent$react_scope$policy
    message("Confirmed project transfer scope: ", metadata$name, " / ", metadata$model,
      if (cost_mode == "posthoc") "; usage and costs recorded after calls" else paste0("; one-shot budget USD ", format(budget, scientific = FALSE, trim = TRUE)),
      ". Annotation evidence checks may send aggregate marker, expression, QC, design and ACT reference summaries",
      " using these read-only tools: ", paste(unlist(scope$tools, use.names = FALSE), collapse = ", "),
      ". Limits: ", scope$max_steps_per_cluster, " turns per cluster, ", scope$max_steps,
      " turns per session",
      ". No cell IDs, cell-level matrices or local paths. Saving a draft never approves it.",
      " Annotation evidence checks record usage and cost after calls; they have no monetary cap.")
  }
  out <- list(provider = metadata, budget = budget, review = review)
  if (cost_mode == "posthoc") out$cost_mode <- "posthoc"
  out
}
