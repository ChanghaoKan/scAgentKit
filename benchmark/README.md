# scAgentKit evaluation scaffolding

> **Status: experimental and incomplete. Do not cite this directory as
> benchmark evidence.**

This directory records proposed evaluation designs for scAgentKit. It is
separate from `tests/`, which contains fast unit tests. Full evaluations
would require:

- LLM API keys (and money)
- Public single-cell datasets (~100 MB to ~10 GB)
- Hours to days of wall time

Current implementation status:

| Script | Status |
|---|---|
| `bench_01_pc_selection.R` | partial prototype; not validated as a reproducible benchmark |
| `bench_02_resolution.R`–`bench_06_ablation.R` | explicit stubs that stop immediately |
| `bench_99_collate.R` | explicit stub that stops immediately |

No comparative-performance, parity, reproducibility, or accuracy conclusion
can be drawn from the repository in its current state.

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

### 4. Script reconstruction (`bench_04_reproducibility.R`)

After generated snippets have been reviewed and completed, test whether the
exported reconstruction can be run from the recorded inputs and compare:

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

### 6. Marker-citation grounding ablation (`bench_06_ablation.R`)

Run `annot_llm_annotate` with each of these removed in turn:

- `contradicting_markers` field requirement
- Cycling-cluster lineage rescue
- TRUE contamination rules
- `validate_markers = TRUE`
- Ensemble (`n_samples = 3 -> 1`)

Datasets with curated ground truth (PBMC 3k, Tabula Muris).

Planned metrics: unsupported-marker citation rate (the current
`.validate_cited_markers` field name is retained for compatibility), label
accuracy against a reviewed reference, and mean heuristic confidence.

## How to inspect the partial harness

Only `bench_01_pc_selection.R` contains a partial harness. Review its dataset
loading, ground-truth mapping, provider configuration, and metric definitions
before attempting a run. The other scripts intentionally stop as stubs.

Prerequisites for development:

```r
remotes::install_github("ChanghaoKan/agentomicsCore", ref = "v0.1.1")
remotes::install_github("ChanghaoKan/scAgentKit", ref = "v0.4.0")
remotes::install_github("satijalab/seurat-data")
```

Set only the provider keys required for your chosen experiment through your
normal secret-management mechanism. Never commit them to this repository.

Then:

```sh
Rscript bench_01_pc_selection.R --datasets pbmc3k,pbmc10k \
        --providers claude,deepseek \
        --out_dir   results/bench_01/
```

The partial harness is intended to write under `results/<bench_id>/`, but its
outputs and schemas are not frozen.

## Reporting

`bench_99_collate.R` is currently a stub and does not generate figures or
captions.

## What is NOT in here

- The published manuscript text (lives in a separate `paper/` repo).
- Frozen versions of the datasets (those are too large; the scripts
  pull via `SeuratData::InstallData()` / accession URLs).
- Pre-computed or independently reviewed results.

## TODO

- [ ] Complete and validate `bench_01_pc_selection.R`
- [ ] Implement `bench_02_resolution.R`
- [ ] Implement `bench_03_batch_var.R`
- [ ] Implement `bench_04_reproducibility.R`
- [ ] Implement `bench_05_providers.R`
- [ ] Implement `bench_06_ablation.R`
- [ ] `bench_99_collate.R`
- [ ] Pre-register the metric definitions before running (OSF / GitHub
      issue tagged `methods-prereg` is fine)
