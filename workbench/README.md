# Local workbench

The workbench opens an existing `sc_run()` project on the machine holding its
data. `/workbench` shows saved QC, strategy, analysis, annotation, outputs and
history. **Review current step** opens `/review` for decisions and optional local
computation. Start a project with the [R tutorial](../README.md#first-analysis)
first; the browser is optional.

## Start from an RDS file

### Start from R

After installing the package, keep using R:

```r
library(scAgentKit)
sc_start("a.rds", "analysis",
  context = list(species = "human", tissue = "Peripheral blood",
    research_goal = "Characterize the major immune populations."))
# Later: reopen the saved project.
sc_start("a.rds", "analysis")
```

This opens a loopback review service with explicit local continuation and returns
control to R. It passes the current R executable and library paths. On first use,
Python ≥ 3.9 must already be available. Browser assets and Python modules are
included in the R package. The launcher installs nothing. A matching source
checkout can be selected explicitly with `checkout=` (or the developer option
`scAgentKit.checkout`); it is checked against the installed R functions and
resource manifest. Development changes require regenerating the manifest with
`Rscript tools/build-workbench-manifest.R` and reinstalling the package.
Repeating the call reuses a matching live service or restarts a stopped service.
Changed RDS paths/content or explicitly changed saved context/reuse settings are
rejected rather than replacing the existing project. For a read-only viewer use
`sc_run_open()` instead.

Supply known metadata roles through `context$columns` and experimental design
through `context$design`; the normal coordinator validates them. The launcher
does not infer these facts. Explicit processed reuse uses
`reuse_processed=TRUE, processed_reason="..."`, with `cluster_column` if needed.
It starts at annotation and does not claim a new raw strategy/QC approval.

### Start from a terminal

In an environment with R, Seurat, the package and Python ≥ 3.9 already installed,
one command creates a new project and starts the local review service:

```sh
python3 workbench/start_analysis.py a.rds --project pbmc-analysis \
  --species human --tissue "Peripheral blood" \
  --research-goal "Characterize the major immune populations"
# Add --r-library /path/to/private/R-library when needed.
```

Use the printed loopback URL. Review and edit the strategy, then select
**Approve strategy and continue locally**. At the annotation boundary, select
**Prepare annotation table**, inspect the markers and fill in the blank rows.
Save the complete proposal, inspect it, then select **Approve annotation and
continue locally** to produce the saved result. These are two scientific
approvals; starting the service and preparing a table grant neither approval.

To leave populations unresolved, supply one reason and explicitly select
**Keep all unfilled populations Unknown**. Known labels require citations from
their own supplied marker evidence. Unresolved population and cell counts remain
visible in the result; a completed workflow does not resolve their identities.

The launcher does not install software, infer species or experimental design,
configure a provider, request a model, or replace an existing output directory.
The selected R library must contain this checkout's workflow implementation.
Keep the terminal open; Ctrl-C closes the local service. Existing projects can
be reopened with `server.py --run-project PATH --local-continue`.

Raw-count analysis is the default even when the input has saved reductions or
clusters. To deliberately reuse normalized data and supplied clusters, add
`--reuse-processed --processed-reason "Explain the reuse decision"` and, if
needed, `--cluster-column COLUMN`. This advanced entry starts at annotation
preparation; it does not perform or claim a new strategy/QC approval.

## Open saved results

Install the R package using the [R package installation](../README.md#installation).
Projects started with `sc_start()` also configure the existing read-only viewer
with the installed package resources. Keep the matching R environment for saved
projects; changing their execution kernel does not grant fresh approval.
For projects created directly with `sc_run()`, select the installed package root
once using `checkout = system.file(package = "scAgentKit")`.

With scAgentKit loaded in the project's R environment:

```r
sc_run_open(project_dir, checkout = system.file(package = "scAgentKit"))
# Subsequent sessions reuse the saved viewer configuration:
sc_run_open(project_dir)
```

This read-only viewer starts or reuses a matching loopback service. It performs
no analysis or model request. Python >= 3.9 is required. Installed resources
are sufficient; a matching checkout remains an optional developer override.
The [researcher guide](../docs/RESEARCHER_PROTOCOL_ZH.md#8-同一项目的可选网页与服务器运行)
has remote-use and scheduler templates.

## Review and continue

To enable review and approved local computation, start the service from the
checkout root with the same R executable and library used for analysis:

```sh
python3 -B workbench/server.py \
  --run-project /absolute/path/to/project \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/private-r-library \
  --local-continue --port 8775
```

Open `http://127.0.0.1:8775/workbench`. Omit `--local-continue` to keep computation
in R. Node is used for tests, not to run the service.

1. Inspect the current evidence and saved strategy or annotation proposal.
2. Revise if needed, then approve the complete saved proposal with a reviewer
   and reason. Approval records a decision; it does not execute analysis.
3. Choose **Continue** to perform the approved local step. It stops at the next
   saved review/configuration boundary. Only run status `complete` means outputs
   have been finalized.

Continue does not request a model. Optional `--model-mock` or
`--model-suggestions` enables a separate request worker for an already configured
provider. Its exact aggregate preview, request consent and scientific approval
are described in [model review](../docs/UNIFIED_MODEL_REVIEW.md).

## Parent and child projects

Add `--subcluster-workspace /absolute/path/to/child-workspace` with a directory
separate from the parent. Once the parent is complete, select exact parent cells
to create a registered child. Each child has its own strategy, review and outputs.
Project links keep browser tabs bound to their selected parent or child.

After child completion, inspect and approve the exact-cell application to a
**new** parent object. The original parent remains unchanged. The parent view
lists derived receipts; apply and undo retain versioned history. See
[subcluster review](../docs/SUBCLUSTER_REVIEW.md) for the R route and conflicts.
`--subcluster-inherit-model` explicitly copies safe model configuration to new
children; it does not copy keys, callbacks, request consent or scientific approvals.

## Saved views and interrupted sessions

Analysis coordinates and markers come from verified saved checkpoints while
annotation is pending, or from the fixed output bundle after completion. Pending
annotation is labeled as such. Missing optional views are reported explicitly.
The browser displays artifact paths; read Seurat RDS files locally in R.

Closing the browser or losing a tunnel does not cancel a local worker. Reconnect
to the same project and inspect saved job/run status. Refreshing, navigation and
polling never approve work or dispatch a new request. After a worker failure,
investigate before an explicit retry; do not remove an active lock.

Completed-run authority is the Seurat output and checkpoints. Modified or missing
convenience CSV/PNG files do not invalidate those authoritative artifacts. Views
never display an export that fails its receipt check. If a bundle is damaged,
the project status and history remain accessible with a warning; inspect the
verified result in R. A changed authoritative checkpoint or Seurat output remains
an integrity error. See [outputs and recovery](../docs/RESEARCHER_PROTOCOL_ZH.md#11-输出恢复与可复现记录).

The saved overview has a 16 MiB display limit and refuses oversized views instead
of silently truncating them. Use local R inspection when a view cannot be supplied.

The project view keeps the saved embedding and selected-cluster markers visible.
Cell-label proportions use the finalized annotation column and every cell in the
exact saved output as their denominator, including missing labels. Pending
proposals are not counted as finalized cell types. A read-only question list
surfaces recorded Unknown/low-confidence labels, missing citations/markers and
explicit saved candidate disagreements; it retains access to all clusters and
the complete review. Flags are inspection aids, not identity scores or approvals.
The review editor already fills fields and marker checkboxes from the same saved
proposal; change disputed rows, save, inspect the rebuilt complete plan and
explicitly approve it. Navigation and summary generation do not write decisions.

## Remote access

The listener binds to `127.0.0.1`. Forward the same port through an existing
authorized SSH connection:

```sh
ssh -N -L 8775:127.0.0.1:8775 your-existing-ssh-host
```

Run computation on an appropriate machine or allocated node. The service does
not allocate scheduler resources. Loopback and Host/Origin checks are not per-user
authentication on a shared host. The browser worker requires POSIX `flock`;
use headless R when that is unavailable. Runtime scope is described in
[runtime support](../docs/LINUX_RUNTIME_SUPPORT.md).

## Technical reference

These interfaces remain available for specific export-based or developer workflows;
they are separate from the project route above:

- [Coordinator review and worker details](RUN_REVIEW_QUICKSTART.md)
- [Portable project adapter](PROJECT_QUICKSTART.md) and [schema](PROJECT_SCHEMA.md)
- [QC adapter](QC_QUICKSTART.md) and [expression evidence](EXPRESSION.md)
- [Backend and browser checks](tests/TEST_PLAN.md), [project adapter checks](tests/PROJECT_TEST_PLAN.md)
- [Mouse ortholog snapshot](data/mouse-orthologs/README.md)

The historical frozen PBMC adapter can still be started with
`sh workbench/run-local.sh /path/to/frozen/phase1/results --port 8765`.
It expects the exact fixture allowlist in `evidence.py`, rather than arbitrary
input data. Its test requirements are documented in the test plans above.
The workbench is excluded from R package builds.

## Runtime distribution

`inst/workbench/` is the single canonical production source. The root
`workbench/` entry points and assets are compatibility symlinks for development;
they are excluded from R packages. Installation generates a manifest from the
R function signatures and every shipped runtime asset. Startup checks both
against the selected installed R namespace before execution. Missing, extra or
changed runtime files fail closed. Python bytecode caches are excluded.

## Evidence-assisted annotation

The preparation table presents saved marker/reference facts and sources before
any labels are selected. It lists tied reference evidence first, with details
collapsed. Candidates retain their actual coverage numerator/denominator and
single-marker limitations. Choose one explicitly to populate an untouched row's
label and admissible citations; write confidence and interpretation yourself.
Human-edited or locally kept rows cannot be overwritten by candidate/bulk actions.

The complete worksheet still saves one typed proposal for separate approval.
Local keeping is optional draft protection, not row-level scientific approval.
Same-tab drafts restore only for exact project/input/evidence/revision bindings;
older drafts are not silently migrated. Discard local edits explicitly to switch
to the model path. See [the formal guide](../docs/ANNOTATION_ASSISTANCE.md).

For an already configured saved provider, enable its existing preview/authorize/
request/adopt component through the same R entry:

```r
sc_start("a.rds", "analysis", model_suggestions = "configured")
```

The default is `"off"`. Unconfigured manual projects continue locally without a
model. Provider/model/budget remain immutable R-side configuration; no browser
credential input is added. Explicit `"simulate"` is for saved mock projects only
and is visibly marked as a zero-model software control.
