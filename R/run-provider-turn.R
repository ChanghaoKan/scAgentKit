# One structured turn, with the existing coordinator's state and provider ledger.
# This module never executes a tool, loops over turns, or creates an approval.
.sc_run_turn_error <- function(code, message) {
  stop(structure(list(message = message, call = NULL, code = code),
    class = c("sc_run_turn_error", "error", "condition")))
}

.sc_run_capacity_bytes <- function(value) {
  if (identical(value, "unlimited")) return(Inf)
  n <- .sc_run_provider_number(value, "max_payload_bytes", 1, 1000000)
  if (n != floor(n)) stop("Request byte limit must be an integer or unlimited.")
  n
}

.sc_run_turn_policy <- function(value = NULL) {
  defaults <- list(mode = "auto", tools = names(.sc_run_react_tools()), act_enabled = TRUE,
    max_steps = 60L, max_steps_per_cluster = 6L, cluster_timeout_seconds = 180,
    tool_timeout_seconds = 60, max_payload_bytes = "unlimited")
  if (!is.null(value)) {
    if (!is.list(value) || is.null(names(value)) || anyDuplicated(names(value)) ||
        any(!names(value) %in% names(defaults)))
      stop("ReAct scope accepts only its read-only tools and bounded limits.", call. = FALSE)
    defaults[names(value)] <- value
  }
  value <- .sc_run_provider_plain(defaults)
  if (!is.character(value$mode) || length(value$mode) != 1L ||
      is.na(value$mode) || !value$mode %in% c("auto", "all", "off"))
    stop("ReAct mode must be auto, all or off.", call. = FALSE)
  selected <- if (!length(value$tools)) character() else unlist(value$tools, use.names = FALSE)
  if (!is.character(selected) || anyNA(selected) || anyDuplicated(selected) ||
      any(!selected %in% names(.sc_run_react_tools())) ||
      !is.logical(value$act_enabled) || length(value$act_enabled) != 1L || is.na(value$act_enabled))
    stop("Invalid read-only ReAct tool scope.", call. = FALSE)
  if (!value$act_enabled) selected <- setdiff(selected, "act_lookup")
  value$tools <- as.list(sort(selected, method = "radix"))
  .sc_run_capacity_bytes(value$max_payload_bytes)
  for (field in c("max_steps", "max_steps_per_cluster")) {
    limit <- 10000
    number <- .sc_run_provider_number(value[[field]], field, 1, limit)
    if (number != floor(number)) stop("ReAct count limits must be integers.", call. = FALSE)
    value[[field]] <- as.integer(number)
  }
  value$cluster_timeout_seconds <- .sc_run_provider_number(value$cluster_timeout_seconds,
    "cluster_timeout_seconds", 1, 3600)
  value$tool_timeout_seconds <- .sc_run_provider_number(value$tool_timeout_seconds,
    "tool_timeout_seconds", 1, 60)
  if (value$max_steps_per_cluster > value$max_steps)
    stop("Per-cluster turn limit cannot exceed the session limit.", call. = FALSE)
  value
}

.sc_run_turn_profile <- function(provider) {
  if (.sc_run_xai_native(provider))
    return(list(schema = "scagentkit.turn-capability.v1", model = provider$model,
      max_output_tokens = 128000, protocol = "agentomics.turn.v2",
      output_cap_basis = "local_cap_at_documented_default_visible_only",
      native_protocol = "xai.responses.v1", qualification = "synthetic_smoke_verified",
      verification_date = "2026-10-20", formal_support = FALSE,
      reasoning_effort = if (is.null(provider$generation$reasoning_effort)) "high" else
        provider$generation$reasoning_effort))
  if (!provider$external && identical(provider$name, "mock"))
    return(list(schema = "scagentkit.turn-capability.v1", model = provider$model,
      max_output_tokens = 393216, protocol = "agentomics.turn.v1"))
  if (!identical(provider$name, "deepseek") || !identical(provider$model, "deepseek-flash"))
    .sc_run_turn_error("unsupported_provider", "This structured adapter supports DeepSeek Flash or an offline mock; other providers require their own adapter.")
  list(schema = "scagentkit.turn-capability.v1", model = "deepseek-flash",
    max_output_tokens = 393216, protocol = "agentomics.turn.v1", thinking = "disabled")
}

.sc_run_turn_factory <- function(provider) {
  .sc_run_turn_profile(provider)
  if (.sc_run_xai_native(provider)) return(.sc_run_xai_factory(provider))
  g <- provider$generation
  if (!identical(g$temperature, 0) ||
      (provider$external && !identical(g$thinking$type, "disabled")) ||
      length(setdiff(names(g), c("temperature", "max_tokens", "timeout_secs", "thinking", "response_format"))))
    .sc_run_turn_error("unsupported_generation", "Structured turns require temperature zero, thinking disabled, and the supported bounded generation settings.")
  if (identical(provider$name, "mock")) return(agentomicsCore::make_turn_fn_openai_compatible(
    "https://offline.invalid/v1", model = provider$model, api_key_env = "",
    max_tokens = g$max_tokens, timeout_secs = g$timeout_secs, temperature = 0))
  # JSON-only completion mode belongs to the old one-shot interface. The turn
  # wire format permits both assistant tool calls and a final JSON text reply.
  agentomicsCore::turn_deepseek(model = provider$model, api_key_env = provider$api_key_env,
    max_tokens = g$max_tokens, timeout_secs = g$timeout_secs)
}

.sc_run_turn_session <- function(root, prompt_version, prompt_hash, policy = NULL,
                                  project_lock_owner = NULL, react_runtime = NULL) {
  root <- .sc_run_root(root)
  if (is.null(project_lock_owner)) {
    owner <- .sc_run_lock(root)
    on.exit(.sc_run_release(root, owner), add = TRUE)
  } else {
    owner <- readRDS(file.path(root, ".run-lock", "owner.rds"))
    if (!identical(owner, project_lock_owner) || !identical(owner$pid, Sys.getpid()))
      .sc_run_turn_error("invalid_session", "The session requires the current coordinator lock.")
  }
  context <- if (is.null(react_runtime)) .sc_run_react_context(root) else {
    .sc_run_react_worker_check(react_runtime)
    react_runtime$context
  }
  state <- .sc_run_load(root, verify = FALSE)
  .sc_run_provider_scalar(prompt_version, "prompt_version", "^[A-Za-z0-9._-]{1,80}$")
  .sc_run_provider_scalar(prompt_hash, "prompt_hash", "^[a-f0-9]{64}$")
  if (is.null(policy)) policy <- state$config$react
  if (is.null(policy)) policy <- state$config$review$transfer_consent$react_scope$policy
  policy <- .sc_run_turn_policy(policy)
  provider <- state$config$provider
  profile <- .sc_run_turn_profile(provider)
  invisible(.sc_run_turn_factory(provider))
  registry <- .sc_run_react_tools()
  tools <- lapply(unlist(policy$tools, use.names = FALSE), function(name)
    list(type = "function", `function` = list(name = name, parameters = registry[[name]]$parameters)))
  if (!length(tools)) tools <- NULL
  record <- list(schema = "scagentkit.react-session.v1", project_id = state$project_id,
    input_hash = context$input_hash, binding = context$binding,
    clusters = as.list(context$clusters), provider_hash = .sc_run_provider_hash(provider),
    prompt_version = prompt_version, prompt_hash = prompt_hash, policy = policy,
    tools = tools, tools_hash = .sc_run_provider_hash(tools),
    capability_profile = profile, capability_hash = .sc_run_provider_hash(profile),
    cost_mode = "posthoc",
    created_revision = state$revision,
    authority = "Bound read-only evidence session; no scientific approval or tool execution.")
  record$id <- paste0("session-", .sc_run_provider_hash(record))
  record$hash <- .sc_run_provider_hash(record)
  key <- paste0("react_session_", record$id)
  state <- .sc_run_put(root, state, key, record)
  state <- .sc_run_event(state, "react_session_prepared", list(session_id = record$id,
    session_hash = record$hash, checkpoint = state$files[[key]],
    provider_dispatch = "not_sent", scientific_approval = FALSE))
  .sc_run_save(root, state)
  record
}

.sc_run_turn_request <- function(session, messages, cluster_id, ordinal,
                                  previous_response_hash = NULL) {
  list(schema = "scagentkit.provider-turn.v1", purpose = "annotation_react",
    session = session, messages = messages, cluster_id = cluster_id,
    ordinal = ordinal, previous_response_hash = previous_response_hash)
}

.sc_run_turn_prepare <- function(request, provider) {
  allowed <- c("schema", "purpose", "session", "messages", "cluster_id", "ordinal",
    "previous_response_hash", "approved_payload_hash", "timeout_seconds", "deadline")
  if (!is.list(request) || is.null(names(request)) || anyDuplicated(names(request)) ||
      any(!names(request) %in% allowed) || !identical(request$schema, "scagentkit.provider-turn.v1") ||
      !identical(request$purpose, "annotation_react"))
    .sc_run_turn_error("invalid_request", "Invalid structured-turn request.")
  session <- request$session
  if (!is.list(session) || !identical(session$schema, "scagentkit.react-session.v1") ||
      !identical(session$hash, .sc_run_provider_hash(session[setdiff(names(session), "hash")])) ||
      !identical(session$provider_hash, .sc_run_provider_hash(provider)) ||
      !identical(session$policy, .sc_run_turn_policy(session$policy)) ||
      !identical(session$tools_hash, .sc_run_provider_hash(session$tools)) ||
      !identical(session$cost_mode, "posthoc") ||
      !identical(session$capability_hash, .sc_run_provider_hash(session$capability_profile)))
    .sc_run_turn_error("invalid_session", "The structured-turn session binding is invalid.")
  .sc_run_provider_scalar(request$cluster_id, "cluster_id")
  if (!request$cluster_id %in% unlist(session$clusters, use.names = FALSE))
    .sc_run_turn_error("invalid_request", "The turn refers to a foreign cluster.")
  ordinal <- .sc_run_provider_number(request$ordinal, "ordinal", 1, session$policy$max_steps)
  if (ordinal != floor(ordinal)) .sc_run_turn_error("invalid_request", "Turn ordinal must be an integer.")
  if (!is.null(request$previous_response_hash))
    .sc_run_provider_scalar(request$previous_response_hash, "previous_response_hash", "^[a-f0-9]{64}$")
  profile <- .sc_run_turn_profile(provider)
  if (!identical(profile, session$capability_profile))
    .sc_run_turn_error("unsupported_provider", "The adapter capability profile changed; prepare a new bound session.")
  g <- provider$generation
  if (g$max_tokens > profile$max_output_tokens)
    .sc_run_turn_error("invalid_output_cap", "The output limit exceeds the qualified model bound.")
  fn <- .sc_run_turn_factory(provider)
  args <- list(messages = request$messages, tools = session$tools,
    tool_choice = if (is.null(session$tools)) NULL else "auto",
    parallel_tool_calls = if (is.null(session$tools)) NULL else FALSE,
    max_tokens = g$max_tokens,
    timeout_secs = min(g$timeout_secs, session$policy$cluster_timeout_seconds))
  if (.sc_run_xai_native(provider)) args <- list(input = request$messages,
    tools = session$tools, max_tokens = g$max_tokens,
    timeout_secs = min(g$timeout_secs, session$policy$cluster_timeout_seconds))
  if (!is.null(request$timeout_seconds)) args$timeout_secs <- min(args$timeout_secs,
    .sc_run_provider_number(request$timeout_seconds, "timeout_seconds", .001,
      session$policy$cluster_timeout_seconds))
  prepared <- do.call(agentomicsCore::prepare_turn_request, c(list(turn_fn = fn), args))
  bytes <- nchar(enc2utf8(prepared$json), type = "bytes")
  if (bytes > .sc_run_capacity_bytes(session$policy$max_payload_bytes))
    .sc_run_turn_error("payload_too_large", "The complete conversation exceeds its authorized byte limit.")
  payload <- list(schema = request$schema, purpose = request$purpose,
    session_id = session$id, session_hash = session$hash, cost_mode = "posthoc",
    cluster_id = request$cluster_id, ordinal = as.integer(ordinal),
    previous_response_hash = request$previous_response_hash,
    prompt_version = session$prompt_version, prompt_hash = session$prompt_hash,
    endpoint = if (.sc_run_xai_native(provider)) "https://api.x.ai/v1/responses" else
      if (provider$external) "https://api.deepseek.com/v1/chat/completions" else "offline-mock",
    wire_json = prepared$json)
  if (!is.null(request$timeout_seconds)) payload$timeout_seconds <- args$timeout_secs
  if (!is.null(request$deadline)) payload$deadline <-
    .sc_run_provider_number(request$deadline, "deadline", 0)
  list(args = args, body = prepared$body, json = prepared$json, payload = payload,
    request_hash = .sc_run_provider_hash(payload), bytes = bytes)
}

.sc_run_turn_privacy <- function(value, context, max_bytes, env_names = NULL) {
  if (nchar(.sc_run_provider_json(value), type = "bytes") > (if (is.numeric(max_bytes) && is.infinite(max_bytes)) max_bytes else .sc_run_capacity_bytes(max_bytes)))
    .sc_run_turn_error("payload_too_large", "The complete conversation or response exceeds its byte limit.")
  strings <- character()
  forbidden <- c("cell_id", "cell_ids", "barcode", "barcodes", "counts_matrix",
    "expression_matrix", "per_cell", "cell_metadata", "file_path", "filepath",
    "source_path", "local_path")
  walk <- function(x, depth = 0L) {
    if (depth > 24L) .sc_run_turn_error("invalid_request", "Nested conversation data exceeds its inspection limit.")
    if (is.null(x)) return(invisible(NULL))
    if (is.list(x)) {
      if (!is.null(names(x))) {
        if (any(tolower(names(x)) %in% forbidden))
          .sc_run_turn_error("private_payload", "Cell-level data or file references were withheld.")
        strings <<- c(strings, names(x))
      } else if (length(x) >= 1L && all(vapply(x, function(row)
          is.list(row) && is.null(names(row)) && length(row) > 1L &&
            all(vapply(row, function(v) is.numeric(v) && length(v) == 1L, logical(1))), logical(1))))
        .sc_run_turn_error("private_payload", "Matrix-shaped cell-level data were withheld.")
      lapply(x, walk, depth = depth + 1L)
    } else if (is.character(x)) {
      strings <<- c(strings, x)
      for (s in x) if (length(s) == 1L && !is.na(s)) {
        encoded <- grepl("\\\\u[0-9A-Fa-f]{0,4}|\\\\/|\\\\\\\\", s)
        if (grepl("^\\s*[\\[{\"]", s)) {
          decoded <- tryCatch(list(value = jsonlite::fromJSON(s, simplifyVector = FALSE)),
            error = function(e) NULL)
          if (is.null(decoded) && encoded)
            .sc_run_turn_error("private_payload", "Uninspectable escaped content was withheld.")
          if (!is.null(decoded) && !identical(decoded$value, s)) walk(decoded$value, depth + 1L)
        } else if (encoded) {
          # Escaped fragments outside valid JSON cannot bypass the identifier scan.
          .sc_run_turn_error("private_payload", "Uninspectable escaped content was withheld.")
        }
      }
    }
    invisible(NULL)
  }
  walk(value)
  if (.sc_run_provider_contains_secret(strings, env_names))
    .sc_run_turn_error("private_payload", "Credential-like content was withheld before transmission.")
  if (anyNA(strings)) .sc_run_turn_error("invalid_request", "Conversation text must not contain missing values.")
  tokens <- unlist(strsplit(strings, "[^[:alnum:]_.:-]+"), use.names = FALSE)
  tokens <- sub("[.:-]+$", "", tokens)
  ids <- context$private_ids
  if (any(strings %in% ids) || any(tokens %in% ids[nchar(ids) >= 4L]) ||
      any(grepl("(^|[^[:alnum:]_])(/[^/[:space:]]|~/|\\.{1,2}/|[A-Za-z]:[\\\\/]|file://)", strings)) ||
      any(grepl("(^|[^[:alnum:]_])[[:alnum:]_.-]+(/[[:alnum:]_.-]+)+\\.[[:alnum:]]{1,8}($|[^[:alnum:]_])", strings)) ||
      any(grepl(context$root, strings, fixed = TRUE)))
    .sc_run_turn_error("private_payload", "A private cell identifier or local path was withheld before transmission.")
  invisible(TRUE)
}

.sc_run_turn_guard <- function(root, request, provider, prepared, react_runtime = NULL) {
  context <- if (is.null(react_runtime)) .sc_run_react_context(root) else {
    .sc_run_react_worker_check(react_runtime)
    if (!identical(root, react_runtime$context$root))
      .sc_run_turn_error("invalid_session", "Foreign evidence worker.")
    react_runtime$context
  }
  state <- .sc_run_load(root, verify = FALSE)
  session <- request$session; key <- paste0("react_session_", session$id)
  if (is.null(state$files[[key]]) ||
      !identical(.sc_run_get(root, state, key), session) ||
      !identical(session$input_hash, context$input_hash) ||
      !identical(session$binding, context$binding) ||
      !identical(session$provider_hash, .sc_run_provider_hash(state$config$provider)) ||
      !identical(provider, state$config$provider))
    .sc_run_turn_error("invalid_session", "The turn does not match the current committed scientific session.")
  .sc_run_transfer_privacy_check(state$config)
  .sc_run_turn_privacy(if (.sc_run_xai_native(provider)) .sc_run_xai_inspectable(prepared$body)
    else prepared$body, context, session$policy$max_payload_bytes, provider$api_key_env)
  list(context = context, state = state)
}

.sc_run_turn_authorized <- function(request, config) {
  consent <- config$review$transfer_consent
  if (is.null(consent) || !identical(consent$schema, "scagentkit.transfer-consent.v2") ||
      !identical(consent$mode, "project") || !isTRUE(consent$confirmed) ||
      !isTRUE(config$review$allow_external) ||
      !identical(consent$hash, .sc_run_provider_hash(consent[setdiff(names(consent), "hash")])) ||
      !identical(consent$provider_hash, .sc_run_provider_hash(config$provider)) ||
      !identical(consent$budget_usd, as.numeric(config$budget)) ||
      !identical(consent$prompt_version, .sc_run_prompt_version())) return(FALSE)
  scope <- consent$react_scope; policy <- request$session$policy
  if (!is.list(scope) || !identical(scope$schema, "scagentkit.react-scope.v1") ||
      !identical(scope$cost_mode, "posthoc")) return(FALSE)
  allowed <- scope$policy
  all(c("study_context", "aggregate_qc", "aggregate_markers", "aggregate_design", "aggregate_expression") %in% consent$categories) &&
    all(unlist(policy$tools, use.names = FALSE) %in% unlist(allowed$tools, use.names = FALSE)) &&
    (!isTRUE(policy$act_enabled) || isTRUE(allowed$act_enabled)) &&
    all(vapply(c("max_steps", "max_steps_per_cluster", "cluster_timeout_seconds",
      "tool_timeout_seconds", "max_payload_bytes"), function(name) if (name == "max_payload_bytes") .sc_run_capacity_bytes(policy[[name]]) <= .sc_run_capacity_bytes(allowed[[name]]) else policy[[name]] <= allowed[[name]], logical(1)))
}

.sc_run_turn_strict_authorized <- function(request, request_hash, state) {
  if (!identical(request$approved_payload_hash, request_hash) ||
      !request_hash %in% state$suggestion_transfer_hashes) return(FALSE)
  any(vapply(state$history, function(event) identical(event$action, "suggestion_transfer_approved") &&
    identical(event$details$request_hash, request_hash) &&
    identical(event$details$session_hash, request$session$hash) &&
    identical(event$details$cluster_id, request$cluster_id) &&
    identical(as.integer(event$details$ordinal), as.integer(request$ordinal)) &&
    is.character(event$details$reviewer) && nzchar(event$details$reviewer) &&
    is.character(event$details$reason) && nzchar(event$details$reason), logical(1)))
}

# Internal hook for the existing exact-payload approval action; not a tool or a
# scientific approval. The later loop/UI integration supplies the inspected revision.
.sc_run_turn_approve <- function(root, request, reviewer, reason, expected_revision) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(root); owner <- .sc_run_lock(root)
  on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  .sc_run_qc_revision_check(state, expected_revision)
  prepared <- .sc_run_turn_prepare(request, state$config$provider)
  .sc_run_turn_guard(root, request, state$config$provider, prepared)
  ledger <- .sc_run_provider_read(file.path(root, "provider", "ledger.json"))
  .sc_run_turn_sequence(request, ledger$entries, prepared)
  state$suggestion_transfer_hashes <- unique(c(state$suggestion_transfer_hashes, prepared$request_hash))
  state <- .sc_run_event(state, "suggestion_transfer_approved", list(
    request_hash = prepared$request_hash, payload_hash = .sc_run_provider_hash(prepared$payload),
    session_hash = request$session$hash, cluster_id = request$cluster_id,
    ordinal = as.integer(request$ordinal), reviewer = reviewer, reason = reason,
    authority = "Exact outgoing structured payload only; no scientific approval."))
  .sc_run_save(root, state)
  invisible(prepared$request_hash)
}

.sc_run_turn_sequence <- function(request, entries, prepared) {
  prior <- Filter(function(x) identical(x$session_id, request$session$id), entries)
  if (request$ordinal != length(prior) + 1L ||
      sum(vapply(prior, function(x) identical(x$cluster_id, request$cluster_id), logical(1))) >=
        request$session$policy$max_steps_per_cluster)
    .sc_run_turn_error("session_limit", "The turn is out of sequence or exceeds its session/cluster allowance.")
  previous <- if (length(prior)) {
    last <- tail(prior, 1L)[[1L]]
    if (!is.null(last$turn_response_hash)) last$turn_response_hash else
      if (!identical(last$delivery, "unknown"))
        last$turn_outcome_hash else NULL
  } else NULL
  if ((length(prior) && is.null(previous)) || !identical(request$previous_response_hash, previous))
    .sc_run_turn_error("invalid_sequence", "The turn does not continue the saved response chain.")
  cluster <- Filter(function(x) identical(x$cluster_id, request$cluster_id), prior)
  if (identical(request$session$capability_profile$native_protocol, "xai.responses.v1"))
    return(.sc_run_xai_sequence(prepared$body$input, cluster))
  current <- prepared$body$messages
  if (!length(cluster)) {
    if (any(!vapply(current, function(x) x$role %in% c("system", "user"), logical(1))))
      .sc_run_turn_error("invalid_sequence", "A new cluster conversation starts with system/user evidence, not fabricated assistant or tool history.")
  } else {
    last <- tail(cluster, 1L)[[1L]]
    if (is.null(last$turn_response) || !identical(last$status, "ok"))
      .sc_run_turn_error("invalid_sequence", "This cluster has no completed response to continue.")
    saved <- jsonlite::fromJSON(last$turn_payload$wire_json, simplifyVector = FALSE)$messages
    prefix <- c(saved, list(last$turn_response$message))
    if (length(current) <= length(prefix) ||
        !identical(.sc_run_provider_json(current[seq_along(prefix)]), .sc_run_provider_json(prefix)) ||
        any(!vapply(current[-seq_along(prefix)], function(x) x$role %in% c("tool", "user"), logical(1))))
      .sc_run_turn_error("invalid_sequence", "The complete saved conversation and assistant response must remain unchanged; only tool results or user follow-up may be appended.")
  }
  invisible(TRUE)
}

.sc_run_turn_response <- function(value, request, context, provider, usage = NULL) {
  if (.sc_run_xai_native(provider))
    return(.sc_run_xai_response(value, request, context, provider, usage))
  fail <- function(status, error) list(status = status, content = NULL,
    turn_response = NULL, error = error)
  if (!is.list(value) || !identical(value$schema_version, "agentomics.turn.v1") ||
      !is.list(value$message) || !identical(value$message$role, "assistant"))
    return(fail("invalid_response", "The provider did not return a valid structured-turn envelope."))
  if (!is.null(usage$output_tokens) && usage$output_tokens > provider$generation$max_tokens)
    return(fail("invalid_response", "Provider output exceeded its configured token cap."))
  safe <- .sc_run_provider_plain(value[c("schema_version", "message", "finish_reason")])
  check <- tryCatch({
    # Core validates the same message shape when constructing the next request.
    # Complete temporary tool results validate pairing without executing tools.
    messages <- list(list(role = "user", content = "Validate response shape."), safe$message)
    calls <- safe$message$tool_calls
    if (length(calls)) messages <- c(messages, lapply(calls, function(call)
      list(role = "tool", tool_call_id = call$id, content = "{}")))
    fn <- .sc_run_turn_factory(provider)
    agentomicsCore::prepare_turn_request(fn, messages = messages)
    if (!safe$finish_reason %in% c("stop", "tool_calls", "length", "max_tokens",
        "max_output_tokens", "content_filter", "function_call", "eos_token", "end_turn", "stop_sequence"))
      stop("Invalid finish reason.")
    .sc_run_turn_privacy(safe, context, request$session$policy$max_payload_bytes, provider$api_key_env)
    TRUE
  }, error = function(e) e)
  if (inherits(check, "error")) return(fail(if (inherits(check, "sc_run_turn_error")) check$code else
    "invalid_response", "The structured response failed its shape, privacy or size checks."))
  if (safe$finish_reason %in% c("length", "max_tokens", "max_output_tokens", "content_filter"))
    return(list(status = "truncated_response", content = NULL, turn_response = safe,
      error = "The provider did not complete the turn; no final draft was accepted."))
  list(status = "ok", content = safe$message, turn_response = safe, error = NULL)
}

.sc_run_turn_usage_consistent <- function(usage, raw) {
  scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x) &&
    x >= 0 && x == floor(x)
  if (!scalar(usage$input_tokens) || !scalar(usage$output_tokens)) return(FALSE)
  same <- function(names, expected) all(vapply(raw[intersect(names(raw), names)],
    function(x) scalar(x) && x == expected, logical(1)))
  if (!same(c("prompt_tokens", "input_tokens"), usage$input_tokens) ||
      !same(c("completion_tokens", "output_tokens"), usage$output_tokens) ||
      !same("total_tokens", usage$input_tokens + usage$output_tokens)) return(FALSE)
  cached <- c(list(usage$cached_tokens), raw[c("prompt_cache_hit_tokens", "cached_tokens",
    "cache_read_input_tokens")], list(raw$prompt_tokens_details$cached_tokens,
      raw$input_tokens_details$cached_tokens))
  cached <- Filter(Negate(is.null), cached)
  if (length(cached) && (!all(vapply(cached, function(x) scalar(x) &&
      x <= usage$input_tokens, logical(1))) || length(unique(unlist(cached))) != 1L)) return(FALSE)
  miss <- raw$prompt_cache_miss_tokens
  if (!is.null(miss) && (!scalar(miss) || miss > usage$input_tokens ||
      (length(cached) && cached[[1L]] + miss != usage$input_tokens))) return(FALSE)
  reasoning <- c(list(raw$reasoning_tokens), list(raw$completion_tokens_details$reasoning_tokens,
    raw$output_tokens_details$reasoning_tokens))
  reasoning <- Filter(Negate(is.null), reasoning)
  if (length(reasoning) && !all(vapply(reasoning, function(x) scalar(x) &&
      x <= usage$output_tokens, logical(1)))) return(FALSE)
  TRUE
}

.sc_run_turn_outcome <- function(entry) {
  list(schema = "scagentkit.turn-outcome.v1", delivery = entry$delivery,
    status = entry$status, response_hash = entry$turn_response_hash,
    usage_hash = .sc_run_provider_hash(entry$usage), cost_state = entry$cost_state,
    cost_usd = entry$cost_usd, cost_mode = "posthoc")
}

# Commit the response through the same immutable checkpoints and state events
# used for scientific evidence, before finalizing its mutable ledger projection.
.sc_run_turn_commit <- function(root, state, entry, action = "provider_turn_completed", extra = list()) {
  key <- paste0("provider_turn_", entry$request_hash)
  state <- .sc_run_put(root, state, key, entry)
  state <- .sc_run_event(state, action, c(list(
    session_id = entry$session_id, session_hash = entry$session_hash,
    cluster_id = entry$cluster_id, ordinal = entry$ordinal,
    request_hash = entry$request_hash, outcome_hash = entry$turn_outcome_hash,
    checkpoint = state$files[[key]], delivery = entry$delivery, status = entry$status,
    usage = entry$usage, cost_usd = entry$cost_usd, cost_basis = entry$cost_basis,
    cost_mode = "posthoc", scientific_approval = FALSE), extra))
  .sc_run_save(root, state)
  state
}

.sc_run_turn_recover_ledger <- function(root, state, ledger, path) {
  changed <- FALSE
  for (i in seq_along(ledger$entries)) {
    entry <- ledger$entries[[i]]
    if (is.null(entry$session_id)) next
    key <- paste0("provider_turn_", entry$request_hash)
    file <- state$files[[key]]
    if (is.null(file)) {
      if (!identical(entry$status, "dispatched"))
        .sc_run_turn_error("invalid_receipt", "A completed turn has no committed state receipt; dispatch refused.")
      next
    }
    saved <- .sc_run_get(root, state, key)
    linked <- any(vapply(state$history, function(event)
      event$action %in% c("provider_turn_completed", "provider_reconciled") &&
        identical(event$details$request_hash, saved$request_hash) &&
        identical(event$details$session_hash, saved$session_hash) &&
        identical(event$details$outcome_hash, saved$turn_outcome_hash) &&
        identical(event$details$checkpoint, file), logical(1)))
    if (!linked || !identical(saved$turn_outcome_hash, .sc_run_provider_hash(saved$turn_outcome)) ||
        !identical(saved$turn_outcome$response_hash, saved$turn_response_hash))
      .sc_run_turn_error("invalid_receipt", "The completed turn does not match its committed state event.")
    # A crash after state commit can leave only the durable dispatch reservation
    # in the ledger. Restore the committed response; never invoke the provider.
    if (identical(entry$status, "dispatched")) {
      if (!identical(entry$turn_payload_hash, saved$turn_payload_hash) ||
          !identical(entry$session_hash, saved$session_hash))
        .sc_run_turn_error("invalid_receipt", "The held reservation differs from its committed response.")
      ledger$entries[[i]] <- saved; changed <- TRUE
      next
    }
    # Explicit reconciliation can also be interrupted after its state commit.
    # Only its exact recorded predecessor may be replaced by the new receipt.
    if (!is.null(saved$reconciliation$previous_entry_hash) &&
        identical(saved$reconciliation$previous_entry_hash, .sc_run_provider_hash(entry))) {
      ledger$entries[[i]] <- saved; changed <- TRUE
      next
    }
    immutable <- c("request_hash", "provider", "purpose", "delivery", "session_id", "session_hash", "cluster_id", "ordinal",
      "previous_response_hash", "turn_payload", "turn_payload_hash", "cost_mode",
      "reservation_usd", "authorization", "effective_timeout_seconds", "turn_outcome", "turn_outcome_hash", "usage",
      "raw_usage", "raw_usage_hash", "cost_state", "cost_usd", "charged_or_held_usd",
      "accounting_issue", "cost_basis", "cost_estimated", "actual_cost_usd",
      "reconciliation")
    same <- all(vapply(immutable, function(name)
      identical(.sc_run_provider_json(entry[[name]]), .sc_run_provider_json(saved[[name]])), logical(1)))
    original <- if (is.null(entry$turn_response_hash)) entry$withheld_response_hash else entry$turn_response_hash
    if (!same || !identical(original, saved$turn_response_hash))
      .sc_run_turn_error("invalid_receipt", "The cached turn differs from its committed response; dispatch refused.")
  }
  if (changed) .sc_run_provider_write(ledger, path)
  ledger
}

.sc_run_turn_settle <- function(entry, value, request, context, provider) {
  is_error <- inherits(value, "error")
  core_error <- inherits(value, "agentomics_turn_error")
  entry$delivery <- if (!is_error) "received" else if (core_error &&
    value$delivery %in% c("not_sent", "unknown", "received")) value$delivery else "unknown"
  metadata <- if (is.list(value)) value$metadata else NULL
  entry$response_metadata <- .sc_run_provider_response_metadata(list(
    response_metadata = metadata), provider$api_key_env)
  entry$response_metadata_hash <- .sc_run_provider_hash(entry$response_metadata)
  entry["raw_usage"] <- list(.sc_run_provider_raw_usage(if (is.list(value)) value$raw_usage else NULL))
  entry$raw_usage_hash <- .sc_run_provider_hash(entry$raw_usage)
  entry["usage"] <- list(.sc_run_provider_usage(value))
  entry$model_reported <- if (is.list(metadata) && is.character(metadata$model) &&
    length(metadata$model) == 1L && !.sc_run_provider_contains_secret(metadata$model, provider$api_key_env))
    substr(metadata$model, 1, 200) else NULL
  safe_metadata <- tryCatch({
    .sc_run_turn_privacy(list(metadata = entry$response_metadata, model = entry$model_reported),
      context, request$session$policy$max_payload_bytes, provider$api_key_env)
    TRUE
  }, error = function(e) FALSE)
  if (!safe_metadata) {
    entry$response_metadata <- .sc_run_provider_response_metadata(NULL)
    entry$response_metadata_hash <- .sc_run_provider_hash(entry$response_metadata)
    entry$model_reported <- NULL
  }
  entry$cost_basis <- "unresolved"; entry$cost_estimated <- FALSE; entry$actual_cost_usd <- NULL
  if (is_error) {
    entry$status <- switch(entry$delivery, not_sent = "not_sent",
      received = "provider_response_error", "delivery_uncertain")
    entry$error <- switch(entry$delivery,
      not_sent = "The provider rejected the request before transmission; no fee was charged.",
      received = "The provider returned an unusable response; available usage was retained.",
      "Delivery is uncertain; no automatic retry is allowed and the cost remains unknown.")
    entry$provider_error_code <- if (core_error && is.character(value$code) &&
      length(value$code) == 1L && grepl("^[a-z_]{1,64}$", value$code)) value$code else "provider_error"
  } else {
    parsed <- .sc_run_turn_response(value, request, context, provider, entry$usage)
    entry[names(parsed)] <- parsed
    if (!is.null(entry$turn_response)) entry$turn_response_hash <- .sc_run_provider_hash(entry$turn_response)
  }
  if (identical(entry$delivery, "not_sent") || !provider$external) {
    entry$cost_state <- "known"; entry$cost_usd <- 0; entry$charged_or_held_usd <- 0
    entry$cost_basis <- if (provider$external) "confirmed_not_sent" else "offline_no_fee"
    entry$actual_cost_usd <- 0
  } else if (identical(entry$delivery, "received")) {
    native <- .sc_run_xai_native(provider)
    consistent <- if (native) !is.null(entry$usage$input_tokens) &&
      !is.null(entry$usage$output_tokens) else .sc_run_turn_usage_consistent(entry$usage, entry$raw_usage)
    if (!consistent) entry$usage_status <- "missing_or_inconsistent"
    cost <- if (native) .sc_run_xai_cost(value) else
      .sc_run_provider_cost(value, if (consistent) entry$usage else NULL, provider)
    entry$cost_state <- cost$state; entry$cost_usd <- cost$cost_usd
    if (identical(cost$state, "known")) {
      entry$charged_or_held_usd <- cost$cost_usd
      explicit <- native || (is.numeric(value$cost_usd) && length(value$cost_usd) == 1L &&
        is.finite(value$cost_usd) && value$cost_usd >= 0)
      entry$cost_basis <- if (explicit) "provider_reported" else "usage_configured_pricing"
      entry$cost_estimated <- !explicit
      if (explicit) entry$actual_cost_usd <- cost$cost_usd
    }
    # Cost is descriptive after the request, never a new send/continue gate.
    # Output caps remain part of the response contract, independent of money.
    if (!native && !is.null(entry$usage$output_tokens) && entry$usage$output_tokens > provider$generation$max_tokens) {
      entry$status <- "invalid_response"; entry$content <- NULL
      entry$error <- "Provider output exceeded its configured token cap."
    }
  }
  entry$turn_outcome <- .sc_run_turn_outcome(entry)
  entry$turn_outcome_hash <- .sc_run_provider_hash(entry$turn_outcome)
  entry
}
