# Existing feature annotations can identify mitochondrial genes without network
# lookup or guessing that an Ensembl identifier is a biological gene symbol.
.sc_run_mito_features <- function(seu, assay, features, species) {
  pattern <- if (identical(species, "human")) "^MT-" else if (identical(species, "mouse")) "^mt-" else NULL
  .sc_run_gene_family_features(seu, assay, features, species, pattern, "mitochondrial")
}

.sc_run_gene_family_features <- function(seu, assay, features, species, pattern, family) {
  result <- function(genes = character(), source = "input_symbols", reason = NULL) {
    if (!is.null(reason)) reason <- gsub("mitochondrial", family, reason, ignore.case = TRUE)
    list(features = genes, summary = list(available = length(genes) > 0L,
      feature_count = length(genes), pattern = pattern, mapping_source = source,
      unavailable_reason = reason))
  }
  if (is.null(pattern)) return(result(reason = paste(
    "Species is unspecified or unsupported; declare human/mouse with matching gene symbols,",
    "or omit percent_mt filtering. Percentage is unavailable, not zero.")))
  ensembl <- grepl("^ENS(MUS)?G[0-9]+([.][0-9]+)?$", features)
  symbols <- features
  source <- "input_symbols"
  if (any(ensembl)) {
    wrong_species <- if (species == "human") grepl("^ENSMUSG", features) else grepl("^ENSG", features)
    if (any(wrong_species)) return(result(source = "unavailable", reason = paste(
      "Ensembl identifiers conflict with the declared species; correct species or feature annotation.",
      "Mitochondrial percentage is unavailable, not zero.")))
    metadata <- seu[[assay]][[]]
    if (anyDuplicated(rownames(metadata)) || !all(features %in% rownames(metadata)))
      return(result(source = "unavailable", reason = "Feature annotations do not align exactly to count feature IDs; mitochondrial percentage is unavailable, not zero."))
    candidates <- intersect(c("sc_feature_name", "gene_symbol", "gene_name", "symbol", "SYMBOL"), names(metadata))
    mappings <- list()
    for (column in candidates) {
      values <- metadata[features, column]
      if (!(is.character(values) || is.factor(values))) next
      values <- as.character(values)
      # Partial or identity ENSG-to-ENSG annotations do not establish symbols.
      if (anyNA(values[ensembl]) || any(!nzchar(trimws(values[ensembl]))) ||
          any(grepl("^ENS(MUS)?G[0-9]", values[ensembl]))) next
      mapped <- features; mapped[ensembl] <- values[ensembl]
      mappings[[column]] <- mapped
    }
    if (!length(mappings)) return(result(source = "unavailable", reason = paste(
      "Ensembl feature IDs need an existing aligned gene-symbol annotation (sc_feature_name, gene_symbol, gene_name, symbol or SYMBOL).",
      "Add that annotation and restart in a new project; mitochondrial percentage is unavailable, not zero.")))
    matched <- lapply(mappings, function(values) grepl(pattern, values))
    if (any(!vapply(matched, identical, logical(1), matched[[1L]])))
      return(result(source = "ambiguous_annotations", reason = paste(
        "Existing gene-symbol columns disagree about mitochondrial features; resolve their annotations before filtering.",
        "Mitochondrial percentage is unavailable, not zero.")))
    source <- paste0("feature_metadata:", names(mappings)[[1L]])
    symbols <- mappings[[1L]]
  }
  genes <- features[grepl(pattern, symbols)]
  result(genes, source, if (!length(genes)) paste(
    "No mitochondrial genes match the declared species symbol convention in the existing annotation;",
    "percentage is unavailable, not zero.") else NULL)
}
