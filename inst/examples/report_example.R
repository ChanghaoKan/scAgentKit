# Reopen saved output paths and scientific-assessment limits; never resume analysis.
report_example <- function(project_dir) {
  project<-scAgentKit::sc_open(project_dir)
  list(status=project$view$status,output=project$view$output,
    scientific_assessment=project$view$scientific_assessment)
}
