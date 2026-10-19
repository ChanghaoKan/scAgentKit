# Shared marker kernels; no AgentSeurat, decision state or file writes.
.sc_marker_test <- function(seu, only_pos=FALSE, min_pct=0.25, logfc_threshold=0) {
  if (!"seurat_clusters" %in% colnames(seu@meta.data))
    stop("No 'seurat_clusters' column; run sc_cluster() first.")
  Seurat::FindAllMarkers(
    seu,
    group.by        = "seurat_clusters",
    only.pos        = only_pos,
    min.pct         = min_pct,
    logfc.threshold = logfc_threshold,
    verbose         = FALSE
  )
}

.sc_marker_summary <- function(markers, top_n=30, log2fc_cut=1, padj_cut=0.05) {
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
  list(filtered=filtered, summary_lines=summary_lines, cycling_score=cycling_score)
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
