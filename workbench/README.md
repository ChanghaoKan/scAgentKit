# Local research workbench

A small, local evidence and review interface for the frozen PBMC3k phase-one
run. It reads real coordinates, marker measurements, reference candidates and
36 cached provider results. It does not compute new annotations or call a model.

## Start

Python 3.9 or newer and a modern browser are sufficient. No package installation,
Node runtime, R session, authentication setup, or external service is required to
use the workbench.

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

The backend reads only its explicit allowlist of result files. It never reads
the count matrix, evaluation truth or `Documents/API.R`, scans credential files,
or sends data to an external API. No remote fonts, scripts or assets are used.
The browser connects only to the local server. Host/Origin checks, a fixed
asset allowlist, a Content Security Policy and plain-text model rendering
protect the local interface from cross-site requests and HTML injection.

Handoffs contain source SHA-256 references, revision snapshots, exact cell
scopes and human event history. They exclude matrices, truth, database exports
and provider response bodies. Human-written labels and reasons remain in the
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
