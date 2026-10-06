# Review a parent and its children with one local service

The parent project and a separate child workspace can share one workbench
process. Review the parent, complete its approved local computation, create a
registered child, review that child and return to the parent's derived-output
receipts. Projects stay on the analysis machine. The browser uses registered
project IDs; it does not ask you to move RDS files or export/import ZIPs.

For the navigable saved overview, QC, strategy, analysis, annotation, outputs
and history, open `/workbench` on this same service. See the
[saved-project workbench guide](UNIFIED_PROJECT_WORKBENCH.md). Its historical
views are read-only; **Review current step** opens the workflow below for the
same registered project. `/review` remains the direct current-review route.

This is a service and navigation increment. The existing R coordinator remains
the authority for scientific proposals, approvals, locks, hashes, computation
and outputs. A project switch neither approves a proposal nor starts a model
request or local computation. Historical synthetic Mac acceptance completed the
parent annotation,
child strategy and annotation, and derived apply in one service process.
Read-only Chrome follow-ups verified the saved parent/child navigation and
derived-output display. Fresh headless R verification passed all 20 object and
history checks. Its precise scope and retained failed test receipts are below;
the current public PBMC experience comparison is in
[first-use review](FIRST_USE_REVIEW.md).

## Shortest startup

Initialize the parent once with `sc_run()` on the machine holding the data.
Use a compatible installed scAgentKit library, the fixed Rscript executable and
an existing child-workspace directory separate from the parent. From this
checkout, start one service:

```sh
python3 workbench/server.py \
  --run-project /absolute/path/to/parent-project \
  --subcluster-workspace /absolute/path/to/child-workspace \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/private-r-library \
  --local-continue --port 8775
```

Open `http://127.0.0.1:8775/review`. A pending parent can be reviewed and
continued in this service; child creation becomes available only after R
reports the parent complete and verifies its saved output. An already completed
parent may also be used as the starting point. The completed source parent is
then read-only for the child workspace. Child apply writes a new derived parent
object and a versioned receipt; it does not rewrite the original parent RDS or
its existing annotation columns.

The command above needs no model provider. For a parent already initialized
with an immutable **mock** provider, add `--model-mock` for clearly marked,
zero-API suggestions. To make that same configured model capability available
to a new child, also add `--subcluster-inherit-model`; inheritance is explicit
at child creation. It copies safe configuration and a separate per-child budget
ceiling, not keys, callbacks, parent consent, approvals or prior spending.

For an already initialized supported real provider, `--model-suggestions`
enables its request worker instead of `--model-mock`. Runtime credentials stay
in the analysis machine's environment. A real request still requires preview
and explicit approval of its exact aggregate payload. The clearly labelled
**Approve and request** button saves consent, verifies the same payload and
starts that request. If the response is lost, refresh only inspects saved state;
an already approved request still has an explicit request button. This
experience increment makes **no real API calls** and does not validate live
provider dispatch. The webpage cannot configure provider, model, endpoint,
settings, budget or credentials. See [unified model review](UNIFIED_MODEL_REVIEW.md)
for request, cache, reservation and unknown-usage behavior.

The listener remains `127.0.0.1`. For an existing authorized remote connection,
the optional tunnel template is:

```sh
ssh -N -L 8775:127.0.0.1:8775 your-existing-ssh-host
```

This guide does not create a login, change a firewall, submit a scheduler job or
provide multiuser HPC authentication. Run local computation on an appropriate
machine or allocated node. On a shared host, loopback access is not user
isolation. If there is no browser, use the headless route below.

## Parent, child and saved results

The review page's project list names the registered parent and children. Open
the appropriate `Parent:` or `Child:` link; that tab stays bound to its selected
project. The parent's **Select parent cells or inspect derived outputs** link
opens the workspace after completion. Before completion, the workspace shows
the saved parent status and a link back to its review. Active and historical
derived receipts are listed on the parent review; **Inspect derived output
receipt** opens the child's exact application view. Creating a child now opens
its central scientific review directly. A completed child has a **Review exact child labels and save a
new parent object** link; after an explicitly approved apply,
the page returns to the parent and shows the active derived receipt. These
transitions submit no additional scientific decision or model request.

Scope URLs carry the registered `project_id`, plus the matching `child_id` for
a child. They change the page's scope, not a server-wide selected project. A
tab's IDs, project header and request binding must agree. A foreign project,
unknown child, stale revision or changed input/proposal cannot gain authority
through a page switch.

The central review sequence remains the same in each project:

1. Inspect the current saved scientific evidence. For model assistance, preview
   the exact aggregate payload, use **Approve and request** for this exact
   request, and inspect the validated candidate. The payload is expanded by
   default; read it before granting transmission permission.
2. Adopt or modify a candidate to create a fresh scientific proposal. Approve
   the whole saved strategy or annotation proposal after review.
3. Use local Continue. It runs only the approved local computation and stops at
   the next saved boundary; it does not dispatch a model.
4. Once a child is complete, inspect its exact-cell application preview and
   explicitly apply to a new parent output. A matching saved receipt returns
   you to the parent automatically, with its derived output already expanded.

Changing tabs or refreshing while a task runs does not cancel it or resend it.
The project-scoped saved job, cache and ledger remain with that project. Read
fresh saved status when returning; a receipt from a prior action is not a fresh
approval snapshot. A repeated exact request reuses the applicable saved receipt
or cache. Failures and ambiguous dispatch do not trigger an automatic paid
retry. A stopped worker still needs the existing explicit inspection/recovery
policy; navigation is not recovery permission.

The service exposes only its operator-selected parent and verified children in
that parent's workspace registry. URLs and browser forms cannot choose an
arbitrary filesystem path, load an arbitrary RDS, submit R source or browse the
server. Output paths identify local artifacts; the service does not serve the
RDS or expression matrix. A derived application remains a saved result, not an
automatically opened new executable project. See
[subcluster review](SUBCLUSTER_REVIEW.md) for exact-ID apply, target-column
conflicts, immutable application history and undo.

## The same workflow without a browser

The service is optional. Start with `sc_run(input, project_dir, context=...)`,
then use `sc_run_inspect()`, `sc_run_suggest()` when configured,
`sc_run_review()` and `sc_run_continue()` against a fresh bound snapshot. Saved
state can be inspected and resumed in another R process; the original R
process does not need to wait for review.

The installed [unified model helper](../inst/examples/unified-model-review.R)
provides a copyable synthetic, zero-API sequence. For a completed parent, the
installed [subcluster helper](../inst/examples/subcluster-review.R) provides
headless child creation, whole-plan review, local continuation, derived apply
and undo. `sc_run_subcluster_list(parent, workspace)` inspects that parent's
registered children. These R operations retain their scientific and transfer
approval requirements; no web navigation or ZIP roundtrip is needed.

```r
library(scAgentKit)
source(system.file("examples", "unified-model-review.R", package = "scAgentKit"))
project_dir <- tempfile("scagentkit-review-")
unified_review_demo(project_dir)  # new synthetic project; explicit mock
view <- unified_review_inspect(project_dir, simulate = TRUE)
view$suggestion$preview          # inspect before approving a request
```

For your own input, supply actual sample/capture/condition/batch column roles
and study background rather than copying the synthetic control plan. An
already processed Seurat may use the existing explicit processed entry and
record why foundation calculations are reused. The browser does not infer
donor identity, treat biological condition as batch or make a universal
biologically correct strategy.

## Supported content and limits

| Capability | Available behavior | Boundary |
| --- | --- | --- |
| Parent/child navigation | One service over one operator-selected parent and its registered children; project-scoped review and derived receipts | No arbitrary path selector, unrelated project import or automatically executable derived RDS |
| Scientific decisions | Existing whole strategy and annotation review, local Continue, exact-ID child apply/undo | A navigation click or model request approval is not scientific approval |
| Model suggestions | Exact aggregate preview, explicit request consent, validated typed candidates, saved cache/ledger | Immutable configured provider only; custom in-memory R callbacks remain headless; no new paid calls in this validation |
| Study background | Initial R `context$notes`, research goal and declared design notes; saved context is inspectable | Existing workbench notes/reasons satisfy this release's scope; approved outgoing aggregates can include context |
| Annotation rationale | Existing per-cluster rationale and reviewer/reason fields, saved with the typed scientific proposal and decision | Editing these can change the scientific proposal and requires fresh review; they are not informal notes |
| Gene evidence in `/review` | Supplied marker statistics (`avgLog2FC`, `pct1`, `pct2`, adjusted p values), cited/all-marker views, local-reference overlap, symbol audit and saved source/provenance | Human exact-symbol GeneCards and mouse official mapped candidates/MGI are [click-only links](GENE_LOOKUPS.md); all mouse candidates remain visible, unmatched means local coverage only, no gene chat; omitted markers do not prove absence |
| Separate directed evidence workbench | Existing applicable, explicitly exported RNA facts in the generic evidence workbench | That separate panel is not an arbitrary gene-query feature of the parent/child coordinator review |
| Outputs | Local Seurat/table/report paths and versioned derived application receipts | Original parent remains unchanged during child work; no browser RDS download or automatic child merge |
| Server/HPC use | Loopback transport, durable project state, optional existing SSH tunnel, headless R | This experience increment is tested on Mac; the f9 baseline has separate Linux runtime evidence. No new Linux browser, scheduler or Windows claim |

## First-use experience

See [first-use review](FIRST_USE_REVIEW.md) for the paired public PBMC/mock
normal journey, click definitions, actual source bindings, refresh/restart
checks and current results. The acceptance below remains the historical
synthetic single-service record; its 16 mechanical clicks include validation
round trips and are not a new PBMC measurement.

## Acceptance evidence

The previous unified-model increment passed Mac R and Python regressions and
completed synthetic/public PBMC parent-child-derived workflows with explicit
simulations. Those workflows used separate service launches and do not by
themselves validate this new lifecycle. Keep their evidence separate from the
single-service checks below.

Mac acceptance started from a new processed-entry project using the
previously verified 476-cell synthetic object. The entry records its reuse
reason and source hash, preserving the existing PCA/UMAP foundation rather than
repeating the earlier PBMC calculations. Child analysis used the exact selected
127-cell raw counts, its separately reviewed strategy and fresh PCA/UMAP, and
produced two child clusters. All three model responses were explicit
simulations. Real API calls and incremental API cost were both zero.

| Single-service check | Executed evidence | Result |
| --- | --- | --- |
| Pending parent and workspace activation | Native Chrome and the actual R bridge showed the incomplete-parent waiting page, completed the processed parent's annotation and activated its workspace without restarting the owned service | Passed |
| Child strategy, refresh and two concurrent tabs | Approved child strategy and local Continue; refresh, project switch and a concurrent parent tab rejoined the identical saved active job. The test temporarily paused only its owned Python worker while scientific R continued | Passed; no duplicate job was started |
| Scope and input rejection | Ten actual rejected requests covered mismatched query/header/body/token, unknown child, browser path/RDS, duplicate/empty scope and completed-parent undo; responses were HTTP 409/403/422 | Passed; parent and child state SHA256 values stayed unchanged |
| Parent → child → parent result | The main service passed six flow checks and completed derived apply; its final display assertion was verified by two read-only follow-ups. Each follow-up navigated parent → child → parent and displayed the saved derived receipt with no POST | Passed across the retained receipts; original scientific operations executed once |
| Cache and saved task continuity | Six saved jobs: three simulated requests and three local Continue jobs. Three historical exact-request probes reused saved results; the parent ledger has one simulated entry and the child ledger two | Passed; all ledger costs zero, no extra model dispatch or scientific computation |
| Headless object and history verification | Fresh R checked unchanged source object, literal IDs, old metadata/raw counts/PCA/UMAP, fresh child reductions, five scoped derived fields and exact restoration of the parent after removing them. Public R inspect/list APIs worked, and an old scientific approval was rejected without changing saved files | All 20 checks passed |
| Scientific implementation | All 206 scientific source files are byte-identical to `d24cf727` | Prior 7,224-pass scientific-suite evidence is reused; this increment did not rerun that whole suite or add a scientific algorithm |
| Python regression | Full suite: 298 tests, 296 passes and two intentionally scheduled R-check skips. Both skipped R checks were then run separately with the actual guarded R worker and passed. All 554 read-only fixture files stayed unchanged; a final context delta passed 55 HTTP checks | Passed within the stated split execution |
| DOM and response regression | DOM suites: 286 passes. Separate response suite: 20 cases and 61 checks | Passed |
| Linux/HPC | One existing Linux VS Code window was visible; no executor command was run | Not validated. A window title does not establish a live connection. No new SSH connection or credentials were requested. Windows and live-provider browser dispatch also remain untested. |

The main harness completed derived apply but failed its final display assertion
because it had not opened the collapsed derived-details section. Its failed
receipt is retained. Two read-only follow-ups passed the saved-output display;
the last also verified the corrected frozen-parent context display (`human`
and tissue), with no new mutation. The first two headless verifier attempts
also retained their failures: their gene-order and receipt-location assumptions
were corrected before the final exact-ID/source-layer checks passed. Correcting
these verifier assumptions did not repeat the scientific workflow.

Observed physical clicks include evidence inspection and navigation:

| Session scope | Scientific/scope clicks | Exact-preview consent clicks | Mechanical clicks | Total physical clicks |
| --- | ---: | ---: | ---: | ---: |
| Main workflow | 6: five approval buttons and one literal cluster checkbox | 3, all local mock previews with no external transfer | 16 | 25 |
| Each read-only verification | 0 | 0 | 4 | 4 |
| All three sessions | 6 | 3 | 24 | 33 |

The main workflow saved three whole scientific approvals, one child-creation
decision and one derived-apply decision. Its 25 POSTs comprise 17 flow mutations,
three historical request-cache probes and five rejected negative-test POSTs.
Four reloads (three after request and one during active child work), one
reference-inheritance dropdown selection and 13 programmatic URL opens across
the sessions—including an invalid-UI tab—are separate non-click actions. A
combined scientific approval/Continue button counts once as a physical click.

The verified derived Seurat SHA256 is
`98fc8ebc3dc8fe4f4d84f961820a190d11eab9f73d3964c1b5c1a5da5b6e9502`.
These checks establish saved-state integrity and navigation behavior. The
simulated `Unknown` annotations do not validate biological labels or live model
choices, and the Mac checks do not establish Linux/HPC compatibility.
