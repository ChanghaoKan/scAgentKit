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
  gsub("(?i)(sk-|xai-)[A-Za-z0-9_-]{12,}", "[REDACTED]", x, perl = TRUE)
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
  fields <- c("name", "model", "generation", "external", "reservation_usd", "pricing", "api_key_env")
  if (!is.list(provider) || is.null(names(provider)) || anyDuplicated(names(provider)) ||
      any(!names(provider) %in% fields)) {
    stop("Provider configuration accepts only name, model, generation, external, reservation_usd, pricing and api_key_env; credentials belong in the runtime environment.")
  }
  name <- .sc_run_provider_scalar(provider$name, "name", "^[A-Za-z0-9._-]+$")
  name <- tolower(name)
  defaults <- switch(name, deepseek = "deepseek-flash",
    grok = "grok-4.20-0309-non-reasoning", manual = "manual", "unspecified")
  model <- .sc_run_provider_scalar(if (is.null(provider$model)) defaults else provider$model,
    "model", "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$")
  external <- if (is.null(provider$external)) !name %in% c("manual", "mock", "local") else provider$external
  if (!is.logical(external) || length(external) != 1L || is.na(external)) stop("`external` must be TRUE or FALSE.")
  if (name %in% c("deepseek", "grok") && !external) stop("Built-in remote providers are external.")
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
        !value %in% c("none", "minimal", "low", "medium", "high")) stop("Unsupported reasoning_effort.")
  }
  generation <- generation[sort(names(generation))]
  reserve <- if (is.null(provider$reservation_usd)) if (external) 0.05 else 0 else provider$reservation_usd
  reserve <- .sc_run_provider_number(reserve, "reservation_usd")
  if (external && reserve <= 0) stop("External calls require a positive `reservation_usd`.")
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
    reservation_usd = reserve, pricing = pricing, api_key_env = env)
  metadata <- .sc_run_provider_plain(metadata)
  if (!identical(.sc_run_provider_json(metadata), .sc_run_provider_redact(.sc_run_provider_json(metadata), env)))
    stop("Credential-like provider metadata is forbidden.")
  list(metadata = metadata, fn = chat_fn)
}

.sc_run_provider_request <- function(request, env_names = NULL) {
  fields <- c("system_prompt", "user_prompt", "purpose", "evidence_hash", "approved_payload_hash", "validator")
  if (!is.list(request) || is.null(names(request)) || anyDuplicated(names(request)) ||
      any(!names(request) %in% fields)) stop("Invalid coordinator provider request fields.")
  system <- .sc_run_provider_scalar(request$system_prompt, "system_prompt")
  user <- .sc_run_provider_scalar(request$user_prompt, "user_prompt")
  if (nchar(enc2utf8(system), type = "bytes") + nchar(enc2utf8(user), type = "bytes") > 100000L)
    stop("Aggregate provider request exceeds 100,000 bytes.")
  if (!identical(c(system, user), .sc_run_provider_redact(c(system, user), env_names))) stop("Credential-like request content is forbidden.")
  if (!is.null(request$validator) && !is.function(request$validator)) stop("Request validator must be a function.")
  purpose <- if (is.null(request$purpose)) "analysis_decision" else .sc_run_provider_scalar(request$purpose, "purpose")
  if (!identical(purpose, .sc_run_provider_redact(purpose, env_names))) stop("Credential-like request purpose is forbidden.")
  evidence <- request$evidence_hash
  if (!is.null(evidence)) evidence <- .sc_run_provider_scalar(evidence, "evidence_hash", "^[a-f0-9]{64}$")
  payload <- list(system_prompt = system, user_prompt = user, purpose = purpose, evidence_hash = evidence)
  serialized <- .sc_run_provider_json(payload)
  if (!identical(serialized, .sc_run_provider_redact(serialized, env_names))) stop("Credential-like request content is forbidden.")
  payload
}

# Root approves this exact payload hash, which includes the transmitted text,
# model and generation settings, rather than just a summary's file name.
.sc_run_request_hash <- function(request, provider = NULL, chat_fn = NULL) {
  spec <- .sc_run_provider_spec(provider, chat_fn)$metadata
  .sc_run_provider_hash(list(schema = "scagentkit.provider-request.v1",
    provider = spec[c("name", "model", "generation", "external")],
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

.sc_run_provider_read <- function(path) {
  if (!file.exists(path)) return(list(schema = "scagentkit.provider-ledger.v1", entries = list()))
  ledger <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(ledger) || !identical(ledger$schema, "scagentkit.provider-ledger.v1") ||
      !is.list(ledger$entries)) stop("Provider ledger is invalid; dispatch refused.")
  for (entry in ledger$entries) {
    if (!is.list(entry) || !is.character(entry$request_hash) || length(entry$request_hash) != 1L ||
        !grepl("^[a-f0-9]{64}$", entry$request_hash) ||
        !is.numeric(entry$charged_or_held_usd) || length(entry$charged_or_held_usd) != 1L ||
        !is.finite(entry$charged_or_held_usd) || entry$charged_or_held_usd < 0)
      stop("Provider ledger entry is invalid; dispatch refused.")
    if (!is.null(entry$raw) && !identical(entry$response_hash, .sc_run_provider_hash(entry$raw)))
      stop("Provider cached response hash mismatch; dispatch refused.")
    if (!is.null(entry$response_metadata_hash) &&
        !identical(entry$response_metadata_hash, .sc_run_provider_hash(entry$response_metadata)))
      stop("Provider cached response metadata hash mismatch; dispatch refused.")
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
  body(adapted) <- bquote({
    .sc_response_frame <- environment()
    .sc_response_result <- tryCatch(.(original), error = function(.sc_response_error) {
      .sc_safe_metadata <- .(capture)(.sc_response_frame, .(env_names))
      stop(structure(list(message = "Provider call returned an error; HTTP error body discarded.",
        call = NULL, response_metadata = .sc_safe_metadata),
        class = c("sc_run_provider_transport_error", "error", "condition")))
    })
    attr(.sc_response_result, "response_metadata") <- .(capture)(.sc_response_frame, .(env_names))
    .sc_response_result
  })
  adapted
}

.sc_run_provider_fn <- function(spec) {
  if (is.function(spec$fn)) return(spec$fn)
  m <- spec$metadata
  if (!m$name %in% c("deepseek", "grok")) return(NULL)
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
  fn <- do.call(getExportedValue("agentomicsCore", paste0("chat_", m$name)), args)
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
    return(list(state = "known", cost_usd = cost))
  }
  list(state = "unknown", cost_usd = NULL)
}

# One dispatch per call. Retry is an explicit action and is accepted only after
# a completed, accounted-for invalid response. An interrupted/unknown dispatch
# is never sent again automatically, even in a fresh R process.
.sc_run_call <- function(project_dir, request, provider = NULL, chat_fn = NULL,
                         budget = 0, allow_external = FALSE, retry = FALSE) {
  spec <- .sc_run_provider_spec(provider, chat_fn)
  request_hash <- .sc_run_request_hash(request, spec$metadata)
  budget <- .sc_run_provider_number(budget, "budget")
  if (!is.logical(retry) || length(retry) != 1L || is.na(retry)) stop("`retry` must be TRUE or FALSE.")
  if (!is.character(project_dir) || length(project_dir) != 1L || is.na(project_dir) || !dir.exists(project_dir))
    stop("Provider project directory must already exist.")
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
  hits <- which(vapply(ledger$entries, function(x) identical(x$request_hash, request_hash), logical(1)))
  if (length(hits)) {
    prior <- ledger$entries[[tail(hits, 1L)]]
    if (!retry || identical(prior$status, "ok")) {
      if (identical(prior$status, "dispatched")) return(result("accounting_hold", "A previous dispatch has no confirmed response; its reservation remains held and it will not be resent."))
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
    retryable <- c("invalid_response", "empty_response", "truncated_response")
    if (!isTRUE(prior$provider$external)) retryable <- c(retryable, "provider_error", "secret_detected")
    if (!prior$status %in% retryable ||
        !identical(prior$cost_state, "known")) return(result("retry_refused", "Retry requires a completed invalid response with known accounting; unknown dispatches need manual reconciliation."))
  }
  if (spec$metadata$external) {
    if (!isTRUE(allow_external) || !identical(request$approved_payload_hash, request_hash))
      return(result("awaiting_external_approval", "The exact aggregate outgoing payload must be approved before external transmission."))
    unresolved <- vapply(ledger$entries, function(x) isTRUE(x$provider$external) &&
      identical(x$provider$name, spec$metadata$name) && (!identical(x$cost_state, "known") || isTRUE(x$accounting_issue)), logical(1))
    if (any(unresolved)) return(result("accounting_hold", "This provider has unresolved usage or cost; cached responses remain available, but new external dispatch is paused."))
  }
  total <- sum(vapply(ledger$entries, function(x) x$charged_or_held_usd, numeric(1)))
  reserve <- spec$metadata$reservation_usd
  if (total + reserve > budget + 1e-12) return(result("budget_stop", "Project budget cannot cover this request reservation.", list(charged_or_held_usd = total, requested_reservation_usd = reserve)))
  # A missing built-in credential is known to precede any HTTP dispatch. Keep
  # cache reads above this check, and do not create an uncertain delivery hold.
  if (is.null(spec$fn) && spec$metadata$name %in% c("deepseek", "grok") &&
      !nzchar(trimws(Sys.getenv(spec$metadata$api_key_env))))
    return(result("needs_provider", paste0("No provider request was sent. Set ",
      spec$metadata$api_key_env, " in the analysis machine's environment, or supply an explicit chat_fn. No reservation was charged or held.")))
  fn <- tryCatch(.sc_run_provider_fn(spec), error = function(e) e)
  if (inherits(fn, "sc_run_provider_adapter_unavailable")) return(result("provider_adapter_unavailable",
    "Provider metadata adapter does not recognize this factory; no request was dispatched."))
  if (inherits(fn, "error")) fn <- NULL
  if (is.null(fn)) return(result("needs_provider", "Supply a runtime chat_fn or configure the provider key in its environment variable."))
  entry <- list(request_hash = request_hash, provider = spec$metadata,
    attempt = length(hits) + 1L, purpose = .sc_run_provider_request(request, spec$metadata$api_key_env)$purpose,
    status = "dispatched", content = NULL, raw = NULL, error = NULL, cached = FALSE,
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE), usage = NULL,
    model_reported = NULL, cost_state = "unknown", cost_usd = NULL,
    reservation_usd = reserve, charged_or_held_usd = reserve, accounting_issue = FALSE,
    response_metadata = .sc_run_provider_response_metadata(NULL), response_audit = NULL)
  ledger$entries <- append(ledger$entries, list(entry))
  index <- length(ledger$entries)
  .sc_run_provider_write(ledger, path) # reservation is durable before any HTTP
  if (identical(getOption("scAgentKit.provider_crash"), "after_dispatch"))
    stop("Injected provider interruption after durable dispatch reservation.")
  before <- length(.sc_run_provider_tokens())
  value <- tryCatch(fn(request$system_prompt, request$user_prompt), error = function(e) e)
  if (identical(getOption("scAgentKit.provider_crash"), "after_response"))
    stop("Injected provider interruption after response; reservation remains held.")
  records <- .sc_run_provider_tokens()
  records <- if (length(records) > before) records[seq.int(before + 1L, length(records))] else list()
  entry$response_metadata <- .sc_run_provider_response_metadata(value, spec$metadata$api_key_env)
  entry$response_metadata_hash <- .sc_run_provider_hash(entry$response_metadata)
  if (inherits(value, "error")) {
    entry$status <- if (spec$metadata$external) "delivery_uncertain" else "provider_error"
    entry$error <- "Provider call failed after dispatch; no automatic retry. Reservation held until usage is reconciled."
    entry$response_audit <- list(json_status = "not_received", json_error = NULL,
      truncation = if (isTRUE(entry$response_metadata$finish_reason %in% c("length", "max_tokens", "max_output_tokens")))
        "provider_reported" else "not_reported")
  } else {
    raw <- if (is.list(value)) value$content else value
    # Metadata was extracted above. Strip every arbitrary character attribute
    # before returning/caching raw text, including in RDS coordinator snapshots.
    if (is.character(raw)) raw <- as.character(raw)
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
    if (cost$state == "known") entry$charged_or_held_usd <- cost$cost_usd
    entry$accounting_issue <- entry$charged_or_held_usd > reserve + 1e-12 ||
      (!is.null(entry$usage$output_tokens) && entry$usage$output_tokens > spec$metadata$generation$max_tokens)
    if (entry$accounting_issue) {
      entry$status <- "budget_stop"
      entry$error <- "Provider cost or output usage exceeded its reservation or configured cap; further dispatch is paused."
    }
  }
  # Local functions cannot incur provider fees; failures still require an
  # explicit retry, and their safe failure is cached here by default.
  if (!spec$metadata$external) { entry$cost_state <- "known"; entry$cost_usd <- 0; entry$charged_or_held_usd <- 0 }
  entry$completed_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  ledger$entries[[index]] <- entry
  .sc_run_provider_write(ledger, path)
  entry
}
