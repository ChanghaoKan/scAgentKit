# Evaluation v2: proposed annotation and human-effort study

**Status: PROPOSED — NOT EXECUTED — NOT PREREGISTERED.**
This document is a plan, not authorization for model calls, data transfer or spending.
No v2 observations, accuracy estimates, time savings or biological benefits exist.
The target is scAgentKit 0.8.1; the reviewed starting source is
`1a856d6d65542479f62d4ad78403b07ad1d101e9`. Before execution, freeze the exact
installed revision and artifact hashes; the version string alone is insufficient.

## Question and smallest useful scope

Does the review interface help analysts produce defensible annotations, and does
adding a model improve those annotations or reduce active analyst time?
Begin with **annotation-only tasks on identical frozen cells and clusters**.
This isolates annotation and review from QC, PC, resolution and integration choices.
It cannot establish better QC, clustering, batch correction or complete-pipeline time.
A later study allowing those decisions needs a separate protocol and new cases.

[V1](EVALUATION_PROTOCOL_V1.md) evaluated offline computation and reference
candidates, with final Unknown controls and no model calls or human-time experiment.
The [archived ifnb A/B plan](archive/IFNB_MODEL_AB_PROTOCOL.md) compares model
evidence packages on already-seen data; it remains an unexecuted exploratory plan.
Neither is replaced or retrospectively relabeled by v2. Preserve all V1 results.

## Three arms and equal information

| Arm | Analyst task | Evidence and assistance |
| --- | --- | --- |
| A: conventional Seurat manual | Review ordinary exported tables/plots and save labels in a structured form | Fixed marker, expression, reference and metadata packet; no model |
| B: scAgentKit manual | Review the same evidence in scAgentKit and explicitly approve labels | Same packet and reference version; no model |
| C: scAgentKit plus model | Review model proposals, correct or abstain, then approve labels | Same scAgentKit evidence as B plus one frozen model configuration |

All arms receive the same cluster membership, label vocabulary, permissible reference
material and information content. Record presentation differences as the intervention.
Disable external searches, chat assistants and extra references during timed sessions;
record protocol deviations. This tests a controlled workflow, not unrestricted practice.
Preserve the initial model proposal and the analyst's final labels separately.
Neither model output nor database overlap is automatically promoted to accepted truth.

## Cases, reference coverage and no-leakage scope

Use public or explicitly authorized data with verifiable specimen/donor provenance.
The planning envelope is two tissue settings, one blood and one non-blood, with
approximately three independent donor cases per setting. **This is a feasibility
proposal, not a locked sample size or a powered confirmatory design.**
Use small cases manageable in one session; select cells without using evaluation labels.
Record whole-capture versus subset status, original cells and all exclusions.

Choose query studies not used in V1 or in method/prompt development. Separate pilot
and evaluation donors, preferably studies; multiple cells or clusters are not replicates.
Reference donors and studies must be distinct from query donors and studies.
Audit target-type coverage before accepting a tissue/reference combination; HPCA
must not be reused as a pancreas subtype reference without demonstrated coverage.
Freeze accessions, donor evidence, IDs, selection rules, label granularity, complete
mapping and reference hashes before inspecting held-out method outcomes.

Evaluator labels, author annotations, tutorial identities, adjudication notes and
prior scores remain outside analysis objects, filenames shown to analysts, prompts
and tool context. Separate the evaluator workspace and access from execution.
Audit final payloads offline for prohibited fields and preserve exact hashes.
An existing public dataset may have entered model pretraining; this cannot be ruled
out by removing its accession. Disclose that uncertainty; stronger unseen-data claims
require independently collected, demonstrably unavailable evaluation data.

## Analysts, assignment and independent assessment

Plan a feasibility pilot with at least three analysts spanning recorded experience
levels and two independent biological assessors. Analysts and assessors have distinct
roles; assessors must not evaluate their own annotations or see arm identity.
Give all analysts the same training on separate pilot cases before measurement.

Each held-out case is completed in all three arms by different analysts. Each analyst
sees a given case only once. Rotate case-to-arm assignment and session order using
a saved randomization schedule, balancing experience and tissue where feasible.
With only three analysts, analyst-by-arm interactions remain poorly estimated;
use the pilot to decide how many analysts and cases the subsequent study needs.

Before seeing method outputs, two assessors independently establish target annotations
from documented source annotations and independent evidence where available.
They record resolution, uncertainty, evidence provenance and disagreements; adjudicate
disagreements while blinded to arms. Unresolved cases remain ambiguous.
Source-label agreement and expert-adjudicated agreement are separate endpoints;
expert agreement without orthogonal evidence is not biological ground truth.
For mixed clusters, assess composition or a prespecified ambiguity rule; do not force
a single label merely because the software emits one label per cluster.

## Outcomes and denominators to freeze after the pilot

Primary comparisons are B versus A (interface) and C versus B (added model).
Select one primary quality endpoint and one primary time endpoint, multiplicity rule,
minimum meaningful differences and any noninferiority margin before held-out execution.
Do not choose the winning endpoint after seeing held-out results.

- Annotation: per-case macro-F1 over fixed evaluable target classes, per-type recall,
  full confusion tables, known-label coverage and correct-label yield over the fixed
  evaluable cell universe. Report broad and fine levels separately.
- Unknown and failure: preserve abstention, missing, timeout, schema and citation
  failures separately. They receive no correct-label credit on known targets and
  remain in denominators. Ambiguous target cells have a frozen separate evaluation
  stratum; retain their count and report appropriate abstention without inventing truth.
- Rare groups: freeze a prevalence definition and minimum evaluable support from
  the pilot, then report every eligible type's recall, support and Unknown fraction.
  Low-support groups remain visible. Fixed cells cannot test QC retention benefit.
- Confidence: collect the same ordinal confidence scale in all arms; report empirical
  agreement and support per level and high-confidence errors. Treat these categories
  as ordinal, not calibrated probabilities. Model and final-human confidence stay separate.
- Human time: measure active review/edit time from opening the prepared packet to
  saved final annotation. Pause recorded interruptions and compute/API waits; report
  preparation, training, waiting and end-to-end elapsed time separately. Record corrections,
  rejected suggestions and requests for extra evidence. Never substitute API time for labor.
- Resources: save calls, input/output tokens, observed charges, wall time, hardware,
  dependency versions and measured peak memory; unavailable values remain null.

Show every case and arm, including failures. Use paired case-level comparisons;
account for analyst and study dependence. Do not bootstrap cells as independent units.
The small pilot is descriptive. Lock the final sample-size rationale, uncertainty
method and analysis script before unblinding a separate evaluation cohort.
Any time-saving claim must be accompanied by quality and abstention results.

## Pilot, freeze and execution gates

1. Run an offline dry run on development/pilot cases only: verify equal evidence,
   target coverage, label joins, output schema, timers and failure bookkeeping.
2. Lock exact software/dependencies, donors/cases, analyst allocation, preprocessing,
   marker settings, packet construction, labels, endpoints, sample size and analysis.
   Fill all unresolved choices in a dated manifest; record departures from this proposal.
3. If an authorized model arm is planned, freeze provider, exact model identifier,
   endpoint, prompt, supported decoding settings, context/output bounds, repetition
   count, timeout/retry policy and price basis. Validate complete payloads offline.
4. Establish explicit authorization covering that provider, transmitted fields and
   maximum spend before external calls. This document grants none; its executable
   inference budget is **zero**. Use only authorized credentials and a hard request,
   token and currency cap; stop on drift or cap exhaustion and retain incomplete arms.
5. Timestamp the final protocol/manifest before held-out execution and outcome inspection.
   Only then describe it as prospectively frozen; do not call this draft preregistered.
6. Execute into a new `benchmark/evaluation-v2/` evidence directory, preserve raw
   responses and decisions, and publish sanitized summaries with reproducible scoring.
   Do not overwrite historical results, change scientific defaults, or tune against
   held-out labels. Any change after unblinding creates a declared exploratory analysis.
