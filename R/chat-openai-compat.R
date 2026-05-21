#' Build a chat_fn that talks to any OpenAI-compatible /v1/chat/completions API
#'
#' Many providers expose an OpenAI-style chat completions endpoint:
#' DeepSeek, OpenRouter, Together AI, Groq, AIMLAPI, CometAPI,
#' SiliconFlow, Moonshot, Yi, Qwen DashScope, vLLM-served models, Ollama,
#' LM Studio, and so on. This wrapper handles all of them with one
#' set of parameters: just point it at the right `base_url` with the
#' right `api_key` and `model` and you're done.
#'
#' Returns a function with signature
#' `function(system_prompt, user_prompt, image_path = NULL) -> character`,
#' the same signature scAgentKit's LLM verbs expect.
#'
#' Image support depends on the model and the provider. Most text-only
#' models (deepseek-chat, llama-3.1, etc.) silently ignore `image_path`.
#' Multimodal models accessed through compatible endpoints (gpt-4o,
#' qwen-vl, deepseek-vl2, gemini-pro-vision via openrouter, claude
#' through compat layers) accept image input. Set `support_image = TRUE`
#' to force-attach as an `image_url` content block; `FALSE` to skip
#' image; default `"auto"` skips silently when image_path is NULL,
#' attaches when non-NULL (matches the OpenAI spec).
#'
#' @param model Character. Model ID as the provider expects it
#'   (e.g. "deepseek-chat", "anthropic/claude-sonnet-4.5",
#'   "openai/gpt-4o", "qwen-vl-max", "Qwen/Qwen2.5-VL-72B-Instruct").
#' @param api_key Character. Provider API key.
#' @param base_url Character. Base URL up to (but not including) the
#'   `/chat/completions` segment. Common defaults:
#'   - DeepSeek: "https://api.deepseek.com/v1"
#'   - OpenRouter: "https://openrouter.ai/api/v1"
#'   - Together: "https://api.together.xyz/v1"
#'   - Groq: "https://api.groq.com/openai/v1"
#'   - SiliconFlow: "https://api.siliconflow.cn/v1"
#'   - Local vLLM: "http://localhost:8000/v1"
#'   - Local Ollama: "http://localhost:11434/v1"
#' @param max_tokens Integer. Defaults to 2000.
#' @param temperature Numeric in [0, 2]. Defaults to 0.
#' @param support_image One of `"auto"` (default), `TRUE`, or `FALSE`.
#'   `"auto"` uses image only when `image_path` is non-NULL and the
#'   model name suggests vision (heuristic). `TRUE` always attaches.
#'   `FALSE` always ignores.
#' @param timeout_secs Numeric. Per-request timeout. Defaults to 180.
#' @param extra_headers Named character vector of extra HTTP headers,
#'   for providers that need them (e.g. OpenRouter's `HTTP-Referer`
#'   and `X-Title`).
#'
#' @return A function `chat_fn(system_prompt, user_prompt, image_path = NULL)`.
#'
#' @examples
#' \dontrun{
#'   # DeepSeek
#'   chat_deepseek <- make_chat_fn_openai_compat(
#'     model    = "deepseek-chat",
#'     api_key  = Sys.getenv("DEEPSEEK_API_KEY"),
#'     base_url = "https://api.deepseek.com/v1"
#'   )
#'
#'   # OpenRouter accessing Claude
#'   chat_or_claude <- make_chat_fn_openai_compat(
#'     model    = "anthropic/claude-sonnet-4.5",
#'     api_key  = Sys.getenv("OPENROUTER_API_KEY"),
#'     base_url = "https://openrouter.ai/api/v1",
#'     extra_headers = c(
#'       `HTTP-Referer` = "https://github.com/your/repo",
#'       `X-Title`      = "scAgentKit"
#'     )
#'   )
#'
#'   # Local vLLM with Qwen-VL
#'   chat_local <- make_chat_fn_openai_compat(
#'     model    = "Qwen/Qwen2.5-VL-7B-Instruct",
#'     api_key  = "EMPTY",
#'     base_url = "http://localhost:8000/v1",
#'     support_image = TRUE
#'   )
#' }
#' @export
make_chat_fn_openai_compat <- function(
    model,
    api_key,
    base_url,
    max_tokens     = 2000,
    temperature    = 0,
    support_image  = "auto",
    timeout_secs   = 180,
    extra_headers  = NULL) {

  if (!nzchar(api_key)) {
    stop("api_key is empty. Pass api_key explicitly or set the relevant ",
         "env var and restart R.")
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Package 'httr2' is required. Install with install.packages('httr2').")
  }
  if (!isTRUE(support_image) && !isFALSE(support_image) &&
      !identical(support_image, "auto")) {
    stop("support_image must be TRUE, FALSE, or 'auto'.")
  }
  # Heuristic: model name contains 'vision', 'vl', 'multimodal', 'gpt-4o',
  # 'gemini', 'pixtral', 'omni', or 'claude' -> probably supports image.
  vision_hint_pat <- "(?i)vision|-vl-|vl-?[0-9]|multimodal|gpt-4o|gpt-4\\.1|gemini|pixtral|omni|claude|qwen2?-?vl"
  model_looks_visiony <- grepl(vision_hint_pat, model, perl = TRUE)

  function(system_prompt, user_prompt, image_path = NULL) {

    # Build user content: list of blocks if image present, else plain string.
    has_image <- !is.null(image_path) && (
      isTRUE(support_image) ||
      (identical(support_image, "auto") && model_looks_visiony)
    )
    if (!is.null(image_path) && !isTRUE(support_image) &&
        !identical(support_image, "auto")) {
      # explicitly set support_image = FALSE: silently skip
      has_image <- FALSE
    }

    user_content <- if (has_image) {
      if (!file.exists(image_path)) {
        stop(sprintf("image_path does not exist: %s", image_path))
      }
      if (!requireNamespace("base64enc", quietly = TRUE)) {
        stop("Package 'base64enc' is required for image input.")
      }
      media_type <- .guess_image_media_type(image_path)
      bytes <- readBin(image_path, what = "raw",
                       n = file.info(image_path)$size)
      data_b64 <- base64enc::base64encode(bytes)
      data_url <- sprintf("data:%s;base64,%s", media_type, data_b64)
      list(
        list(type = "image_url",
             image_url = list(url = data_url)),
        list(type = "text", text = user_prompt)
      )
    } else {
      user_prompt   # plain string -> OpenAI accepts simple form
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

    headers <- c(
      Authorization  = paste("Bearer", api_key),
      `Content-Type` = "application/json"
    )
    if (!is.null(extra_headers)) {
      headers <- c(headers, extra_headers)
    }

    resp <- httr2::request(base_url) |>
      httr2::req_url_path_append("chat/completions") |>
      httr2::req_headers(!!!headers) |>
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
      } else if (!is.null(parsed) && !is.null(parsed$message)) {
        parsed$message
      } else {
        httr2::resp_body_string(resp)
      }
      stop(sprintf("OpenAI-compat API error (HTTP %d): %s", status, err_msg))
    }

    if (is.null(parsed) || is.null(parsed$choices) ||
        length(parsed$choices) == 0) {
      stop("API returned no content. Raw: ",
           httr2::resp_body_string(resp))
    }

    # Token accounting. OpenAI-compatible providers usually return:
    #   usage: { prompt_tokens, completion_tokens, total_tokens }
    # Some (DeepSeek, Qwen) also include `prompt_cache_hit_tokens` for
    # cached prompt prefix; we map that to cached_tokens.
    if (!is.null(parsed$usage)) {
      cache_hit <- parsed$usage$prompt_cache_hit_tokens %||%
                   parsed$usage$prompt_tokens_details$cached_tokens %||%
                   NA_integer_
      # Derive a short provider tag from the base_url host (e.g.
      # "api.deepseek.com" -> "deepseek", "dashscope.aliyuncs.com" ->
      # "dashscope"). This is best-effort — failures fall back to
      # "openai_compat".
      provider_tag <- tryCatch({
        host <- regmatches(base_url,
                            regexpr("(?<=://)[^/]+", base_url, perl = TRUE))
        host <- sub("^api\\.", "", host)
        host <- sub("^www\\.", "", host)
        host <- strsplit(host, "\\.")[[1]][1]
        if (length(host) == 0 || !nzchar(host)) "openai_compat" else host
      }, error = function(e) "openai_compat")

      .token_record(
        provider      = paste0("openai_compat:", provider_tag),
        model         = parsed$model %||% model,
        input_tokens  = parsed$usage$prompt_tokens,
        output_tokens = parsed$usage$completion_tokens,
        cached_tokens = cache_hit,
        call_type     = if (is.null(image_path)) "text" else "vision"
      )
    }

    parsed$choices[[1]]$message$content
  }
}
