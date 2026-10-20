# Trial controls phase report

Base: PR #28, `1face3a5f29ae4668b0752018fad47c2e3f07c1b`.
Branch: `feat/trial-run-controls`; stacked review only. No merge or formal experiment.

## Completed implementation

- Entry points and dispatch use post-call actual usage/cost recording. Deprecated
  numeric budget arguments remain accepted but do not cap, pre-count or reserve.
  Unknown delivery still blocks automatic resend; unknown cost alone does not.
- Missing-key startup retains the configured provider. Explicit same-project retry
  is possible after configuring the key; no model-switching resume.
- Cooperative cancellation from the workbench or `sc_run_control`; durable local
  control receipts and existing state events record observed operational changes.
- Repeated evidence without progress falls back after two repeated tool rounds.
  Completed clusters/tool turns reuse existing checkpoints. Prepared, expired,
  never-dispatched requests may be prepared again; strict transfer approval applies
  to the new payload. Uncertain delivery retains its original request identity.
- Optional logical disk allowance defaults unlimited, stops at checkpoint/stage
  boundaries, and never deletes saved results. Essential audit writes remain possible.

## Abstractions and reuse

One small operational-control module and public setter were added. It reuses atomic
writes, existing stage events, provider ledger, ReAct traces, locks and checkpoints.
No new scheduler, monetary budget service, approval gate or scientific algorithm.
The Python cancellation route writes the same control document while the R worker
owns the project lock; it does not terminate another process.

## Validation status

PR #29: https://github.com/ChanghaoKan/scAgentKit/pull/29. No merge.
PR #26 (1675887), #27 (b5c468f), #28 (1face3a): all four exact-head workflows passed.
Local final targeted R tests passed (four old Core 0.1.1 tests skipped). Python:
397 tests passed, 15 environment-dependent skips. All 21 Node scripts passed.
Actual Chrome/R bridge storage and effective-limit checks passed.

The final installed-code public PBMC3k mock run completed three explicit scripted
approvals, 2,683 retained cells, eight clusters/eight tool calls, no fallback and
matching offline replay in 465.663 seconds. Implementation hash:
`23fed9ead6a12828c9370796c7ec2c5b9135b9428b1cebcf7b3e4cb264b15512`.
No paid provider call or accuracy experiment was run.

CI on da51a51 passed workbench, installed-runtime-contract and release-archive.
The complete R check passed 10,138 assertions but found one stale child-context
expectation of a $0.01 reservation. This follow-up changes that expectation to
zero; delivery-uncertainty and no-duplicate-callback checks remain. The matching
old-Core-only assertion is also updated. Production code is unchanged from da51a51.
The final follow-up CI status is recorded in the PR/delivery report.

Auxiliary local package check with optional Suggests allowed and tests/vignettes
omitted: zero errors, two missing-vignette warnings and one existing namespace note.
This is not substituted for complete CI. Earlier source/install mismatch failures
and obsolete-budget fixture failures are preserved in work logs, not counted as passes.

## Acceptance changes and paper milestone

Standards 1/4/12/13 gain entry consistency, operational recovery, replay and end-to-end
engineering coverage. Standard 16 is not solved by this change: scientific implementation
hash changes still invalidate older projects. Three approvals and save-not-approve remain.
This removes trial usability blockers for ReAct v1; formal evaluation, independent truth,
50k complete-flow acceptance and the remaining paper matrix are not claimed complete.

## Limits and deviations

Cancellation is cooperative; a current HTTP/computation may finish and incur cost.
Disk allowance is not an OS hard quota and may be exceeded between boundaries.
Resume restores completed stage/function boundaries, not an arbitrary R instruction.
Control receipts remain available if cancellation happens before state observes them.
No additional paid smoke, model qualification, formal experiment or merge was performed.
Monetary legacy branches were removed rather than retaining a hidden cap, following the
user's later decision that costs are only recorded after calls.

User instructions: `docs/user/TRIAL_CONTROLS.md` and `.zh.md`.
