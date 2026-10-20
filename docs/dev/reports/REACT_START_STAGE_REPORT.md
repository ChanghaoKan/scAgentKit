# ReAct startup and three-gate acceptance stage

Development integration candidate; not a release or biological validation.

## PR and commit range

The candidate integrates #22/#24 (`df8e36095cda6842c39e5119e333faf8b3fa3e43`)
and #23 (`5a9032b7842ace2923eac303e7c70de6570abbf0`) locally at `8eb47b7`.
The PR description records its final submitted head and range. This does not
merge those candidates into main, whose baseline remains `49352181`.
Core remains pinned to released v0.3.0.

## Delivered and reused mechanisms

New `sc_start` projects default to ReAct auto and diagnostic-only QC/batch
checks. Processed reuse omits raw diagnostics. Reopening preserves the saved
configuration and rejects explicit conflicting settings. Interactive external
startup offers one aggregate-transfer confirmation; noninteractive callers
supply explicit consent or use strict payload review. Scientific approvals
remain separate.

Default one-shot drafts now use post-call accounting as ReAct already does.
No pre-counting, reservation or monetary cap is introduced. Missing cost remains
unknown; uncertain delivery prevents automatic retransmission. Explicit legacy
caps and existing project settings retain their previous behavior.

An additive `cost_mode` config/consent field selects the existing ledger path.
No new store, checkpoint engine, event mechanism, approval API or provider
adapter is added. Startup reuses existing configuration validation, transfer
consent, provider ledger, suggestion workers and three human review gates.
The implementation hash changes because the one-shot dispatch semantics change.

The full LLM example and English/Chinese guides cover startup, review, evidence
checks, failure fallback, recorded costs and offline replay. A public mock
example starts through the installed `sc_start`, adopts each complete draft,
then separately approves it through the existing review API. Its reviewer is
`benchmark-policy:accept_drafts`; it is not a package auto-approval feature.

## Validation

- Initial startup/transfer/E2E regression: 64 assertions, no failures/warnings/skips.
- Accounting, provider, transfer and suggestion regression: 472 assertions, no failures/warnings/skips.
- Integrated biology, diagnostics, ReAct tools/worker/loop/audit/evaluation/replay: 636 assertions, no failures/warnings/skips.
- All Node DOM suites passed; a focused posthoc display assertion also passed.
- Python: 394 collected, 15 skipped. Two first-pass failures came from relative
  local R library paths after subprocess directory changes. Both affected
  modules passed on rerun with absolute paths (three tests); no product change
  was needed for these environment failures.
- Final installed-example and native xAI mock regression: 51 assertions, no failures/warnings/skips.
- Limited local R CMD check: zero errors/warnings, one existing namespace NOTE
  for `getFromNamespace` in ReAct worker code (tracked by #21). Tests/manual/
  vignettes were excluded from this check. A full local check was unavailable
  because Pandoc and optional suggested packages are not installed; CI remains
  the full-check authority.
- Installed package build succeeded. No real provider, paid call or private
  held-out data was used.

Actual Chrome + installed R bridge completed all three gates on a fresh public
project: candidates adopted unchanged, three explicit approvals, final state
`complete`, 80-cell Seurat result, ReAct all with two tool calls, and offline
replay matching the saved draft. There were no external browser requests or
page errors. Final implementation hash:
`42fa3bdf4cad63fef4c320a70858b0722894e74b1ffe26e3ca32c13063d77bf1`.
The completion receipt records revisions 13→16→32, 34→37→47, and 75→79→85.

CI snapshot at submission: #22 has all four workflows green. #23/#24 have
workbench, installed-runtime and release-archive green; R-CMD-check remains
running on both exact heads. No failed CI item was found, so no speculative CI
patch was made. This integration PR starts its own CI after submission. Local
checks are not represented as remote CI completion.

## Acceptance status changes and paper milestone

Criteria 1/3/4: a default one-line development entry now includes the integrated
features, with one transfer confirmation and post-call usage. Earlier requested
cost forecasts/caps were intentionally removed by the user. Input-format and
failure coverage remains supported by existing tests, not newly established for
every platform here.

Criteria 7/8/12/13: integrated mock evidence demonstrates three saved, unapproved
model candidates, three explicit approvals, read-only ReAct all and API-free
replay. The fixed test is part of ordinary testthat discovery used by CI.
Criterion 18 gains concise English/Chinese guidance and complete examples.

Paper milestone: startup integration joins the submitted stage 3 UI, B1/B2 and
4E candidates. E1–E5, biological threshold calibration, public truth benchmarks
and formal experiments remain outstanding. This is not a claim that the paper
milestone or 1.0 is ready.

## Known limits and deviations

- The branch is stacked across three unmerged feature PRs so acceptance can
  exercise their combined behavior without merging them prematurely.
- Mock `pbmc_small` validates software control flow, not annotation accuracy,
  biological safety of thresholds, real-model reliability or 50k performance.
- One-shot posthoc accounting was included here because the old reservation
  path otherwise blocked the agreed default startup. Historical capped
  configurations are intentionally preserved.
- The 15 skipped Python tests are not claimed as executed coverage. Actual
  Chrome checks are manual acceptance, not claimed as browser coverage in CI.

Stage 4 release scope still includes the public PBMC3k real-provider smoke
script/run and final ACT manifest/release review. This report completes the
requested startup/example/software-acceptance substage, not those unexecuted
release requirements.

Browser-driver development exposed assumptions in the acceptance harness:
read-only inspection may return a stale-binding/lock conflict while a worker
commits a new revision; the two strategy gates can share a stage name and even
a proposal hash. The driver now waits for completed computation nodes and retries
only those transient reads. It never retries a decision or provider request.
