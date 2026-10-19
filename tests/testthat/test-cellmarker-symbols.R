mock_cellmarker_cache <- function() {
  path <- tempfile("cellmarker-cache-")
  dir.create(path)
  file <- file.path(path, "CellMarker2_human.xlsx")
  writeBin(charToRaw("offline cache fixture"), file)
  list(path = path, file = file)
}

cellmarker_symbol_fixture <- function() {
  data.frame(cell_name = c("Monocyte", "Macrophage"),
             marker = c("CD16", "CD206"), Symbol = c("FCGR3A", "MRC1"),
             gene_symbol = c("NOT_PREFERRED1", "NOT_PREFERRED2"),
             tissue_type = "Peripheral blood", cancer_type = "Normal", species = "Human",
             stringsAsFactors = FALSE)
}

test_that("explicit local CellMarker imports prefer gene symbols and record unverified local provenance", {
  skip_if_not_installed("readxl")
  cache <- mock_cellmarker_cache(); on.exit(unlink(cache$path, recursive = TRUE))
  writeLines("https://example.invalid/claimed-publisher.xlsx", paste0(cache$file, ".source-url"))
  local_mocked_bindings(.cellmarker_read_excel = function(...) cellmarker_symbol_fixture(), .package = "scAgentKit")
  ref <- annot_query_cellmarker("human", tissue = "blood", local_file = cache$file,
    sha256 = digest::digest(file = cache$file, algo = "sha256"))
  expect_identical(ref$marker, c("FCGR3A", "MRC1"))
  expect_false(any(ref$marker %in% c("CD16", "CD206")))
  expect_identical(attr(ref, "marker_column"), "Symbol")
  expect_identical(attr(ref, "source_path"), normalizePath(cache$file))
  expect_identical(attr(ref, "source_md5"), unname(tools::md5sum(cache$file)))
  expect_identical(attr(ref, "source_sha256"), digest::digest(file = cache$file, algo = "sha256"))
  expect_true(is.na(attr(ref, "source_url")))
  expect_false(attr(ref, "source_url_verified"))
  expect_identical(attr(ref, "source_mode"), "explicit_local_import_unverified_publisher")
  expect_identical(attr(ref, "scope_status"), "matched")
  out <- annot_match_reference(data.frame(cluster="0",gene="FCGR3A"), ref)
  expect_identical(out$matched_markers,"FCGR3A")
  expect_identical(attr(out,"reference_provenance")$marker_column,"Symbol")
  expect_identical(attr(out,"reference_provenance")$source_sha256,attr(ref,"source_sha256"))
})

test_that("local gene_symbol fallback precedes marker and explicit scope never expands", {
  skip_if_not_installed("readxl")
  cache <- mock_cellmarker_cache(); on.exit(unlink(cache$path, recursive = TRUE))
  raw <- cellmarker_symbol_fixture(); raw$Symbol <- NULL; raw$gene_symbol <- c("FCGR3A", "MRC1")
  local_mocked_bindings(.cellmarker_read_excel = function(...) raw, .package = "scAgentKit")
  ref <- annot_query_cellmarker("human", tissue = "blood", local_file = cache$file)
  expect_identical(ref$marker, c("FCGR3A", "MRC1"))
  expect_identical(attr(ref,"marker_column"),"gene_symbol")
  raw$gene_symbol <- NULL
  ref <- annot_query_cellmarker("human", tissue = "blood", local_file = cache$file)
  expect_identical(ref$marker,c("CD16","CD206")); expect_identical(attr(ref,"marker_column"),"marker")
  absent <- annot_query_cellmarker("human", tissue = "liver", local_file = cache$file)
  expect_equal(nrow(absent),0);expect_identical(attr(absent,"scope_status"),"zero_matches")
  expect_match(attr(absent,"scope_notice"),"no all-tissue fallback")
  mouse <- annot_query_cellmarker("mouse", tissue = "blood", local_file = cache$file)
  expect_equal(nrow(mouse),0); expect_identical(attr(mouse,"scope_status"),"zero_matches")
})

test_that("CellMarker never contacts arbitrary mirrors or trusts a cache sidecar", {
  cache <- mock_cellmarker_cache(); on.exit(unlink(cache$path,recursive=TRUE))
  for (url in c("http://117.50.127.228/table.xlsx","https://example.invalid/source-a.xlsx"))
    expect_error(annot_query_cellmarker("human",tissue="blood",local_file=cache$file,url=url),"fixed official HTTPS")
  expect_error(annot_query_cellmarker("human",tissue="blood",cache_dir=cache$path),"waiting for a verified fixed")
  expect_error(annot_query_cellmarker("human",local_file=cache$file),"explicit tissue")
  expect_error(annot_query_cellmarker("human",tissue="blood",local_file=cache$file,sha256=paste(rep("0",64),collapse="")),"SHA256 does not match")
  expect_error(annot_query_cellmarker("human",tissue="blood",local_file=cache$file,force_refresh=TRUE),"waiting for a verified fixed")
})
