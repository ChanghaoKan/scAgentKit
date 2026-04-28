#' Find marker genes for all clusters
#'
#' Wrapper around [Seurat::FindAllMarkers()]. Returns the full marker table
#' and stores it at `obj@@params$all_markers` for downstream filtering or
#' annotation. Use [sc_markers_summary()] to get the
#' filtered + pct_diff-ranked top-N-per-cluster summary.
#'
#' @param obj An AgentSeurat object after [sc_cluster()].
#' @param only_pos Logical. Default FALSE (keep down-regulated markers too,
#'   which can be informative for negative markers in annotation).
#' @param min_pct Numeric. Default 0.25.
#' @param logfc_threshold Numeric. Default 0 (no pre-filter; filter later).
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat; marker table is stored at
#'   `obj@@params$all_markers`.
#' @export
sc_find_markers <- function(obj,
                            only_pos         = FALSE,
                            min_pct          = 0.25,
                            logfc_threshold  = 0,
                            rationale        = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (!"seurat_clusters" %in% colnames(obj@data@meta.data)) {
    stop("No 'seurat_clusters' column; run sc_cluster() first.")
  }

  seu <- obj@data
  markers <- Seurat::FindAllMarkers(
    seu,
    only.pos        = only_pos,
    min.pct         = min_pct,
    logfc.threshold = logfc_threshold,
    verbose         = FALSE
  )

  script <- sprintf(
'# ---- Find all markers (min.pct = %s, logfc.threshold = %s) ----
all_markers <- FindAllMarkers(seurat_obj,
                              only.pos        = %s,
                              min.pct         = %s,
                              logfc.threshold = %s)',
    format(min_pct), format(logfc_threshold),
    as.character(only_pos), format(min_pct), format(logfc_threshold)
  )

  n_markers <- nrow(markers)
  n_clusters <- length(unique(markers$cluster))

  if (is.null(rationale)) {
    rationale <- sprintf(
      "FindAllMarkers produced %d marker rows across %d clusters.",
      n_markers, n_clusters
    )
  }

  obj <- .record_step(
    obj            = obj,
    step_name      = "sc_find_markers",
    function_name  = "sc_find_markers",
    params         = list(only_pos = only_pos, min_pct = min_pct,
                          logfc_threshold = logfc_threshold,
                          n_markers = n_markers, n_clusters = n_clusters),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "markers_found"
  )
  obj@params$all_markers <- markers
  obj
}

#' Filter and rank markers; optionally export a per-cluster summary
#'
#' Applies the ranking used in the Ca_Ctrl pipeline: keep markers with
#' `avg_log2FC > log2fc_cut` and `p_val_adj < padj_cut`, then rank within
#' each cluster by `pct.1 - pct.2` (specificity) and keep the top N.
#' Writes a compact text summary in the form
#' `cluster0:Gene1,Gene2,...` (convenient for pasting into ACT/CellMarker).
#'
#' @param obj An AgentSeurat object after [sc_find_markers()].
#' @param top_n Integer, top markers per cluster. Default 30.
#' @param log2fc_cut Numeric. Default 1.
#' @param padj_cut Numeric. Default 0.05.
#' @param output_path Optional path to write the text summary. If NULL,
#'   no file is written. Default "markers_top_per_cluster.txt".
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat; filtered table is stored at
#'   `obj@@params$markers_filtered` and the per-cluster summary list at
#'   `obj@@params$markers_summary`.
#' @export
sc_markers_summary <- function(obj,
                               top_n        = 30,
                               log2fc_cut   = 1,
                               padj_cut     = 0.05,
                               output_path  = "markers_top_per_cluster.txt",
                               rationale    = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  markers <- obj@params$all_markers
  if (is.null(markers)) stop("No marker table found; run sc_find_markers() first.")

  # Avoid R CMD check notes for NSE vars
  avg_log2FC <- p_val_adj <- pct.1 <- pct.2 <- pct_diff <- cluster <- gene <- NULL

  filtered <- markers |>
    dplyr::filter(avg_log2FC > log2fc_cut, p_val_adj < padj_cut) |>
    dplyr::mutate(pct_diff = pct.1 - pct.2) |>
    dplyr::group_by(cluster) |>
    dplyr::arrange(dplyr::desc(pct_diff), .by_group = TRUE) |>
    dplyr::slice_head(n = top_n) |>
    dplyr::ungroup()

  summary_lines <- filtered |>
    dplyr::group_by(cluster) |>
    dplyr::summarise(genes = paste0(gene, collapse = ","), .groups = "drop") |>
    dplyr::mutate(output = paste0("cluster", cluster, ":", genes)) |>
    dplyr::pull(output)

  if (!is.null(output_path)) {
    dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)
    writeLines(summary_lines, output_path)
  }

  script <- sprintf(
'# ---- Marker filter + top-N ranking by pct_diff ----
markers_filtered <- all_markers %%>%%
  dplyr::filter(avg_log2FC > %s, p_val_adj < %s) %%>%%
  dplyr::mutate(pct_diff = pct.1 - pct.2) %%>%%
  dplyr::group_by(cluster) %%>%%
  dplyr::arrange(desc(pct_diff), .by_group = TRUE) %%>%%
  dplyr::slice_head(n = %d) %%>%%
  dplyr::ungroup()',
    format(log2fc_cut), format(padj_cut), top_n
  )
  if (!is.null(output_path)) {
    script <- paste0(script, sprintf(
'\n\nsummary_lines <- markers_filtered %%>%%
  dplyr::group_by(cluster) %%>%%
  dplyr::summarise(genes = paste0(gene, collapse = ",")) %%>%%
  dplyr::mutate(output = paste0("cluster", cluster, ":", genes)) %%>%%
  dplyr::pull(output)
writeLines(summary_lines, "%s")',
      output_path
    ))
  }

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Top %d markers per cluster (log2FC > %s, padj < %s), ranked by pct.1 - pct.2.",
      top_n, format(log2fc_cut), format(padj_cut)
    )
  }

  obj <- .record_step(
    obj            = obj,
    step_name      = "sc_markers_summary",
    function_name  = "sc_markers_summary",
    params         = list(top_n = top_n, log2fc_cut = log2fc_cut,
                          padj_cut = padj_cut, output_path = output_path,
                          n_rows_kept = nrow(filtered)),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "markers_summarized"
  )
  obj@params$markers_filtered <- filtered
  obj@params$markers_summary  <- summary_lines

  # v0.1.11: cell-cycle dominance score per cluster.
  # When top markers are dominated by cell-cycle genes (KIAA0101, UBE2C,
  # TOP2A, MKI67, BIRC5, ...), the cluster's identity is hard to infer
  # from markers alone. We expose this score so annot_llm_annotate can
  # adapt its prompt accordingly.
  cc_genes <- .cell_cycle_marker_set()
  cycling_score <- filtered %>%
    dplyr::group_by(cluster) %>%
    dplyr::summarise(
      cc_frac      = mean(toupper(gene) %in% cc_genes),
      n_cc_in_top  = sum(toupper(gene) %in% cc_genes),
      n_top        = dplyr::n(),
      .groups      = "drop"
    ) %>%
    dplyr::mutate(
      cycling_dominant = cc_frac >= 0.30
    ) %>%
    as.data.frame()
  obj@params$cluster_cycling_score <- cycling_score

  obj
}

# Conservative cell-cycle marker set.
# Source: Tirosh 2016 S/G2M genes (~100) + a few canonical proliferation
# markers (MKI67, PCNA). Stored here rather than re-imported from Seurat
# to avoid namespace surprises on v5.
.cell_cycle_marker_set <- function() {
  toupper(c(
    # S phase (Tirosh)
    "MCM5","PCNA","TYMS","FEN1","MCM2","MCM4","RRM1","UNG","GINS2","MCM6",
    "CDCA7","DTL","PRIM1","UHRF1","MLF1IP","HELLS","RFC2","RPA2","NASP",
    "RAD51AP1","GMNN","WDR76","SLBP","CCNE2","UBR7","POLD3","MSH2","ATAD2",
    "RAD51","RRM2","CDC45","CDC6","EXO1","TIPIN","DSCC1","BLM","CASP8AP2",
    "USP1","CLSPN","POLA1","CHAF1B","BRIP1","E2F8","KIAA0101",
    # G2M phase (Tirosh)
    "HMGB2","CDK1","NUSAP1","UBE2C","BIRC5","TPX2","TOP2A","NDC80","CKS2",
    "NUF2","CKS1B","MKI67","TMPO","CENPF","TACC3","FAM64A","SMC4","CCNB2",
    "CKAP2L","CKAP2","AURKB","BUB1","KIF11","ANP32E","TUBB4B","GTSE1",
    "KIF20B","HJURP","CDCA3","HN1","CDC20","TTK","CDC25C","KIF2C","RANGAP1",
    "NCAPD2","DLGAP5","CDCA2","CDCA8","ECT2","KIF23","HMMR","AURKA","PSRC1",
    "ANLN","LBR","CKAP5","CENPE","CTCF","NEK2","G2E3","GAS2L3","CBX5","CENPA",
    "CCNB1","STMN1","ZWINT","UBE2T","HIST1H4C","CENPW","CDKN3","TUBB","CENPN"
  ))
}
