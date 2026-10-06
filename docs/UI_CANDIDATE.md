# Blue workflow candidate

This is an independent local UI candidate. The scientific R implementation is
the frozen b43 candidate; the blue main-view design comes from e81d416. Visual
acceptance remains pending researcher feedback.

Start the existing server with an installed compatible scAgentKit library and
one server-side project. Use a separate child workspace if subanalysis is needed:

```sh
python3 -B workbench/server.py \
  --run-project /absolute/path/to/project \
  --subcluster-workspace /absolute/path/to/separate-existing-child-directory \
  --local-continue \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/compatible-r-library \
  --port 0
```

Open the printed loopback address followed by **`/workbench`**. This is the
project entrance: current step, saved QC impact, embedding, marker evidence,
annotation and outputs. Its navigation opens the scoped review and child tools
in the same service. The project directory holds checkpoints, approval history,
bundle and outputs; ordinary review does not require ZIP import/export or
moving a large RDS.

Enabling a child workspace freezes a completed parent's review decisions. To
try parent annotation undo before creating children, start without
`--subcluster-workspace`; stop that service and restart it with the separate
workspace after finishing parent review. Both launches use the same saved
project and `/workbench` entrance.

The launch above enables explicit approved local computation. It supplies no
model-dispatch flags. A new model request still belongs to the project's
configured, separately approved workflow. Keys are configured on the analysis
machine; they are never browser form fields. For server use, retain loopback
binding and access through an operator-created SSH tunnel. This candidate does
not submit scheduler jobs or open a browser automatically.

In review, inspect the complete strategy, QC retention and visible risks before
saving edits or approving. Approval and execution have separate saved states.
Local Continue runs the approved stage and can stop at another review node.
Annotations retain source, uncertainty, rationale and decision history. Undo
adds a compensating record. Child writeback undo creates a restored derived
output, while earlier history remains saved.

Parent annotation undo archives the prior annotation and returns the saved
project to a stopped review boundary. A fresh proposal must then be configured
through the existing R workflow. This candidate does not automatically resend
or readopt the old suggestion after undo.

A selected parent population creates an independent child. Parent annotation
is saved provenance and a soft hypothesis, not child ground truth. At the
stopped child annotation boundary, its context tool can correct or disable that
hypothesis. Context correction invalidates the prior annotation proposal and
requires fresh review; it preserves completed foundation calculations. Child
writeback uses exact retained cell IDs and creates a new parent RDS. Unselected
cells and old annotation columns retain the existing preservation policy.

Seurat outputs are saved on the analysis machine and shown as local paths;
the web service does not download raw RDS objects. Load a saved output from R
with `readRDS(path)` when needed.

Research context notes, approval reasons and cluster rationales remain part of
the R workflow. The earlier evidence/session workbench retains its separate
note capability in its existing mode. Those sessions are not silently combined
with an R project's journal.

Use a new engineering project for experiments and acceptance checks. Public
offline fixtures, manual labels and mock suggestions demonstrate software
behavior; they are not validated QC recommendations or biological findings.
The prior two-request real-AI PBMC run remains a separate completed record.
