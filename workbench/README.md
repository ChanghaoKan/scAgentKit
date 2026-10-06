# Local research workbench

A small, local evidence and review interface for the frozen PBMC3k phase-one
run. It reads real coordinates, marker measurements, reference candidates and
36 cached provider results. The directed loop classifies disagreements, reads
targeted RNA evidence locally, and prepares a provisional review. It does not
apply automatic annotations or call a model.

## Start

Python 3.9 or newer and a modern browser are sufficient. No package installation,
Node runtime, R session, authentication setup, or external service is required to
use the workbench.

The optional directed RNA tab additionally requires an existing R installation
with SeuratObject, Matrix, jsonlite and digest. It uses the frozen retained
Seurat RDS explicitly supplied by the operator; no package installation is
performed by the server.

From the repository root:

```sh
sh workbench/run-local.sh /path/to/frozen/phase1/results --port 8765
```

Open **http://127.0.0.1:8765**. The server always binds to `127.0.0.1`; there is
no option to expose it on a network interface. Stop it with Ctrl+C. By default,
the session is saved in ignored `workbench/.local/session.json`. To start a
separate session or restore a handoff into an empty store, supply
`--session /path/to/new-session.json`. An existing history is never replaced by
a conflicting import.

The `--results-root` must contain the phase-one directories named in
`evidence.py:ALLOWED_FILES`. Source data is deliberately excluded from Git.
Missing, malformed, inconsistent, or unexpectedly sized input is rejected.
The verified fixture is 2,700 input cells, 2,638 retained cells, nine clusters;
cluster 6 contains 155 cells. Calls comprise 33 strict valid results, two format
rejections and one transport failure. This MVP intentionally validates this
one frozen fixture; it is not a general-purpose dataset uploader.

To enable the directed evidence loop, use a separate session/cache and port:

```sh
sh workbench/run-local.sh /path/to/frozen/phase1/results --port 8766 \
  --session /path/to/local/phase3-session.json \
  --directed-source /path/to/frozen/phase1/results/pbmc3k_verified/scagentkit_fixed_seurat.rds \
  --directed-cache /path/to/local/directed-cache --r-library /path/to/existing/R/library
```

## Directed evidence loop

Open **Directed evidence** for cluster 6. The versioned explicit dictionary
classifies all nine clusters, keeping strict and posthoc lanes separate.
An explicit synonym is distinct from a parent/subtype relationship, an
identity/state mismatch, a missing candidate, an unrecognized dictionary
label, a biological abstention, or a transport/format failure.

The typed plan fixes its allowed tools, RNA counts/data layers, reasons and
exact 155-cell scope. **Execute local evidence plan** runs the allowlisted R
extractor once for its content fingerprint. It validates output before
promoting an immutable local cache. It reads existing counts and normalized
data, plus actual QC metadata; it does not normalize, recluster, split, delete,
or infer doublets/NKT/donor identity. A changed source, scope, tool, dictionary
or rule fingerprint prevents silent cache reuse. Changed running Python rule
bytes require a server restart.

The current real fixture has 21/24 available panel genes. TRAC/TRBC1/TRBC2
are unavailable in the current stored RNA matrix; this makes no claim about
the experiment or biological absence. Under the displayed **uncalibrated**
rule (gene count > 0 for at least two measured anchors), 13 cells satisfy only
the T program gate, 39 only the NK program gate, 2 both and 101 neither.
These are program-detection observations, not true T/NK cell proportions.
Available T anchors are 3/6; NK anchors are 4/4. Library QC, per-gene normalized
distributions, candidate-control contrasts and threshold sensitivity remain
visible with their provenance.

The default result is `coarse_only` evidence support for an NK-compatible
RNA program. Identity remains `unresolved_identity`, and the recommended
formal cell-type label is **unknown**. Other exploratory thresholds give
different statuses; the UI discloses this boundary sensitivity. Shared
cytotoxic markers, CD8A alone, consensus, or an author label cannot turn this
into a confirmed NK identity. All-rest comparisons are displayed beside
expression-selected, correlated and unverified candidate lymphocyte
controls; a contrast that disappears or reverses is explicitly disclosed.

This result is derived from measured input, not the cluster ID. Synthetic
sufficient T and NK evidence in the same cluster-6 scope produces distinct
`supported` broad provisional identity recommendations. `supported` still
means an uncalibrated review hypothesis, never an established identity or an
automatic acceptance; insufficient, mixed and coarse evidence retain unknown.

**Prepare unresolved draft** fills unknown plus a directed evidence reference.
It saves nothing until a human enters a reason and records the decision.
A human can correct that draft with a custom label; accepted describes the
review workflow and never biological truth. Existing accepted human records
are never overwritten by execution. The new append-only event retains a
content-addressed proposal capsule, exact scope and all source/tool/rule
fingerprints. Undo adds a compensation; refresh, restart and handoff replay
preserve the original event and capsule. A changed supplemental RNA source
marks only decisions that cite its old capsule stale.

Handoffs without directed references stay v1. Adding a directed reference
upgrades to v2 while preserving all prior event bytes and hashes. This version
can read both formats; the older phase-two server only reads v1. Use separate
session files when keeping both versions running. Handoffs preserve review
capsules and source hashes; the original RDS/frozen inputs must still be
available locally to reproduce extraction from scratch.

## Try the review loop

1. Start with **Cluster 6**. Compare the actual UMAP, marker measurements,
   database overlaps and the four model conditions. The guided DeepSeek CD8
   result conflicts with three NK results; this is a biological question to
   inspect, not a majority-vote truth claim.
2. Select a candidate or **Keep unknown**. Set the decision dimension to cell
   type, cell state, or QC/anomaly. Enter a reason and choose a workflow status.
   **Record decision** saves only a human review event.
3. Open **Decision history**. Revise a label with another reason, or use **Undo
   with reason**. Undo appends a compensation; it keeps the original record.
4. Refresh the browser or restart the server. Decisions and history reload
   from disk. **Export handoff** and **Import handoff** round-trip the same
   event history and scope. Import into an empty session for a separate copy.
5. **Refresh evidence** rehashes the actual source bytes. A changed fingerprint
   marks earlier decisions stale and clears any unsaved draft. It never reuses
   an earlier decision as a current result.

Every event has the dataset revision, cluster ID, dimension and the exact,
sorted cell-ID set. A type decision does not apply to state, QC, another cluster,
or another evidence revision. Proposed, reviewed and accepted describe review
workflow; they are not claims of biological correctness. A deliberate unknown,
an unmade human decision and a failed model request remain distinct.

## Evidence and limits

- The SVG scatter plot contains all 2,638 real retained-cell coordinates. UMAP
  geometry alone does not establish identity.
- Marker tables show **up to 30** filtered genes with actual log2FC, pct.1,
  pct.2, detection difference, adjusted p values and source. Some clusters have
  fewer qualifying markers. A missing gene in this subset is not evidence of
  absent expression.
- Database overlaps are heuristic candidates. Overlap count, reference size,
  ties and label granularity matter; score is not a posterior probability.
- Guided and independent are two evidence conditions for each model. The
  four cached single-call results are not an independently validated ensemble.
  Raw strict interpretation and posthoc cluster-prefix normalization appear
  separately. Model confidence is a model assertion.
- Dictionary/subtype granularity, biological disagreement, format rejection,
  and transport failure are separate issues. Published author labels are
  contextual references, not an absolute gold standard; truth is not loaded.
- Human decisions do not modify or apply labels to the source Seurat object.
  This MVP preserves the review trail for subsequent explicit analysis.

## Local data boundary

The base backend reads only its explicit allowlist of result files. With an
explicit `--directed-source`, its fixed R tool also reads the local frozen RNA
object to produce the scoped evidence summaries. It never reads evaluation
truth or `Documents/API.R`, scans credential files, or sends data to an external
API. No remote fonts, scripts or assets are used.
The browser connects only to the local server. Host/Origin checks, a fixed
asset allowlist, a Content Security Policy and plain-text model rendering
protect the local interface from cross-site requests and HTML injection.

Handoffs contain source SHA-256 references, revision snapshots, exact cell
scopes and human event history. They exclude matrices, truth, database exports
and provider response bodies. V2 also contains the cited proposal's observed
program evidence and immutable provenance. Human-written labels and reasons remain in the
handoff; review them before sharing it yourself.

History uses a hash chain, validated references, idempotent request IDs,
interprocess locking, atomic replacement and filesystem synchronization. The
API only appends; malformed or conflicting imports are refused. Damaged local
history becomes read only and is preserved rather than overwritten. Hashes
detect corruption and inconsistent edits; they are not signatures and do not
authenticate a maliciously rewritten file by its local owner.

No code, data or application deployment is published by running this tool.
The Python HTTP server is for local research use, not internet hosting.

## Verify

Backend tests use Python's standard library. The browser test uses an already
available Playwright installation and Chrome in a fresh temporary profile;
Node/Playwright are QA tools only. It copies the exact evidence allowlist into
an isolated temporary fixture for mutation tests, leaving the frozen run intact.

See [the acceptance matrix and reproduction commands](tests/TEST_PLAN.md).
Screenshots, sessions and copied fixtures belong outside Git. The backend
checks and real-browser suite cover actual input loading, UMAP selection, exact
scope, unknown, required input, repeat activation, durable reload, undo,
handoff identity, stale evidence, damaged history and literal model rendering.

The UI and server are separate from the R package and excluded from R builds.
