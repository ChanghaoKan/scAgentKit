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
# For standard DeepSeek Flash, omitted budget in sc_start selects USD1.
# This project-scope helper requires an explicit chosen cap, for example budget=1
# or budget=.73; confirmed=TRUE covers that actual cap and the data categories.
# Existing project caps stay frozen; a model cannot increase them.
# Prices/usage need provider-specific validation; a mock is not fee calibration.
