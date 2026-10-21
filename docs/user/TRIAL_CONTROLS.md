# Cancellation, recovery and disk limits

These controls apply to one saved project. Resuming uses its recorded
configuration; it does not revise scientific choices or provider settings.
Use the [review workflow](WORKFLOW.md) to revise a scientific proposal.

## Cancel and continue

In the workbench, **Cancel after current call** requests a safe stop for the active
model task. The current API call may finish and be billed. Cancellation does not
kill R or another project. From R, the same project control is:

```r
sc_run_control(project_dir, cancel = TRUE, reason = "Pause for inspection")
```

Before continuing, inspect the saved status and provider ledger. Clear the
cancellation request, then explicitly retry the approved computation:

```r
sc_run_control(project_dir, cancel = FALSE, reason = "Continue the same analysis")
sc_run_resume(project_dir, retry = TRUE)
```

For a model suggestion, reopen the project and request its saved preview
again. Cached baseline responses, completed ReAct clusters and completed tool
turns are reused. If a missing API key caused the stop, set the provider's
environment variable before requesting the draft again.

An unfinished computation resumes at its last completed function/stage boundary;
it does not restore an arbitrary instruction inside a running algorithm.
Completed projects reopen for review without rerunning analysis.

## Resolve interrupted requests

If a process stopped during transmission, the provider may have received the
request without returning a response. Inspect the provider record and reconcile
it with `sc_run_provider_reconcile()` before retrying. Supply the request hash,
confirmed cost, reviewer and verification reason. Set `delivery="not_sent"`
only with confirmation that the request was not transmitted, or
`delivery="received"` with confirmation of receipt. A cost receipt alone does
not establish delivery. Reloading or resuming never automatically resends an
uncertain request.

Recover a stale process lock with `sc_run_unlock()` only after verifying that
its owner has stopped. Do not delete a lock held by a running worker.

## Set a project disk allowance

Disk allowance is optional and unlimited by default. After creating a project:

```r
sc_run_control(project_dir, disk_limit_bytes = 20 * 1024^3,
               reason = "Allow up to 20 GiB of project files")
sc_run_control(project_dir, disk_limit_bytes = NULL,
               reason = "Remove the optional allowance")
```

This counts logical project file sizes, skips links, and checks stage/checkpoint
boundaries. It is not an operating-system hard quota: a running computation,
temporary files and essential audit records can temporarily exceed it. On a
limit stop, raise/remove the allowance and explicitly continue; saved results
are not deleted. The workbench's storage button measures current usage.

For request sizes, worker timeouts, storage measurement and project archives,
see [resource controls](RESOURCE_CONTROLS.md). Provider usage and costs are
recorded after calls; neither cancellation nor a disk allowance is a spending
cap.
