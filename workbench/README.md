# Local workbench

The workbench opens an existing `sc_run()` project on the machine holding its
data. `/workbench` shows saved QC, strategy, analysis, annotation, outputs and
history. **Review current step** opens `/review` for decisions and optional local
computation. Start a project with the [R tutorial](../README.md#first-analysis)
first; the browser is optional.

## Open saved results

Install the R package using the [pinned installation](../README.md#installation).
The browser files are excluded from R package builds, so obtain the same source
separately (Git and Python >= 3.9 are required):

```sh
git clone https://github.com/ChanghaoKan/scAgentKit.git
cd scAgentKit
git checkout --detach 727b1afc30b532683e7bf25f85a75d4c04399780
```

Keep this checkout path and the private R library together in your project notes.
Use the matching source for an older project rather than upgrading its kernel
or replacing its saved state to make it open.

With scAgentKit loaded in the project's R environment:

```r
sc_run_open(project_dir, checkout = "/path/to/scAgentKit")
# Subsequent sessions reuse the saved viewer configuration:
sc_run_open(project_dir)
```

This read-only viewer starts or reuses a matching loopback service. It performs
no analysis or model request. Python >= 3.9 and a source checkout are required.
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
