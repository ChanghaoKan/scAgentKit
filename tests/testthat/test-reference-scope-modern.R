test_that("modern reference scope requires explicit fields and excludes all-tissue fallback", {
  env<-new.env();utils::data("pbmc_small",package="SeuratObject",envir=env)
  seu<-env$pbmc_small;seu$seurat_clusters<-as.character(SeuratObject::Idents(seu))
  markers<-data.frame(cluster="0",gene="CD3D")
  reference<-data.frame(cell_type="T cell",marker="CD3D",species="human",tissue="all")
  context<-list(species="human",tissue="blood")
  run<-function(ref=reference,ctx=context) .sc_run_reference_evidence(seu,markers,ctx,ref,"seurat_clusters",list(strict_scope=TRUE))
  absent<-run();expect_identical(absent$provenance$status,"scope_mismatch")
  expect_equal(nrow(absent$matches),0L);expect_equal(absent$provenance$scope$tissue_all_rows,0L)
  expect_match(absent$provenance$scope_notice,"no all-tissue fallback")
  reference$tissue<-"Peripheral blood"
  matched<-run();expect_identical(matched$provenance$status,"matched")
  expect_equal(nrow(matched$matches),1L)
  missing<-reference;missing$species<-NULL
  expect_error(run(missing),"Add the missing fields: species")
  expect_error(run(ctx=list(species="human")),"Add the missing fields: tissue")
  expect_error(run(ctx=list(species="human",tissue="all")),"actual tissue")
  reference$species<-"mouse"
  expect_identical(run()$provenance$status,"scope_mismatch")
})
