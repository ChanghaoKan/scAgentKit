# Opt-in, local, copy-only experiments. Results never choose a strategy.
.sc_run_science_options <- function(value = NULL) {
  if (is.null(value) || identical(value,FALSE)) return(NULL)
  x <- .sc_run_annotation_options(value,c("pc_sensitivity","resampling","resolution_extension","panels","cross_sample","mixed_lineage"),"scientific_review")
  for (key in c("pc_sensitivity","resampling","resolution_extension","cross_sample","mixed_lineage")) {
    if (is.null(x[[key]])) x[[key]] <- FALSE
    if (!is.logical(x[[key]]) || length(x[[key]]) != 1L || is.na(x[[key]])) stop("scientific_review flags must be TRUE or FALSE.",call.=FALSE)
  }
  if (is.null(x$panels)) x$panels <- list()
  if (is.character(x$panels) && length(x$panels)==1L) x$panels <- .sc_run_classic_panels(x$panels)
  if (!is.list(x$panels) || (length(x$panels) && (is.null(names(x$panels)) || anyDuplicated(names(x$panels)) || any(!nzchar(names(x$panels)))))) stop("panels requires a named list or blood/pancreas.",call.=FALSE)
  x$panels <- lapply(x$panels,function(genes) {
    if(is.list(genes) && is.null(names(genes)) && all(vapply(genes,function(g) is.character(g) && length(g)==1L,logical(1)))) unlist(genes,use.names=FALSE) else genes
  })
  for (genes in x$panels) if (!is.character(genes) || !length(genes) || anyNA(genes) || any(!nzchar(genes)) || anyDuplicated(genes)) stop("Panel genes must be unique literal symbols.",call.=FALSE)
  x
}

.sc_run_classic_panels <- function(tissue) {
  switch(tissue, blood=list(T=c("CD3D","CD3E","TRAC"),B=c("CD79A","MS4A1","CD37"),
    NK=c("NKG7","GNLY","PRF1"),Monocyte=c("LST1","S100A8","FCN1"),
    Dendritic=c("FCER1A","CD1C","CST3"),Platelet=c("PPBP","PF4")),
    pancreas=list(alpha=c("GCG","TTR"),beta=c("INS","IAPP"),delta="SST",PP="PPY",
      acinar=c("PRSS1","CPA1","CTRB2"),ductal=c("KRT19","KRT8","KRT18"),
      endothelial=c("PECAM1","VWF","KDR"),stellate=c("COL1A1","COL1A2","DCN")),
    stop("Built-in panels support human blood/pancreas only; supply explicit symbols for another species.",call.=FALSE))
}

.sc_run_science_partition <- function(seu, k, resolution, seed) {
  if (!"pca" %in% names(seu) || k < 2 || k > ncol(SeuratObject::Embeddings(seu,"pca")) || ncol(seu)<21)
    stop("Sensitivity needs actual PCA dimensions and at least 21 cells.",call.=FALSE)
  seed_exists <- exists(".Random.seed",.GlobalEnv,inherits=FALSE); old_seed <- if(seed_exists) get(".Random.seed",.GlobalEnv) else NULL
  on.exit(if(seed_exists) assign(".Random.seed",old_seed,.GlobalEnv) else if(exists(".Random.seed",.GlobalEnv,inherits=FALSE)) rm(".Random.seed",envir=.GlobalEnv),add=TRUE)
  set.seed(seed)
  working <- Seurat::FindNeighbors(seu,reduction="pca",dims=seq_len(k),k.param=20L,
    graph.name=c("science_nn","science_snn"),verbose=FALSE)
  working <- Seurat::FindClusters(working,graph.name="science_snn",resolution=resolution,
    random.seed=seed,algorithm=1L,verbose=FALSE)
  stats::setNames(as.character(SeuratObject::Idents(working)),colnames(working))
}

.sc_run_science_partition_compare <- function(reference, candidate) {
  if (is.null(names(reference)) || is.null(names(candidate)) || anyDuplicated(names(reference)) || anyDuplicated(names(candidate)) ||
      anyNA(reference) || anyNA(candidate) || any(!nzchar(reference)) || any(!nzchar(candidate)) || !all(names(candidate) %in% names(reference)))
    stop("Partitions need unique named exact cell IDs, with candidate a subset of reference.",call.=FALSE)
  shared <- names(candidate); ref <- reference[shared]
  per_cluster <- lapply(sort(unique(reference),method="radix"),function(id) {
    original <- names(reference)[reference==id]; retained <- intersect(original,shared)
    match <- vapply(unique(candidate),function(other) {
      cells <- names(candidate)[candidate==other]
      length(intersect(retained,cells))/length(union(retained,cells))
    },numeric(1))
    list(cluster=id, original_cells=length(original), retained_cells=length(retained),
      coverage=length(retained)/length(original),best_jaccard=if(length(retained)) max(match) else NULL)
  })
  list(shared_cells=length(shared),ari=if(length(shared)>1L) .adjusted_rand_index(ref, candidate) else NULL,
    clusters=length(unique(candidate)),per_cluster=per_cluster,
    interpretation="Best Jaccard is a descriptive matching on shared cells; retention is separate. No lineage or independent biological replication.")
}

.sc_run_science_diagnostics <- function(seu, config, plan) {
  options <- .sc_run_science_options(config$scientific_review)
  if (is.null(options)) return(NULL)
  seed_present <- exists(".Random.seed",.GlobalEnv,inherits=FALSE)
  saved_seed <- if(seed_present) get(".Random.seed",.GlobalEnv) else NULL
  on.exit(if(seed_present) assign(".Random.seed",saved_seed,.GlobalEnv) else if(exists(".Random.seed",.GlobalEnv,inherits=FALSE)) rm(".Random.seed",envir=.GlobalEnv),add=TRUE)
  before <- .sc_run_hash(seu)
  cells <- colnames(seu); column <- config$cluster_column
  if (!column %in% names(seu[[]])) stop("Scientific diagnostics require current membership.",call.=FALSE)
  membership <- stats::setNames(as.character(seu[[]][[column]]),cells)
  k <- seu@misc$strategy_execution$neighbors$pcs
  if (is.null(k)) k <- if(identical(plan$pcs$method,"fixed")) plan$pcs$ndim else {
    p <- .sc_run_pc_candidates(SeuratObject::Stdev(seu[["pca"]])); p$candidates[[if(plan$pcs$threshold==.85) "p85" else "p80"]]$ndim
  }
  if(is.list(k)) k <- k$ndim else if(length(k)>1L) k <- length(k)
  if(!is.numeric(k) || length(k)!=1L || !is.finite(k) || k<2L || k!=floor(k)) stop("Approved neighbor PC count is absent or invalid.",call.=FALSE)
  measured <- function(fn) tryCatch(c(list(status="measured"),fn()),error=function(e) list(status="unavailable",reason=conditionMessage(e)))
  corrected_pipeline <- identical(plan$batch$method,"harmony") ||
    (!is.null(plan$cycle) && !identical(plan$cycle$method,"none"))
  if(corrected_pipeline && (options$pc_sensitivity || options$resampling || options$resolution_extension))
    return(list(schema="scagentkit.scientific-diagnostics.v1",status="unavailable",
      reason="Copy-based PCA diagnostics do not yet reproduce approved Harmony/cycle regression; no PCA-only run is presented as same-pipeline stability.",
      default_changed=FALSE,provider_calls=0L))
  out <- list(schema="scagentkit.scientific-diagnostics.v1",options=options,
    cells=cells,input_object_hash=before,approved_pc_count=k,approved_resolution=plan$clustering$resolution,
    default_changed=FALSE,provider_calls=0L)
  if(options$pc_sensitivity) out$pc_sensitivity <- measured(function() {
    available <- ncol(SeuratObject::Embeddings(seu,"pca"))
    candidates <- sort(unique(pmax(2L,pmin(available,c(k-5L,k,k+5L)))))
    list(actual_pcs=available,requested=c(k-5L,k,k+5L),bounded_candidates=candidates,
      comparisons=lapply(candidates,function(n) {
        partition <- .sc_run_science_partition(seu,n,plan$clustering$resolution,plan$analysis$seed)
        c(list(pcs=n),.sc_run_science_partition_compare(membership,partition),
          list(marker_consistency=.sc_run_science_marker_consistency(seu,config,membership,partition)))
      }))
  })
  if(options$resampling) out$resampling <- measured(function() {
    seed_exists <- exists(".Random.seed",.GlobalEnv,inherits=FALSE)
    old_seed <- if(seed_exists) get(".Random.seed",.GlobalEnv) else NULL
    on.exit(if(seed_exists) assign(".Random.seed",old_seed,.GlobalEnv) else if(exists(".Random.seed",.GlobalEnv,inherits=FALSE)) rm(".Random.seed",envir=.GlobalEnv),add=TRUE)
    counts <- .sc_project_layer(seu,config$assay,config$counts_layer,raw_counts=TRUE)
    if(!setequal(colnames(counts),cells)) stop("Resampling source cell IDs differ.")
    counts <- counts[,cells,drop=FALSE]
    results <- lapply(42:46,function(seed) {
      set.seed(seed); selected <- sort(sample.int(ncol(seu),floor(.8*ncol(seu))))
      working <- Seurat::CreateSeuratObject(counts[,selected,drop=FALSE],assay=config$assay,
        meta.data=seu[[]][selected,,drop=FALSE],min.cells=0,min.features=0)
      settings <- .sc_run_strategy_runtime_settings(plan)
      working <- .sc_run_strategy_normalize_hvg(working,config,settings,counts[,selected,drop=FALSE])
      hvg <- SeuratObject::VariableFeatures(working[[config$assay]])
      if(plan$analysis$npcs>=min(length(hvg),ncol(working))) stop("Resample has insufficient cells/HVGs for the unchanged PCA request.")
      working <- Seurat::ScaleData(working,assay=config$assay,features=hvg,verbose=FALSE)
      working <- Seurat::RunPCA(working,assay=config$assay,features=hvg,npcs=plan$analysis$npcs,seed.use=seed,verbose=FALSE)
      c(list(seed=seed,cells=colnames(working)),.sc_run_science_partition_compare(membership,
        .sc_run_science_partition(working,k,plan$clustering$resolution,seed)))
    })
    list(fraction=.8,seeds=42:46,rebuild="Normalize/HVG/PCA/neighbors/clusters on each subset",replicates=results,
      interpretation="Computational resampling on one dataset, not donor-level uncertainty or optimal resolution.")
  })
  if(options$resolution_extension) out$resolution_extension <- measured(function() {
    grid <- sort(unique(c(plan$clustering$resolution,plan$clustering$diagnostic_resolutions)))
    initial <- lapply(grid,function(r) .sc_run_science_partition(seu,k,r,plan$analysis$seed))
    counts <- vapply(initial,function(x) length(unique(x)),integer(1))
    edge_ari <- if(length(initial)>1L) .adjusted_rand_index(initial[[length(initial)-1L]],initial[[length(initial)]]) else NA_real_
    extend <- counts[1L]==1L || counts[length(counts)]==1L || (is.finite(edge_ari) && edge_ari<.9)
    extra <- if(extend) setdiff(c(.1,1.4,1.6),grid) else numeric()
    list(initial_grid=grid,initial_cluster_counts=counts,upper_edge_ari=edge_ari,extension_triggered=extend,
      extended=lapply(extra,function(r) c(list(resolution=r),.sc_run_science_partition_compare(membership,
        .sc_run_science_partition(seu,k,r,plan$analysis$seed)))),
      approved_resolution_unchanged=plan$clustering$resolution)
  })
  if(length(options$panels) || options$cross_sample || options$mixed_lineage)
    out$expression <- .sc_run_expression_panels(seu,config$assay,config$counts_layer,config$normalized_layer,
      column,options$panels,config$context$columns$sample,options$mixed_lineage)
  if(!identical(before,.sc_run_hash(seu))) stop("Scientific diagnostics changed their input object.",call.=FALSE)
  out$hash <- .sc_run_hash(out)
  out
}

.sc_run_science_marker_consistency <- function(seu,config,reference,candidate) {
  marker_config <- config; marker_config$scientific_review <- NULL
  signature <- function(membership) {
    working <- seu
    working[[config$cluster_column]] <- unname(membership[colnames(working)])
    found <- .sc_run_markers(working,marker_config)$marker_summary
    split(as.character(found$gene),as.character(found$cluster))
  }
  a <- signature(reference); b <- signature(candidate)
  rows <- lapply(sort(unique(reference),method="radix"),function(id) {
    cells <- names(reference)[reference==id]
    ids <- sort(unique(candidate),method="radix")
    scores <- vapply(ids,function(other) {
      selected <- names(candidate)[candidate==other]
      length(intersect(cells,selected))/length(union(cells,selected))
    },numeric(1))
    matched <- ids[which.max(scores)]
    genes_a <- unique(a[[id]]); genes_b <- unique(b[[matched]])
    list(reference_cluster=id,matched_cluster=matched,cell_jaccard=max(scores),
      reference_marker_count=length(genes_a),candidate_marker_count=length(genes_b),
      marker_jaccard=if(length(genes_a) && length(genes_b)) length(intersect(genes_a,genes_b))/length(union(genes_a,genes_b)) else NULL)
  })
  list(status="measured",clusters=rows,
    interpretation="Native pooled differential top-marker sets after best shared-cell cluster matching; empty sets are unavailable. Same-data marker overlap is not independent identity validation.")
}
