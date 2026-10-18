# Sparse, explicit expression measurements; no panel name becomes a label.
.sc_run_expression_panels <- function(seu, assay, counts_layer, data_layer, cluster_column,
  panels=list(), sample_column=NULL, mixed_lineage=FALSE) {
  counts <- .sc_project_layer(seu,assay,counts_layer,raw_counts=TRUE)
  data <- .sc_project_layer(seu,assay,data_layer)
  cells <- colnames(seu); metadata <- seu[[]]
  if(!identical(colnames(counts),cells) || !identical(colnames(data),cells) || !identical(rownames(counts),rownames(data)))
    stop("Expression review requires exact aligned raw and normalized layers.",call.=FALSE)
  membership <- as.character(metadata[[cluster_column]])
  if(length(membership)!=length(cells) || anyNA(membership) || any(!nzchar(membership))) stop("Expression review requires complete clusters.",call.=FALSE)
  genes <- sort(unique(unlist(panels,use.names=FALSE)),method="radix")
  present <- intersect(genes,rownames(counts)); missing <- setdiff(genes,rownames(counts))
  sample <- if(is.null(sample_column)) NULL else as.character(metadata[[sample_column]])
  if(!is.null(sample_column) && (length(sample)!=length(cells) || anyNA(sample) || any(!nzchar(sample))))
    stop("Cross-sample expression requires complete explicitly declared sample IDs.",call.=FALSE)
  measured <- function(inside,outside) {
    if(!length(present)) return(list())
    mean_in <- Matrix::rowMeans(data[present,inside,drop=FALSE]); pct_in <- Matrix::rowMeans(counts[present,inside,drop=FALSE]>0)
    mean_out <- if(length(outside)) Matrix::rowMeans(data[present,outside,drop=FALSE]) else rep(NA_real_,length(present))
    pct_out <- if(length(outside)) Matrix::rowMeans(counts[present,outside,drop=FALSE]>0) else rep(NA_real_,length(present))
    lapply(seq_along(present),function(i) list(gene=present[i],mean_log_normalized=unname(mean_in[i]),pct_detected=unname(pct_in[i]),
      mean_log_normalized_outside=if(length(outside)) unname(mean_out[i]) else NULL,
      pct_detected_outside=if(length(outside)) unname(pct_out[i]) else NULL,
      mean_difference=if(length(outside)) unname(mean_in[i]-mean_out[i]) else NULL,
      detection_difference=if(length(outside)) unname(pct_in[i]-pct_out[i]) else NULL))
  }
  clusters <- lapply(sort(unique(membership),method="radix"),function(id) {
    inside <- which(membership==id); outside <- which(membership!=id)
    strata <- if(is.null(sample)) list() else lapply(sort(unique(sample),method="radix"),function(s) {
      a <- which(membership==id & sample==s); b <- which(membership!=id & sample==s)
      list(sample=s,inside_cells=length(a),outside_cells=length(b),
        status=if(length(a)>=20L && length(b)>=20L) "measured" else "unavailable",
        reason=if(length(a)>=20L && length(b)>=20L) NULL else "At least 20 cells inside and outside this cluster in this sample are required.",
        genes=if(length(a)>=20L && length(b)>=20L) measured(a,b) else list())
    })
    list(cluster=id,cells=length(inside),genes=measured(inside,outside),samples=strata,
      cross_sample_status=if(length(Filter(function(x) x$status=="measured",strata))>=2L) "descriptive_replication" else "unavailable")
  })
  coexpression <- NULL
  if(isTRUE(mixed_lineage) && length(panels)>=2L) {
    support <- lapply(panels,function(g) {
      g <- intersect(g,rownames(counts))
      if(!length(g)) return(rep(NA_integer_,length(cells)))
      as.integer(Matrix::colSums(counts[g,,drop=FALSE]>0))
    })
    pairs <- utils::combn(names(panels),2,simplify=FALSE)
    coexpression <- lapply(pairs,function(pair) {
      measured_a <- length(intersect(panels[[pair[1]]],rownames(counts)))
      measured_b <- length(intersect(panels[[pair[2]]],rownames(counts)))
      eligible <- measured_a>0 && measured_b>0
      selected <- if(eligible) support[[pair[1]]] >= min(2L,measured_a) & support[[pair[2]]] >= min(2L,measured_b) else rep(FALSE,length(cells))
      list(panels=pair,status=if(eligible) "measured" else "unavailable",detected_gene_counts=list(
        first=stats::setNames(support[[pair[1]]],cells),second=stats::setNames(support[[pair[2]]],cells)),
        coexpressing_cells=if(eligible) cells[selected] else NULL,
        threshold="At least min(2, measured panel genes) detected per panel; exploratory display, not a doublet or ambient classifier.")
    })
  }
  common <- lapply(present,function(gene) {
    fractions <- vapply(clusters,function(cluster) {
      row <- Filter(function(row) identical(row$gene,gene),cluster$genes)[[1L]]
      row$pct_detected
    },numeric(1))
    list(gene=gene,clusters_measured=length(clusters),fraction_clusters_detected_in_half_cells=mean(fractions>=.5),
      broadly_detected=length(clusters)>=2L && mean(fractions>=.5)>=.8,
      interpretation="Detection in at least half of cells in >=80% of clusters is a descriptive broad-expression flag, not lineage specificity or semantic evidence.")
  })
  list(status="measured",panels=panels,measured_genes=present,missing_genes=missing,clusters=clusters, common_marker_review=common,
    mixed_lineage=coexpression,ambient_status="not_estimated_without_an_explicit_background_model",
    interpretation="Mean is mean log-normalized expression; pct is raw-count detection. Panels overlap and expression may reflect state, related lineages, doublets or ambient RNA. No automatic type, contamination diagnosis, correction or deletion. Cross-sample contrasts are descriptive and sample counts are not donor replicates.")
}
