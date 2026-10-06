# Request and review model suggestions in the same project

Use `sc_run()` once to initialize a project with verified input, study context and
an optional model configuration. The unified model-review component then saves
an exact aggregate request preview, its request approval, a model candidate and
your decision to adopt or discard that candidate. The same operations are
available from R and the optional loopback browser for a parent or scoped child.
The browser does not require a manually exported ZIP or copy of the source RDS.

Model-request approval and scientific approval are separate. Allowing the model
to see an aggregate payload does not approve its thresholds, PCs, correction,
clustering or labels. Adopting a candidate replaces a typed proposal for review;
it does not execute analysis or accept cell identities. Approve the complete
scientific proposal after inspecting its local evidence and impact, then use
local Continue. You do not need a separate approval click for every cluster.

The validation counts in this guide belong to the prior unified-model increment,
not a fresh release-candidate check. The later single-service acceptance is
documented separately in [single-service review](SINGLE_SERVICE_REVIEW.md); use
the [release checklist](RELEASE_CANDIDATE_CHECKLIST.md) for current-source results.

Mac validation has completed the restartable headless loop and the synthetic
parent/child browser workflow through a new derived Seurat output. The scientific
R source passed `R CMD check` with `Status: OK` and 7,224 passing assertions; the
Python suite passed all 285 tests after the suggestion-response bridge fix.
No new real provider request or paid API use occurred. The offline mode is an
explicit simulation, not a live DeepSeek/Grok result. The installed
[unified-model-review.R](../inst/examples/unified-model-review.R) example
provides the headless sequence with synthetic inputs and a zero budget. Its
bundled helper was also run end to end on a new 120-cell synthetic project:
both request/adoption and separate scientific approval stages completed, with
PCA, UMAP, `Unknown` labels and two zero-cost simulated ledger entries.
See the validation scope and remaining gaps below before extending these
results to another environment or dataset.

## What remains in the starting R call

The analysis machine still needs an installed compatible package/library and a
new durable `project_dir`. Supply the actual named raw-count matrix, Seurat object
or local RDS to `sc_run()`. Declare `species`, `tissue`, actual sample/capture/
condition/group/batch column roles, research goals and relevant free-text notes.
Omit unavailable roles rather than inventing metadata. Captures are not inferred
donors, and a biological condition is not automatically a technical batch.
Ambiguous layers and invalid literal cell/feature IDs require explicit resolution;
the browser does not repair or reinterpret them.

Use `strategy=TRUE` for the existing whole QC/analysis strategy review. An already
processed Seurat may enter at `start_stage="processed"` with the selected layer,
cluster column and an explicit `processed_reason`; that entry records which
foundation is reused. Raw counts and processed input have different authority.
See [First run](FIRST_RUN.md), [strategy support](ANALYSIS_STRATEGY_SUPPORT.md) and
[scoped child review](SUBCLUSTER_REVIEW.md) for their supported computations.

Choose the provider/model, generation settings, budget, aggregate-transfer policy
and any required diagnostic inputs **at initialization**. The saved provider
configuration is immutable. Model keys stay in the analysis machine's environment
or user secret mechanism, and a custom callback stays in R memory. See the
[environment-based provider example](FIRST_RUN.md#connect-a-built-in-provider-through-the-r-environment).
The built-in factories read `DEEPSEEK_API_KEY` or `XAI_API_KEY` at dispatch; no key
belongs in context, RDS, logs, browser fields or URLs.

`provider=NULL` is a supported manual project with zero model calls. A missing
provider or runtime callback/credential is a configuration boundary, not a model
decision. Supply a manual typed proposal or restore the runtime environment for
the exact initialized configuration. There is no late browser provider, model,
endpoint, generation-setting or budget mutation. A different configuration needs
a new project.

## Preview, approve, request, adopt or discard

The public R action is `sc_run_suggest()`; its actions have distinct effects:

| Action | Saved result | What to inspect before the next action |
| --- | --- | --- |
| `preview` | Exact aggregate evidence, purpose and initialized model/settings | The actual transmitted content, privacy implications and budget reservation |
| `approve` | Authority for that exact request snapshot | Its current project/input/evidence/request hashes and revision |
| `request` | A validated typed candidate or a recoverable stop | Candidate parameters/labels, cited evidence, source, uncertainty, usage/cost and failure status |
| `adopt` | The candidate becomes a new unapproved scientific proposal | Fresh proposal evidence, local impact and scientific review hashes |
| `discard` | Candidate/request decision history is retained without adopting it | The still-current scientific proposal and any remaining configuration boundary |

For a copyable offline first run, source the helper and create its **synthetic**
project. The supplied initial strategy is an explicit keep-all software control
with finite demonstration settings; the mock replays it and marks its rationale
and risks `SIMULATED`. It does not invent a scientific strategy. The later mock
annotation candidate is `Unknown`.

```r
library(scAgentKit)
source(system.file("examples", "unified-model-review.R", package = "scAgentKit"))
project_dir <- tempfile("scagentkit-unified-demo-")
unified_review_demo(project_dir)  # synthetic raw input; immutable mock provider
view <- unified_review_inspect(project_dir, simulate = TRUE)
view$suggestion$preview         # exact payload/model/settings and zero budget

view <- unified_review_suggest(project_dir, view, "approve", simulate = TRUE,
  reviewer = "demo analyst", reason = "Reviewed this exact simulated request; no external transfer.")
view <- unified_review_suggest(project_dir, view, "request", simulate = TRUE)
view$suggestion$candidate       # inspect the candidate before choosing to adopt
view <- unified_review_suggest(project_dir, view, "adopt", simulate = TRUE,
  reviewer = "demo analyst", reason = "Adopt the simulated candidate for scientific review only.")
view$strategy_review$details    # inspect its current whole proposal/local impact
approved <- unified_review_science(project_dir, view, "approve",
  reviewer = "demo analyst", reason = "Approve this exact synthetic software-control strategy.")
run <- unified_review_continue(project_dir, approved)
view <- unified_review_inspect(project_dir, simulate = TRUE)
```

Every model-suggestion helper action displays and returns a fresh saved snapshot. The next action
uses that snapshot's bindings; do not reuse `view` from before an intervening
mutation. Repeat the same preview/request/adopt sequence at the saved
`annotation_propose` stage, inspect `view$annotation_review$details`, approve the
whole annotation proposal, and Continue to `run$output$seurat`. This is software
practice with unresolved identities, not a real-data biological recommendation.
When using the example's separate CLI commands, run `inspect` after every
mutation and read its output before the next command. That command saves the
displayed snapshot used for the following decision; an old CLI snapshot fails
the revision checks instead of acquiring fresh authority.

For your own matrix/Seurat/local RDS, use `unified_review_start(input, project_dir,
context=..., strategy_proposal=..., provider=..., budget=..., review=...)` or the
underlying `sc_run()` once. Supply your study-specific typed starting plan, or
leave it unavailable for configured model/manual planning. Do not apply the
synthetic keep-all plan to a real dataset by default. For an initialized built-in
provider, use `simulate=FALSE`; an explicit custom `chat_fn` is supported in R
only for the `request` action and must be reattached after an R restart.

Inspect a fresh snapshot between actions. Approval does not dispatch; request is
the explicit dispatch action. A stale, foreign or changed snapshot cannot acquire
new authority. Unsupported parameters, malformed/empty responses and hallucinated
marker citations do not become executable R. A discarded candidate is not a
scientific rejection or an instruction to generate another answer.

Only the fixed, initialized provider may receive the approved aggregate request.
Matrices, raw cell IDs and personal metadata are excluded from model payloads;
free text and aggregate group labels can still reveal private information.
Keeping the raw object on the analysis machine does not mean no information
leaves it. The trusted local review browser is a different local evidence
destination and may display exact scope/cell IDs.

Requests use the saved cache and usage/reservation ledger. There is no automatic
paid retry. Unknown usage retains a conservative hold, and a failed/stopped model
request does not silently become an accepted proposal. The budget is per project;
do not assume a shared provider account or all parent/child projects have a
combined billing cap. Restore saved state and inspect the failure before making
an explicit next request. A worker timeout/crash with ambiguous dispatch blocks
browser resending; it needs explicit R ledger inspection/reconciliation. Do not
delete its hold or edit the journal to force another request.

After adopting a strategy or annotation candidate, approve its **whole** fresh
scientific review with `sc_run_review()` or the same browser panel. Local
`sc_run_continue()` and the browser Continue button run only approved local
computation. Continue cannot dispatch a model or turn a missing proposal into an
invented decision. Browser request jobs use a separate explicit model action.

## Optional browser worker

The server operator supplies a fixed Rscript and private R library. For an
initialized real-provider parent project, the intended service invocation is:

```sh
python3 -m workbench.server \
  --run-project /absolute/path/to/parent-project \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/private-r-library \
  --local-continue --model-suggestions --port 8774
```

Open `http://127.0.0.1:8774/review`. `--model-suggestions` explicitly enables the
configured-provider worker; it does not change project configuration, grant
payload consent or authorize a new request. This round has not tested a live
provider through that worker. Built-in DeepSeek/Grok workers restore the
initialized configuration using server-environment credentials. Custom in-memory
R callbacks remain headless R operations; the browser cannot restore one from
an environment variable or submitted source code. The optional operator
`--model-timeout` bounds the worker wait (default 300 seconds, range 1–3600); it
does not alter the project's immutable generation settings or approve retries.

For the explicitly initialized synthetic mock project, use `--model-mock`
instead of `--model-suggestions`. This simulates a model and makes zero paid or
external API calls. It does not let a manually configured real project switch
provider through a browser flag. Operator flags are not browser settings.

The browser may preview the request, approve its exact payload, start an
asynchronous request, inspect the saved candidate and adopt or discard it. It
cannot submit R code, a callback, endpoint, key, arbitrary file path, provider,
model/settings or budget. The fixed worker records job status and saved results;
browser refresh or HTTP disconnection is not a request retry or scientific
approval. Check durable job/project state after a disconnect before another
action. See [workbench startup and trust boundaries](../workbench/RUN_REVIEW_QUICKSTART.md).
Browser evidence reads have a bounded 125-second wait to cover the bridge's
120-second limit. A timeout does not trigger an automatic request retry or
invalidate a completed saved job; inspect current durable state before acting.
The service binds loopback only; it does not create SSH access, open a public
listener or configure multiuser HPC authentication.

## Parent and child use the same model-review component

Start the service with both `--run-project` and `--subcluster-workspace`. It can
review and continue the pending parent, then make the child workspace available
after that parent completes. The same process handles its registered child
reviews and the parent's derived-output receipts; a parent-to-child switch no
longer requires stopping and relaunching the service. The completed source
parent becomes read-only in this workspace service. See
[single-service review](SINGLE_SERVICE_REVIEW.md) for project selection,
per-tab binding, startup and this lifecycle's separate validation status.

Child creation defaults to `inherit_model=FALSE`: the child has no inherited
model authority and remains usable with manual typed proposals. In R, explicitly
pass `inherit_model=TRUE` to `sc_run_subcluster()` to inherit the initialized
parent configuration. For operator-mediated child creation, explicitly enable
`--subcluster-inherit-model` as well. Inheritance does not copy a key, runtime
callback, parent request approval or scientific decision. Each child's current
aggregate scope and candidate need their own exact request/scientific review.
Each inherited child copies the parent's configured budget ceiling into its own
ledger. It does not subtract the parent's prior spending or share a total parent/
descendant balance; multiple children can therefore have separate ceilings. The
zero-paid-call checks cannot establish an aggregate billing cap.
Use `sc_run_suggest()` and local Continue for configured-child model assistance;
ordinary child `sc_run_resume()` is not a provider-attachment or dispatch path.

The parent/child service form is:

```sh
python3 -m workbench.server \
  --run-project /absolute/path/to/parent-project \
  --subcluster-workspace /absolute/path/to/child-workspace \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/private-r-library \
  --local-continue --model-mock --subcluster-inherit-model --port 8774
```

That command is for a parent initialized with the explicit mock configuration.
For a real configured provider, replace the mock flag with `--model-suggestions`
and provide its runtime environment. Do not send a real private child aggregate
as a demonstration. The existing child scope, raw-count reconstruction, exact
cell-ID application and undo rules remain in force; a parent's cluster number
is not a child cell ID, and adopting a child suggestion does not rewrite the
completed parent.

## Evidence and remaining gaps

The model sees the saved aggregate evidence and declared context, proposes typed
parameters or annotation rows, and exposes rationale and uncertainty for review.
This does not establish biological correctness, calibrated confidence or a
universal QC/PC/resolution choice. Missing top markers are not absent expression;
database coverage scores are not probabilities. Explicit label relationships
and local reference provenance retain their existing limits.

Free-text study context can be supplied from R at initialization. This increment
does not implement a separate conversational notes editor, a gene-by-gene
explanation chat, new model-driven biological verification, automatic ontology
repair or arbitrary project loading. The single-service guide distinguishes
existing study background, scientific rationale and saved gene evidence from
those unsupported editors/chats. Browser and headless validation are software
checks of the paths below; the prior branch's Linux/HPC checks do not validate
these new model workers. The historical browser checks below used separate
service launches and must not be cited as validation of the later single-service
lifecycle.

| Executed validation | Scope and result |
| --- | --- |
| Mac scientific package check | Frozen scientific R source passed `R CMD check`: `Status: OK`, 7,224 passing assertions and no test failures, warnings or skips. Optional unavailable packages were not exercised. The later bridge fix changes suggestion IPC serialization, not scientific R code. |
| Mac Python regression | After the bridge fix, all 285 tests passed; the existing read-only fixture files were unchanged. A separate pure IPC check covers bounded suggestion responses and rejects mismatched project/input/revision descriptors. |
| Restartable headless synthetic project | Fresh R processes completed strategy and annotation preview/approval/request/adoption, separate scientific approval, local Continue and final output. Repeated requests used cached simulated responses. Verification preserved source identity, exact retained cell IDs, old metadata and annotations, and single execution of completed stages. No browser was needed. |
| Native Chrome synthetic parent and child | Both completed through the shared component, with four exact payload approvals, four whole scientific approvals, child creation and application to a derived output. The source parent remained unchanged during child work. The first harness reached the successful apply response, then read the wrong receipt field; a fresh read-only native Chrome follow-up verified the saved active application and derived output. The failed harness receipt is retained alongside that follow-up. |
| Public PBMC3k native Chrome | Completed the 2,700-cell parent, 1,139-cell child and derived output across three native Chrome sessions: 18 observed button clicks, four exact payload approvals, four whole scientific approvals and eight saved successful jobs. All original parent files remained unchanged during child work. The first session stopped after a short evidence-read timeout before any child request; the bounded-read correction allowed child review to resume. A later acceptance-session limit closed Chrome while an approved local Continue completed durably; a fresh session verified that saved completion and applied the child without another model request or repeated computation. Earlier failed receipts, including the oversized adoption IPC response, remain preserved. Parent object verification passed 22 checks; fresh R verification of the derived object passed all 14 checks, covering exact parent counts/metadata/old annotations and object slots, scoped new columns, child PCA/UMAP and two zero-cost simulated ledger entries. |

All model responses in these executed workflows are explicitly simulated.
Strategy simulation replays an already supplied manual typed plan; annotation
simulation proposes `Unknown`. Local normalization, PCA, neighbors, clustering,
UMAP, markers and reference evidence really execute, but these runs do not test
a live model's scientific choices or establish biological annotation accuracy.
Paid API requests and incremental API cost are both zero.

Linux/HPC validation for the model-worker increment is pending. Its recorded
probe had no visible VS Code window to target and exposed no direct Linux
executor. No new SSH connection, remote command or environment change was
attempted. A later single-service probe found an existing Linux window;
that observation is not a live-executor check. See the
[single-service acceptance status](SINGLE_SERVICE_REVIEW.md#acceptance-evidence)
for the current scope. Windows and live-provider browser dispatch also remain
untested. These are remaining validation boundaries, not assertions that the
user or server is offline.
