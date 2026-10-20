react_tool_fixture <- function() {
  root <- tempfile("react-tools-"); dir.create(root)
  cells <- paste0("private-cell-", sprintf("%02d", 12:1))
  genes <- c(paste0("G", sprintf("%02d", 1:60)), "RPL3", "MT-CO1")
  counts <- Matrix::Matrix(matrix(rep(c(0, 0, 1, 4), length.out = length(genes) * length(cells)),
    nrow = length(genes), dimnames = list(genes, cells)), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- log1p(counts)
  seu$seurat_clusters <- rep(c("0", "1"), each = 6)
  seu$sample_label <- rep(c("private-sample-A", "private-sample-B"), each = 6)
  seu$percent.mt <- c(1:5, NA_real_, 7:12)
  table <- data.frame(cluster = rep(c("0", "1"), each = length(genes)), gene = rep(genes, 2),
    avg_log2FC = rep(seq(3, .1, length.out = length(genes)), 2), pct.1 = .8, pct.2 = .1, p_val_adj = .001)
  table$p_val_adj[table$gene == "G32"] <- .1
  table$pct.1[table$gene == "G33"] <- .05
  table$avg_log2FC[table$gene == "G34"] <- -.1
  summary <- table[table$gene %in% genes[1:30], ]
  attr(summary, "marker_pool") <- list(exclusions = list(excluded_genes = as.list("G35")))
  marker_record <- list(markers = table, marker_summary = summary,
    parameters = list(exclude_genes = "G36", exclude_shared = TRUE), cluster_column = "seurat_clusters")
  reference <- data.frame(species = c("human", "human", "mouse", "human"),
    tissue = c("blood", "lung", "blood", "blood"), cell_type = c("T cell", "wrong tissue", "wrong species", "B cell"),
    marker = c("G01", "G01", "G01", "G02"), pmid = c("123", "456", "789", "234"))
  attr(reference, "reference_source") <- "ACT"
  attr(reference, "source_version") <- "test-snapshot"
  attr(reference, "source_path") <- "/private/never-transmit.tsv"
  config <- list(assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    cluster_column = "seurat_clusters", context = list(species = "human", tissue = "blood",
      columns = list(sample = "sample_label")))
  state <- list(project_id = "react-software-fixture", input_hash = .sc_run_hash(seu), config = config,
    config_hash = .sc_run_hash(config), implementation_hash = .sc_run_implementation(),
    files = list(), history = list(), revision = 0L, stage = "annotation_propose", pending = NULL)
  evidence <- list(summary = list(), private = list(input_cells = data.frame(cell_id = cells,
    cluster = unname(as.character(seu$seurat_clusters)))))
  for (name in c("input", "analysis")) state <- .sc_run_put(root, state, name, seu)
  state <- .sc_run_put(root, state, "markers", marker_record)
  state <- .sc_run_put(root, state, "reference", reference)
  state <- .sc_run_put(root, state, "annotation_evidence", evidence)
  commit <- function(state) .sc_run_atomic(list(schema = "scagentkit.run-state.v1",
    hash = .sc_run_hash(state), state = state), file.path(root, "state.rds"))
  commit(state)
  list(root = root, state = state, context = .sc_run_react_context(root), cells = cells,
    genes = genes, seu = seu, commit = commit)
}

react_local <- function(fixture, tool, arguments, cache_dir = FALSE) {
  definition <- .sc_run_react_tools()[[tool]]
  .sc_run_react_dispatch_local(fixture$context, tool,
    .sc_run_react_arguments(definition, arguments), cache_dir)
}
