# Diagnostic-only marker work uses a fixed native prefilter. The final selected
# cohort still calls .sc_run_markers with the unchanged full-result config.
.sc_run_scan_marker_config <- function(config,top_n=30L) {
  out<-config
  requested<-if(is.null(config$markers))list()else config$markers
  out$markers<-utils::modifyList(requested,list(only_pos=TRUE,min_pct=.25,
    logfc_threshold=.25,log2fc_cut=.25,top_n=as.integer(top_n)))
  out
}

.sc_run_scan_marker_programs <- function(markers,context) {
  ids<-sort(unique(as.character(markers$cluster)),method="radix")
  ribosomal<-"^(RPL[0-9]+[A-Z]?|RPS[0-9]+[A-Z]?|RPLP[0-2]|RPSA)$"
  human<-identical(context$species,"human")
  rows<-lapply(ids,function(id) {
    selected<-markers[as.character(markers$cluster)==id&markers$avg_log2FC>0&markers$pct.1>markers$pct.2,,drop=FALSE]
    selected<-selected[order(-selected$avg_log2FC,-(selected$pct.1-selected$pct.2),selected$gene),,drop=FALSE]
    genes<-as.character(head(selected$gene,30L))
    symbols<-length(genes)>0L&&!any(grepl("^ENS(MUS)?G[0-9]+",genes))
    list(clusterId=id,top_gene_count=length(genes),top_genes=.sc_project_array(genes),
      symbol_status=if(symbols)"literal_symbols"else"unavailable_or_unmapped_identifiers",
      ribosomal_fraction=if(symbols)mean(grepl(ribosomal,genes,ignore.case=TRUE))else NULL,
      mitochondrial_fraction=if(symbols)mean(grepl("^MT[-.]",genes,ignore.case=TRUE))else NULL,
      cycle_status=if(human&&symbols)"human_review_list"else"unavailable_no_supported_symbol_mapping",
      cycle_fraction=if(human&&symbols)mean(genes%in%.cell_cycle_marker_set())else NULL)
  })
  list(schema="scagentkit.scan-marker-programs.v1",rows=rows,
    policy="Fractions among at most 30 native positive, detection-concordant markers ranked by fold change then detection difference. Human cycle list is a review heuristic, not a noise/lineage classifier; no mouse ortholog guessing.")
}

.sc_run_adjacent_split_markers <- function(seu,config,assignments) {
  records<-list()
  if(length(assignments)<2L)return(list(schema="scagentkit.adjacent-split-markers.v1",records=records))
  # Exact cell alignment is checked by the complete scan tree before this call.
  for(i in seq.int(2L,length(assignments))) {
    parent<-assignments[[i-1L]];child<-assignments[[i]]
    for(label in sort(unique(parent),method="radix")) {
      selected<-parent==label
      sizes<-table(child[selected])
      if(length(sizes)<2L)next
      record<-list(from_resolution=as.numeric(names(assignments)[i-1L]),to_resolution=as.numeric(names(assignments)[i]),
        parent_cluster=label,cells=as.integer(sum(selected)),cell_scope_hash=.sc_run_hash(names(parent)[selected]),
        child_sizes=lapply(names(sizes),function(id)list(clusterId=id,cells=as.integer(sizes[[id]]))),
        contrast="Each child versus the other children WITHIN this exact parent scope; saved normalized RNA, no new normalization or clustering.",
        status="unavailable_small_child",markers=list(),parameters=NULL,warnings=list())
      if(all(sizes>=3L)) {
        working<-seu[,names(parent)[selected],drop=FALSE]
        working[[config$cluster_column]]<-factor(unname(child[selected]))
        warnings<-character()
        found<-withCallingHandlers(.sc_run_markers(working,.sc_run_scan_marker_config(config,10L)),warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
        record$status<-if(nrow(found$marker_summary))"measured"else"no_markers_passed"
        record$markers<-.sc_run_annotation_marker_records(found$marker_summary)
        record$parameters<-found$parameters;record$warnings<-as.list(unique(warnings))
        record$native_marker_rows<-nrow(found$markers)
      }
      records[[length(records)+1L]]<-record
    }
  }
  list(schema="scagentkit.adjacent-split-markers.v1",records=records,
    limitation="Same-data within-parent contrasts are descriptive. No passing markers, small child groups or cycle/shared-gene dominance do not establish identity, lineage or an optimal resolution.")
}
