# Reviewed subclusters, exact cell scope, new parent output

Start from a **completed** `sc_run` parent. Select one or more literal parent
cluster IDs, create a separate child project from their raw counts, review one
whole child strategy, then review the child's annotations. Applying the child
creates a new derived parent RDS with fresh subtype columns. The original
parent project, output object and annotation columns remain unchanged.

The same operations work from R without a browser. The optional workbench uses
these R operations and the existing typed strategy/annotation/Continue path;
there is no second analysis engine, manual ZIP exchange or model request in the
subcluster actions.

## Headless start from your completed parent

Install this checkout in the library used by your run. The installed helper
keeps inspection separate from decisions and does not read a key or call a
provider:

```r
library(scAgentKit)
source(system.file("examples", "subcluster-review.R", package = "scAgentKit"))
parent <- "/absolute/path/to/completed-parent"
child <- "/absolute/path/to/subcluster-workspace/child-T"
dir.create(dirname(child), recursive = TRUE, showWarnings = FALSE)

# First inspect available literal IDs and counts. A label such as "T cells"
# is not an ID unless that is the value in the declared cluster column.
available <- subcluster_example_scope(parent)
available$clusters
selected <- subcluster_example_scope(parent, clusters = c("1", "4"))
selected$selected                    # union count and frozen selection hash

subcluster_example_create(parent, child, selected,
  reviewer = "analyst", reason = "Inspect the selected populations at finer resolution.")
view <- subcluster_example_inspect(child)
view$run$strategy_review$details      # all child settings and exact QC impact

# This approves only the displayed strategy. Inspect again after each action.
subcluster_example_decide(child, view, "approve", reviewer = "analyst",
  reason = "Reviewed the displayed child strategy, scope and applicability.")
view <- subcluster_example_inspect(child)
subcluster_example_continue(child, view)
view <- subcluster_example_inspect(child)
```

The child directory must be new and separate from the parent; its containing
workspace must exist. Nested parent-to-child-to-grandchild analysis is not
supported in this increment.

Child input contains only the selected raw-count layer and source metadata.
Species and declared study context are inherited with parent provenance.
Parent embeddings, neighbor graphs and active cluster identities are not
reused; parent cluster/annotation columns are source facts, not child truth.
The child receives its own project ID, input hash, parameters, seed, evidence,
review decisions, checkpoints and outputs.

Without a provider, Continue stops normally at annotation configuration. To
retain uncertainty for every actual child cluster:

```r
subcluster_example_unknown(child, view, reviewer = "analyst",
  reason = "The supplied child evidence does not justify biological identities.")
view <- subcluster_example_inspect(child)
view$run$annotation_review$details
subcluster_example_decide(child, view, "approve", reviewer = "analyst",
  reason = "Keep the displayed Unknown/low annotations and their uncertainty.")
view <- subcluster_example_inspect(child)
subcluster_example_continue(child, view)
view <- subcluster_example_inspect(child)
stopifnot(view$run$status == "complete")
```

`Unknown` is an explicit unresolved annotation, not an automatically inferred
cell type. A typed manual annotation proposal can instead use the usual
`sc_run_propose`/`sc_run_review` route. Known labels must cite supplied markers
for their exact current child clusters. Empty marker evidence can still be
reviewed as `Unknown`/`low`; cluster numbers alone are not labels or parent cell
IDs.

## Inspect, then apply by literal cell ID

```r
view <- subcluster_example_inspect(child, column = "sc_T_subtype")
view$apply_snapshot                  # parent/child hashes, scope and new columns
applied <- subcluster_example_apply(child, view, reviewer = "analyst",
  reason = "Apply the reviewed child annotations to a new parent copy.",
  request_id = "T-subtype-apply-001")
derived <- readRDS(applied$application$output_path)
```

Only the child cells retained by its exact approved QC decision receive labels.
Cells outside that retained scope, including deliberately filtered selected
cells, receive `NA` in the new columns. This version supports `outside = "NA"`
only. Original parent cell order, raw/normalized layers, other metadata,
annotations and reductions are preserved. Writes align by literal ID even if
the child output is reordered; duplicate IDs, unexpected missing/extra IDs and
numeric cluster-to-parent mappings are rejected.

Inspect binds the parent's project/input, revision, cluster membership and
output hash, and the child's current completed annotation evidence/output.
Apply checks these again under locks. Changing the parent revision, input,
membership or output rejects the old snapshot; a matching cell set alone is
insufficient. A target-column conflict or a changed child annotation requires
a new inspection. Repeating the **same** request ID and payload reuses its
receipt; reusing it for different work is rejected.

Applications are immutable versions in the child's integration history, linked
to both projects. They do not modify the original parent or silently merge
overlapping children. Two children can overlap while producing separate parent
derivatives; combining them is outside this version's scope.

```r
# Undo creates a restored version; it does not rewrite/delete existing RDS files.
view <- subcluster_example_inspect(child, column = "sc_T_subtype")
undone <- subcluster_example_undo(child, view,
  application_id = applied$application$application_id,
  reviewer = "analyst", reason = "Withdraw this subtype application.",
  request_id = "T-subtype-undo-001")
restored <- readRDS(undone$undo$output_path)
```

After revising and reapproving child annotations, inspect and apply again. To
replace that child's current active application to the same target column, pass its
application ID as `supersedes` to `subcluster_example_inspect`. A new immutable
derived object and linked history record are created; a different child's
application cannot be supplied as authorization. Undo and repeated revisions
remain exact-scope operations. An undone application is already inactive; a
later application does not pass that withdrawn ID as `supersedes`.
Undo of a replacement restores and reactivates its linked previous application;
undo of the first application creates a restored copy of the original parent.

## Explicit child choices

Creation records these choices before the central child strategy review:

| Choice | Default | Supported alternative and boundary |
| --- | --- | --- |
| QC | `retain_selected` | `review` permits only the displayed, approved exact-ID subset of the frozen selection. Default prohibits a second filter. |
| Doublets | `keep` | No child score refit or second doublet removal. Verified parent scores retain their original cohort provenance; they are source evidence only. |
| Batch | `none` | `review` enables the usual typed strategy selection with fresh child design checks. Parent correction is not inherited. |
| Cell cycle | `none` | `recompute` requires explicit fresh `cycle_diagnostics` and a new score-column prefix; regression still needs applicability and strategy approval. |
| Reference | `none` | `inherit` requires a verified local parent reference snapshot and explicit source version. Child marker candidates are recomputed. |

For example, supply `choices = list(qc = "review", doublet = "keep",
batch = "review", cycle = "none", reference = "inherit")` when creating a new
child. Changing these creation choices means creating a new child rather than
silently weakening the existing one. Scores without a verified parent artifact
are metadata only, not validated child evidence. Fresh cycle scoring does not
turn parent fixed-cohort scores into child scores.

`strategy_proposal = NULL` gives a disclosed **software starting plan**, not an
AI recommendation: LogNormalize/10,000; HVGs up to 2,000 expressed genes;
computed PCs up to 30 and the cell/feature rank limit; selected PCs up to 20;
seed 17; resolution 0.4; no batch correction; UMAP neighbors up to 30 and
`n_cells - 1`. The complete actual settings are shown for one whole approval.
Pass a complete typed `strategy_proposal` to choose other supported values.
Invalid user values fail validation and are not clipped or replaced with 0.5.

The graph path requires **at least 21 selected cells** and three expressed
features. Smaller or empty selections are blocked before publishing a child;
there is no silent neighbor/resolution fallback. A fresh approved QC selection
must also satisfy the supported analysis requirements.

Inherited reference provenance, including CM2 when supplied as that reference,
includes the verified parent snapshot, explicit source version and child scope.
Current child markers and candidates are regenerated;
historical parent cluster candidates, annotations and LLM-response rows are
not imported as current child evidence. Parent selection is a conditional
analysis scope, not independent biological validation.

## Optional loopback workbench

Start on the machine holding the parent and a separate child workspace. A
pending parent may finish its approved analysis in the same service; child
creation waits for its verified completion. Use this checkout's package in the
selected R library:

```sh
python3 workbench/server.py \
  --run-project /absolute/path/to/parent-project \
  --subcluster-workspace /absolute/path/to/subcluster-workspace \
  --r-library /absolute/path/to/private-r-library \
  --local-continue --port 8773
```

Open `http://127.0.0.1:8773/review` for a pending parent, or `/subclusters` for
its workspace. Once the parent completes, select exact parent clusters, inspect
the union and provenance, enter the rationale, and create a child. Open that child,
review its whole strategy, approve and Continue; supply/review its annotations,
then inspect and apply back to a new derived parent output. Child selection in
HTTP uses registered project IDs, not browser-supplied filesystem paths. The
workspace registry can be inspected in R with
`sc_run_subcluster_list(parent, workspace)`.

The selection/writeback page is `/subclusters?child_id=<registered-project-ID>&project_id=<same-ID>`;
central child strategy/annotation review and Continue use
`/review?child_id=<the-same-ID>&project_id=<same-ID>`. Registered navigation
links supply those bindings. See [single-service review](SINGLE_SERVICE_REVIEW.md)
for returning to the parent and inspecting saved derived receipts without
restarting the service. Web creation offers explicit QC
`retain_selected`/`review`, batch `none`/`review`, and reference
`none`/`inherit` choices, defaulting to retain/none/none. Reference inheritance
still requires the verified parent snapshot and source version; selecting it
does not bypass R validation. Doublets stay `keep` and cell cycle stays `none`
in the web creation form. Fresh cycle scoring settings use the headless R
entry above. These creation choices bound what the child's later central
strategy review can authorize; selecting `review` does not execute a filter or
correction. Changing the target column or
`supersedes` requires refreshing saved state before applying its newly bound
preview. The completed source parent is read-only; before completion its
approved local Continue remains available when explicitly enabled.

The server binds to loopback only. On your own computer, an existing authorized
SSH connection can forward the same port:

```sh
ssh -N -L 8773:127.0.0.1:8773 your-existing-ssh-host
```

This is a template, not an attempted login or scheduler submission. Without
browser access, use the same R helper and saved project. Closing the browser
does not mutate the parent or cancel a persisted Continue job. Refresh and
inspect saved status after restart; do not remove an active lock. Cancelling
the child selection or declining apply saves no application.

Orderly creation errors release their owned locks and allow a retry with the
same request and payload. A killed R initializer can leave an abandoned lock;
this version does not remove it automatically. Confirm the recorded owner has
stopped before explicit recovery. `sc_run_unlock` requires saved run state and
cannot recover a creation lock left before the initial state was saved.

By default, child creation uses zero provider budget and does not inherit a
provider; manual proposals and unresolved annotation remain supported. Explicit
model-configuration inheritance and separately approved aggregate requests are
available through [unified model review](UNIFIED_MODEL_REVIEW.md). That option
does not copy keys, callbacks or parent consent into a child. The browser
displays output paths; it does not serve the expression matrix or RDS, accept
credentials, automatically choose biological identities, merge children or
submit cluster jobs. Local review contains exact IDs needed for review, while
provider transfer remains a separate authorized aggregate-only operation.

## Legacy boundary and validation scope

The acceptance counts below are historical scoped-subcluster receipts, not a
fresh release-candidate check or the later single-service acceptance. See the
[release checklist](RELEASE_CANDIDATE_CHECKLIST.md) and
[single-service review](SINGLE_SERVICE_REVIEW.md) for those distinct records.

The new path does **not** call `annot_subcluster`. That older function has
positional parent writes after subset calculations, and its automatic
resolution helper can fall back to 0.5 on malformed output. Those behaviors
are not accepted by this exact-ID, typed reviewed path. The legacy function
remains a separate API; this increment does not claim to repair every legacy
sub-annotation mode.

Mac acceptance on 2026-10-05 passed 13 focused mechanism tests with 399
assertions and no failures, errors, warnings or skips. Full `R CMD check
--no-manual --ignore-vignettes` finished with `Status: OK`; its test suite
reported 7,136 passes and zero failures, warnings or skips. Optional Suggests
dependency INFO remains in the check log, and the command deliberately skipped
vignettes. The full Python suite passed 255 tests without failures, errors or
skips; all 62 protected fixture SHA256 values remained unchanged.

Native Chrome 154.0.8037.93 passed all eight acceptance checks through the
actual R bridge. From a 480-cell synthetic parent, selecting literal cluster
`"0"` created an 80-cell child, followed by whole-strategy approval, fresh
analysis, manual `Unknown` annotation review, derived-parent apply and restored
undo output. Cancellation, duplicate creation/apply, and HTTP server restart
preserved saved authority and parent bytes. The owned server, browser and
temporary profile were closed after testing; no hidden R annotation assistance
was used.

Six independent R processes completed create, strategy, annotation, apply,
undo and verify for a 35-cell selection from the 2,700-cell public PBMC parent.
The child produced one cluster with reviewed `Unknown`/`low` labels. Checks
confirmed sparse raw-count preservation, fresh child PCA, literal-ID writeback
with outside-scope NA, unchanged parent files, immutable application/restoration
outputs and idempotent completed Continue/apply/undo after restart. A separate
six-process headless cycle also passed for an 80-cell selection from the
480-cell synthetic parent, retaining all 80 cells in one unresolved child
cluster. A real concurrency test released two R creators from one barrier:
one saved the child at review and the other was rejected by the lock; a third process reused
the same request without changing state bytes.

Injected creation/apply/undo errors exercised explicit recovery of saved
receipts and orphaned artifacts; these are not SIGKILL recovery results. All
acceptance used zero provider calls, no key-file reads and US$0 API cost. These
are software workflow checks on Mac, not Linux/HPC validation, biological
annotation accuracy or evidence for a universal subcluster resolution.
