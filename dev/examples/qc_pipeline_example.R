# Development-only driver. Run from the repository root, or set option scAgentKit.dev_examples.
# This file is excluded from the installed examples and package archive.
# Start QC review through the single saved-project workflow.
# This function only prepares a review; real-study approvals remain the analyst's.
qc_pipeline_example <- function(input,project_dir,context) {
  scAgentKit::sc_review(scAgentKit::sc_analyze(input,project_dir,context=context))
}
