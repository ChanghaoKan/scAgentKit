# Runtime identity is independent of saved scientific execution fingerprints.
.sc_start_signature <- function(fn) {
  list(formals=paste(deparse(formals(fn),width.cutoff=500L),collapse="\n"),
    body=paste(deparse(body(fn),width.cutoff=500L),collapse="\n"))
}

.sc_start_runtime_check <- function(runtime, checkout = NULL) {
  runtime <- normalizePath(runtime,mustWork=TRUE)
  manifest_path <- file.path(runtime,"runtime-manifest.json")
  if (!file.exists(manifest_path)) stop("Runtime manifest missing; reinstall the matching package.",call.=FALSE)
  manifest <- jsonlite::fromJSON(manifest_path,simplifyVector=FALSE)
  if (!identical(manifest$schema,"scagentkit.runtime.v1")) stop("Unsupported runtime manifest.",call.=FALSE)
  ns <- asNamespace("scAgentKit")
  selected <- sort(unique(c(grep("^(sc_run|\\.sc_project_format_|\\.sc_run_|\\.sc_ui_|\\.sc_start_|\\.sc_marker_|\\.sc_reference_|\\.validate_|\\.decision_|\\.review_)",ls(ns,all.names=TRUE),value=TRUE),
    "sc_analyze","sc_open","sc_review","sc_start","sc_project_prepare",".sc_project_layer",
    ".sc_project_identity",".adjusted_rand_index","sc_cycle_gene_set")))
  if (!setequal(selected,names(manifest$functions))) stop("Installed package and runtime expose different workflow functions.",call.=FALSE)
  for (name in selected) if (!identical(digest::digest(.sc_start_signature(get(name,ns)),
      algo="sha256",serializeVersion=2L),manifest$functions[[name]]))
    stop("Installed package and runtime differ; install the matching package before starting.",call.=FALSE)
  files <- sort(list.files(runtime,recursive=TRUE,all.files=TRUE,no..=TRUE))
  files <- files[!grepl("(^|/)(__pycache__|[.]local)(/|$)|[.]pyc$|(^|/)[.]DS_Store$|^runtime-manifest[.]json$",files)]
  if (!setequal(files,names(manifest$assets))) stop("Runtime asset inventory differs; reinstall before starting.",call.=FALSE)
  for (file in files) if (!identical(digest::digest(file=file.path(runtime,file),algo="sha256"),manifest$assets[[file]]))
    stop("Runtime asset changed: ",file,". Reinstall before starting.",call.=FALSE)
  if (!is.null(checkout)) {
    definitions <- list()
    for (file in sort(list.files(file.path(checkout,"R"),"[.]R$",full.names=TRUE))) {
      for (expr in parse(file)) if (is.call(expr) && identical(expr[[1]],as.name("<-")) &&
          is.symbol(expr[[2]]) && is.call(expr[[3]]) && identical(expr[[3]][[1]],as.name("function")))
        definitions[[as.character(expr[[2]])]] <- eval(expr[[3]],envir=baseenv())
    }
    source_names <- grep("^(sc_run|\\.sc_project_format_|\\.sc_run_|\\.sc_ui_|\\.sc_start_|\\.sc_marker_|\\.sc_reference_|\\.validate_|\\.decision_|\\.review_)",names(definitions),value=TRUE)
    if (!setequal(source_names,grep("^(sc_run|\\.sc_project_format_|\\.sc_run_|\\.sc_ui_|\\.sc_start_|\\.sc_marker_|\\.sc_reference_|\\.validate_|\\.decision_|\\.review_)",selected,value=TRUE)))
      stop("Installed package and source checkout expose different workflow functions.",call.=FALSE)
    for (name in selected) if (is.null(definitions[[name]]) ||
        !identical(.sc_start_signature(get(name,ns)),.sc_start_signature(definitions[[name]])))
      stop("Installed package and source checkout differ. Install this checkout first.",call.=FALSE)
  }
  invisible(runtime)
}
