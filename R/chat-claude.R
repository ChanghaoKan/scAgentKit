#' Build a chat_fn that talks to the Anthropic Claude Messages API
#'
#' Returns a function with signature
#' `function(system_prompt, user_prompt, image_path = NULL) -> character`,
#' the same signature scAgentKit's LLM verbs expect (e.g.
#' [annot_llm_annotate()], [sc_resolution_recommend()],
#' [sc_select_pcs_visual()]).
#'
#' Both `api_key` and `base_url` are arguments, so the same wrapper
#' works against the official Anthropic endpoint, an Anthropic-compatible
#' proxy (e.g. CometAPI, an internal gateway), or a Bedrock/Vertex
#' relay that exposes a `/v1/messages` endpoint. To compare models,
#' just build multiple chat_fns:
#' \preformatted{
#'   chat_sonnet <- make_chat_fn_claude(model = "claude-sonnet-4-5",
#'                                      api_key = "sk-ant-...")
#'   chat_opus   <- make_chat_fn_claude(model = "claude-opus-4-7",
#'                                      api_key = "sk-ant-...")
#' }
#'
#' @param model Character. Claude model ID. Defaults to
#'   "claude-sonnet-4-5" — best price/intelligence ratio for the kinds
#'   of structured-decision and vision tasks scAgentKit uses. Pass
#'   "claude-opus-4-7" for the highest-intelligence model (more
#'   expensive; note Opus 4.7 ignores `temperature`).
#' @param api_key Character. The API key. Defaults to
#'   `Sys.getenv("ANTHROPIC_API_KEY")` for convenience but you can pass
#'   it directly: `make_chat_fn_claude(api_key = "sk-ant-...")`.
#' @param base_url Character. API base URL. Defaults to the official
#'   Anthropic endpoint. Override to point at a proxy or self-hosted
#'   relay. The function appends `v1/messages` to this URL.
#' @param max_tokens Integer. Defaults to 2000 (enough for the JSON
#'   schemas this package uses; bump for longer-form analysis).
#' @param temperature Numeric in [0, 1]. Defaults to 0. Ignored for
#'   Claude Opus 4.7 (which removed the parameter).
#' @param timeout_secs Numeric. Per-request timeout. Defaults to 180.
#'
#' @return A function `chat_fn(system_prompt, user_prompt, image_path = NULL)`
#'   that returns the assistant's text response.
#'
#' @examples
#' \dontrun{
#'   # Option 1: env var (set ANTHROPIC_API_KEY in ~/.Renviron)
#'   chat_fn <- make_chat_fn_claude()
#'
#'   # Option 2: explicit key
#'   chat_fn <- make_chat_fn_claude(api_key = "sk-ant-...")
#'
#'   # Option 3: against a proxy / gateway
#'   chat_fn <- make_chat_fn_claude(
#'     model    = "claude-opus-4-7",
#'     api_key  = "your-proxy-key",
#'     base_url = "https://your-proxy.example.com"
#'   )
#'
#'   # vision call
#'   chat_fn(
#'     "You are a single-cell expert.",
#'     "Which UMAP shows cleanest cluster separation?",
#'     image_path = "figures/umap_ndim30.png"
#'   )
#' }
#' @param api_key Character. Authentication token. Resolution order:
#'   (1) explicit `api_key` argument; (2) `ANTHROPIC_AUTH_TOKEN` env var
#'   (used by proxies/relays — sent as `Authorization: Bearer ...`);
#'   (3) `ANTHROPIC_API_KEY` env var (official Anthropic — sent as
#'   `x-api-key`).
#' @param base_url Character. Defaults to `ANTHROPIC_BASE_URL` env var
#'   if set, otherwise `"https://api.anthropic.com"`. Set this to point
#'   at a relay / proxy that exposes the Anthropic Messages API.
#' @param auth_style Character, one of `"auto"`, `"bearer"`, `"x-api-key"`.
#'   `"auto"` (default) uses Bearer if `ANTHROPIC_AUTH_TOKEN` is set or
#'   if a non-default `base_url` is in use, otherwise falls back to
#'   x-api-key. Override only if your relay disagrees with this heuristic.
#' @export
make_chat_fn_claude <- function(
    model        = "claude-sonnet-4-5",
    api_key      = NULL,
    base_url     = NULL,
    auth_style   = c("auto", "bearer", "x-api-key"),
    max_tokens   = 2000,
    temperature  = 0,
    timeout_secs = 180) {

  auth_style <- match.arg(auth_style)

  # Resolve base_url: explicit arg -> env var -> official default
  if (is.null(base_url)) {
    env_url <- Sys.getenv("ANTHROPIC_BASE_URL")
    base_url <- if (nzchar(env_url)) env_url else "https://api.anthropic.com"
  }
  using_proxy <- !identical(base_url, "https://api.anthropic.com")

  # Resolve api_key: explicit arg -> ANTHROPIC_AUTH_TOKEN -> ANTHROPIC_API_KEY
  resolved_via_bearer <- FALSE
  if (is.null(api_key) || !nzchar(api_key)) {
    bearer <- Sys.getenv("ANTHROPIC_AUTH_TOKEN")
    if (nzchar(bearer)) {
      api_key <- bearer
      resolved_via_bearer <- TRUE
    } else {
      api_key <- Sys.getenv("ANTHROPIC_API_KEY")
    }
  }
  if (!nzchar(api_key)) {
    stop("No auth token found. Pass api_key explicitly, or set one of: ",
         "ANTHROPIC_AUTH_TOKEN (proxy/relay) or ANTHROPIC_API_KEY (official).")
  }

  # Resolve auth header style
  if (auth_style == "auto") {
    auth_style <- if (resolved_via_bearer || using_proxy) "bearer" else "x-api-key"
  }

  if (using_proxy) {
    message(sprintf(
      "[make_chat_fn_claude] using proxy base_url = '%s' (auth_style='%s'). ",
      base_url, auth_style),
      "Be aware: requests/responses are visible to the proxy operator. ",
      "Avoid sending sensitive or unpublished data through untrusted relays."
    )
  }

  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Package 'httr2' is required for make_chat_fn_claude(). ",
         "Install with install.packages('httr2').")
  }
  if (!requireNamespace("base64enc", quietly = TRUE)) {
    stop("Package 'base64enc' is required for image input. ",
         "Install with install.packages('base64enc').")
  }

  # Opus 4.7 dropped temperature support; omit it on that model.
  send_temperature <- !grepl("opus-4-7", model)

  function(system_prompt, user_prompt, image_path = NULL) {

    # Build the user message content. Image first, then text — Claude
    # vision works best with the image positioned before the question.
    user_content <- list()
    if (!is.null(image_path)) {
      if (!file.exists(image_path)) {
        stop(sprintf("image_path does not exist: %s", image_path))
      }
      media_type <- .guess_image_media_type(image_path)
      bytes <- readBin(image_path, what = "raw",
                       n = file.info(image_path)$size)
      data_b64 <- base64enc::base64encode(bytes)
      user_content[[length(user_content) + 1]] <- list(
        type   = "image",
        source = list(
          type       = "base64",
          media_type = media_type,
          data       = data_b64
        )
      )
    }
    user_content[[length(user_content) + 1]] <- list(
      type = "text",
      text = user_prompt
    )

    body <- list(
      model      = model,
      max_tokens = max_tokens,
      system     = system_prompt,
      messages   = list(
        list(role = "user", content = user_content)
      )
    )
    if (send_temperature) body$temperature <- temperature

    headers <- if (auth_style == "bearer") {
      list(
        Authorization       = paste("Bearer", api_key),
        `anthropic-version` = "2023-06-01",
        `content-type`      = "application/json"
      )
    } else {
      list(
        `x-api-key`         = api_key,
        `anthropic-version` = "2023-06-01",
        `content-type`      = "application/json"
      )
    }

    resp <- httr2::request(base_url) |>
      httr2::req_url_path_append("v1", "messages") |>
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
      } else {
        httr2::resp_body_string(resp)
      }
      stop(sprintf("Claude API error (HTTP %d): %s", status, err_msg))
    }

    if (is.null(parsed) || is.null(parsed$content)) {
      stop("Claude API returned no content. Raw response: ",
           httr2::resp_body_string(resp))
    }

    # Token accounting. Anthropic returns:
    #   usage: { input_tokens, output_tokens,
    #            cache_creation_input_tokens, cache_read_input_tokens }
    # We collapse cache reads into cached_tokens (they're billed at a
    # discount but still count for cost reporting).
    if (!is.null(parsed$usage)) {
      .token_record(
        provider      = "anthropic",
        model         = parsed$model %||% model,
        input_tokens  = parsed$usage$input_tokens,
        output_tokens = parsed$usage$output_tokens,
        cached_tokens = parsed$usage$cache_read_input_tokens %||% NA_integer_,
        call_type     = if (is.null(image_path)) "text" else "vision"
      )
    }

    # Extract text blocks from content (skip thinking blocks etc.)
    txt <- vapply(parsed$content, function(b) {
      if (!is.null(b$type) && b$type == "text" && !is.null(b$text)) b$text
      else ""
    }, character(1))
    paste(txt[nzchar(txt)], collapse = "\n")
  }
}

# Map file extension -> media_type. Claude supports jpeg, png, gif, webp.
.guess_image_media_type <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    jpg  = "image/jpeg",
    jpeg = "image/jpeg",
    png  = "image/png",
    gif  = "image/gif",
    webp = "image/webp",
    stop(sprintf("Unsupported image extension '%s' for Claude vision (supported: jpg/jpeg/png/gif/webp).", ext))
  )
}
