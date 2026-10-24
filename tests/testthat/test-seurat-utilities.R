test_that("retained metrics preserve raw counts and require an explicit species or patterns", {
  counts<-Matrix::Matrix(matrix(c(2,4,3,5,7,9,11,13),4,2,
    dimnames=list(c("MT-CO1","RPSA","RPS6KB1","HBA1"),c("001","NA"))),sparse=TRUE)
  x<-Seurat::CreateSeuratObject(counts,min.cells=0,min.features=0)
  before<-.sc_run_hash(x)
  expect_error(qc_add_metrics(x),"Declare species")
  for(assay_type in c("Assay5","Assay")) {
    use<-if(assay_type=="Assay")withr::with_options(list(Seurat.object.assay.version="v3"),Seurat::CreateSeuratObject(counts,min.cells=0,min.features=0)) else x
    out<-qc_add_metrics(use,species="human")
    expect_identical(colnames(out),colnames(x));expect_identical(rownames(out),rownames(x))
    expect_equal(unname(out$percent.ribo),100*as.numeric(counts["RPSA",])/as.numeric(Matrix::colSums(counts)))
    expect_identical(SeuratObject::LayerData(out,assay="RNA",layer="counts"),SeuratObject::LayerData(use,assay="RNA",layer="counts"))
  }
  expect_identical(.sc_run_hash(x),before)
})
test_that("QC defaults resolve aligned symbols and preserve unavailable family measurements", {
  counts <- Matrix::Matrix(matrix(c(2, 2, 1, 3, 0, 4, 0, 0), 2, 4,
    dimnames = list(c("ENSG00000198888", "ENSG00000141510"), c("001", "NA", "zero", "empty"))), sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  object[["RNA"]] <- SeuratObject::AddMetaData(object[["RNA"]],
    data.frame(gene_symbol = c("MT-ND1", "TP53"), row.names = rownames(counts)))
  original <- .sc_run_hash(object)
  measured <- qc_add_metrics(object, species = "human")
  expect_equal(unname(measured$percent.mt), c(50, 25, 0, NA_real_))
  expect_true(all(is.na(measured$percent.ribo)))
  expect_true(all(is.na(measured$percent.hb)))
  expect_identical(measured@misc$qc_metric_source$metrics$percent.mt$mapping_source, "feature_metadata:gene_symbol")
  expect_identical(.sc_run_hash(object), original)
  conflicted <- object
  conflicted[["RNA"]] <- SeuratObject::AddMetaData(conflicted[["RNA"]],
    data.frame(symbol = c("TP53", "TP53"), row.names = rownames(counts)))
  expect_true(all(is.na(qc_add_metrics(conflicted, species = "human")$percent.mt)))
  explicit <- qc_add_metrics(conflicted, mt_pattern = "98888$", ribo_pattern = "41510$", hb_pattern = "absent")
  expect_equal(unname(explicit$percent.mt), c(50, 25, 0, NA_real_))
  expect_true(all(is.na(explicit$percent.hb)))
  expect_identical(.sc_run_hash(measured@assays$RNA@layers$counts), .sc_run_hash(object@assays$RNA@layers$counts))
  expect_identical(.sc_run_hash(object), original)
  unmapped <- object
  unmapped[["RNA"]][["gene_symbol"]] <- NULL
  expect_true(all(is.na(qc_add_metrics(unmapped, species = "human")$percent.mt)))
})

test_that("split merge needs declared roles and explicit collision handling", {
  x<-SeuratObject::pbmc_small;x$source_sample<-rep(c("A","B"),each=40)
  before<-.sc_run_hash(x);parts<-qc_split(x,"source_sample")
  expect_setequal(names(parts),c("A","B"));expect_equal(vapply(parts,ncol,1L),c(A=40L,B=40L))
  merged<-qc_merge(parts)
  expect_setequal(colnames(merged),colnames(x))
  expect_equal(as.matrix(SeuratObject::LayerData(merged,layer="counts"))[,colnames(x)],as.matrix(SeuratObject::LayerData(x,layer="counts")))
  expect_error(qc_split(x,"guessed_batch"),"absent")
  expect_error(qc_merge(list(x,x)),"Duplicate cell IDs")
  explicit<-qc_merge(list(x,x),add_cell_ids=c("copy1","copy2"))
  expect_identical(ncol(explicit),160L);expect_false(anyDuplicated(colnames(explicit))>0)
  expect_identical(.sc_run_hash(x),before)
})
test_that("plot utilities save real figures without mutating Seurat or requesting a model", {
  raw<-Seurat::CreateSeuratObject(SeuratObject::LayerData(SeuratObject::pbmc_small,layer="counts"))
  x<-qc_add_metrics(raw,species="human")
  x<-sc_project_prepare(x,nfeatures=100,npcs=5,dims=1:4,run_umap=TRUE,seed=17)
  x$sc_annotation<-"Unknown";before<-.sc_run_hash(x);path<-tempfile();dir.create(path)
  qc<-qc_plot(x,out_dir=path,group_by=NULL)
  umap<-sc_plot_umap(x,out_dir=path)
  expect_true(all(file.exists(c(qc,umap))))
  expect_true(all(file.info(c(qc,umap))$size>1000))
  expect_identical(.sc_run_hash(x),before)
  expect_error(qc_plot(x,out_dir=path,group_by="absent"),"absent")
})
test_that("ontology utilities map an explicit table or Seurat copy without approving labels", {
  skip_if_not_installed("ontologyIndex")
  path<-tempfile(fileext=".obo")
  writeLines(c("format-version: 1.2","","[Term]","id: CL:0000001","name: test cell",'synonym: "exact alias" EXACT []'),path)
  table<-data.frame(label=c("test cell","exact alias","unknown"))
  mapped<-annot_map_to_cl(table,obo_path=path)
  expect_identical(mapped$cl_id,c("CL:0000001","CL:0000001",NA_character_))
  expect_false("cl_id" %in% names(table))
  x<-SeuratObject::pbmc_small;x$sc_annotation<-"test cell";before<-.sc_run_hash(x)
  out<-annot_map_to_cl(x,obo_path=path)
  expect_true(all(out$cl_id=="CL:0000001"));expect_identical(out$sc_annotation,x$sc_annotation)
  expect_identical(.sc_run_hash(x),before)
})
