# Bridge layer: aliases agentomicsCore's public extension API back into
# scAgentKit's namespace using the legacy `.`-prefixed names that the
# scAgentKit source files (qc-*.R, sc-*.R, annot-*.R) historically used.
#
# This lets the ~7000 lines of existing scAgentKit source compile without
# rewriting every call site of `.record_step()`, `.find_in_decisions()`,
# `.attach_step_tokens()`, etc.
#
# When/if we ever rewrite those files, this file can be deleted.
#
# All assignments are made at package-load time. They are not @export'd
# (they're internal aliases).

#' @importFrom agentomicsCore record_step find_in_decisions
#' @importFrom agentomicsCore token_record token_records_summarise
#' @importFrom agentomicsCore with_token_scope attach_step_tokens
#' @importFrom agentomicsCore esc_html
NULL

# ---- Re-exports for backward compatibility ----
# Users who previously called scAgentKit::chat_claude(), ::save_checkpoint(),
# ::get_decisions(), etc. continue to work after the v0.3.0 refactor.
# These use the standard roxygen re-export idiom: each `@importFrom` +
# `@export` + bare `agentomicsCore::name` line makes roxygen generate both
# importFrom(agentomicsCore, name) and export(name), bundling them into a
# single reexports.Rd. (This is exactly how tidyverse packages re-export
# magrittr's pipe.)

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

#' @importFrom agentomicsCore save_checkpoint
#' @export
agentomicsCore::save_checkpoint

#' @importFrom agentomicsCore load_checkpoint
#' @export
agentomicsCore::load_checkpoint

#' @importFrom agentomicsCore export_decisions
#' @export
agentomicsCore::export_decisions

#' @importFrom agentomicsCore get_decisions
#' @export
agentomicsCore::get_decisions

#' @importFrom agentomicsCore get_script
#' @export
agentomicsCore::get_script

#' @importFrom agentomicsCore get_figures
#' @export
agentomicsCore::get_figures

#' @importFrom agentomicsCore get_token_usage
#' @export
agentomicsCore::get_token_usage

#' @importFrom agentomicsCore upgrade_checkpoint
#' @export
agentomicsCore::upgrade_checkpoint

#' @importFrom agentomicsCore token_usage_summary
#' @export
agentomicsCore::token_usage_summary

#' @importFrom agentomicsCore token_usage_reset
#' @export
agentomicsCore::token_usage_reset

#' Extract the underlying Seurat object (backward-compatible alias)
#'
#' Alias for [agentomicsCore::get_data()], kept so existing
#' `scAgentKit::get_seurat()` calls keep working after the v0.3.0
#' refactor.
#'
#' @param obj An AgentSeurat (or AgentOmics) object.
#' @return The wrapped Seurat object, or a list of Seurat objects.
#' @export
get_seurat <- function(obj) {
  agentomicsCore::get_data(obj)
}


#' Export accumulated scRNA-seq analysis snippets
#'
#' scAgentKit wrapper around [agentomicsCore::export_script()] that emits
#' the standard single-cell library preamble (`Seurat`, `dplyr`,
#' `tibble`, `qs2`).
#'
#' @inheritParams agentomicsCore::export_script
#' @return Invisibly returns `path`.
#' @export
export_script <- function(obj,
                          path           = "reproducible_script.R",
                          header_comment = NULL) {
  agentomicsCore::export_script(
    obj,
    path           = path,
    header_comment = header_comment,
    libraries      = c("Seurat", "dplyr", "tibble", "qs2"),
    title          = "Generated scRNA-seq analysis trace",
    generated_by   = "scAgentKit"
  )
}

# ---- Internal alias layer (legacy ".name" -> public "name") ----
.record_step             <- function(...) agentomicsCore::record_step(...)
.find_in_decisions       <- function(...) agentomicsCore::find_in_decisions(...)
.attach_step_tokens      <- function(...) agentomicsCore::attach_step_tokens(...)
.record_figure           <- function(...) agentomicsCore::record_figure(...)
.apply_to_data           <- function(...) agentomicsCore::apply_to_data(...)
.with_token_scope        <- function(expr) {
  # with_token_scope expects an unevaluated expression; forward via
  # substitute() so the lazy semantics survive the alias hop.
  agentomicsCore::with_token_scope(expr)
}
.token_record            <- function(...) agentomicsCore::token_record(...)
.token_records_summarise <- function(...) agentomicsCore::token_records_summarise(...)
.esc                     <- function(x) agentomicsCore::esc_html(x)

# Environment alias: the token state lives in agentomicsCore's namespace.
# Because environments are reference objects, binding .token_state to the
# SAME environment here means that when agentomicsCore's chat_fn wrappers
# mutate it (token_state$records[[...]] <- rec), scAgentKit code reading or
# writing .token_state$records sees the identical environment. This works
# because agentomicsCore (an Imports dependency) is guaranteed loaded
# before this file is sourced.
.token_state <- agentomicsCore::token_state

# The %||% infix is re-exported via the @importFrom roxygen tag above;
# any duplicate `%||%` definitions still living in the older source
# files of scAgentKit (annot-llm.R, sc-resolution-recommend.R, etc.)
# remain compatible because they are identical.

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) b else a
}
