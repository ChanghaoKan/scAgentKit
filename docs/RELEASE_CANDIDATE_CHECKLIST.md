# Release candidate: scope, checks and remaining work

This candidate starts from frozen commit
`99d88481614ec54902b28b4a217ca2067ba382c2`. It is experimental analysis software
with explicit human decisions. A successful workflow or regression suite does
not establish biological accuracy, optimal QC or suitability for every study.
Documentation corrections do not themselves constitute a new scientific test.

The evidence tables below retain the prior `bd8f799` candidate's Mac/Linux
receipts. The new Linux-runtime increment starts from
`bd8f799da7f51d97b8614399bb5a633176dc4b46`, adds the explicitly audited
scDblFinder 1.22.0/xgboost 1.7.11.1 pair. Final Linux v3 full check is
**Status OK: 7379 PASS / 0 FAIL / 0 WARN / 2 runtime-specific SKIP**; bounded
real-method and Mac headless CLI acceptance also passed. Linux v2
**Status: 2 NOTEs** and earlier failures remain preserved. See
[Linux runtime support](LINUX_RUNTIME_SUPPORT.md) for receipts and limits.
Earlier passing totals remain versioned evidence.

## What this version supports

| Area | Supported contract | Boundary |
| --- | --- | --- |
| Input and recovery | Named raw-count matrix, Seurat or local RDS; exact layer/ID checks; explicit processed entry; durable headless inspect/review/continue | No universal file importer, normalized-data substitute for counts or automatic migration of saved approvals |
| QC and strategy | Default typed-range QC; optional whole-strategy review with explicitly declared MAD pools, cell-cycle programs, capture-specific doublet scoring and guarded Harmony/PC policies | Methods require their own applicability/dependency guards. No inferred donor/capture/batch role, automatic best rule, ambient-RNA correction or QC-accuracy claim |
| Annotation | Saved markers, supplied local-reference candidates, typed model/manual proposals, Unknown, reviewed new columns and history | Confidence is qualitative; reference scores are heuristics. No held-out label-accuracy or calibrated-probability claim |
| Parent and children | One loopback service over one configured parent and registered children; per-tab bindings; exact-ID derived apply/undo and receipts | Completed source parent is read-only in workspace mode. No arbitrary path/RDS/code selector, automatic child merge or executable derived-project import |
| Model assistance | Exact aggregate preview, separate request consent, explicit dispatch, validated candidate adoption, cache/usage/holds; configured DeepSeek/Grok factory or headless callback | Continue is local computation. Provider configuration is immutable. Custom callbacks stay in R. Current acceptance uses mocks and does not prove live-provider biology |
| Study notes and gene evidence | Initial `context$notes`, research goal/design notes, scientific rationale, supplied marker statistics and saved reference/source provenance | Independent project/cluster notes editing and a notes journal are absent. Arbitrary gene chat, literature search and negative-expression inference are absent |
| Deployment | Private R library, durable local storage, loopback review, headless Rscript and scheduler/tunnel templates | Templates are not tested site deployment. Shared-filesystem semantics and multiuser HPC authentication require separate validation; no scheduler submission is performed |

The [first-run](FIRST_RUN.md) and [server-first](SERVER_FIRST.md) examples default
to `strategy = FALSE`; their narrow tables are not the whole package support
matrix. Optional contracts are documented in
[strategy support](ANALYSIS_STRATEGY_SUPPORT.md), [MAD review](MAD_REVIEW.md),
[cell-cycle review](CELL_CYCLE_REVIEW.md), [doublet review](DOUBLET_REVIEW.md),
[Harmony/PC review](HARMONY_PC_REVIEW.md), [subcluster review](SUBCLUSTER_REVIEW.md)
and [single-service review](SINGLE_SERVICE_REVIEW.md).

These fail-closed, exact-layer and no-automatic-provider-retry contracts apply
to `sc_run` and its managed review paths. Older exported `AgentSeurat` APIs
have distinct policies: legacy annotation can retry or use a layer fallback,
and legacy sub-annotation can infer species from gene case. Their existence
does not make those behaviors part of the reviewed coordinator.

## Install this checkout, separately from the user library

The README's pinned `@v0.4.0` GitHub commands install the older tagged toolkit,
not these unreleased features. For this candidate, use a fresh private directory
and this exact checkout. Install required dependencies in the declared private
library before installing the package; this command does not download or repair
dependencies:

```sh
rc_checkout=/absolute/path/to/scAgentKit-release-candidate
rc_r_library=/absolute/path/to/new/private-rc-library
mkdir -p "$rc_r_library"
cd "$rc_checkout"
R_ENVIRON_USER=/dev/null R_PROFILE_USER=/dev/null R_LIBS_USER="$rc_r_library" \
  R CMD INSTALL --library="$rc_r_library" .
```

Use that same library with the fixed Rscript executable when starting the
[single service](SINGLE_SERVICE_REVIEW.md#shortest-startup), and when resuming
projects. Record the installed package path, implementation fingerprint,
dependency versions and actual `.libPaths()` in the validation receipt. Do not
silently fall back to another installed scAgentKit. Installing a package into a
fresh library is distinct from verifying that all optional methods execute.

The strict doublet adapter retains exactly **scDblFinder 1.26.7 with xgboost
>=3.1** and additionally accepts exactly **scDblFinder 1.22.0 with xgboost
1.7.11.1**, each with all three accepted canonical formal/body hashes below.
A generic latest-version
`BiocManager::install("scDblFinder")` is not a promise of adapter compatibility.
An unsupported version or changed function hash fails closed; accepting another
release requires an explicit adapter review, not removal of the guard.

| scDblFinder release | Audited function | Accepted SHA-256 |
| --- | --- | --- |
| 1.26.7 | `scDblFinder` | `0beee189415aadb8eb7b1c2bd2d9a87bf7f19b6986cc7b410dd70b3976758fb7` |
| 1.26.7 | `.scDblscore` | `c17836de1f003e867401677a95ddb148311577997c9fd08f9cecda5ba83b4c9f` |
| 1.26.7 | `.xgbtrain` | `9587a78018158c55d5bb3660b87660d9440efadf7d8cbb0476f53bea0aad3307` |
| 1.22.0 | `scDblFinder` | `9a4ad55e93b80d59f4ced150eacd6e5f2429bbe53567c24a5c3dc18194d441b2` |
| 1.22.0 | `.scDblscore` | `c17836de1f003e867401677a95ddb148311577997c9fd08f9cecda5ba83b4c9f` |
| 1.22.0 | `.xgbtrain` | `d9be56120cc9b3e32a117366fbade307f13d06ad08e3e3150f38436fd3d3611a` |

Each capture still requires three audited successful fits and predictions; saved
evidence binds its recorded pair rather than an installed-package lookup. Older
records lacking the explicit pair are accepted only with saved 1.26.7 and a valid
xgboost >=3.1 plus the expected hashes/audits. Missing/unknown historical versions
and unversioned legacy records require regeneration and fresh review, without
automatic approval migration.

Harmony has its own audited version/source/settings boundary; see its guide.
Optional dependencies being listed in `Suggests` do not make arbitrary versions
supported. This candidate audit makes no real model request and reads no keys.

## Keep evidence versions and data roles separate

| Evidence | Data/model path | What it establishes |
| --- | --- | --- |
| Historical module guides | Named older implementation fingerprints; synthetic and public PBMC development workflows; local methods and mocks/manual or supplied historical proposals | Bounded module behavior at those versions. Their test totals are not new final-source runs |
| Prior unified-model increment `d24cf727` | Synthetic and public PBMC parent/child workflows using separate service launches and simulated requests | Prior model/cache/approval and object integrity behavior; not the new single-service lifecycle |
| Frozen single-service increment `99d8848` | Processed-entry reuse of verified 476-cell synthetic parent; new raw 127-cell child; three simulated responses; zero live APIs | Parent/child navigation, saved task continuity, rejection bindings and derived-object integrity in one Mac service. It did not rerun public PBMC |
| Fresh frozen-baseline check | Fresh private install of exact `99d8848` archive | Complete check log: 7,224 passes, zero test failures/warnings/skips, Status OK. The wrapper receipt was lost during transport interruption; the complete log remains |
| Repaired candidate v2 | Fresh private package with the three minimal audit fixes; checked 340-file snapshot and explicit source equivalence | Focused fixes and real synthetic Harmony verified; latest complete Mac R check is Status OK with 7,282 passing assertions and zero test failures/warnings/skips. Optional package INFO and manual/vignette exclusions are recorded below |
| Held-out scientific benchmark | Independent public human/mouse data with declared reference provenance | Planned; existing PBMC is development data, not held-out evidence |

The single-service scientific source was byte-identical to `d24cf727`, so its
delivery explicitly reused the prior scientific-suite receipt and reran service
checks. This release audit then freshly checked frozen `99d8848` and made three
minimal privacy/provenance/replay repairs. Candidate v1 reported 7,238 passes
and three new fixture-construction errors; these failures are retained. Fixing
the test constructor and explicit sparse fixture passed 13 focused tests with
142 assertions and no warnings/errors. Candidate v2 has been privately installed
and its complete Mac R check passed: Status OK, 7,282 assertions, zero failures/warnings/test skips.
Document any omitted optional dependency, INFO, skip, manual/vignette exclusion
or failed attempt alongside the final outcome. A model ID in configuration does
not prove a real request occurred. Software format, coverage and biology are
separate results; Unknown is a legitimate unresolved outcome.

## Current Linux closure checkpoint

| Receipt | Actual outcome and boundary |
| --- | --- |
| Mac v2 full R check | Status OK; 7390 PASS / 0 FAIL / 0 WARN / 1 SKIP; 491.581 s. Legacy genuine acceptance skipped on modern 1.26.7/3.2.1.1 runtime |
| Linux v2 full R check | exit 0; 1350.359 s; 7379 PASS / 0 FAIL / 0 WARN / 2 SKIP; **Status: 2 NOTEs** (.gitignore and CITATION.cff), with modern-only genuine checks skipped |
| Linux v2 Python | 300 total; 284 passed / 16 skipped / 0 failures/errors; explicit real-fixture requirements and an Rscript-unavailable case remain disclosed |
| Real legacy classifier | Three new projects plus fresh R verification passed: public 2700→2511; synthetic A/B each 440→438; capture audits, exact joins, preserved annotation columns and durable no-op resume |
| Real Harmony 2.0.5 | Four fresh R processes passed start/foundation/finish/verify; 120→119 cells, harmony neighbors and Unknown final annotations; later acceptance reused these unchanged receipts |
| Mac v3 packaging | Status OK / exit 0 / 18.541 s with --no-tests; not another 7390-assertion run |
| Linux v3 final check | **Status OK**, exit 0 / 1325.37 s; 7379 PASS / 0 FAIL / 0 WARN / 2 modern-runtime SKIP. Exact 52 tests and runner, forbidden metadata absent; sealed source and mutable build copy unchanged. INFO only: unavailable optional ontologyIndex |
| Linux v3 Python | 300 total / 284 passed / 16 explicit fixture or isolated-Rscript skips / 0 failures/errors; 97.39 s (98.043 s wrapper) |
| Mac browser-free CLI | Seven fresh R commands passed: 180→172 synthetic cells, Unknown new annotations, exact raw counts/cell order/old annotations; fresh no-provider resume was a durable no-op |
| Preserved unsuccessful attempts | First Mac and Linux checks each had three stale fixture assertions; baseline 46/51 with five timeouts; strict source-cache preflight rejection; first legacy-helper ordering assertion |

Current fees are US$0 with zero live model calls; prior conservative API
occupancy remains US$0.07910195. Checked source commit
`21e451bef0dbc137c9251da5aaafc4385d6d3346` is local only. Final documentation
and delivery manifest must preserve all 312 non-Markdown files, including
71 R production files, 96 workbench files and 52 test files. Mac packaging
used --no-tests; the full Mac and Linux checks are distinct receipts. No
broader HPC/Windows or biological accuracy conclusion follows from them.

## Prior bd8f799 release gates and recorded status

The prior `bd8f799` repaired production runtime fingerprint was
`e74de4903372dbcc80b6a27ff47bb5bf74e449920f4ebb023b14f63c94aa69a9`.
This fingerprint covers selected implementation functions, not every source
file. The checked v2 snapshot enumerates all 340 source files, including docs,
with manifest SHA-256
`15a4688e4187893a5951da6ca44a47a059684df80ba95e7cddc5271ba91638a6`.
That prior checklist update changed Markdown after its snapshot. The prior delivery
used a separate whole-source manifest with explicit equivalence of all 311
non-Markdown files to the checked snapshot. Its commit and manifest are recorded
in the external audit handoff; this document cannot include its own final hash.
The new doublet adapter has its separate completed Linux v3 receipt above; this
historical table remains evidence for the prior source. See [the current runtime checkpoint](LINUX_RUNTIME_SUPPORT.md#current-execution-checkpoint).

| Gate | Verified outcome or remaining work |
| --- | --- |
| Exact version | Checked v2 private package/runtime and whole-source snapshot recorded above; final committed source/archive/patch and complete manifest are bound in the external audit handoff. All 311 non-Markdown files match checked v2 |
| Complete R check | Frozen `99d8848`: complete log Status OK, 7,224 passes, zero test failures/warnings/skips; wrapper receipt lost during transport interruption. Repaired v1: 7,238 passes and three new fixture errors retained. Focused corrected fixtures: 13 tests/142 assertions, no warnings/errors. Latest complete v2 Mac check: Status OK, 7,282 passes, zero failures/warnings/test skips; 499.463 seconds. INFO: unavailable Suggests clustree, magick, ontologyIndex, SeuratData; manual excluded and vignettes intentionally skipped |
| Python | 300 tests: 298 passes and two explicitly scheduled R skips. Root separately executed those two actual R expression checks successfully. Python preserved 62 protected original fixtures; the separate R checks preserved the broader 554-file read-only fixture set. These are different scopes |
| DOM/client responses | 286 DOM passes; separate QC suite 12 cases and review-response suite 20 cases/61 assertions. These execute production scripts with inert DOMs, not native Chrome |
| Source equivalence | `rc-post-fixture-equivalence.json` proves all production and workbench files unchanged after the R-test-fixture-only correction. Python/DOM receipts therefore apply to those exact unchanged files; final Markdown updates require a separate delivery manifest |
| Real method/workflow integrity | Latest private v2 package completed a 120-cell synthetic real Harmony 2.0.5 workflow in four fresh R processes. Counts, the extra RNA layer, PCA and bundle actual-Harmony provenance/hash were verified; the caller's source object remained unchanged. `rc-real-harmony-v1/*.json` are the receipts; this demonstrates execution, not biological efficacy. Frozen single-service native/headless receipts remain versioned evidence |
| Commands and claims | Static startup-flag/export/helper/local-link audit clean. Installed-helper execution must be distinguished from source parsing or function existence |
| Linux/HPC | Previously authorized Linux executor: R 4.5.1, Python 3.13.5, Seurat 5.4, SeuratObject 5.3 and existing private agentomicsCore 0.1.1. Fresh isolated install/source-to-installed fingerprint check passed. Public development PBMC completed all 11 separate R modes: raw QC approval through 2700-cell output, idempotent resume and processed reuse/new annotation column; explicit manual Unknown proposals, no model API. Python: 300 collected, 284 pass, 16 fixture/R-isolation skips, zero failures/errors. Full R check timed out after 1200 seconds during tests: no complete assertion/skip totals or Status OK, retained logs require follow-up. Source and original public-project file hashes stayed unchanged. Harmony 1.2.3/scDblFinder 1.22 are unsupported by strict adapters. No full Linux/HPC, optional-method or scheduler compatibility claim |
| Scientific benchmark | The independent public human/mouse [protocol draft](BENCHMARK_PROTOCOL_DRAFT.md) is separate from these workflow checks. Existing PBMC is development data. No new API or large-data download in this audit |

The three confirmed P2 issues have minimal fixes and targeted evidence:

- Managed bundle provenance now records actual strategy/analysis and processed
  reuse provenance, including executed Harmony. The prior hardcoded
  `skip/manual`/empty-analysis discrepancy is retained as the motivating defect;
  the latest real Harmony run verifies the repaired output.
- Provider configuration and validator-result attributes are scrubbed before
  saved/exported projections. Targeted tests use synthetic attributes and mocked
  transport; they read no user key and make no live request.
- Local Continue validates immutable receipt bindings around the enqueue race.
  Two deterministic negative controls and 31 passing mechanism checks cover
  rejection; fake-worker process tests are distinct from scientific R execution.

For those prior bd8f799 receipts, the final Mac R check and bounded Linux
core workflow were complete; its full Linux regression remained open after
the recorded timeout. The new closure results are listed separately above. Independent notes
remain an explicit scope gap, and gene chat remains outside this release. Neither the real
synthetic method run nor regression counts establish held-out biology.

## Module coverage and actual-method boundaries

Paths below are relative to `tests/testthat/` for R and `workbench/tests/` for
Python/DOM. This is an inventory of relevant tests, not a claim that every
method ran unmocked. Latest complete Mac R check passed as stated above; individual unmocked-method claims remain bounded by their separate receipts.
Older public/synthetic method receipts in the module guides remain tied to their
named versions; no live model API was used in this candidate audit.

| Module | R test files | Python/client test files | Actual versus simulated evidence |
| --- | --- | --- | --- |
| Input, species and restart state | `test-run.R`, `test-run-species.R`, `test-first-use-errors.R` | `test_run_review_runtime.py`, `test_single_service_runtime.py` | R sparse/count/ID/state checks; human/mouse declaration checks are not real mouse scientific acceptance |
| Typed QC and impact binding | `test-run-qc.R`, `test-run-qc-preview.R`, `test-run-qc-review-binding.R` | `test_qc_runtime.py`, `test_run_review_runtime.py`, `test_qc_response.mjs` | Exact synthetic scopes and stale/hash controls; older public PBMC checks are development evidence, without QC truth |
| Whole strategy and Seurat foundation | `test-run-strategy-schema.R`, `test-run-strategy-execute.R`, `test-run-strategy-integration.R`, `test-run-joint-integration.R` | `test_strategy_review_runtime.py`, `strategy_review_dom.cjs` | Actual synthetic Seurat calculations, typed proposal guards and dependency reuse; provider suggestions mocked |
| MAD and prefilter | `test-run-mad-schema.R`, `test-run-mad-engine.R`, `test-run-mad-integration.R`, `test-run-prefilter.R` | `test_strategy_review_runtime.py`, `mad_review_dom.cjs` | Real deterministic sparse statistics/cell sets; historical synthetic/PBMC controls. No scientific threshold optimality claim |
| Cell-cycle diagnostics/regression | `test-run-cycle-schema.R`, `test-run-cycle-engine.R`, `test-run-cycle-integration.R` | `test_strategy_review_runtime.py`, `cycle_review_dom.cjs` | Synthetic score/regression guards; historical real-method/public receipts. No validated mouse phase accuracy |
| Capture doublets | `test-run-doublet-schema.R`, `test-run-doublet-engine.R`, `test-run-doublet-integration.R` | `test_strategy_review_runtime.py`, `doublet_review_dom.cjs` | Integration detector is a mock; historical real scDblFinder 1.26.7 synthetic/public receipts are separate. No fresh candidate biological doublet truth or unsupported-version claim |
| Harmony and PC policies | `test-run-harmony-schema.R`, `test-run-harmony-engine.R`, `test-run-harmony-integration.R`, `test-run-pc-diagnostics.R` | `test_strategy_review_runtime.py`, `test_strategy_harmony_dom.mjs` | Upstream Harmony mocked in adapter/integration tests; latest separate 120-cell real Harmony 2.0.5 run and older public/synthetic receipts. No efficacy inference |
| Markers, reference evidence and annotation | `test-run-annotation.R`, `test-run-annotation-review.R`, `test-run-reference-evidence.R`, `test-cellmarker-symbols.R` | `test_run_review_runtime.py`, `test_review_response.mjs` | Supplied marker/reference provenance and Unknown/manual review; historical PBMC and historical model responses. No new live annotation or held-out accuracy |
| Provider, budget, cache and typed suggestions | `test-run-provider.R`, `test-run-provider-metadata.R`, `test-run-suggest.R`, `test-annotation-output-budget.R` | `test_run_suggestion_runtime.py`, `test_run_suggestion_http.py`, `test_run_suggestion_dom.mjs`, `test_run_suggestion_bridge.R` | Mock HTTP/providers and explicit simulations; privacy/cost/retry/rejection mechanisms. Live browser provider dispatch remains unvalidated |
| Local Continue and locks/replay | `test-run-continue.R`, `test-run-review-actions.R` | `test_run_continue_runtime.py`, `test_run_continue_http.py` | Real Python children with fake R workers for mechanism tests; latest real Harmony workflow exercises the R Continue path in fresh processes. Immutable-receipt race negative controls included |
| Scoped child create/apply/undo | `test-run-subcluster-integration.R`, `test-run-subcluster-apply.R` | `test_run_subcluster_runtime.py`, `test_run_subcluster_http.py`, `test_subcluster_dom.mjs` | Exact-ID synthetic integration/undo controls; historical public PBMC and frozen same-service synthetic workflows. Parent preservation is not subtype accuracy |
| One-service scope navigation | `test-run-review-actions.R`, `test-run-subcluster-integration.R` | `test_single_service_runtime.py`, `test_single_service_http.py`, `test_single_service_dom.mjs` | Latest production Python/DOM bindings; frozen `99d8848` native Chrome synthetic parent→child→derived flow. Native latest-source rerun is not implied |
| Portable evidence/review compatibility | `test-project-export.R`, `test-project-review.R` | `test_project.py`, `test_project_http.py`, `test_project_runtime.py`, `test_project_store.py`, `test_expression_export.py` | Compatibility tests plus separately executed actual R expression checks. This generic mode is distinct from managed coordinator review |
| Study notes and gene evidence limits | Context/reference tests above | Review-response tests above | Initial context and scientific rationale only; no independent notes journal/editor or gene-chat implementation/test claim |

## The 25-click receipt, without treating acceptance detours as requirements

The recorded main workflow contains six scientific/scope actions, three
exact-preview consents and the following sixteen mechanical clicks. The
consents approved local simulations and transmitted no data externally.

| Order | Scope/action | Role |
| ---: | --- | --- |
| 1 | Parent: open workspace before completion | Acceptance-only waiting-page probe |
| 2 | Waiting workspace: return to parent review | Acceptance-only return |
| 3 | Parent annotation: expand exact request preview | Evidence inspection |
| 4 | Parent annotation: Request | Explicit approved request dispatch |
| 5 | Parent annotation: Adopt | Candidate becomes a fresh scientific proposal |
| 6 | Completed parent: open cluster/derived workspace | Navigation |
| 7 | Workspace: open registered child review | Navigation |
| 8 | Child strategy: expand exact request preview | Evidence inspection |
| 9 | Child strategy: Request | Explicit approved request dispatch |
| 10 | Child strategy: Adopt | Candidate becomes a fresh scientific proposal |
| 11 | Running child: switch to parent | Acceptance-only active-job probe |
| 12 | Parent: return to running child | Acceptance-only rejoin probe |
| 13 | Child annotation: expand exact request preview | Evidence inspection |
| 14 | Child annotation: Request | Explicit approved request dispatch |
| 15 | Child annotation: Adopt | Candidate becomes a fresh scientific proposal |
| 16 | Child: return to parent derived outputs | Navigation/result inspection |

Removing only the four acceptance detours gives 21 clicks for this observed
processed-parent path. This is accounting, not a usability minimum or a promise
for raw data, revisions or every review node. The separate literal-cluster
checkbox is scientific selection. Three whole-proposal approve/Continue
buttons, child creation and derived apply account for the other five scientific
clicks. Reloads, typing, the reference-inheritance dropdown and programmatic URL
opens are outside the physical-click count. Each read-only follow-up added four
mechanical clicks, giving 33 clicks across all three acceptance sessions.

Possible later simplifications to evaluate are opening previews by default and
offering automatic navigation after explicit child creation. No UI change is
made in this audit. Preserve actual payload inspection, scientific approval,
request authorization and candidate adoption; reducing a count alone is not a
reason to merge those decisions.

## Next executable work

Finalize the documentation-only delivery manifest against the completed
Linux v3 source/check receipt, preserving all non-Markdown bytes. Keep
remaining scope limits explicit. Then freeze the separate
scientific benchmark protocol before selecting methods, parameters or provider
calls. For QC without truth, report retention, descriptive diagnostics and
sensitivity/stability rather than accuracy. For annotation, report format
validity, coverage/Unknown and label accuracy separately, with an independent
reference and documented ontology granularity. Estimate request counts and
costs before any future paid-run decision. No such request is made in this
audit.
