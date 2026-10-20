.sc_run_prompt_version <- function() "aggregate-review.v2"

# Transfer consent never grants scientific approval. The exact payload remains
# visible and hashed even when a creation-time scope permits another dispatch.
.sc_run_transfer_categories <- function(kind) {
  switch(sub("^simulated_", "", kind), strategy = c("study_context", "aggregate_qc", "aggregate_markers", "aggregate_design", "aggregate_expression"),
    qc = c("study_context", "aggregate_qc", "aggregate_design"),
    annotation = c("study_context", "aggregate_markers", "aggregate_design", "aggregate_expression"),
    character())
}

.sc_run_transfer_scope <- function(kind) {
  list(schema = "scagentkit.transfer-scope.v1", prompt_version = .sc_run_prompt_version(),
    kind = kind, categories = .sc_run_transfer_categories(kind))
}

.sc_run_transfer_options <- function(value, provider, budget, cost_mode = "legacy_cap") {
  if (is.null(value)) return(NULL)
  value <- .sc_run_provider_plain(value)
  if (!is.list(value) || is.null(names(value)) || anyDuplicated(names(value)) ||
      !identical(value$mode, "project") ||
      length(setdiff(names(value), c("mode", "confirmed", "reviewer", "reason", "categories", "react"))))
    stop("Project transfer consent requires mode='project', confirmed=TRUE, reviewer, reason and explicit categories; omit it for strict per-payload review.", call. = FALSE)
  if (!identical(value$confirmed, TRUE)) stop("Confirm the displayed data categories and project USD cap before enabling project transfer consent.", call. = FALSE)
  .sc_project_string(value$reviewer, "transfer reviewer")
  .sc_project_string(value$reason, "transfer reason")
  categories <- unlist(value$categories, use.names = FALSE)
  allowed <- c("study_context", "aggregate_qc", "aggregate_markers", "aggregate_design", "aggregate_expression")
  if (!is.character(categories) || !length(categories) || anyNA(categories) ||
      anyDuplicated(categories) || any(!categories %in% allowed))
    stop("Choose explicit aggregate transfer categories; cell IDs, matrices and per-cell metadata cannot be authorized.", call. = FALSE)
  if ((!isTRUE(provider$external) && !identical(provider$name, "mock")) || (budget <= 0 && cost_mode != "posthoc"))
    stop("Project transfer consent requires an external provider (or explicit offline mock) and an explicit positive USD cap.", call. = FALSE)
  out <- list(schema = "scagentkit.transfer-consent.v2", mode = "project", confirmed = TRUE,
    reviewer = value$reviewer, reason = value$reason, categories = sort(categories),
    provider_hash = .sc_run_provider_hash(provider), budget_usd = as.numeric(budget),
    prompt_version = .sc_run_prompt_version(),
    react_scope = list(schema = "scagentkit.react-scope.v1", cost_mode = "posthoc",
      policy = .sc_run_turn_policy(value$react),
      category_meaning = "Aggregate markers include bounded local ACT reference entries; aggregate QC includes cluster-context summaries. No identifiers, matrices, paths or writable tools.",
      authority = "Read-only bounded annotation turns only; saving a draft never approves it."))
  if (cost_mode == "posthoc") out$cost_mode <- "posthoc"
  if (.sc_run_provider_contains_secret(out, provider$api_key_env))
    stop("Credential-like transfer consent is forbidden.", call. = FALSE)
  out$hash <- .sc_run_provider_hash(out)
  out
}

.sc_run_transfer_authorized <- function(request, config) {
  consent <- config$review$transfer_consent
  if (is.null(consent) || !consent$schema %in% c("scagentkit.transfer-consent.v1", "scagentkit.transfer-consent.v2") ||
      !identical(consent$mode, "project") || !isTRUE(consent$confirmed) ||
      !isTRUE(config$review$allow_external)) return(FALSE)
  without_hash <- consent; without_hash$hash <- NULL
  if (!identical(consent$hash, .sc_run_provider_hash(without_hash)) ||
      !identical(consent$provider_hash, .sc_run_provider_hash(config$provider)) ||
      !identical(consent$budget_usd, as.numeric(config$budget))) return(FALSE)
  if (identical(consent$cost_mode, "posthoc") != identical(config$cost_mode, "posthoc")) return(FALSE)
  kind <- request$purpose
  if (!is.character(kind) || length(kind) != 1L || !kind %in% c("strategy", "qc", "annotation", "simulated_strategy", "simulated_qc", "simulated_annotation")) return(FALSE)
  if (startsWith(kind, "simulated_") && !identical(config$provider$name, "mock")) return(FALSE)
  scope <- .sc_run_transfer_scope(kind)
  identical(request$transfer_scope, scope) && identical(request$prompt_version, consent$prompt_version) &&
    identical(consent$prompt_version, scope$prompt_version) &&
    all(scope$categories %in% consent$categories)
}
