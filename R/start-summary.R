# Read-only setup feedback. Availability is not scientific suitability.
.sc_start_summary <- function(setup, mode, processed = FALSE) {
  provider <- setup$provider
  consent <- if (!isTRUE(setup$review$allow_external)) "external transfer disabled" else
    if (identical(setup$review$transfer_consent$mode, "project")) "explicit saved project scope" else "exact payload approval required"
  key_ready <- !isTRUE(provider$external) || (!is.null(provider$api_key_env) && nzchar(trimws(Sys.getenv(provider$api_key_env))))
  message("Startup mode: ", mode, "; provider: ", provider$name,
    if (!is.null(provider$model)) paste0(" / ", provider$model),
    if (!is.null(provider$base_url)) paste0("; destination: ", provider$base_url),
    "; consent: ", consent, "; credential: ", if (key_ready) "available or unnecessary" else "missing",
    ". Startup sends no model request. Provider and transfer policy are fixed for this project.")
  if (processed) {
    message("Method readiness: processed foundation reused; no new doublet or Harmony execution is started.")
    return(invisible(NULL))
  }
  probes <- list(doublet = function() {
    .sc_run_doublet_dependencies()
    .sc_run_doublet_classifier_adapter()
  }, Harmony = .sc_run_harmony_source)
  for (name in names(probes)) {
    result <- tryCatch({probes[[name]](); "software available; study design and scientific review still required"},
      error = function(e) paste0("software unavailable for the supported adapter: ", conditionMessage(e)))
    message(name, " readiness: ", result)
  }
  message("Optional methods are not auto-installed or executed. Use the isolated environment recipe in docs/LINUX_RUNTIME_SUPPORT.md; missing design evidence remains unassessed.")
  invisible(NULL)
}
