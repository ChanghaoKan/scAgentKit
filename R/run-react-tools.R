# Read-only annotation evidence tools. Only the dispatcher writes cache records;
# no tool changes a scientific checkpoint, metadata, proposal or approval.
.sc_run_react_tools <- function() {
  text <- list(type = "string", minLength = 1L, maxLength = 128L)
  offset <- list(type = "integer", minimum = 0L, maximum = 1000000L, default = 0L)
  genes <- list(type = "array", minItems = 1L, maxItems = 20L,
    uniqueItems = TRUE, items = text)
  definition <- function(name, properties, required, execute, limit) list(name = name,
    schema_version = "scagentkit.react-tools.v2", parameters = list(type = "object",
      properties = properties, required = as.list(required), additionalProperties = FALSE),
    max_argument_bytes = 8192L, max_result_bytes = limit, timeout_seconds = 60,
    execute = execute)
  list(cluster_markers = definition("cluster_markers", list(cluster_id = text, offset = offset,
      n = list(type = "integer", minimum = 1L, maximum = 50L, default = 30L)),
      "cluster_id", .sc_run_react_cluster_markers, 32768L),
    gene_expression = definition("gene_expression", list(cluster_id = text, genes = genes),
      c("cluster_id", "genes"), .sc_run_react_gene_expression, 16384L),
    act_lookup = definition("act_lookup", list(genes = genes, offset = offset, n = list(type="integer", minimum=1L, maximum=100L, default=100L)), "genes", .sc_run_react_act_lookup, 32768L),
    cluster_context = definition("cluster_context", list(cluster_id = text),
      "cluster_id", .sc_run_react_cluster_context, 16384L))
}

.sc_run_react_error <- function(code, message) {
  stop(structure(list(message = message, call = NULL, code = code),
    class = c("sc_run_react_error", "error", "condition")))
}

.sc_run_react_arguments <- function(definition, value) {
  bad <- function() .sc_run_react_error("invalid_arguments", "Arguments do not match this tool's strict schema.")
  if (!is.list(value) || is.object(value) || is.null(names(value)) ||
      anyNA(names(value)) || anyDuplicated(names(value)) || any(!nzchar(names(value))) ||
      as.numeric(utils::object.size(value)) > 65536) bad()
  schema <- definition$parameters
  if (length(setdiff(names(value), names(schema$properties))) ||
      length(setdiff(unlist(schema$required), names(value)))) bad()
  scalar_text <- function(x, spec) is.character(x) && !is.object(x) && length(x) == 1L &&
    is.null(names(x)) && !is.na(x) && nzchar(trimws(x)) &&
    nchar(enc2utf8(x), type = "bytes") <= spec$maxLength && !grepl("[[:cntrl:]]", x)
  out <- list()
  for (key in names(schema$properties)) {
    spec <- schema$properties[[key]]; item <- value[[key]]
    if (is.null(item)) {
      if (key %in% names(value)) bad()
      if (is.null(spec$default)) next
      item <- spec$default
    }
    if (identical(spec$type, "string")) {
      if (!scalar_text(item, spec)) bad()
    } else if (identical(spec$type, "integer")) {
      if (!is.numeric(item) || is.object(item) || length(item) != 1L ||
          !is.null(names(item)) || !is.finite(item) || item != floor(item) ||
          item < spec$minimum || item > spec$maximum) bad()
      item <- as.integer(item)
    } else if (identical(spec$type, "array")) {
      if ((!is.character(item) && !is.list(item)) || is.object(item) ||
          !is.null(names(item)) || length(item) < spec$minItems || length(item) > spec$maxItems ||
          !all(vapply(as.list(item), scalar_text, logical(1), spec$items))) bad()
      item <- unlist(item, use.names = FALSE)
      if (anyDuplicated(item)) bad()
      item <- as.list(sort(item, method = "radix"))
    } else bad()
    out[[key]] <- item
  }
  if (nchar(.sc_project_json(out), type = "bytes") > definition$max_argument_bytes) bad()
  out
}

.sc_run_react_read <- function(context, name) {
  if (is.environment(context$objects) && environmentIsLocked(context$objects)) {
    if (!exists(name, context$objects, inherits = FALSE)) return(NULL)
    return(get(name, context$objects, inherits = FALSE))
  }
  record <- context$binding$files[[name]]
  if (is.null(record)) return(NULL)
  readRDS(file.path(context$root, record$path))
}

.sc_run_react_cluster <- function(context, cluster) {
  if (!cluster %in% context$clusters)
    .sc_run_react_error("unknown_cluster", "The requested cluster is absent from the bound analysis.")
  invisible(cluster)
}

.sc_run_react_cluster_markers <- function(context, arguments) {
  .sc_run_react_cluster(context, arguments$cluster_id)
  saved <- .sc_run_react_read(context, "markers"); table <- saved$markers
  required <- c("cluster", "gene", "avg_log2FC", "pct.1", "pct.2", "p_val_adj")
  if (!is.data.frame(table) || anyDuplicated(names(table)) || !all(required %in% names(table)))
    .sc_run_react_error("invalid_evidence", "The bound marker table is unavailable or invalid.")
  table <- table[as.character(table$cluster) == arguments$cluster_id, required, drop = FALSE]
  if (anyNA(table) || any(!nzchar(as.character(table$gene))) || anyDuplicated(table$gene) ||
      !all(vapply(table[c("avg_log2FC", "pct.1", "pct.2", "p_val_adj")],
        function(x) is.numeric(x) && all(is.finite(x)), logical(1))) ||
      any(table$pct.1 < 0 | table$pct.1 > 1 | table$pct.2 < 0 | table$pct.2 > 1 |
        table$p_val_adj < 0 | table$p_val_adj > 1))
    .sc_run_react_error("invalid_evidence", "The bound marker statistics are invalid.")
  parameters <- saved$parameters
  excluded <- unique(c(parameters$exclude_genes,
    unlist(attr(saved$marker_summary, "marker_pool")$exclusions$excluded_genes, use.names = FALSE)))
  if (isTRUE(parameters$exclude_shared)) excluded <- unique(c(excluded,
    as.character(table$gene[grepl("^(RPL[0-9]+[A-Z]?|RPS[0-9]+[A-Z]?|RPLP[0-2]|RPSA)$|^MT[-.]",
      table$gene, ignore.case = TRUE)])))
  table <- table[order(-table$avg_log2FC, -(table$pct.1 - table$pct.2),
    as.character(table$gene), method = "radix"), , drop = FALSE]
  total <- nrow(table); offset <- if (is.null(arguments$offset)) 0L else arguments$offset
  table <- utils::head(table[seq_len(total) > offset, , drop=FALSE], arguments$n)
  rows <- lapply(seq_len(nrow(table)), function(i) {
    row <- table[i, , drop = FALSE]; exclude <- as.character(row$gene) %in% excluded
    list(gene = as.character(row$gene), avg_log2FC = unname(row$avg_log2FC),
      pct1 = unname(row$pct.1), pct2 = unname(row$pct.2), padj = unname(row$p_val_adj),
      excluded = exclude, support_eligible = !exclude && row$p_val_adj < .05 &&
        row$avg_log2FC > 0 && row$pct.1 > row$pct.2)
  })
  list(status = "available", cluster_id = arguments$cluster_id,
    source = "saved_FindAllMarkers", comparison = "cluster_vs_all_other_cells",
    rows_available = total, returned = length(rows), offset = offset,
    next_offset = if (offset + length(rows) < total) offset + length(rows) else NULL,
    truncated = offset > 0L || total > length(rows), markers = rows,
    interpretation = "Saved test results only; eligibility is a statistical citation rule, not a validated cell-type assignment. Missing rows do not establish absent expression.")
}

.sc_run_react_gene_expression <- function(context, arguments) {
  .sc_run_react_cluster(context, arguments$cluster_id)
  seu <- .sc_run_react_read(context, "analysis"); cfg <- context$config
  counts <- .sc_project_layer(seu, cfg$assay, cfg$counts_layer, raw_counts = TRUE)
  data <- .sc_project_layer(seu, cfg$assay, cfg$normalized_layer)
  cells <- colnames(seu); metadata <- seu[[]]
  if (!setequal(colnames(counts), cells) || !setequal(colnames(data), cells) ||
      !setequal(rownames(counts), rownames(data)) || !setequal(rownames(metadata), cells))
    .sc_run_react_error("invalid_evidence", "Expression layers do not match the bound cell and feature scope.")
  membership <- as.character(metadata[cells, cfg$cluster_column])
  inside <- cells[membership == arguments$cluster_id]; outside <- cells[membership != arguments$cluster_id]
  genes <- unlist(arguments$genes, use.names = FALSE); present <- intersect(genes, rownames(counts))
  mean_in <- mean_out <- pct_in <- pct_out <- numeric()
  if (length(present)) {
    mean_in <- Matrix::rowMeans(data[present, inside, drop = FALSE])
    pct_in <- Matrix::rowMeans(counts[present, inside, drop = FALSE] > 0)
    if (length(outside)) {
      mean_out <- Matrix::rowMeans(data[present, outside, drop = FALSE])
      pct_out <- Matrix::rowMeans(counts[present, outside, drop = FALSE] > 0)
    }
  }
  list(status = "available", cluster_id = arguments$cluster_id,
    test_status = "not_tested", support_eligible = FALSE,
    mean_definition = "Arithmetic mean of the saved normalized data layer; no fold change or differential-expression test is computed.",
    detection_definition = "Fraction with positive raw counts; outside means all other bound analysis cells.",
    genes = lapply(genes, function(gene) {
      if (!gene %in% present) return(list(gene = gene, status = "missing", test_status = "not_tested"))
      list(gene = gene, status = "measured", test_status = "not_tested",
        mean_inside = unname(mean_in[gene]), detection_inside = unname(pct_in[gene]),
        outside_status = if (length(outside)) "available" else "unavailable",
        mean_outside = if (length(outside)) unname(mean_out[gene]) else NULL,
        detection_outside = if (length(outside)) unname(pct_out[gene]) else NULL)
    }))
}

.sc_run_react_act_lookup <- function(context, arguments) {
  reference <- .sc_run_react_read(context, "reference")
  unavailable <- function(reason) list(status = "unavailable", reason = reason, entries = list())
  if (is.null(reference)) return(unavailable("ACT was not configured in the bound project."))
  if (!is.data.frame(reference) || !identical(attr(reference, "reference_source"), "ACT") ||
      !all(c("species", "tissue", "cell_type", "marker") %in% names(reference)))
    return(unavailable("The bound reference is not an identified ACT snapshot."))
  species <- .sc_run_species(context$config$context$species, allow_missing = TRUE)
  tissue <- context$config$reference_review$tissue
  if (is.null(tissue)) tissue <- context$config$context$tissue
  if (is.null(species) || !is.character(tissue) || length(tissue) != 1L ||
      is.na(tissue) || !nzchar(trimws(tissue)) || tolower(trimws(tissue)) == "all")
    return(unavailable("ACT requires an explicit supported species and exact tissue."))
  keep <- !is.na(reference$species) & !is.na(reference$tissue) &
    .sc_run_species_values(reference$species) == species &
    tolower(trimws(reference$tissue)) == tolower(trimws(tissue)) &
    reference$marker %in% unlist(arguments$genes, use.names = FALSE)
  selected <- reference[which(keep), , drop = FALSE]
  selected <- selected[order(as.character(selected$marker), as.character(selected$cell_type),
    method = "radix"), , drop = FALSE]
  total <- nrow(selected); offset <- if (is.null(arguments$offset)) 0L else arguments$offset
  n <- if (is.null(arguments$n)) 100L else arguments$n
  selected <- utils::head(selected[seq_len(total) > offset, , drop=FALSE], n)
  text <- function(x) if (is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)) x else "unknown"
  version <- text(attr(reference, "source_version"))
  list(status = if (total) "matched" else "zero_matches", source = "ACT",
    snapshot_version = version, species = species, tissue = trimws(tissue),
    rows_available = total, returned = nrow(selected), offset = offset,
    next_offset = if (offset + nrow(selected) < total) offset + nrow(selected) else NULL,
    truncated = offset > 0L || total > nrow(selected),
    entries = lapply(seq_len(nrow(selected)), function(i) list(gene = as.character(selected$marker[i]),
      cell_type = as.character(selected$cell_type[i]), species = species, tissue = trimws(tissue),
      pmid = if ("pmid" %in% names(selected)) text(as.character(selected$pmid[i])) else "unknown",
      snapshot_version = version)),
    interpretation = "Exact declared species and tissue only. ACT overlap is background reference evidence, not independent proof or a differential-expression test.")
}

.sc_run_react_distribution <- function(value) {
  if (!is.numeric(value) || !length(value)) return(list(status = "unavailable", measured_cells = 0L, median = NULL))
  finite <- is.finite(value)
  list(status = if (!any(finite)) "unavailable" else if (all(finite)) "available" else "partial",
    measured_cells = sum(finite), missing_cells = sum(!finite),
    median = if (any(finite)) unname(stats::median(value[finite])) else NULL)
}

.sc_run_react_cluster_context <- function(context, arguments) {
  .sc_run_react_cluster(context, arguments$cluster_id)
  seu <- .sc_run_react_read(context, "analysis"); metadata <- seu[[]]; cfg <- context$config
  cells <- colnames(seu); metadata <- metadata[cells, , drop = FALSE]
  inside <- which(as.character(metadata[[cfg$cluster_column]]) == arguments$cluster_id)
  values <- function(column) if (!is.null(column) && column %in% names(metadata)) metadata[[column]][inside] else NULL
  qc <- list(source = "saved_analysis_metadata",
    interpretation = "Saved metadata summaries; counts and feature totals are not recomputed from the current layer.",
    total_counts = .sc_run_react_distribution(values(paste0("nCount_", cfg$assay))),
    detected_features = .sc_run_react_distribution(values(paste0("nFeature_", cfg$assay))),
    mitochondrial_percent = .sc_run_react_distribution(values("percent.mt")))
  sample_column <- cfg$context$columns$sample
  samples <- list(status = "unavailable", composition = list())
  if (!is.null(sample_column) && sample_column %in% names(metadata)) {
    labels <- as.character(metadata[[sample_column]])
    groups <- sort(unique(labels[!is.na(labels) & nzchar(labels)]), method = "radix")
    counts <- table(factor(labels[inside], levels = groups)); active <- counts > 0
    # Suppress the whole composition if even one stratum is identifying. Never
    # merge small scientific groups or emit labels from arbitrary metadata.
    if (anyNA(labels[inside]) || any(!nzchar(labels[inside])) || any(counts[active] < 5L)) {
      samples$status <- "suppressed"; samples$reason <- "Incomplete sample assignments or a within-cluster sample group smaller than five cells."
    } else {
      samples$status <- "available"
      samples$composition <- lapply(unname(which(active)), function(i) list(sample = paste0("sample_", i),
        cells = unname(as.integer(counts[i])), proportion = unname(as.numeric(counts[i])) / length(inside)))
      samples$label_policy <- "Stable project-local sample aliases; original sample labels are not transmitted."
    }
  }
  diagnostic <- function(name, keys) {
    record <- .sc_run_react_read(context, name)
    if (is.null(record) || !is.data.frame(record$scores) || is.null(record$summary$columns))
      return(list(status = "unavailable", scores = list()))
    scores <- record$scores
    if (!"cell_id" %in% names(scores) || !is.character(scores$cell_id) ||
        anyNA(scores$cell_id) || anyDuplicated(scores$cell_id) ||
        !identical(record$cell_ids, scores$cell_id) ||
        !all(cells[inside] %in% scores$cell_id))
      .sc_run_react_error("invalid_evidence", "Diagnostic scores have an invalid cell identity binding.")
    index <- match(cells[inside], scores$cell_id)
    metrics <- lapply(keys, function(key) {
      column <- record$summary$columns[[key]]
      .sc_run_react_distribution(if (!is.null(column) && column %in% names(scores)) scores[[column]][index] else NULL)
    }); names(metrics) <- keys
    list(status = if (any(vapply(metrics, function(x) x$status != "unavailable", logical(1)))) "available" else "unavailable",
      scores = metrics)
  }
  list(status = "available", cluster_id = arguments$cluster_id, cells = length(inside),
    samples = samples, qc = qc, doublet = diagnostic("doublet_diagnostics", "score"),
    cell_cycle = diagnostic("cycle_diagnostics", c("s_score", "g2m_score", "difference")),
    interpretation = "Saved summaries for the current analysis cells only. Missing diagnostics are unavailable, not zero; doublet scores are predictions, not biological truth.")
}
