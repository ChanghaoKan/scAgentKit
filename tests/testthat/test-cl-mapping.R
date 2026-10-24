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

test_that("fuzzy lookup ranks only current CL terms and grants no exact identity", {
  skip_if_not_installed("ontologyIndex")
  path <- cl_fixture_obo(); on.exit(unlink(path))
  for (query in c("obsolete cell", "test organ", "test cel")) {
    result <- cl_lookup(query, n = 10L, obo_path = path)
    expect_identical(result$cl_id, "CL:0000001")
  }
  expect_true(is.na(.cl_match_one("test cel", .get_cl_ontology(path))$cl_id))
})


test_that("default CL is a verified fixed local release with no imports or network", {
  skip_if_not_installed("ontologyIndex")
  cl <- .get_cl_ontology()
  source <- attr(cl, "scAgentKit_source")
  expect_identical(source$sha256, "c6274fb65cdf740b983a06b74cb678814249d7f8e580c2ec9de54bf204a2b1c7")
  expect_identical(source$mode, "fixed_bundled_release")
  expect_identical(source$provenance$release, "v2026-06-08")
  expect_identical(source$provenance$license, "CC-BY-4.0")
  expect_false(any(startsWith(readLines(source$path, warn = FALSE), "import:")))
  expect_identical(.cl_match_one("T cell", cl)$cl_id, "CL:0000084")
  expect_identical(.cl_match_one("T cel", cl)$cl_id, NA_character_)
})

test_that("ambiguous exact names or synonyms stay unresolved instead of picking the first ID", {
  cl <- list(name = c("CL:0000001" = "first cell", "CL:0000002" = "second cell"),
    synonym = list("CL:0000001" = '"shared alias" EXACT []', "CL:0000002" = '"shared alias" EXACT []'))
  expect_identical(.cl_match_one("shared alias", cl)$cl_id, NA_character_)
  cl$name[[2L]] <- "first cell"
  expect_identical(.cl_match_one("first cell", cl)$cl_id, NA_character_)
  cl$name[[2L]] <- "shared alias"
  expect_identical(.cl_match_one("shared alias", cl)$cl_id, NA_character_)
})
