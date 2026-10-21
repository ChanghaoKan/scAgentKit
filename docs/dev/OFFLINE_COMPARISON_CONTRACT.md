# Offline comparison and installed-package validation

This contract separates software verification, a public-data workflow case,
and a scientific comparison. Passing a contract or synthetic test does not
establish annotation accuracy, superiority, or user time savings. No provider
requests, credentials, private datasets, or data downloads are required by the
contract validator. Existing provider benchmarks remain separate and opt-in.

## Existing capabilities and boundaries

| Existing artifact | What it establishes | What it does not establish |
| --- | --- | --- |
| `benchmark/pbmc3k_repro.R` | Local counts, fixed choices, isolated optional truth, saved-decision replay, same-cell and numerical checks | Quality of inferred labels or autonomous parameter choices |
| `benchmark/pbmc3k_reference_inputs.R` | Offline reference candidates, actual guided/independent prompt inputs, provenance | Model outputs, reviewed labels, candidate probability |
| `tests/testthat/test-audit-scientific-boundaries.R` and reference/review tests | Scientific input and decision invariants on controlled inputs | Generalization to independent biological samples |
| `bench_01_pc_selection.R` | Partial prototype | Completed comparative evidence |
| `bench_02`–`bench_06`, `bench_99` | Explicit stubs | Runnable benchmark suite or summary metrics |
| Public PBMC browser workflow | Packaging, evidence transfer, full proposal/approval, result/reopen behavior | Biological truth or a participant study |

PBMC used during development is a **development case**, even when the source
is public. These tests use no seven private user datasets. Their provenance,
rights, labels, and sharing permission are not assumed.

## Freeze an experiment before running methods

Keep an experiment directory outside the source package. Freeze input SHA256,
exact ordered cell IDs, raw assay/layer, species and tissue, metadata roles,
filtering and QC, normalization/HVG/PC/neighbors/clustering choices, seeds,
marker filters, reference release and license, and each method's parameters.
Record source commit, source archive hash, installed package/runtime hashes,
R/Python/dependency versions, OS and BLAS, commands, warnings, failures and
skips. Preserve the actual protocol bytes and its SHA256. A manifest validates
record structure; a human must verify that its provenance claims match the
experiment. The validator cannot prove a dataset is held out or a reviewer is
independent.

Use the same frozen input and settings for the old and new interface unless
the experiment explicitly changes an analysis method. Store original labels,
unknowns, failed and excluded cells without silent remapping or dropping.
Do not tune a parameter to evaluation labels. Reference candidates, reference
scores, coverage, model suggestions, and reviewer labels are distinct fields;
a candidate remains evidence until a person makes a recorded decision.

Keep truth in an **evaluator-only** table and process. It must never enter the
analysis object, prompt, reference choice, candidate ordering, parameter choice
or interaction task. A manifest must cite its independent source, granularity,
and a predeclared mapping SHA256. Reconcile exact literal IDs by keyed joins;
reject duplicates, missing cells and positional joins. Author labels may be
imperfect: disagreement with them is reference disagreement, not proof that a
method is biologically wrong.

## Small executable contract

`benchmark/contracts/compare_offline.py` uses only Python 3.9+ standard library.
It validates explicitly exported evaluator artifacts and prints a report to
stdout. It does not parse Seurat objects, infer labels, access the network,
construct a provider, or run a new annotation algorithm.

```sh
python3 -B -m unittest discover -s benchmark/tests -v
python3 -B benchmark/contracts/compare_offline.py /local/experiment
```

`comparison.json` has schema `scagentkit.offline-comparison.v1` and requires:

| Field | Meaning |
| --- | --- |
| `dataset_role` | `synthetic_control`, `development_case`, or `held_out`; descriptive, not independently certified |
| `input_sha256`, `protocol_sha256` | SHA256 of the frozen input and protocol |
| `software_commit`, `environment` | Exact implementation identity and environment record |
| `cells` | `{path, sha256}` of UTF-8 CSV with unique `cell_id`; fixes the complete universe |
| `methods` | Distinct `{name, path, sha256}` records; each CSV has exactly those cells and `cell_id,label,status` |
| optional `truth` | `{path, sha256, source, granularity, mapping_sha256}`; CSV has exactly those cells and `cell_id,label,status` |

All artifact paths must resolve inside the experiment directory. CSV bytes
must match their recorded SHA256. Method statuses are `reviewed`, `unknown`,
`excluded`, `failed`, `not_run`. Only `reviewed` may carry a non-unknown label;
all other rows keep blank or literal `unknown`. Preserve a separate rich
candidate/evidence table rather than putting top-1 into this prediction column.
Truth statuses are `reviewed`, `ambiguous`, `unlabeled`.

Without truth, `annotation_accuracy` is JSON `null`, denominator zero and
`accuracy_status` is `not_evaluated_no_truth`. The report still counts status
and reviewed coverage over **all frozen cells**. With truth, the denominator
is all cells with reviewed truth; unknown/excluded/failed/not-run predictions
remain in that denominator and cannot improve a score by disappearing. Only
exact pre-mapped reviewed labels match. Ambiguous/unlabeled truth is counted
outside that denominator. Synthetic scores are marked `synthetic_only`; other
scores are `reference_agreement_only`. `scientific_accuracy_claim` remains
false. This intentionally small check does not implement clustering ARI,
hierarchical label distance, calibration, confidence intervals or hypothesis
tests. Report exclusion/retention separately before interpreting any metric.

The unit tests generate tiny explicit synthetic CSVs at runtime. They check
unknown retention, absence of truth, candidate rejection, fixed denominators,
ambiguous truth, tamper detection, complete IDs and duplicate rejection. They
validate bookkeeping only; synthetic labels are never PBMC truth.

## Same-task interface comparison

Use the same frozen public PBMC project/revision, marker/reference assets,
annotation target and analyst instructions for the baseline and new interface.
Predeclare the operational counts: evidence copy/paste operations, departures
to another file/page to retrieve evidence, and manual row edits. Count explicit
candidate selections separately from free text edits, and count approval and
continue actions separately. Store event traces and the initial/final proposal
hashes. Verify both runs still save one complete proposal and require its
separate approval. Preserve unknown and coarse labels; do not force a label to
complete a task. Counterbalance order in any subsequent participant study.

A developer replay can show that an operation was removed or became reachable
in one view. It cannot establish user-perceived effort or time saved. Wall time
mixes computation, hardware and interaction; it is not an annotation-quality or
usability result. If the baseline lacks the same evidence, record that mismatch
instead of presenting unequal tasks as a controlled comparison.

## Installed package and platform gates

For each final archive, prepare the approved Release archive once, SHA256 it, and install into a **new target
library** using that archive. Existing dependencies may be reused; explicitly
record `.libPaths()` and `sessionInfo()`. This is an independent target-package
installation in the current environment, not a clean Mac. Run the following
with the existing dependency library in `R_LIBS_USER` as appropriate:

```sh
mkdir /tmp/scagentkit-fresh-library
Rscript -e 'remotes::install_local("scAgentKit_0.6.0.tar.gz", lib="/tmp/scagentkit-fresh-library", dependencies=c("Depends", "Imports"), upgrade="never", build=FALSE)'
Rscript benchmark/contracts/installed_package_smoke.R \
  /tmp/scagentkit-fresh-library /tmp/installed-smoke.json
```

The smoke checks that the loaded package resides in the new library, verifies
all bundled asset/R signatures and changes to a fresh temporary directory. It
starts/reopens an RDS project, imports a two-sample MEX table with shuffled
metadata, saves and separately approves complete strategy/annotation proposals,
and executes both phases through actual installed loopback HTTP background
workers. It verifies exact counts/metadata, completes with explicit Unknown,
reuses and restarts the completed service without changing state, reads the
saved result HTTP projection, and starts a single-directory MEX entry. The
companion `installed_continue.py` must be copied alongside the smoke. Services
are stopped on exit. This synthetic HTTP control is not an actual browser or
biological accuracy test; retain a separate full public-data Chrome walkthrough.
Run the complete R/Python/Node suites on the frozen revision as separate gates.

`.github/workflows/installed-runtime-contract.yaml` defines fresh hosted
Ubuntu and macOS jobs with dependency caching disabled. Each resolves the
package's required dependencies, builds an archive, installs into a new library,
hides the source checkout, and runs the synthetic installed smoke and offline
contract controls. CI installation may use normal public package registries;
it performs no model inference or private-data transfer. The checkout is
restored even on smoke failure. This is a proposed executable gate until actual
hosted runs succeed; a local Mac run does **not** verify Linux. The hosted job
uses the runner's installed toolchain, so it is not a hermetic pinned image.
It excludes the optional dependency/full scientific/browser matrix covered by
other suites. Windows, HPC schedulers/NFS, remote tunneling and alternative
BLAS remain unverified here. Record optional dependency skips explicitly.

## Inputs still needed for a real comparison

- Independent public count files with exact version, hashes, rights and a
  documented cell/sample/donor/capture/condition mapping; do not infer design
  from identifier strings.
- Independently reviewed labels at a frozen broad/fine granularity, ambiguous
  policy, exact IDs and mapping; PBMC workflow labels and reference top-1 are
  insufficient. Preserve a held-out cohort outside development tuning.
- A valid, licensed, frozen species/tissue reference and provenance; demonstration
  reference templates cannot substitute for a biological reference.
- Predeclared methods/baselines, unknown handling, retention, failure policy,
  replicate unit, metrics and uncertainty plan. Cells from one donor are not
  independent biological replicates.
- For any later provider comparison, separate explicit authorization for the
  exact payload, provider/model/version and repeat plan. None is needed
  or granted by running this offline contract.
- For a user-effort claim, independent participants and a controlled same-task
  protocol. Developer self-tests and runtime measurements are insufficient.
