# Generate from the single canonical runtime and parsed R function constructors.
# Installation needs only existing package dependencies, never Python.
root <- normalizePath(".", mustWork = TRUE)
runtime <- file.path(root, "inst", "workbench")
definitions <- list()
for (file in sort(list.files(file.path(root, "R"), "[.]R$", full.names = TRUE))) {
  for (expr in parse(file)) if (is.call(expr) && identical(expr[[1]], as.name("<-")) &&
      is.symbol(expr[[2]]) && is.call(expr[[3]]) && identical(expr[[3]][[1]], as.name("function")))
    definitions[[as.character(expr[[2]])]] <- eval(expr[[3]], envir = baseenv())
}
selected <- sort(unique(c(grep("^(sc_run|\\.sc_project_format_|\\.sc_run_|\\.sc_ui_|\\.sc_start_|\\.sc_marker_|\\.sc_reference_|\\.validate_|\\.decision_|\\.review_)", names(definitions), value=TRUE),
  "sc_analyze", "sc_open", "sc_review", "sc_start", "sc_project_prepare", ".sc_project_layer",
  ".sc_project_identity", ".adjusted_rand_index", "sc_cycle_gene_set")))
signature <- function(fn) list(formals=paste(deparse(formals(fn),width.cutoff=500L),collapse="\n"),
  body=paste(deparse(body(fn),width.cutoff=500L),collapse="\n"))
functions <- setNames(lapply(selected,function(name) digest::digest(signature(definitions[[name]]),
  algo="sha256",serializeVersion=2L)), selected)
files <- sort(list.files(runtime, recursive=TRUE, all.files=TRUE, no..=TRUE))
files <- files[!grepl("(^|/)(__pycache__|[.]local)(/|$)|[.]pyc$|(^|/)[.]DS_Store$|^runtime-manifest[.]json$",files)]
assets <- setNames(lapply(files,function(path) digest::digest(file=file.path(runtime,path),algo="sha256")),files)
jsonlite::write_json(list(schema="scagentkit.runtime.v1", functions=functions, assets=assets),
  file.path(runtime,"runtime-manifest.json"),auto_unbox=TRUE,pretty=TRUE)
