# Server-first analysis with `sc_run()`

`sc_run()` coordinates an analysis in one persistent project directory on the
machine that holds the data. It accepts a raw counts matrix, a Seurat object, or a
local RDS path. The R process saves its checkpoint and exits when a decision needs
review. A later `sc_run_resume()` continues from the saved checkpoint.

The normal workflow is **run → inspect → approve or revise → continue**. QC review
works from R alone or the optional loopback workbench connected to the same run
directory. The same live project window reviews pending annotation proposals;
the completed annotation-bundle refinement window remains a separate mode. You do
not need to move a large RDS, export an evidence ZIP, import a journal, or leave an
R process running while reviewing a suggestion.

This is a constrained coordinator, not an autonomous biological analyst. A model
can propose supported structured operations and annotations. It cannot generate
R code for execution. Decisions and their evidence stay reviewable, and an
accepted label remains an analyst decision rather than proof of cell identity.

## Minimal R example: new synthetic counts

Install this checkout's version of the package into the R library used on the
analysis machine. The included helper creates a small sparse, non-PBMC synthetic
mixture and a mock provider. It makes no HTTP request and costs zero.

```r
library(scAgentKit)
source(system.file("examples", "server_first.R", package = "scAgentKit"))
toy <- make_server_demo_input()
context <- server_demo_context()
# species, tissue, columns=list(sample=..., capture=..., batch=...,
#   condition=...), and free-text notes describe this toy study.
project_dir <- "/durable/path/to/synthetic-project"  # choose a fresh directory
run <- sc_run(toy, project_dir, context = context,
  provider = server_demo_provider(), chat_fn = server_demo_chat, budget = 0,
  analysis = list(nfeatures = 200L, npcs = 12L, dims = 1:10,
    resolution = 0.3, seed = 73031L, umap_neighbors = 20L))

qc <- sc_run_inspect(project_dir)
qc$evidence                         # actual sample/capture QC summaries
qc$pending$proposal$rules            # filters, reasons and risks
qc$pending$proposal$retention        # predicted cells retained by group
sc_run_approve(project_dir, qc$pending$hash,
  reviewer = "your analyst ID", reason = "Reviewed the toy QC rule and retention.")

# This may run in another R process. Re-source the helper to reattach its mock.
run <- sc_run_resume(project_dir,
  provider = server_demo_provider(), chat_fn = server_demo_chat)
annotation <- sc_run_inspect(project_dir)
annotation$pending$proposal          # one proposal per actual cluster
sc_run_approve(project_dir, annotation$pending$hash,
  reviewer = "your analyst ID", reason = "Reviewed toy suggestions; retain Unknown.")
run <- sc_run_resume(project_dir,
  provider = server_demo_provider(), chat_fn = server_demo_chat)
stopifnot(run$status == "complete")
final <- readRDS(run$output$seurat)
table(final$sc_annotation)
```

The mock's QC bounds come from each supplied group's observed 5th percentile;
they demonstrate the mechanism and are not suggested thresholds for a real
study. Its annotations deliberately remain `Unknown`. A bare named sparse counts
matrix can also be passed to `sc_run()`; without metadata columns the diagnostics
will state that separate sample/capture QC is unavailable. A Seurat input or local
RDS retains those metadata columns for grouping.

The same example is an Rscript driver. Every command below starts a fresh R
process. `awaiting_review` exits successfully and releases its compute allocation:

```sh
Rscript --vanilla inst/examples/server_first.R /durable/path/to/toy-project run
Rscript --vanilla inst/examples/server_first.R /durable/path/to/toy-project inspect
Rscript --vanilla inst/examples/server_first.R /durable/path/to/toy-project approve
Rscript --vanilla inst/examples/server_first.R /durable/path/to/toy-project resume
Rscript --vanilla inst/examples/server_first.R /durable/path/to/toy-project inspect
Rscript --vanilla inst/examples/server_first.R /durable/path/to/toy-project approve
Rscript --vanilla inst/examples/server_first.R /durable/path/to/toy-project resume
```

The driver's `approve` mode is for the synthetic example only. Real projects
should use the R inspection and explicit reason shown above.

## Minimal R example: an existing processed object

```r
processed <- readRDS("/server/data/my-processed-seurat.rds")
context <- list(species = "human", tissue = "declare your actual tissue",
  columns = list(sample = "sample_id", capture = "capture_id",
    batch = "prep_batch", condition = "condition"),
  notes = "Explain study design, expected populations and preparation limitations.")
run <- sc_run(processed, "/durable/path/to/processed-project",
  context = context, start_stage = "processed",
  processed_reason = "QC and processing completed in the documented prior pipeline; reuse counts, normalized RNA, clusters and reductions.",
  assay = "RNA", counts_layer = "counts", normalized_layer = "data",
  cluster_column = "seurat_clusters", annotation_column = "review_2026",
  provider = server_demo_provider(), chat_fn = server_demo_chat, budget = 0)
# Goes directly to markers and annotation review; preserves basic analysis.
annotation <- sc_run_inspect("/durable/path/to/processed-project")
```

Load the preceding example helpers first, and replace the column names and
provenance with the verified study's values. The mock can be used on local data
without transmitting it. For a self-contained processed toy, run
[`inst/examples/server_processed.R`](../inst/examples/server_processed.R).
Approve and resume its annotation node as in the preceding example.

## Configure a remote provider on the analysis machine

The built-in configuration invokes the existing `agentomicsCore::chat_deepseek()`
or `chat_grok()` factory only when an approved request is ready to dispatch. Keys
come from the running machine's environment; no key value is supplied to `sc_run`.
Configure `DEEPSEEK_API_KEY` or `XAI_API_KEY` through your own secret mechanism.
The following starts a **new** project and initially pauses at an outgoing preview:

```r
provider <- list(name = "deepseek", model = "deepseek-flash",
  api_key_env = "DEEPSEEK_API_KEY", reservation_usd = 0.05,
  pricing = list(input_per_million = 0.30, output_per_million = 1.20,
    cached_input_per_million = 0.006),
  generation = list(temperature = 0, max_tokens = 1200L,
    thinking = list(type = "disabled")))
# For Grok or another provider, also fill pricing from its verified current
# model-specific rates before starting; do not reuse these DeepSeek rates.
run <- sc_run(toy, "/durable/path/to/provider-toy", context = server_demo_context(),
  provider = provider, budget = 0.20, review = list(allow_external = TRUE))
preview <- sc_run_inspect("/durable/path/to/provider-toy")
stopifnot(preview$pending$kind == "external_transfer")
preview$pending$proposal$payload     # exact transmitted system and user text
preview$pending$proposal$provider    # model and generation configuration
sc_run_approve("/durable/path/to/provider-toy", preview$pending$hash,
  reviewer = "your analyst ID", reason = "I reviewed and permit this aggregate payload.")
run <- sc_run_resume("/durable/path/to/provider-toy")
# Now inspect and approve the separate QC proposal. A later annotation request
# has its own aggregate transfer preview before the annotation approval node.
```

This complete-run configuration includes the three USD-per-million pricing
fields used by the implementation. The DeepSeek Flash values above use the
conservative peak rates checked on 2026-10-03: input cache miss 0.30, output 1.20,
and input cache hit 0.006. Off-peak rates are lower; these settings deliberately
keep a conservative usage estimate rather than claiming an exact invoice.
Recheck the [official model pricing](https://api-docs.deepseek.com/quick_start/pricing/)
before starting a new project and replace the values if the tariff changed.
Do not change pricing in a saved run: it is part of the provider configuration
bound to its approved requests. Start a fresh project for changed settings.

With returned input/output usage and these rates, the coordinator settles each
request reservation and can continue from QC to the separate annotation request.
A missing usage response still retains its hold and pauses new requests. Omitting
`pricing` is appropriate only for a deliberate single-request smoke, or a custom
`chat_fn` that returns a known `cost_usd`; a factory response with usage but no
pricing cannot calculate its cost and will hold the reservation after that call.

`allow_external = TRUE` enables proposing a transfer; the exact payload still
needs approval. To use an existing factory or custom runtime function, pass it as
`chat_fn` with safe provider metadata, including `external = TRUE` for a remote
service. Closures and keys are never saved; reattach `chat_fn` in a new R process
if a new request needs it. Saved approvals bind the model and generation settings.

`budget` is the maximum charged or reserved USD for this project. A reservation is
a conservative hold, not a guaranteed provider bill. Supply verified per-million
rates through `provider$pricing`, or return usage plus `cost_usd` from a custom
function, for known accounting. Without known accounting an external response
keeps its hold and further requests pause. Review current provider pricing before
configuring rates. Inspect `provider/ledger.json` for usage, charges and holds.

## Input and research context

Use actual counts for `start_stage = "qc"`. `counts_layer` selects an exact Seurat
v5 layer by name. The coordinator rejects missing or ambiguous layers, incomplete
cell coverage, invalid counts, and inconsistent IDs. Normalized or scaled values
are not a substitute for raw counts. Split layers must be resolved explicitly
before running; the coordinator does not guess which split layer represents all
cells. Computation uses Seurat v5 public layer APIs and preserves sparse counts.
A matrix's cell and feature names must be complete, nonempty and unique. Matrix
feature IDs containing `_` or `|` are rejected because Seurat would rename them.
If needed, make a deliberate collision-checked rename before calling `sc_run`,
retain its mapping, and use those literal IDs consistently. No rename is guessed.

Context should identify the species and tissue, name the real metadata columns,
and explain the study in plain language. The sample column identifies the sample
represented in the object; the capture column identifies a capture or library.
Neither implies a donor. A biological condition such as Ca/Ctrl is not a technical
batch variable. This guide's default `strategy = FALSE` path records batch
information and skips integration. The optional concentrated strategy supports
separately reviewed, guarded Harmony with explicitly sourced technical roles;
see [Harmony/PC review](HARMONY_PC_REVIEW.md). It does not infer that correction
is scientifically appropriate.

For an already processed object, choose `start_stage = "processed"` explicitly
and give `processed_reason` describing the prior QC and processing provenance.
The object must have the selected normalized layer, cluster membership, and the
required processed evidence. The coordinator records the reason for skipping raw
QC and the standard calculation stages. It does not silently recompute them.

## What is persisted

The project owns the input copy, source identity, evidence, proposal, stage
checkpoints, provider cache, decision history, parameters, review bundle, and
final artifacts. The source R object is not modified. QC applies approved filters
to the saved copy; annotations are written as new metadata columns with confidence
and rationale. The journal records evidence identity, approval identity and reviewer.

| Path in the project | Purpose |
| --- | --- |
| `state.rds` | Authoritative checksummed state and history commit |
| `status.json` | Readable status projection |
| `decision_history.json` | Append-only decision-event projection |
| `checkpoints/` | Versioned input, evidence, proposals and completed objects |
| `provider/ledger.json` | Safe provider settings, responses, usage, cache and budget holds |
| `output/seurat.rds` | New final Seurat object |
| `output/markers.csv`, `metadata.csv`, `parameters.json` | Tables and recorded settings |
| `output/report.md`, `umap.png`, `qc.png` | Run report and available figures |
| `resume.R` | Local recovery entry script |
| `bundle/` | Completed annotation evidence for optional browser refinement |

All run and approval writes occur on the analysis machine. A project lock prevents
concurrent mutation. Approvals bind the input, evidence, and proposal identities;
a changed or replaced proposal needs a fresh approval. Repeated resume calls use
completed checkpoints and cached provider responses. A browser, network, SSH, or
R process disconnect does not erase a completed persisted stage.

Keep the project directory on durable storage with filesystem support for atomic
rename and exclusive directory creation. This version was validated on local Mac
storage. Shared filesystems such as NFS require site-specific verification of
those primitives; no general NFS, `fdatasync`, or exactly-once execution guarantee
is claimed. Completed persisted checkpoints are reused; a process interrupted
during an uncommitted local computation may recompute that stage. A lock left by a terminated process is
not removed automatically. Inspect the recorded owner and confirm that no process
is active before calling `sc_run_unlock()` with the exact owner token and a reason
describing the verification. It refuses recovery while a local owner is alive.
Never delete a lock to make two writers run at once.

## Human review

Cell-changing QC requires explicit approval by default. Inspect the QC summaries,
the model's supported thresholds, reasons and risks, and the predicted retained
cell count before approving the current proposal hash. A rejected proposal is
preserved in history. A corrected manual typed proposal can replace it, after
which the new proposal needs approval.

Typed QC permits only inclusive `range` operations on `nCount`, `nFeature` and
available `percent_mt`, with optional exact sample/capture selectors from the
saved evidence. Every filter has at least one nonnegative bound. Unsupported
operations, arbitrary code, invented groups, missing measurements and proposals
that remove every cell are rejected. Threshold proposals do not select a batch,
remove genes or run doublet detection.

For example, revise a saved **toy** proposal or reject it first:

```r
qc <- sc_run_inspect(project_dir)
sc_run_reject(project_dir, qc$pending$hash,
  reviewer = "your analyst ID", reason = "The toy lower bound is too restrictive.")
revised <- qc$pending$proposal$rules
revised$filters[[1]]$min <- 1L        # deliberately permissive toy-only override
revised$rationale <- "Analyst reviewed this toy group and changed its lower bound."
sc_run_propose(project_dir, revised,
  reviewer = "your analyst ID", reason = "Manual structured override for the toy example.")
current <- sc_run_inspect(project_dir)
sc_run_approve(project_dir, current$pending$hash,
  reviewer = "your analyst ID", reason = "Reviewed the replacement and its predicted retention.")
```

`sc_run_propose()` also accepts a local JSON file containing the same typed object.
Reviewing a file does not require a browser or ZIP. With no provider, `sc_run()`
still saves diagnostics and aggregate evidence and returns `awaiting_configuration`;
provide a typed manual proposal with `sc_run_propose()` to continue. For an
explicitly preapproved rule, supply the exact typed rule as both `qc_proposal` and
`review = list(preapprove_qc = rule)`. The coordinator records that preapproval
only if its validated canonical rule exactly matches the proposed rule.

Pending annotation proposals are approved headlessly. Unknown labels and
insufficient evidence are valid outcomes. The coordinator writes `sc_annotation`
and its confidence/rationale companions by default; set `annotation_column` to a
fresh name when an earlier run already has that column. Existing output-column
collisions are rejected, preserving earlier labels.
`sc_run_undo()` currently undoes an executed annotation approval only: it archives
the completed convenience outputs, retains immutable checkpoints and history,
and reopens annotation review from the saved processed object. It does not undo
QC. Completed computation is reported as `EXECUTED`; use `sc_run_accept()` only
after separately judging the scientific result to record `RESULT_ACCEPTED`.

## Providers and data transmission

No provider and no external-transmission consent means no external request. You
can still inspect diagnostics and evidence and provide a manual typed proposal.
Supply a provider factory or a `chat_fn(system_prompt, user_prompt)` to use a
model. The built-in DeepSeek and Grok factories read keys from environment
variables on the machine running R. Configure keys through your user environment
or secret mechanism before starting R. Do not put keys in context, an RDS,
project files, scripts, HTML, logs, or a browser.

Review the outgoing preview before granting consent. External requests contain
the approved aggregate QC or cluster marker/expression evidence and research
context. They exclude raw matrices, barcodes, and personal per-cell metadata.
Free text and sample/capture labels can still reveal sensitive information; use
nonidentifying labels and omit private details. Keeping raw data on the server
does not mean that no aggregate data leaves it.

Model ID, generation settings, usage, response identity, and budget reservations
are recorded without credentials. Calls are serial, cached, and have no automatic
retry. Invalid, empty, unsupported, or uncertain responses stop in a recoverable
state. An explicit retry may make a new request only for a completed invalid
response with known accounting. An interrupted or unknown dispatch remains held
until it can be reconciled; it is never resent automatically. Unknown usage keeps
a conservative budget reservation instead of being recorded as a free request. A mock provider
is sufficient to run the examples and test the complete mechanism without an API
key or fee.

## Optional annotation workbench and SSH

The unified `/review` workbench follows the same project from QC to pending
annotation, exposes supplied marker statistics and saved source provenance,
records typed corrections and approval, and offers supported undo after
writeback. Its explicit Continue launches supported approved local computation;
it does not configure, recover a callback for, or call a provider. See
[annotation review](ANNOTATION_REVIEW.md) and
[unified startup](../workbench/RUN_REVIEW_QUICKSTART.md).

Pending QC has a direct live-project mode that reads the saved impact preview
and records approvals, revisions with reasons, or rejection through the same
atomic R coordinator. In the unified `/review` session, approve the saved QC
proposal, then choose Continue to apply it and run the recorded local stages.
The standalone QC-only review service remains review-only. See
[QC review](QC-review.md) and [QC workbench startup](../workbench/QC_QUICKSTART.md).
Headless `sc_run_resume()` remains available for subsequent computation and
explicitly authorized model requests.

Continue is a separate action from approval. R binds it to the freshly inspected
project ID, input hash and revision and verifies saved configuration,
implementation and artifacts under the project lock. The HTTP service launches a
persisted asynchronous local worker; closing the page, losing SSH or restarting
that service does not by itself cancel the worker or remove saved checkpoints.
Inspect the same project's saved job and run status after reconnecting. A worker
ending at `awaiting_review` or `awaiting_configuration` has paused; it has not
completed the scientific workflow. Only the run's `complete` status indicates
final output. Duplicate bound Continue submissions reuse the job; stale bindings
are rejected rather than silently rebound.

The local Continue boundary never calls a model or offline mock, reads a provider
cache to obtain a new proposal, or approves an outgoing transfer. When another
proposal is missing, it saves `awaiting_configuration` and the required R action.
Supply a manual typed proposal or use the existing explicitly authorized R
provider workflow, then refresh. Keeping a saved annotation plan requires one
approval for the whole proposal, not one approval per cluster. With both proposals
available, raw entry needs QC approve/Continue and annotation approve/Continue;
processed entry skips the QC pair.

The HTTP service starts computation locally; it does not schedule work. Use an
appropriate analysis machine or allocated compute node, not an unapproved login
node. An interrupted R process or node failure still has the checkpoint,
uncommitted-stage retry and owner-verified lock limitations documented above.
No exactly-once execution or general shared-filesystem guarantee is added.
The new Continue main workflow was exercised on the user's Mac with real Chrome
and the fixed R worker using synthetic and public PBMC inputs. It covered local
computation and output, explicit R manual-annotation configuration, browser/HTTP
disconnect and restart recovery, duplicate-job reuse, and an explicit local-failure
retry. Final annotation labels remained `Unknown`; the synthetic result had one
cluster and no supplied markers. No external API request was made and API cost was
US$0. These checks demonstrate the software workflow, not biological cell identity
or every supplementary failure scenario. Earlier Linux headless results belong to
the previous path; this new Continue has not been validated on Linux, HPC or
Windows.

After the coordinator completes, the existing workbench can refine its
automatically managed annotation evidence in `bundle/`. It supports cluster
annotation decisions, unknown labels, review status, reasons, history, and undo.
This annotation-bundle mode does **not** approve a pending coordinator proposal, and its
journal is not automatically imported into `sc_run` state. Use
`sc_run_inspect()` and `sc_run_approve()` for the coordinator's review nodes.
The existing `sc_review_validate()` / `sc_review_apply()` functions remain the
explicit writeback route for a browser refinement journal. See
[`workbench/PROJECT_QUICKSTART.md`](../workbench/PROJECT_QUICKSTART.md).

Run the workbench on the same machine as the project and bind it to loopback. For
example, when the coordinator provides the annotation bundle path:

```sh
sh workbench/run-project.sh /absolute/path/to/project/bundle --port 8770
# Open http://127.0.0.1:8770 only on this machine, or through a tunnel.
```

From your own workstation, replace the host with a server you are authorized to
use and create a tunnel:

```sh
ssh -N -L 8770:127.0.0.1:8770 YOUR_USER@YOUR_SERVER
```

Then open `http://127.0.0.1:8770` on the workstation. The service stays bound to
`127.0.0.1`; this requires no public bind, firewall change, or new authentication
configuration. On a server without a display, print the URL and tunnel command.
Do not try to open a Mac browser from the analysis server. Review can finish
entirely in R when no web service is available.

## Batch jobs and recovery

See [`inst/examples/slurm_sc_run.sh`](../inst/examples/slurm_sc_run.sh) for a Slurm
template. Customize resource requests, paths, R environment, and the command for
your site's scheduler. Run compute on allocated compute nodes. The example does
not submit a job or start compute on a login node.

An `awaiting_review` result is a successful pause: the Rscript process can exit
normally and release the allocation. Inspect and approve the saved proposal, then
run another batch job with `sc_run_resume(project_dir)`. No browser process is
needed during compute. If a stage fails, inspect the saved error and fix its cause;
use an explicit retry only after checking whether an external request could be
charged again. Standard normalization through UMAP is one checkpointed local
analysis stage in this version. A failure inside that unfinished stage reruns
that local stage; completed QC, evidence, approval and provider requests are
reused. It does not promise separate recovery at every Seurat verb.

## Supported scope

This version supports exact raw counts inputs, grouped QC evidence, typed QC
threshold proposals and predicted retention, persistent review, a standard Seurat
normalization/HVG/PCA/neighbors/clustering/UMAP workflow, marker evidence,
independent annotation suggestions, annotation writeback, and the explicit
processed-object entry path. Existing local reference matching can provide
database candidates when a compatible reference is supplied.

The default path shown here does not run Harmony or doublet detection. Optional
`strategy = TRUE` adds the explicit reviewed contracts linked from the
[release checklist](RELEASE_CANDIDATE_CHECKLIST.md). No path automatically
infers study design, chooses a batch correction, detects every doublet or
ambient RNA artifact, validates arbitrary model
parameters, or guarantees correct biology for an arbitrary dataset. These require
project-specific analysis and review. Private data is not used for an unsolicited
API demonstration. Linux/HPC deployment instructions are provided as templates;
only environments listed in the project's validation report have actually been
tested.
