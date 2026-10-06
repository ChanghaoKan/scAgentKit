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

## Phase 3: directed evidence loop acceptance addendum

Phase 3 runs in its own checkout and uses a fresh isolated localhost server and
session. Leave the Phase 1 sources, Phase 2 checkout, and the user's live session
untouched. The first implementation uses cached calls and locally extracted
expression summaries; there is no model request or outside data transfer.

The following table is a case plan grounded in the existing 36-call cache. It is
not a set of biological gold labels or a claim that all clusters are resolved.

| Cluster | Required distinctions in directed review |
| --- | --- |
| 0 | Naive CD4 T singular/plural and optional `+` spelling can be exact synonyms; spelling differences alone cannot create a biological conflict |
| 1 | CD14/classical monocyte aliases must be distinguished from a general monocyte parent; keep any subtype qualification visible |
| 2 | Two strict format rejects stay failures even when separate posthoc interpretation is usable; the two valid CD4 T plural variants do not conflict |
| 3 | Naive B versus B retains the naive state/finer qualification, not an exact synonym; uncertainty remains visible even if both share B identity |
| 4 | One transport failure remains separate from unknown; CD8 T identity and cytotoxic state remain separate dimensions |
| 5 | CD16/non-classical monocyte variants retain coarse/fine qualifications; one parent match cannot manufacture a subtype consensus |
| 6 | The 155-cell CD8/NK conflict has priority; terminal effector/cytotoxic is state evidence, legacy lexicon `unknown` is not a biological unknown prediction |
| 7 | cDC2 abbreviation/full-name relation is separate from parent DC granularity; legacy dictionary misses must not become biological unknowns |
| 8 | Platelet singular/plural are aliases; megakaryocyte and platelet must not be declared exact synonyms merely because a legacy broad mapping grouped them |

Taxonomy unit cases additionally compare `NK cell` with a qualified CD56 NK
subtype: a coarse/fine relationship is not an exact synonym. A label containing
only a cell state, such as `cytotoxic`, must not be accepted as a lineage identity.
Every interpretation names its taxonomy/rule revision and retains the raw source
label and any posthoc result separately.

| Concern | Required acceptance observation |
| --- | --- |
| Triage coverage | All 9 clusters have an explicit explanation; identity conflict, granularity, state, dictionary failure, and model failure stay distinguishable |
| Expression provenance | The real local extraction identifies the assay/layer, source content hashes, dataset revision, requested genes, and exact cell IDs; c6 has exactly 155 cells |
| Missing versus zero | An unavailable gene is marked unavailable with no fabricated zero statistic; an available gene with zero detected cells remains a measured zero |
| Mixed coexpression | Joint per-cell detection/coexpression counts are shown separately from aggregate marker percentages; shared cytotoxic genes alone cannot prove CD8 or NK identity |
| Low depth | A low-depth or weak-coverage warning is distinct from zero expression and from QC acceptance; a provisional threshold never claims biological validation |
| Existing human decision | Accepted human decisions remain unchanged when a plan, proposal, extraction, or replay is generated; a proposal is not an automatic decision |
| Proposal adoption | Adoption visibly names the proposal and exact cluster/dimension/revision/cell scope, requires a human reason, and appends a new review event |
| Undo and replay | Undo appends a compensation event; exporting/importing/replaying restores identical history and derived human decisions |
| Changed evidence | Real source bytes and expression/taxonomy evidence fingerprints determine revisions; changed input makes old proposals/decisions stale and cannot silently transfer drafts |
| No new evidence | Repeated directed review with the same evidence cannot claim a new independent result; it reuses the cached plan or explicitly stops |
| Bounded loop | A configured round limit, budget cap, or absence of new evidence stops iteration with an explicit reason; no API key or request is needed for cached replay |
| Rendering and locality | Proposed labels/reasons/raw model content render as text; all browser assets and evidence requests stay on localhost |

Scientific negative controls must be demonstrated by independent synthetic
cases in the domain/extraction test reports and, where visible, by the browser:

- Shared NKG7/GNLY/PRF1/CD8A alone leaves identity unresolved. Joint expression
  cannot by itself infer NKT cells, doublets, or another mixed identity.
- Two T/NK subgroups and a broadly consistent group with the same aggregate
  means remain distinguishable through cell-level distributions/coexpression.
- Missing TRAC, measured zero TRAC, and an unavailable/null measurement are
  represented differently. Low-depth cells and extreme values cannot justify a
  false claim of absent expression.
- With measured evidence fixed, changing a truth/reference label or the model
  consensus cannot change the rule's evidence-based conclusion.
- A contrast against all remaining cells and a contrast against relevant
  lymphocyte candidates are separate controls. If an apparent effect disappears
  under the relevant control, the proposal discloses this explicitly.
- Coverage and sensitivity near provisional thresholds are visible. A rule
  result has its own provisional status and label granularity and never forces
  an NK conclusion merely to close the review loop.

If an LLM adapter is absent, browser QA verifies cached replay and no network
requests and records the adapter as out of scope. It must not invent an API round
or claim that a model was run. Budget/round-limit adapter cases only run if an
adapter is implemented and can be tested with a local deterministic fake.

Run the directed browser suite independently of the Phase 2 smoke suite:

```sh
/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node \
  workbench/tests/browser_directed.mjs \
  --results-root /path/to/frozen/phase1/results \
  --directed-source /path/to/retained-seurat.rds \
  --r-library /path/to/local/R/library \
  --output /tmp/fresh-directed-qa-directory
```

The harness copies the RDS into that fresh output directory before performing
the source-byte stale check. Its ephemeral server binds `127.0.0.1`, owns a new
journal/cache, and is stopped together with the isolated Chrome profile. The
directory contains the report, five screenshots, actual browser handoff download,
and private test fixtures; do not commit it or publish its contents.

The final independent Chrome 154.0.8037.93 run passed **9/9 directed cases**.
It loaded all nine clusters and the real 155-cell cluster 6 RNA evidence, preserved
an existing accepted human unknown, prepared an unknown draft with the proposal
capsule, and required an explicit reason and Record decision. Replaying identical
evidence reused the cache. A changed source byte invalidated the cached expression
and marked the referenced accepted record stale while preserving its label and
raw history. Restoring the bytes restored the verified capsule. Undo appended a
compensation; the actual UI download/import and a JavaScript JSON API round trip
preserved identical history. The directed panel fit a 390-pixel viewport with no
document overflow, page errors, or remote requests. Model review was disabled:
zero provider calls and zero incremental cost.

The real panel has three unavailable T anchors (`TRAC`, `TRBC1`, `TRBC2`), with
null statistics displayed as missing rather than fabricated zero percentages.
Every measured gene in this real panel has at least one detected cell. Consequently
the missing-versus-measured-zero negative case belongs to the synthetic domain
and extractor suites; the browser report explicitly records that no real
measured-zero gene was observed. Provisional program support retains the formal
cell-type label `unknown`; it does not establish NK, T, NKT, or doublet identity.

Private final artifacts on the development Mac:
`/tmp/scagentkit-directed-browser-qa-final/directed-browser-report.json` and the
`01`–`05` PNG screenshots in that directory. Core evidence fingerprint:
`d6e18dc8f98b570478e0e2a193d4df693fff00d36176df76a239364063b1c3e2`.
