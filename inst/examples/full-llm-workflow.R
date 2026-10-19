# Source only defines this helper. It never installs software or reads a key.
# The researcher must review the exact categories/provider/USD cap and call
# with confirmed=TRUE. Keys stay in the runtime environment, never arguments.
# Opening the browser stages drafts; three scientific approvals remain manual.
full_llm_start <- function(input, project_dir, context, provider, budget,
                           reviewer, reason, categories, confirmed=FALSE,
                           browse=interactive()) {
  if(!isTRUE(confirmed))stop("Review the data categories, provider/model and USD cap before confirming project transfer consent.",call.=FALSE)
  scAgentKit::sc_start(input,project_dir,context=context,provider=provider,budget=budget,
    review=list(allow_external=TRUE,transfer_consent=list(mode="project",confirmed=TRUE,
      reviewer=reviewer,reason=reason,categories=categories)),browse=browse)
}
# For strict per-payload consent, call sc_start directly with
# review=list(allow_external=TRUE), omitting transfer_consent.
# Without an available configured key, sc_start explains the manual fallback.
# Prices/usage need provider-specific validation; a mock is not fee calibration.
