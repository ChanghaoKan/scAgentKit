# Local background continuation interface

The optional server runtime is `RunContinueRuntime(project_dir, library=None,
rscript="Rscript", threads=2)`. Project, library, executable and thread count are
operator configuration. HTTP cannot set them. This feature checks for POSIX
`flock` when enabled and adds no unconditional `fcntl` import. This increment does
not establish support for the existing workbench on Windows.

`describe(run=None)` reads saved JSON and a nonblocking job lock. It never starts
R. A supplied full inspector may be used for the availability binding; otherwise
the existing `status.json` convenience projection supplies it. That projection
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

Job statuses are `queued`, `running`, `succeeded`, `failed`, and `interrupted`.
`succeeded` means the local call reached a verified stop point. The scientific
result is complete only when `next_run_status` is `complete`. Review, configuration
and provider boundaries remain explicit stop points. After a terminal job, fetch
the full inspector before using new scientific bindings or approving another node.

Availability reasons include `ready`, `job_active`, `owner_still_alive`,
`explicit_retry_required`, `complete`, `scientific_review_required`,
`configuration_required`, `unsupported_failed_stage`, and `not_ready`.
Failed/running R retries are restricted to the coordinator's local calculation
stages: qc_evidence, qc_apply, analysis, markers, annotation_evidence,
annotation_apply and finalize. Proposal failures need manual R configuration.
A failure requires an explicit new request with `retry=true`; both the worker
and recorded R process must be confirmed dead. An unknown/live owner blocks retry.

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
removed from both worker and R environments. The fixed bridge has one operation,
`sc_run_continue`, and accepts no R code, callbacks, provider configuration or
browser-selected paths. No new AI request is dispatched by this feature.

The mechanism tests use real detached Python processes and an explicitly fake
Rscript executable. They test process/descriptor behavior rather than claiming
real R or biological validation. Actual R/browser acceptance is a separate check.
This local mechanism does not add authentication for multiple HPC users, perform
scheduler submission, or repair non-POSIX filesystems.
