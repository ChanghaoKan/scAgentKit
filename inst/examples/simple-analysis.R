# Installed offline software check: one public three-gate engine.
# The helper name is retained solely because the published README installation
# check invokes it. It delegates to the one current tutorial, not another pipeline.
simple_analysis_after <- function(project_dir) {
  env<-new.env(parent=environment())
  sys.source(system.file("examples","three-gate-analysis.R",package="scAgentKit"),envir=env)
  env$three_gate_analysis(project_dir)$result
}
