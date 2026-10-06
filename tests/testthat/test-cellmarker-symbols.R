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
             tissue_type = "Peripheral blood", cancer_type = "Normal",
             stringsAsFactors = FALSE)
}

test_that("CellMarker gene symbols take precedence over protein aliases and retain provenance", {
  skip_if_not_installed("readxl")
  cache <- mock_cellmarker_cache()
  on.exit(unlink(cache$path, recursive = TRUE))
  url <- "https://example.invalid/pinned-cellmarker.xlsx"
  writeLines(url, paste0(cache$file, ".source-url"))
  local_mocked_bindings(.cellmarker_read_excel = function(...) cellmarker_symbol_fixture(),
                        .package = "scAgentKit")
  ref <- annot_query_cellmarker("human", tissue = "blood", cache_dir = cache$path, url = url)
  expect_identical(ref$marker, c("FCGR3A", "MRC1"))
  expect_false(any(ref$marker %in% c("CD16", "CD206")))
  expect_identical(attr(ref, "marker_column"), "Symbol")
  expect_identical(attr(ref, "source_path"), normalizePath(cache$file))
  expect_identical(attr(ref, "source_md5"), unname(tools::md5sum(cache$file)))
  expect_identical(attr(ref, "source_url"), url)
  expect_identical(attr(ref, "source_version"), "CellMarker2.0")
  expect_true(attr(ref, "source_url_verified"))
  obj <- AgentSeurat(list(s1 = "stub"))
  obj@params$markers_filtered <- data.frame(cluster = "0", gene = "FCGR3A")
  out <- annot_match_reference(obj, ref)
  expect_identical(out@params$reference_matches$matched_markers, "FCGR3A")
  expect_identical(out@params$reference_provenance$marker_column, "Symbol")
  expect_identical(out@params$reference_provenance$source_url, url)
})

test_that("CellMarker prefers gene_symbol fallback before marker and documents manual cache URL", {
  skip_if_not_installed("readxl")
  cache <- mock_cellmarker_cache()
  on.exit(unlink(cache$path, recursive = TRUE))
  raw <- cellmarker_symbol_fixture()
  raw$Symbol <- NULL
  raw$gene_symbol <- c("FCGR3A", "MRC1")
  local_mocked_bindings(.cellmarker_read_excel = function(...) raw,
                        .package = "scAgentKit")
  ref <- annot_query_cellmarker("human", cache_dir = cache$path)
  expect_identical(ref$marker, c("FCGR3A", "MRC1"))
  expect_identical(attr(ref, "marker_column"), "gene_symbol")
  expect_false(attr(ref, "source_url_verified"))
  expect_true(is.na(attr(ref, "source_url")))
  expect_match(attr(ref, "requested_url"), "Cell_marker_Human.xlsx", fixed = TRUE)
  raw$gene_symbol <- NULL
  ref <- annot_query_cellmarker("human", cache_dir = cache$path)
  expect_identical(ref$marker, c("CD16", "CD206"))
  expect_identical(attr(ref, "marker_column"), "marker")
})

test_that("CellMarker cache detects different recorded URL without contacting the network", {
  skip_if_not_installed("readxl")
  cache <- mock_cellmarker_cache()
  on.exit(unlink(cache$path, recursive = TRUE))
  writeLines("https://example.invalid/source-a.xlsx", paste0(cache$file, ".source-url"))
  expect_error(annot_query_cellmarker("human", cache_dir = cache$path,
                                     url = "https://example.invalid/source-b.xlsx"),
               "different URL")
})
