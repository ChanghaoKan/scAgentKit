# Resource capacity, deadlines, paging and storage — 2026-10-21

Base: #27 / fb3fa34ff4439a4ea006ebff7407bb0e18bfac75. Stacked draft; no merge authorization.

## Delivered behavior

New ReAct policies default to `max_payload_bytes="unlimited"`: no arbitrary application request-byte quota. A finite user-selected 1–1,000,000-byte quota is still supported and hash/consent bound. One-shot and conversation paths use the same saved setting. Requests without this optional field also have no application byte quota; explicit saved finite policies remain unchanged. An increased finite quota or unlimited request cannot inherit a smaller project transfer allowance.

The former hard-coded scan 60,000 bytes and the intermediate proposed 60% share were application choices, not provider limits; neither had a model-context basis. For new finite policies the scan receives the remaining measured prompt space after the other aggregates and system prompt, with a small conservative empty-placeholder allowance. Unlimited policies retain the full scan projection. Existing source hash, split inventory and omission accounting remain. The complete request still passes its final size check. No byte-to-token conversion or invented model context size is introduced. The preview explicitly reports model context capacity as unknown; provider-specific context admission is pending. A provider context rejection follows existing failure/fallback handling, without automatic resend.

Default sc_start whole-worker timeout is derived from the saved provider timeout, startup/finalization allowance, tool initialization allowance and the ReAct session-step/cluster-time limits, capped at 24 hours. Explicit model_timeout remains possible (1–86,400 seconds). This removes the unconditional 300-second cutoff in this entry point; lower-level operator CLI defaults remain explicit. Internal provider/tool/cluster deadlines and interrupted/uncertain-delivery reconciliation remain. A dedicated user cancel action is not implemented. Very large custom policies can still reach the 24-hour operator safety bound; it is not a provider limit or monetary budget.

Read-only cluster_markers and act_lookup accept offset-based continuation. Each response includes offset, returned/available counts, partial status and next_offset. Fixed input bindings, stable sort order, normalized arguments and schema-aware cache keys preserve page identity. Tool schema becomes v2; marker citations still require the same saved statistical evidence and exclusions. Per-call result and argument limits remain, and gene queries remain bounded. No cells or paths enter model tool responses.

The workbench adds on-demand local storage measurement. It counts logical file bytes, skips links (directory opens use no-follow), reports partial lower bounds when the bounded scan ends, and never deletes data. Documentation explains whole-project archival after workers stop, verification of copied hashes, and separate preservation of inputs/environment. A review bundle is not a full project archive.

Effective byte settings and outer worker time are visible in the existing suggestion panel. Post-call cost accounting is unchanged; unknown costs remain unknown. The older explicit monetary-cap dispatch branches remain pending cleanup; this capacity checkpoint does not claim all entry defaults are unified yet.

## Verification and status

Initial targeted checks exposed pagination fields missing from the strict public-output allowlist and a size-error fallback relying on the old literal message. Both were fixed: only the new numeric paging fields are permitted, and size rejection has a structured condition class. An intermediate startup attempt correctly rejected a stale runtime manifest after UI edits; final checks use a rebuilt installed candidate. An initial parallel eval integration assertion reported accuracy 0 instead of 1; its isolated rerun and final serial run passed. The transient cause was not established, so that first run is retained as a failure. The final serial integration batch is recorded in the accompanying report rather than treating the initial run as passing.

Offline cases cover finite rejection, >1 MB unlimited acceptance, changed-request hashes, full marker-page coverage without duplication, ACT continuation, invalid offsets, strict privacy checks, existing consent/fallbacks, replay, and native startup configuration binding. Python covers no-follow storage/no deletion/partial counts and worker limits. Node suites exercise production UI source. Full CI on the submitted candidate remains required.

#25: all four CI workflows passed at audit. #26/#27: release-archive, workbench and installed runtime passed. Both R-CMD-check runs failed on the same stale MAD test assertion: it read quality.mad after exact duplicate evidence was moved to canonical qc_mad. The correction verifies qc_mad, absence of the redundant copy, and the alias target/hash. Fresh CI is required; no failure is bypassed and nothing is merged.

## Not delivered / limitations

No verified per-model token admission, adaptive cross-model context negotiation or new first-gate retrieval loop. Unlimited removes an application quota, not physical RAM, provider context, HTTP or service constraints. Very large unique evidence can still require provider fallback/manual review. No large-real-data scientific accuracy result is claimed.

No optional project disk allowance yet, nor configurable ZIP/display/journal expansion, journal segmentation, automatic archive or free-disk reservation. The subsequently relayed preference for an optional project disk allowance is a separate pending checkpoint; it must stop at safe writes without deleting completed records, not kill unrelated R processes. Existing ZIP protections remain. Storage measurement is a live, bounded logical-size snapshot, not a consistent archive manifest. Existing project integrity/scientific implementation changes still block incompatible resume. Existing run checkpoints already reuse saved completed stage outputs, and completed ReAct clusters are skipped on resume; this is stage/function-boundary continuation, not instruction-level recovery inside an unfinished computation. No new recovery engine is added. ReAct stops when a no-tool response passes final draft/citation validation, not merely when any model response ends. Repeated tool evidence is cached; repeated no-progress model turns currently terminate through existing step/time guards, without a separate stagnation detector. Those guards are retained as loop-safety controls, not monetary quotas.

## Acceptance, complexity and paper milestone

Advances standards 1/7/12 through public configuration, continuation evidence and replay validation; does not close standards 11/14, 50k whole-pipeline validation or 1.0 readiness. ReAct tool and prompt/implementation hashes change (aggregate-review.v5). Existing approval structure is unchanged.

New abstractions: one byte-setting decoder and one read-only local storage measurement function/schema. Reuse request hashing, project consent, scan projection, worker deadlines, tools, cache, citation checks and replay. No new coordinator, budget system, scientific approval action or data-deletion policy. Deviations: optional model-context enforcement and storage-format migration remain separate work; arbitrary byte/percentage defaults were removed instead of being presented as validated model budgets.

## Public development smoke

The first real DeepSeek request stopped at gate 1: the draft omitted required diagnostic resolutions, and a risk field cited a noncanonical evidence ID. No scientific approval occurred. Prompt v5 explicitly states the required scan and canonical evidence IDs; validation was not relaxed. The failed run is preserved (actual cost $0.0076458).

A deliberate fresh-project retest with DeepSeek deepseek-flash completed all three scripted approvals on public PBMC3k, with 2700 output cells, 16 tool calls, 8 completed ReAct clusters, no fallback, and matching offline replay. Elapsed time: 415.715 seconds. Actual usage: 175543 input and 9129 output tokens; recorded cost: $0.052591524. Implementation hash: 7e1a6737e516160667074b2d2a0ea2f9fa5f57e792e922455460297e312202df. This receipt belongs to that installed implementation, not subsequent candidate revisions. It is engineering validation, not truth-label accuracy or a paper experiment.
