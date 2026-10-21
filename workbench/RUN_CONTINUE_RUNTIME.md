# Local background continuation interface

The optional server runtime is `RunContinueRuntime(project_dir, library=None,
rscript="Rscript", threads=2)`. Project, library, executable and thread count are
operator configuration. HTTP cannot set them. This feature checks for POSIX
`flock` when enabled and adds no unconditional `fcntl` import. This increment does
not establish support for the existing workbench on Windows.

`describe(run=None)` performs a fresh read-only R project-format check, then
reads saved JSON and a nonblocking job lock. Polling does not start scientific
analysis or a model request. A supplied full inspector may be used for the
availability binding; otherwise the existing `status.json` convenience projection supplies it. That projection
only rejects obviously stale requests. The fixed R `sc_run_continue` call
revalidates authoritative state, input, implementation, approval and revision
under the existing R project lock before changing scientific state.

`submit(payload)` accepts exactly:

```json
{
  "project_id": "the literal inspected project ID",
  "input_hash": "the exact lowercase SHA-256 input hash",
  "expected_revision": 12,
  "request_id": "a fresh browser nonce",
  "retry": false
}
```

The server checks same-origin CSRF before calling this method. A request ID binds
all five fields. Repeating it returns the same persisted job without launching a
worker. A second tab with a different nonce and the same four execution-binding
fields may reuse an active job; its nonce is durably recorded too. Changing a
recorded nonce's fields is rejected. A new execution uses a new nonce.

GET inspection and polling return:

```json
{
  "schema": "scagentkit.run-continue.workbench.v1",
  "enabled": true,
  "job": null,
  "availability": {
    "can_continue": true,
    "can_retry": false,
    "requires_explicit_retry": false,
    "reason": "ready",
    "project_id": "literal ID",
    "input_hash": "exact hash",
    "expected_revision": 12
  }
}
```

When present, `job` contains `job_id`, `status`, `request_id`, `project_id`,
`input_hash`, `expected_revision`, `retry`, `created_at`, `updated_at`,
`next_run_status`, `next_run_stage`, `next_run_revision`, `error`, and
`retry_permitted`. `error` is null or an object with fixed safe `code` and `message`.
POST returns the same shape plus the boolean `duplicate`.
An explicitly restored terminal job also includes `restoration_sha256`, identifying
its local restoration receipt.

Job statuses are `queued`, `running`, `succeeded`, `failed`, and `interrupted`.
`succeeded` means the local call reached a verified stop point. The scientific
result is complete only when `next_run_status` is `complete`. Review, configuration
and provider boundaries remain explicit stop points. After a terminal job, fetch
the full inspector before using new scientific bindings or approving another node.

Availability reasons include `ready`, `job_active`, `owner_still_alive`,
`explicit_retry_required`, `complete`, `scientific_review_required`,
`configuration_required`, `unsupported_failed_stage`, and `not_ready`.
Failed/running R retries are restricted to the coordinator's local calculation
stages: prefilter, qc_evidence, qc_apply, analysis, strategy_evidence,
strategy_apply, strategy_selection, strategy_preprocess, strategy_basis,
strategy_batch, strategy_neighbors, strategy_cluster, markers,
annotation_evidence, annotation_apply and finalize (`LOCAL_RETRY_STAGES` in
`run_continue_runtime.py`). Proposal failures need manual R configuration.
A failure requires an explicit new request with `retry=true`. The worker and its
R child hold the job flock for their whole lifetime, so acquiring the flock is
the proof that no owner is still running; a missing launch record or a reused
PID therefore cannot leave a job permanently active.

All job state lives in the same project's `.workbench-jobs`, with private atomic
JSON records and a cross-process flock. The detached worker and its fixed R child
inherit the same lock descriptor, so closing the browser/server does not stop
work or permit another server to launch duplicate calculation. Polling reconciles
a dead active owner to `interrupted` without automatically rerunning it. The
scientific R lock is never deleted or bypassed. A stale R lock or unknown worker
owner requires inspection through the existing R recovery procedures.

There is no synchronous analysis timeout. R stdout/stderr are discarded, not
sent to the browser or written to job logs. Private records retain process IDs,
exit codes, code/config hashes and verified stop summaries. Provider keys are
removed from both worker and R environments. The fixed analysis bridge has one
operation,
`sc_run_continue`, and accepts no R code, callbacks, provider configuration or
browser-selected paths. No new AI request is dispatched by this feature.

The mechanism tests use real detached Python processes and an explicitly fake
Rscript executable. They test process/descriptor behavior rather than claiming
real R or biological validation. Actual R/browser acceptance is a separate check.
This local mechanism does not add authentication for multiple HPC users, perform
scheduler submission, or repair non-POSIX filesystems.

## Restore a complete terminal-job backup (unreleased)

A full backup copied back to its original path has new filesystem directory
identities, even when every file is unchanged. Ordinary inspection deliberately
does not silently adopt those identities. Development builds containing the
`restore` command can explicitly restore the local continuation binding.

Stop the original project's browser service, workers, R processes and descendants,
including any directly started R analysis, before taking/restoring a complete
backup. A copied lock file cannot establish that the original workers stopped.
Use the original recorded project path and matching R environment. The complete
backup must include `project-format.json` and `state.rds` with the current format.
The [format gate](README.md#project-format-and-reopening) runs before restoration
locks, job records or receipts are written. Restoration does not upgrade formats.
Keep the backup.
After verifying that the original processes are stopped, run from that R environment:

```r
project_dir <- "/absolute/original/project/path"
restore_cli <- system.file("workbench", "run_continue_runtime.py",
  package="scAgentKit", mustWork=TRUE)
status <- system2("python3", c(shQuote(restore_cli), "restore",
  shQuote(normalizePath(project_dir, mustWork=TRUE)),
  "--confirm-original-stopped",
  "--reviewer", shQuote("Your name"),
  "--reason", shQuote("Restored the complete terminal-job backup at its original path.")))
stopifnot(status == 0L)
sc_open(project_dir)
```

The command requires explicit confirmation that the original processes stopped,
an exclusive local continuation lock, no observed unresolved R project lock,
terminal saved jobs, and consistent job/config/request records. It refuses
queued/running job backups and relocation to a different path. Resolve an active
or uncertain original worker before making a new terminal backup; do not edit job
statuses, remove scientific locks or rewrite hashes to force restoration.

An immutable receipt in `.workbench-jobs/restorations/` records old and new
directory bindings, verified local job/request hashes, the operator and reason,
and hashes of the state/projection bytes observed during the check. Old jobs, configs, scientific
state, checkpoints and approvals are not rewritten. Receipt-backed old requests
can return their existing terminal result; a new Continue request uses a fresh
job and the current binding. Copying the project again requires a new explicit
restoration.

This operation restores local job metadata only. A fresh read-only R preflight
validates the project format and state hash; it does not validate a scientific
result. The receipt's observed byte hashes are audit context, not an atomic R
snapshot.
The continuation lock does not exclude directly started R operations.
Normal R inspection and
continuation still verify the authoritative state, evidence and approvals.
Restoration may start the read-only R preflight. It starts no analysis worker,
scientific computation or model request.
