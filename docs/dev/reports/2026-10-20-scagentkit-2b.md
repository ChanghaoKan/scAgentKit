# Stage 2B report — bounded annotation evidence loop

Status: implementation and local verification in progress; not a release.
Base: scAgentKit `edba33ac8528a7ccfc6ab6e4e0528f038bcf7210`, after #17 and #18
merged with all required checks passing. Core #3 merged at
`2ccf6a9df7cbdbd0fc03dddf96aa23d8afb277dd`.

## PR and commit range

The stage PR and exact head will be recorded in its GitHub description after
publication; the baseline above is fixed. Core compatibility prerequisite:
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
