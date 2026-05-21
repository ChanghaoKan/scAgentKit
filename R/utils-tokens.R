# Token usage tracking ------------------------------------------------------
#
# Centralised, provider-agnostic accounting of LLM token consumption. Every
# provider-specific chat_fn wrapper (chat-claude.R, chat-openai-compat.R) is
# expected to call .token_record() after parsing the API response, passing in
# whatever the provider's `usage` block tells us.
#
# Two access patterns:
#
#   1. **Global accumulator** (default): records go into a package-private
#      environment. Use [token_usage_summary()] to read, [token_usage_reset()]
#      to clear. This is the lightweight path when you just want a total at
#      the end of a session.
#
#   2. **Step-scoped**: callers can wrap a block with
#      [.with_token_scope()] to capture only the tokens spent inside that
#      block. annot_llm_annotate / sc_resolution_recommend etc. use this so
#      AgentSeurat@token_usage gets a per-step breakdown.
#
# The .token_record() function is intentionally lenient: any missing field
# silently becomes NA. Different providers have inconsistent `usage` schemas
# (Anthropic: input_tokens/output_tokens; OpenAI-compatible: prompt_tokens/
# completion_tokens). The recorder normalises both into input_tokens /
# output_tokens.

.token_state <- new.env(parent = emptyenv())
.token_state$records <- list()


#' Record a single LLM call's token usage
#'
#' Provider wrappers call this after each successful API response. End users
#' should not need to call this directly.
#'
#' @param provider Character, e.g. `"anthropic"`, `"openai_compat:deepseek"`.
#' @param model Character, the model identifier returned by the API.
#' @param input_tokens Integer or NA.
#' @param output_tokens Integer or NA.
#' @param cached_tokens Integer or NA (Anthropic prompt caching, OpenAI
#'   prompt cache hits, etc.). Default NA.
#' @param call_type Character, free-form tag for what kind of call this was
#'   (e.g. `"annotation"`, `"resolution_recommend"`). Default NA.
#' @keywords internal
#' @noRd
.token_record <- function(provider, model,
                           input_tokens, output_tokens,
                           cached_tokens = NA_integer_,
                           call_type     = NA_character_) {
  rec <- list(
    time          = Sys.time(),
    provider      = as.character(provider),
    model         = as.character(model),
    input_tokens  = suppressWarnings(as.integer(input_tokens)),
    output_tokens = suppressWarnings(as.integer(output_tokens)),
    cached_tokens = suppressWarnings(as.integer(cached_tokens)),
    call_type     = as.character(call_type)
  )
  .token_state$records[[length(.token_state$records) + 1L]] <- rec
  invisible(rec)
}


#' Summary of LLM token consumption since the last reset
#'
#' Aggregates the per-call records into a tidy data frame and a
#' provider/model breakdown. Useful at the end of a session to report total
#' compute cost.
#'
#' @return A list with two data frames:
#'   - `by_call`: one row per LLM call, with all recorded fields.
#'   - `by_model`: aggregated by provider + model, with totals.
#'
#' @export
token_usage_summary <- function() {
  records <- .token_state$records
  if (length(records) == 0) {
    empty <- data.frame(
      provider = character(0), model = character(0),
      input_tokens = integer(0), output_tokens = integer(0),
      cached_tokens = integer(0), n_calls = integer(0),
      stringsAsFactors = FALSE
    )
    return(list(
      by_call  = data.frame(time = as.POSIXct(character(0)),
                            provider = character(0), model = character(0),
                            input_tokens = integer(0),
                            output_tokens = integer(0),
                            cached_tokens = integer(0),
                            call_type = character(0),
                            stringsAsFactors = FALSE),
      by_model = empty,
      total    = list(input_tokens = 0L, output_tokens = 0L,
                       cached_tokens = 0L, n_calls = 0L)
    ))
  }
  by_call <- do.call(rbind, lapply(records, function(r) {
    data.frame(
      time          = r$time,
      provider      = r$provider,
      model         = r$model,
      input_tokens  = r$input_tokens,
      output_tokens = r$output_tokens,
      cached_tokens = r$cached_tokens,
      call_type     = r$call_type,
      stringsAsFactors = FALSE
    )
  }))
  key <- paste(by_call$provider, by_call$model, sep = "|")
  by_model <- do.call(rbind, lapply(unique(key), function(k) {
    rows <- by_call[key == k, , drop = FALSE]
    data.frame(
      provider      = rows$provider[1],
      model         = rows$model[1],
      input_tokens  = sum(rows$input_tokens,  na.rm = TRUE),
      output_tokens = sum(rows$output_tokens, na.rm = TRUE),
      cached_tokens = sum(rows$cached_tokens, na.rm = TRUE),
      n_calls       = nrow(rows),
      stringsAsFactors = FALSE
    )
  }))
  total <- list(
    input_tokens  = sum(by_call$input_tokens,  na.rm = TRUE),
    output_tokens = sum(by_call$output_tokens, na.rm = TRUE),
    cached_tokens = sum(by_call$cached_tokens, na.rm = TRUE),
    n_calls       = nrow(by_call)
  )
  list(by_call = by_call, by_model = by_model, total = total)
}


#' Reset the global token usage accumulator
#'
#' @export
token_usage_reset <- function() {
  .token_state$records <- list()
  invisible(NULL)
}


# Internal: capture only the token records produced inside `expr`. Used by
# annot_llm_annotate, sc_resolution_recommend, etc. to attribute tokens to
# specific pipeline steps without losing the global accumulator.
.with_token_scope <- function(expr) {
  before <- length(.token_state$records)
  val    <- force(expr)
  after  <- length(.token_state$records)
  step_records <- if (after > before) {
    .token_state$records[(before + 1L):after]
  } else list()
  list(value = val, records = step_records)
}


# Internal: collapse a list of token records into a tidy summary (used by
# the per-step AgentSeurat@token_usage entries).
.token_records_summarise <- function(records) {
  if (length(records) == 0) {
    return(list(n_calls = 0L,
                 input_tokens = 0L, output_tokens = 0L,
                 cached_tokens = 0L))
  }
  list(
    n_calls       = length(records),
    input_tokens  = sum(vapply(records, function(r)
                         r$input_tokens %||% NA_integer_, integer(1)),
                         na.rm = TRUE),
    output_tokens = sum(vapply(records, function(r)
                         r$output_tokens %||% NA_integer_, integer(1)),
                         na.rm = TRUE),
    cached_tokens = sum(vapply(records, function(r)
                         r$cached_tokens %||% NA_integer_, integer(1)),
                         na.rm = TRUE),
    by_model      = (function() {
      key  <- vapply(records, function(r)
                       paste(r$provider, r$model, sep = "|"), character(1))
      uk   <- unique(key)
      data.frame(
        provider      = vapply(uk, function(k) records[[which(key == k)[1]]]$provider, character(1)),
        model         = vapply(uk, function(k) records[[which(key == k)[1]]]$model,    character(1)),
        input_tokens  = vapply(uk, function(k) sum(vapply(
                          records[key == k],
                          function(r) r$input_tokens %||% NA_integer_,
                          integer(1)), na.rm = TRUE), integer(1)),
        output_tokens = vapply(uk, function(k) sum(vapply(
                          records[key == k],
                          function(r) r$output_tokens %||% NA_integer_,
                          integer(1)), na.rm = TRUE), integer(1)),
        n_calls       = vapply(uk, function(k) sum(key == k), integer(1)),
        stringsAsFactors = FALSE
      )
    })()
  )
}


# Internal: snapshot the global accumulator at entry to an LLM-using step,
# call this again at exit, store the slice in obj@token_usage[[step_name]].
# Used by sc_resolution_recommend / sc_select_pcs_visual / sc_select_batch_var
# etc. annot_llm_annotate has its own per-cluster path that also needs to
# work under parallel execution, so it uses .with_token_scope directly.
.attach_step_tokens <- function(obj, step_name, records_before) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  records_after <- length(.token_state$records)
  if (records_after > records_before) {
    slice <- .token_state$records[(records_before + 1L):records_after]
    obj@token_usage[[step_name]] <- .token_records_summarise(slice)
  }
  obj
}
