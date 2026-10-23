# Creation-time adapter. Deliberately outside sc_run/.sc_run_: the
# coordinator executes a checksummed project snapshot, never a moving default.
.sc_act_root <- function() system.file('extdata','references','act-private-2026-10-20',package='scAgentKit',mustWork=TRUE)
.sc_act_manifest <- function(root=.sc_act_root()) {
  path<-file.path(root,'PROVENANCE.json')
  expected<-'75f27aa181e616d7e6e18365691ff8612d06780879af9003f081a8acd4d35331'
  if(!file.exists(path)||nzchar(Sys.readlink(path))||!identical(digest::digest(file=path,algo='sha256'),expected))
    stop('ACT provenance changed or is missing. Restore the pinned installation; no reference was accepted.',call.=FALSE)
  manifest<-jsonlite::fromJSON(path,simplifyVector=FALSE)
  for(spec in manifest$files) {
    asset<-file.path(root,spec$file)
    if(!file.exists(asset)||nzchar(Sys.readlink(asset))||!identical(digest::digest(file=asset,algo='sha256'),spec$sha256))
      stop('ACT asset changed or is missing: ',spec$file,'. Restore the pinned installation.',call.=FALSE)
  }
  manifest
}

.sc_act_read <- function(species) {
  root<-.sc_act_root();manifest<-.sc_act_manifest(root)
  selected<-Filter(function(x)identical(x$species,species),manifest$files)
  if(length(selected)!=1L)stop('ACT covers explicit human and mouse only.',call.=FALSE)
  spec<-selected[[1L]];asset<-file.path(root,spec$file)
  con<-gzfile(asset,'rb');on.exit(close(con),add=TRUE)
  bytes<-readBin(con,'raw',n=as.integer(spec$original_bytes)+1L)
  if(length(bytes)!=spec$original_bytes||!identical(digest::digest(bytes,algo='sha256',serialize=FALSE),spec$original_sha256))
    stop('ACT decompressed source SHA256 differs; no rows were accepted.',call.=FALSE)
  raw<-utils::read.table(text=rawToChar(bytes),header=TRUE,sep='\t',quote='"',comment.char='',check.names=FALSE,
    colClasses='character',na.strings=character(),stringsAsFactors=FALSE)
  if(!identical(names(raw),unlist(manifest$columns,use.names=FALSE))||nrow(raw)!=spec$data_rows||
     any(tolower(raw$Species)!=species)||any(!startsWith(raw$SourceURL,spec$source_prefix)))
    stop('ACT schema, species, row count or source paths differ from the pinned snapshot.',call.=FALSE)
  list(raw=raw, manifest=manifest, spec=spec, asset=asset)
}

#' List exact tissue scopes in the pinned ACT snapshot
#' @param species Explicit human or mouse scope.
#' @return Data frame of literal tissue keys and source-row counts; no scope is selected.
#' @export
annot_act_scopes <- function(species) {
  loaded <- .sc_act_read(.sc_run_species(species))
  counts <- table(loaded$raw$Tissue)
  data.frame(tissue=names(counts), source_rows=as.integer(counts), stringsAsFactors=FALSE)
}

#' Load the pinned ACT snapshot offline
#' @param species Explicit human or mouse scope.
#' @param tissue Actual tissue, matched exactly after trimming/case folding.
#' @return Marker reference with original PMID/source fields and fixed provenance.
#' @export
annot_act_reference <- function(species,tissue) {
  species<-.sc_run_species(species)
  if(!is.character(tissue)||length(tissue)!=1L||is.na(tissue)||!nzchar(trimws(tissue))||tolower(trimws(tissue))=='all')
    stop('Choose an actual ACT tissue; all-tissue fallback is not supported.',call.=FALSE)
  loaded <- .sc_act_read(species)
  raw <- loaded$raw; manifest <- loaded$manifest; spec <- loaded$spec; asset <- loaded$asset
  out<-raw;names(out)[1:5]<-c('species','tissue','cell_type','marker','pmid')
  out$source_row<-seq_len(nrow(out))+1L
  for(key in c('species','tissue','cell_type','marker','pmid'))out[[paste0('act_',key,'_original')]]<-out[[key]]
  out$act_source_file_original<-out$SourceFile;out$act_source_url_original<-out$SourceURL
  out$species<-rep(species,nrow(out))
  keep<-tolower(trimws(out$tissue))==tolower(trimws(tissue))
  out<-out[keep,,drop=FALSE];out$source<-rep('ACT',nrow(out));out<-.explode_markers(out);rownames(out)<-NULL
  attr(out,'reference_source')<-'ACT';attr(out,'source_mode')<-'bundled_ACT_snapshot'
  attr(out,'source_path')<-asset;attr(out,'source_sha256')<-spec$sha256;attr(out,'source_md5')<-unname(tools::md5sum(asset))
  attr(out,'original_sha256')<-spec$original_sha256;attr(out,'source_url')<-manifest$source_page
  attr(out,'requested_url')<-manifest$source_page;attr(out,'source_url_verified')<-FALSE
  attr(out,'source_version')<-manifest$snapshot_id;attr(out,'source_date')<-NA_character_
  attr(out,'retrieved_at')<-manifest$downloaded_date_as_supplied
  attr(out,'license')<-manifest$license_terms
  attr(out,'act_snapshot')<-manifest;attr(out,'act_citation')<-manifest$citation
  attr(out,'n_input_rows')<-spec$data_rows;attr(out,'species')<-species;attr(out,'tissue_filter')<-trimws(tissue)
  attr(out,'scope_status')<-if(nrow(out))'matched' else 'zero_matches'
  attr(out,'scope_notice')<-if(nrow(out))'ACT rows match the exact declared species/tissue.' else
    paste0('ACT has no exact match for species=',species,', tissue=',trimws(tissue),'. No broader tissue or cross-species fallback was used.')
  out
}

.sc_ui_act_default <- function(context, tissue = context$tissue) {
  species<-tryCatch(.sc_run_species(context$species),error=function(e)NULL)
  if(is.null(species)||!is.character(tissue)||length(tissue)!=1L||is.na(tissue)||!nzchar(trimws(tissue))||tolower(trimws(tissue))=='all') {
    message('ACT default needs explicit human/mouse species and an actual tissue; reference matching remains unassessed.');return(NULL)
  }
  ref<-annot_act_reference(species,tissue)
  if(!nrow(ref))message(attr(ref,'scope_notice'), ' Inspect annot_act_scopes(species); choose reference_tissue explicitly rather than changing study facts.')
  ref
}
.sc_ui_act_provenance <- function(reference) {
  manifest<-attr(reference,'act_snapshot')
  if(is.null(manifest))return(list())
  list(original_sha256=attr(reference,'original_sha256'),
    preparation_note=paste(attr(reference,'scope_notice'),'ACT snapshot downloaded',manifest$downloaded_date_as_supplied,
      '; publisher release/date:',manifest$publisher_release,manifest$publisher_release_date,
      '; snapshot license:',manifest$license_terms,'. Citation:',manifest$citation$title,
      'DOI',manifest$citation$doi,'PMID',manifest$citation$pmid))
}
