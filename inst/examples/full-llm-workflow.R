# Sourcing defines a helper and sends nothing. Credentials stay in the named
# provider environment variable. Confirm aggregate data transfer once; every
# scientific decision still needs a separate human approval in the browser.
full_llm_start <- function(input, project_dir, context, provider, budget = NULL,
                           reviewer, reason, categories, confirmed = FALSE,
                           browse = interactive(), react = "auto") {
  if (!isTRUE(confirmed)) stop("Review the provider/model and aggregate data categories, then confirm transfer. Usage and costs are recorded afterwards.", call. = FALSE)
  scAgentKit::sc_start(input, project_dir, context = context, provider = provider,
    budget = budget, react = react,
    review = list(allow_external = TRUE, transfer_consent = list(mode = "project",
      confirmed = TRUE, reviewer = reviewer, reason = reason, categories = categories)),
    browse = browse)
}
# 1. Review the initial strategy and diagnostic QC/batch evidence; adopt/edit
#    the prepared draft, then approve it. Saving/adopting is not approval.
# 2. Review the measured resolution scan and batch-preservation evidence;
#    adopt/edit the next draft and approve the selected scanned resolution.
# 3. Review annotation and ACT agreement. ReAct auto checks low-confidence,
#    Unknown or conflicting clusters. Expand evidence steps, adopt/edit, approve.
# 4. Retrieve sc_result(sc_open(project_dir)). Reopen with sc_start using the
#    same input/project; omit settings to retain the saved configuration.
# 5. sc_react_replay(project_dir) reconstructs the original saved draft offline.
#    sc_react_eval(project_dir, truth="truth.csv") compares evaluator-only truth.
# react="all" checks every cluster; react="off" keeps the one-shot draft.
# Strict per-payload transfer: sc_start(..., review=list(allow_external=TRUE)).
# Missing key falls back visibly to manual mode. No call is resent automatically
# after uncertain delivery. All requests use post-call accounting; the deprecated
# budget argument does not impose a cap.
