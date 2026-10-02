make_annot_replay_fixture <- function() {
  counts <- Matrix::Matrix(matrix(
    c(2, 1, 3, 0, 1, 2, 0, 3), nrow = 2,
    dimnames = list(c("G1", "G2"), paste0("C", 1:4))
  ), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts = counts)
  odd_cluster <- '1"; sentinel <- TRUE; #\n`cluster`\\tail'
  seu$seurat_clusters <- c("0", "0", odd_cluster, "unmapped")
  obj <- AgentSeurat(seu)
  obj@params$llm_annotations <- data.frame(
    cluster = c("0", odd_cluster),
    primary_annotation = c('T"; sentinel <- TRUE; #\n`cell`\\tail',
                           "Rare 'cells'\nwith `backticks`"),
    recommended_action = c("accept", "reject"),
    stringsAsFactors = FALSE
  )
  obj
}

replay_annot_script <- function(input, output) {
  replay <- new.env(parent = globalenv())
  replay$sentinel <- FALSE
  replay$seurat_obj <- input@data
  script <- tail(output@scripts, 1)
  expect_silent(code <- parse(text = script))
  # The sentinel assignment appears only inside data strings. Evaluate
  # the fixed trace, never the old unsafe trace or standalone label text.
  expect_silent(eval(code, envir = replay))
  expect_identical(replay$sentinel, FALSE)
  replay
}

test_that("LLM labels, cluster IDs, and unusual column names replay as data", {
  input <- make_annot_replay_fixture()
  column <- 'cell type"; sentinel <- TRUE; #\n`label`'
  out <- annot_apply(input, column_name = column)
  replay <- replay_annot_script(input, out)
  expect_identical(colnames(replay$seurat_obj), colnames(out@data))
  expect_identical(replay$seurat_obj@meta.data[[column]], out@data@meta.data[[column]])
  expect_identical(out@data@meta.data[[column]][4], "Unannotated")
  expect_identical(out@decisions[[1]]$params$annotation_mapping,
                   stats::setNames(input@params$llm_annotations$primary_annotation,
                                   input@params$llm_annotations$cluster))
})

test_that("rejected cluster literals replay safely through cell-ID subsetting", {
  input <- make_annot_replay_fixture()
  out <- annot_apply(input, drop_rejected = TRUE)
  replay <- replay_annot_script(input, out)
  expect_identical(colnames(out@data), c("C1", "C2", "C4"))
  expect_identical(colnames(replay$seurat_obj), colnames(out@data))
  expect_identical(replay$seurat_obj@meta.data$cell_type, out@data@meta.data$cell_type)
  expect_identical(replay$rejected_clusters, input@params$llm_annotations$cluster[2])
})

test_that("manual mapping literals and overrides replay without executing text", {
  input <- make_annot_replay_fixture()
  overrides <- stats::setNames(
    c('"; sentinel <- TRUE; #\nmanual `cell`', "Override 'rare' cells"),
    input@params$llm_annotations$cluster
  )
  for (source in c("manual", "llm")) {
    out <- annot_apply(input, source = source, manual_overrides = overrides,
                       drop_rejected = TRUE)
    replay <- replay_annot_script(input, out)
    expect_identical(colnames(replay$seurat_obj), colnames(out@data))
    expect_identical(replay$seurat_obj@meta.data$cell_type, out@data@meta.data$cell_type)
    expect_length(out@decisions[[1]]$params$rejected_clusters, 0)
    expect_identical(colnames(out@data), paste0("C", 1:4))
  }
})

test_that("replay verifies input cell IDs before updating or subsetting", {
  input <- make_annot_replay_fixture()
  out <- annot_apply(input, drop_rejected = TRUE)
  replay <- new.env(parent = globalenv())
  replay$sentinel <- FALSE
  replay$seurat_obj <- input@data[, 1:3]
  before <- replay$seurat_obj
  expect_error(eval(parse(text = tail(out@scripts, 1)), envir = replay),
               "Replay input cell IDs differ")
  expect_identical(replay$seurat_obj, before)
  expect_identical(replay$sentinel, FALSE)
})

test_that("changed per-cell clusters stop replay before any metadata change or deletion", {
  input <- make_annot_replay_fixture()
  overrides <- stats::setNames(c("T cell", "Rare cell"),
                               input@params$llm_annotations$cluster)
  for (source in c("llm", "manual")) {
    out <- annot_apply(input, source = source,
                       manual_overrides = if (source == "manual") overrides else NULL,
                       drop_rejected = TRUE)
    replay <- new.env(parent = globalenv())
    replay$seurat_obj <- input@data
    clusters <- as.character(input@data$seurat_clusters)
    replay$seurat_obj$seurat_clusters <- clusters[c(3, 4, 1, 2)]
    before <- replay$seurat_obj
    expect_error(eval(parse(text = tail(out@scripts, 1)), envir = replay),
                 "Replay input cluster assignments differ")
    expect_identical(replay$seurat_obj, before)
    expect_false(exists("cell_type_map", envir = replay, inherits = FALSE))
  }
})

test_that("cluster snapshots are matched by cell ID and permit input reordering", {
  input <- make_annot_replay_fixture()
  out <- annot_apply(input, drop_rejected = TRUE)
  reordered <- input
  cell_order <- c("C4", "C2", "C1", "C3")
  reordered@data <- Seurat::CreateSeuratObject(
    counts = SeuratObject::LayerData(input@data, layer = "counts")[, cell_order],
    meta.data = input@data@meta.data[cell_order, , drop = FALSE]
  )
  expect_identical(colnames(reordered@data), cell_order)
  replay <- replay_annot_script(reordered, out)
  expect_setequal(colnames(replay$seurat_obj), colnames(out@data))
  expect_identical(
    replay$seurat_obj@meta.data[colnames(out@data), "cell_type"],
    out@data@meta.data$cell_type
  )
  expect_identical(colnames(replay$seurat_obj), c("C4", "C2", "C1"))
})
