# Shared, local-only source identity for export and review writeback.
.sc_project_fail <- function(message) stop(message, call. = FALSE)

.sc_project_string <- function(value, name, nullable = FALSE) {
  if (nullable && is.null(value)) return(invisible(NULL))
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value))
    .sc_project_fail(paste0("`", name, "` must be one nonempty string", if (nullable) " or NULL" else "", "."))
  invisible(value)
}

.sc_project_unwrap <- function(object) {
  if (inherits(object, "Seurat")) return(object)
  if (methods::is(object, "AgentSeurat")) {
    value <- object@data
    if (inherits(value, "Seurat")) return(value)
    if (is.list(value) && length(value) == 1L && inherits(value[[1L]], "Seurat"))
      return(value[[1L]])
    .sc_project_fail("AgentSeurat must wrap exactly one Seurat object; select or merge explicitly first.")
  }
  .sc_project_fail("`object` must be a Seurat object or an AgentSeurat wrapping exactly one Seurat.")
}

.sc_project_ids <- function(ids, name) {
  if (is.null(ids) || !is.character(ids) || !length(ids) || anyNA(ids) ||
      any(!nzchar(ids)) || anyDuplicated(ids))
    .sc_project_fail(paste0(name, " must be nonempty, unique, literal gene/cell IDs with no missing values."))
  invisible(ids)
}

.sc_project_json <- function(value, pretty = FALSE) {
  .sc_project_json_check(value)
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", na = "null",
                               digits = NA, pretty = pretty, force = TRUE))
}
.sc_project_json_check <- function(value) {
  keys <- names(value)
  if (!is.null(keys) && (anyNA(keys) || any(!nzchar(keys)) || anyDuplicated(keys)))
    .sc_project_fail("JSON objects require unique nonempty keys at every level.")
  if (is.list(value)) {
    for (item in value) .sc_project_json_check(item)
  } else if (is.numeric(value)) {
    available <- value[!is.na(value)]
    if (any(is.nan(value)) || any(!is.finite(available)))
      .sc_project_fail("Export JSON numeric values must be finite; actual NA may remain null.")
    if (any(abs(available) > 9007199254740991 & available == floor(available)))
      .sc_project_fail("Export JSON integers must be exactly representable (at most 2^53 - 1 in magnitude).")
  }
  invisible(TRUE)
}
.sc_project_sha_text <- function(value) digest::digest(enc2utf8(value), algo = "sha256", serialize = FALSE)
.sc_project_sha_file <- function(path) digest::digest(path, algo = "sha256", file = TRUE)
.sc_project_array <- function(value) unname(as.list(value))
.sc_project_map <- function(value = list()) {
  stats::setNames(value, if (is.null(names(value))) character() else names(value))
}

# Counts are validated before Seurat constructors can repair duplicate names.
.sc_project_matrix <- function(value, name, raw_counts = FALSE) {
  if (!(is.matrix(value) || inherits(value, "Matrix")) || length(dim(value)) != 2L)
    .sc_project_fail(paste0(name, " must be a two-dimensional numeric matrix."))
  .sc_project_ids(rownames(value), paste0(name, " feature IDs"))
  .sc_project_ids(colnames(value), paste0(name, " cell IDs"))
  values <- if (inherits(value, "sparseMatrix")) {
    if ("x" %in% methods::slotNames(value)) value@x else 1
  } else as.vector(value)
  if (!(is.numeric(values) || is.logical(values)) || any(!is.finite(values)))
    .sc_project_fail(paste0(name, " must contain finite numeric values."))
  if (raw_counts && (any(values < 0) || any(values != floor(values))))
    .sc_project_fail(paste0(name, " must contain genuine finite nonnegative integer counts; supply an existing raw counts layer."))
  # Conversion expands triangular/symmetric storage sparsely, never as a full dense assay.
  if (!inherits(value, "sparseMatrix")) value <- Matrix::Matrix(value, sparse = TRUE)
  value <- methods::as(methods::as(methods::as(value, "generalMatrix"), "CsparseMatrix"), "dMatrix")
  value <- Matrix::drop0(value)
  value[order(enc2utf8(rownames(value)), method = "radix"),
        order(enc2utf8(colnames(value)), method = "radix"), drop = FALSE]
}

.sc_project_layer <- function(object, assay, layer, raw_counts = FALSE) {
  .sc_project_string(layer, "layer")
  if (sum(names(object@assays) == assay) != 1L)
    .sc_project_fail(paste0("Assay `", assay, "` is absent or ambiguous; choose an explicit existing assay."))
  selected <- object[[assay]]
  layers <- SeuratObject::Layers(selected, search = NA)
  if (sum(layers == layer) != 1L) {
    .sc_project_fail(paste0("Exact layer `", assay, "/", layer, "` is unavailable or ambiguous. Available layers: ",
                           paste(layers, collapse = ", "), ". Join split layers explicitly with JoinLayers(), or select an exact full-cell layer; export never joins or falls back."))
  }
  if (layer %in% c("counts", "data") && any(startsWith(layers, paste0(layer, "."))))
    .sc_project_fail(paste0("Split `", assay, "/", layer, "` layers are present. JoinLayers() explicitly before export; no split-layer fallback is allowed."))
  value <- SeuratObject::LayerData(selected, layer = layer, fast = FALSE)
  .sc_project_matrix(value, paste0(assay, "/", layer), raw_counts)
}

.sc_project_sparse_hash <- function(value) {
  # R's version-2 XDR serialization supplies platform-independent IEEE doubles.
  # Only canonical CSC dimensions/pointers/indices/values enter this component.
  digest::digest(list(dim = as.integer(dim(value)), p = as.integer(value@p),
                      i = as.integer(value@i), x = as.double(value@x)),
                 algo = "sha256", serialize = TRUE, serializeVersion = 2L)
}

.sc_project_identity <- function(object, assay = "RNA", counts_layer = "counts",
                                 normalized_layer = "data", cluster_column = "seurat_clusters") {
  object <- .sc_project_unwrap(object)
  .sc_project_string(assay, "assay")
  .sc_project_string(counts_layer, "counts_layer")
  .sc_project_string(normalized_layer, "normalized_layer", nullable = TRUE)
  .sc_project_string(cluster_column, "cluster_column")
  if (counts_layer %in% c("data", "scale.data") ||
      (!is.null(normalized_layer) && identical(counts_layer, normalized_layer)))
    .sc_project_fail("Select a genuine raw counts layer, distinct from normalized data; `data` and `scale.data` cannot be used as counts.")
  cells <- colnames(object)
  .sc_project_ids(cells, "Complete object cell IDs")
  cells <- cells[order(enc2utf8(cells), method = "radix")]
  counts <- .sc_project_layer(object, assay, counts_layer, raw_counts = TRUE)
  if (!setequal(colnames(counts), cells))
    .sc_project_fail("Selected counts assay/layer must cover every colnames(object) cell exactly. Join or reconstruct a full-cell layer explicitly; subsetting the project is not permitted.")
  data <- if (is.null(normalized_layer)) NULL else .sc_project_layer(object, assay, normalized_layer)
  if (!is.null(data) && (!identical(rownames(data), rownames(counts)) || !identical(colnames(data), cells)))
    .sc_project_fail("Selected normalized layer must cover the exact same complete cells and features as counts. Choose or explicitly prepare matching layers; export never imputes or subsets.")
  metadata <- object@meta.data
  .sc_project_ids(rownames(metadata), "Metadata cell IDs")
  if (!setequal(rownames(metadata), cells)) .sc_project_fail("Metadata must cover the complete object cell universe exactly.")
  if (sum(names(metadata) == cluster_column) != 1L)
    .sc_project_fail(paste0("Cluster column `", cluster_column, "` is missing or ambiguous; supply a processed object or call sc_project_prepare() explicitly."))
  membership <- metadata[cells, cluster_column]
  if (!(is.atomic(membership) || is.factor(membership)) || anyNA(membership))
    .sc_project_fail("Cluster membership has actual missing values or is not atomic. Assign every cell explicitly; the literal string 'NA' is permitted.")
  membership <- as.character(membership)
  if (anyNA(membership) || any(!nzchar(membership))) .sc_project_fail("Cluster IDs must be nonempty literal strings with no missing membership.")
  names(membership) <- cells
  features <- rownames(counts)
  identity <- list(algorithm = "scagentkit.source.v1", assay = assay, countsLayer = counts_layer,
                   normalizedLayer = normalized_layer, clusterColumn = cluster_column,
                   cellCount = length(cells), featureCount = length(features),
                   cellsHash = .sc_project_sha_text(.sc_project_json(.sc_project_array(cells))),
                   featuresHash = .sc_project_sha_text(.sc_project_json(.sc_project_array(features))),
                   membershipHash = .sc_project_sha_text(.sc_project_json(lapply(seq_along(cells), function(i) list(cellId = cells[i], clusterId = membership[[i]])))),
                   countsHash = .sc_project_sparse_hash(counts),
                   dataHash = if (is.null(data)) NULL else .sc_project_sparse_hash(data))
  identity$fingerprint <- .sc_project_sha_text(.sc_project_json(identity))
  c(identity, list(cells = cells, features = features, membership = membership, counts = counts, data = data))
}
