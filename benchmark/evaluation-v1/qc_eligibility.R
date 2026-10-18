# Read the frozen baseline checkpoint; never fit or change a QC rule.
a <- commandArgs(TRUE); stopifnot(length(a)==2L, file.exists(a[1]), !file.exists(a[2]))
x <- readRDS(a[1])
panel <- Filter(function(z) identical(z$preset_id,"any_quality3"), x$summary$presets)
stopifnot(length(panel)==1L, is.logical(panel[[1]]$available), length(panel[[1]]$available)==1L,
          !is.na(panel[[1]]$available))
jsonlite::write_json(list(status=if(panel[[1]]$available)"eligible" else "ineligible",
  preset=panel[[1]], checkpoint_sha256=digest::digest(file=a[1],algo="sha256"),
  original_cells=length(x$cell_ids),missing_mt=sum(!is.finite(x$metrics$percent_mt)),
  interpretation="All three frozen metrics are required; no partial OR substitution or imputation.",
  numerical_analysis_rerun=FALSE),a[2],auto_unbox=TRUE,pretty=TRUE,null="null")
