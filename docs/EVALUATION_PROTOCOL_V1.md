# Prospective offline evaluation v1

Registered before new QC/annotation implementation or outcome inspection. This
protocol supersedes the narrower future-work scope in BENCHMARK_PROTOCOL_DRAFT.md
for this experiment only. It is a development evaluation, not a clinical claim.
PR #11 remains draft until the effect and installation gates finish.

## Immutable baseline and provenance

- Baseline commit: `b3227303a14bf68bbfb643b090998aa81614d8d2`.
- Scientific/runtime source: `2d8c5482197a4200650f4b3d0fa574b420a5c207`;
  subsequent baseline commits only change the browser acceptance harness.
- Existing ordinary archive SHA256:
  `4c288a6c132b37769d3c36e123ed822ca5633b2e7537946ccfdba937e6bc934b`.
- New methods are optional, individually committed, and compared against that
  baseline. Record source/tree, package versions, OS/BLAS, seeds, input/member
  SHA256s, exact cell and gene IDs, references and artifact hashes in each run.
- Do not mutate old saved project hashes, approvals, checkpoints or archives.
  Comparison projects are new siblings from the same verified original counts.

## Data, order and eligibility

First run PBMC3k alone before expanding to the other two datasets. Outcomes from
PBMC3k are development results; changes after inspecting them must be declared.
Before reading expanded outcomes, freeze dataset and reference hashes and label
mapping. Ineligible analyses remain unavailable with reasons, not synthetic data.

1. **PBMC3k**: official 10x Cell Ranger 1.1.0 filtered hg19 matrix, healthy donor,
   CC BY 4.0, 2700 called cells; no independent cell-quality or cell-identity truth.
   Source: https://cf.10xgenomics.com/samples/cell/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz
   Dataset: https://www.10xgenomics.com/datasets/3-k-pbm-cs-from-a-healthy-donor-1-standard-1-1-0
   Existing local download is 7,621,991 bytes, SHA256
   `847d6ebd9a1ec9a768f2be7e40ca42cbfe75ebeb6d76a4c24167041699dc28b5`.
   Member hashes are in benchmark/evaluation-v1/input-manifest.json.
   Confirm the official download has identical bytes before running. Input is
   counts only, one declared sample/capture; never split it into fake samples.
   Tutorial cluster names, chosen resolutions and prior developer labels are
   not truth and are excluded from all analysis objects and scoring targets.
2. **ifnb**: official SeuratData IFNB distribution (Kang interferon experiment).
   Provision counts and metadata separately; record author publication, version,
   source and hashes before outcomes. Keep condition separate from donor/capture;
   use sample/donor only if explicitly documented. Author cell labels, if supplied,
   are evaluator-only agreement targets, not independent biological truth.
   Without reliable sample mapping, cross-sample QC/HVG claims are unavailable.
3. **Non-blood**: Baron human pancreas GSM2230757 (GSE84133), unnormalized UMI
   counts and separate author labels, using the author/GEO route described in
   BENCHMARK_PROTOCOL_DRAFT.md. Confirm applicable redistribution terms; store
   attribution, source, byte hashes and cell joins. One specimen cannot support
   cross-donor generalization. Author labels remain evaluator-only.

All cells are used in the first PBMC3k pilot. Expanded datasets: all cells up to
5000, otherwise first 5000 ordered by SHA256(`evaluation-v1|accession|cell_id`),
then cell_id. Freeze selected IDs before labels; report partial-capture status
and disable capture-total doublet heuristics on subsets. No paid inference,
external count upload or model API is permitted; downloads are public data only.

## Baselines and frozen analysis

Use one required external comparator: **SingleR + official celldex Blueprint/ENCODE
human reference**, if its official dependency installation is compatible with the
approved environment; otherwise report exact blocker before replacing it.
Freeze reference bytes, release/name/version and main/fine labels before prediction.
Blueprint/ENCODE is a blood reference: pancreas comparison requires an appropriate
independent reference (e.g. celldex HPCA) and an explicit coverage limitation,
never forcing pancreas into blood types. No reference derived from the query
study, query cells or tutorial labels is eligible as independent validation.

Baseline coordinator: explicit human species/raw RNA counts, known sample facts,
minimal positive-count prerequisite, `keep_all` quality policy, no batch correction,
no doublet call, LogNormalize(10000), global vst HVG 2000, ScaleData, at most 50 PCs,
computed-top50 80% policy, seed 42, measured resolutions 0.2,0.4,0.6,0.8,1.0,1.2;
predeclared selected resolution 0.6. UMAP is visualization only, not a metric.
Use approved public API decisions and separate approvals; no provider responses.
Without human-reviewed annotation, the coordinator baseline remains Unknown;
reference coverage candidates are scored as candidates, never upgraded to labels.

SingleR runs on the same normalized cells/genes with frozen reference and default
pruning, serial execution. Preserve raw/pruned labels, full scores and parameters.
Map main labels to **T, B, NK, Monocyte, Dendritic, Granulocyte, Other, Unknown** for
blood; fine labels to exact reference main/fine vocabulary. Fixed mapping:
T-cells/CD4+ T-cells/CD8+ T-cells -> T; B-cells -> B; NK cells -> NK;
Monocytes -> Monocyte; DC/pDC -> Dendritic; neutrophils/eosinophils/basophils ->
Granulocyte. Any unlisted main label is Other; pruned NA is Unknown. Save literal
mapping before scoring. Pancreas broad map: alpha,beta,delta,gamma/PP,acinar,
ductal,endothelial,stellate,immune,Other,Unknown; refine from source vocabulary
before expanded outcomes, never by an optimal label permutation.

## Prespecified changes, sequence and comparison metrics

Each stage has a focused software regression plus the same PBMC3k numerical
comparison. Expand biological interpretation only after appropriate data exists.
No test count or feature count is evidence of biological improvement.

| Stage | Optional change | Prespecified evidence and boundary |
| --- | --- | --- |
| A | Downloader timeout/retry | Bounded retries for transient HTTP/network errors, fail fast on permanent errors/hash mismatch, exact bytes and README load/version/path assertions. Independent commit; no scientific change. |
| B | Sample QC comparison and draft preselection | Compare group-level median/count/feature/MT summaries across actual comparable samples; robust outlier score requires >=5 groups, otherwise descriptive only. Within-group cell MAD is reported separately. Never treat IFN condition as technical quality. Compare exact per-sample retention and tail flags for all existing presets; preselection is only an editable draft, requires separate save/approval. No auto-deletion or universal best preset. |
| C | PC elbow and k +/- 5 | Record deterministic maximum-distance elbow on computed variance curve; recompute neighbors/clusters at k-5,k,k+5, bounded to valid actual PCs (>=2), same HVGs/cells/seed/resolution. Report ARI, cluster counts/sizes and marker-set Jaccard; no optimum inferred from maximal stability. |
| D | Sample-aware HVG | If >=2 actual comparable samples: top2000 vst each eligible sample, consensus order by selection frequency then median within-sample rank then literal gene; retain2000. Eligible sample>=30 cells, unavailable cases explicit. Compare overlap, sample contribution, selected-gene variance and downstream partitions; do not substitute treatment as sample. |
| E | Resampling and resolution | Five prespecified 80% subsamples, seeds42..46, rebuild HVG/PCA/graph, match shared-cell partitions using ARI and per-cluster best Jaccard/coverage. Cells are not donor replicates. If outer resolution has no nontrivial partition or scan trend is boundary-limited, optionally extend once to0.1 and1.4/1.6; cap1.6. Keep selected0.6 baseline; no optimization against labels. |
| F | Ambient/mixed lineage | Report classic-panel normalized expression, pct detected, within-cell coexpression and background ambiguity. Mixed lineage can be state, doublet or ambient; marker presence alone does not diagnose contamination. SoupX only with independently verified raw+filtered matched capture input; filtered-only is unavailable. decontX only optional with compatible approved dependencies and recorded assumptions. Preserve original counts, separate corrected assay/project, record fractions and before/after counts, never overwrite checkpoints. |
| G | Annotation evidence | Panel pct/mean and differential direction; citation must have positive saved FC plus positive pct1-pct2 to count as positive numerical support. This is not label semantic truth. Cross-sample consistency requires adequate groups, report each sample's effect/support without treating cells as replicates. Fisher one-sided enrichment uses unique assayed genes actually eligible in the marker test as universe, intersect query+reference with that universe, save a/b/c/d and BH correction across all tested labels; keep absolute hits/coverage/denominator. Missing background means unavailable, not a p-value. |

Classical blood panel (fixed before outcomes): T CD3D/CD3E/TRAC; B CD79A/MS4A1/CD37;
NK NKG7/GNLY/PRF1; monocyte LST1/S100A8/FCN1; DC FCER1A/CD1C/CST3;
platelet PPBP/PF4. Pancreas: alpha GCG/TTR; beta INS/IAPP; delta SST;
PP PPY; acinar PRSS1/CPA1/CTRB2; ductal KRT19/KRT8/KRT18; endothelial
PECAM1/VWF/KDR; stellate COL1A1/COL1A2/DCN. These are descriptive overlapping
panels, not disjoint truth, universal thresholds or a classifier. Non-detection,
missing genes, ambient expression and related-lineage overlap remain separate.

## Outcomes, no-help/regression and default gate

Primary PBMC3k outputs: exact retention and counts, unknown/failure coverage,
reference agreement (explicitly not accuracy), candidate/citation support
availability, contradictions, stability and computational resources. Report a
full confusion matrix and all denominators, raw and pruned reference labels,
per-type support and rare-type retention. Accuracy/F1 are **null** when no
independent labels exist. With frozen author labels in expanded data, report
broad/fine exact agreement, macro-F1, per-type recall, coverage and end-to-end
correct-label yield over original evaluable cells; unknown/excluded/failed are
misses, not dropped. Those are author-label agreement, not verified truth.

- No help: only more outputs/tests, no prespecified evidence gain; unchanged
  agreement with increased ambiguity/runtime; zero-coverage selective accuracy;
  tiny reference denominators or Fisher p-values alone; same-sample stability
  alone; a reference candidate agreeing with the reference that generated it.
- Material regression: any authoritative count/checkpoint mutation, silent
  sample/condition confusion, invalid p-value background, unsupported label
  promotion, >=0.02 absolute reduction in author-label macro-F1 or correct-label
  yield, >=0.05 rare-type recall/retention reduction (where n>=20), or >2x runtime
  or peak memory without a measured benefit. Report all, do not hide failed runs.
- Evidence availability improvements can justify an optional diagnostic, not an
  automatic scientific default. Default adoption needs no material regression
  across all eligible datasets and independent review of a meaningful measured
  benefit; PBMC3k reference-only agreement cannot satisfy a biological default
  gate. Improvements selected after reading results are exploratory.
- Human effort: measure only future independent participants with timer start at
  opening frozen evidence and stop at separately saved final review; exclude
  compute/wait interruptions, log corrections/abstentions and counterbalance.
  No participants in this pilot => human time and savings **not measured**.
- Cost: inference calls0, model cost US$0; record measured process wall/user time
  and peak RSS, download bytes and any known infrastructure charge separately.
  Do not invent human time or zero cloud cost where billing is unknown.

## Installation, publication and completion checklist

- [x] Push baseline and create draft PR #11; remote b322730 verified.
- [ ] Commit this protocol and input manifest before implementation/outcome reads.
- [ ] Verify official PBMC3k bytes, provision compatible official comparator.
- [ ] Complete smallest baseline; report missing truth/unsupported comparisons.
- [ ] A through G as separate issues/commits with old/new paired artifacts.
- [ ] Freeze/execute ifnb and non-blood extensions before default conclusions.
- [ ] Current final SHA R/Python/Node/installed browser and hosted CI.
- [ ] Fresh Linux empty-library acceptance on existing hosted CI/container;
      Mac private library reuse is explicitly insufficient.
- [ ] Summarize neutral/negative results and keep harmful changes non-default.

Do not dispatch release workflow publication, merge, delete old draft releases,
generate credentials, change server auth, send data to models or incur inference
fees. Public CI normal operation is authorized; any new security/environment or
paid-resource requirement must be reported concretely. Optional method failures
remain visible. A blocked or scientifically ineligible stage cannot be checked
as complete merely because a helper exists.
