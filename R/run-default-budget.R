# Only this measured provider/model/output bound receives a paid default.
# This configures a cap, never consent, client construction or dispatch.
.sc_run_new_budget <- function(provider = NULL, budget = NULL, chat_fn = NULL) {
  spec <- .sc_run_provider_spec(provider, chat_fn)
  metadata <- spec$metadata
  rates <- list(cached_input_per_million = .006, input_per_million = .30, output_per_million = 1.20)
  eligible <- is.null(spec$fn) && identical(metadata$name, 'deepseek') && identical(metadata$model, 'deepseek-flash') &&
    metadata$generation$max_tokens <= 4096 && identical(metadata$generation$thinking$type, 'disabled') &&
    metadata$reservation_usd <= .05 && (is.null(metadata$pricing) || isTRUE(all.equal(metadata$pricing, rates)))
  if (eligible && is.null(metadata$pricing)) metadata$pricing <- rates
  amount <- if (is.null(budget)) if (eligible) 1.00 else 0 else .sc_run_provider_number(budget, 'budget')
  list(provider = metadata, budget = amount, calibrated = eligible, chat_fn = spec$fn)
}
