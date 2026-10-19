# Join only explicitly validated partitions of one selected assay. Export and
# checkpoint readers retain their strict exact-layer contract.
.sc_run_join_input_layers <- function(seu, assay, counts_layer, normalized_layer) {
  if (sum(names(seu@assays) == assay) != 1L) return(list(seu = seu, receipts = list()))
  receipts <- list()
  prefixes <- unique(c(counts_layer, normalized_layer))
  for (prefix in prefixes) {
    layers <- SeuratObject::Layers(seu[[assay]], search = NA)
    parts <- layers[startsWith(layers, paste0(prefix, "."))]
    if (!length(parts)) next
    if (prefix %in% layers)
      stop("Exact and split ", assay, "/", prefix, " layers coexist; choose or reconstruct one unambiguous source before starting.", call. = FALSE)
    if (!prefix %in% c("counts", "data"))
      stop("Custom split layers need an explicit JoinLayers() preparation before starting.", call. = FALSE)
    matrices <- lapply(parts, function(layer) .sc_project_matrix(
      SeuratObject::LayerData(seu[[assay]], layer = layer, fast = FALSE),
      paste0(assay, "/", layer), raw_counts = identical(prefix, counts_layer)))
    features <- rownames(matrices[[1L]])
    if (any(!vapply(matrices, function(value) identical(rownames(value), features), logical(1))))
      stop("Split ", assay, "/", prefix, " layers have different feature sets; automatic joining cannot invent unmeasured genes or discard features.", call. = FALSE)
    cells <- unlist(lapply(matrices, colnames), use.names = FALSE)
    if (anyDuplicated(cells) || !setequal(cells, colnames(seu)))
      stop("Split ", assay, "/", prefix, " layers must cover every object cell exactly once with no overlap; repair the layer coverage before starting.", call. = FALSE)
    hashes <- vapply(matrices, .sc_project_sparse_hash, character(1))
    joined <- SeuratObject::JoinLayers(seu[[assay]], layers = prefix, new = prefix)
    value <- .sc_project_matrix(SeuratObject::LayerData(joined, layer = prefix, fast = FALSE),
      paste0(assay, "/", prefix), raw_counts = identical(prefix, counts_layer))
    if (!identical(rownames(value), features) || !setequal(colnames(value), colnames(seu)))
      stop("Joined layer feature/cell coverage changed; input was not accepted.", call. = FALSE)
    for (i in seq_along(matrices)) if (!identical(hashes[[i]], .sc_project_sparse_hash(
        value[features, colnames(matrices[[i]]), drop = FALSE])))
      stop("JoinLayers changed source values; input was not accepted.", call. = FALSE)
    seu[[assay]] <- joined
    receipts[[length(receipts) + 1L]] <- list(schema = "scagentkit.layer-join.v1",
      operation = "SeuratObject::JoinLayers", assay = assay, target_layer = prefix,
      source_layers = parts, source_sha256 = unname(hashes),
      source_cells = vapply(matrices, ncol, integer(1)),
      cells = ncol(value), features = nrow(value), joined_sha256 = .sc_project_sparse_hash(value),
      exact_value_and_coverage_check = TRUE)
  }
  if (length(receipts)) {
    key <- tail(make.unique(c(names(seu@misc), "scagentkit_layer_joins")), 1L)
    seu@misc[[key]] <- receipts
  }
  list(seu = seu, receipts = receipts)
}
