# Native protocol helpers share the coordinator's session, state and ledger.
# No remote response-ID history, server tools or provider-side fallback.
.sc_run_xai_native <- function(provider) {
  identical(provider$name, "grok") && identical(provider$model, "grok-4.7")
}

.sc_run_xai_factory <- function(provider) {
  if (!"turn_grok" %in% getNamespaceExports("agentomicsCore"))
    .sc_run_turn_error("unsupported_provider", "The installed Core does not include the native xAI adapter.")
  g <- provider$generation
  if (length(setdiff(names(g), c("temperature", "max_tokens", "timeout_secs",
      "response_format", "reasoning_effort"))) ||
      !identical(g$temperature, 0))
    .sc_run_turn_error("unsupported_generation", "Native xAI turns require the supported explicit generation settings.")
  effort <- if (is.null(g$reasoning_effort)) "high" else g$reasoning_effort
  if (!effort %in% c("low", "medium", "high", "xhigh"))
    .sc_run_turn_error("unsupported_generation", "Unsupported native xAI reasoning effort.")
  getExportedValue("agentomicsCore", "turn_grok")(model = provider$model,
    api_key_env = provider$api_key_env, temperature = g$temperature, effort = effort,
    max_tokens = g$max_tokens, timeout_secs = g$timeout_secs)
}

# Only a reasoning item's protocol ciphertext is opaque. Every other field,
# text block, function argument and result remains subject to full inspection.
# The sequence guard separately proves that outgoing opaque items are exactly
# those in the committed received history; an exemption is not authorization.
.sc_run_xai_inspectable <- function(value) {
  inspect_items <- function(items) {
    if (!is.list(items)) return(items)
    lapply(items, function(item) {
      if (is.list(item) && identical(item$type, "reasoning") &&
          is.character(item$encrypted_content) && length(item$encrypted_content) == 1L)
        item$encrypted_content <- "[opaque native reasoning]"
      item
    })
  }
  if (!is.null(value$input)) value$input <- inspect_items(value$input)
  if (!is.null(value$protocol$output)) value$protocol$output <- inspect_items(value$protocol$output)
  value
}

.sc_run_xai_sequence <- function(current, cluster) {
  if (!length(cluster)) {
    valid <- vapply(current, function(x) is.list(x) &&
      (is.null(x$type) || identical(x$type, "message")) &&
      is.character(x$role) && length(x$role) == 1L &&
      x$role %in% c("system", "user"), logical(1))
    if (!all(valid))
      .sc_run_turn_error("invalid_sequence", "A native session starts with system/user evidence only.")
    return(invisible(TRUE))
  }
  last <- tail(cluster, 1L)[[1L]]
  if (is.null(last$turn_response$protocol$output) || !identical(last$status, "ok"))
    .sc_run_turn_error("invalid_sequence", "No completed native response is available to continue.")
  saved <- jsonlite::fromJSON(last$turn_payload$wire_json, simplifyVector = FALSE)$input
  prefix <- c(saved, last$turn_response$protocol$output)
  if (length(current) <= length(prefix) ||
      !identical(.sc_run_provider_json(current[seq_along(prefix)]), .sc_run_provider_json(prefix)))
    .sc_run_turn_error("invalid_sequence", "The complete native history must remain unchanged.")
  appended <- current[-seq_along(prefix)]
  valid <- vapply(appended, function(x)
    identical(x$type, "function_call_output") ||
      ((is.null(x$type) || identical(x$type, "message")) && identical(x$role, "user")), logical(1))
  if (!all(valid))
    .sc_run_turn_error("invalid_sequence", "Only local function results or user follow-up may be appended.")
  invisible(TRUE)
}

.sc_run_xai_response <- function(value, request, context, provider, usage) {
  fail <- function(code = "invalid_response") list(status = code, content = NULL,
    turn_response = NULL, error = "The native response failed its protocol, privacy or size checks.")
  if (!is.list(value) || !identical(value$schema_version, "agentomics.turn.v2") ||
      !identical(value$protocol$schema, "xai.responses.v1")) return(fail())
  safe <- .sc_run_provider_plain(value[c("schema_version", "message", "finish_reason", "protocol")])
  checked <- tryCatch({
    if (nchar(.sc_run_provider_json(safe), type = "bytes") > request$session$policy$max_payload_bytes)
      .sc_run_turn_error("payload_too_large", "Native response exceeds the session limit.")
    if (!safe$protocol$status %in% c("completed", "incomplete", "failed"))
      stop("Unexpected native status.")
    text <- character(); calls <- list(); refusal <- FALSE
    for (item in safe$protocol$output) {
      if (identical(item$type, "function_call")) calls <- append(calls, list(list(
        id = item$call_id, type = "function",
        `function` = list(name = item$name, arguments = item$arguments))))
      if (identical(item$type, "message")) for (block in item$content) {
        if (identical(block$type, "refusal")) refusal <- TRUE
        if (identical(block$type, "output_text")) text <- c(text, block$text)
      }
    }
    message <- list(role = "assistant", content = if (length(text)) paste(text, collapse = "\n") else NULL)
    if (length(calls)) message$tool_calls <- calls
    finish <- if (refusal) "refusal" else if (safe$protocol$status != "completed")
      safe$protocol$status else if (length(calls)) "tool_calls" else "stop"
    if (!identical(.sc_run_provider_json(message), .sc_run_provider_json(safe$message)) ||
        !identical(finish, safe$finish_reason) || (finish == "stop" && !any(nzchar(text))))
      stop("Native projection differs.")
    input <- c(list(list(role = "user", content = "Validate native response.")),
      safe$protocol$output, lapply(calls, function(call)
        list(type = "function_call_output", call_id = call$id, output = "{}")))
    agentomicsCore::prepare_turn_request(.sc_run_xai_factory(provider), input = input)
    .sc_run_turn_privacy(.sc_run_xai_inspectable(safe), context,
      request$session$policy$max_payload_bytes, provider$api_key_env)
    TRUE
  }, error = identity)
  if (inherits(checked, "error")) return(fail(if (inherits(checked, "sc_run_turn_error"))
    checked$code else "invalid_response"))
  status <- switch(safe$finish_reason, refusal = "provider_refusal",
    incomplete = "truncated_response", failed = "provider_response_error", "ok")
  list(status = status, content = if (status == "ok") safe$message else NULL,
    turn_response = safe, error = if (status == "ok") NULL else
      "The provider did not complete a usable native turn; no automatic retry.")
}

.sc_run_xai_cost <- function(value) {
  ticks <- value$raw_usage$cost_in_usd_ticks
  if (is.numeric(ticks) && length(ticks) == 1L && is.finite(ticks) &&
      ticks >= 0 && ticks == floor(ticks) && ticks <= 2^53 - 1)
    return(list(state = "known", cost_usd = ticks / 1e10))
  # Do not apply Chat token arithmetic to native reasoning billing. A missing
  # provider cost stays unknown; it neither blocks nor invents a zero charge.
  list(state = "unknown", cost_usd = NULL)
}
