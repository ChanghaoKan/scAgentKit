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

The final installed-source test pass and exact-head CI are recorded in the delivery
report. Earlier tests run while source and installed runtime differed are not treated
as final validation. A development PBMC3k mock run completed three scripted approvals,
8 clusters and replay with no fallback in 342.803 seconds, implementation hash
`5460cf4d4630e32b31a4fe06938f5a6c83ada9ff405864213b0a32734dec3bfa`.
That receipt predates the final provider authorization cleanup; it is not a final-head
live provider test and makes no biological accuracy claim.

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
