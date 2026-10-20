# Pause, continue and project disk allowance

All new entry points record actual provider usage and cost after calls. A missing
key leaves the chosen provider configured: set its environment variable and
explicitly request the draft again in the same project. Model or scientific
configuration changes are not part of resume.

In the workbench, **Cancel after current call** requests a safe stop for the active
model task. The current API call may finish and be billed. Cancellation does not
kill R or another project. From R, the same project control is:

```r
sc_run_control(project_dir, cancel = TRUE, reason = "Pause for inspection")
```

Before continuing, inspect the saved status and provider ledger. Clear the stop:

```r
sc_run_control(project_dir, cancel = FALSE, reason = "Continue the same analysis")
sc_run_resume(project_dir, retry = TRUE)  # approved local/coordinator stages
```

For a model suggestion task, reopen the same project and explicitly request its
saved preview again. The exact baseline response is read from cache, completed
ReAct clusters are skipped, and saved completed tool turns are reused. If the
process stopped during transmission, delivery may be unknown: reconcile that
record in R before continuing. A cost receipt alone does not resolve delivery.
Use `sc_run_provider_reconcile(..., delivery="not_sent")` only when the provider
confirms no transmission, or `delivery="received"` for confirmed receipt, with
the verification reason recorded. Neither reload nor resume automatically resends
an uncertain request. A stale process lock requires explicit `sc_run_unlock`
after verifying that its owner has stopped; never delete locks while a worker lives.

An unfinished computation resumes at its last completed function/stage boundary;
it does not restore an arbitrary instruction inside a running algorithm.
Completed projects reopen for review without rerunning analysis.

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

Repeated identical tool evidence without progress causes a baseline fallback;
a validated final draft ends refinement immediately. Existing configured step
and timeout bounds still apply. The user must approve scientific decisions.
