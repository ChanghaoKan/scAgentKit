test_that("supported species are explicit human and mouse aliases only", {
  human <- c("human", " HUMAN ", "Homo sapiens", "homo_sapiens", "homo-sapiens",
             "H. sapiens", "h.sapiens", "hsapiens", "9606")
  mouse <- c("mouse", "Mus musculus", "mus_musculus", "mus-musculus",
             "M. musculus", "m.musculus", "mmusculus", "10090")
  for (value in human) expect_identical(scAgentKit:::.sc_run_species(value), "human")
  for (value in mouse) expect_identical(scAgentKit:::.sc_run_species(value), "mouse")
  expect_null(scAgentKit:::.sc_run_species(NULL, allow_missing = TRUE))
  expect_error(scAgentKit:::.sc_run_species(NULL), "Declare species explicitly")
  for (value in c("rat", "zebrafish", "human-like", "unknown", "MKI67", "Mki67"))
    expect_error(scAgentKit:::.sc_run_species(value), "Unsupported species")
  expect_identical(scAgentKit:::.sc_run_species_values(c("human", "Mus musculus", "rat", NA)),
                   c("human", "mouse", NA_character_, NA_character_))
})

test_that("context cannot infer species from symbols or create unsupported projects", {
  counts <- Matrix::Matrix(matrix(c(1, 2, 3, 4), nrow = 2,
    dimnames = list(c("MKI67", "Mki67"), c("001", "NA"))), sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  expect_null(scAgentKit:::.sc_run_context(list(), object)$species)
  expect_identical(scAgentKit:::.sc_run_context(list(species = "Homo sapiens"), object)$species, "human")
  expect_identical(scAgentKit:::.sc_run_context(list(species = "Mus musculus"), object)$species, "mouse")
  root <- tempfile("unsupported-species-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  calls <- 0L
  expect_error(sc_run(object, root, context = list(species = "rat"),
    chat_fn = function(...) { calls <<- calls + 1L; stop("must never call") }), "Unsupported species")
  expect_equal(calls, 0L)
  expect_false(file.exists(file.path(root, ".sc-run", "state.rds")))
  gene_set <- sc_cycle_gene_set("Mus musculus", s_genes = paste0("S", 1:5),
    g2m_genes = paste0("G", 1:5), source = "Explicit software fixture", version = "1")
  expect_identical(gene_set$species, "mouse")
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "Homo sapiens"),
    list(gene_set = gene_set)), "species does not match")
})

test_that("CM2 reference scopes accept declared aliases and exclude unsupported organisms", {
  counts <- Matrix::Matrix(matrix(c(1, 2, 2, 1), nrow = 2,
    dimnames = list(c("GENE1", "Gene1"), c("001", "NA"))), sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  object$literal_cluster <- c("01", "01")
  markers <- data.frame(cluster = "01", gene = "GENE1")
  reference <- data.frame(cell_type = c("human short", "human formal", "mouse short", "mouse formal", "rat"),
    marker = "GENE1", species = c("human", "Homo sapiens", "mouse", "Mus musculus", "rat"), tissue = "blood")
  evidence <- function(species) scAgentKit:::.sc_run_reference_evidence(object, markers,
    list(species = species, tissue = "blood"), reference, "literal_cluster")
  human <- evidence("Homo sapiens"); mouse <- evidence("Mus musculus")
  expect_setequal(human$all_matches$cell_type, c("human short", "human formal"))
  expect_setequal(mouse$all_matches$cell_type, c("mouse short", "mouse formal"))
  expect_equal(human$provenance$scope$excluded_unavailable_rows, 1L)
  expect_identical(human$provenance$scope$species_method, "explicit_human_mouse_aliases")
  expect_error(evidence("rat"), "Unsupported species")
})
