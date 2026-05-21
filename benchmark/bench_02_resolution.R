#!/usr/bin/env Rscript
# bench_02_resolution.R --- STUB
#
# Compare sc_resolution_recommend (vision and non-vision) against:
#   - Fixed resolution 0.3 / 0.5 / 0.8 / 1.0
#   - clustree largest-stable-region
#   - Maximum silhouette resolution
# Datasets: PBMC 3k/10k, HCA Liver, Tabula Muris liver.
# Metric: |chosen_n_clusters - author_n_clusters| and ARI vs author labels.
#
# See benchmark/README.md for the full spec.
#
# TODO:
#   - load_dataset() registry (factor out from bench_01)
#   - implement build_chat_fn() (factor out from bench_01)
#   - implement clustree-based baseline (cluster sweep -> clustree::clustree
#     -> pick the resolution where mean cluster crossing rate stabilises)
#   - implement silhouette baseline
#   - implement scAgentKit vision and non-vision paths
stop("bench_02_resolution.R is a stub. See benchmark/README.md.")
