#' Explicitly prepare a copy for project export
#'
#' Runs standard analysis only when requested, retains every cell, and records
#' both requested and effective settings. Matrix IDs and genuine counts are
#' checked before any Seurat constructor can repair feature names.
#' @param object Seurat, a single-object AgentSeurat, or a named counts matrix.
#' @param assay,counts_layer Explicit assay and genuine raw counts layer.
#' @param cluster_column Column for computed cluster membership.
#' @param normalization_method,scale_factor Normalization settings.
#' @param nfeatures,npcs Requested variable features and principal components.
#' @param dims Prepared components used for neighbors and UMAP, or NULL.
#' @param resolution Clustering resolution.
#' @param seed Random seed.
#' @param run_umap Whether to compute a UMAP reduction.
#' @param umap_neighbors Requested UMAP neighbors.
#' @return A prepared copy in the input object family; matrix input returns Seurat.
#' @export
sc_project_prepare <- function(object, assay = "RNA", counts_layer = "counts",
                               cluster_column = "seurat_clusters",
                               normalization_method = "LogNormalize", scale_factor = 10000,
                               nfeatures = 2000, npcs = 30, dims = NULL,
                               resolution = 0.5, seed = 1, run_umap = TRUE,
                               umap_neighbors = 30) {
  .sc_project_string(assay, "assay")
  .sc_project_string(counts_layer, "counts_layer")
  .sc_project_string(cluster_column, "cluster_column")
  .sc_project_string(normalization_method, "normalization_method")
  if (!normalization_method %in% c("LogNormalize", "RC"))
    .sc_project_fail("Project preparation supports explicit LogNormalize or RC; other methods require explicit external preparation.")
  if (counts_layer %in% c("data", "scale.data")) .sc_project_fail("Preparation requires genuine raw counts; data and scale.data are not counts layers.")
  positive <- function(value, name, integer = FALSE) {
    if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value <= 0 ||
        (integer && (value != floor(value) || value > .Machine$integer.max)))
      .sc_project_fail(paste0("`", name, "` must be one positive ", if (integer) "integer" else "number", "."))
    invisible(value)
  }
  positive(scale_factor, "scale_factor")
  positive(nfeatures, "nfeatures", TRUE)
  positive(npcs, "npcs", TRUE)
  positive(resolution, "resolution")
  positive(umap_neighbors, "umap_neighbors", TRUE)
  if (!is.numeric(seed) || length(seed) != 1L || !is.finite(seed) || seed != floor(seed) || seed < 0 || seed > .Machine$integer.max)
    .sc_project_fail("`seed` must be one nonnegative integer.")
  if (!is.logical(run_umap) || length(run_umap) != 1L || is.na(run_umap)) .sc_project_fail("`run_umap` must be TRUE or FALSE.")
  matrix_input <- is.matrix(object) || inherits(object, "Matrix")
  if (matrix_input) {
    .sc_project_matrix(object, "Input counts matrix", raw_counts = TRUE)
    if (counts_layer != "counts") .sc_project_fail("A matrix input creates the explicit standard counts layer; use counts_layer='counts'.")
    if (any(grepl("[_|]", rownames(object))))
      .sc_project_fail("Seurat would rename feature IDs containing '_' or '|'. Rename them explicitly before preparation so literal source IDs are reviewable.")
    seu <- Seurat::CreateSeuratObject(counts = object, assay = assay, min.cells = 0, min.features = 0)
  } else seu <- .sc_project_unwrap(object)
  cells <- colnames(seu)
  .sc_project_ids(cells, "Complete object cell IDs")
  counts <- .sc_project_layer(seu, assay, counts_layer, raw_counts = TRUE)
  if (!setequal(colnames(counts), cells)) .sc_project_fail("Preparation requires the selected counts layer to cover every object cell exactly; join or reconstruct it explicitly first.")
  if (ncol(counts) < 3L || nrow(counts) < 3L) .sc_project_fail("Standard PCA/neighbors preparation requires at least three cells and three features; export an already processed object instead.")
  requested <- list(assay = assay, counts_layer = counts_layer, cluster_column = cluster_column,
                    normalization_method = normalization_method, scale_factor = scale_factor,
                    nfeatures = as.integer(nfeatures), npcs = as.integer(npcs),
                    dims = if (is.null(dims)) NULL else .sc_project_array(dims), resolution = resolution,
                    seed = as.integer(seed), run_umap = run_umap, umap_neighbors = as.integer(umap_neighbors),
                    qc_filter = "none", cells_removed = 0L)
  if (!is.null(dims) && (!is.numeric(dims) || !length(dims) || any(!is.finite(dims)) || any(dims < 1L) || any(dims != floor(dims)) || anyDuplicated(dims)))
    .sc_project_fail("`dims` must be distinct positive integer component indices or NULL.")
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv, inherits = FALSE) else NULL
  on.exit(if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv) else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
  set.seed(as.integer(seed))
  # Normalize the explicitly selected matrix so Seurat's layer search cannot
  # silently consume another counts layer. Other assays/counts remain on the copy.
  normalized <- Seurat::NormalizeData(counts, normalization.method = normalization_method,
                                      scale.factor = scale_factor, verbose = FALSE)
  SeuratObject::LayerData(seu, assay = assay, layer = "data") <- normalized
  feature_assay <- SeuratObject::CreateAssayObject(counts = counts, min.cells = 0, min.features = 0)
  feature_assay <- Seurat::FindVariableFeatures(feature_assay, selection.method = "vst",
                                               nfeatures = min(as.integer(nfeatures), nrow(counts)), verbose = FALSE)
  features <- SeuratObject::VariableFeatures(feature_assay)
  if (length(features) < 3L) .sc_project_fail("Fewer than three variable features are available; prepare a suitable feature set explicitly before export.")
  SeuratObject::VariableFeatures(seu[[assay]]) <- features
  seu <- Seurat::ScaleData(seu, assay = assay, features = features, verbose = FALSE)
  effective_npcs <- min(as.integer(npcs), length(features) - 1L, ncol(counts) - 1L)
  seu <- Seurat::RunPCA(seu, assay = assay, features = features, npcs = effective_npcs,
                        seed.use = as.integer(seed), verbose = FALSE)
  available <- ncol(SeuratObject::Embeddings(seu[["pca"]]))
  dims_use <- if (is.null(dims)) seq_len(available) else as.integer(dims)
  if (any(dims_use > available)) .sc_project_fail("Requested PCA dimensions exceed the computed components; reduce dims/npcs or supply more cells and variable features.")
  graph_names <- paste0(assay, c("_nn", "_snn"))
  seu <- Seurat::FindNeighbors(seu, reduction = "pca", dims = dims_use,
                               k.param = min(20L, ncol(counts) - 1L), graph.name = graph_names, verbose = FALSE)
  # FindClusters writes seurat_clusters internally; preserve a pre-existing
  # column when a distinct output column was explicitly selected.
  previous_clusters <- seu@meta.data$seurat_clusters
  seu <- Seurat::FindClusters(seu, graph.name = graph_names[2L], resolution = resolution,
                              random.seed = as.integer(seed), verbose = FALSE)
  membership <- as.character(seu@meta.data$seurat_clusters)
  seu[[cluster_column]] <- membership
  if (cluster_column != "seurat_clusters") {
    if (is.null(previous_clusters)) seu$seurat_clusters <- NULL else seu$seurat_clusters <- previous_clusters
  }
  effective_neighbors <- min(as.integer(umap_neighbors), ncol(counts) - 1L)
  if (run_umap) seu <- Seurat::RunUMAP(seu, reduction = "pca", dims = dims_use,
                                      n.neighbors = effective_neighbors, seed.use = as.integer(seed), verbose = FALSE)
  if (!identical(colnames(seu), cells)) .sc_project_fail("Preparation unexpectedly changed the cell universe; no result was returned.")
  requested$effective <- list(nfeatures = length(features), npcs = available, dims = .sc_project_array(dims_use),
                              umap_neighbors = if (run_umap) effective_neighbors else NULL, cell_count = length(cells))
  seu@misc$sc_project_prepare <- requested
  if (!matrix_input && methods::is(object, "AgentSeurat")) {
    output <- object
    if (is.list(output@data) && !inherits(output@data, "Seurat")) output@data[[1L]] <- seu else output@data <- seu
    output@params$project_prepare <- requested
    return(output)
  }
  seu
}
