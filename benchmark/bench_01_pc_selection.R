#!/usr/bin/env Rscript
# bench_01_pc_selection.R
#
# Compare scAgentKit's `sc_select_pcs_visual` against simple baselines for
# the choice of how many PCs to retain. Metric: downstream cluster ARI vs
# author labels at a fixed resolution.
#
# Status: partial prototype. Use pbmc3k_repro.R for the offline workflow
# and replay check. Provider runs require explicit --allow_llm opt-in.
#
# Usage:
#   Rscript bench_01_pc_selection.R \
#     --datasets  pbmc3k,pbmc10k \
#     --providers claude,deepseek \
#     --resolution 0.5 \
#     --out_dir   results/bench_01/

suppressPackageStartupMessages({
  library(optparse)
  library(scAgentKit)
  library(Seurat)
  library(dplyr)
})

# ---- CLI -------------------------------------------------------------------

opt_list <- list(
  make_option("--datasets",  type = "character", default = "pbmc3k"),
  make_option("--providers", type = "character", default = ""),
  make_option("--allow_llm", action = "store_true", default = FALSE),
  make_option("--allow_data_download", action = "store_true", default = FALSE),
  make_option("--resolution", type = "double",   default = 0.5),
  make_option("--out_dir",   type = "character", default = "results/bench_01/")
)
opt <- parse_args(OptionParser(option_list = opt_list))
dir.create(opt$out_dir, recursive = TRUE, showWarnings = FALSE)

datasets  <- strsplit(opt$datasets,  ",", fixed = TRUE)[[1]]
providers <- Filter(nzchar, strsplit(opt$providers, ",", fixed = TRUE)[[1]])
if (length(providers) && !isTRUE(opt$allow_llm)) {
  stop("Provider runs may upload data and incur charges. Pass --allow_llm only after authorization.")
}

# ---- Dataset registry ------------------------------------------------------
# Keep reference labels outside input metadata. No reference vocabulary
# or class count is available to a provider-assisted selection step.
load_dataset <- function(name) {
  if (name == "pbmc3k") {
    if (!requireNamespace("SeuratData", quietly = TRUE)) {
      stop("Install SeuratData: remotes::install_github('satijalab/seurat-data')")
    }
    if (isTRUE(opt$allow_data_download)) SeuratData::InstallData("pbmc3k")
    seu <- SeuratData::LoadData("pbmc3k")
    if (!"seurat_annotations" %in% colnames(seu@meta.data)) {
      stop("Local pbmc3k data has no seurat_annotations reference column.")
    }
    truth <- stats::setNames(as.character(seu$seurat_annotations), colnames(seu))
    # Preserve only mechanically generated input/QC metadata, rather
    # than attempting to guess every possible author-label column name.
    seu@meta.data <- seu@meta.data[, intersect(
      c("orig.ident", "nCount_RNA", "nFeature_RNA"), colnames(seu@meta.data)
    ), drop = FALSE]
    list(seu = seu, truth = truth)
  } else if (name == "pbmc10k") {
    stop("TODO: implement pbmc10k loader (e.g. 10x public dataset).")
  } else if (name == "tabula_muris_liver") {
    stop("TODO: implement Tabula Muris liver loader (Smart-seq2 / 10x).")
  } else if (name == "hca_liver") {
    stop("TODO: implement HCA Liver loader (Aizarani 2019).")
  } else {
    stop(sprintf("Unknown dataset '%s'. Add a loader in bench_01_pc_selection.R.", name))
  }
}

# ---- chat_fn registry ------------------------------------------------------
build_chat_fn <- function(provider) {
  switch(provider,
    claude   = chat_claude(),
    deepseek = chat_deepseek(),
    openai   = chat_openai(),
    grok     = chat_grok(),
    qwen     = chat_qwen(),
    stop(sprintf("Unknown provider '%s'.", provider))
  )
}

# ---- Baselines -------------------------------------------------------------
# Each baseline returns an integer ndim given a Seurat object with PCA.
baselines <- list(
  fixed_ndim_20 = function(seu) 20L,
  fixed_ndim_30 = function(seu) 30L,
  elbow_seurat = function(seu) {
    # Simple elbow: first PC where (stdev[i] - stdev[i+1]) drops below
    # 5% of the largest gap. This is a stand-in for analyst-eye reading
    # of ElbowPlot; refine if it disagrees with curated values.
    stdev <- seu[["pca"]]@stdev
    diffs <- -diff(stdev)
    thresh <- 0.05 * max(diffs)
    elbow <- which(diffs < thresh)[1]
    if (is.na(elbow)) length(stdev) else elbow
  },
  jackstraw = function(seu) {
    # JackStraw is slow; cap candidates at 50 PCs.
    dims <- seq_len(min(50L, length(seu[["pca"]]@stdev)))
    seu <- JackStraw(seu, num.replicate = 100, dims = max(dims), verbose = FALSE)
    seu <- ScoreJackStraw(seu, dims = dims)
    js  <- seu[["pca"]]@jackstraw@overall.p.values
    max(1L, sum(js[, 2] < 0.05))
  }
)

# ---- scAgentKit pipeline ---------------------------------------------------
run_scagentkit <- function(seu, chat_fn, tissue) {
  obj <- AgentSeurat(seu)
  obj <- qc_add_metrics(obj, species = "human")
  obj <- sc_normalize(obj)
  obj <- sc_find_hvg(obj)
  obj <- sc_scale(obj)
  obj <- sc_pca(obj, npcs = 50)
  obj <- sc_select_pcs_visual(obj, chat_fn = chat_fn, tissue = tissue)
  list(
    # This recommendation location is part of the documented public API;
    # the legacy .find_in_decisions alias is package-internal.
    ndim  = obj@params$pcs_visual_recommendation$chosen,
    obj   = obj
  )
}

# ---- Cluster + score helper -----------------------------------------------
cluster_and_score <- function(seu_with_pca, ndim, resolution, author_label) {
  ndim <- min(as.integer(ndim), length(seu_with_pca[["pca"]]@stdev))
  if (length(ndim) != 1L || is.na(ndim) || ndim < 1L) stop("Invalid ndim.")
  seu <- FindNeighbors(seu_with_pca, dims = seq_len(ndim), verbose = FALSE)
  seu <- FindClusters(seu, resolution = resolution, verbose = FALSE)
  clus <- as.character(seu$seurat_clusters)
  truth <- as.character(author_label[colnames(seu)])
  keep <- !is.na(clus) & !is.na(truth)
  ari <- .adjusted_rand_index(clus[keep], truth[keep])
  list(ari = ari, n_clusters = length(unique(clus[keep])))
}

# Inlined ARI (mirrors the package-internal one)
.adjusted_rand_index <- function(a, b) {
  tab <- table(a, b); n <- sum(tab)
  if (n < 2L) return(NA_real_)
  sum_comb <- function(x) sum(choose(x, 2))
  a_s <- sum_comb(rowSums(tab)); b_s <- sum_comb(colSums(tab))
  t_s <- sum_comb(as.vector(tab))
  expected <- a_s * b_s / choose(n, 2)
  max_idx  <- (a_s + b_s) / 2
  if (max_idx == expected) return(1)
  (t_s - expected) / (max_idx - expected)
}

# ---- Main loop -------------------------------------------------------------
results <- list()
for (ds in datasets) {
  message(sprintf("[bench_01] === Dataset: %s ===", ds))
  loaded <- load_dataset(ds)
  seu <- loaded$seu
  truth <- loaded$truth
  write.csv(data.frame(cell_id = names(truth), label = unname(truth)),
            file.path(opt$out_dir, paste0(ds, "_reference_labels.csv")),
            row.names = FALSE)

  # Run a single Seurat preprocessing pass so all methods see the same
  # PCA. (The scAgentKit path also computes its own PCA internally;
  # asserting equivalence is part of bench_04_reproducibility.R.)
  seu <- NormalizeData(seu, verbose = FALSE)
  seu <- FindVariableFeatures(seu, verbose = FALSE)
  seu <- ScaleData(seu, verbose = FALSE)
  seu <- RunPCA(seu, npcs = 50, verbose = FALSE)

  # Baselines
  for (bn in names(baselines)) {
    message(sprintf("  baseline: %s", bn))
    ndim <- baselines[[bn]](seu)
    sc <- cluster_and_score(seu, ndim, opt$resolution, truth)
    results[[length(results) + 1]] <- data.frame(
      dataset = ds, method = bn, provider = NA, ndim = ndim,
      ari = sc$ari, n_clusters = sc$n_clusters,
      stringsAsFactors = FALSE
    )
  }

  # scAgentKit per provider
  for (prov in providers) {
    message(sprintf("  scAgentKit + %s", prov))
    chat <- build_chat_fn(prov)
    sk <- run_scagentkit(seu, chat_fn = chat, tissue = ds)
    sc <- cluster_and_score(get_seurat(sk$obj), sk$ndim, opt$resolution, truth)
    results[[length(results) + 1]] <- data.frame(
      dataset = ds, method = "scagentkit", provider = prov,
      ndim = sk$ndim, ari = sc$ari, n_clusters = sc$n_clusters,
      stringsAsFactors = FALSE
    )
  }
}

df <- do.call(rbind, results)
write.csv(df,
          file = file.path(opt$out_dir, "metrics.csv"),
          row.names = FALSE)
message(sprintf("[bench_01] wrote %s", file.path(opt$out_dir, "metrics.csv")))
print(df)
