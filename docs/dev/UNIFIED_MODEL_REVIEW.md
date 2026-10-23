# Request and review model suggestions in the same project

Developer driver: run from the repository root or set `options(scAgentKit.dev_examples="/absolute/path/to/scAgentKit/tools/dev/examples")`. These focused drivers are not installed; use the [current researcher entry](../user/WORKFLOW.md) for a study.

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
See [First run](../SCIENTIFIC_REVIEW_QUICKSTART.md), [strategy support](ANALYSIS_STRATEGY_SUPPORT.md) and
[scoped child review](../SUBCLUSTER_REVIEW.md) for their supported computations.

Choose the provider/model, generation settings, aggregate-transfer policy
and any required diagnostic inputs **at initialization**. The saved provider
configuration is immutable. Model keys stay in the analysis machine's environment
or user secret mechanism, and a custom callback stays in R memory. See the
[environment-based provider example](../SCIENTIFIC_REVIEW_QUICKSTART.md).
The built-in factories read `DEEPSEEK_API_KEY` or `XAI_API_KEY` at dispatch; no key
belongs in context, RDS, logs, browser fields or URLs.

For the low-level `sc_run()`/`sc_analyze()` entries, `provider=NULL` is a manual project. The convenience `sc_start()` entry detects exactly one available DeepSeek/Grok key; use `provider="manual"` to select manual mode explicitly. Startup alone sends zero model calls. A missing
provider or runtime callback/credential is a configuration boundary, not a model
decision. Supply a manual typed proposal or restore the runtime environment for
the exact initialized configuration. There is no late browser provider, model,
endpoint or generation-setting mutation. A different configuration needs
a new project.

## Reach the existing component from the installed entry

For a saved project already initialized with an immutable supported provider, use
`sc_start(project_dir="analysis", model_suggestions="configured")`.
This enables the existing component; it does not request a model or approve a
transfer. The annotation worksheet has an explicit route to that same preview.
Default `"auto"` follows the saved provider (manual/off, mock/simulate or configured). Explicit `"off"` disables browser model actions; a missing credential leaves manual drafting available. Explicit `"simulate"` requires an immutable mock project and makes
only marked software-control responses, never biological inference.

The browser cannot add a provider to a manual project. Initialization still uses
the existing R APIs described above. A prepared local worksheet now participates
in unsaved-edit protection: save it as a complete proposal or explicitly discard
its current local edits before model actions. Model adopt remains a complete
proposal operation; it never fills selected rows or overwrites locally kept rows.
See [annotation assistance](ANNOTATION_ASSISTANCE.md).

## Preview, approve, request, adopt or discard

The public R action is `sc_run_suggest()`; its actions have distinct effects:

| Action | Saved result | What to inspect before the next action |
| --- | --- | --- |
| `preview` | Exact aggregate evidence, purpose and initialized model/settings | The actual transmitted content, privacy implications, transfer consent and resource limits |
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
source(file.path(getOption("scAgentKit.dev_examples", file.path(getwd(), "tools", "dev", "examples")), "unified-model-review.R"))
project_dir <- tempfile("scagentkit-unified-demo-")
unified_review_demo(project_dir)  # synthetic raw input; immutable mock provider
view <- unified_review_inspect(project_dir, simulate = TRUE)
view$suggestion$preview         # exact payload/model/settings; no external call

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
context=..., strategy_proposal=..., provider=..., review=...)` or the
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

Requests use the saved cache and post-call usage ledger. Known costs and the
number of requests with unknown costs are reported separately; unknown costs
are not zero. There is no monetary cap for a request, project or group of parent
and child projects. There is no automatic paid retry, and a failed/stopped model
request does not silently become an accepted proposal. Restore saved state and
inspect the failure before making an explicit next request. A worker timeout or
crash with ambiguous dispatch blocks browser resending; inspect and reconcile
the R ledger explicitly. Do not edit the journal to force another request.

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
model/settings. The fixed worker records job status and saved results;
browser refresh or HTTP disconnection is not a request retry or scientific
approval. Check durable job/project state after a disconnect before another
action. See [workbench startup and trust boundaries](../../workbench/RUN_REVIEW_QUICKSTART.md).
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
[single-service review](../../workbench/README.md) for project selection,
per-tab binding, startup and remote-use limits.

Child creation defaults to `inherit_model=FALSE`: the child has no inherited
model authority and remains usable with manual typed proposals. In R, explicitly
pass `inherit_model=TRUE` to `sc_run_subcluster()` to inherit the initialized
parent configuration. For operator-mediated child creation, explicitly enable
`--subcluster-inherit-model` as well. Inheritance does not copy a key, runtime
callback, parent request approval or scientific decision. Each child's current
aggregate scope and candidate need their own exact request/scientific review.
Each child records its own request usage and available costs after calls; the
parent's prior charges are not copied. Parent and child requests have no
monetary cap.
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

## Scope

The request worker supports the immutable configured provider, exact aggregate
consent, cached typed candidates and explicit adoption. It does not provide
general literature chat, automatic ontology resolution or biological validation.
Custom in-memory callbacks remain available through R. See the
[workbench guide](../../workbench/README.md) for service and remote-use limits.
