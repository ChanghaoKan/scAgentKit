#' Universal OpenAI-compatible chat_fn factory
#'
#' Builds a `chat_fn` that talks to any OpenAI-compatible chat
#' completions endpoint. Most providers (DeepSeek, xAI/Grok, Kimi/Moonshot,
#' Qwen/DashScope, Doubao, Zhipu/GLM, OpenAI itself, Together, Groq,
#' OpenRouter, local Ollama / vLLM) implement the OpenAI Chat Completions
#' protocol exactly:
#'
#' - POST `<base_url>/chat/completions`
#' - Auth via `Authorization: Bearer <key>` header
#' - JSON body with `{model, messages: [{role, content}], temperature, max_tokens, ...}`
#' - Multimodal images via content blocks: `{type: "image_url", image_url: {url: "data:image/png;base64,..."}}`
#'
#' Use this factory directly, or use one of the provider-specific
#' helpers ([chat_deepseek()], [chat_grok()], [chat_qwen()], [chat_kimi()],
#' [chat_openai()]) which preset the URL/key/model for you.
#'
#' For Anthropic Claude, use [make_chat_fn_claude()] instead — Anthropic's
#' Messages API is NOT OpenAI-compatible (different headers, system field
#' lifted out of messages, image blocks use `source.base64` not `image_url`).
#'
#' @param base_url Character. Endpoint base URL, e.g.
#'   `"https://api.deepseek.com/v1"`, `"https://api.x.ai/v1"`,
#'   `"https://api.openai.com/v1"`. Should end at `/v1` (or wherever
#'   the API roots `chat/completions` under). Trailing slash optional.
#' @param model Character. Provider-specific model ID, e.g.
#'   `"deepseek-chat"`, `"grok-4-1-fast"`, `"gpt-4o-mini"`.
#' @param api_key Character. The actual key. If NULL (default), read
#'   from environment variable named by `api_key_env`.
#' @param api_key_env Character. Environment variable name to look up
#'   the key from. Default `"OPENAI_API_KEY"`. Examples:
#'   `"DEEPSEEK_API_KEY"`, `"XAI_API_KEY"`, `"DASHSCOPE_API_KEY"`.
#'   Pass `""` for endpoints that need no key (local Ollama).
#' @param supports_vision Logical. If TRUE, image_path arguments are
#'   sent as `image_url` content blocks. If FALSE (default), they are
#'   silently ignored with a one-time message. Set TRUE only for
#'   models you've confirmed handle images (e.g. grok-4-1-fast,
#'   gpt-4o, qwen-vl-max). Text-only models will error out on image
#'   blocks.
#' @param max_tokens Integer. Default 2000.
#' @param temperature Numeric in [0, 2]. Default 0 (deterministic).
#' @param timeout_secs Numeric. Per-request timeout. Default 180.
#' @param extra_headers Optional named character vector of extra HTTP
#'   headers to send. Useful for OpenRouter (`HTTP-Referer`, `X-Title`)
#'   or Azure (`api-key`).
#' @param extra_body Optional named list of extra JSON fields merged
#'   into the request body. Useful for provider-specific knobs like
#'   `enable_search`, `reasoning_effort`, `top_p`, etc.
#'
#' @return A function `chat_fn(system_prompt, user_prompt, image_path = NULL)`
#'   returning the assistant's text response.
#'
#' @examples
#' \dontrun{
#'   # DeepSeek
#'   chat <- make_chat_fn_openai_compatible(
#'     base_url    = "https://api.deepseek.com/v1",
#'     model       = "deepseek-chat",
#'     api_key_env = "DEEPSEEK_API_KEY"
#'   )
#'
#'   # Grok with vision
#'   chat <- make_chat_fn_openai_compatible(
#'     base_url    = "https://api.x.ai/v1",
#'     model       = "grok-4-1-fast",
#'     api_key_env = "XAI_API_KEY",
#'     supports_vision = TRUE
#'   )
#'
#'   # Local Ollama
#'   chat <- make_chat_fn_openai_compatible(
#'     base_url    = "http://localhost:11434/v1",
#'     model       = "qwen2.5:14b",
#'     api_key_env = "",                     # no key needed
#'     supports_vision = FALSE
#'   )
#' }
#' @export
make_chat_fn_openai_compatible <- function(
    base_url,
    model,
    api_key         = NULL,
    api_key_env     = "OPENAI_API_KEY",
    supports_vision = FALSE,
    max_tokens      = 2000,
    temperature     = 0,
    timeout_secs    = 180,
    extra_headers   = NULL,
    extra_body      = NULL) {

  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Package 'httr2' is required. install.packages('httr2').")
  }
  if (isTRUE(supports_vision) && !requireNamespace("base64enc", quietly = TRUE)) {
    stop("Package 'base64enc' is required for image input. install.packages('base64enc').")
  }
  if (is.null(api_key)) {
    api_key <- Sys.getenv(api_key_env)
  }
  needs_key <- nzchar(api_key_env)
  if (needs_key && !nzchar(api_key)) {
    stop(sprintf(
      "API key is empty. Set environment variable %s in ~/.Renviron and restart R, ",
      api_key_env
    ),
    "or pass `api_key` directly to make_chat_fn_openai_compatible().")
  }

  base_url <- sub("/+$", "", base_url)   # strip trailing slash(es)
  warned_image <- FALSE                  # only warn once per chat_fn

  function(system_prompt, user_prompt, image_path = NULL) {

    # Build user content
    user_content <- if (is.null(image_path)) {
      user_prompt
    } else if (!isTRUE(supports_vision)) {
      if (!warned_image) {
        message(sprintf("[%s] image input ignored (supports_vision = FALSE).",
                        model))
        warned_image <<- TRUE
      }
      user_prompt
    } else {
      if (!file.exists(image_path)) {
        stop(sprintf("image_path does not exist: %s", image_path))
      }
      media <- .guess_image_media_type_oai(image_path)
      bytes <- readBin(image_path, what = "raw",
                       n = file.info(image_path)$size)
      data_b64 <- base64enc::base64encode(bytes)
      data_uri <- sprintf("data:%s;base64,%s", media, data_b64)
      list(
        list(type = "text", text = user_prompt),
        list(type = "image_url",
             image_url = list(url = data_uri))
      )
    }

    body <- list(
      model       = model,
      max_tokens  = max_tokens,
      temperature = temperature,
      messages    = list(
        list(role = "system", content = system_prompt),
        list(role = "user",   content = user_content)
      )
    )
    if (!is.null(extra_body) && length(extra_body) > 0) {
      body <- utils::modifyList(body, extra_body)
    }

    headers <- c(
      `Content-Type` = "application/json",
      if (needs_key) c(Authorization = paste("Bearer", api_key)) else NULL,
      extra_headers
    )

    resp <- httr2::request(base_url) |>
      httr2::req_url_path_append("chat", "completions") |>
      httr2::req_headers(!!!as.list(headers)) |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(timeout_secs) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform()

    status <- httr2::resp_status(resp)
    parsed <- tryCatch(httr2::resp_body_json(resp),
                       error = function(e) NULL)

    if (status >= 400) {
      err_msg <- if (!is.null(parsed) && !is.null(parsed$error$message)) {
        parsed$error$message
      } else {
        httr2::resp_body_string(resp)
      }
      stop(sprintf("OpenAI-compatible API error from %s (HTTP %d): %s",
                   base_url, status, err_msg))
    }

    if (is.null(parsed) || is.null(parsed$choices) ||
        length(parsed$choices) == 0) {
      stop(sprintf("API returned no choices. Raw: %s",
                   substr(httr2::resp_body_string(resp), 1, 500)))
    }

    msg <- parsed$choices[[1]]$message
    # Handle both text-content and content-block responses
    txt <- if (is.character(msg$content)) {
      msg$content
    } else if (is.list(msg$content)) {
      pieces <- vapply(msg$content, function(b) {
        if (!is.null(b$type) && b$type == "text" && !is.null(b$text)) b$text
        else ""
      }, character(1))
      paste(pieces[nzchar(pieces)], collapse = "\n")
    } else {
      as.character(msg$content)
    }
    if (!nzchar(trimws(txt))) {
      stop("API returned empty content. Raw: ",
           substr(httr2::resp_body_string(resp), 1, 500))
    }
    txt
  }
}

# Map file extension to OpenAI-compatible media types.
.guess_image_media_type_oai <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    jpg  = "image/jpeg",
    jpeg = "image/jpeg",
    png  = "image/png",
    gif  = "image/gif",
    webp = "image/webp",
    stop(sprintf("Unsupported image extension '%s' (use jpg/jpeg/png/gif/webp).", ext))
  )
}


# ============================================================================
# Provider presets
# ============================================================================
# These wrap make_chat_fn_openai_compatible with sensible defaults.
# All accept `model`, `api_key`, `vision`, `...` (forwarded to the factory).

#' DeepSeek chat_fn (text-only)
#'
#' Cheap, fast, strong on structured-output tasks. Best for marker
#' annotation, batch-variable selection, resolution recommendation,
#' and other text-only LLM steps in scAgentKit.
#'
#' @param model Default `"deepseek-chat"`. Other options:
#'   `"deepseek-reasoner"` (slower, stronger reasoning).
#' @param api_key_env Default `"DEEPSEEK_API_KEY"`.
#' @param ... Forwarded to [make_chat_fn_openai_compatible()].
#' @export
chat_deepseek <- function(model       = "deepseek-chat",
                          api_key_env = "DEEPSEEK_API_KEY",
                          ...) {
  make_chat_fn_openai_compatible(
    base_url        = "https://api.deepseek.com/v1",
    model           = model,
    api_key_env     = api_key_env,
    supports_vision = FALSE,
    ...
  )
}

#' Grok (xAI) chat_fn — vision-capable
#'
#' Cheap, fast, with real-time web knowledge and OpenAI-compatible
#' vision. Good for budget-conscious testing of vision-dependent
#' steps like [sc_select_pcs_visual()].
#'
#' @param model Default `"grok-4-1-fast"` (vision OK, 2M context).
#'   Use `"grok-4-1-fast-non-reasoning"` for the cheapest option,
#'   or `"grok-code-fast-1"` for code tasks.
#' @param api_key_env Default `"XAI_API_KEY"`.
#' @param vision Logical. Default TRUE.
#' @param ... Forwarded to [make_chat_fn_openai_compatible()].
#' @export
chat_grok <- function(model       = "grok-4-1-fast",
                      api_key_env = "XAI_API_KEY",
                      vision      = TRUE,
                      ...) {
  make_chat_fn_openai_compatible(
    base_url        = "https://api.x.ai/v1",
    model           = model,
    api_key_env     = api_key_env,
    supports_vision = isTRUE(vision),
    ...
  )
}

#' Qwen (DashScope) chat_fn
#'
#' Alibaba's Qwen models via DashScope's OpenAI-compatible endpoint.
#' For text use `"qwen-plus"` / `"qwen-max"`. For vision use
#' `"qwen-vl-plus"` / `"qwen-vl-max"` and set `vision = TRUE`.
#'
#' @param model Default `"qwen-plus"`.
#' @param api_key_env Default `"DASHSCOPE_API_KEY"`.
#' @param vision Logical. Default FALSE. Set TRUE only when using a
#'   vision-language model (e.g. `qwen-vl-max`).
#' @param ... Forwarded to [make_chat_fn_openai_compatible()].
#' @export
chat_qwen <- function(model       = "qwen-plus",
                      api_key_env = "DASHSCOPE_API_KEY",
                      vision      = FALSE,
                      ...) {
  make_chat_fn_openai_compatible(
    base_url        = "https://dashscope.aliyuncs.com/compatible-mode/v1",
    model           = model,
    api_key_env     = api_key_env,
    supports_vision = isTRUE(vision),
    ...
  )
}

#' Kimi (Moonshot) chat_fn
#'
#' Moonshot AI's Kimi via their OpenAI-compatible endpoint. Strong on
#' long-context and Chinese tasks. Models: `"moonshot-v1-8k"`,
#' `"moonshot-v1-32k"`, `"moonshot-v1-128k"` (text); `"moonshot-v1-8k-vision-preview"`
#' for vision.
#'
#' @param model Default `"moonshot-v1-32k"`.
#' @param api_key_env Default `"MOONSHOT_API_KEY"`.
#' @param vision Logical. Default FALSE.
#' @param ... Forwarded to [make_chat_fn_openai_compatible()].
#' @export
chat_kimi <- function(model       = "moonshot-v1-32k",
                      api_key_env = "MOONSHOT_API_KEY",
                      vision      = FALSE,
                      ...) {
  make_chat_fn_openai_compatible(
    base_url        = "https://api.moonshot.cn/v1",
    model           = model,
    api_key_env     = api_key_env,
    supports_vision = isTRUE(vision),
    ...
  )
}

#' OpenAI chat_fn
#'
#' For OpenAI's own API. Most users will pick `gpt-4o-mini` for cost
#' or `gpt-4o` for quality (both vision-capable).
#'
#' @param model Default `"gpt-4o-mini"`.
#' @param api_key_env Default `"OPENAI_API_KEY"`.
#' @param vision Logical. Default TRUE for 4o-class models.
#' @param ... Forwarded to [make_chat_fn_openai_compatible()].
#' @export
chat_openai <- function(model       = "gpt-4o-mini",
                        api_key_env = "OPENAI_API_KEY",
                        vision      = TRUE,
                        ...) {
  make_chat_fn_openai_compatible(
    base_url        = "https://api.openai.com/v1",
    model           = model,
    api_key_env     = api_key_env,
    supports_vision = isTRUE(vision),
    ...
  )
}

#' Anthropic Claude chat_fn — vision-capable
#'
#' Convenience alias for [make_chat_fn_claude()] (see that function for
#' full options). Default uses Claude Sonnet 4.6: best price/intelligence
#' ratio for the structured decisions and vision tasks scAgentKit uses.
#'
#' @param model Default `"claude-sonnet-4-6"`. Use `"claude-opus-4-7"`
#'   for the highest-intelligence model.
#' @param api_key_env Default `"ANTHROPIC_API_KEY"`.
#' @param ... Forwarded to [make_chat_fn_claude()].
#' @export
chat_claude <- function(model       = "claude-sonnet-4-6",
                        api_key_env = "ANTHROPIC_API_KEY",
                        ...) {
  make_chat_fn_claude(
    model   = model,
    api_key = Sys.getenv(api_key_env),
    ...
  )
}


#' List supported LLM providers
#'
#' Print a human-readable summary of the chat_fn presets shipped with
#' scAgentKit. For each, shows the helper function, default model,
#' default environment variable for the API key, vision support, and
#' which scAgentKit pipeline steps it's suitable for.
#'
#' This is meant as discoverability: type `list_chat_providers()` to
#' see what's available.
#'
#' @return Invisibly returns a data frame with the same info.
#' @export
list_chat_providers <- function() {
  df <- data.frame(
    helper       = c("chat_deepseek()", "chat_grok()", "chat_qwen()",
                     "chat_kimi()", "chat_openai()", "chat_claude()"),
    default_model = c("deepseek-chat", "grok-4-1-fast", "qwen-plus",
                      "moonshot-v1-32k", "gpt-4o-mini", "claude-sonnet-4-6"),
    api_key_env  = c("DEEPSEEK_API_KEY", "XAI_API_KEY", "DASHSCOPE_API_KEY",
                     "MOONSHOT_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"),
    vision       = c("no", "yes (default)", "no (yes for qwen-vl-*)",
                     "no (yes for *-vision-preview)", "yes",
                     "yes"),
    cost_tier    = c("$$ (cheapest)", "$$ (cheap, vision)",
                     "$$ (China region best)", "$$ (long-context strong)",
                     "$$$ (4o-mini cheap, 4o pricey)",
                     "$$$ (Sonnet 4.6 mid, Opus 4.7 high)"),
    notes        = c("Best for text-only structured decisions; recommended default for marker annotation.",
                     "Cheap vision; alternative to Claude for budget testing.",
                     "Good Chinese-language support; vision via qwen-vl-max.",
                     "Long context; useful for very large marker tables.",
                     "Industry standard; gpt-4o-mini cheap, gpt-4o full quality.",
                     "Strongest at structured reasoning + vision; recommended for sc_select_pcs_visual(). Default sonnet-4-6; opus-4-7 available."),
    stringsAsFactors = FALSE
  )

  cat("scAgentKit chat_fn providers\n")
  cat(strrep("=", 70), "\n", sep = "")
  for (i in seq_len(nrow(df))) {
    cat(sprintf("\n%-18s default model: %s\n", df$helper[i], df$default_model[i]))
    cat(sprintf("%-18s api key env  : %s\n", "", df$api_key_env[i]))
    cat(sprintf("%-18s vision       : %s\n", "", df$vision[i]))
    cat(sprintf("%-18s cost tier    : %s\n", "", df$cost_tier[i]))
    cat(sprintf("%-18s use for      : %s\n", "", df$notes[i]))
  }
  cat("\n")
  cat("For an arbitrary OpenAI-compatible endpoint not listed above, use\n")
  cat("make_chat_fn_openai_compatible(base_url=, model=, api_key_env=, ...).\n")
  cat("All chat_fn returned by these helpers share the same signature:\n")
  cat("  chat_fn(system_prompt, user_prompt, image_path = NULL) -> character\n")
  cat("so you can swap providers without changing pipeline code.\n")

  invisible(df)
}
