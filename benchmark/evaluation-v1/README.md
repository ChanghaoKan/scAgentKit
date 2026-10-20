# Frozen public offline comparison

Read `docs/EVALUATION_PROTOCOL_V1.md` before execution. Inputs, cell selection,
label mappings and references are frozen before query outcomes. No model API,
tutorial identities, inferred donor/sample mapping or human time savings.
Raw matrices, reference objects, per-cell exports and full native artifacts remain outside Git.
Sanitized aggregate results and engineering evidence are in [results/report.md](results/report.md).

Provision official bytes with `fetch_inputs.py`, sparse Baron inputs with
`prepare_baron.py`, counts-only objects with `prepare_inputs.R`, and independent
reference marker lists with `freeze_references.R`. Preserve the download and
preparation receipts, including failed attempts. Use approved existing official
R dependencies; these scripts do not install software. Public references in the
pilot came from official celldex1.12.0/ExperimentHub, with SingleR2.14.2. The newer
celldex dependency failed to link on the Mac; its failed install was preserved.

`run_workflow.R input.rds NEW_OUTPUT LIBRARY VARIANT reference.csv DATASET`
executes the installed public workflow and all three explicit scientific
approvals. The only reviewed annotation is an explicit Unknown control. Reference
candidates are separate unreviewed outputs. `run_singler.R analysis.rds ref.rds
NEW_OUTPUT` provides the fixed offline comparator. Never reuse output directories.

`run_dataset.py EVIDENCE BASELINE_LIBRARY AFTER_LIBRARY DATASET` runs the fixed
variants once per dataset, preserves child exit/log receipts, and scores against
the original cell universe. PBMC3k's independently executed baseline/after pair
is reused only with complete receipts. ifnb condition is never used as sample;
sample-HVG is ineligible for PBMC3k/ifnb. Baron has four declared specimens and
is eligible for sample-HVG, but remains ineligible for the five-sample outlier
score. The baseline SingleR predictions stay the fixed reference comparison
for every variant; author-label agreement is evaluated separately for expanded
data. The actual frozen HPCA has no pancreatic-islet/alpha/beta/delta/PP/acinar/ductal target labels; nonblood annotation-quality validation did not pass. Literal mapped matches are not accuracy.

`evaluate.py` rejects foreign/duplicate IDs and keeps excluded/Unknown cells in
denominators. `--truth` means distributed author labels, not verified truth;
`--reference` explicitly reports classifier agreement with accuracy/F1 null.
No labels means no accuracy. `test_evaluate.py` checks denominator bookkeeping.

`run_ambient.R LIBRARY input.rds baseline-analysis.rds raw.tar.gz NEW_OUTPUT`
requires the complete matched PBMC3k capture and preliminary clusters; SoupX and
decontX remain separate outputs with original counts preserved. The companion
`summarize_ambient.R LIBRARY input.rds OUTPUT` verifies saved native hashes and
canonical literal IDs before descriptive expression/SingleR comparisons. It does
not rerun either fit. The initial pilot harness compared native Seurat order to
canonical sorted adapter order and failed after both native fits had saved valid
outputs; this failed record remains, and saved outputs were verified separately.

R receipts include wall/user/system time; dataset child receipts include actual
exit codes. A Mac sandbox denied `/usr/bin/time -l` access to `kern.clockrate` in
the first pair, so that wrapper exited1 after successful completed R workflows.
Peak RSS is unavailable for those runs; do not infer resource savings. Concurrent
local checks may affect wall time. A positive software test or extra evidence is
not biological improvement. Keep optional diagnostics/correction non-default
until their scientific/default gates are met. Negative and unavailable results
belong in the report.

After the original PBMC pair started, a short native process sample identified
recursive printing into `capture.output`'s growing in-memory text connection.
Future runs now preserve **all** printed review text in separate file-backed
logs, with per-operation elapsed/user/system time and byte counts. Decisions,
public API calls, parameters and evaluation criteria are unchanged. Original
pair measurements remain preserved and include the old collector's overhead;
do not compare their wall times directly with the new collection policy, or
attribute that overhead to numerical algorithms. An operation includes API
integrity checks, optional continuation and rendering; it is not kernel time.

`runtime_segments.R VARIANT_DIRECTORY output.json` reads and verifies the sealed
state before reporting execution/review wall-time intervals. It separates
approved computation/persistence windows from review/printing windows, while
explicitly retaining integrity-check overhead. It does not label review time
as pure collection overhead or human effort. Dataset orchestration reuses only
complete variants with exact input/reference/library identity and successful
matching process receipts; incomplete/failed work is never silently repeated.

## Eligibility bookkeeping

The three-metric QC-OR ablation requires measured counts, features and
mitochondrial fractions. The driver reads the frozen baseline MAD checkpoint,
records its hash and explicit unavailability reasons, and skips an ineligible
ablation without substituting a two-metric rule. Independent eligible variants
still run. Existing failed attempts and their logs are preserved separately.
`--only-variant after-qc-or` or `--only-variant after-sample-hvg` can finish one
preregistered ablation after a preserved driver failure. This mode verifies the
complete frozen baseline and does not repeat completed numerical variants.

Post-hoc common-class and timing corrections are in [results/report-corrections.md](results/report-corrections.md).
Reproduce common-class scores with `python3 posthoc_report.py results/metrics.json output.json`;
optional `--timings` reads saved stage projections without rerunning analysis.
The original metrics/failures remain unchanged. Model A/B protocol（已撤下的未执行方案） is protocol-only, with zero model calls.

Prediction statuses are a scoring contract: only `candidate_only_not_reviewed` and
`reference_prediction` may receive credit. Failed/not-run/schema-failed, missing
and unrecognized statuses force Unknown without changing raw outputs. The
post-hoc reader requires status-aware aggregates or the bundled hash-bound
[prediction audit](results/prediction-status-audit.json). To audit existing saved
CSVs without any refit, use `audit_prediction_status.py EVIDENCE metrics.json output.json`.
