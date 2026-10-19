# Development-only driver. Run from the repository root, or set option scAgentKit.dev_examples.
# This file is excluded from the installed examples and package archive.
# Public offline software control, not an automatic real-study analysis.
# Source and call public_workflow_example() with a NEW project directory.
public_workflow_example <- function(project_dir) {
  env<-new.env(parent=environment())
  sys.source(file.path(getOption("scAgentKit.dev_examples", file.path(getwd(), "dev", "examples")), "three-gate-analysis.R"),envir=env)
  env$three_gate_analysis(project_dir)
}
