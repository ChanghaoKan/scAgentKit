# Compact blue candidate

This independent candidate starts from `5b48b26`. The previous source directory
and preview remain available. Visual acceptance depends on researcher feedback.

Open **`/workbench`** on the address printed by the existing server. The main
view puts the saved plot, literal cluster selection, marker evidence and current
action first. Source details, parameters and complete records remain accessible
through labeled disclosures. Uncertainty, a pending decision and errors remain
part of the displayed decision context.

For a preview of an already completed server-side project, use an installed
compatible R library and omit computation and model flags:

```sh
python3 -B workbench/server.py \
  --run-project /absolute/path/to/completed-project \
  --subcluster-workspace /absolute/path/to/separate-existing-workspace \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/compatible-r-library \
  --port 0
```

Keep the printed loopback address private to the running machine; use an
operator-created SSH tunnel for a remote project. Nothing here submits a
scheduler job or configures an external model. The project journal, checkpoints,
bundle and Seurat output stay on the analysis machine. Routine analysis does not
require copying a ZIP or a large RDS between machines.

The unchanged workflow, review permissions, context correction, output and undo
boundaries are described in [UI_CANDIDATE.md](UI_CANDIDATE.md). A completed parent
attached to a child workspace has a read-only parent review. Compact presentation
does not grant new approval or execution permissions.

The demonstration uses an already completed public PBMC engineering project and
mock suggestions. Its plots and counts come from saved evidence; Unknown/low
labels do not establish biological identity. This visual change does not validate
QC recommendations or add a claim about a user's Linux/HPC environment.
