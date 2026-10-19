# Public offline software control, not an automatic real-study analysis.
# Source and call public_workflow_example() with a NEW project directory.
public_workflow_example <- function(project_dir) {
  env<-new.env(parent=environment())
  sys.source(system.file("examples","three-gate-analysis.R",package="scAgentKit"),envir=env)
  env$three_gate_analysis(project_dir)
}
