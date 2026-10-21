# Provider calls for the resumable coordinator. Functions and credentials stay
# in memory; the single atomic ledger contains only safe configuration and data.
.sc_run_provider_scalar <- function(x, name, pattern = NULL) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x) ||
      (!is.null(pattern) && !grepl(pattern, x))) stop("Invalid provider ", name, ".")
  x
}

.sc_run_provider_number <- function(x, name, minimum = 0, maximum = Inf) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) ||
      x < minimum || x > maximum) stop("Invalid provider ", name, ".")
  as.numeric(x)
}

.sc_run_provider_plain <- function(x) {
  # JSON omits arbitrary attributes, but RDS preserves them. Keep only data
  # values and list field names; never inspect objects held in attributes.
  if (is.null(x)) return(NULL)
  fields <- attr(x, "names", exact = TRUE)
  attributes(x) <- NULL
  if (is.list(x)) {
    x <- lapply(x, .sc_run_provider_plain)
    if (!is.null(fields)) {
      attributes(fields) <- NULL
      names(x) <- fields
    }
  }
  x
}

.sc_run_provider_redact <- function(x, env_names = NULL) {
  # Never preserve HTTP error bodies, credentials echoed by a custom provider,
  # or environment keys in responses. Do not inspect a chat closure's environment.
  env_names <- unique(c("DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENAI_API_KEY", env_names))
  keys <- Sys.getenv(env_names)
  for (key in keys[nzchar(keys)]) x <- gsub(key, "[REDACTED]", x, fixed = TRUE)
  x <- gsub("(?i)Bearer[[:space:]]+[A-Za-z0-9._~+/-]{8,}", "Bearer [REDACTED]", x, perl = TRUE)
  # Anchor the key prefix at a token boundary so ordinary prose such as
  # "high-risk-stratification" is not mistaken for an "sk-" credential.
  gsub("(?i)(?<![A-Za-z0-9_-])(sk-|xai-)[A-Za-z0-9_-]{12,}", "[REDACTED]", x, perl = TRUE)
}

.sc_run_provider_contains_secret <- function(x, env_names = NULL) {
  if (is.null(x)) return(FALSE)
  if (!is.null(names(x)) && .sc_run_provider_contains_secret(names(x), env_names)) return(TRUE)
  if (is.list(x)) return(any(vapply(x, .sc_run_provider_contains_secret, logical(1), env_names = env_names)))
  is.character(x) && !identical(x, .sc_run_provider_redact(x, env_names))
}

.sc_run_provider_json <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
}

.sc_run_provider_hash <- function(x) {
  digest::digest(enc2utf8(.sc_run_provider_json(x)), algo = "sha256", serialize = FALSE)
}

# This is a configuration parser, not a factory invocation: inspecting a plan
# or reading a cache never needs a key. Only call() constructs the built-in fn.
.sc_run_provider_spec <- function(provider = NULL, chat_fn = NULL) {
  if (!is.null(chat_fn) && !is.function(chat_fn)) stop("`chat_fn` must be a function.")
  if (is.function(provider)) {
    if (!is.null(chat_fn)) stop("Supply either a provider function or `chat_fn`.")
    chat_fn <- provider; provider <- NULL
  }
  if (is.null(provider)) provider <- list(name = if (is.null(chat_fn)) "manual" else "custom")
  if (is.character(provider) && length(provider) == 1L) provider <- list(name = tolower(provider))
  fields <- c("name", "model", "generation", "external", "pricing", "api_key_env", "base_url")
  if (!is.list(provider) || is.null(names(provider)) || anyDuplicated(names(provider)) ||
      any(!names(provider) %in% fields)) {
    stop("Provider configuration accepts only name, model, generation, external, pricing, api_key_env and base_url; credentials belong in the runtime environment.")
  }
  name <- .sc_run_provider_scalar(provider$name, "name", "^[A-Za-z0-9._-]+$")
  name <- tolower(name)
  defaults <- switch(name, deepseek = "deepseek-flash",
    grok = "grok-4.20-0309-non-reasoning", manual = "manual", "unspecified")
  model <- .sc_run_provider_scalar(if (is.null(provider$model)) defaults else provider$model,
    "model", "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$")
  external <- if (is.null(provider$external)) !name %in% c("manual", "mock", "local") else provider$external
  if (!is.logical(external) || length(external) != 1L || is.na(external)) stop("`external` must be TRUE or FALSE.")
  if (name %in% c("deepseek", "grok", "openai_compatible") && !external) stop("Built-in remote providers are external.")
  base_url <- provider$base_url
  if (identical(name, "openai_compatible")) {
    if (is.null(provider$model) || is.null(provider$api_key_env))
      stop("OpenAI-compatible providers require explicit model, api_key_env and HTTPS base_url.")
    base_url <- .sc_run_provider_scalar(base_url, "base_url")
    # A destination is part of transmission consent. Keep credentials, queries,
    # fragments and literal IP addresses out of saved provider configuration.
    if (!grepl("^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?([:][0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$", base_url) ||
        grepl("^https://[0-9.]+([:/]|$)", base_url))
      stop("base_url needs an HTTPS hostname and optional path; omit credentials, query and fragment.")
    base_url <- sub("/+$", "", base_url)
  } else if (!is.null(base_url)) stop("base_url is available only for name='openai_compatible'.")
  generation <- list(temperature = 0, max_tokens = 4096, timeout_secs = 180,
    response_format = list(type = "json_object"))
  if (name == "deepseek") generation$thinking <- list(type = "disabled")
  supplied <- provider$generation
  allowed <- c("temperature", "max_tokens", "timeout_secs", "seed", "top_p",
    "frequency_penalty", "presence_penalty", "thinking", "response_format", "reasoning_effort")
  if (!is.null(supplied)) {
    if (!is.list(supplied) || is.null(names(supplied)) || anyDuplicated(names(supplied)) ||
        any(!names(supplied) %in% allowed)) stop("Unsupported provider generation setting.")
    generation[names(supplied)] <- supplied
  }
  generation$temperature <- .sc_run_provider_number(generation$temperature, "temperature", 0, 2)
  generation$max_tokens <- .sc_run_provider_number(generation$max_tokens, "max_tokens", 1, .Machine$integer.max)
  if (generation$max_tokens != floor(generation$max_tokens)) stop("`max_tokens` must be an integer.")
  generation$timeout_secs <- .sc_run_provider_number(generation$timeout_secs, "timeout_secs", 1, 3600)
  if (!is.null(generation$seed)) {
    generation$seed <- .sc_run_provider_number(generation$seed, "seed", 0, .Machine$integer.max)
    if (generation$seed != floor(generation$seed)) stop("`seed` must be an integer.")
  }
  if (!is.null(generation$top_p)) generation$top_p <- .sc_run_provider_number(generation$top_p, "top_p", 0, 1)
  for (field in c("frequency_penalty", "presence_penalty"))
    if (!is.null(generation[[field]])) generation[[field]] <- .sc_run_provider_number(generation[[field]], field, -2, 2)
  for (field in c("thinking", "response_format")) {
    if (!is.null(generation[[field]])) {
      value <- generation[[field]]
      choices <- if (field == "thinking") c("disabled", "enabled") else "json_object"
      if (!is.list(value) || !identical(names(value), "type") ||
          !is.character(value$type) || length(value$type) != 1L || !value$type %in% choices)
        stop("Unsupported provider ", field, ".")
    }
  }
  if (!is.null(generation$reasoning_effort)) {
    value <- generation$reasoning_effort
    if (!is.character(value) || length(value) != 1L ||
        !value %in% c("none", "minimal", "low", "medium", "high", "xhigh")) stop("Unsupported reasoning_effort.")
  }
  generation <- generation[sort(names(generation))]
  pricing <- provider$pricing
  if (!is.null(pricing)) {
    fields <- c("input_per_million", "output_per_million", "cached_input_per_million")
    if (!is.list(pricing) || is.null(names(pricing)) || anyDuplicated(names(pricing)) ||
        !all(c("input_per_million", "output_per_million") %in% names(pricing)) ||
        any(!names(pricing) %in% fields)) stop("Invalid provider pricing; supply per-million USD rates.")
    pricing <- lapply(pricing[sort(names(pricing))], .sc_run_provider_number, name = "pricing")
  }
  env <- provider$api_key_env
  if (is.null(env)) env <- switch(name, deepseek = "DEEPSEEK_API_KEY", grok = "XAI_API_KEY", NULL)
  if (!is.null(env)) env <- .sc_run_provider_scalar(env, "api_key_env", "^[A-Z][A-Z0-9_]*$")
  metadata <- list(name = name, model = model, generation = generation, external = external,
    pricing = pricing, api_key_env = env)
  if (!is.null(base_url)) metadata$base_url <- base_url
  metadata <- .sc_run_provider_plain(metadata)
  if (!identical(.sc_run_provider_json(metadata), .sc_run_provider_redact(.sc_run_provider_json(metadata), env)))
    stop("Credential-like provider metadata is forbidden.")
  list(metadata = metadata, fn = chat_fn)
}

.sc_run_provider_request <- function(request, env_names = NULL) {
  fields <- c("system_prompt", "user_prompt", "purpose", "evidence_hash", "approved_payload_hash", "validator", "transfer_scope", "prompt_version", "max_payload_bytes")
  if (!is.list(request) || is.null(names(request)) || anyDuplicated(names(request)) ||
      any(!names(request) %in% fields)) stop("Invalid coordinator provider request fields.")
  system <- .sc_run_provider_scalar(request$system_prompt, "system_prompt")
  user <- .sc_run_provider_scalar(request$user_prompt, "user_prompt")
  limit <- if (is.null(request$max_payload_bytes)) Inf else
    .sc_run_capacity_bytes(request$max_payload_bytes)
  if (limit != floor(limit)) stop("Request byte limit must be an integer.")
  if (nchar(enc2utf8(system), type = "bytes") + nchar(enc2utf8(user), type = "bytes") > limit)
    stop(structure(list(message=paste0("Aggregate provider request exceeds its configured ", limit, " byte limit."), call=NULL), class=c("sc_run_payload_too_large", "error", "condition")))
  if (!identical(c(system, user), .sc_run_provider_redact(c(system, user), env_names))) stop("Credential-like request content is forbidden.")
  if (!is.null(request$validator) && !is.function(request$validator)) stop("Request validator must be a function.")
  purpose <- if (is.null(request$purpose)) "analysis_decision" else .sc_run_provider_scalar(request$purpose, "purpose")
  if (!identical(purpose, .sc_run_provider_redact(purpose, env_names))) stop("Credential-like request purpose is forbidden.")
  evidence <- request$evidence_hash
  if (!is.null(evidence)) evidence <- .sc_run_provider_scalar(evidence, "evidence_hash", "^[a-f0-9]{64}$")
  payload <- list(system_prompt = system, user_prompt = user, purpose = purpose, evidence_hash = evidence)
  if (!is.null(request$max_payload_bytes)) payload$max_payload_bytes <- request$max_payload_bytes
  if (!is.null(request$prompt_version)) payload$prompt_version <- .sc_run_provider_scalar(
    request$prompt_version, "prompt_version", "^[A-Za-z0-9._-]{1,80}$")
  if (!is.null(request$transfer_scope)) {
    if (!identical(request$transfer_scope, .sc_run_transfer_scope(purpose)) ||
        !purpose %in% c("strategy", "qc", "annotation", "simulated_strategy", "simulated_qc", "simulated_annotation")) stop("Invalid aggregate transfer scope.")
    payload$transfer_scope <- request$transfer_scope
  }
  serialized <- .sc_run_provider_json(payload)
  if (!identical(serialized, .sc_run_provider_redact(serialized, env_names))) stop("Credential-like request content is forbidden.")
  payload
}

# Root approves this exact payload hash, which includes the transmitted text,
# model and generation settings, rather than just a summary's file name.
.sc_run_request_hash <- function(request, provider = NULL, chat_fn = NULL) {
  spec <- .sc_run_provider_spec(provider, chat_fn)$metadata
  if (identical(request$schema, "scagentkit.provider-turn.v1"))
    return(.sc_run_turn_prepare(request, spec)$request_hash)
  .sc_run_provider_hash(list(schema = "scagentkit.provider-request.v1",
    provider = spec[c("name", "model", "generation", "external",
      if (!is.null(spec$base_url)) c("base_url", "api_key_env"))],
    request = .sc_run_provider_request(request, spec$api_key_env)))
}

.sc_run_provider_write <- function(value, path) {
  tmp <- tempfile(".atomic-", tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writeLines(.sc_run_provider_json(value), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) stop("Cannot atomically save provider ledger.")
  invisible(value)
}

.sc_run_provider_release <- function(lock, token) {
  owner <- tryCatch(jsonlite::fromJSON(file.path(lock, "owner.json"), simplifyVector = FALSE),
    error = function(e) NULL)
  if (!is.null(owner) && identical(owner$token, token)) unlink(lock, recursive = TRUE)
  invisible(NULL)
}

.sc_run_provider_cost_record_valid <- function(entry) {
  if (identical(entry$cost_state, "unknown")) return(is.null(entry$cost_usd))
  identical(entry$cost_state, "known") && is.numeric(entry$cost_usd) &&
    length(entry$cost_usd) == 1L && is.finite(entry$cost_usd) && entry$cost_usd >= 0
}

.sc_run_provider_read <- function(path) {
  if (!file.exists(path)) return(list(schema = "scagentkit.provider-ledger.v1", entries = list()))
  ledger <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(ledger) || !identical(ledger$schema, "scagentkit.provider-ledger.v1") ||
      !is.list(ledger$entries)) stop("Provider ledger is invalid; dispatch refused.")
  for (entry in ledger$entries) {
    if (!is.list(entry) || !is.character(entry$request_hash) || length(entry$request_hash) != 1L ||
        !grepl("^[a-f0-9]{64}$", entry$request_hash) ||
        !.sc_run_provider_cost_record_valid(entry))
      stop("Provider ledger entry is invalid; dispatch refused.")
    if (!is.null(entry[["raw"]]) && !identical(entry$response_hash, .sc_run_provider_hash(entry[["raw"]])))
      stop("Provider cached response hash mismatch; dispatch refused.")
    if (!is.null(entry$raw_usage_hash) &&
        !identical(entry$raw_usage_hash, .sc_run_provider_hash(entry[["raw_usage"]])))
      stop("Provider cached raw usage hash mismatch; dispatch refused.")
    if (!is.null(entry$response_metadata_hash) &&
        !identical(entry$response_metadata_hash, .sc_run_provider_hash(entry$response_metadata)))
      stop("Provider cached response metadata hash mismatch; dispatch refused.")
    if (!is.null(entry$turn_response) &&
        !identical(entry$turn_response_hash, .sc_run_provider_hash(entry$turn_response)))
      stop("Provider cached structured response hash mismatch; dispatch refused.")
    if (!is.null(entry$turn_payload) &&
        !identical(entry$turn_payload_hash, .sc_run_provider_hash(entry$turn_payload)))
      stop("Provider cached structured payload hash mismatch; dispatch refused.")
    if (!is.null(entry$turn_outcome) &&
        !identical(entry$turn_outcome_hash, .sc_run_provider_hash(entry$turn_outcome)))
      stop("Provider cached structured outcome hash mismatch; dispatch refused.")
  }
  ledger
}

.sc_run_provider_parse <- function(raw, validator = NULL, env_names = NULL) {
  if (!is.character(raw) || length(raw) != 1L || is.na(raw) || !nzchar(trimws(raw)))
    return(list(status = "empty_response", content = NULL, error = "Provider returned no non-empty JSON string."))
  if (!identical(raw, .sc_run_provider_redact(raw, env_names)))
    return(list(status = "secret_detected", content = NULL, error = "Credential-like provider response was discarded."))
  parsed <- tryCatch({
    if (!grepl("^\\s*\\{", raw)) stop("Response must be a JSON object without prose or fences.")
    value <- jsonlite::fromJSON(trimws(raw), simplifyVector = FALSE)
    value <- .decision_object(value, required = character(), optional = names(value))
    if (!is.null(validator)) value <- validator(value)
    # Validator results may contain data only; never persist functions or objects.
    data_only <- function(x) {
      if (is.null(x)) return(TRUE)
      if (is.list(x) && !is.object(x)) return(all(vapply(x, data_only, logical(1))))
      is.atomic(x) && !is.object(x) && !is.raw(x)
    }
    if (!data_only(value)) stop("Validator must return plain serializable data.")
    value <- .sc_run_provider_plain(value)
    if (.sc_run_provider_contains_secret(value, env_names))
      stop(structure(list(message = "Credential-like validated content was discarded.", call = NULL),
        class = c("sc_run_provider_secret", "error", "condition")))
    value
  }, error = function(e) e)
  if (inherits(parsed, "error")) return(list(status = if (inherits(parsed, "sc_run_provider_secret")) "secret_detected" else "invalid_response", content = NULL,
    error = substr(.sc_run_provider_redact(conditionMessage(parsed), env_names), 1, 2000)))
  list(status = "ok", content = parsed, error = NULL)
}

# Metadata is data, never the HTTP response, request headers or provider error
# body. Missing fields stay unknown for legacy content-only chat functions.
.sc_run_provider_response_metadata <- function(value, env_names = NULL) {
  nested <- if (is.list(value)) value$response_metadata else attr(value, "response_metadata", exact = TRUE)
  if (!is.list(nested) || is.object(nested)) nested <- list()
  field <- function(aliases) {
    for (name in aliases) {
      if (!is.null(nested[[name]])) return(nested[[name]])
      candidate <- if (is.list(value)) value[[name]] else attr(value, name, exact = TRUE)
      if (!is.null(candidate)) return(candidate)
    }
    NULL
  }
  finish <- field("finish_reason")
  allowed_finish <- c("stop", "length", "max_tokens", "max_output_tokens", "content_filter",
    "tool_calls", "function_call", "eos_token", "end_turn", "stop_sequence")
  if (!is.character(finish) || length(finish) != 1L || is.na(finish) ||
      !finish %in% allowed_finish) finish <- NULL
  if (!is.null(finish)) {
    finish <- unname(as.character(finish))
    if (.sc_run_provider_contains_secret(finish, env_names)) finish <- NULL
  }
  status <- field(c("http_status", "status_code", "status"))
  if (!is.numeric(status) || length(status) != 1L || !is.finite(status) ||
      status != floor(status) || status < 100 || status > 599) status <- NULL
  if (!is.null(status)) status <- as.integer(status)
  identifier <- function(aliases) {
    value <- field(aliases)
    if (!is.character(value) || length(value) != 1L || is.na(value) ||
        !grepl("^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", value)) return(NULL)
    value <- unname(as.character(value))
    if (.sc_run_provider_contains_secret(value, env_names)) return(NULL)
    value
  }
  request_id <- identifier("request_id")
  response_id <- identifier(c("response_id", "id"))
  available <- sum(!vapply(list(finish, status, request_id, response_id), is.null, logical(1)))
  list(schema = "scagentkit.provider-response-metadata.v1",
    availability = if (!available) "unavailable" else if (available == 4L) "available" else "partial",
    finish_reason = finish, http_status = status, request_id = request_id, response_id = response_id)
}

.sc_run_provider_response_result <- function(raw, validator = NULL, env_names = NULL,
                                             metadata = NULL, usage = NULL, max_tokens = NULL) {
  metadata <- .sc_run_provider_response_metadata(list(response_metadata = metadata), env_names)
  parsed <- .sc_run_provider_parse(raw, validator, env_names)
  confirmed <- metadata$finish_reason %in% c("length", "max_tokens", "max_output_tokens")
  capped <- !is.null(usage$output_tokens) && !is.null(max_tokens) && usage$output_tokens >= max_tokens
  audit <- list(json_status = parsed$status, json_error = parsed$error,
    truncation = if (isTRUE(confirmed)) "provider_reported" else if (isTRUE(capped) &&
      is.null(metadata$finish_reason)) "suspected_output_cap" else "not_reported")
  # Preserve the received bytes for audit, but never repair, complete or accept
  # JSON that the provider says stopped at its output limit.
  if (isTRUE(confirmed) && parsed$status != "secret_detected") {
    parsed$status <- "truncated_response"; parsed$content <- NULL
    parsed$error <- "Provider reported an output limit; the response is incomplete and requires an explicit new request or manual proposal."
  } else if (!is.null(metadata$http_status) && (metadata$http_status < 200 || metadata$http_status >= 300) &&
      parsed$status != "secret_detected") {
    parsed$status <- "provider_response_error"; parsed$content <- NULL
    parsed$error <- "Provider returned a non-success HTTP status; no response was accepted."
  }
  parsed$response_metadata <- metadata
  parsed$response_audit <- audit
  parsed
}

.sc_run_provider_capture_metadata <- function(frame, env_names = NULL) {
  local <- function(name) if (exists(name, envir = frame, inherits = FALSE))
    get(name, envir = frame, inherits = FALSE) else NULL
  parsed <- local("parsed")
  choice <- if (is.list(parsed) && is.list(parsed$choices) && length(parsed$choices))
    parsed$choices[[1L]] else NULL
  response <- local("resp")
  # Read exactly one allowed response header; no headers object or body is
  # copied into the result, error condition, ledger or coordinator checkpoint.
  request_id <- if (!is.null(response)) tryCatch(httr2::resp_header(response, "x-request-id"),
    error = function(e) NULL) else NULL
  .sc_run_provider_response_metadata(list(http_status = local("status"),
    finish_reason = if (is.list(choice)) choice$finish_reason else NULL,
    response_id = if (is.list(parsed)) parsed$id else NULL,
    request_id = request_id), env_names)
}

# agentomicsCore 0.1.1 exposes no structured-response option. Copy only the
# returned function and adapt its body in memory, retaining its existing lexical
# environment without inspecting it. No namespace or dependency is modified.
.sc_run_provider_adapter <- function(fn, env_names = NULL,
                                     version = as.character(utils::packageVersion("agentomicsCore"))) {
  factory <- getExportedValue("agentomicsCore", "make_chat_fn_openai_compatible")
  inner <- tail(as.list(body(factory)), 1L)[[1L]]
  recognized <- identical(version, "0.1.1") && is.function(fn) &&
    is.call(inner) && identical(inner[[1L]], as.name("function")) &&
    identical(formals(fn), inner[[2L]]) && identical(body(fn), inner[[3L]]) &&
    identical(tail(as.list(body(fn)), 1L)[[1L]], as.name("txt"))
  if (!recognized) stop(structure(list(message =
    "Provider metadata adapter does not recognize this factory version or function body; no request was dispatched.",
    call = NULL), class = c("sc_run_provider_adapter_unavailable", "error", "condition")))
  adapted <- fn
  original <- body(fn)
  capture <- .sc_run_provider_capture_metadata
  capture_usage <- function(frame) {
    parsed <- if (exists("parsed",frame,inherits=FALSE)) get("parsed",frame,inherits=FALSE) else NULL
    .sc_run_provider_raw_usage(if(is.list(parsed)) parsed$usage else NULL)
  }
  body(adapted) <- bquote({
    .sc_response_frame <- environment()
    .sc_response_result <- tryCatch(.(original), error = function(.sc_response_error) {
      .sc_safe_metadata <- .(capture)(.sc_response_frame, .(env_names))
      stop(structure(list(message = "Provider call returned an error; HTTP error body discarded.",
        call = NULL, response_metadata = .sc_safe_metadata),
        class = c("sc_run_provider_transport_error", "error", "condition")))
    })
    attr(.sc_response_result, "raw_usage") <- .(capture_usage)(.sc_response_frame)
    attr(.sc_response_result, "response_metadata") <- .(capture)(.sc_response_frame, .(env_names))
    .sc_response_result
  })
  adapted
}

.sc_run_provider_fn <- function(spec) {
  if (is.function(spec$fn)) return(spec$fn)
  m <- spec$metadata
  if (!m$name %in% c("deepseek", "grok", "openai_compatible")) return(NULL)
  if (!requireNamespace("agentomicsCore", quietly = TRUE)) stop("agentomicsCore is required for built-in providers.")
  g <- m$generation
  args <- list(model = m$model, api_key_env = m$api_key_env, max_tokens = g$max_tokens,
    temperature = g$temperature, timeout_secs = g$timeout_secs)
  extra <- g[setdiff(names(g), c("max_tokens", "temperature", "timeout_secs"))]
  if (length(extra)) args$extra_body <- extra
  if (m$name == "grok") args$vision <- FALSE
  structured <- "structured_response" %in% names(formals(
    getExportedValue("agentomicsCore", "make_chat_fn_openai_compatible")))
  if (structured) args$structured_response <- TRUE
  factory <- if (identical(m$name, "openai_compatible")) {
    args$base_url <- m$base_url
    args$supports_vision <- FALSE
    "make_chat_fn_openai_compatible"
  } else paste0("chat_", m$name)
  fn <- do.call(getExportedValue("agentomicsCore", factory), args)
  if (structured) fn else .sc_run_provider_adapter(fn, m$api_key_env)
}

.sc_run_provider_tokens <- function() {
  if (!requireNamespace("agentomicsCore", quietly = TRUE)) return(list())
  getExportedValue("agentomicsCore", "token_state")$records
}

.sc_run_provider_usage <- function(value, records = list()) {
  usage <- if (is.list(value)) value$usage else attr(value, "usage", exact = TRUE)
  if (is.null(usage) && length(records)) {
    sum_field <- function(field) {
      values <- vapply(records, function(x) {
        v <- x[[field]]
        if (is.numeric(v) && length(v) == 1L && is.finite(v)) as.numeric(v) else NA_real_
      }, numeric(1))
      if (anyNA(values)) NULL else sum(values)
    }
    usage <- list(input_tokens = sum_field("input_tokens"), output_tokens = sum_field("output_tokens"),
      cached_tokens = sum_field("cached_tokens"))
  }
  if (!is.list(usage)) return(NULL)
  first <- function(fields) {
    for (field in fields) if (!is.null(usage[[field]])) {
      v <- usage[[field]]
      if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v < 0 || v != floor(v)) return(NULL)
      return(as.numeric(v))
    }
    NULL
  }
  list(input_tokens = first(c("input_tokens", "prompt_tokens")),
    output_tokens = first(c("output_tokens", "completion_tokens")),
    cached_tokens = first(c("cached_tokens", "prompt_cache_hit_tokens")))
}

.sc_run_provider_cost <- function(value, usage, metadata) {
  if (!metadata$external) return(list(state = "known", cost_usd = 0))
  cost <- if (is.list(value)) value$cost_usd else attr(value, "cost_usd", exact = TRUE)
  if (is.numeric(cost) && length(cost) == 1L && is.finite(cost) && cost >= 0)
    return(list(state = "known", cost_usd = as.numeric(cost)))
  p <- metadata$pricing
  if (!is.null(usage$input_tokens) && !is.null(usage$output_tokens) && !is.null(p)) {
    cached <- if (is.null(usage$cached_tokens)) 0 else usage$cached_tokens
    if (cached > usage$input_tokens) return(list(state = "unknown", cost_usd = NULL))
    rate <- if (is.null(p$cached_input_per_million)) p$input_per_million else p$cached_input_per_million
    cost <- ((usage$input_tokens - cached) * p$input_per_million + cached * rate +
      usage$output_tokens * p$output_per_million) / 1e6
    if (!is.finite(cost)) return(list(state = "unknown", cost_usd = NULL))
    return(list(state = "known", cost_usd = cost))
  }
  list(state = "unknown", cost_usd = NULL)
}

# One dispatch per call. Retry is an explicit action and is accepted only after
# a completed, accounted-for invalid response. An interrupted/unknown dispatch
# is never sent again automatically, even in a fresh R process.
.sc_run_call <- function(project_dir, request, provider = NULL, chat_fn = NULL,
                         allow_external = FALSE, retry = FALSE,
                         project_lock_owner = NULL, react_runtime = NULL) {
  .sc_run_control_check(project_dir)
  spec <- .sc_run_provider_spec(provider, chat_fn)
  turn <- identical(request$schema, "scagentkit.provider-turn.v1")

  prepared <- if (turn) tryCatch(.sc_run_turn_prepare(request, spec$metadata), error = function(e) e) else NULL
  if (inherits(prepared, "error")) return(list(status = if (inherits(prepared, "sc_run_turn_error"))
    prepared$code else "invalid_request", content = NULL, raw = NULL, cached = FALSE,
    request_hash = NULL, provider = spec$metadata, delivery = "not_sent",
    error = "The structured request could not be prepared; no transmission occurred."))
  request_hash <- if (turn) prepared$request_hash else .sc_run_request_hash(request, spec$metadata)
  if (!is.logical(retry) || length(retry) != 1L || is.na(retry)) stop("`retry` must be TRUE or FALSE.")
  if (!is.character(project_dir) || length(project_dir) != 1L || is.na(project_dir) || !dir.exists(project_dir))
    stop("Provider project directory must already exist.")
  if (turn) {
    if (is.null(project_lock_owner)) {
      project_lock_owner <- .sc_run_lock(project_dir)
      on.exit(.sc_run_release(project_dir, project_lock_owner), add = TRUE)
    } else {
      active <- tryCatch(readRDS(file.path(project_dir, ".run-lock", "owner.rds")), error = function(e) NULL)
      if (is.null(active) || !identical(active, project_lock_owner) ||
          !identical(active$pid, Sys.getpid()))
        .sc_run_turn_error("invalid_session", "The structured turn requires the current project's coordinator lock.")
    }
  }
  base <- file.path(project_dir, "provider"); dir.create(base, showWarnings = FALSE)
  lock <- file.path(base, ".dispatch-lock")
  result <- function(status, error, extra = list()) c(list(status = status, content = NULL,
    raw = NULL, error = error, request_hash = request_hash, provider = spec$metadata, cached = FALSE), extra)
  if (!dir.create(lock, showWarnings = FALSE)) return(result("provider_busy", "Another provider dispatch holds the project lock; inspect before recovering a stale lock."))
  token <- .sc_run_provider_hash(list(Sys.getpid(), as.character(Sys.time()), tempfile()))
  on.exit(.sc_run_provider_release(lock, token), add = TRUE)
  .sc_run_provider_write(list(token = token, pid = Sys.getpid(), host = unname(Sys.info()["nodename"]),
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE)), file.path(lock, "owner.json"))
  path <- file.path(base, "ledger.json")
  ledger <- .sc_run_provider_read(path)
  guard <- if (turn) .sc_run_turn_guard(project_dir, request, spec$metadata, prepared, react_runtime) else NULL
  if (turn) ledger <- .sc_run_turn_recover_ledger(project_dir, guard$state, ledger, path)
  if (turn && isTRUE(allow_external) && !isTRUE(guard$state$config$review$allow_external))
    .sc_run_turn_error("invalid_session", "A turn cannot replace the committed project's external-transfer policy.")
  if (turn && retry) return(result("retry_refused", "Structured turns do not resend an earlier turn; resume its saved response or reconcile uncertain delivery."))
  hits <- which(vapply(ledger$entries, function(x) identical(x$request_hash, request_hash), logical(1)))
  if (length(hits)) {
    prior <- ledger$entries[[tail(hits, 1L)]]
    if (!retry || identical(prior$status, "ok")) {
      if (identical(prior$status, "dispatched")) return(result("delivery_uncertain",
        "A previous dispatch has no confirmed response and will not be resent automatically."))
      if (turn) {
        # The validated structured response is the sole content source. Never
        # return an older duplicate raw/content projection without rechecking it.
        prior$raw <- NULL
        prior$content <- NULL
        if (identical(prior$delivery, "unknown")) {
          prior$status <- "delivery_uncertain"
          prior$error <- "Delivery is uncertain; no automatic retry is allowed."
        }
        if (is.null(prior$turn_response) && !is.null(prior$withheld_response_hash)) {
          prior$status <- "private_payload"
          prior$error <- "Cached response content was withheld by privacy validation."
        }
        audit_safe <- tryCatch({
          .sc_run_turn_privacy(list(metadata = prior$response_metadata, model = prior$model_reported),
            guard$context, request$session$policy$max_payload_bytes, spec$metadata$api_key_env)
          TRUE
        }, error = function(e) FALSE)
        if (!audit_safe) {
          prior$response_metadata <- .sc_run_provider_response_metadata(NULL)
          prior$response_metadata_hash <- .sc_run_provider_hash(prior$response_metadata)
          prior$model_reported <- NULL
          ledger$entries[[tail(hits, 1L)]] <- prior
          .sc_run_provider_write(ledger, path)
        }
        if (!is.null(prior$turn_response)) {
          parsed <- .sc_run_turn_response(prior$turn_response, request, guard$context, spec$metadata,
            prior$usage)
          if (is.null(parsed$turn_response)) {
            prior$withheld_response_hash <- prior$turn_response_hash
            prior$turn_response <- NULL; prior$turn_response_hash <- NULL
            prior$content <- NULL; prior$raw <- NULL; prior$response_hash <- NULL
            prior$status <- parsed$status; prior$error <- parsed$error
            ledger$entries[[tail(hits, 1L)]] <- prior
            .sc_run_provider_write(ledger, path)
          } else if (!isTRUE(prior$accounting_issue)) {
            prior$status <- parsed$status; prior$content <- parsed$content; prior$error <- parsed$error
          }
        }
        if (.sc_run_provider_contains_secret(prior$error, spec$metadata$api_key_env))
          prior$error <- "Cached failure details were withheld."
        ledger$entries[[tail(hits, 1L)]] <- prior
        .sc_run_provider_write(ledger, path)
        prior$cached <- TRUE
        return(prior)
      }
      if (isTRUE(prior$accounting_issue)) { prior$cached <- TRUE; return(prior) }
      parsed <- if (!is.null(prior$raw)) .sc_run_provider_response_result(prior$raw, request$validator,
        unique(c(spec$metadata$api_key_env, prior$provider$api_key_env)), prior$response_metadata,
        prior$usage, prior$provider$generation$max_tokens) else
        list(status = prior$status, content = NULL, error = prior$error)
      prior$status <- parsed$status; prior$content <- parsed$content; prior$error <- parsed$error
      if (!is.null(parsed$response_metadata)) {
        prior$response_metadata <- parsed$response_metadata
        prior$response_metadata_hash <- .sc_run_provider_hash(prior$response_metadata)
        prior$response_audit <- parsed$response_audit
      }
      if (identical(parsed$status, "secret_detected")) {
        prior$raw <- NULL; prior$response_hash <- NULL
        ledger$entries[[tail(hits, 1L)]] <- prior
        .sc_run_provider_write(ledger, path)
      }
      prior$cached <- TRUE
      return(prior)
    }
    retryable <- c("invalid_response", "empty_response", "truncated_response", "reconciled_no_response")
    if (!isTRUE(prior$provider$external)) retryable <- c(retryable, "provider_error", "secret_detected")
    if (!prior$status %in% retryable ||
        !identical(prior$cost_state, "known")) return(result("retry_refused", "Retry requires a completed invalid response with known accounting; unknown dispatches need manual reconciliation."))
  }
  if (spec$metadata$external) {
    authorized <- if (turn) .sc_run_turn_strict_authorized(request, request_hash, guard$state) ||
      .sc_run_turn_authorized(request, guard$state$config) else
      identical(request$approved_payload_hash, request_hash)
    if (!isTRUE(allow_external) || !authorized)
      return(result("awaiting_external_approval", "The exact aggregate outgoing payload must be approved before external transmission."))
    unresolved <- vapply(ledger$entries, function(x) {
      if (!isTRUE(x$provider$external) || !identical(x$provider$name, spec$metadata$name)) return(FALSE)
      uncertain <- identical(x$delivery, "unknown") || x$status %in% c("dispatched", "delivery_uncertain")
      uncertain
    }, logical(1))
    if (any(unresolved)) return(result("delivery_uncertain",
      "An earlier request has uncertain delivery; it will not be resent automatically."))
  }
  if (turn) {
    sequence <- tryCatch(.sc_run_turn_sequence(request, ledger$entries, prepared), error = function(e) e)
    if (inherits(sequence, "error")) return(result(sequence$code, conditionMessage(sequence)))
  }
  # A missing built-in credential is known to precede any HTTP dispatch. Keep
  # cache reads above this check, and do not create an uncertain delivery hold.
  if (is.null(spec$fn) && spec$metadata$name %in% c("deepseek", "grok", "openai_compatible") &&
      !nzchar(trimws(Sys.getenv(spec$metadata$api_key_env))))
    return(result("needs_provider", paste0("No provider request was sent. Set ",
      spec$metadata$api_key_env, " in the analysis machine's environment, or supply an explicit chat_fn. No request was dispatched.")))
  fn <- tryCatch(if (turn) {
    if (is.function(spec$fn)) spec$fn else if (identical(spec$metadata$name, "mock")) NULL else
      .sc_run_turn_factory(spec$metadata)
  } else .sc_run_provider_fn(spec), error = function(e) e)
  if (inherits(fn, "sc_run_provider_adapter_unavailable")) return(result("provider_adapter_unavailable",
    "Provider metadata adapter does not recognize this factory; no request was dispatched."))
  if (inherits(fn, "error")) fn <- NULL
  if (is.null(fn)) return(result("needs_provider", "Supply a runtime chat_fn or configure the provider key in its environment variable."))
  entry <- list(request_hash = request_hash, provider = spec$metadata,
    attempt = length(hits) + 1L, purpose = if (turn) request$purpose else .sc_run_provider_request(request, spec$metadata$api_key_env)$purpose,
    status = "dispatched", content = NULL, raw = NULL, error = NULL, cached = FALSE,
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE), usage = NULL,
    model_reported = NULL, cost_state = "unknown", cost_usd = NULL,
    accounting_issue = FALSE,
    response_metadata = .sc_run_provider_response_metadata(NULL), response_audit = NULL)
  entry$prompt_version <- if (turn) request$session$prompt_version else
    if (is.null(request$prompt_version)) "unversioned_custom" else request$prompt_version
  entry$payload_hash <- .sc_run_provider_hash(if (turn) prepared$payload else .sc_run_provider_request(request, spec$metadata$api_key_env))
  if (turn) {
    entry$session_id <- request$session$id; entry$session_hash <- request$session$hash
    entry$cluster_id <- request$cluster_id; entry$ordinal <- as.integer(request$ordinal)
    entry$previous_response_hash <- request$previous_response_hash
    entry$turn_payload <- prepared$payload; entry$turn_payload_hash <- .sc_run_provider_hash(prepared$payload)
    entry$delivery <- "unknown"
    entry$authorization <- if (.sc_run_turn_authorized(request, guard$state$config))
      list(mode = "project", consent_hash = guard$state$config$review$transfer_consent$hash) else
      list(mode = "strict", approved_payload_hash = request$approved_payload_hash)
  }
  if (!is.null(request$transfer_scope)) {
    entry$prompt_version <- request$transfer_scope$prompt_version
    entry$transfer_categories <- request$transfer_scope$categories
  }
  ledger$entries <- append(ledger$entries, list(entry))
  index <- length(ledger$entries)
  .sc_run_provider_write(ledger, path) # dispatch is durable before any HTTP
  if (turn) {
    guard$state <- .sc_run_event(guard$state, "provider_turn_dispatched", list(
      session_id = entry$session_id, session_hash = entry$session_hash,
      cluster_id = entry$cluster_id, ordinal = entry$ordinal,
      request_hash = request_hash, payload_hash = entry$payload_hash,
      authorization = entry$authorization,
      scientific_approval = FALSE))
    .sc_run_save(project_dir, guard$state)
  }
  if (identical(getOption("scAgentKit.provider_crash"), "after_dispatch"))
    stop("Injected provider interruption after durable dispatch.")
  before <- length(.sc_run_provider_tokens())
  value <- tryCatch(if (turn) {
    again <- .sc_run_turn_prepare(request, spec$metadata)
    if (!identical(again$json, prepared$json)) .sc_run_turn_error("invalid_request", "Prepared turn changed before dispatch.")
    args <- prepared$args
    if (!is.null(request$deadline)) {
      remaining <- request$deadline - as.numeric(Sys.time())
      if (remaining <= .001) stop(structure(list(message = "The cluster deadline expired before dispatch.",
        call = NULL, code = "cluster_timeout", delivery = "not_sent"),
        class = c("agentomics_turn_error", "error", "condition")))
      args$timeout_secs <- min(args$timeout_secs, remaining)
    }
    entry$effective_timeout_seconds <- args$timeout_secs
    do.call(fn, args)
  } else fn(request$system_prompt, request$user_prompt), error = function(e) e)
  if (identical(getOption("scAgentKit.provider_crash"), "after_response"))
    stop("Injected provider interruption after response; delivery is unresolved.")
  records <- .sc_run_provider_tokens()
  records <- if (length(records) > before) records[seq.int(before + 1L, length(records))] else list()
  if (turn) {
    entry <- .sc_run_turn_settle(entry, value, request, guard$context, spec$metadata)
    entry$completed_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
    guard$state <- .sc_run_turn_commit(project_dir, guard$state, entry)
    if (identical(getOption("scAgentKit.provider_crash"), "after_turn_commit"))
      stop("Injected provider interruption after committed response; ledger recovery requires no transmission.")
    ledger$entries[[index]] <- entry
    .sc_run_provider_write(ledger, path)
    return(entry)
  }
  entry$response_metadata <- .sc_run_provider_response_metadata(
    if (inherits(value, "agentomics_turn_error")) list(response_metadata = value$metadata) else value,
    spec$metadata$api_key_env)
  entry$response_metadata_hash <- .sc_run_provider_hash(entry$response_metadata)
  if (inherits(value, "error")) {
    delivery <- if (inherits(value, "agentomics_turn_error") &&
      value$delivery %in% c("not_sent", "unknown", "received")) value$delivery else "unknown"
    entry$delivery <- delivery
    entry$status <- if (!spec$metadata$external) "provider_error" else
      switch(delivery, not_sent = "not_sent", received = "provider_response_error", "delivery_uncertain")
    entry$error <- "Provider call failed after dispatch; no automatic retry. Available usage is retained; unknown delivery requires reconciliation."
    entry$response_audit <- list(json_status = "not_received", json_error = NULL,
      truncation = if (isTRUE(entry$response_metadata$finish_reason %in% c("length", "max_tokens", "max_output_tokens")))
        "provider_reported" else "not_reported")
    if (inherits(value, "agentomics_turn_error")) {
      entry$raw_usage <- .sc_run_provider_raw_usage(value$raw_usage)
      entry$raw_usage_hash <- .sc_run_provider_hash(entry$raw_usage)
      entry$usage <- .sc_run_provider_usage(value)
      if (identical(delivery, "not_sent")) {
        entry$cost_state <- "known"; entry$cost_usd <- 0
        entry$error <- "The provider rejected the request before transmission; no fee was charged."
      } else if (identical(delivery, "received")) {
        cost <- .sc_run_provider_cost(value, entry$usage, spec$metadata)
        entry$cost_state <- cost$state; entry$cost_usd <- cost$cost_usd
        entry$accounting_issue <- (!is.null(entry$usage$output_tokens) && entry$usage$output_tokens > spec$metadata$generation$max_tokens)
        entry$error <- "The provider returned an unusable response; available usage was retained without retry."
        entry$response_audit$json_status <- "received_invalid"
        if (isTRUE(entry$accounting_issue)) {
          entry$status <- "invalid_response"
          entry$error <- "The received response exceeded the configured output token limit; response rejected."
        }
      }
    }
  } else {
    raw <- if (is.list(value)) value$content else value
    # Metadata was extracted above. Strip every arbitrary character attribute
    # before returning/caching raw text, including in RDS coordinator snapshots.
    if (is.character(raw)) raw <- as.character(raw)
    entry$raw_usage <- .sc_run_provider_raw_usage(if(is.list(value)) value$raw_usage else attr(value,"raw_usage",exact=TRUE))
    if (!is.null(entry$raw_usage)) entry$raw_usage_hash <- .sc_run_provider_hash(entry$raw_usage)
    entry$usage <- .sc_run_provider_usage(value, records)
    parsed <- .sc_run_provider_response_result(raw, request$validator, spec$metadata$api_key_env,
      entry$response_metadata, entry$usage, spec$metadata$generation$max_tokens)
    entry$status <- parsed$status; entry$content <- parsed$content; entry$error <- parsed$error
    entry$response_audit <- parsed$response_audit
    if (is.character(raw) && length(raw) == 1L && !is.na(raw) && parsed$status != "secret_detected") {
      entry$raw <- raw; entry$response_hash <- .sc_run_provider_hash(raw)
    }
    model <- if (is.list(value)) value$model else attr(value, "model", exact = TRUE)
    if (is.null(model) && length(records)) model <- records[[length(records)]]$model
    if (is.character(model) && length(model) == 1L && !is.na(model) &&
        identical(model, .sc_run_provider_redact(model, spec$metadata$api_key_env))) entry$model_reported <- substr(model, 1, 200)
    cost <- .sc_run_provider_cost(value, entry$usage, spec$metadata)
    entry$cost_state <- cost$state; entry$cost_usd <- cost$cost_usd
    entry$accounting_issue <- (!is.null(entry$usage$output_tokens) && entry$usage$output_tokens > spec$metadata$generation$max_tokens)
    if (entry$accounting_issue) {
      entry$status <- "invalid_response"
      entry$error <- "Provider output usage exceeded the configured token limit; response rejected."
    }
  }
  # Local functions cannot incur provider fees; failures still require an
  # explicit retry, and their safe failure is cached here by default.
  if (!spec$metadata$external) { entry$cost_state <- "known"; entry$cost_usd <- 0 }
  entry$completed_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  ledger$entries[[index]] <- entry
  .sc_run_provider_write(ledger, path)
  entry
}

#' Reconcile a provider ledger entry with unresolved cost or delivery
#'
#' A single request or structured turn records costs after the response. An
#' uncertain delivery prevents new external requests to that provider. After
#' checking the provider's billing records, record the confirmed charge here.
#' Reconciliation never resends a request. A single request without a response
#' becomes `reconciled_no_response`; a retry requires independently confirmed
#' delivery and an explicit `retry = TRUE`. Structured turns never resend.
#' Recording a charge alone does not resolve uncertain delivery. Structured
#' reconciliation commits a new immutable receipt with the confirmed invoice.
#'
#' @param project_dir Run directory.
#' @param request_hash Exact 64-character request hash of the unresolved entry.
#' @param cost_usd Actual charge in USD confirmed by the analyst (0 if none).
#' @param reviewer,reason Analyst identity and how cost/delivery were verified.
#' @param delivery NULL preserves uncertainty; not_sent or received requires independent provider confirmation.
#' @return Invisibly, the reconciled ledger entry.
#' @export
sc_run_provider_reconcile <- function(project_dir, request_hash, cost_usd, reviewer, reason, delivery = NULL) {
  .sc_project_format_entry(project_dir)
  if (!is.null(delivery) && (!is.character(delivery) || length(delivery) != 1L || !delivery %in% c("not_sent", "received")))
    stop("delivery must be NULL, not_sent or received, confirmed by the operator.", call. = FALSE)
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  if (!is.character(request_hash) || length(request_hash) != 1L || !grepl("^[a-f0-9]{64}$", request_hash))
    stop("`request_hash` must be one exact 64-character lowercase hex hash.", call. = FALSE)
  cost_usd <- .sc_run_provider_number(cost_usd, "cost_usd")
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- if (file.exists(file.path(root, "state.rds"))) .sc_run_load(root) else NULL
  lock <- file.path(root, "provider", ".dispatch-lock")
  if (!dir.create(lock, showWarnings = FALSE))
    stop("Another provider dispatch holds the project lock; reconcile after it finishes.", call. = FALSE)
  token <- .sc_run_provider_hash(list(Sys.getpid(), as.character(Sys.time()), tempfile()))
  on.exit(.sc_run_provider_release(lock, token), add = TRUE)
  .sc_run_provider_write(list(token = token, pid = Sys.getpid(), host = unname(Sys.info()["nodename"]),
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE)), file.path(lock, "owner.json"))
  path <- file.path(root, "provider", "ledger.json")
  ledger <- .sc_run_provider_read(path)
  if (!is.null(state)) ledger <- .sc_run_turn_recover_ledger(root, state, ledger, path)
  hits <- which(vapply(ledger$entries, function(x) identical(x$request_hash, request_hash), logical(1)))
  if (!length(hits)) stop("No provider ledger entry has this request hash.", call. = FALSE)
  index <- tail(hits, 1L); entry <- ledger$entries[[index]]
  if (!isTRUE(entry$provider$external) ||
      (identical(entry$cost_state, "known") && !isTRUE(entry$accounting_issue) &&
       (is.null(delivery) || !identical(entry$delivery, "unknown"))))
    stop("This ledger entry has no unresolved accounting or delivery; only external entries with unknown cost, unknown delivery or an accounting issue are reconciled.", call. = FALSE)
  previous <- list(status = entry$status, delivery = entry$delivery, cost_state = entry$cost_state,
    cost_usd = entry$cost_usd, accounting_issue = isTRUE(entry$accounting_issue))
  previous_entry_hash <- if (!is.null(entry$session_id)) .sc_run_provider_hash(entry) else NULL
  if (entry$status %in% c("dispatched", "delivery_uncertain")) entry$status <- "reconciled_no_response"
  if (!is.null(delivery)) entry$delivery <- delivery
  entry$cost_state <- "known"; entry$cost_usd <- cost_usd
  entry$accounting_issue <- FALSE
  entry$reconciliation <- list(reviewer = reviewer, reason = reason, previous = previous, confirmed_delivery = delivery,
    reconciled_at = format(Sys.time(), tz = "UTC", usetz = TRUE))
  if (!is.null(entry$session_id)) {
    entry$reconciliation$previous_entry_hash <- previous_entry_hash
    entry$actual_cost_usd <- cost_usd; entry$cost_estimated <- FALSE
    entry$cost_basis <- "analyst_confirmed_invoice"
    entry$turn_outcome <- .sc_run_turn_outcome(entry)
    entry$turn_outcome_hash <- .sc_run_provider_hash(entry$turn_outcome)
    state <- .sc_run_turn_commit(root, state, entry, "provider_reconciled",
      list(previous = previous, reviewer = reviewer, reason = reason))
    ledger$entries[[index]] <- entry
    .sc_run_provider_write(ledger, path)
    return(invisible(entry))
  }
  ledger$entries[[index]] <- entry
  .sc_run_provider_write(ledger, path)
  if (!is.null(state)) {
    state <- .sc_run_event(state, "provider_reconciled", list(request_hash = request_hash,
      provider = entry$provider$name, cost_usd = cost_usd, previous = previous, reviewer = reviewer, reason = reason))
    .sc_run_save(root, state)
  }
  invisible(entry)
}

# Preserve provider usage field names and nested numeric detail, never the HTTP
# envelope, headers, arbitrary strings, key material or provider callback frame.
.sc_run_provider_raw_usage <- function(value) {
  allowed <- c('prompt_tokens','completion_tokens','total_tokens','input_tokens','output_tokens',
    'prompt_cache_hit_tokens','prompt_cache_miss_tokens','cache_read_input_tokens',
    'cache_creation_input_tokens','cached_tokens','prompt_tokens_details','completion_tokens_details',
    'input_tokens_details','output_tokens_details','reasoning_tokens','audio_tokens',
    'text_tokens','image_tokens','video_tokens','accepted_prediction_tokens','rejected_prediction_tokens',
    'cost_in_usd_ticks')
  clean <- function(x, depth=0L) {
    if (is.numeric(x) && length(x)==1L && is.finite(x) && x>=0 && x==floor(x)) return(as.numeric(x))
    if (!is.list(x) || is.null(names(x)) || depth>3L || anyDuplicated(names(x))) return(NULL)
    out <- lapply(x[intersect(names(x),allowed)],clean,depth=depth+1L)
    Filter(Negate(is.null),out)
  }
  if (!is.list(value)) return(NULL)
  clean(value)
}
