# Stage 2B report — bounded annotation evidence loop

Status: implementation and local verification in progress; not a release.
Base: scAgentKit `edba33ac8528a7ccfc6ab6e4e0528f038bcf7210`, after #17 and #18
merged with all required checks passing. Core #3 merged at
`2ccf6a9df7cbdbd0fc03dddf96aa23d8afb277dd`.

## PR and commit range

Stage PR: [scAgentKit #19](https://github.com/ChanghaoKan/scAgentKit/pull/19).
Implementation range: `edba33a..38b4e3b`; later documentation-only receipt commits
are identified by the PR head. The baseline above is fixed. Core compatibility prerequisite:
[Core #5](https://github.com/ChanghaoKan/agentomicsCore/pull/5),
`2ccf6a9..9799ab4`, optional DeepSeek tool-call index handling. That PR's
R-CMD-check passed; it remains unmerged. This branch pins its exact commit.

## Changes against acceptance criteria

- 7, partial: the engine now executes bounded read-only annotation retrieval,
  checks saved citations and produces a draft; UI, public startup default and
  full evaluation remain pending.
- 8, preserved: all mock coordinator results stop before approval. Citation
  provenance survives permitted manual edits without granting model authority.
- 9, partial foundation: session/cluster/risk/citation receipts enter bound
  project state and decision history; portable final-object audit is later work.
- 11/12, not completed: stable saved messages and results are available for 4E,
  but no public evaluation or replay function is claimed here.
- 13, partial: pbmc_small mock annotation reaches the third review without
  approval; the fixed three-gate acceptance test remains stage 4.
- 14, not completed: 50k synthetic tool performance is measured below; this is
  not a full public-data analysis or biological validation.

## Tests and CI

Local verification receipts and CI status are appended to the PR description
for its exact head. All tests use mock transport; no real API runs in CI.
The stage adds loop/recovery/fallback/manual-reference/risk validation tests and
reuses the existing transport privacy, delivery and ledger tests.

## Performance

Apple M5, 10 logical CPUs, 16 GiB memory, macOS 26.5.1 arm64, R 4.6.1.
Synthetic 50,000 cells x 20,000 genes, with saved synthetic marker statistics.
No FindAllMarkers, real annotation, or accuracy experiment was performed.

| Tool | Cold seconds | Hot median seconds (3 repeats) |
|---|---:|---:|
| cluster_markers | 0.061 | 0.056 |
| gene_expression | 2.348 | 0.045 |
| act_lookup | 0.055 | 0.055 |
| cluster_context | 0.044 | 0.037 |

Initial context verification: 12.128 s; verified worker loading: 13.762 s;
final full verification: 1.800 s. OS cache was not flushed. Each result hash
matched across cold/hot calls; all four tools met 60 seconds. Raw machine,
configuration and timing receipts are in ../benchmarks/react-session-50k/.

## Abstractions and reuse

Three modules: persistent read-only worker runtime, deterministic evidence/risk
validator, bounded cluster coordinator. Reuses existing tool registry, state
checkpoints, locks, provider ledger, transport receipts, events and approval
validator. No second audit store or scientific approval mechanism is added.
The implementation hash includes versioned prompts and tool schemas.

## Known limits and plan deviations

- `sc_run(react=list(...))` is opt-in; sc_start default and trace UI are later.
- JSON trace export and offline replay are not yet exposed; authoritative state
  checkpoints already contain complete requests/responses and tool results.
- Strict transfer approval waits consume the persisted cluster wall-clock
  deadline. Expiry safely falls back; it never resets the allowance.
- Core #5 is an additional prerequisite discovered by real protocol smoke.
- No monetary estimate/cap is added. Old one-shot accounting stays compatible.
- Scientific input changes still block. No existing approval is migrated.

## Paper milestone progress

The 2A prerequisite is merged. 2B implements the main retrieval path; M1-xAI
continues alongside it. After 2B acceptance/merge, B1/B2 can proceed alongside
trace UI and 4E evaluation/replay. E3 discovery metrics will use these versioned
risk fields. No formal experiment or biological benefit claim is made yet.


## Additional verification receipts

Final targeted run before the process-stop fix: 59 cases, 420 passing assertions
and one failure exposing asynchronous worker termination. The fix waits for
termination before allowing continuation; all 19 worker assertions then passed.
A fresh fixed-source full suite and GitHub checks are in progress; do not count
the earlier overlapping source/install run as valid full-suite evidence.

Authorized DeepSeek synthetic engine runs exercised all four read-only tools.
A deliberately three-call tool bound caused step_limit fallback (2 provider
requests, 3 tool calls, 5.487 seconds). With default six limits, two independent
new-project runs each used 3 provider requests / 4 tools (~8.4 seconds) and
returned invalid_draft fallback. The captured diagnostic response included
prose before JSON and cited ACT lookup as marker support. The first fails the
JSON contract; the second is independently inadmissible under the marker-only
citation rule. The baseline Unknown was retained and never approved. No
uncertain request was retried. These demonstrate real fallback behavior, not
successful DeepSeek final-draft qualification or biological accuracy.

Raw per-call usage is committed in ../benchmarks/provider-smoke/; DeepSeek
returned no explicit monetary cost, so it remains unknown. No further provider
requests are needed to diagnose this result. The Grok integrated successful
synthetic draft is reported separately in M1-xAI, not attributed to this branch.

Manual-review regression follow-up: a saved manual deletion previously projected
the pre-edit citation set into the review while committing the reduced citation
authority. The new actual-save test reproduced the stale-review failure. The
fix rebuilds the evidence projection after pruning citation authority, before
publishing review/pending state. The four integration assertions now pass:
review verifies, approval remains absent, the third gate is pending, and the
removed outside-pool gene cannot be re-added manually.
