#' Estimate ambient RNA on an explicit single capture without replacing counts
#' @param input Seurat object or named sparse raw-count matrix.
#' @param method SoupX (requires matched empty droplets) or decontX.
#' @param capture Named declaration with id, source and complete=TRUE.
#' @param clusters Named literal per-cell preliminary cluster IDs.
#' @param raw_counts Optional matched unfiltered droplet counts.
#' @param assay,counts_layer Explicit raw assay and layer for Seurat input.
#' @param seed Fixed numerical seed.
#' @param round_counts Explicitly round corrected output; default FALSE preserves estimates.
#' @param output_dir Optional new output directory; existing directories are refused.
#' @return Corrected counts and before/after receipt; original input is unchanged.
#' @export
sc_run_ambient_correction <- function(input, method=c("SoupX","decontX"), capture,
  clusters, raw_counts=NULL, assay="RNA", counts_layer="counts", seed=42L,
  round_counts=FALSE, output_dir=NULL) {
  if (!is.null(output_dir)) .sc_project_format_entry(output_dir, allow_new = TRUE)
  method <- match.arg(method)
  .sc_run_strategy_fields(capture,c("id","source","complete"),name="capture")
  .sc_project_string(capture$id,"capture id"); .sc_project_string(capture$source,"capture source")
  if(!identical(capture$complete,TRUE)) stop("Correction requires an explicit complete single-capture declaration; do not pool captures or use arbitrary subsets.",call.=FALSE)
  if(!is.logical(round_counts) || length(round_counts)!=1L || is.na(round_counts)) stop("round_counts must be explicit logical.",call.=FALSE)
  seed <- .sc_run_strategy_number(seed,"seed",0,.Machine$integer.max,integer=TRUE)
  input_hash <- .sc_run_hash(input)
  counts <- if(inherits(input,"Seurat")) .sc_project_layer(input,assay,counts_layer,raw_counts=TRUE) else input
  valid_matrix <- function(x) {
    if(!inherits(x,"sparseMatrix") || is.null(rownames(x)) || is.null(colnames(x)) || anyDuplicated(rownames(x)) ||
      anyDuplicated(colnames(x)) || anyNA(rownames(x)) || anyNA(colnames(x)) || any(!nzchar(rownames(x))) || any(!nzchar(colnames(x))) ||
      any(!is.finite(x@x)) || any(x@x<0)) stop("Ambient input requires nonnegative finite named sparse counts with unique literal IDs.",call.=FALSE)
  }
  valid_matrix(counts)
  if(any(counts@x != floor(counts@x))) stop("Ambient input must be original integer counts, not normalized or already corrected values.",call.=FALSE)
  if(!is.character(clusters) || is.null(names(clusters)) || anyDuplicated(names(clusters)) ||
      !setequal(names(clusters),colnames(counts)) || anyNA(clusters) || any(!nzchar(clusters)) || length(unique(clusters))<2L)
    stop("Ambient correction needs at least two preliminary clusters named by exact cell IDs.",call.=FALSE)
  clusters <- clusters[colnames(counts)]
  if(!is.null(raw_counts)) {
    valid_matrix(raw_counts)
    if(!setequal(rownames(raw_counts),rownames(counts)) || !all(colnames(counts) %in% colnames(raw_counts)))
      stop("Raw and filtered counts must match feature universe and literal filtered barcodes.",call.=FALSE)
    raw_counts <- raw_counts[rownames(counts),,drop=FALSE]
    if(!identical(.sc_project_sparse_hash(raw_counts[,colnames(counts),drop=FALSE]),.sc_project_sparse_hash(counts)))
      stop("Raw/filtered values disagree on the same cells; cannot infer a valid background.",call.=FALSE)
    if(any(raw_counts@x!=floor(raw_counts@x))) stop("Raw droplets must contain original integer counts.",call.=FALSE)
  }
  if(method=="SoupX" && (is.null(raw_counts) || length(setdiff(colnames(raw_counts),colnames(counts)))<20L))
    stop("SoupX requires matched raw+filtered counts with at least 20 additional background droplets; filtered-only correction is unavailable.",call.=FALSE)
  background <- if(is.null(raw_counts)) NULL else raw_counts[,setdiff(colnames(raw_counts),colnames(counts)),drop=FALSE]
  if(!is.null(background) && ncol(background)==0L) background <- NULL
  package <- if(method=="SoupX") "SoupX" else "celda"
  if(!requireNamespace(package,quietly=TRUE)) stop("Optional ambient dependency unavailable: ",package,". Install explicitly from CRAN/Bioconductor; no automatic substitution.",call.=FALSE)
  if(!is.null(output_dir) && file.exists(output_dir)) stop("Use a new output directory to preserve previous results.",call.=FALSE)
  seed_exists <- exists(".Random.seed",.GlobalEnv,inherits=FALSE); old <- if(seed_exists) get(".Random.seed",.GlobalEnv) else NULL
  on.exit(if(seed_exists) assign(".Random.seed",old,.GlobalEnv) else if(exists(".Random.seed",.GlobalEnv,inherits=FALSE)) rm(".Random.seed",envir=.GlobalEnv),add=TRUE)
  set.seed(seed)
  fit <- .sc_run_ambient_fit(counts,if(method=="SoupX") raw_counts else background,clusters,method,seed)
  corrected <- methods::as(fit$counts,"dgCMatrix")
  valid_matrix(corrected)
  if(!identical(dimnames(corrected),dimnames(counts))) stop("Ambient method changed literal feature/cell scope.",call.=FALSE)
  if(round_counts) corrected <- round(corrected)
  contamination <- as.numeric(fit$contamination)
  if(length(contamination)!=ncol(counts) || any(!is.finite(contamination)) || any(contamination<0 | contamination>1))
    stop("Ambient method returned incomplete or invalid contamination estimates.",call.=FALSE)
  if(!identical(input_hash,.sc_run_hash(input))) stop("Ambient adapter mutated the original input.",call.=FALSE)
  receipt <- list(schema="scagentkit.ambient-correction.v1",method=method,version=as.character(utils::packageVersion(package)),
    capture=capture,seed=seed,rounded=round_counts,input_hash=input_hash,
    original_counts_hash=.sc_project_sparse_hash(counts),corrected_counts_hash=.sc_project_sparse_hash(corrected),
    raw_background_hash=if(is.null(background)) NULL else .sc_project_sparse_hash(background),
    raw_input_hash=if(is.null(raw_counts)) NULL else .sc_project_sparse_hash(raw_counts),
    background_cells=if(is.null(background)) character() else colnames(background),
    background=if(is.null(background)) "decontX infers background from other clusters; no empty-droplet measurement" else "matched raw droplets",
    cells=colnames(counts),features=rownames(counts),clusters=clusters,
    contamination=stats::setNames(contamination,colnames(counts)),
    before_umi=stats::setNames(as.numeric(Matrix::colSums(counts)),colnames(counts)),
    after_umi=stats::setNames(as.numeric(Matrix::colSums(corrected)),colnames(counts)),
    before_detected=stats::setNames(as.numeric(Matrix::colSums(counts>0)),colnames(counts)),
    after_detected=stats::setNames(as.numeric(Matrix::colSums(corrected>0)),colnames(counts)),
    authoritative_input_changed=FALSE,default_enabled=FALSE,
    interpretation="Model-dependent estimate; inspect original/corrected panel expression and rare types. Native RNA may be removed. No automatic replacement, deletion or claim of improved accuracy.")
  if(!is.null(output_dir)) {
    dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
    saveRDS(corrected,file.path(output_dir,"corrected-counts.rds"),version=2L)
    jsonlite::write_json(receipt,file.path(output_dir,"comparison.json"),auto_unbox=TRUE,pretty=TRUE,null="null",na="null")
  }
  list(corrected_counts=corrected,receipt=receipt)
}

.sc_run_ambient_fit <- function(counts, raw, clusters, method, seed) {
  if(method=="SoupX") {
    fit <- SoupX::SoupChannel(tod=raw,toc=counts)
    fit <- SoupX::setClusters(fit,clusters)
    fit <- SoupX::autoEstCont(fit,doPlot=FALSE)
    list(counts=SoupX::adjustCounts(fit,roundToInt=FALSE),contamination=fit$metaData[colnames(counts),"rho"])
  } else {
    fit <- celda::decontX(x=counts,z=as.integer(factor(clusters)),background=raw,seed=seed,verbose=FALSE)
    list(counts=fit$decontXcounts,contamination=fit$contamination)
  }
}
