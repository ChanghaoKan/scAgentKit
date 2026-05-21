# scAgentKit benchmarks

This directory contains the validation experiments for the scAgentKit
methods paper. They are deliberately separate from `tests/` (which is for
fast unit tests in CI) because they require:

- LLM API keys (and money)
- Public single-cell datasets (~100 MB to ~10 GB)
- Hours to days of wall time

## What we benchmark and why

scAgentKit enters a crowded space (mLLMCelltype, CyteType, DeepCellSeek,
scAgent, CellTypeAgent, LICT, CellMaster, GPTCellType, ...). To stand out,
we benchmark on what those tools **do not** do:

- **Upstream pipeline decisions** (PC selection, clustering resolution,
  batch variable identification). Competitors are annotation-only.
- **End-to-end reproducibility** (does the exported script reproduce the
  same Seurat object?). Competitors don't ship a reproducibility layer.
- **The annotation step** is benchmarked too, but as a *parity check* —
  we expect to be in the same ballpark as mLLMCelltype, not to win.

## Planned experiments

### 1. PC selection (`bench_01_pc_selection.R`)

scAgentKit's `sc_select_pcs_visual` vs:

- Seurat default `ElbowPlot` interpreted at the typical 1st-eigenvalue-cliff
- Fixed `ndim = 20` (popular convenience default)
- Fixed `ndim = 30`
- `JackStraw` permutation-based selection

Datasets: PBMC 3k, PBMC 10k, HCA Liver (sampled to 30k), Tabula Muris liver.

Metric: downstream ARI of clusters vs author labels at fixed resolution.

### 2. Clustering resolution (`bench_02_resolution.R`)

scAgentKit's `sc_resolution_recommend` (vision + non-vision) vs:

- Single fixed resolution: 0.3, 0.5, 0.8, 1.0
- `clustree` largest-stable-region heuristic
- Maximum silhouette resolution

Same datasets.

Metric: |chosen_n_clusters - author_n_clusters| and ARI vs author labels.

### 3. Batch variable identification (`bench_03_batch_var.R`)

scAgentKit's `sc_select_batch_var` vs:

- "Use sample" (default for most users)
- All-metadata-columns regress-out (anti-pattern)
- Reference batch as published by the data author

Datasets requiring batch correction: multi-donor HCA Liver subset,
GSE149614 HCC tumor + adjacent.

Metric: post-Harmony LISI (batch) + LISI (cell type) trade-off, kBET
score.

### 4. End-to-end reproducibility (`bench_04_reproducibility.R`)

Run scAgentKit, export the script via `get_script(obj)`, run that script
from scratch, compare:

- Per-cell cluster assignment: Jaccard / ARI
- Per-cell UMAP coordinates: Procrustes-aligned distance
- Annotation labels: exact-match fraction

Run on PBMC 3k. Repeat with `set.seed()` removed to quantify
*irreducible* LLM-call non-determinism.

### 5. Multi-provider robustness (`bench_05_providers.R`)

Same dataset, same prompts, swap chat_fn across:
DeepSeek-V3, GPT-4o, Claude Sonnet 4.6, Grok 4, Qwen-Plus, Kimi.

Metric: pairwise label agreement matrix; ensemble-of-providers vs
ensemble-of-samples-within-provider.

### 6. Anti-hallucination ablation (`bench_06_ablation.R`)

Run `annot_llm_annotate` with each of these removed in turn:

- `contradicting_markers` field requirement
- Cycling-cluster lineage rescue
- TRUE contamination rules
- `validate_markers = TRUE`
- Ensemble (`n_samples = 3 -> 1`)

Datasets with curated ground truth (PBMC 3k, Tabula Muris).

Metric: hallucination rate (from `.validate_cited_markers`), label
accuracy, mean hybrid confidence.

## How to run

Each script is self-contained. Pre-requisites:

```r
remotes::install_github("ChanghaoKan/scAgentKit", ref = "v0.2.0")
remotes::install_github("satijalab/seurat-data")

# API keys in ~/.Renviron
ANTHROPIC_API_KEY=sk-ant-...
DEEPSEEK_API_KEY=sk-...
OPENAI_API_KEY=sk-...
```

Then:

```sh
Rscript bench_01_pc_selection.R --datasets pbmc3k,pbmc10k \
        --providers claude,deepseek \
        --out_dir   results/bench_01/
```

Outputs go under `results/<bench_id>/` as `.qs` (full AgentSeurat
objects), `.csv` (metric tables), and `figures/` (per-comparison
panels).

## Reporting

`bench_99_collate.R` reads all `results/*/metrics.csv`, generates the
paper's Figure 3-5 panels with `ggplot2`, and writes
`paper/figures/`. Reviewer-grade caption strings live in
`paper/captions.yaml`.

## What is NOT in here

- The published manuscript text (lives in a separate `paper/` repo).
- Frozen versions of the datasets (those are too large; the scripts
  pull via `SeuratData::InstallData()` / accession URLs).
- Pre-computed results (will be uploaded to Zenodo on paper acceptance
  with the DOI cross-referenced from this README).

## TODO

- [ ] Implement `bench_01_pc_selection.R`
- [ ] Implement `bench_02_resolution.R`
- [ ] Implement `bench_03_batch_var.R`
- [ ] Implement `bench_04_reproducibility.R`
- [ ] Implement `bench_05_providers.R`
- [ ] Implement `bench_06_ablation.R`
- [ ] `bench_99_collate.R`
- [ ] Pre-register the metric definitions before running (OSF / GitHub
      issue tagged `methods-prereg` is fine)
