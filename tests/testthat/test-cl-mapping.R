cl_fixture_obo <- function() {
  path <- tempfile(fileext = ".obo")
  writeLines(c("format-version: 1.2", "",
    "[Term]", "id: CL:0000001", "name: test cell",
    'synonym: "exact alias" EXACT []',
    'synonym: "broad alias" BROAD [PMID:1]',
    'synonym: "typed exact" EXACT OMO:0003000 []',
    'synonym: "HSC" RELATED OMO:0003000 []', "",
    "[Term]", "id: CL:0000002", "name: obsolete cell", "is_obsolete: true", "",
    "[Term]", "id: UBERON:0000001", "name: test organ"), path)
  path
}

test_that("CL mapping uses only EXACT synonyms of non-obsolete CL terms", {
  skip_if_not_installed("ontologyIndex")
  cl <- scAgentKit:::.get_cl_ontology(cl_fixture_obo())
  id <- function(x) scAgentKit:::.cl_match_one(x, cl)$cl_id
  expect_identical(id("Test  Cell"), "CL:0000001")
  expect_identical(id("exact alias"), "CL:0000001")
  expect_identical(id("typed exact"), "CL:0000001")
  expect_identical(id("broad alias"), NA_character_)
  expect_identical(id("HSC"), NA_character_)
  expect_identical(id("obsolete cell"), NA_character_)
  expect_identical(id("test organ"), NA_character_)
  parsed <- scAgentKit:::.cl_synonym('"a \\"quoted\\" name" EXACT []')
  expect_identical(parsed, list(text = 'a "quoted" name', scope = "EXACT"))
})

test_that("the CL session cache is keyed by path and content", {
  skip_if_not_installed("ontologyIndex")
  first <- cl_fixture_obo()
  second <- tempfile(fileext = ".obo")
  writeLines(c("format-version: 1.2", "", "[Term]", "id: CL:0000099", "name: other cell"), second)
  expect_identical(scAgentKit:::.cl_match_one("test cell", scAgentKit:::.get_cl_ontology(first))$cl_id, "CL:0000001")
  other <- scAgentKit:::.get_cl_ontology(second)
  expect_identical(scAgentKit:::.cl_match_one("other cell", other)$cl_id, "CL:0000099")
  expect_identical(scAgentKit:::.cl_match_one("test cell", other)$cl_id, NA_character_)
  expect_identical(attr(other, "scAgentKit_source")$sha256, digest::digest(file = second, algo = "sha256"))
})
