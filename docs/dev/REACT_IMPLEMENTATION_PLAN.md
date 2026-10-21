# ReAct annotation implementation plan

This plan records the approved scope for evidence retrieval before the third
scientific approval. The first implementation contains four internal read-only
tools. It does not enable model tool calling or change the public annotation
workflow. Each subsequent stage has its own pull request.

The approved 2026-10-20 [paper milestone plan](PAPER_MILESTONE_PLAN.md)
integrates this first release with B1/B2 and evaluation E0–E5. It records the
paper/1.0 split and provider-specific M1 work. The [evaluation protocol](EVALUATION_PROTOCOL_V2.md)
is the authority for scoring definitions and experiment gates; its engineering
approval is not a formal experiment freeze.

## Scope and sequence

| Stage | Deliverable | Dependency |
| --- | --- | --- |
| 1 | `cluster_markers`, `gene_expression`, `act_lookup`, `cluster_context`; strict arguments, bounded aggregate results, frozen evidence, caching and time limits | PR #14 merged; rebase on the resulting main; record baseline commit in the PR |
| 2A Core | agentomicsCore v0.2.0 structured turn protocol and offline tests, retaining old text interfaces | May proceed alongside stage 1 |
| 2A scAgentKit | Adopt the published Core release; session consent, complete payload hashes, per-turn usage/cost records and delivery status | Core v0.2.0 release |
| 2B | Bounded sequential ReAct, baseline fallback, durable cluster progress, citation proofs, third-gate outer risk enums with production format validation, and tool/ACT ablations | Stages 1 and 2A |
| 3 | Verified audit projections, per-row trace display, citation links and run statistics | Stage 2B authority records |
| 4E | Mandatory first-release evaluation, external baseline import, hierarchical CL scoring and offline replay | Stage 2B records and stage 3 audit projections; complete before or alongside stage 4 |
| 4 | Public `react` option, bilingual guidance including reviewer replay, examples, mock end-to-end tests and a manual real-provider smoke script | All earlier stages, including 4E |

Core protocol work could continue independently while stage 1 waited for
PR #14. That gate is now met: PR #14 was merged, and stage 1 was rebased onto
main commit `1936bb6cc244a24c4ff04775ca2e76f7b30f2ee7` before implementation
resumed. The stage 1 PR must retain this baseline in its description.

Stage 1 performance acceptance uses 50,000-cell synthetic sparse Seurat fixtures,
with machine configuration and separate cold/hot cache timings. It measures the
four tools, not biological accuracy or full marker discovery performance.
`compare_clusters` and `cl_lookup` are deferred to the post-paper R2 work.
DeepSeek remains the initial implementation. Product support targets all four
providers, chosen by the user: DeepSeek, OpenAI, Anthropic and xAI. Each has a
separate M1 PR. Paper experiments use DeepSeek plus Grok; M1-xAI is first,
using Responses with grok-4.7 as the documented candidate. Anthropic/OpenAI
remain formal product targets and may follow the paper milestone. Exact model
and comparator settings require development qualification, not a cost quote.

Once 2B merges, B1/B2 proceed in parallel with stage 3 UI, 4E evaluation/replay
and stage 4 documentation work; they do not wait for every ReAct v1 stage to
finish. B2 integration still needs the shared B1 diagnostic checkpoint. Final
release acceptance retains its stated prerequisites. E3 injectors can develop
earlier, but first-gate discovery-rate integration requires B1/B2 production
risk fields, and third-gate discovery requires 2B fields. Until available, those
capabilities are unsupported rather than scored through keyword substitutes.

Every PR description must name its new abstractions, explain whether existing
checkpoints, the provider ledger and events can serve the same purpose, and
reuse those mechanisms wherever possible. No parallel state authority, billing
ledger or event system is planned.

Expected change areas (new file names after stage 1 remain provisional):

| PR | Expected files |
| --- | --- |
| 1 | `R/run-react-tools.R`, `R/run-react-dispatch.R`, dependency fingerprint in `R/run.R`, `DESCRIPTION`, focused tests, `tools/benchmark-react-tools.R`, benchmark records and development plan |
| 2A Core | Core `R/chat-turn.R`, legacy factory compatibility in `R/chat-providers.R`, protocol tests, package metadata and generated API help |
| 2A scAgentKit | `DESCRIPTION`, `R/run-provider.R`, `R/start-provider.R`, transfer-consent helpers and provider/consent tests |
| 2B | New `R/run-react.R`, citation-proof helpers, `inst/prompts/`, annotation prepare/review/history integration, `R/run.R` configuration/fingerprint, recovery and ablation tests |
| 3 | Annotation audit projections and `inst/workbench/static/app.js`, corresponding R/DOM tests; rebuild the existing runtime manifest |
| 4E | New evaluation/replay R entry points and tests; reuse `benchmark/evaluation-v1/` data preparation/label maps and existing CL mapping; evaluation exports and replay fixtures |
| 4 | `R/start-api.R` and engine option plumbing, public exports/help, README quick start, bilingual user guides/examples, mock end-to-end tests, `dev/smoke/react-real.R`, ACT manifest and `NEWS.md` |

## Citation and editing contract

The existing `annotation.v1` proposal remains intact. A versioned outer record
will bind citations and tool results to that proposal and its scientific review.
Stage 2B must deliver all five required third-gate outer risk fields, including
`doublet_risk` and `ambient_suspected`, and their production format validation.
E3 uses these records for the primary discovery metric; the UI/evaluator must
not create them later. The same outer draft record includes those risk fields;
the existing `annotation.v1` payload and strategy free-text risk field remain
unchanged. Production validators check format, enumerations and binding. Missing
legacy assessments are explicitly unassessed, not negative. See the protocol for
the scope, source and assessment-status contract.

Pool citations retain the existing rules. An additional tool citation must come
from the current session's `cluster_markers` result for the same cluster. The
saved FindAllMarkers row must have `p_val_adj < 0.05`, `avg_log2FC > 0`,
`pct.1 > pct.2`, and must not be excluded. Validation reads these statistics from
the saved tool result, never from a model's claims.

`gene_expression` is descriptive, untested background evidence, including
negative evidence. It cannot satisfy the requirement that a known label have a
supporting marker. It does not calculate an additional FoldChange or p-value.

Source identity is bound to `(cluster, gene)`. Editing a label, confidence or
rationale retains verified tool citations. Removing a citation removes its
source record. A newly added manual citation must satisfy the original pool
rules; an unverified `tool:` string grants no authority.

## Session, accounting and recovery contract

The initial DeepSeek adapter uses thinking disabled and temperature zero.
The planned four-provider product has a user-selected provider and a dated
validated-model list; support must be earned per adapter/model, not inferred
from a configurable name. A successful independent one-shot draft is saved before
ReAct. The former single guided request becomes one bounded multi-turn session,
without adding a scientific approval or granting the model approval authority.

The default `react="auto"` session scope is included in creation-time aggregate
transfer confirmation. Strict mode requires approval of each exact outgoing
payload. Every turn has a separate payload hash and ledger entry. New structured
turns have no monetary cap: record provider usage and costs after each response,
without added token counters, safety factors, pre-send estimates or reservation
prerequisites. Single-request and structured-turn calls both use post-call
accounting without monetary caps or reservations. Unknown price or usage remains
unknown rather than zero and does not itself prevent a new structured request.
Uncertain delivery is never automatically resent. Reuse the existing ledger,
consent and events. The [provider contract](PROVIDER_MODEL_AND_USAGE_CONTRACT.md)
defines model qualification, complete protocol history, refusals and post-run
cost reporting. No pre-run total-cost estimate gates model choice or a stage.

M1-xAI uses Responses and preserves the ordered response output items, including
encrypted reasoning, in the same session. Use store=false and explicitly request
reasoning.encrypted_content; this avoids relying on stored response IDs but is
not a blanket zero-log-retention promise. Opaque content is protocol state, not
biological evidence. Grok reasoning cannot be disabled; effort and sampling are
provider-specific and remain unfrozen until matched-comparator qualification.
CASSIA's native Grok path uses legacy Chat and the default high effort; it does
not forward a requested effort. This endpoint difference is disclosed. Existing
180-second cluster deadlines remain, despite vendor advice for longer requests.

Failure falls back to the saved one-shot row. If no valid baseline exists, the
status is `baseline_unavailable` and the existing local/manual draft remains.
Scientific integrity failures continue to block operations.

All effective limits are saved in configuration. The initial defaults are six
model turns per cluster, sixty turns for the annotation session, three minutes
per cluster, and sequential cluster execution. Tool execution has a sixty-second
maximum and must also respect the cluster's remaining deadline. Background
worker deadlines leave time to persist progress and fallback status.

Stage 2B replaces per-tool process startup/full checkpoint hashing with a
session-lived worker. Under the existing project lock, verify and deserialize the
same bytes (or a verified worker-private immutable copy) and pin all four tools'
inputs in memory. Per-turn regular-file/symlink, size, mtime, inode and scientific
binding checks are early alarms only. Before publishing a final draft, fully
verify checkpoint SHA and current scientific/history bindings again, allowing
legitimate ledger/event appends. A hash-before/read-original/hash-after sequence
alone is not a sufficient loading guarantee. Cache content must be verified
against the same identity. The external controller still kills timed-out workers;
recovery fully verifies inputs and never automatically resends uncertain delivery.
Citation, risk and session-verification records join the existing approval-bound
evidence file set. Integrity errors block rather than becoming fallback. Measure
session setup, cold/hot tools, final verification and memory separately.

The recorded configuration also includes an explicit allowed tool list
(`config$react$tools`) and an ACT-evidence switch. Disabling ACT evidence must
cover the ACT comparison/trigger and all ACT material supplied to the model,
not just remove `act_lookup` from the tool schema. Effective configuration
participates in cache, session and resume identity and is exported with every
evaluation.

The coordinator owns cache and audit writes. Tools cannot modify analysis,
metadata, parameters, proposals or approvals. Immutable per-cluster checkpoints
and their hashes are committed through `state.rds`; readable JSON traces are
projections. Completed clusters are reused on recovery, with exact evidence and
configuration checks.

## Privacy, identity and release acceptance

Tool caches bind canonical arguments to the selected analysis/markers/reference
and diagnostic checkpoints, configuration, implementation and tool schema.
The original input hash alone is insufficient. The entire outbound conversation,
including tool parameters, results and errors, must pass aggregate-only
projection and privacy checks. No cell IDs, per-cell matrices or local paths are
sent to the model.

Complete bounded tool results are retained for verification and replay; a
truncated UI preview is not the authority. Scientific approval binds the
baseline, resulting draft, trace manifest and citation proofs.

Before the public release, ACT provenance must include a source URL, download
date, publisher version when available, and license terms. Unconfirmed items
must explicitly be `unknown`, not empty. CI uses mock providers only. The
PBMC3k real-provider script runs manually, with recorded tool calls, elapsed time
and cost; no cost or accuracy claim is inferred from mock execution.

Implementation changes invalidate the established execution fingerprint. Old
project hashes and approvals must not be rewritten to force continuation.

## Required evaluation and offline replay

`sc_react_eval(project, truth, ...)` is required in the first release. Reuse the
data preparation and label maps in `benchmark/evaluation-v1/`, the existing CL
mapping, and the committed run records. External methods use the same scorer
through CSV input containing `cell_id` or `cluster_id`, plus `label`. Any
cell-to-cluster aggregation policy and coverage must be explicit and recorded.

Report both the fixed set of difficult clusters (those examined by ReAct) and
all clusters, using the same cohorts for the one-shot, ReAct and external
predictions. For each cohort, report exact CL matches, ancestor matches along
one or more `is_a` edges, Unknown proportion, and unmapped-label counts.
Unmapped labels are excluded from the scored denominator rather than counted
as errors; export denominator and mapping coverage to make this visible.
Also report strict accuracy beside it, retaining unmapped predictions in the
denominator as errors. Ancestor distance is capped at three; cluster truth
requires 80% valid-label coverage and 80% dominance within valid labels.
The protocol fixes matching direction, allowed ancestors, Unknown handling and
all denominators. Costs and tokens are annotation-level totals; also export
per-cluster steps, fallback rate, fallback reason counts and effective ablation
configuration. Baseline and additional ReAct costs must be distinguishable.

`sc_react_replay(project)` requires no API key and never calls a provider.
Replay consumes saved model responses and complete tool results, verifies
checkpoint/configuration identities, reruns the read-only tools and citation
validator, and reconstructs the final draft. It reports differences against
the saved tool results and draft without replacing the originals. Missing or
corrupt records produce explicit diagnostics. The trace format must therefore
be versioned, exportable and sufficient for both replay and evaluation.

## Confirmed 1.0 audit and stage reporting

The 1.0 gap audit was performed after stage 1 was submitted and was confirmed
by the maintainer. Its gaps are now assigned in the paper milestone plan;
confirmation does not imply those gaps have been implemented or validated.

The audit covers one-line startup and input normalization; startup behavior
and graceful fallback; evidence-backed drafts at all three approvals;
annotation and CL mapping; draft/approval separation; portable Seurat audit and
researcher-facing outputs; evaluation on three public truth-labelled datasets;
keyless replay; a fixed mock three-approval CI test; a public 50,000-cell full
workflow benchmark; API freeze and semantic versioning; patch-compatible
project migration with audited environment differences; supported platforms
and simple installation; and concise user documentation.

The stage 1 synthetic tool benchmark is distinct from the future 1.0 public
50,000-cell full-workflow benchmark. Neither substitutes for the other.
The audit report must end with a consolidated v1/v2/independent-release
roadmap and its critical path. ReAct v1, B1/B2, E0–E5 and the primary M1 provider
are the paper milestone (tentatively 0.10); U1/U2/O1/C1/P1/V1/V2/R2 follow it
as 1.0 work. The unpublished final holdout is a primary E5 paper result.

Each completed stage must provide a stage report containing PR links and
commit ranges, changes in the relevant 1.0 acceptance criteria, test and CI
results, known limitations, and deviations with reasons. Before 1.0, combine
the verified evidence in a readiness report suitable for external review.
Each report also states positioning-evidence changes and paper milestone
progress. E0 records its engineering protocol commit; E5 separately records
the formal experiment-freeze receipt and protocol revision.
