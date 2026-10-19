# Creation-time provider selection never constructs a client or sends a request.
# Reopening uses the saved policy even when the operator's environment changes.
.sc_start_provider_setup <- function(provider = NULL, budget = NULL, review = NULL, saved = NULL) {
  if (!is.null(saved)) {
    if ((!is.null(provider) && !identical(.sc_run_provider_spec(provider)$metadata, saved$provider)) ||
        (!is.null(budget) && !identical(as.numeric(budget), as.numeric(saved$budget))) ||
        (!is.null(review) && !identical(review, saved$review)))
      stop("Reopening uses the saved provider, budget and transfer policy; omit these settings or create a new project.", call. = FALSE)
    return(list(provider = saved$provider, budget = saved$budget, review = saved$review))
  }
  if (is.null(budget)) budget <- 0
  budget <- .sc_run_provider_number(budget, "budget")
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
  if (identical(metadata$name, "manual")) {
    message("Manual mode: review and edit the local strategy and annotation drafts; no model request is sent.")
    budget <- 0; review <- list(allow_external = FALSE)
  } else if (isTRUE(metadata$external)) {
    if (!isTRUE(review$allow_external))
      message("Provider configured. External transfer is disabled; set review=list(allow_external=TRUE) for a new project to enable exact-payload transfer review.")
    if (budget == 0)
      message("Provider budget is zero. No paid request can run; choose an explicit USD cap after reviewing provider pricing. A calibrated default is not yet available.")
  }
  if (!is.null(review$transfer_consent)) {
    if (!isTRUE(review$allow_external)) stop("Enable allow_external before confirming project transfer scope.", call. = FALSE)
    invisible(.sc_run_transfer_options(review$transfer_consent, metadata, budget))
  }
  list(provider = metadata, budget = budget, review = review)
}
