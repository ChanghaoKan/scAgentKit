# Shared provider pricing defaults. Costs are recorded from actual usage,
# independently of transfer consent.
.sc_run_provider_defaults <- function(provider = NULL, chat_fn = NULL) {
  spec <- .sc_run_provider_spec(provider, chat_fn)
  metadata <- spec$metadata
  rates <- list(cached_input_per_million = .006, input_per_million = .30, output_per_million = 1.20)
  eligible <- is.null(spec$fn) && identical(metadata$name, 'deepseek') && identical(metadata$model, 'deepseek-flash') &&
    metadata$generation$max_tokens <= 4096 && identical(metadata$generation$thinking$type, 'disabled') &&
    (is.null(metadata$pricing) || isTRUE(all.equal(metadata$pricing, rates)))
  if (eligible && is.null(metadata$pricing)) metadata$pricing <- rates
  list(provider = metadata, chat_fn = spec$fn)
}
