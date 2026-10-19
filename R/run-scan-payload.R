# Purpose-built aggregate projection; complete native scan/checkpoints remain
# local and unchanged. Omit whole split blocks only, with an explicit inventory.
.sc_run_cluster_scan_payload <- function(scan,max_bytes=60000L) {
  pack<-function(rows,columns)unname(lapply(rows,function(row)unname(lapply(columns,function(key)row[[key]]))))
  marker_columns<-c("clusterId","gene","avgLog2FC","pct1","pct2","pAdj")
  marker_rows<-function(rows,n) {
    groups<-unique(vapply(rows,`[[`,character(1),"clusterId"))
    unlist(lapply(groups,function(id)head(Filter(function(row)identical(row$clusterId,id),rows),n)),recursive=FALSE)
  }
  inventory<-lapply(scan$adjacent_splits$records,function(row)
    list(from_resolution=row$from_resolution,to_resolution=row$to_resolution,parent_cluster=row$parent_cluster,
      cells=row$cells,status=row$status,child_sizes=row$child_sizes))
  global<-lapply(names(scan$markers),function(key) {
    record<-scan$markers[[key]]
    programs<-record$marker_programs
    if(!is.null(programs))programs$rows<-lapply(programs$rows,function(row)row[setdiff(names(row),"top_genes")])
    list(resolution=as.numeric(key),status=record$status,markers=pack(marker_rows(record$markers,3L),marker_columns),programs=programs)
  })
  payload<-list(schema="scagentkit.cluster-scan-aggregate.v2",hash=scan$hash,
    source_scan_hash=scan$hash,resolutions=scan$resolutions,provisional_resolution=scan$provisional_resolution,
    selected_pcs=scan$selected_pcs,seed=scan$seed,
    tree=list(node_columns=c("id","resolution","cluster","cells","sample_counts"),
      nodes=pack(scan$tree$nodes,c("id","resolution","cluster","cells","sample_counts")),
      edge_columns=c("source","target","cells"),edges=pack(scan$tree$edges,c("source","target","cells"))),
    marker_columns=marker_columns,global_markers_top3=global,
    adjacent_split_inventory=inventory,adjacent_splits_top10=list(),
    scientific_diagnostics=scan$scientific_diagnostics,
    projection=list(maximum_bytes=as.integer(max_bytes),global_markers_per_cluster=3L,adjacent_markers_per_child=10L,
      split_policy="Largest parent cell scopes first; each included block retains complete saved top-ten rows for its children. Full inventory and source scan hash identify omitted blocks. Complete local evidence is unchanged.",
      interpretation="Bounded same-data aggregate for recommendations, not all marker evidence or a biological optimum."))
  bytes<-function(value)nchar(enc2utf8(.sc_run_provider_json(value)),type="bytes")
  # Reserve explicit accounting fields before testing a candidate block.
  payload$projection$total_split_blocks<-length(inventory)
  payload$projection$included_split_blocks<-0L
  payload$projection$omitted_split_blocks<-length(inventory)
  payload$status<-"partial_split_projection"
  payload$projection$bytes<-as.integer(max_bytes)
  if(bytes(payload)>max_bytes) {
    return(list(schema=payload$schema,hash=scan$hash,source_scan_hash=scan$hash,resolutions=scan$resolutions,
      status="unavailable_essential_aggregates_exceed_bound",
      reason="The essential graph/program inventory exceeds the bounded model projection; inspect complete local evidence manually."))
  }
  records<-scan$adjacent_splits$records
  ordering<-if(length(records))order(-vapply(records,`[[`,numeric(1),"cells"),seq_along(records))else integer()
  for(index in ordering) {
    row<-records[[index]]
    if(!identical(row$status,"measured"))next
    block<-c(inventory[[index]],list(markers=pack(row$markers,marker_columns),contrast=row$contrast))
    candidate<-payload
    candidate$adjacent_splits_top10<-c(candidate$adjacent_splits_top10,list(block))
    count<-length(candidate$adjacent_splits_top10)
    candidate$projection$included_split_blocks<-count
    candidate$projection$omitted_split_blocks<-length(inventory)-count
    if(bytes(candidate)<=max_bytes)payload<-candidate
  }
  payload$projection$included_split_blocks<-length(payload$adjacent_splits_top10)
  payload$projection$omitted_split_blocks<-length(inventory)-length(payload$adjacent_splits_top10)
  if(payload$projection$omitted_split_blocks==0L)payload$status<-"complete_projection"
  repeat {
    actual<-bytes(payload)
    if(identical(payload$projection$bytes,actual))break
    payload$projection$bytes<-actual
  }
  if(bytes(payload)>max_bytes) {
    # Adding accounting must not create an oversized request. No scientific
    # rows are partially removed: fall back to the explicit blocked view.
    return(list(schema=payload$schema,hash=scan$hash,source_scan_hash=scan$hash,resolutions=scan$resolutions,
      status="unavailable_essential_aggregates_exceed_bound",reason="Aggregate accounting exceeds the bound; inspect complete local scan evidence."))
  }
  payload
}
