# Bounded annotation sessions (2B)

This stage adds an opt-in engine path: `sc_run(..., react = list(mode = "all"))`.
`mode` is `auto`, `all` or `off`; NULL retains the legacy path. The public
`sc_start(react="auto")` default and trace interface are stage 4/3 work. The
single-turn transport contract remains in STRUCTURED_PROVIDER_TURNS.md.

The coordinator first validates the complete one-shot baseline with the
`scagentkit.annotation-draft.v1` risk envelope. Its proposal remains
`scagentkit.annotation.v1`. It processes selected clusters in sorted order,
preserving non-target rows. `auto` selects low confidence, Unknown/unannotated,
or ACT disagreement; disabling ACT removes reference information from the
baseline prompt, disables lookup and excludes ACT disagreement from selection.

Default limits are 6 model turns and 6 tool calls per cluster, 60 of each per
session, 180 seconds per cluster, and 60 seconds per tool. Limits and tool
allowlists are recorded in config. The wall-clock cluster deadline persists
across interruption and strict transfer approval waits: an expired cluster
falls back rather than acquiring a fresh time allowance on restart. There is
no monetary cap, token estimator or reservation. Single requests and structured
turns record usage and available cost after delivery; unavailable cost is not
zero. Uncertain deliveries are never automatically resent.

## Integrity and recovery

The session loads SHA-verified checkpoint bytes into one isolated worker,
checks worker implementation/schema identity, and locks its object environment.
The worker caches by tool, normalized arguments, input binding and schema hash.
Calls check file size, modification time and device/inode; these are alarms,
not cryptographic proof. Full checkpoint SHA verification runs before each
cluster result is published and before final completion. Metadata-preserving
edits therefore cannot publish a result. Scientific integrity faults block;
provider/format/limit failures preserve the baseline row and a specific reason.
No baseline yields `baseline_unavailable`, leaving manual annotation available.

The existing state checkpoint mechanism stores `annotation_react_run`,
`react_cluster_<hash>`, `annotation_react_citations`, `annotation_baseline_risks`
and provider turn/session receipts. A pending request is saved before dispatch;
a received tool-call queue is saved before execution. Completed clusters are
skipped after interruption. Existing locks, atomic state save, ledger and events
are reused; no second scheduler, database or approval system is introduced.
The future stage-3 JSON exports are projections of these bound checkpoints.

## Deterministic evidence checks

Every cited gene has one `pool` or `tool:N` source. Only saved, same-session,
same-cluster `cluster_markers` results admit genes outside the original pool:
`padj < .05`, positive fold change, greater within-cluster detection, and not
excluded. The validator reads saved tool statistics and verifies the result
hash. Model-supplied statistics, other clusters/sessions and gene_expression
cannot supply that authority. Expression is untested background evidence.

Manual edits preserve authority by cluster/gene. Label, confidence and rationale
edits retain citations; deleting a citation revokes that pair. A subsequently
added manual gene must meet the original pool rule. Review and approval bind
risk records, citations, cluster traces and provider receipts. Saving a draft
never approves it.

All new model drafts require the five enumerated `risk_flags.v1` records:
doublet_risk, batch_status, qc_celltype_concern, cycle_concern, ambient_suspected.
Assessed fields require current evidence IDs. This checks format and provenance,
not the biological truth of a model interpretation. Legacy records remain
explicitly unassessed; annotation.v1 itself is unchanged.

## Verification scope

See tests/testthat/test-run-react-loop.R and test-run-react-worker.R for the
mock loop, durable recovery, fallback, manual citation and integrity paths.
Existing provider-turn tests cover complete-history privacy and uncertain
receipt recovery. The pbmc_small coordinator test stops at unapproved third-gate
review; the three-gate accept-drafts acceptance test remains stage 4.

The 50k-cell synthetic performance receipt is in
benchmarks/react-session-50k/. Reproduce using tools/benchmark-react-tools.R to
prepare the synthetic fixture and tools/benchmark-react-session.R to measure
one session. It does not establish biological accuracy or the later full
50k-cell public-data pipeline acceptance criterion.

DeepSeek requires the optional-index compatibility patch in Core PR #5,
pinned in Remotes for review. No release tag was rewritten. xAI's native adapter
and protocol receipts are a separate M1 change; this stage does not mark it as
formally supported. Trace UI, export/replay and evaluation remain later stages.

The persisted absolute cluster deadline is part of the authorized request hash.
Immediately before dispatch, the actual HTTP timeout is reduced to the remaining
wall-clock allowance and recorded in the committed receipt. Pausing for strict
approval or resuming a pending request cannot reuse an older, longer relative
timeout. The wire body and consent hash stay unchanged; an expired deadline is
recorded as not sent.
