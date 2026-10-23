tenx_fixture <- function(path=tempfile(),sample=1L,gzip=FALSE,n_genes=6L,n_cells=4L,multimodal=TRUE) {
  dir.create(path,recursive=TRUE)
  ids<-paste0("ENSG",seq_len(n_genes));genes<-paste0("G",seq_len(n_genes));barcodes<-paste0("ACGT",seq_len(n_cells),"-1")
  counts<-Matrix::Matrix(matrix(seq_len(n_genes*n_cells)%%5L,nrow=n_genes),sparse=TRUE)
  features<-data.frame(ids,genes,type="Gene Expression")
  if(multimodal){counts<-rbind(counts,rep(2,n_cells));features<-rbind(features,data.frame(ids="ADT1",genes="G1",type="Antibody Capture"))}
  Matrix::writeMM(counts,file.path(path,"matrix.mtx"))
  utils::write.table(features,file.path(path,"features.tsv"),sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  writeLines(barcodes,file.path(path,"barcodes.tsv"))
  if(gzip)for(name in c("matrix.mtx","features.tsv","barcodes.tsv")) {
    file<-file.path(path,name);con<-gzfile(paste0(file,".gz"),"wb");writeBin(readBin(file,"raw",file.info(file)$size),con);close(con);unlink(file)
  }
  list(path=path,counts=counts[seq_len(n_genes),,drop=FALSE],ids=ids,genes=genes,barcodes=barcodes)
}
tenx_context<-function()list(species="human",tissue="Synthetic test",research_goal="Offline software input verification")

test_that("10x single MEX keeps sparse Gene Expression identity and source files",{
  f<-tenx_fixture(gzip=TRUE)
  files<-list.files(f$path,full.names=TRUE);before<-vapply(files,.sc_project_sha_file,character(1))
  x<-.sc_ui_tenx_input(f$path,tenx_context(),"S1","raw")
  counts<-SeuratObject::LayerData(x$input[["RNA"]],layer="counts")
  expect_true(inherits(counts,"sparseMatrix"));expect_identical(rownames(counts),f$genes)
  expect_identical(colnames(counts),paste("S1",f$barcodes,sep="::"))
  expect_equal(unname(as.matrix(counts)),unname(as.matrix(f$counts)))
  expect_identical(x$input[["RNA"]][[]]$sc_feature_id,f$ids)
  expect_true(all(x$input[["RNA"]][[]]$sc_feature_type=="Gene Expression"))
  p<-x$input@misc$scagentkit_tenx_import
  expect_identical(p$samples$matrix_kind,"raw");expect_match(p$raw_note,"Empty-droplet")
  expect_identical(p$files[[1]]$excluded_features,1L)
  expect_identical(x$context$columns$sample,"sample_id")
  expect_identical(vapply(files,.sc_project_sha_file,character(1)),before)
  expect_error(.sc_ui_tenx_input(f$path,tenx_context(),"S1"),"matrix_kind")
})

test_that("sample table prefixes repeated barcodes and joins shuffled metadata by exact keys",{
  a<-tenx_fixture();b<-tenx_fixture()
  # A second feature file/matrix has a different physical row order.
  file<-file.path(b$path,"features.tsv");features<-read.delim(file,header=FALSE)
  order<-rev(seq_len(nrow(features)));utils::write.table(features[order,],file,sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  mm<-Matrix::readMM(file.path(b$path,"matrix.mtx"));Matrix::writeMM(mm[order,],file.path(b$path,"matrix.mtx"))
  samples<-data.frame(sample_id=c("S1","S2"),path=c(a$path,b$path),matrix_kind=c("filtered","raw"),donor=c("D1","D2"),condition=c("control","treated"))
  meta<-data.frame(sample_id=rep(samples$sample_id,each=4),barcode=rep(a$barcodes,2),measurement=as.character(1:8))
  meta<-meta[8:1,]
  x<-.sc_ui_tenx_input(samples,tenx_context(),cell_metadata=meta)
  expect_identical(colnames(x$input),paste(rep(c("S1","S2"),each=4),rep(a$barcodes,2),sep="::"))
  expect_identical(x$input$measurement,stats::setNames(as.character(1:8),colnames(x$input)))
  expect_identical(unname(x$input$donor),rep(c("D1","D2"),each=4))
  expect_identical(unname(x$input$condition),rep(c("control","treated"),each=4))
  expect_identical(x$context$columns$donor,"donor");expect_identical(x$context$columns$condition,"condition")
  expect_true(x$input@misc$scagentkit_tenx_import$cell_metadata$reordered_by_key)
  counts<-SeuratObject::LayerData(x$input[["RNA"]],layer="counts")
  expect_equal(unname(as.matrix(counts[,1:4])),unname(as.matrix(counts[,5:8])))
  expect_null(x$context$design)
  bad<-samples;bad$sample_id[2]<-"S1";expect_error(.sc_ui_tenx_input(bad,tenx_context()),"unique")
  bad<-samples;bad$path[2]<-a$path;expect_error(.sc_ui_tenx_input(bad,tenx_context()),"more than once")
  expect_error(.sc_ui_tenx_input(samples,tenx_context(),cell_metadata=meta[-1,]),"every imported")
  wrong<-meta;wrong$barcode[1]<-"FOREIGN";expect_error(.sc_ui_tenx_input(samples,tenx_context(),cell_metadata=wrong),"every imported")
  wrong<-meta;wrong[1,]<-wrong[2,];expect_error(.sc_ui_tenx_input(samples,tenx_context(),cell_metadata=wrong),"exactly once")
  expect_error(.sc_ui_tenx_input(samples,modifyList(tenx_context(),list(columns=list(sample="other")))),"conflicts")
  features$V1[1]<-"foreign_gene";utils::write.table(features,file,sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  expect_error(.sc_ui_tenx_input(samples,tenx_context()),"feature sets differ")
})

test_that("feature ambiguity and incomplete MEX fail without silent repair",{
  f<-tenx_fixture();file<-file.path(f$path,"features.tsv");ft<-read.delim(file,header=FALSE)
  ft$V2[2]<-ft$V2[1];utils::write.table(ft,file,sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  named<-.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered")
  expect_true(all(grepl("^G1.feature-",rownames(named$input)[1:2])))
  expect_false(anyDuplicated(rownames(named$input))>0L)
  expect_identical(named$input@misc$scagentkit_tenx_import$n_key_changes,2L)
  expect_identical(named$input[["RNA"]][[]]$sc_feature_name,ft$V2[seq_along(f$ids)])
  x<-.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered",feature_key="id")
  expect_identical(rownames(x$input),f$ids)
  expect_identical(x$input[["RNA"]][[]]$sc_feature_name,ft$V2[seq_along(f$ids)])
  unlink(file);expect_error(.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered"),"exactly one")
  f<-tenx_fixture();writeLines("one-barcode",file.path(f$path,"barcodes.tsv"))
  expect_error(.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered"),"dimensions")
})

test_that("sample TSV resolves relative directories and sc_analyze uses the existing review kernel",{
  root<-tempfile();dir.create(root);f<-tenx_fixture(file.path(root,"sample"),n_genes=80,n_cells=40)
  # The small reader fixture repeats modulo-five columns at 80 genes. This
  # entry smoke needs genuinely varying profiles; constant-data rejection is
  # tested separately and must not be bypassed just to check the importer.
  varied<-outer(seq_len(80L),seq_len(40L),function(g,cell) (17*g+23*cell+11*g*cell)%%101)
  Matrix::writeMM(Matrix::Matrix(rbind(varied,rep(2L,40L)),sparse=TRUE),file.path(f$path,"matrix.mtx"))
  samples<-data.frame(sample_id="S1",path="sample",matrix_kind="filtered",donor="D1",condition="control")
  table<-file.path(root,"samples.tsv");utils::write.table(samples,table,sep="\t",quote=FALSE,row.names=FALSE)
  x<-.sc_ui_tenx_input(table,tenx_context())
  expect_identical(x$input@misc$scagentkit_tenx_import$samples$path,normalizePath(f$path))
  project<-tempfile()
  result<-sc_analyze(table,project,tenx_context(),plan=list(analysis=list(nfeatures=60,npcs=5),pcs=5,umap=FALSE))
  expect_identical(result$view$status,"awaiting_review");expect_identical(result$view$stage,"strategy_propose")
  state<-.sc_run_load(project);saved<-.sc_run_get(project,state,"input")
  expect_identical(saved@misc$scagentkit_tenx_import,x$input@misc$scagentkit_tenx_import)
  expect_identical(state$config$context$columns$sample,"sample_id")
  expect_identical(state$source$type,"local_rds")
  expect_false(file.exists(state$source$path))
  expect_null(state$files$analysis)
  before<-.sc_project_sha_file(file.path(project,"state.rds"))
  local<-.sc_ui_import_summary(project,result$view)
  expect_identical(local$input_import$n_cells,40L)
  expect_identical(local$input_import$samples$sample_id,"S1")
  expect_identical(.sc_project_sha_file(file.path(project,"state.rds")),before)
  stale<-result$view;stale$input_hash<-"foreign";expect_error(.sc_ui_import_summary(project,stale),"stale")
})


test_that("raw triplet values cannot hide invalid counts through duplicate aggregation",{
  f<-tenx_fixture()
  for(values in list(c(-1,2),c(.5,.5),c(NA,2))) {
    writeLines(c("%%MatrixMarket matrix coordinate real general","7 4 2",paste("1 1",values)),file.path(f$path,"matrix.mtx"))
    expect_error(.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered"),"raw counts")
  }
})

test_that("ID keys use existing explicit mitochondrial symbols without renaming features",{
  f<-tenx_fixture();file<-file.path(f$path,"features.tsv");ft<-read.delim(file,header=FALSE);ft$V2[1]<-"MT-ND1"
  utils::write.table(ft,file,sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  x<-.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered",feature_key="id")
  qc<-.sc_run_qc_evidence(x$input,x$context)
  expect_true(qc$summary$mitochondrial$available)
  expect_identical(qc$summary$mitochondrial$mapping_source,"feature_metadata:sc_feature_name")
  expect_identical(qc$summary$mitochondrial$feature_count,1L)
  counts<-SeuratObject::LayerData(x$input,assay="RNA",layer="counts")
  expect_equal(unname(qc$metrics$percent_mt),unname(100*as.numeric(counts[1,])/Matrix::colSums(counts)))
  expect_identical(rownames(x$input),f$ids)
  expect_match(x$input@misc$scagentkit_tenx_import$symbol_note,"unavailable")
})


test_that("explicit analysis keys preserve duplicate symbols and Seurat separator collisions without gene loss",{
  f<-tenx_fixture();file<-file.path(f$path,"features.tsv");ft<-read.delim(file,header=FALSE)
  ft$V2[1:3]<-c("Gene_A","Gene-A","Gene|A")
  utils::write.table(ft,file,sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  x<-.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered")
  keys<-rownames(x$input)
  expect_true(all(grepl("^feature-",keys[c(1,3)])))
  expect_identical(keys[2],"Gene-A")
  expect_identical(x$input[["RNA"]][[]]$sc_feature_id,f$ids)
  expect_identical(x$input[["RNA"]][[]]$sc_feature_name,ft$V2[1:6])
  counts<-SeuratObject::LayerData(x$input[["RNA"]],layer="counts")
  expect_equal(unname(as.matrix(counts)),unname(as.matrix(f$counts)))
  y<-.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered")
  a<-tempfile();b<-tempfile();saveRDS(x$input,a,version=2L);saveRDS(y$input,b,version=2L)
  expect_identical(.sc_project_sha_file(a),.sc_project_sha_file(b))
  expect_identical(x$input@misc$scagentkit_tenx_import$key_changes$analysis_key,keys[c(1,3)])
})


test_that("technical key collisions fail globally and invalid symbols do not create MT aliases",{
  f<-tenx_fixture();file<-file.path(f$path,"features.tsv");ft<-read.delim(file,header=FALSE)
  suffix<-substr(digest::digest(f$ids[1],algo="sha256",serialize=FALSE),1,16)
  ft$V2[1:3]<-c("G","G",paste0("G.feature-",suffix))
  utils::write.table(ft,file,sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  expect_error(.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered"),"analysis keys are duplicated")
  ft$V2[1:3]<-c("MT_ND1","Gene_A","Gene_A")
  utils::write.table(ft,file,sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  x<-.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered")
  expect_false(any(grepl("^MT-",rownames(x$input))))
  expect_false(.sc_run_qc_evidence(x$input,x$context)$summary$mitochondrial$available)
  perm<-rev(seq_len(nrow(ft)))
  utils::write.table(ft[perm,],file,sep="\t",row.names=FALSE,col.names=FALSE,quote=FALSE)
  mm<-Matrix::readMM(file.path(f$path,"matrix.mtx"));Matrix::writeMM(mm[perm,],file.path(f$path,"matrix.mtx"))
  y<-.sc_ui_tenx_input(f$path,tenx_context(),"S1","filtered")
  a<-x$input[["RNA"]][[]];b<-y$input[["RNA"]][[]]
  expect_identical(stats::setNames(a$sc_analysis_key,a$sc_feature_id)[sort(a$sc_feature_id)],
    stats::setNames(b$sc_analysis_key,b$sc_feature_id)[sort(a$sc_feature_id)])
})

test_that("feature preflight explains differences before loading mismatched matrices", {
  a<-tenx_fixture();b<-tenx_fixture(n_genes=5L)
  samples<-data.frame(sample_id=c("first","second"),path=c(a$path,b$path),matrix_kind="filtered")
  writeLines("deliberately unreadable matrix",file.path(b$path,"matrix.mtx"))
  expect_error(.sc_ui_tenx_input(samples,tenx_context()),"sample second vs first; missing 1 \\[ENSG6")
})
