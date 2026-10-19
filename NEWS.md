# Development (unreleased)

- Modern projects require explicit reference species/tissue fields and study
  scope, exclude all-tissue records, and show a plain zero-match next action.
  Existing low-level scope behavior remains explicitly recorded for legacy
  adapters; a new modern project always selects strict scope.

- Annotation query pools rank fold change first, then detection difference.
  Configurable shared ribosomal/mitochondrial symbol exclusions apply only to
  that pool; complete marker results remain intact. Save exclusion parameters
  and observed excluded feature IDs with the pool evidence.

- Remove the legacy HTTP/IP CellMarker fallback. Until the fixed official
  HTTPS file has a verified checksum, provide a clear waiting message and
  explicit local XLSX import with SHA256 provenance. Require species/tissue,
  report zero matches, and never authenticate a publisher URL from a sidecar
  or silently expand the tissue scope. No CellMarker data is redistributed.

- Default ontology mapping uses the unmodified, SHA256-pinned Cell Ontology
  v2026-06-08 base asset, bundled with CC-BY-4.0 attribution and license.
  There is no latest-version network fallback. Ambiguous exact labels/synonyms
  remain unresolved, as do fuzzy and obsolete matches.

- With explicit creation-time project transfer consent, stage one automatic model
  draft per saved evidence snapshot. Strict exact-payload consent stays explicit.
  Saved attempts, uncertain accounting, unsaved edits and unavailable budgets
  prevent automatic requests; adoption and all scientific approvals stay human.
  Explicit offline mock scope uses a distinct simulation request identity.

- Keep the standard raw project's measured-resolution approval mandatory for
  model drafts. Explicit advanced no-scan setup remains separate; models cannot
  disable a required gate. Rare declared metadata groups or literal cell-ID
  labels/context block only the optional provider path, leaving local review
  available and preserving the complete source evidence.

- Model adoption retains explicitly supplied and later saved human strategy
  choices and annotation rows. Versioned controls and additive adoption receipts
  record which fields were retained; the raw model response is unchanged.
  A merged draft is revalidated and still grants no scientific approval.

- Persist concise per-choice strategy reasons for QC, doublets, cycle, batch,
  HVGs, PCs, clustering and UMAP. Modern model drafts require all reasons.
  Each is editable without replacing other draft fields; saved proposals and
  all scientific approvals remain bound to the exact complete version.

- Modern raw entry attempts eligible S/G2M evidence, with regression none by
  default and explicit unavailable reasons for missing genes/species support.
  Add doublet auto/off/flag/remove modes: auto/flag keeps cells, and missing
  called-cell/capture/dependency/cohort facts remain unassessed. Remove requires
  eligible fixed predictions and exact human strategy approval. No droplet
  calling, capture inference or cycling-cell deletion is introduced.

- Use one conservative QC fallback: a complete eligible grouped MAD panel
  starts with conservative_and3; otherwise keep all cells and explicitly mark
  quality unassessed. Zero-count cells are not silently dropped by this draft.
  Cancel independent OR automatic prefill; saved and edited choices remain
  unchanged and all filtering still requires the complete human strategy approval.

- Prepare a persisted sample-role draft from five whitelisted metadata columns.
  A sole complete candidate can be a documented sample fallback; multiple
  candidates require author choice and never imply a technical batch. Model
  summaries contain group sizes and common fixed-vocabulary values only, not
  IDs, free-text metadata or rare labels. Unmapped input no longer receives
  automatic pooled MAD; choosing facts rebuilds grouped evidence without approval.

- Preserve original cell metadata, column locations and exact cell-ID mapping
  separately in modern-entry Seurat checkpoints. A collision-safe hashed misc
  record protects prior labels before new reviewed output fields are written.
  Direct sc_run keeps its existing fresh-column default; protected record or
  cell-scope changes still block annotation.

- Automatically join valid Seurat v5 counts/data partitions within the selected
  assay at input. Every source value, feature set and exact cell partition is
  checked and a join receipt is saved. Mixed exact/split layers, overlapping or
  incomplete cells and incompatible feature sets remain blocking errors.
  Export and checkpoint readers still require exact protected layers.

- Use existing aligned human/mouse feature-symbol annotations for mitochondrial
  QC on Ensembl identifiers. Missing, partial, species-conflicting or ambiguous
  mappings remain conspicuously unavailable, never a fabricated zero percentage.
  No annotation database is downloaded and input count features remain unchanged.

- Add explicit creation-time aggregate transfer consent bound to provider,
  category list, prompt version and project USD cap. Exact previews and hashes
  remain available; requests outside that scope still require strict review.
  This consent grants no scientific approval and is not inherited by children.
  Suggestion accounting now includes remaining USD beside used/held amounts.

- Let sc_start save an explicit provider, budget and transfer policy, or detect
  exactly one configured vendor key. Missing or ambiguous keys use a visible
  manual fallback. Startup prepares a local draft without sending requests;
  reopening retains the saved policy, and scientific approvals remain human.

- Support an explicit OpenAI-compatible HTTPS endpoint through the existing
  agentomicsCore factory. Destination and key environment name join the exact
  request hash; keys remain runtime-only. No agentomicsCore changes are needed.
  Three scientific approvals, transfer consent and budget checks remain required.

# scAgentKit 0.8.0 (experimental)

## Breaking API changes and rebuilding projects

- Remove 36 function exports and the AgentSeurat class. This is the planned
  earliest removal milestone (0.8.0), not a compatible 0.6.x/0.7.x patch.
  See docs/API_CONSOLIDATION.md and inst/api-contract.json for the exact list
  and retained Seurat/table return types. No compatibility facade is provided.
- Keep original input, project, checkpoints, package build and environment.
  Rebuild a development project in a new directory and review strategy,
  measured clustering and annotation independently. Do not edit authority,
  approvals or implementation hashes to force continuation. Old environments
  can still be restored separately; old tags/assets are not modified.
- The standard raw-count path now has three scientific approvals. Defaults,
  confidence heuristics and numerical parity are not biological validation.

## Single project workflow

- Extract shared marker/reference/validation/ARI kernels and retire 36 redundant
  public functions plus the AgentSeurat class. Useful standalone tools accept
  Seurat/tables; project prepare/export/review interchange remains.
- Development test projects may be rebuilt. The implementation hash changes;
  saved project hashes and approvals must not be edited to force a resume.
- Repository examples and benchmark drivers now use the reviewed engine. Published
  Git/release artifacts and frozen baseline evidence are unchanged. See
  docs/API_CONSOLIDATION.md and inst/api-contract.json.


## Optional scientific diagnostics (effect evaluation pending)

- New raw strategy projects keep applicable classic mean/detection evidence for
  explicitly declared human blood/PBMC or pancreas, separate from opt-in
  rebuilding diagnostics. Unknown tissue/species and absent panel genes are
  recorded as unavailable/missing. PC sensitivity, resampling, extra resolution
  extension, sample-consensus HVGs and automatic QC draft preselection stay off
  by default. Ordinary PCA/80% selection, resolution scan/tree and applicable
  QC/citation/Fisher evidence remain; SoupX/decontX stay optional R-only calls.

- Add explicit per-sample HVG consensus, sample-median QC comparisons, guarded
  unsaved/unapproved OR draft preselection, PC elbow and optional k+/-5,
  resampling and finite resolution-extension experiments.
- Add local panel expression/detection, broad-expression and cross-sample
  contrasts, positive numerical citation gates, and eligible-background Fisher
  evidence while retaining absolute hits and reference coverage.
- Add separately returned SoupX/decontX count corrections with input guards and
  before/after provenance. Original counts/checkpoints are never replaced.
- Extend the public browser entry with explicit optional scientific settings;
  unsupported pipelines or inputs remain unavailable. No biological improvement
  or human time-saving claim is made before the registered paired evaluation.
- Release acceptance retries transient downloads with bounded attempts and an
  explicit1800-second timeout; permanent errors and checksum mismatches fail.

## Earlier intermediate legacy review work (historical)

- R review printing now gives bounded summaries with explicit access to the full
  sealed `snapshot$view` and `snapshot$annotations`; it does not remove evidence,
  audit records or weaken hashes. This is separate from the HTTP display repair.
- Grounded declared counterevidence is a review hint and no longer alone makes
  an accepted, grounded legacy proposal unusable. Citation validity, review hints,
  label usability and explicit reviewed-workflow approval are separate. Invalid
  citations, absent support and unresolved/action-blocked proposals remain blocked.
- `annot_apply()` retains existing per-cell labels for blocked **and unmapped**
  clusters; only eligible mapped cells or explicit manual overrides are replaced.
  If the target column is absent, unreplaced cells start as `Unannotated`.
  Manual overrides are audited separately and do not establish model success.
- `hybrid_confidence` remains the raw weighted numeric heuristic; it is neither
  calibrated probability nor writeback permission. Its raw band is saved as
  `hybrid_confidence_raw_label`; effective `hybrid_confidence_label`/`confidence`
  and `label_usable` can be low/false despite a high raw score. For example a raw
  0.710 can coexist with blocked fabricated support. Preserve raw response audits.
- Before upgrading, preserve the original object/project and exact environment.
  Review retained labels and new usability/review fields rather than assuming a
  nonempty label was newly accepted. Use explicit manual overrides for a deliberate
  legacy label change; use a new project with independent approval for the reviewed
  workflow. Never rewrite old project hashes/approvals/checkpoints to force resume.

## Breaking changes

The reviewed workflow and helper fingerprints change. Preserve each existing
project and its exact original package/dependencies; restore that environment
to continue, or start a new project from the original input and review it again.
Never edit saved hashes, approvals or authoritative checkpoints to force resume.
The published v0.6.0 tag and assets remain unchanged.

- The main entry offers measured sample-aware QC/MAD candidates, a disclosed
  at-most-50-PC internal 80% policy and measured resolution-tree review before
  final clustering selection. These are review options, not biological optima.
- Add local evidence-guided QC, PC, resolution and optional-path candidates.
  QC uses measured flag combinations and exact impacts without a universal
  preset or score. PC advice distinguishes pending rules from actual internal
  top50 80%/85% crossings; resolution comparisons expose conflicts and equivalent
  memberships without an optimality score. Explicit author corrections remain
  necessary, and unsupported or missing assessments remain visible in results.
- Saving declared facts is not scientific approval. Applying a candidate edits
  only a local draft; saving rebuilds its R review before explicit approval.
  The default raw scan retains initial-strategy, measured-resolution and
  annotation approvals. Missing optional facts/dependencies affect that path,
  without certifying that an unexecuted assessment was performed.
- Annotation coverage, raw weighted confidence and citation checks do not
  establish calibrated probability, label semantics or independent accuracy.
  Invalid model evidence cannot promote an automatic authoritative label;
  original proposals and failed audits remain available for review.
- An evidence-backed source lock and installed-archive real-browser acceptance
  supplement environment records; full OS reconstruction is not promised.

# scAgentKit 0.6.0 (2026-10-18)

## Saved-project compatibility and metadata priors

The audited implementation changes the implementation hash relative to earlier
code. A saved project whose recorded hash differs from the running code or its
fingerprinted dependency versions cannot continue execution, approval or review
under that implementation. `sc_run_resume()` checks this before continuing,
including for a completed run. A package version number alone is not the test.

Keep the original project, inputs, package build and dependency versions. To
continue that project, restore its original environment and exact package build;
otherwise create a new project directory from the original input and review the
analysis again. Do not edit project hashes, approvals or checkpoints to force a
resume. Previously completed objects still require their recorded file-integrity
checks; changing convenience exports does not authorize changing authority.

Author-label metadata priors are off by default in legacy annotation and
resolution recommendation. `use_metadata_prior=TRUE` is an explicit opt-in;
independent annotation mode continues to exclude these priors.

## Legacy workflow migration

Legacy `annot_subcluster()` replies now use the same eight-field annotation
schema and optional cluster echo as `annot_llm_annotate()`. Old three-field
`label` replies fail visibly. Marker citations, failed attempts and lineage
calculation errors are retained for review; one failed lineage prevents an
overall successful decision while preserving its previous labels and result.

The legacy `qc_*` execution wrappers, basic-analysis `sc_*` wrappers and
recommendation functions, `annot_match_reference()`, `annot_llm_annotate()`,
`annot_apply()` and `annot_subcluster()` now emit lifecycle deprecation warnings
with concrete reviewed `sc_run` migration paths. They remain exported and callable.
The first published deprecation is **0.6.0**. The exports remain available through
**0.6.x** and **0.7.x**; removal is planned no earlier than **0.8.0**, subject to
the migration notice in that release. Utility accessors, reference readers, comparison helpers and current
project APIs are retained. The reviewed coordinator has explicit configuration,
proposal and approval boundaries; these are not signature-compatible replacements.
Manual split/merge and gene-removal helpers have no one-to-one coordinator
equivalent. The latter does not authorize input-gene deletion in `sc_run()`.

- Add independently reviewed raw-count child projects from frozen parent cluster selections, with explicit QC/batch/cycle/reference choices and no inherited parent embedding or cluster truth.
- Apply reviewed child subtypes by literal cell ID to new parent derivatives, with stale/conflicting scope rejection, idempotent receipts, linked immutable application versions and undo; the original parent remains unchanged.

- Add an explicitly reviewed, design-guarded Harmony strategy stage with a fresh embedding, RNA-based marker evidence and cached-PCA recovery; correction still defaults to `none` and processed entry reuses its supplied foundation.
- Add `.80`/`.85` `computed_top50` policies with saved actual candidate counts and a disclosed first-`min(50, computed PCs)` variance denominator; no full-expression variance or universal optimal-dimension claim.

- Add a first-use R helper and offline raw-input example with saved inspection snapshots, typed decisions, context/provider configuration and fresh-process recovery.
- Reject annotation-column conflicts before computation and report unreadable input RDS files at entry. Missing built-in provider credentials pause for configuration before dispatch or reservation; existing caches remain readable without a key.

- Add server-side `sc_run` with typed QC/annotation proposals, exact approvals, checkpoints and headless resume.
- Add aggregate-transfer previews, provider budget holds/caches, input/config/implementation binding, and explicit scientific result acceptance.
- Reuse existing Seurat preparation, marker/reference and project bundle functions; preserve source objects and annotation columns.
- Add immutable QC impact previews with exact cell scope, actual sample/capture distributions, filter overlaps, missing measurements, and explicit comparison rules.
- Bind QC decisions to preview parameters, input, evidence, implementation and revision; changed previews reject stale decisions. Support audited keep/revise/repreview/reject in R and the optional loopback workbench connected to the same run directory.
- Add immutable annotation review with exact per-cluster cell scope, supplied marker statistics, saved independent reference provenance, and honest mock/provider/manual source records.
- Add a unified project workbench and `sc_run_review()` for QC/annotation keep, revise, reject and executed annotation undo. Project, input, proposal, review and revision are checked under one R lock; no review action computes or dispatches a provider.
- Browser review saves decisions only; run subsequent computation with `sc_run_resume()` in R. Batch correction requires the separate explicit guarded strategy choice described above.

# scAgentKit 0.4.0.9000 (local development)

* Parse cleaning recommendations as strict JSON; preserve the caller's deletion
  setting, retain cells on failure, and save prompts, responses, cell IDs,
  final labels, and successful or failed audit records for offline replay.
* Validate annotation, PC, resolution, and batch recommendation schemas; reject
  malformed types, invalid enums, unsupported candidates, and wrong cluster IDs.
* Use the same differential and cycling rescue evidence in annotation prompts
  and marker-citation checks. Model failure remains visible for analyst review.
* Add optional independent database/LLM initial assessment while retaining
  reference-guided annotation as the default. Add offline evidence review with
  explicit label mapping and agreement, conflict, or unknown outcomes.
* Preserve reference source provenance, apply available species filtering, and
  handle empty references or no positive marker matches without crashing.
* Repair the PC benchmark API calls and add an offline PBMC3k Seurat5 comparison
  and saved-decision replay harness. Reference labels stay outside analysis
  input; mock tests are not annotation accuracy evidence.

---

# scAgentKit 0.4.0 (2026-07-21)

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
