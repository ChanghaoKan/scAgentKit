# These adapter tests deliberately scramble child cell/cluster order. Parent
# cluster labels and row positions are never an annotation join key.
subcluster_copy_fixture <- function() {
  cells <- c("001", "1", "NA", "cell space", "outside", "last")
  counts <- Matrix::Matrix(matrix(seq_len(48L) %% 7L, nrow = 8L,
    dimnames = list(paste0("ScopeGene", 1:8), cells)), sparse = TRUE)
  parent <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  parent$parent_cluster <- factor(c("01", "01", "1", "NA", "1", "NA"),
    levels = c("NA", "1", "01", "unused"))
  parent$prior_identity <- factor(c("prior", NA, "prior", "prior", NA, "prior"),
    levels = c("unused", "prior"))
  parent$technical_batch <- c("a", "b", "a", "b", "a", "b")
  selected <- cells[1:4]
  shuffled <- selected[c(4L, 2L, 1L, 3L)]
  child <- Seurat::CreateSeuratObject(counts[, shuffled, drop = FALSE],
    min.cells = 0, min.features = 0)
  child$child_cluster <- c("0", "1", "1", "0")
  labels <- stats::setNames(c("first literal", "second literal", "Unknown", "space literal"), selected)
  child$child_label <- unname(labels[shuffled])
  child$child_label_confidence <- c("low", "high", "medium", "low")
  child$child_label_rationale <- paste("Explicit child evidence for", shuffled)
  list(parent = parent, child = child, selected = selected, labels = labels)
}

subcluster_copy <- function(fixture, child = fixture$child, expected = fixture$selected,
                            column = "reviewed_subtype") {
  scAgentKit:::.sc_run_subcluster_copy(fixture$parent, child, expected, column,
    "child-literal-scope", "child_cluster", "child_label")
}

test_that("subtype adapter joins literal cell IDs after child reordering and preserves parent", {
  fixture <- subcluster_copy_fixture()
  original <- serialize(fixture$parent, NULL, version = 2L)
  result <- subcluster_copy(fixture)
  object <- result$seu
  expect_s4_class(object, "Seurat")
  expect_identical(serialize(fixture$parent, NULL, version = 2L), original)
  expect_identical(colnames(object), colnames(fixture$parent))
  expect_identical(rownames(object), rownames(fixture$parent))
  expect_identical(SeuratObject::LayerData(object, assay = "RNA", layer = "counts"),
    SeuratObject::LayerData(fixture$parent, assay = "RNA", layer = "counts"))
  expect_true(inherits(SeuratObject::LayerData(object, assay = "RNA", layer = "counts"), "sparseMatrix"))
  for (name in names(fixture$parent[[]]))
    expect_identical(object[[]][[name]], fixture$parent[[]][[name]])
  expect_identical(unname(object[[]][fixture$selected, "reviewed_subtype"]),
    unname(fixture$labels[fixture$selected]))
  expect_true(all(is.na(object[[]][setdiff(colnames(object), fixture$selected), "reviewed_subtype"])))
  expect_identical(unname(object[[]]["001", "reviewed_subtype"]), "first literal")
  expect_identical(unname(object[[]]["1", "reviewed_subtype"]), "second literal")
  expect_identical(unname(object[[]]["NA", "reviewed_subtype"]), "Unknown")
  for (field in c("confidence", "rationale")) {
    source <- paste0("child_label_", field)
    expect_identical(unname(object[[]][fixture$selected, paste0("reviewed_subtype_", field)]),
      unname(fixture$child[[]][fixture$selected, source]))
  }
  expect_identical(unname(object[[]][fixture$selected, "reviewed_subtype_child_cluster"]),
    unname(fixture$child[[]][fixture$selected, "child_cluster"]))
  expect_true(all(object[[]][fixture$selected, "reviewed_subtype_source_child"] == "child-literal-scope"))
  expect_false(identical(as.character(object$parent_cluster[1:4]), object$reviewed_subtype[1:4]))
  expect_true(all(result$fields %in% names(object[[]])))
})

test_that("subtype adapter rejects missing foreign duplicated and renamed literal IDs", {
  fixture <- subcluster_copy_fixture()
  original <- serialize(fixture$parent, NULL, version = 2L)
  expect_error(subcluster_copy(fixture, child = fixture$child[, -1L]), "cell|scope|ID")
  expect_error(subcluster_copy(fixture, expected = c(fixture$selected, fixture$selected[1L])), "unique|duplicat|ID")
  expect_error(subcluster_copy(fixture, expected = c(fixture$selected[-1L], "foreign")), "cell|scope|ID")
  changed <- fixture$child
  colnames(changed) <- paste0(colnames(changed), "_1")
  expect_error(subcluster_copy(fixture, child = changed), "cell|scope|ID")
  # A malformed object bypasses constructors only to exercise failclosed ID
  # validation; it is never used for scientific computation.
  changed <- fixture$child
  attr(changed@meta.data, "row.names") <- rep("duplicate", ncol(changed))
  expect_error(subcluster_copy(fixture, child = changed), "cell|scope|ID|unique|duplicat")
  expect_identical(serialize(fixture$parent, NULL, version = 2L), original)
})

test_that("subtype adapter rejects existing targets companions and unreviewed labels atomically", {
  fixture <- subcluster_copy_fixture()
  for (column in c("reviewed_subtype", "reviewed_subtype_confidence", "reviewed_subtype_rationale",
                   "reviewed_subtype_source_child", "reviewed_subtype_child_cluster")) {
    conflict <- fixture
    conflict$parent[[column]] <- "prior value"
    before <- serialize(conflict$parent, NULL, version = 2L)
    expect_error(subcluster_copy(conflict), "column|exist|conflict")
    expect_identical(serialize(conflict$parent, NULL, version = 2L), before)
  }
  for (column in c("child_label", "child_label_confidence", "child_label_rationale", "child_cluster")) {
    child <- fixture$child
    child[[column]] <- NULL
    expect_error(subcluster_copy(fixture, child = child), "column|label|annotation|cluster|missing|absent")
  }
  child <- fixture$child
  child$child_label[1L] <- NA_character_
  expect_error(subcluster_copy(fixture, child = child), "label|annotation|missing|NA|complete")
})
