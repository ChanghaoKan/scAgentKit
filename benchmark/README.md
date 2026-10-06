# scAgentKit evaluation scaffolding

> **Status: experimental. The PBMC3k workflow/replay harness is runnable;
> the comparative evaluation suite remains incomplete. A workflow check
> is not evidence of annotation accuracy or superiority over other tools.**

This directory contains a local PBMC3k reproducibility check and proposed
evaluation designs for scAgentKit. It is separate from `tests/`, which
contains fast unit tests. Full provider evaluations would require:

- LLM API keys (and money)
- Public single-cell datasets (~100 MB to ~10 GB)
- Hours to days of wall time

Current implementation status:

| Script | Status |
|---|---|
| `pbmc3k_repro.R` | executable offline Seurat5 workflow and saved-decision replay; requires local raw counts and installed dependencies |
| `bench_01_pc_selection.R` | partial prototype; corrected public APIs and reference-label isolation; provider calls and data installation require explicit opt-in |
| `bench_02_resolution.R`–`bench_06_ablation.R` | explicit stubs that stop immediately |
| `bench_99_collate.R` | explicit stub that stops immediately |

The PBMC3k outputs report the measured workflow and replay checks from each
run. The incomplete comparison scripts cannot support a general
comparative-performance or annotation-accuracy conclusion.

## Local PBMC3k workflow and replay

`pbmc3k_repro.R` receives an already downloaded 10X filtered counts directory.
It neither installs dependencies nor downloads data, creates a provider,
reads API credentials, or uploads input. The CLI uses base R and the package
dependencies. Keep the R library local to the experiment; dependency
installation is a separate step subject to the environment's permissions.

From the repository root, with the task's private library and local files:

```sh
Rscript benchmark/pbmc3k_repro.R \
  --library_dir ../.r-lib \
  --counts_dir ../data/pbmc3k/filtered_gene_bc_matrices/hg19 \
  --truth_csv ../data/pbmc3k/truth.csv \
  --ncells 800 --seed 999 \
  --out_dir ../results/pbmc3k_run

Rscript benchmark/pbmc3k_repro.R \
  --library_dir ../.r-lib \
  --mode replay --run_dir ../results/pbmc3k_run \
  --out_dir ../results/pbmc3k_replay
```

Use fresh output directories; the harness refuses to overwrite a nonempty
directory. Adjust the paths for another workstation. `--truth_csv` is
optional. It must contain unique `cell_id` and `label` columns with exact
barcode matches. If the source label data uses bare barcodes and counts use
the `-1` suffix, perform and document that explicit transformation in the
separate truth file before running. Extra provenance columns, such as
`source_cell_id`, are preserved in the evaluation copy.

The raw matrix is sampled before any reference-label read. The default
uses 800 barcodes sampled from sorted IDs with seed 999, then stores the
selected IDs in sorted order. Both methods create a fresh Seurat5 `Assay5`
object with only `orig.ident`, `nCount_RNA`, and `nFeature_RNA` input metadata.
Reference labels, their vocabulary, and their class count never enter an
analysis object or decision input.

The fixed choices are saved before the analysis runs:

| Step | Choice |
|---|---|
| Gene retention | detected in at least 3 sampled cells |
| QC | `nCount_RNA > 0`, `200 < nFeature_RNA < 2500`, `0 <= percent.mt < 5` |
| Normalization | LogNormalize, scale factor 10,000 |
| Variable features and scaling | vst, 2,000 HVGs; scale HVGs only |
| PCA and graph | 30 PCs computed, PCs 1–10 used for neighbors |
| Clustering | Louvain, resolution 0.5 |
| Random state | RNG kind and seed 999 recorded; effective Seurat PCA/UMAP seeds 42 and clustering seed 0 recorded |
| Markers | FindAllMarkers with `only.pos = FALSE`, `min.pct = 0.25`, `logfc.threshold = 0` |
| Evidence summary | `avg_log2FC > 1`, `p_val_adj < 0.05`; rank by `pct.1 - pct.2`, top 30 per cluster |

`seurat5_fixed` executes native Seurat operations; `scagentkit_fixed`
executes the corresponding recorded scAgentKit wrappers. The upper feature
cutoff, which is not an argument of `qc_threshold()`, uses an explicitly
recorded subset step. This is a fixed analyst baseline: it does not test an
LLM's choice of QC, PCs, resolution, or cell type.

The valid human PBMC ACT database is not bundled. The demonstration
`inst/extdata/reference_template.tsv` is excluded from this experiment.
ACT reference matching is recorded as `missing_reference`; both LLM paths
are `not_run_no_authorization`. Their per-cell files retain `unknown`
instead of borrowing reference labels. The guided and independent input
manifests preserve the same filtered marker evidence, tissue `blood`, and
empty reference candidates for later authorized two-path review. They are
prepared inputs, not saved model answers. SingleR and CellTypist are also
explicitly `not_run` and are not prerequisites for this first check.

Each run writes:

- Raw input checksums, selected barcodes, sampled raw counts, blind Seurat
  input, saved fixed decisions in RDS/JSON, package versions, and session info.
- Per-method cell IDs, retention/failure status, cluster IDs, unknown
  biological labels, Seurat objects, marker tables, filtered top-30 evidence,
  UMAP coordinates/plots, audit decisions, and scAgentKit script trace.
- `steps.csv` with success/failure, warnings, and elapsed seconds;
  `method_status.csv`, `annotation_status.csv`, and `run_status.txt`.
- `method_comparison.csv` with barcode order, cluster agreement/ARI, and
  maximum absolute PCA/UMAP differences. Biological label agreement is
  unevaluated because annotation is not run.
- If truth is supplied, an independent `evaluation/` copy and
  `cluster_vs_reference_ari`. This compares a partition with reference
  labels; `annotation_accuracy` remains `NA`.
- On replay, `replay_checks.csv` comparing barcode order, clusters, labels,
  markers, PCA, and UMAP with the original run.

Replay uses the saved sampled count matrix, barcode order, RNG state
configuration, and decisions; it does not resample or call a provider.
It requires a successful prior run, identical R and package versions,
identical harness source, identical installed scAgentKit/agentomicsCore
code checksums, and the saved count checksum. Exact same-cell and cluster
checks plus numerical PCA/UMAP differences below `1e-8` determine success.
Package fingerprints use paths relative to each package root, so an exact
copy of the installed library can be replayed from a different directory.
Source reinstallation can change `Built` timestamps and lazy-load files;
strict byte verification requires the saved installed-library snapshot.
Cross-platform or different-BLAS numerical reproducibility is not claimed.
The audit script snippets remain an inspection trace; this harness is the
executable replay entry point.

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

`bench_01_pc_selection.R` is a separate partial prototype. Review its dataset
loading, ground-truth mapping, provider configuration, and metric definitions
before attempting a run. The numbered scripts other than `bench_01`
intentionally stop as stubs.

Separate prerequisites for prototype development (install only in an
authorized environment; these commands are not part of the offline harness):

```r
remotes::install_github("ChanghaoKan/agentomicsCore", ref = "v0.1.1")
remotes::install_github("ChanghaoKan/scAgentKit", ref = "v0.4.0")
remotes::install_github("satijalab/seurat-data")
```

Set only the provider keys required for your chosen experiment through your
normal secret-management mechanism. Never commit them to this repository.

Then:

```sh
Rscript benchmark/bench_01_pc_selection.R --datasets pbmc3k \
        --out_dir   results/bench_01/
```

The prototype requires an already installed local SeuratData PBMC3k
dataset and the development-only `optparse` package. Data installation is
disabled unless `--allow_data_download` is supplied. Providers default to
an empty list. Only after authorization for paid calls and data upload,
add `--allow_llm --providers claude,deepseek` to run the provider paths.

The partial harness is intended to write under `results/<bench_id>/`, but its
outputs and schemas are not frozen.

## Reporting

`bench_99_collate.R` is currently a stub and does not generate figures or
captions.

## What is NOT in here

- The published manuscript text (lives in a separate `paper/` repo).
- Bundled frozen public datasets (the PBMC harness accepts local input and
  saves its sampled matrix; the prototype's download step is opt-in).
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

## Planned provider comparison (not run)

After approval of the provider, call budget, and public aggregate data scope,
the first experiment will compare DeepSeek and Grok text annotation in
`guided` and `independent` modes using the same frozen PBMC3k marker evidence,
clusters, background, common JSON mode, and output limit. The current fixed
full-data run has 9 clusters: one sample per cluster per mode per provider
means 36 attempts, with zero JSON/schema or HTTP retries and manual review of
disagreements. No provider quality ranking is assumed in advance.

Use provider-neutral per-attempt records for requested/reported model and
snapshot, prompts and reference hashes, local/API seeds, temperature, caps,
raw output, parsing/schema/citation status, timing, tokens, and missing-cost
flags. Compare annotation accuracy at a predefined label granularity with
independently stored truth, unknown rate, failures, wall time, tokens, and
cost. Assess stability only with separately budgeted repeated real calls.
Mock responses establish control-flow behavior only. Preserve each method's
labels and unknowns; replay saved decisions without constructing a provider
or sending API requests.
