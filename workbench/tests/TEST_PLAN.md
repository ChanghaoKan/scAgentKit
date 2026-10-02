# Local research workbench acceptance

Run against the frozen Phase 1 results using a new temporary session. The browser
suite opens a new headless Chrome profile and blocks every non-loopback request.
It must not use the user's browser profile, read `Documents/API.R`, call a model,
or upload source data. Screenshots and exported sessions stay outside Git.

## Commands

The application has no JavaScript dependency requirement. Browser QA alone needs
an existing Node runtime, Playwright, and a Chrome installation. On the development
Mac those are already bundled with the app:

```sh
/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node \
  workbench/tests/browser_smoke.mjs \
  --results-root /path/to/frozen/phase1/results
```

Elsewhere use `node` and pass `--playwright /path/to/playwright` and
`--chrome /path/to/chrome` (or the corresponding `PLAYWRIGHT_MODULE_PATH` and
`CHROME_EXECUTABLE` environment variables). The harness starts/stops its own
Python server on an ephemeral `127.0.0.1` port and creates its own event store.
It prints a fresh temporary artifact directory. If passing `--output`, use a new
directory for each run so prior acceptance history is preserved.

## Browser acceptance matrix

| Concern | Required observation |
| --- | --- |
| Genuine data | 2,638 unique UMAP cell IDs, 9 clusters, cluster 6 exactly 155 cells; 36 cached model calls |
| Selection | Cluster list and real UMAP points select the same cluster and cell set |
| Marker evidence | Up to 30 filtered genes with actual pct/logFC and provenance (30 in cluster 6, 17 in cluster 0, 26 in cluster 2); absence does not imply no expression |
| Model evidence | Four conditions per cluster; raw response separate from posthoc normalization; 33 strict-valid / 2 format rejects / 1 transport failure |
| Interpretation | Biological disagreement, granularity/dictionary issues, format rejection, and network failure remain distinct |
| Unknown | Explicit unknown requires a reason; unmade decision and model failure do not become unknown labels |
| Scope | Each write states input revision, cluster, dimension (`type`, `state`, `QC`), and exact cell IDs |
| Human/source boundary | Human labels cannot mutate marker/database/model sources or author/reference labels |
| Review | Proposed/reviewed/accepted are review states, never asserted biological truth |
| Required input | Blank reason, invalid dimension/status/cluster/revision, missing evidence, and malformed JSON reject atomically |
| Durability | Save, browser refresh, server restart, export, and import preserve identical history and derived decisions |
| Repeated activation | A double click creates only one event; duplicate request ID is idempotent, conflicting reuse rejected |
| Undo | A reasoned compensation event is appended; original events stay byte-equivalent and visible |
| Damaged history | Duplicate JSON keys (preserving original file bytes), duplicate IDs, dangling references, changed hashes, corrupt JSON reject or force read-only mode |
| Stale evidence | Actual source byte change changes revision; previous decisions become stale and never silently reapply |
| Handoff | Export/import round trip identical; duplicate import cannot duplicate events; changed input flagged stale |
| XSS | Raw model HTML appears as literal text and cannot execute markup or handlers |
| Local privacy | Server binds loopback; browser makes no remote requests; frontend contains no remote assets |
| Layout | Desktop and narrow view usable with legible evidence, scope, and history; screenshots retained locally |

Backend unit tests handle adversarial journal/hash/reference and byte-change
cases. Browser tests independently verify the visible selection/review/handoff
loop on real frozen data. Assertions do not treat author/reference labels as an
absolute gold standard or claim biology has been validated by a review status.

## Manual demonstration

1. Start the local server with the frozen Phase 1 root and an empty event file.
2. Read cluster 6's 155-cell scope; compare top-30 marker evidence, database
   candidates, and four cached model conditions. Expand raw responses and note
   the independent posthoc column.
3. Choose **Retain unknown**, give a reason for the CD8/NK boundary, and save a
   proposed type decision. Record a state/QC note separately if warranted.
4. Inspect history, revise the type with a reason, then undo with another reason.
   Confirm both the original and the compensation remain visible.
5. Refresh. Export the handoff, import it again, and confirm history is identical.
6. Run a separate temporary fixture with a changed evidence byte. Confirm old
   decisions become stale, with the new fingerprint clearly visible.

Do not mutate the frozen original results for the stale demonstration. Copy only
the exact evidence allowlist to a temporary directory; never copy credentials,
raw matrices, or evaluation truth files into the workbench.
