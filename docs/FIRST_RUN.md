# First run: one project on the data machine

Use `sc_run()` to start a durable analysis, inspect its saved proposal, approve or
correct it, then explicitly continue. Use R resume below, or the optional
browser's Continue for supported local computation. The helper packages the R
interaction into `first_run_start()`, `first_run_inspect()`,
`first_run_decide()` and `first_run_resume()`. It uses the same R coordinator and
approval authority as the workbench; no manual RDS/ZIP transfer is required.

Install this checkout's package and dependencies in the R library you will use
on the analysis machine. These instructions concern the resumable coordinator;
the separate lower-level toolkit examples in the README have different policies.
Choose a fresh project directory on durable storage and use the same package and
library version when resuming it.

```r
library(scAgentKit)
helper <- system.file("examples", "first-run.R", package = "scAgentKit")
stopifnot(nzchar(helper))
source(helper)
```

## Try the offline synthetic workflow first

The bundled driver creates a small sparse synthetic Seurat object, supplies its
real sample/capture QC aggregate to a **local mock**, and pauses for a reviewed
typed proposal. Its toy quantile bounds demonstrate recovery and correction;
they are not thresholds for an actual study. The mock's annotation is `Unknown`.
There is no credential, external request or API fee.

From this checkout, each line starts a new R process:

```sh
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy demo
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy inspect
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy revise-qc
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy inspect
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy approve
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy resume
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy inspect
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy revise-annotation
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy inspect
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy approve
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy resume
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy output
Rscript --vanilla inst/examples/first-run.R /durable/path/to/fresh-toy resume
```

`awaiting_review` is a successful checkpoint: the process exits and releases its
compute allocation. `inspect` shows and saves the snapshot used by the next
decision. A revision requires another inspection; the previous approval snapshot
is stale. Approving saves a decision; `resume` performs the next supported stage.
The last completed `resume` reuses saved outputs and does not call the mock again.
The driver reports the number of mock calls in each process, including zero.

Scripted toy revisions/approval reasons are accepted only for the driver-created
synthetic project. For your own data, source the helper and supply your own R
decision and reason below. `inspect`, `resume` and `output` can also operate on an
existing run directory; the browser is optional.

## Start your own raw matrix, Seurat or local RDS

`input` is one of these alternatives, on the machine holding the data:

```r
# A named genes-by-cells raw-count matrix or sparse Matrix:
input <- counts
# Or an existing Seurat object with a genuine raw counts layer:
input <- seu
# Or a local RDS containing either supported object; no copy to your laptop:
input <- "/data/my-input.rds"
```

Matrix row/cell IDs must already be unique, nonempty literal strings. Counts must
be finite, nonnegative integers; normalized/scale data cannot stand in for counts.
No ID repair, barcode coercion, split-layer guess or metadata fabrication occurs.
Matrix feature IDs containing `_` or `|` that Seurat would rewrite need an
explicit collision-checked mapping before entry; keep that mapping as provenance.
Seurat v5 layers must be selected explicitly when names are ambiguous, and the
selected counts layer must cover all input cells. A bare matrix has no sample/
capture metadata: omit `columns` or supply a verified Seurat object containing it.
In the tested SeuratObject 5.3.0 environment, creating or subsetting an Assay5 to
one cell can lose the required two-dimensional layer shape. Unreadable layers
are rejected; the coordinator does not repair or coerce them. Use a verified
object whose layers remain two-dimensional. Single-cell export was also checked
with an explicitly constructed valid legacy Assay through the public v5 APIs.
For 10x directories, h5ad or other files, use your own verified loader to create a
supported object first; this helper is not a universal file importer.

Describe actual metadata roles and research features:

```r
context <- list(
  species = "human", tissue = "declare the actual tissue",
  columns = list(sample = "sample_id", capture = "capture_id",
                 condition = "condition"),
  notes = "Describe study design, preparation, expected populations and known limitations."
)
project_dir <- "/durable/path/to/fresh-study"
```

Each named column must exist on the supplied Seurat object; omit absent roles.
Capture is a library/capture role, not an inferred donor. A biological condition
such as Ca/Ctrl is not inferred as a technical batch. If known, a true batch
column can be recorded in `context$columns$batch`; integration is still skipped
in this guide's default `strategy = FALSE` path. The optional reviewed strategy
has a separate guarded [Harmony contract](HARMONY_PC_REVIEW.md); it never chooses
a batch from biological condition alone. For a bare matrix, use the same context
without `columns`.

With no provider or initial rule, the single starting call saves diagnostics and
QC evidence and pauses for configuration. It does not invent an AI threshold:

```r
run <- first_run_start(input, project_dir, context = context,
  provider = NULL, budget = 0, review = list(allow_external = FALSE),
  assay = "RNA", counts_layer = "counts", annotation_column = "reviewed_identity")
view <- first_run_inspect(project_dir)
view$evidence
view$evidence$mitochondrial           # availability/reason, not an assumed zero
```

Select a study-specific typed rule after inspecting those actual summaries, then
submit it with `sc_run_propose(project_dir, rule, reviewer=..., reason=...)`. Rules
use only inclusive `range` bounds on measured `nCount`, `nFeature` and available
`percent_mt`, optionally scoped to actual sample/capture values. See
[QC-review.md](QC-review.md) for the complete schema and missing-metric behavior.
There is no default rule recommended for arbitrary data.
The current mitochondrial calculation recognizes human `^MT-` or mouse `^mt-`
symbols. Other species/conventions or absent matching features leave it
unavailable; omit that filter or prepare a verified compatible input explicitly.

If you already have a reviewed typed rule, pass `qc_proposal=rule` to the starting
call instead. The project still pauses for approval of its computed impact:

```r
# rule is your explicit study-specific scagentkit.qc.v1 object.
# Add qc_proposal=rule to first_run_start(...), or after diagnostics:
sc_run_propose(project_dir, rule, reviewer = "your analyst ID",
               reason = "Explain the proposed study-specific bounds and risks.")
view <- first_run_inspect(project_dir)
view$qc_preview$details$retention
view$qc_preview$details$filter_impacts
view$qc_preview$details$distributions
view$qc_preview$details$unavailable

# Correct the full typed rule if needed, then inspect its fresh impact.
replacement <- view$qc_preview$details$canonical_parameters$proposal
# Edit replacement with the bounds/selectors you have justified for this study.
first_run_decide(project_dir, "revise", snapshot = view, proposal = replacement,
  reviewer = "your analyst ID", reason = "Explain this exact QC correction.")
view <- first_run_inspect(project_dir)
first_run_decide(project_dir, "approve", snapshot = view,
  reviewer = "your analyst ID", reason = "Explain why the displayed exact retention and risks are acceptable.")
first_run_resume(project_dir)
```

For QC and annotation, `first_run_decide()` uses the displayed project's input,
proposal, review and revision fingerprints, never a silently refreshed unseen
plan. A stale snapshot, foreign project, changed input or unsupported rule is
rejected by the unified R operation under the project lock. It supports `reject`
with a reason as well; rejection does not
automatically request another model or apply a filter. Its saved convenience
snapshot is local, separate from the authoritative project state.

Without a provider, the next pause is annotation configuration. Supply manual
`Unknown` labels from the saved actual cluster scope, then review that proposal:

```r
view <- first_run_inspect(project_dir)
sc_run_propose(project_dir, first_run_unknown(view), reviewer = "your analyst ID",
               reason = "Initial manual Unknown proposal pending annotation review.")
view <- first_run_inspect(project_dir)
view$annotation_review$details$source
view$annotation_review$details$annotations

replacement <- first_run_unknown(view,
  rationale = "Reviewed available evidence; subtype/identity remains unresolved.")
first_run_decide(project_dir, "revise", snapshot = view, proposal = replacement,
  reviewer = "your analyst ID", reason = "Explain the manual correction and uncertainty.")
view <- first_run_inspect(project_dir)
first_run_decide(project_dir, "approve", snapshot = view,
  reviewer = "your analyst ID", reason = "Approve the reviewed manual labels and their limitations.")
run <- first_run_resume(project_dir)
stopifnot(run$status == "complete")
final <- readRDS(run$output$seurat)
```

You may retain a proposal or replace selected rows with justified coarser labels
and actual marker citations instead of making every label `Unknown`. Every
cluster must appear once. A known label needs a citation from that cluster's
supplied marker evidence; matching a gene is not proof that it supports the
scientific interpretation. Low/medium/high confidence is qualitative, and missing
top markers do not establish absent expression. Unprovided reference matches and
independent counterevidence remain explicitly unavailable. See
[ANNOTATION_REVIEW.md](ANNOTATION_REVIEW.md) for evidence meaning and executed
annotation undo; old metadata columns are preserved by writing fresh columns.

## Connect a built-in provider through the R environment

Configure `DEEPSEEK_API_KEY` or `XAI_API_KEY` through your user secret mechanism on
the analysis machine. Do not put key values in this helper, context, RDS, browser
or logs. `first_run_provider()` creates safe configuration only; the existing
DeepSeek/Grok factory reads the key at dispatch. A selected provider with no key
raises a clear configuration error and makes zero calls. Explicitly choose
`provider=NULL` for diagnostics and manual work.

For a **fresh** provider project, use the actual model ID and verified current
per-million USD rates. This example reads nonsecret configuration from environment
variables as well, so it does not embed guessed prices or change a saved run:

```r
provider <- first_run_provider("deepseek", model = Sys.getenv("SC_MODEL_ID"),
  pricing = list(
    input_per_million = as.numeric(Sys.getenv("SC_INPUT_USD_PER_MILLION")),
    output_per_million = as.numeric(Sys.getenv("SC_OUTPUT_USD_PER_MILLION")),
    cached_input_per_million = as.numeric(Sys.getenv("SC_CACHED_INPUT_USD_PER_MILLION"))),
  reservation_usd = 0.05)
# Use "grok" for the existing Grok factory; configure XAI_API_KEY and that
# verified model's own rates/settings. A zero cached-input rate must be justified.
run <- first_run_start(input, "/durable/path/to/fresh-provider-study",
  context = context, provider = provider, budget = 0.20,
  review = list(allow_external = TRUE), annotation_column = "reviewed_identity")
view <- first_run_inspect("/durable/path/to/fresh-provider-study")
stopifnot(view$pending$kind == "external_transfer")
view$pending$proposal                 # exact transmitted payload/model/settings
first_run_decide("/durable/path/to/fresh-provider-study", "approve", snapshot = view,
  reviewer = "your analyst ID", reason = "Reviewed and permit this exact aggregate transfer.")
first_run_resume("/durable/path/to/fresh-provider-study")
# Inspect the separate QC decision. The later annotation request has its own
# aggregate-transfer preview, followed by a separate annotation approval.
```

`allow_external=TRUE` enables proposing a transfer; it does not approve it.
The outgoing-transfer decision uses the existing `sc_run_approve()` /
`sc_run_reject()` hash-and-revision interface after the helper checks the
snapshot's project/input identity. That convenience identity check precedes
the locked decision; it is separate from the mandatory unified identity fields
used for QC and annotation. External transfer is not an approval node in the
local review/Continue browser.

By default only explicitly approved aggregate QC/marker evidence and context leave
the machine; matrices and cell IDs are excluded from those provider requests.
Free text and group labels can still reveal private information. Raw data staying
on the server does not mean no aggregate information leaves it. The optional
trusted local review browser receives local QC scope and cell IDs, separately
from this external-transfer consent.

Budget is charged or conservatively reserved USD per project. Too little budget
stops dispatch; unknown usage keeps its hold. Requests are cached and are not
retried automatically. Restarts do not authorize new calls; new stages still need
their own transfer/decision approval. Changing provider/model/settings on a saved
run is unsupported: restore its exact configuration or start a fresh project.
An explicit custom `chat_fn` must be reattached in a new R process when needed;
it is not saved with the project. The offline driver uses this mechanism to
reattach its mock. No paid run is required to learn the workflow.

## Existing processed data, parameters and boundaries

An already processed Seurat object may enter with `start_stage="processed"`, a
documented `processed_reason`, exact normalized layer and cluster column. This
reuses base analysis and goes to saved marker evidence and annotation. See the
[processed example](../inst/examples/annotation-review.R). A matrix/RDS that
only contains raw counts cannot claim that entry point.

This table describes this helper's default `strategy = FALSE` path. It is not
the complete current package support matrix. Optional concentrated strategy,
MAD/cycle/doublet diagnostics, guarded Harmony and scoped children have separate
contracts in the [release checklist](RELEASE_CANDIDATE_CHECKLIST.md).

| Item | This first-run path |
| --- | --- |
| PCs/HVG/normalization | Standard existing `sc_project_prepare`; explicit `analysis=list(nfeatures=..., npcs=..., dims=..., ...)` settings. Effective settings are recorded. No automatic scientific PC selection or PC approval node. |
| Resolution | Explicit `analysis$resolution`, seed and related settings are recorded. No automatic resolution scan/recommendation/approval. |
| Batch | Context can record a real technical batch; integration is skipped. Condition is not a batch and capture is not a donor. |
| Doublets/ambient RNA | Not run by this first-run path. Optional explicit `doublet_diagnostics` belongs to `strategy = TRUE`; ambient-RNA correction remains unsupported. An external verified preprocessing workflow can be documented at processed entry. |
| QC | Reviewed typed count/feature/available-mitochondrial ranges with exact impacts. No arbitrary generated R, automatic optimization or biological truth claim. |
| Annotation | Saved suggestions, supplied markers and actual reference provenance; manual correction/Unknown, exact approval, fresh-column output and audited annotation undo. Confidence is not calibrated. |
| Browser | Optional loopback QC/annotation review and explicit local Continue. Separately enabled unified model review can preview/approve/request an immutable configured provider; Continue itself never dispatches it. No credential entry, arbitrary R or scheduler submission. Custom in-memory callbacks remain headless. |
| HPC | Checkpointed headless Rscript and scheduler templates; intended scheduler/shared-filesystem behavior needs actual site-specific verification. |

Start an optional browser on the data machine using the same project/library:

```sh
python3 workbench/server.py --run-project /absolute/path/to/project --local-continue --port 8772
# Add --r-library /path/to/private/R-library if needed.
```

Open `http://127.0.0.1:8772/review` locally, or use your already authorized SSH
tunnel to that loopback port. Omit `--local-continue` for review-only service and
continue from R instead. The browser saves the same bound decisions and
shows pending/completed status. After approving QC, choose **Continue** to apply
the approved filters and run the saved local analysis. After approving the whole
annotation plan, choose Continue to finalize outputs. Keeping the saved plan does
not require a confirmation for each cluster. Continue is a persisted asynchronous
worker; reconnect and inspect its job and run status if the page or HTTP service
disconnects. No public binding, authentication change, scheduler submission or
browser launch is required. Run the service on an appropriate analysis machine
or allocated compute node; it launches local work there.

Continue stops at `awaiting_configuration` when a new proposal or runtime provider
is needed. It does not call even an offline mock, recover a saved callback, use
the provider cache, or approve/transmit a new aggregate request. Supply a typed
manual proposal in R, as above, or explicitly inspect, authorize and resume the
model request through R, then refresh the browser. Thus a raw project with both
proposals available needs two whole-plan approvals and two Continue actions; a
manual/mock project without its annotation proposal also needs that R
configuration step. A processed entry omits the QC decision.

`first_run_resume()` retains its full R behavior, including an authorized model
request when configured; it is broader than browser Continue. The browser's
local-only boundary does not replace the provider transfer and budget gates.
[Workbench details](../workbench/RUN_REVIEW_QUICKSTART.md) explain the worker and
trusted-local-session boundaries. The new Continue main workflow was exercised
on the user's Mac with real Chrome and the fixed R worker using synthetic and
public PBMC inputs. It included explicit R configuration of manual annotation
proposals, whole-plan approval, local output, disconnect/restart recovery and
duplicate-job reuse; an explicit local-failure retry was also exercised. Final
labels remained `Unknown`, including a synthetic result with no supplied markers.
No external API request was made and API cost was US$0. These checks establish
the demonstrated software workflow, not biological identities. Earlier Linux
headless results do not validate this new Continue path; new Linux Continue, HPC
and Windows worker execution have not been validated.

The final run reports the new Seurat path plus saved tables, available plots,
parameters, report and history in the project. Re-source the helper and call
`first_run_resume(project_dir)` from another R process to recover. Completed
checkpoints/caches are reused; an interrupted uncommitted computation may need an
explicit retry. Do not delete a lock to bypass another writer; use the documented
owner-verified recovery mechanism. This first-use path does not establish
arbitrary biological correctness or manuscript-level validation.
