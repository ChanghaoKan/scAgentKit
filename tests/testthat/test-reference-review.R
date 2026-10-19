





test_that("reference load filters tissue/species and records pinned-file provenance", {
  withr::local_options(lifecycle_verbosity="quiet")
  path <- tempfile(fileext = ".tsv")
  on.exit(unlink(path))
  ref <- data.frame(cell_type = c("T cell", "Mouse T", "Hepatocyte"),
                    marker = c("G1", "G2", "ALB"),
                    tissue = c(" Blood ", "blood", "liver"),
                    species = c(" HUMAN ", "mouse", "human"))
  write.table(ref, path, sep = "\t", row.names = FALSE, quote = FALSE)
  loaded <- annot_load_reference(path, tissue_filter = "blood", species = "human")
  expect_identical(loaded$cell_type, "T cell")
  expect_identical(attr(loaded, "source_path"), normalizePath(path))
  expect_identical(attr(loaded, "source_md5"), unname(tools::md5sum(path)))
  expect_equal(attr(loaded, "n_input_rows"), 3)
  out <- annot_match_reference(data.frame(cluster="0",gene="G1"),loaded)
  expect_identical(attr(out,"reference_provenance")$source_md5,attr(loaded,"source_md5"))
  expect_identical(attr(out,"reference_provenance")$source_path,normalizePath(path))
  expect_identical(out$cell_type,"T cell")
})
