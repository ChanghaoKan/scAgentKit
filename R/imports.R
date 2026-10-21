# Provider factories and token utilities. Project authority belongs to the reviewed engine.
# ---- Provider and token helpers used by the reviewed engine ----
# Project objects and authority are owned by sc_run; generic object-workflow facades are not exported.

#' @importFrom agentomicsCore chat_claude
#' @export
agentomicsCore::chat_claude

#' @importFrom agentomicsCore chat_openai
#' @export
agentomicsCore::chat_openai

#' @importFrom agentomicsCore chat_deepseek
#' @export
agentomicsCore::chat_deepseek

#' @importFrom agentomicsCore chat_grok
#' @export
agentomicsCore::chat_grok

#' @importFrom agentomicsCore chat_qwen
#' @export
agentomicsCore::chat_qwen

#' @importFrom agentomicsCore chat_kimi
#' @export
agentomicsCore::chat_kimi

#' @importFrom agentomicsCore list_chat_providers
#' @export
agentomicsCore::list_chat_providers

#' @importFrom agentomicsCore make_chat_fn_claude
#' @export
agentomicsCore::make_chat_fn_claude

#' @importFrom agentomicsCore make_chat_fn_openai_compat
#' @export
agentomicsCore::make_chat_fn_openai_compat

#' @importFrom agentomicsCore make_chat_fn_openai_compatible
#' @export
agentomicsCore::make_chat_fn_openai_compatible









#' @importFrom agentomicsCore token_usage_summary
#' @export
agentomicsCore::token_usage_summary

#' @importFrom agentomicsCore token_usage_reset
#' @export
agentomicsCore::token_usage_reset

# Single package-wide NULL-coalescing helper. Missing means NULL, a
# zero-length value, or a scalar NA. Callers use these three fallbacks.
# Do not redefine it elsewhere: without a Collate field the
# alphabetically last definition silently wins for the whole namespace.
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.atomic(a) && is.na(a))) b else a
}
