# Review PNGs are immutable evidence, not convenience exports. Only publication
# creates them; inspect/approval verifies the saved bytes and selection binding.
.sc_run_annotation_plot_selection <- function(evidence,proposal,analysis) {
  list(schema="scagentkit.annotation-plot-selection.v1", analysis=analysis,
    top_markers=lapply(evidence$summary$clusters,function(row)
      list(clusterId=row$clusterId,genes=unique(head(vapply(row$markers,`[[`,character(1),"gene"),5L)))),
    citations=lapply(proposal$annotations,function(row)
      list(clusterId=row$clusterId,genes=unique(unlist(row$markers,use.names=FALSE)))))
}

.sc_run_annotation_plots_get <- function(root,state,evidence,proposal) {
  if (is.null(state$config$input_policy)) return(NULL)
  if (is.null(state$files$annotation_plots)) stop("Save the annotation draft to prepare its bound plot evidence.",call.=FALSE)
  record<-.sc_run_get(root,state,"annotation_plots")
  selection<-.sc_run_annotation_plot_selection(evidence,proposal,state$files$analysis)
  if (!identical(record$schema,"scagentkit.annotation-plots.v1") ||
      !identical(record$selection,selection) ||
      !identical(record$hash,.sc_run_hash(record[setdiff(names(record),"hash")])))
    stop("Annotation plots do not match the current citation selection and analysis checkpoint.",call.=FALSE)
  for (plot in record$plots) {
    path<-file.path(root,plot$path)
    if (!file.exists(path)||nzchar(Sys.readlink(path))||!identical(plot$sha256,.sc_project_sha_file(path)))
      stop("Saved annotation plot changed; review and approval are stale.",call.=FALSE)
  }
  record
}

.sc_run_annotation_plots_prepare <- function(root,state,evidence,proposal) {
  if (is.null(state$config$input_policy)) return(state)
  selection<-.sc_run_annotation_plot_selection(evidence,proposal,state$files$analysis)
  prior<-if(is.null(state$files$annotation_plots)) NULL else .sc_run_get(root,state,"annotation_plots")
  if (!is.null(prior)&&identical(prior$selection,selection)) {
    .sc_run_annotation_plots_get(root,state,evidence,proposal)
    return(state)
  }
  seu<-.sc_run_get(root,state,"analysis")
  assay<-state$config$assay
  SeuratObject::DefaultAssay(seu)<-assay
  top<-unique(unlist(lapply(selection$top_markers,`[[`,"genes"),use.names=FALSE))
  cited<-unique(unlist(lapply(selection$citations,`[[`,"genes"),use.names=FALSE))
  if (any(!c(top,cited)%in%rownames(seu)))
    stop("A review plot gene is absent from the exact analysis assay. Check the saved marker evidence; no plot was substituted.",call.=FALSE)
  record<-list(schema="scagentkit.annotation-plots.v1",selection=selection,
    selection_hash=.sc_run_hash(selection),plots=list(),parameters=list(dotplot_scale=FALSE,featureplot_order=TRUE),
    citation_status=if(length(cited)) "pending" else "not_requested_no_citations",
    dotplot_status=if(length(top)) "pending" else "unavailable_no_positive_pool_genes",
    notice="Top-five pool genes are deduplicated for DotPlot. FeaturePlots show the saved cited genes on an existing embedding; plots are descriptive, not independent identity validation.")
  relative<-file.path("review-evidence","annotation",record$selection_hash)
  for (part in c("review-evidence",file.path("review-evidence","annotation"),relative)) {
    path<-file.path(root,part)
    target<-Sys.readlink(path)
    if(!is.na(target)&&nzchar(target))stop("Review evidence directory cannot be a symlink.",call.=FALSE)
    if(!dir.exists(path)&&!dir.create(path))stop("Cannot create the local review evidence directory.",call.=FALSE)
  }
  save_plot<-function(plot,name,kind,genes,width=10,height=6) {
    destination<-file.path(root,relative,paste0(name,".png"))
    temporary<-tempfile(".plot-",tmpdir=dirname(destination),fileext=".png")
    on.exit(unlink(temporary),add=TRUE)
    ggplot2::ggsave(temporary,plot=plot,device="png",width=width,height=height,dpi=120,bg="white",limitsize=TRUE)
    sha<-.sc_project_sha_file(temporary)
    if(file.exists(destination)) {
      if(nzchar(Sys.readlink(destination))||!identical(.sc_project_sha_file(destination),sha))
        stop("An immutable annotation PNG path already contains different bytes; restore the saved evidence.",call.=FALSE)
    } else if(!file.rename(temporary,destination))stop("Cannot save the annotation review PNG.",call.=FALSE)
    list(kind=kind,genes=.sc_project_array(genes),path=file.path(relative,paste0(name,".png")),sha256=sha,
      bytes=unname(file.info(destination)$size),width_in=width,height_in=height,dpi=120L)
  }
  if(length(top)) {
    plot<-Seurat::DotPlot(seu,features=top,assay=assay,group.by=state$config$cluster_column,scale=FALSE)+
      ggplot2::theme(axis.text.x=ggplot2::element_text(angle=90,hjust=1,vjust=.5))
    record$plots[[length(record$plots)+1L]]<-save_plot(plot,"top-five-dotplot","dotplot",top,
      width=max(8,min(18,length(top)*.25)),height=max(5,min(14,length(selection$top_markers)*.3)))
    record$dotplot_status<-"saved"
  }
  reduction<-if("umap"%in%names(seu@reductions)) "umap" else if("pca"%in%names(seu@reductions)) "pca" else NULL
  record$reduction<-reduction
  if(length(cited)&&!is.null(reduction)) {
    pages<-split(cited,ceiling(seq_along(cited)/4L))
    for(i in seq_along(pages)) {
      genes<-pages[[i]]
      plot<-Seurat::FeaturePlot(seu,features=genes,reduction=reduction,combine=TRUE,ncol=2,order=TRUE)
      record$plots[[length(record$plots)+1L]]<-save_plot(plot,paste0("citations-",i),"featureplot",genes,height=if(length(genes)>2L)10 else 5)
    }
    record$citation_status<-"saved"
  } else if(length(cited)) record$citation_status<-"unavailable_no_saved_embedding"
  record$hash<-.sc_run_hash(record)
  state<-.sc_run_put(root,state,"annotation_plots",record)
  for(plot in record$plots) state$files[[paste0("annotation_plot:",plot$path)]]<-list(path=plot$path,sha256=plot$sha256)
  .sc_run_event(state,"annotation_plot_evidence_prepared",list(selection_hash=record$selection_hash,
    plot_hash=record$hash,plots=lapply(record$plots,function(plot)plot[c("kind","path","sha256","genes")]),
    provider_dispatch="not_sent"))
}
