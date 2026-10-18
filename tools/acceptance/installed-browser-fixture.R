#!/usr/bin/env Rscript
# Installed-package-only setup/oracle. Never source implementation or make decisions.
a <- commandArgs(TRUE)
stopifnot(length(a) == 4L)
action <- a[[1L]]; output <- normalizePath(a[[2L]], mustWork=TRUE)
.libPaths(c(normalizePath(a[[3L]], mustWork=TRUE), .libPaths()))
archive <- normalizePath(a[[4L]], mustWork=TRUE)
suppressPackageStartupMessages(library(scAgentKit))
write_json <- function(x, name) jsonlite::write_json(x, file.path(output,name), auto_unbox=TRUE, pretty=TRUE, null='null')
project <- file.path(output,'project'); input <- file.path(output,'input.rds')
if (action == 'setup') {
  stopifnot(!dir.exists(project), !file.exists(input))
  stopifnot(is.null(getOption('scAgentKit.checkout')))
  installed <- find.package('scAgentKit')
  runtime <- system.file('workbench',package='scAgentKit',mustWork=TRUE)
  temporary <- tempfile('archive-identity-'); dir.create(temporary)
  utils::untar(archive, exdir=temporary)
  archived <- list.dirs(temporary, recursive=FALSE)[[1L]]
  stopifnot(read.dcf(file.path(archived,'DESCRIPTION'))[1,'Version'] == as.character(packageVersion('scAgentKit')))
  manifest <- 'runtime-manifest.json'
  built <- jsonlite::read_json(file.path(archived,'inst','workbench',manifest))
  live <- jsonlite::read_json(file.path(runtime,manifest))
  stopifnot(identical(built$schema,live$schema))
  # Install-time manifest rebuilding may reorder named entries by OS locale.
  for (field in c('functions','assets')) {
    stopifnot(setequal(names(built[[field]]),names(live[[field]])))
    for (name in names(built[[field]])) stopifnot(identical(built[[field]][[name]],live[[field]][[name]]))
  }

  unlink(temporary,recursive=TRUE)
  data('pbmc_small',package='SeuratObject',envir=environment())
  pbmc_small$acceptance_sample <- rep(c('offline_A','offline_B'),length.out=ncol(pbmc_small))
  saveRDS(pbmc_small,input)
  # sc_start defaults to raw reanalysis, model_suggestions='off', no provider.
  launch <- NULL
  invisible(capture.output(launch <- sc_start(input, project, context=list(
    species='human',tissue='public PBMC software fixture',
    research_goal='Offline software acceptance; Unknown labels, no biological accuracy claim',
    columns=list(sample='acceptance_sample')), browse=FALSE,model_suggestions='off')))
  write_json(list(launch=launch,package=installed,runtime=runtime,
    version=as.character(packageVersion('scAgentKit')), R=R.version.string,
    input_cells=colnames(pbmc_small), archive_sha256=digest::digest(file=archive,algo='sha256'),
    model_suggestions='off', source_checkout=NULL), 'launch.json')
} else if (action == 'reopen') {
  launch <- NULL
  invisible(capture.output(launch <- sc_start(input,project,browse=FALSE,model_suggestions='off')))
  write_json(list(launch=launch,view=sc_run_inspect(project)), 'reopen.json')
} else if (action == 'verify') {
  view <- sc_run_inspect(project)
  stopifnot(identical(view$status,'complete'), identical(view$stage,'complete'))
  final <- readRDS(view$output$seurat); original <- readRDS(input)
  stopifnot(ncol(final)>0L, all(colnames(final) %in% colnames(original)),
    all(tolower(as.character(final$sc_annotation))=='unknown'),
    file.exists(view$output$report))
  history <- jsonlite::read_json(file.path(project,'decision_history.json'),simplifyVector=FALSE)
  events <- history$events
  executed <- vapply(Filter(function(x) identical(x$action,'executed'),events),function(x)x$details$stage,'')
  stopifnot(sum(executed=='finalize')==1L, sum(executed=='annotation_apply')==1L)
  approved <- Filter(function(x) identical(x$action,'approved'),events)
  kinds <- vapply(approved,function(x)x$details$kind,'')
  stopifnot(sum(kinds=='annotation')==1L, sum(kinds=='strategy')>=1L)
  state <- readRDS(file.path(project,'state.rds'))
  artifact <- function(name) {
    record <- state$files[[name]]; stopifnot(!is.null(record))
    file <- file.path(project,record$path)
    stopifnot(file.exists(file),identical(digest::digest(file=file,algo='sha256'),record$sha256))
    readRDS(file)
  }
  ledger_path <- file.path(project,'provider','ledger.json')
  ledger_exists <- file.exists(ledger_path)
  ledger <- if(ledger_exists) jsonlite::read_json(ledger_path) else list(schema='scagentkit.provider-ledger.v1',entries=list())
  stopifnot(is.list(ledger),identical(ledger$schema,'scagentkit.provider-ledger.v1'),
    'entries' %in% names(ledger),is.list(ledger$entries),length(ledger$entries)==0L,identical(state$config$provider$name,'manual'),
    identical(state$config$provider$external,FALSE))
  selection <- jsonlite::read_json(file.path(output,'author-selection.json'))
  review <- artifact('strategy_review'); scan <- artifact('cluster_scan')
  analysis <- artifact('analysis'); markers <- artifact('markers'); evidence <- artifact('annotation_evidence')
  last_strategy <- tail(Filter(function(x) identical(x$details$kind,'strategy'),approved),1L)[[1L]]
  stopifnot(identical(last_strategy$details$review_hash,review$hash),
    identical(review$details$cluster_diagnostics$hash,scan$hash),
    identical(selection$scan_hash,scan$hash),
    identical(selection$resolution,review$details$canonical_proposal$clustering$resolution),
    identical(analysis@misc$strategy_execution$cluster$resolution,selection$resolution))
  expected <- analysis@misc$strategy_execution$cluster$diagnostic_assignments[[as.character(selection$resolution)]]
  membership <- as.character(analysis[[]][[state$config$cluster_column]])
  stopifnot(identical(names(expected),colnames(analysis)),identical(unname(expected),membership),
    identical(digest::digest(expected,algo='sha256',serializeVersion=2L),
      scan$membership_hashes[[as.character(selection$resolution)]]),
    identical(colnames(analysis),colnames(final)),
    identical(as.character(final[[]][[state$config$cluster_column]]),membership),
    identical(evidence$private$input_cells$cell_id,colnames(analysis)),
    identical(evidence$private$input_cells$cluster,membership),
    identical(markers$cluster_column,state$config$cluster_column))
  # Independently project actual final marker rows to the measured scan format.
  table <- markers$marker_summary
  marker_records <- lapply(seq_len(nrow(table)),function(i) list(
    clusterId=as.character(table$cluster[i]),gene=as.character(table$gene[i]),
    avgLog2FC=unname(table$avg_log2FC[i]),pct1=unname(table$pct.1[i]),
    pct2=unname(table$pct.2[i]),pAdj=unname(table$p_val_adj[i]),source='Seurat::FindAllMarkers'))
  stopifnot(isTRUE(all.equal(marker_records,scan$markers[[as.character(selection$resolution)]]$markers,tolerance=1e-10)),
    identical(markers$parameters,scan$markers[[as.character(selection$resolution)]]$parameters))
  resolution_binding <- list(resolution=selection$resolution,scan_hash=scan$hash,
    strategy_review_hash=review$hash,membership_hash=scan$membership_hashes[[as.character(selection$resolution)]],
    marker_rows=nrow(table),actual_final_membership_and_markers_verified=TRUE)
  write_json(list(status='passed',view=view,cells=ncol(final),labels=unique(final$sc_annotation),
    output_sha256=digest::digest(file=view$output$seurat,algo='sha256'),
    executed_stages=executed,approval_kinds=kinds,ledger=ledger,ledger_file_exists=ledger_exists,provider_calls=length(ledger$entries),
    provider=state$config$provider,resolution_binding=resolution_binding,
    scientific_accuracy_tested=FALSE),'r-output-verification.json')
} else stop('Unknown action')
