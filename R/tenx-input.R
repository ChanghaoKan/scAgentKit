# Exact local 10x MEX adapter. No inference, normalization or source writes.
.sc_ui_tenx_table <- function(value, what) {
  if (is.data.frame(value)) out <- value else {
    .sc_project_string(value, paste0(what, " table path"))
    if (!file.exists(value) || dir.exists(value)) stop(what, " table is missing; supply an existing CSV/TSV file.", call.=FALSE)
    out <- utils::read.table(value, header=TRUE, sep=if (grepl("[.]csv$",value,ignore.case=TRUE)) "," else "\t",
      colClasses="character", check.names=FALSE, stringsAsFactors=FALSE, comment.char="", quote="\"", na.strings=character())
  }
  if (!nrow(out) || anyDuplicated(names(out)) || anyNA(names(out)) || any(!nzchar(names(out))) ||
      !all(vapply(out,function(x)is.atomic(x)&&!anyNA(x),logical(1))))
    stop(what, " needs nonempty rows, unique column names and no missing values.",call.=FALSE)
  out[] <- lapply(out,as.character)
  out
}
.sc_ui_tenx_file <- function(root, stems) {
  paths <- unlist(lapply(stems,function(x)file.path(root,c(x,paste0(x,".gz")))),use.names=FALSE)
  paths <- paths[file.exists(paths)&!dir.exists(paths)]
  if (length(paths)!=1L) stop("10x directory needs exactly one ",paste(stems,collapse=" or "),
    " (plain or .gz); restore missing files or remove ambiguous duplicate copies.",call.=FALSE)
  normalizePath(paths,mustWork=TRUE)
}
.sc_ui_tenx_read <- function(directory, feature_key) {
  if (!dir.exists(directory)) stop("10x directory is missing; correct the sample table path.",call.=FALSE)
  files <- c(matrix=.sc_ui_tenx_file(directory,"matrix.mtx"),
    features=.sc_ui_tenx_file(directory,c("features.tsv","genes.tsv")),
    barcodes=.sc_ui_tenx_file(directory,"barcodes.tsv"))
  hashes <- vapply(files,.sc_project_sha_file,character(1))
  tab <- function(path)utils::read.delim(path,header=FALSE,colClasses="character",quote="",comment.char="",check.names=FALSE,na.strings=character())
  features <- tab(files[["features"]]); barcodes <- tab(files[["barcodes"]])
  if (!ncol(features)%in%c(2L,3L)||ncol(barcodes)!=1L)
    stop("10x features need 2 or 3 columns and barcodes one column; supply standard MEX files.",call.=FALSE)
  names(features) <- c("feature_id","feature_name","feature_type")[seq_len(ncol(features))]
  if (ncol(features)==2L) features$feature_type <- "Gene Expression"
  .sc_project_ids(features$feature_id,"10x feature IDs")
  .sc_project_ids(barcodes[[1]],"10x barcodes")
  if (any(grepl("::",barcodes[[1]],fixed=TRUE))) stop("10x barcode contains reserved '::'; provide literal unprefixed barcodes.",call.=FALSE)
  if (anyNA(features)||any(!nzchar(as.matrix(features)))) stop("10x feature fields must not be empty.",call.=FALSE)
  con <- if (grepl("[.]gz$",files[["matrix"]])) gzfile(files[["matrix"]],"rt") else file(files[["matrix"]],"rt")
  on.exit(close(con),add=TRUE)
  counts <- Matrix::readMM(con)
  if (!"x"%in%methods::slotNames(counts) || any(!is.finite(counts@x)) || any(counts@x<0) || any(counts@x!=floor(counts@x)))
    stop("10x MEX entries must be finite nonnegative integer raw counts before sparse aggregation; restore a genuine counts matrix.",call.=FALSE)
  counts <- methods::as(counts,"CsparseMatrix")
  if (!identical(dim(counts),c(nrow(features),nrow(barcodes)))) stop("10x matrix dimensions do not match features/barcodes; restore a matching file set.",call.=FALSE)
  keep <- features$feature_type=="Gene Expression"
  if (!any(keep)) stop("10x files contain no Gene Expression features; choose the gene-expression MEX directory.",call.=FALSE)
  selected <- features[keep,,drop=FALSE]
  keys <- selected[[if (feature_key=="name") "feature_name" else "feature_id"]]
  reason<-rep("unchanged",length(keys))
  if (feature_key=="name") {
    duplicate<-duplicated(keys)|duplicated(keys,fromLast=TRUE)
    invalid<-grepl("[_|]",keys)
    suffix<-vapply(selected$feature_id,function(id)substr(digest::digest(id,algo="sha256",serialize=FALSE),1,16),character(1))
    # Technical keys are never biological aliases. Neutral keys avoid creating
    # a new canonical symbol/MT prefix from an incompatible source symbol.
    keys[duplicate&!invalid]<-paste0(keys[duplicate&!invalid],".feature-",suffix[duplicate&!invalid])
    keys[invalid]<-paste0("feature-",suffix[invalid])
    reason[duplicate]<-"duplicate original symbol; feature-ID technical suffix, no inferred symbol mapping"
    reason[invalid]<-"Seurat-incompatible original name; neutral technical key, no biological alias"
  }
  if (anyDuplicated(keys)||any(grepl("[_|]",keys))) stop("10x analysis keys are duplicated or Seurat-incompatible; resolve an explicit feature mapping before importing.",call.=FALSE)
  selected$analysis_key<-keys;selected$analysis_reason<-reason
  counts <- counts[keep,,drop=FALSE]; dimnames(counts)<-list(keys,barcodes[[1]])
  .sc_project_matrix(counts,"10x Gene Expression counts",raw_counts=TRUE)
  if (!identical(hashes,vapply(files,.sc_project_sha_file,character(1)))) stop("10x source changed while reading; retry with stable files.",call.=FALSE)
  list(counts=counts,features=selected,files=as.list(files),sha256=as.list(hashes),
    excluded_features=sum(!keep),excluded_feature_types=sort(unique(features$feature_type[!keep])))
}
.sc_ui_tenx_input <- function(input,context,sample_id=NULL,matrix_kind=NULL,cell_metadata=NULL,feature_key="name") {
  feature_key <- match.arg(feature_key,c("name","id"))
  imported <- is.data.frame(input)||(is.character(input)&&length(input)==1L&&
    (dir.exists(input)||grepl("[.](csv|tsv)$",input,ignore.case=TRUE)))
  if (!imported) {
    if (!is.null(sample_id)||!is.null(matrix_kind)||!is.null(cell_metadata)) stop("10x options require a MEX directory or sample table input.",call.=FALSE)
    return(list(input=input,context=context,imported=FALSE))
  }
  source_tables<-list()
  if (is.character(input)&&!dir.exists(input)) source_tables$samples<-list(path=normalizePath(input,mustWork=TRUE),sha256=.sc_project_sha_file(input))
  if (is.character(cell_metadata)&&length(cell_metadata)==1L) source_tables$cells<-list(path=normalizePath(cell_metadata,mustWork=TRUE),sha256=.sc_project_sha_file(cell_metadata))
  if (is.null(context)) context<-list()
  if (!is.list(context)) stop("context must be a named list.",call.=FALSE)
  single <- is.character(input)&&length(input)==1L&&dir.exists(input)
  base <- if (is.character(input)&&!single) dirname(normalizePath(input,mustWork=TRUE)) else getwd()
  if (single) {
    .sc_project_string(sample_id,"sample_id")
    .sc_project_string(matrix_kind,"matrix_kind ('raw' or 'filtered')")
    samples <- data.frame(sample_id=sample_id,path=normalizePath(input,mustWork=TRUE),matrix_kind=matrix_kind,stringsAsFactors=FALSE)
  } else {
    if (!is.null(sample_id)||!is.null(matrix_kind)) stop("Put sample_id and matrix_kind in every sample table row, not separate arguments.",call.=FALSE)
    samples <- .sc_ui_tenx_table(input,"Sample")
  }
  roles<-c("donor","condition","batch","capture","treatment","qc_group","group")
  if (!all(c("sample_id","path","matrix_kind")%in%names(samples))||length(setdiff(names(samples),c("sample_id","path","matrix_kind",roles))))
    stop("Sample table needs sample_id, path, matrix_kind; optional columns are donor, condition, batch, capture, treatment, qc_group, group.",call.=FALSE)
  if (anyDuplicated(samples$sample_id)||any(!grepl("^[A-Za-z0-9][A-Za-z0-9.-]*$",samples$sample_id)))
    stop("sample_id must be unique nonempty IDs containing letters, digits, '.' or '-'; correct duplicate IDs before importing.",call.=FALSE)
  if (any(!samples$matrix_kind%in%c("raw","filtered"))) stop("Declare matrix_kind as 'raw' or 'filtered' for every sample; this is not inferred from directory names.",call.=FALSE)
  if (any(!nzchar(samples$path))) stop("Sample paths must not be empty.",call.=FALSE)
  samples$path<-vapply(samples$path,function(path) {
    path<-if (grepl("^(/|~)",path))path.expand(path) else file.path(base,path)
    if (!dir.exists(path)) stop("10x directory is missing; correct the sample table path.",call.=FALSE)
    normalizePath(path,mustWork=TRUE)
  },character(1))
  if (anyDuplicated(samples$path)) stop("A 10x directory occurs more than once; list each source once with its actual sample_id.",call.=FALSE)
  reads<-lapply(samples$path,.sc_ui_tenx_read,feature_key=feature_key)
  first<-reads[[1]]$features
  metadata<-vector("list",length(reads))
  for (i in seq_along(reads)) {
    features<-reads[[i]]$features
    if (!setequal(features$feature_id,first$feature_id)) stop("Gene Expression feature sets differ between samples. No intersection/union is applied; harmonize explicitly with a recorded mapping before importing.",call.=FALSE)
    order<-match(first$feature_id,features$feature_id)
    if (!identical(unname(as.matrix(features[order,,drop=FALSE])),unname(as.matrix(first))))
      stop("Feature ID/name/type mapping differs between samples; resolve the conflicting feature annotation explicitly.",call.=FALSE)
    reads[[i]]$counts<-reads[[i]]$counts[order,,drop=FALSE]
    barcodes<-colnames(reads[[i]]$counts)
    ids<-paste(samples$sample_id[i],barcodes,sep="::")
    colnames(reads[[i]]$counts)<-ids
    row<-samples[rep(i,length(ids)),setdiff(names(samples),c("path","matrix_kind")),drop=FALSE]
    row$tenx_barcode<-barcodes;row$tenx_matrix_kind<-samples$matrix_kind[i];rownames(row)<-ids
    metadata[[i]]<-row
  }
  counts<-do.call(cbind,lapply(reads,`[[`,"counts"));metadata<-do.call(rbind,metadata)
  .sc_project_ids(colnames(counts),"Prefixed 10x cell IDs")
  joined<-FALSE; reordered<-FALSE
  if (!is.null(cell_metadata)) {
    cells<-.sc_ui_tenx_table(cell_metadata,"Cell metadata")
    if (!all(c("sample_id","barcode")%in%names(cells))) stop("Cell metadata needs explicit sample_id and barcode columns; do not rely on row order.",call.=FALSE)
    ids<-paste(cells$sample_id,cells$barcode,sep="::")
    if (anyDuplicated(ids)||!setequal(ids,colnames(counts))) stop("Cell metadata must cover every imported sample_id/barcode exactly once with no extra cells; correct missing/duplicate/foreign keys.",call.=FALSE)
    extra<-setdiff(names(cells),c("sample_id","barcode"))
    if (length(intersect(extra,names(metadata)))) stop("Cell metadata repeats sample-level or reserved columns; keep each field in one table.",call.=FALSE)
    reordered<-!identical(ids,colnames(counts));joined<-TRUE
    metadata<-cbind(metadata,cells[match(colnames(counts),ids),extra,drop=FALSE])
    rownames(metadata)<-colnames(counts)
  }
  columns<-context$columns
  if (is.null(columns)) columns<-list()
  if (is.character(columns))columns<-as.list(columns)
  if (!is.list(columns)|| (length(columns)&&(is.null(names(columns))||anyDuplicated(names(columns))))) stop("context$columns must be a named role mapping.",call.=FALSE)
  declared<-c(sample="sample_id",stats::setNames(intersect(roles,names(samples)),intersect(roles,names(samples))))
  for(role in names(declared)) {
    if(!is.null(columns[[role]])&&!identical(columns[[role]],unname(declared[[role]]))) stop("context$columns conflicts with the explicit sample table role ",role,"; use its declared column.",call.=FALSE)
    columns[[role]]<-unname(declared[[role]])
  }
  context$columns<-columns
  seu<-Seurat::CreateSeuratObject(counts=counts,min.cells=0,min.features=0,meta.data=metadata,assay="RNA")
  feature_metadata<-first;names(feature_metadata)<-paste0("sc_",names(first));rownames(feature_metadata)<-rownames(counts)
  seu[["RNA"]]<-SeuratObject::AddMetaData(seu[["RNA"]],feature_metadata)
  provenance<-list(schema="scagentkit.tenx-import.v1",feature_key=feature_key,
    feature_policy="Exact Gene Expression feature ID set; reorder by first sample, no intersection/union or gene aggregation. Original ID/name/type retained; analysis-key changes listed explicitly.",
    key_changes=first[first$analysis_key!=first[[if(feature_key=="name")"feature_name" else "feature_id"]],,drop=FALSE],
    n_key_changes=sum(first$analysis_key!=first[[if(feature_key=="name")"feature_name" else "feature_id"]]),
    n_features=nrow(counts),n_cells=ncol(counts),cell_id_format="sample_id::barcode",samples=cbind(samples,n_cells=vapply(reads,function(x)ncol(x$counts),integer(1))),
    symbol_note=if(feature_key=="id") "Feature IDs are the analysis keys. Symbol-based mitochondrial, cycle and reference evidence may be unavailable; no automatic ID-to-symbol mapping was performed." else "Compatible unique symbols keep their original analysis keys. Incompatible names receive neutral feature-ID keys; all duplicate-name members receive stable technical suffixes; original IDs/names/types are retained, with no inferred symbol mapping for changed keys.",
    files=lapply(reads,function(x)list(paths=x$files,sha256=x$sha256,excluded_features=x$excluded_features,excluded_feature_types=x$excluded_feature_types)),
    source_tables=source_tables,
    cell_metadata=list(supplied=joined,reordered_by_key=reordered,missing=0L,extra=0L,sha256=if(joined).sc_run_hash(metadata) else NULL),
    raw_note="Raw matrices retain all supplied barcodes. Empty-droplet calling, ambient correction and doublet detection were not performed by import.")
  for (record in source_tables) if (!file.exists(record$path)||!identical(record$sha256,.sc_project_sha_file(record$path)))
    stop("Source metadata table changed while reading; retry with stable files.",call.=FALSE)
  for (record in reads) if (!identical(unlist(record$sha256),vapply(unlist(record$files),.sc_project_sha_file,character(1))))
    stop("10x source changed during multi-sample import; retry with stable files.",call.=FALSE)
  provenance$hash<-.sc_run_hash(provenance)
  seu@misc$scagentkit_tenx_import<-provenance
  invisible(.sc_run_context(context,seu))
  list(input=seu,context=context,imported=TRUE)
}

# Browser-only projection; local source paths never enter the model summary.
.sc_ui_import_summary <- function(project_dir,view) {
  root<-.sc_run_root(project_dir);state<-.sc_run_load(root)
  if (!identical(view$project_id,state$project_id)||!identical(view$input_hash,state$input_hash)||
      !identical(view$revision,state$revision)) stop("Import summary has a stale project binding.",call.=FALSE)
  input<-.sc_run_get(root,state,"input")
  record<-input@misc$scagentkit_tenx_import
  if (is.null(record)) return(view)
  hash<-record$hash;record$hash<-NULL
  if (!identical(record$schema,"scagentkit.tenx-import.v1")||!identical(hash,.sc_run_hash(record)))
    stop("Protected import receipt is invalid.",call.=FALSE)
  record$columns<-state$config$context$columns
  view$input_import<-record
  view
}
