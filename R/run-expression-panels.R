# Sparse, explicit expression measurements; no panel name becomes a label.
.sc_run_expression_panels <- function(seu, assay, counts_layer, data_layer, cluster_column,
  panels=list(), sample_column=NULL, mixed_lineage=FALSE, quality_group_column=sample_column) {
  counts <- .sc_project_layer(seu,assay,counts_layer,raw_counts=TRUE)
  data <- .sc_project_layer(seu,assay,data_layer)
  cells <- colnames(seu); metadata <- seu[[]]
  if(!setequal(colnames(counts),cells) || !setequal(colnames(data),cells) || !setequal(rownames(counts),rownames(data)) || !setequal(rownames(metadata),cells))
    stop("Expression review requires exact aligned raw and normalized layers.",call.=FALSE)
  counts <- counts[,cells,drop=FALSE]; data <- data[rownames(counts),cells,drop=FALSE]
  metadata <- metadata[cells,,drop=FALSE]
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
    eligible <- Filter(function(row) identical(row$status,"measured"),strata)
    consistency <- lapply(present,function(gene) {
      rows <- lapply(eligible,function(sample) Filter(function(row) identical(row$gene,gene),sample$genes)[[1L]])
      positive <- vapply(rows,function(row) row$mean_difference>0 && row$detection_difference>0,logical(1))
      negative <- vapply(rows,function(row) row$mean_difference<0 && row$detection_difference<0,logical(1))
      list(gene=gene,samples_evaluable=length(rows),positive_samples=sum(positive),negative_samples=sum(negative),
        consistent_positive=if(length(rows)>=2L) all(positive) else NULL,
        interpretation="Concordant positive mean-log-expression and detection contrasts in every evaluable sample; descriptive, not a sample-level significance test.")
    })
    list(cluster=id,cells=length(inside),genes=measured(inside,outside),samples=strata,cross_sample_consistency=consistency,
      cross_sample_status=if(length(Filter(function(x) x$status=="measured",strata))>=2L) "descriptive_replication" else "unavailable")
  })
  totals <- as.numeric(Matrix::colSums(counts)); detected <- as.numeric(Matrix::colSums(counts>0))
  quality_groups <- if(is.null(quality_group_column)) rep("unstratified",length(cells)) else
    as.character(metadata[[quality_group_column]])
  if(length(quality_groups)!=length(cells) || anyNA(quality_groups) || any(!nzchar(quality_groups)))
    stop("Expression count flags require complete explicitly declared quality groups.",call.=FALSE)
  high_count <- rep(NA,length(cells)); count_z <- rep(NA_real_,length(cells))
  for(group in unique(quality_groups)) {
    index <- which(quality_groups==group); transformed <- log10(totals[index]+1)
    center <- stats::median(transformed); spread <- stats::mad(transformed,constant=1.4826)
    if(length(index)>=30L && is.finite(spread) && spread>sqrt(.Machine$double.eps)) {
      count_z[index] <- (transformed-center)/spread; high_count[index] <- count_z[index]>3
    }
  }
  cell_quality <- lapply(seq_along(cells),function(i) list(cell_id=cells[i],group=quality_groups[i],
    total_umi=totals[i],detected_features=detected[i],count_robust_z=if(is.na(count_z[i])) NULL else count_z[i],
    high_count_flag=if(is.na(high_count[i])) NULL else high_count[i]))
  coexpression <- NULL
  lineage_panels <- panels[setdiff(names(panels),"cited_marker_review")]
  if(isTRUE(mixed_lineage) && length(lineage_panels)>=2L) {
    support <- lapply(panels,function(g) {
      g <- intersect(g,rownames(counts))
      if(!length(g)) return(rep(NA_integer_,length(cells)))
      as.integer(Matrix::colSums(counts[g,,drop=FALSE]>0))
    })
    pairs <- utils::combn(names(lineage_panels),2,simplify=FALSE)
    coexpression <- lapply(pairs,function(pair) {
      measured_a <- length(intersect(panels[[pair[1]]],rownames(counts)))
      measured_b <- length(intersect(panels[[pair[2]]],rownames(counts)))
      eligible <- measured_a>0 && measured_b>0
      selected <- if(eligible) support[[pair[1]]] >= min(2L,measured_a) & support[[pair[2]]] >= min(2L,measured_b) else rep(FALSE,length(cells))
      list(panels=pair,status=if(eligible) "measured" else "unavailable",detected_gene_counts=list(
        first=stats::setNames(support[[pair[1]]],cells),second=stats::setNames(support[[pair[2]]],cells)),
        coexpressing_cells=if(eligible) cells[selected] else NULL,
        coexpressing_cell_quality=if(eligible) cell_quality[selected] else list(),
        lineage_relationship=if(all(pair %in% c("T","NK"))) "Related T/NK programs can overlap; not an exclusive-lineage rule" else "Distinct panel names do not establish biological exclusivity; inspect literal genes and tissue context",
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
    mixed_lineage=coexpression,cell_quality=cell_quality,high_count_interpretation="Within-declared-sample log10(total_UMI+1) robust z>3, >=30 cells/nonzero MAD; pooled unstratified scope is disclosed. Flag-only, never deletion or doublet truth.",ambient_status="not_estimated_without_an_explicit_background_model",
    interpretation="Mean is mean log-normalized expression; pct is raw-count detection. Panels overlap and expression may reflect state, related lineages, doublets or ambient RNA. No automatic type, contamination diagnosis, correction or deletion. Cross-sample contrasts are descriptive and sample counts are not donor replicates.")
}
