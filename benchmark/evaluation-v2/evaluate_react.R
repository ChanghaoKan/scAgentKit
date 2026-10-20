# Thin versioned adapter. Reuse evaluation-v1 preparation and label-map sections;
# all scoring lives in sc_react_eval, not a second benchmark implementation.
evaluate_react <- function(project, truth, external = list(), label_map_file = NULL,
                           prediction_section = NULL, truth_section = NULL,
                           allowed_ancestors = character(), output_dir = NULL) {
  maps <- NULL
  if (!is.null(label_map_file)) {
    source <- jsonlite::fromJSON(label_map_file, simplifyVector = FALSE)
    section <- function(name) {
      if (is.null(name) || !name %in% names(source) || !is.list(source[[name]]))
        stop("Choose an existing label-map object section.")
      unlist(source[[name]], use.names = TRUE)
    }
    maps <- list(prediction = section(prediction_section), truth = section(truth_section))
  }
  scAgentKit::sc_react_eval(project, truth, external = external, label_map = maps,
    allowed_ancestors = allowed_ancestors, output_dir = output_dir)
}
