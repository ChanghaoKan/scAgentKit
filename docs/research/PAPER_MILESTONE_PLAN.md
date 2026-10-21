# Paper milestone and 1.0 development plan

Plan confirmed on 2026-10-20. The provisional paper milestone is **0.10**;
this version number does not announce a release or biological validation.
E0 establishes the protocol and plan. Formal experiments require the freeze
criteria in [evaluation protocol v2](EVALUATION_PROTOCOL_V2.md). Public claims
must stay within the [research scope](SCAGENTKIT_POSITIONING_V2.md).

The PR statuses below are dated records, not a live release tracker. Each PR
must identify its baseline commit, changed files, new abstractions, reuse of
checkpoints/ledgers/events, tests actually run and limitations. Existing
mechanisms must be reused where possible; parallel state stores, ledgers,
event systems and automatic-approval APIs are outside the plan. Stage reports
must record the PR/commit, changes to 1.0 acceptance and research evidence,
tests/CI, limitations, deviations and paper-milestone progress.

## Submitted PRs: recorded status

- [agentomicsCore #2](https://github.com/ChanghaoKan/agentomicsCore/pull/2), reviewed head `cab2b4002fbdb361f2cbed858f0cda08a100e270`: merged as `d9348c128609857ae4a722a26aa011c95f4aac5d`; [v0.2.0 was released](https://github.com/ChanghaoKan/agentomicsCore/releases/tag/v0.2.0), verified on 2026-10-20. This satisfied the dependency prerequisite for scAgentKit 2A.
- [scAgentKit #15](https://github.com/ChanghaoKan/scAgentKit/pull/15), reviewed head `703309b`: marked Ready and merged after R-CMD-check, release-archive and the other two CI checks passed; merge commit `7507f2d081a5a9a0af809921d47778da038cf03a`. The stage 1 baseline was `1936bb6cc244a24c4ff04775ca2e76f7b30f2ee7`, after #14 merged. The completed four-tool performance measurement on 50k synthetic cells is not a complete public-data workflow validation at that scale.
- E0 [#16](https://github.com/ChanghaoKan/scAgentKit/pull/16) used baseline `7507f2d081a5a9a0af809921d47778da038cf03a` and engineering-protocol commit `a7bb0c1507b3381f6977ac8f007d657fb0c11437`. It merged as `b5bfbb668c581b043449199343af355249c19fa6` after the required CI checks passed. Subsequent decisions update this plan; the original stage report is a historical record. Formal experiments had not been frozen.
- scAgentKit 2A [#17](https://github.com/ChanghaoKan/scAgentKit/pull/17) was submitted from baseline `b5bfbb668c581b043449199343af355249c19fa6`, head `141d7a90697d26579a83ebac104172d38269691e`. It implemented structured single-turn transport and session binding, without the loop. CI was pending at the time of this record; this entry does not establish a merge or working ReAct loop.
- Core [#3](https://github.com/ChanghaoKan/agentomicsCore/pull/3), head `8416a4499a8c05fd19146550a4a0ea31d4866efc`, documented the v0.2.0 response `assistant` role and its interaction with older mocks. CI passed; the PR had not merged. The published tag was not altered.

## ReAct v1 for the paper milestone

| PR/stage | Scope and expected files | Abstractions and reuse | Completion criteria |
| --- | --- | --- | --- |
| Stage 1 / #15 | Four tools, dispatcher, strict argument/privacy/size limits, cache, worker, tests and 50k synthetic performance record; `R/run-react-tools.R`, `run-react-dispatch.R`, `run.R`, DESCRIPTION, tests and developer documentation | Registry/context/dispatcher; reuse state, SHA, atomic writes and implementation fingerprints; no LLM loop | Both required CI checks pass; PR marked Ready and merged; reviewed and final commits recorded |
| Core 2A / Core #2 | Structured turn, request preview, tool calls, usage and delivery status; `R/chat-turn.R`, existing factory integration, exports/help, tests, version/NEWS | Single-turn protocol with the existing text interface and token recording; no tool execution or approval | Merge and release v0.2.0 |
| scAgentKit 2A | DESCRIPTION Remotes/Imports; provider/start/transfer/suggest, ledger and consent tests | Bounded multi-turn sessions and turn binding; reuse ledger/consent/event | Published Core release; privacy checks on the entire message history; usage/cost recorded after single requests and structured turns, without a monetary cap or pre-send cost estimate; no resend after uncertain delivery |
| 2B | `R/run-react.R`, outer citation/risk records, `inst/prompts/`, annotation prepare/review/history, configuration/hash, mock tests; updates to the existing dispatcher | Sequential loop; `annotation.v1` payload; the five outer risk categories for the third gate and production format validation delivered in 2B; a session-resident worker using the existing process mechanism | Baseline → auto/all/off; 6 turns/cluster, 60/session, 3 minutes/cluster; allowlist/ACT ablations and per-cluster recovery; full SHA checks at start/end, loading of the same bytes, and intermediate stat-change alerts; repeat warm-cache and complete-session performance measurements |
| 3 | Existing audit projections, workbench frontend/bridges, R/DOM tests, runtime manifest | Authoritative state with JSON projections; no new state store | Collapsible investigation trace, citation navigation, cost/fallback summaries; manual edits retain `(cluster,gene)` provenance; existing approval workflow |
| 4E | `R/react-eval.R`, `R/react-replay.R` (provisional), exports/help/tests; extension of shared v1 scoring | Public eval/replay; one CL mapping/scoring implementation; production tools and citation validator | All-cluster/difficult-cluster scores; CL distance ≤3; cluster truth 80/80; primary and strict accuracy reported together; external CSV, cost/token/step/fallback fields; key-free replay and difference report |
| 4 | Start API/argument forwarding, README, guides, examples, mock E2E, `tools/dev/smoke/react-real.R`, ACT manifest, NEWS | Existing startup/UI; no additional confirmation or approval layer | `sc_start(...,react="auto")`; mock acceptance of drafts at all three gates with `react="all"`; complete ACT provenance fields; manual real-data PBMC3k script and recorded execution status |

The first four tools are `cluster_markers`, `gene_expression`, `act_lookup` and
`cluster_context`. Tool citations must come from valid saved `cluster_markers`
rows for the same cluster in the current session: padj < .05, FC > 0,
pct1 > pct2 and genes outside the exclusion set. `gene_expression` provides
untested contextual evidence. Manual edits to labels, confidence or rationales
retain validated provenance. Deleting a citation removes its provenance;
new manual citations follow the existing pool rules.

When a valid baseline exists, model-capability, step, time or result-validation
failures fall back per cluster. Without a baseline, the status is
`baseline_unavailable`. Integrity failures block execution. Performance
optimizations do not alter this boundary: cached and resident data must have
the same verified scientific identity. Third-gate risks belong to the versioned
outer draft record, with the `annotation.v1` inner payload. Missing fields in
older or manual records are explicitly unassessed.

## Evaluation and biological methods for the paper milestone

| PR | Scope and expected files | New abstractions and reuse requirements | Dependencies and acceptance |
| --- | --- | --- | --- |
| **E0: protocol and research scope** | This protocol, scope document, milestone plan, benchmark README, external-method notes, manifest fields/examples and archived earlier proposals | Documentation only; no executable framework or package-hash change | Submit E0 first; record the engineering-protocol commit in the stage report. Exact models and empirical parameters are not yet frozen for experiments |
| E1: runner A | `benchmark/evaluation-v2/run_pipeline.R`, summary projections, fixtures/tests; reuse v1 counts-only preparation and run helpers | One policy configuration and `run_summary` projection, calling existing public suggestion/`sc_review`, checkpoint/ledger/event APIs | After E0, parallel with ReAct; mock three-gate accept/rules/fixed policies, failure/recovery, unsupported switches and truth isolation; reviewer=`benchmark-policy:<policy>` |
| E2: stability B / external import | Stability, external CSV/JSON adapters, tests; extension of v1 scoring | Shared label maps, CL handling and denominators; no second scoring implementation | E1; only replicate ID changes across N runs; hand-checked Jaccard/ARI/label-hierarchy metrics, missingness and ID mismatch; maintainer execution after verification of the official CellAgent version/command |
| E3: perturbations C | Sparse-integer perturbation generators, parameter/risk-field mapping, scores/tests | Fixed perturbation registry outside the package, shared integer/ID/hash checks; not a model tool | E1/E2; ten mechanisms and small fixtures; low-RNA cases use selected real populations, unknown types use visible-reference holdout; primary detection rate reads production-validated structured risk fields; first gate requires B1/B2, third gate requires 2B; unavailable capabilities return `unsupported` |
| **M1-xAI: primary matrix, priority** | Native Core Responses adapter, full output-item/tool/usage tests; scAgentKit capability/consent/ledger and model manifest | Extend the existing versioned provider envelope for opaque items; reuse turn/ledger/privacy mechanisms; no separate session store | Official `grok-4.7` capability and offline forwarding of the exact CASSIA model ID verified; complete preset/live smoke pending; 180 seconds/cluster; cost recorded only after calls |
| M1-OpenAI: formal product support | Separate provider PR with the same scope | Existing contracts; verification of each actual model | User-selectable provider, validated model manifest, public development-data N=3 `accept_drafts` usability checks; may follow the paper and does not block the primary matrix |
| M1-Anthropic: formal product support | Separate native Messages provider PR, tool-use/full-response/usage tests | Existing contracts; parameter and opaque-block verification for each actual Claude model | User-selectable provider, validated model manifest, public development-data N=3 `accept_drafts` usability checks; may follow the paper and does not block the primary matrix |
| E4: evidence metrics D / development runs | Trace adapter, evidence/calibration/ablation scoring, shared tests, development manifest/CSV/report | Use production validation and stable traces from 4E; no duplicate validator | ReAct 2B/3/4E; original-citation denominators, ACT/LLM/ReAct comparisons; development N=3 `accept_drafts` with mock and validated live providers; the same N=3 usability checks for other supported providers, separate from primary scientific conclusions |
| **B1: diagnostic-cluster QC** | Diagnostic checkpoint, typed QC overrides, MAD/preview/strategy/schema/UI/tests, methods appendix, NEWS | Read-only diagnostics and `(cluster,metric)` overrides; reuse approval, invalidation, MAD and selectors; first-gate outer risk record | After 2B merges, parallel with UI/4E/documentation; diagnostic identities before approval and recomputation afterward; relaxation requires at least N non-MT/ribosomal/stress genes among the top 5 positive markers (N=3 confirmed during development); effective thresholds/retention differences; conflicting overrides rejected, membership changes invalidate them |
| **B2: batch-correction necessity** | Harmony/recommend/B1 diagnostics, strategy schema, second-gate UI, tests/NEWS | Reuse design rank, `nested_biology`, kNN/Harmony; no new package dependencies; `batch_status` enumeration | Parallel development after 2B merges; integration requires shared B1 diagnostics; excess same-batch mixing, fixed-cluster neighborhood purity, within-type condition signal with ≥2 samples/condition; technical and biological metrics reported separately; no correction by default for absent effects or complete confounding |
| **E5: formal freeze, public-data and final holdout experiments** | Freeze receipt, data/model/comparator manifests, results/reports; independent paired human labels, CL/masks and import | Same scoring and audit outputs; no additional scientific semantics | ReAct v1 + B1 + B2 + E1–E4 + primary-matrix M1 complete; ≥3 eligible public datasets, N=5 and applicable ablations; freeze after qualification of DeepSeek + Grok and comparator presets; post-run usage/cost summaries by dataset × repeat × method; primary holdout results completed in this stage |

E1–E3 may be developed in parallel. After 2B merges, B1/B2 may proceed alongside
UI, 4E evaluation/replay and documentation. E3 generators need not wait for every
risk field, but first-gate detection acceptance requires B1/B2 and third-gate
detection requires 2B. Unimplemented capabilities must return `unsupported`;
the evaluator must not simulate scientific behavior. E-series PRs must not
include package-level scientific changes. Production validators check the risk
fields introduced by B1/B2 and 2B. Primary detection rates use these structured
fields; keyword matching is supplementary.

B1/B2 require rule-based fallback, minimal prefiltering and user approval.
Eligibility for B1 threshold relaxation does not establish cell health. Every
tightening or relaxation needs a rationale; other baseline metrics still apply.
B2 must not treat unchanged RNA data as evidence against overcorrection.
External evaluation also uses scIB-style truth ARI/NMI and cell-type preservation.

The primary paper matrix is **DeepSeek + Grok**. M1-xAI prioritizes Responses,
with `grok-4.7` as the specific candidate whose official capability has been
verified. Offline CASSIA exact-ID forwarding has been verified, but Flash
thinking parameters, Grok effort and endpoint differences require the
[qualification record](../../benchmark/evaluation-v2/manifests/model-qualification.md).
The complete preset and live API validation are pending; the product's Flash
default must not be changed implicitly. **All four providers are formal product
targets selected by the user.** Anthropic/OpenAI support proceeds in separate
PRs and may follow the paper. Other supported providers receive N=3
`accept_drafts` usability checks on public development data; these do not support
primary scientific conclusions or block the paper. The
[model and usage contract](../dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md) and
[E5 cost report](../../benchmark/evaluation-v2/manifests/E5_COST_REPORTING.md)
require post-run recording and comparison, without price-based selection or
pre-send monetary thresholds.

Public data first released after model training are a preferred supplement.
The unpublished final holdout and its provenance records provide the principal
support for the claim that evaluation data were unseen; they do not establish
that the model lacks prior knowledge of the same cell biology. The holdout must
not enter development, tuning or prompt design. Truth, CL mappings and agreement
masks are frozen before its first run. The maintainer executes `accept_drafts`
and rules policies without manually changing decisions. Work and results
previously assigned to E6 are included in E5; final-holdout validation does not
wait until after the paper milestone.

## 1.0 work after the paper milestone

The following work is required by the 1.0 plan but does not block the paper
milestone. Claims about the paper version must reflect these limitations;
planned work does not satisfy 1.0 acceptance criteria.

| Work | Minimum scope and reuse | Completion criteria |
| --- | --- | --- |
| M1-Anthropic / M1-OpenAI | Separate formal adapters for the remaining two providers; model manifests, protocol/usage tests, reuse of Core/ledger/consent | User-selectable providers; models outside the manifest marked `unverified`; public development-data N=3 `accept_drafts` usability checks; post-run cost reporting only |
| U1: input and startup | Structured sample-column confirmation, MEX declarations, one-time consent, input checks and timing explanations; start/metadata/tenx/UI | Explanations supported by measurements; no additional pre-send cost estimate, following the later decision |
| U2: evidence for the three gates | First-gate rationales tied to specific evidence, complete HVG information, second-gate evidence navigation | Existing v1 evidence identity; no second LLM validator |
| O1: portable results | `@misc$scAgentKit` audit projection, final figures/tables, researcher report, optional h5ad | RDS remains readable outside the project; audit records are append-only |
| C1: project updates | Proposed classification of scientifically equivalent changes, difference-confirmation receipts and migration regression fixtures | Original hashes/approvals retained; integrity failures and scientific-code changes block reuse; dependency minor versions alone do not prove equivalence. This proposal conflicts with the current no-migration development contract and requires a separate policy decision |
| P1: API/installation/documentation | `inst/api-contract.json`, semantic-version tests, convenient formal installation, clean-environment CI, a short starting guide | Tested on macOS/Linux; freeze after API stabilization |
| V1: public 50k complete workflow | Provenance, three gates, per-stage time and process-tree memory, failures/waiting | Separate from the completed four-tool synthetic benchmark |
| V2: 1.0 readiness report | Updated evidence for 18 criteria, PR/commit, CI, results/limitations and installation/project-update status | All required acceptance criteria met before claiming 1.0 readiness |
| R2: second-gate ReAct | Reuse scan/`adjacent_splits`/registry/loop; cached `compare_clusters` differences and tests; `cl_lookup` may be independent | No additional approval or repeated scan; satisfy the new retrieval component of criterion 6 |

## Critical path and stage reports

The initial critical path is **Core v0.2.0 → scAgentKit 2A → 2B merge**. It then
splits into two parallel branches: **3 (UI) / 4E (evaluation and replay) /
4 (documentation and release acceptance)**, and **B1/B2 (shared diagnostics and
risk fields)**. Both branches feed **E5 freeze / primary experiments / primary
holdout results → paper milestone**. B2 integration requires the shared
diagnostics. Final stage 4 release acceptance requires its prerequisites, but
neither constraint blocks B1/B2 development. The stage 1 merge is another
prerequisite for 2B. E0 → E1/E2/E3 proceeds alongside ReAct; E3 detection-rate
integration waits for 2B/B1/B2 risk fields. E4 completes when the traces and 4E
are available. Data/comparator qualification and M1-xAI proceed in parallel and
also block E5. Formal adapters and usability checks for providers outside the
primary matrix are not on the paper's critical path; the four-provider product
target still applies.

Each stage report must include:

1. PR link and baseline → head/merge commit range; the E0 protocol commit and E5 experiment-freeze receipt.
2. Changes to the 18 1.0 acceptance criteria. Approval of a plan cannot satisfy an uncompleted criterion.
3. Evidence supporting biological decisions, explicit decisions/reproducibility, citations, LLM assistance, ACT, same-model annotation and sustained use.
4. Tests, CI and experiments actually executed, distinguishing mocks, development runs, formal experiments and static inspection.
5. **Paper-milestone progress:** completed items, the next critical-path item, candidate/frozen status of the primary matrix, and formal support/usability validation for all four providers.
6. Known limitations, deviations from the plan and their reasons.

Scripted `accept_drafts` is not a human acceptance rate. N=3 development runs are
not formal stability evidence. Merged code is not biological validation.
External longitudinal cases and human-user studies may be added under separate
protocols; the paper must retain the corresponding limitations if these studies
have not been completed.

## Startup integration candidate: 2026-10-21

Stage 4 startup, examples and three-gate mock acceptance were implemented on the
local integration baseline of #22–24; see
`reports/REACT_START_STAGE_REPORT.md`. The new `sc_start` defaults to ReAct auto,
enables diagnostic evidence, obtains one-time external-transfer consent, and
records usage after both one-shot drafts and ReAct calls. The real-data PBMC3k
manual smoke test, ACT manifest review and full CI required for a formal release
still need separate acceptance. This candidate does not establish completion of
stage 4 or the paper milestone.
