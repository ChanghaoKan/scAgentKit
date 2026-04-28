# =============================================================
# Example chat_fn wrappers for scAgentKit's LLM calls
#
# CONTRACT (updated):
#   chat_fn(system_prompt, user_prompt, image_path = NULL) -> character
#
#   - image_path = NULL       -> text-only call (used by annot_llm_annotate)
#   - image_path = "foo.png"  -> multimodal call; the image is attached to
#                                the user message (used by
#                                sc_resolution_recommend with vision = TRUE)
#
# Every wrapper below honours this contract. If your chosen model does
# not support vision, it is still fine to send text-only — call
# sc_resolution_recommend(vision = FALSE) in that case.
#
# Deterministic settings:
#   - Set temperature = 0 for annotation / resolution tasks.
#   - Some providers accept `seed`; use it where available.
#   - Cross-day reproducibility is not guaranteed even at temperature = 0.
#     Pin model versions (e.g. "claude-sonnet-4-5-20260401") for
#     publication. The structured outputs are captured in
#     obj@params$*, which is sufficient for audit.
# =============================================================

# ----- Helper: read a PNG/JPEG as base64 ----------------------------------
.read_image_base64 <- function(path) {
  if (!requireNamespace("base64enc", quietly = TRUE)) {
    # Fall back to built-in base64 encoding via openssl if available
    if (requireNamespace("openssl", quietly = TRUE)) {
      raw <- readBin(path, "raw", n = file.info(path)$size)
      return(openssl::base64_encode(raw))
    }
    stop("Install 'base64enc' or 'openssl' for vision mode: install.packages('base64enc')")
  }
  base64enc::base64encode(path)
}

.media_type_for <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    png  = "image/png",
    jpg  = "image/jpeg",
    jpeg = "image/jpeg",
    webp = "image/webp",
    gif  = "image/gif",
    stop("Unsupported image extension: ", ext))
}

# ----- A. Anthropic via `ellmer` (recommended default) -----------------------
# Claude supports vision natively; ellmer handles image attachment via
# `content_image_file()`. Set ANTHROPIC_API_KEY.
make_chat_fn_anthropic <- function(model = "claude-sonnet-4-5") {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Install 'ellmer' first: install.packages('ellmer')")
  }
  function(system_prompt, user_prompt, image_path = NULL) {
    chat <- ellmer::chat_anthropic(
      model         = model,
      system_prompt = system_prompt,
      params        = ellmer::params(temperature = 0)
    )
    if (is.null(image_path)) {
      chat$chat(user_prompt, echo = FALSE)
    } else {
      chat$chat(
        ellmer::content_image_file(image_path),
        user_prompt,
        echo = FALSE
      )
    }
  }
}

# ----- B. OpenAI via `ellmer` ------------------------------------------------
# GPT-4o supports vision. Set OPENAI_API_KEY.
make_chat_fn_openai <- function(model = "gpt-4o-mini") {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Install 'ellmer' first: install.packages('ellmer')")
  }
  function(system_prompt, user_prompt, image_path = NULL) {
    chat <- ellmer::chat_openai(
      model         = model,
      system_prompt = system_prompt,
      params        = ellmer::params(temperature = 0, seed = 999)
    )
    if (is.null(image_path)) {
      chat$chat(user_prompt, echo = FALSE)
    } else {
      chat$chat(
        ellmer::content_image_file(image_path),
        user_prompt,
        echo = FALSE
      )
    }
  }
}

# ----- C. DeepSeek / Qwen via OpenAI-compatible endpoint ---------------------
# Many domestic providers (DeepSeek, Qwen, Zhipu) expose OpenAI-compatible
# REST endpoints. Vision support varies by model — DeepSeek's current chat
# model does not support images; Qwen-VL does. If the selected model is
# text-only, the image will be silently ignored (text-only fallback).
make_chat_fn_deepseek <- function(model    = "deepseek-chat",
                                  api_key  = Sys.getenv("DEEPSEEK_API_KEY"),
                                  base_url = "https://api.deepseek.com/v1",
                                  supports_vision = FALSE) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Install 'ellmer' first.")
  }
  if (!nzchar(api_key)) stop("Set DEEPSEEK_API_KEY or pass api_key.")
  function(system_prompt, user_prompt, image_path = NULL) {
    chat <- ellmer::chat_openai(
      model         = model,
      base_url      = base_url,
      api_key       = api_key,
      system_prompt = system_prompt,
      params        = ellmer::params(temperature = 0)
    )
    if (is.null(image_path) || !isTRUE(supports_vision)) {
      if (!is.null(image_path) && !isTRUE(supports_vision)) {
        message("[deepseek wrapper] image ignored: supports_vision = FALSE.")
      }
      chat$chat(user_prompt, echo = FALSE)
    } else {
      chat$chat(
        ellmer::content_image_file(image_path),
        user_prompt,
        echo = FALSE
      )
    }
  }
}

# ----- D. Local Ollama via httr2 --------------------------------------------
# No API key, no external data transfer: good for sensitive data. Vision
# requires a vision-capable model (llava / llama3.2-vision / qwen2-vl).
# Install: install.packages(c("httr2", "jsonlite", "base64enc"))
make_chat_fn_ollama <- function(model    = "llama3.1:70b",
                                base_url = "http://localhost:11434",
                                supports_vision = FALSE) {
  if (!requireNamespace("httr2",    quietly = TRUE)) stop("Install 'httr2'.")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Install 'jsonlite'.")

  function(system_prompt, user_prompt, image_path = NULL) {
    user_msg <- list(role = "user", content = user_prompt)

    # Ollama supports images on the user message via the `images` field
    # (array of base64 strings). Only attempt if the caller asked for it
    # AND claims the model supports vision.
    if (!is.null(image_path)) {
      if (!isTRUE(supports_vision)) {
        message("[ollama wrapper] image ignored: supports_vision = FALSE.")
      } else {
        img_b64 <- .read_image_base64(image_path)
        user_msg$images <- list(img_b64)
      }
    }

    body <- list(
      model    = model,
      stream   = FALSE,
      options  = list(temperature = 0, seed = 999),
      messages = list(
        list(role = "system", content = system_prompt),
        user_msg
      )
    )
    resp <- httr2::request(base_url) |>
      httr2::req_url_path("/api/chat") |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(180) |>
      httr2::req_perform()
    parsed <- httr2::resp_body_json(resp)
    parsed$message$content
  }
}

# ----- E. Mock wrapper for unit tests / dry runs -----------------------------
# Returns a fixed response shaped like either the annotation schema or
# (if the user prompt smells like a resolution task) the resolution schema.
# Useful for exercising the pipeline without network calls or API spend.
make_chat_fn_mock <- function(annotation = "T cell",
                              chosen_resolution = 0.3) {
  function(system_prompt, user_prompt, image_path = NULL) {
    is_resolution <- grepl("clustering resolution|chosen_resolution",
                           system_prompt, ignore.case = TRUE)
    if (is_resolution) {
      jsonlite::toJSON(list(
        chosen_resolution = chosen_resolution,
        confidence        = "medium",
        alternatives      = c(chosen_resolution - 0.1, chosen_resolution + 0.1),
        clustree_notes    = if (!is.null(image_path))
                              "Mock: saw clustree plateau at the chosen resolution."
                            else NA,
        reasoning         = "Mock response for dry run."
      ), auto_unbox = TRUE, na = "null")
    } else {
      jsonlite::toJSON(list(
        primary_annotation      = annotation,
        confidence              = "low",
        supporting_markers      = list("MOCK_GENE"),
        contradicting_markers   = list(),
        alternative_annotations = list("Mock alt"),
        proportion_assessment   = "reasonable",
        recommended_action      = "flag_for_review",
        reasoning               = "Mock response for dry run."
      ), auto_unbox = TRUE)
    }
  }
}
