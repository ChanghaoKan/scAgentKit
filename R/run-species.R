# Explicit supported-species aliases, never inferred from gene symbols or
# capitalization. Missing declarations stay unknown; other organisms fail.
.sc_run_species <- function(species, allow_missing = FALSE) {
  if (is.null(species)) {
    if (isTRUE(allow_missing)) return(NULL)
    .sc_project_fail("Declare species explicitly as human/Homo sapiens or mouse/Mus musculus; gene symbols do not determine species.")
  }
  .sc_project_string(species, "species")
  canonical <- .sc_run_species_values(species)
  if (!is.na(canonical)) return(unname(canonical))
  .sc_project_fail("Unsupported species: this version supports only Homo sapiens (human) and Mus musculus (mouse), with explicit documented aliases. No ortholog or case-based inference is performed.")
}

.sc_run_species_values <- function(values) {
  aliases <- list(
    human = c("human", "homo sapiens", "homo_sapiens", "homo-sapiens", "h. sapiens", "h.sapiens", "hsapiens", "9606"),
    mouse = c("mouse", "mus musculus", "mus_musculus", "mus-musculus", "m. musculus", "m.musculus", "mmusculus", "10090"))
  dictionary <- stats::setNames(rep(names(aliases), lengths(aliases)), unlist(aliases, use.names = FALSE))
  unname(dictionary[tolower(trimws(as.character(values)))])
}
