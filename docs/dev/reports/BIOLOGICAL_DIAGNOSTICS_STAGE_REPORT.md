# B1/B2 diagnostic and review integration candidate

Status: draft PR, not formal biological validation or a release. Base main after
Core v0.3.0 and scAgentKit #19/#20 (`49352181f3ccb54e5d3dac3f52c4100d1446a98e`).
The PR description records the final head and exact commit range.

## Changes and reuse

B1 adds a separate diagnostic checkpoint, global/sample/cluster QC comparisons,
top-five marker evidence and deterministic eligibility for relaxation. QC v2
replaces a specified diagnostic cluster/metric baseline predicate while retaining
other metrics, rule logic and the minimum prefilter. Hash-bound evidence,
effective threshold tables and retention changes are visible before approval.
Approved analysis recomputes its own PCA; tests stop at the second human gate.

B2 adds candidate-pool-corrected same-batch neighbor excess, fixed-label purity
and sample-equal condition-centroid measurements. Complete confounding includes
multiple distinct batches nested within a condition. Rule recommendations retain
none when effect is absent, confounded or not assessable. Existing Harmony
provenance/design guards remain authoritative. Post-correction measurements use
actual approved PCA/Harmony dimensions and appear with resolution evidence.

First-gate risk fields reuse the five annotation risk enums and deterministic
validator, with strategy-specific evidence binding. Missing model assessments
remain visibly rule-derived or unassessed. Saved drafts cannot approve anything.

New abstractions: one diagnostic checkpoint, one typed replacement operation,
and a descriptive batch metric record. Reused: existing QC/MAD calculations,
selectors, checkpoints, hashes, dependency invalidation, review/event lifecycle,
Harmony execution, risk validator and frontend controls. No additional gate,
provider, mutable tool or approval mechanism.

## Tests and CI

Apple M5, 16 GiB RAM, macOS, R 4.6.1. No large performance benchmark claimed.

- Broader diagnostic/QC/strategy/Harmony-selection regression: 1,079 assertions
  passed, no failures or warnings; three Harmony-dependent tests initially
  skipped because the isolated library lacked Harmony.
- After installing Harmony 2.0.5 in that isolated library, the Harmony suite
  passed 686 assertions with no failures, warnings or skips. This includes
  synthetic software controls and tests mocking the upstream integration;
  these counts are overlapping suites, not 1,765 unique assertions or an
  accuracy benchmark.
- First-gate/rendering DOM suite: 40 checks passed; QC DOM suite: 6 passed.
- New tests cover diagnostic/final PCA separation, second-gate stopping,
  unsupported relaxation, tightening, overlapping/stale replacements,
  missing MT evidence, input/RNG preservation, structured risk validation,
  candidate-pool reference, confounding, replicate weighting and unavailable
  condition signal. Final PR CI remains required.

## Acceptance and paper milestone

Standards 5/6 gain diagnostic evidence and structured risks at the existing
strategy/resolution gates; standard 8's human-approval boundary is preserved.
Formal accuracy, 50k full-pipeline performance, three-dataset results and 1.0
compatibility are not established here.

Paper milestone: 2B/M1-xAI merged; #22 provides the trace UI candidate with real
Chrome acceptance. This PR advances B1 and B2 together because they share the
same diagnostic checkpoint and first-gate binding. 4E evaluation/replay, stage 4
startup/docs and integrated end-to-end validation remain outstanding.

## Limits and deviations

B1/B2 are submitted as a single integration candidate instead of separate PRs
so the shared diagnostic checkpoint and risk schema are reviewable together.
Both switches remain independently configurable and recorded.

The engine feature is opt-in; `sc_start` defaults belong to stage 4. The initial
marker support N=3 and batch excess 0.1 are recorded development settings.
Biological decline cutoffs remain explicitly unfrozen pending development-set
calibration before formal experiments. No composite preservation score is used.
Diagnostic clusters are proxies for cell types, not validated identities.
Unresolved Ensembl IDs cannot qualify for relaxation. Condition diagnostics
require declared independent samples; the software cannot certify independence.
Full browser acceptance of B1/B2 and the integrated user journey is still required.
