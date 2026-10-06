# Review QC and annotations in one local session

Use `/workbench` for the complete navigable saved-project view on this same
service: overview, QC, strategy, analysis, annotation, children, outputs and
history. Its saved UMAP/markers and historical records are read-only. The
[saved-project guide](../docs/UNIFIED_PROJECT_WORKBENCH.md) covers startup and
limits; `/review` below remains the explicit current-decision interface.

The optional workbench connects to an existing `sc_run()` project directory. R remains the authority for proposals, decisions, fingerprints, locks, execution and undo. The browser submits typed decisions and offers **Continue** for the next supported local computation. It cannot submit R code, supply credentials or read the expression matrix. Starting a project remains an explicit R operation. This guide describes the local Continue path; separately enabled [unified model review](../docs/UNIFIED_MODEL_REVIEW.md) adds exact aggregate preview, request consent and an explicit configured-provider request action. Continue itself never dispatches a model. For one parent and its registered children, see [single-service review](../docs/SINGLE_SERVICE_REVIEW.md).

The main Continue workflow was exercised on the user's Mac with real Chrome and the fixed R worker using synthetic and public PBMC inputs. The PBMC run retained 2,527 of 2,700 cells and finalized all labels as manual `Unknown`; the synthetic run had one cluster and no supplied markers and was also finalized as `Unknown`. Validation covered actual approvals and local computation, an explicit R annotation-configuration step, browser/HTTP disconnect and restart recovery, duplicate-job reuse, and a separate explicit local-failure retry. These are software-workflow checks, not validated cell identities. No external API request was made and API cost was US$0. Earlier Linux headless results cover a different path; this new Continue has not been validated on Linux, HPC or Windows.

## Start a review session

Install the current scAgentKit package in the R library used by the run. Use a project created with that same coordinator implementation; this addition does not migrate older project approvals across an implementation change. Start the workbench on the machine that holds the project:

```sh
python3 workbench/server.py \
  --run-project /absolute/path/to/project \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/private-r-library \
  --local-continue \
  --port 8772
```

Open `http://127.0.0.1:8772/` (or `/review`) for the unified review page. `--local-continue` explicitly enables the local worker; omit it to retain the review-only service and resume from R. Its fixed QC pane reuses the existing QC preview interface with fully bound unified requests. On a unified `--run-project` server, `/qc` and `/api/qc/inspect` retain the legacy saved view, while `/api/qc/decision` is rejected: submit decisions through `/review`. The separate legacy QC-only server handler remains compatible. The unified page uses `/api/run-review/` and `sc_run_review()`.

For a remote machine, run this command on your own computer and open the same URL:

```sh
ssh -N -L 8772:127.0.0.1:8772 your-existing-ssh-host
```

Keep the local and remote port numbers identical. Requests with a different Host port are rejected by design. The server binds only to `127.0.0.1`; it does not configure SSH, authentication, firewalls or scheduler jobs.

Use a trusted local or SSH-tunnel session. Loopback binding, Host/Origin validation and the session token protect the review transport; they are not per-user authentication. Other processes that can reach the same node's loopback listener can read the review and obtain its token. Shared multiuser HPC authentication and isolation are outside this version's scope.

The background worker requires POSIX `flock` support. Without it, use the review-only service and explicit R continuation; this new browser feature does not add Windows worker support.

## QC, then Continue local computation

Review the QC preview's exact cell scope, retained/removed IDs, independent and overlapping filter reasons, unavailable measurements, distributions and any explicit sensitivity comparison. Enter the reviewer and reason. Approve the saved preview, reject it, or revise the typed rules and rebuild the preview before approving.

An approval saves the displayed decision. **Continue** is a separate, explicit action: it starts a persisted local worker using the freshly inspected project ID, input hash and revision. R verifies that binding and the saved approved proposal under the project lock. The browser displays the job status and refreshes the run at its next checkpoint; it does not keep an HTTP request open for the analysis.

Continue can apply approved QC, run the recorded standard analysis and markers, build annotation evidence, and apply an approved annotation and finalize outputs. It stops when another proposal or runtime provider is needed. In particular, it does not reattach or call an offline mock callback: callbacks are not saved with the project. A worker ending at `awaiting_configuration` is a successful pause, not a completed analysis.

For a raw project with proposals available at both review checkpoints, the ordinary browser sequence is **approve QC → Continue → approve the whole annotation plan → Continue**. No per-cluster confirmation is required when keeping the saved annotation plan. A processed entry skips the QC review and needs the annotation approval and Continue only. Revisions add a save-and-review step; they are optional corrections, not required clicks.

If Continue reaches annotation configuration, use the saved actual cluster evidence to supply a manual proposal in R, for example:

```r
library(scAgentKit)
source(system.file("examples", "first-run.R", package = "scAgentKit"))
project_dir <- "/absolute/path/to/project"
view <- first_run_inspect(project_dir)
sc_run_propose(project_dir, first_run_unknown(view,
  rationale = "Reviewed supplied evidence; identity remains unresolved."),
  reviewer = "your analyst ID", reason = "Manual Unknown proposal for the actual clusters.")
```

Refresh the browser, review that saved proposal, approve it once and choose Continue. This manual configuration is required when no annotation proposal exists; the browser does not manufacture a suggestion just to finish the workflow.

Headless R and scheduled Rscript remain available. The existing full resume can request a new model proposal after the run's separate transfer authorization:

```r
scAgentKit::sc_run_resume(project_dir)
```

If the run uses an explicit `chat_fn`, supply that function through the supported R resume configuration when a new proposal is needed. The workbench never receives or executes it. Review and approve each outgoing aggregate transfer in R; Continue cannot grant that consent or dispatch the request. Refresh after the R process reaches the next checkpoint.

The same local-only boundary is available without the browser. Inspect **after** saving the approval so the revision reflects that decision:

```r
current <- scAgentKit::sc_run_inspect(project_dir)
run <- scAgentKit::sc_run_continue(project_dir,
  project_id = current$project_id, input_hash = current$input_hash,
  expected_revision = current$revision)
```

This operation has no provider or callback argument. A stale revision fails instead of silently continuing a newer plan. Its default does not retry a failed or interrupted computation; explicit `retry=TRUE` applies only to supported local stages after investigating the failure and resolving any abandoned lock. Provider/proposal failures still require the explicit R configuration/resume route.

## Review cluster annotations

The annotation pane shows each exact cluster ID and cell scope, the saved label, qualitative confidence, rationale and cited markers. The marker tables distinguish cited markers from all supplied marker statistics. `pct1` and `pct2` are fractions; adjusted p values and log fold changes are the saved marker-table values. No new expression or negative-evidence test is performed by the review page. A marker omitted from the supplied table does not establish absent expression.

The source panel identifies the current saved proposal separately from a historical provider response and its `matches_current` flag. `mock`, `model`, `manual` and `unknown` describe saved provenance. A configured provider alone does not prove that it authored the current proposal. Local reference candidates are supporting suggestions; their scores are heuristics, not probabilities or biological exclusions. Low/medium/high confidence is qualitative.

Keep a saved suggestion, type a coarser label, or choose `Unknown`. A known label needs at least one selected supporting citation from that exact cluster's supplied marker evidence; the UI does not accept arbitrary genes. Unknown clears citations, and Keep restores the original saved proposal. Each changed cluster needs a new rationale. Enter an overall reviewer and reason, then save corrections to create a new bound proposal. Approve only the saved plan; unsaved edits disable approval. Rejection records its reason without executing annotation. The page shows the current proposal and decision history, so the original model/mock suggestion remains available for comparison after manual correction.

After approving the whole saved plan, choose Continue to write the new Seurat output and reports. Output paths are displayed; the browser does not serve the RDS or matrix. Headless `sc_run_resume()` remains an alternative. A fresh R process can resume a completed project without repeating completed analysis.

## Worker status and interrupted sessions

Continue is asynchronous. Its persisted job identity and status are separate from the authoritative R run state. Repeated submission of the same bound action reuses that job rather than starting a second computation. A stale revision, changed input or different project is rejected. A finished job can still have a run awaiting review or configuration; only the run's `complete` status indicates finalized output.

Local task receipts, configuration and owner/status records are stored under the project's `.workbench-jobs/`. They supplement the R checkpoints and do not replace `state.rds` or grant a scientific approval. Polling reads saved status; it never starts another R calculation.

Closing or refreshing the browser, losing the tunnel, or restarting the HTTP service does not by itself cancel the detached local worker or remove saved checkpoints. Reconnect the service to the same project and inspect its saved job/run status before acting again. An unknown response is not permission to start another worker. Do not remove a lock to bypass an active computation.

Terminating R or losing the compute node is a different boundary: a completed checkpoint is reusable, but an interrupted uncommitted stage may need an explicit local-compute retry and owner-verified lock recovery. Continue does not automatically retry a failed stage or replay a provider request. The filesystem and shared-node limitations in [SERVER_FIRST.md](../docs/SERVER_FIRST.md) still apply.

The HTTP service launches local computation on its own machine; it is not a scheduler client. Start it on an appropriate machine or allocated compute node. It does not submit a job, allocate resources or establish that it is safe to compute on a login node.

## Undo an executed annotation decision

The following annotation undo applies to a standalone review service. In the
[single-service parent/child mode](../docs/SINGLE_SERVICE_REVIEW.md), the completed
source parent is read-only, including parent annotation undo. A child's versioned
derived application has its separate explicit apply/undo interface.

For a completed annotation decision, the page offers the existing supported undo operation with the exact decision ID, reviewer and reason. R verifies the full project/input/proposal/review/revision binding under its project lock. Undo archives completed outputs and preserves checkpoints and history; it reopens annotation configuration. Make and save a new reviewed proposal before approving again. QC execution is not undone by this annotation action.

## Saved state and privacy

Both QC and annotation submissions carry the project ID, input hash, proposal hash, review hash and expected revision. R rejects stale or changed bindings. The UI also disables all decision controls after an unverified HTTP/JSON/schema/identity response and requires a successful verified refresh before another submission. Duplicate decisions do not execute analysis twice. The project can be reviewed without keeping the originating R process alive.

The trusted local browser receives review context, exact cell/cluster IDs, sample/capture scope, per-cell QC evidence and marker summaries needed for review. Raw counts, expression matrices, provider keys and provider headers are not served. This local review access is separate from provider transmission: any external model call uses the run's separately authorized aggregate evidence and configured R provider. “Raw data stay on the server” does not mean that no aggregate information is sent to a provider.

Continue requests carry only the bound local action; the configured project and R executable/library are selected by the operator at server startup. Browser fields are data, not executable R. Continue is neither model consent nor scientific approval and cannot alter the run's provider, budget or analysis settings.

The local Continue path supports the current QC preview, whole-plan annotation review and constrained local computation. It does not infer donor/batch identity, prove labels biologically correct, submit scheduler work or dispatch a model through Continue. An optional, separately enabled model-suggestion worker retains its own payload consent and request action. Headless R inspect/approve/reject/revise/resume remains available when no browser is present.
