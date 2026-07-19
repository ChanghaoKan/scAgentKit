# scAgentKit 0.4.0 (2026-07-20)

* Make `annot_apply()` non-destructive by default: clusters flagged by an
  LLM as `reject` are retained unless the analyst explicitly sets
  `drop_rejected = TRUE` after review.
* Restore `R CMD check` CI, correct clean-install instructions, and pin the
  compatible `agentomicsCore` v0.1.1 release in package and Docker metadata.
* Repair the PBMC3K vignette and examples to match current public APIs.
* Pass the selected PCA dimensions and Harmony iteration limit through the
  documented `dims.use` and `max.iter.harmony` arguments.
* Clarify that marker-citation checks aid review but do not guarantee cell-type
  annotation accuracy.
* Reframe generated scripts and the incomplete benchmark directory as
  reviewable prototype artifacts rather than validated end-to-end replay or
  performance evidence.
* Remove local session history and stale release/citation metadata.

---

# scAgentKit 0.3.0 (2026)

scAgentKit remains an experimental, human-in-the-loop research-software
prototype. Decision records and generated script snippets support review;
they do not by themselves establish scientific validity or exact replay.

This release factors the omic-agnostic infrastructure into a new package,
**`agentomicsCore`**, on which scAgentKit (and future
`atacAgentKit`, `chipAgentKit`, `spatialAgentKit`) all depend. The
methods-paper framing changes accordingly: scAgentKit becomes the first
single-cell *instantiation* of the agentomicsCore framework, not a
standalone product.

## What moved out of scAgentKit (now in agentomicsCore)

* S4 container (`AgentSeurat` is now a subclass of `agentomicsCore::AgentOmics`)
* Decision log + generated script export (`record_step`,
  `find_in_decisions`)
* Multi-provider chat factory (`chat_claude`, `chat_openai`,
  `chat_deepseek`, `chat_grok`, `chat_qwen`, `chat_kimi`)
* Best-effort LLM token tracking when providers return usage metadata
* Checkpoint I/O (`save_checkpoint`, `load_checkpoint`)
* Generic HTML report renderer (`render_report`, with an `extras` hook)

## What stayed in scAgentKit

Everything single-cell-specific: all `qc_*`, `sc_*`, `annot_*` functions,
plus the wrapping `report_html()` that calls `render_report()` with
scAgentKit's domain-specific section renderers as `extras`.

## Compatibility

* `AgentSeurat` continues to be a class (now an S4 subclass of
  `AgentOmics`), so existing checkpoints load and existing code that
  checks `methods::is(obj, "AgentSeurat")` continues to pass.
* All previously-internal helpers (`.record_step`, `.find_in_decisions`,
  `.attach_step_tokens`, `.with_token_scope`, `.token_record`,
  `.token_records_summarise`, `.esc`, `.token_state`) remain available
  in scAgentKit via an internal alias layer
  (`R/imports.R`). Older checkpoints should still be backed up and tested
  before replacing the originals.
* All previously-exported symbols from scAgentKit
  (`scAgentKit::chat_claude`, `::save_checkpoint`, `::get_decisions`,
  etc.) continue to resolve, via re-exports.

## Required action when upgrading

Install both packages:

```r
remotes::install_github("ChanghaoKan/agentomicsCore")
remotes::install_github("ChanghaoKan/scAgentKit")    # v0.3.0
```

Then, if you have saved AgentSeurat checkpoints from v0.1.x / v0.2.x,
optionally migrate them in-place:

```r
obj <- load_checkpoint("old.qs")
obj <- upgrade_checkpoint(obj)
save_checkpoint(obj, "old.qs")
```

---

# scAgentKit 0.2.0 (2026-05-22)

This release added experimental token-accounting, parallel annotation,
checkpoint-version, and evaluation scaffolding. These features still require
provider- and dataset-specific validation.

## Breaking

* `AgentSeurat` now has two extra slots: `@version` (the scAgentKit
  release that constructed the object) and `@token_usage` (per-step
  LLM consumption). Checkpoints saved under v0.1.x load with these
  slots empty; call `upgrade_checkpoint(obj)` to populate them.

## New features

* **Token usage tracking.** Built-in chat factories record provider-returned
  token metadata after successful API calls. Inspect via
  `token_usage_summary()` (global) or
  `get_token_usage(obj)` (per pipeline step). Anthropic and OpenAI-
  compatible usage schemas are both normalised to
  `{input_tokens, output_tokens, cached_tokens}`. Provider tag is
  derived from base_url so DeepSeek / Qwen / Kimi / Grok / Groq all
  show up distinctly.
* **Parallel annotation.** `annot_llm_annotate(parallel = TRUE)` runs
  per-cluster LLM calls under `future::plan()`. Token records from
  worker processes are merged back into the parent's accumulator.
  Requires `future.apply` (Suggests). With `temperature = 0` and
  `n_samples = 1` does not eliminate provider-side non-determinism.
* **Cell Ontology mapping.** New `annot_map_to_cl()` resolves
  annotations to CL identifiers via exact name + synonym match (no
  fuzzy / embedding similarity by design — see the docstring for the
  rationale). New `cl_lookup()` for interactive exploration. Optional
  dep via `ontologyIndex`.
* **Checkpoint versioning.** `upgrade_checkpoint()` repairs older
  AgentSeurat objects loaded from disk.
* **First vignette.** `vignettes/scAgentKit-pbmc3k.Rmd` walks through
  the full pipeline on PBMC 3k.

## Infrastructure

* **GitHub Actions CI** (`.github/workflows/R-CMD-check.yaml`) runs a single
  Ubuntu `R CMD check` job.
* **Docker development environment.** `Dockerfile` pins the R base image and
  core release reference; CRAN/Bioconductor dependencies resolve at build
  time unless an external lock or image digest is used.
* **Evaluation scaffolding.** `benchmark/` documents six planned studies.
  `bench_01_pc_selection.R` is a partial prototype; the other scripts are
  explicit stubs and no results are included.

## Smaller things

* `show(<AgentSeurat>)` prints version and total token usage one-liner.
* `get_token_usage(obj)` accessor.

---

# scAgentKit 0.1.24 (2026-05-21)

## Breaking
* `annot_llm_annotate()`: `strict_vocabulary` is now **opt-in**. When a celltype column is auto-detected in metadata, `expected_celltypes` is still extracted as a *prior* (the LLM is told to prefer these), but the strict-match constraint is no longer auto-engaged. To force the LLM to use the dataset author's exact vocabulary, pass `strict_vocabulary = TRUE`.

## New features
* `qc_mad()`: count and feature metrics (`nCount_RNA`, `nFeature_RNA`) are now MAD-filtered in **log10 space**, matching standard practice (Germain 2020; OSCA; Pijuan-Sala 2019). Percentage metrics (`percent.mt`, `percent.ribo`, `percent.hb`) remain in linear space (upper-only).
* `annot_llm_annotate()` gains an **ensemble** mode: `n_samples = 3` (or higher) calls the LLM multiple times per cluster and records majority vote, agreement fraction, and a `disagreement_flag`. Requires `temperature > 0` in the chat_fn factory to be meaningful.
* `annot_llm_annotate()` now **validates LLM-cited markers** against the actual input list. `supporting_markers` and `contradicting_markers` not present in the cluster's marker evidence are recorded in a new `hallucinated_markers` field and reduce the cluster's hybrid confidence.
* New **hybrid confidence** score: combines reference-overlap quality, marker specificity, hallucination rate, and proportion plausibility into a scalar in [0, 1]. Surfaced alongside the LLM's self-reported confidence with an automatic `confidence_disagreement` flag.
* `annot_subcluster()`: `n_hvg` and `n_pcs` accept `"adaptive"` (now the default), scaling with subset size on log10 curves. Fixed numeric values still work for explicit control.

## Reporting
* `report_html()` highlights clusters with `recommended_action == "flag_for_review"`, non-empty `contradicting_markers`, hallucinated markers, or confidence disagreement.

## Defaults
* `chat_claude()` default model bumped from `claude-sonnet-4-5` to `claude-sonnet-4-6`.

## Fixes & housekeeping
* Fixed `DESCRIPTION` Authors@R (given/family order and contact email).
* Fixed `CITATION.cff` (previously contained the shell heredoc instead of YAML).
* Removed stray `2.x` file at repo root.
* Added `NEWS.md`.

---

# scAgentKit 0.1.23 (2026-05)

## Internal versions (reconstructed from inline comments)

### 0.1.22
* `annot_subcluster()`: adaptive resolution curve tightened by 0.05 (was over-fragmenting T/NK at 22k cells in v0.1.21).

### 0.1.21
* `annot_subcluster()`: `subcluster_resolution = "adaptive"` is the new default (was a fixed 0.5).

### 0.1.18
* Diagnostic check in `annot_subcluster()` for corrupted `meta.data$cell_type` length vs `nrow(meta.data)`.

### 0.1.16
* `sc_resolution_recommend()`: multi-panel UMAP vision mode (clustree + UMAPs at representative resolutions). Strict constraint that `chosen_resolution` must be one of the panel resolutions actually shown.

### 0.1.14
* Re-prompt loop in `sc_resolution_recommend()` when vision constraints are violated on the first pass.

### 0.1.12
* `annot_llm_annotate()`: cycling-cluster lineage rescue. For clusters where cell-cycle genes dominate the differential markers, compute and surface high-expression non-CC, non-housekeeping genes as a "lineage rescue" list. Structured naming: `Cycling cells (lineage candidate: X)` / `Cycling cells (lineage uncertain)`.

### 0.1.11
* Initial cycling-cluster awareness flag passed into prompts.

### 0.1.8
* Seurat v5 S4 method-dispatch fix in subcluster scaling pipeline.

### 0.1.6
* `annot_llm_annotate()` and `sc_resolution_recommend()`: auto-detect a celltype column in metadata to populate `expected_celltypes` and `expected_n_celltypes`. (Note: v0.1.24 changes this from a strict constraint to a prior.)

### 0.1.0
* Initial public version. Atomic Seurat-wrapping tool functions, AgentSeurat S4 container, decision log, reproducible script export, multi-provider chat_fn factory, HTML report.
