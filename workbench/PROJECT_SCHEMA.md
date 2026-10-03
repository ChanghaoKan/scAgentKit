# Generic local project protocol v1

This is the implementation contract for the generic round trip. Legacy PBMC
loaders and handoffs remain separate; they cannot acquire a source identity by
being attached to a new project. All files stay local.

## Three identities

- `projectId`: an explicit nonempty user supplied string, never a path.
- `sourceFingerprint`: R computes `scagentkit.source.v1` over the complete
  `colnames(object)` cell universe, sorted exact gene/cell IDs, explicit assay
  and counts/normalized layer names, their actual values, cluster column and
  exact sorted cell-to-cluster membership. Irrelevant metadata and row/column
  order do not enter this identity. Canonical sparse CSC/drop-zero form is
  used; no dense expansion of the full assay. No barcode normalization.
- `bundleDigest`: SHA256 of the actual UTF-8 `project.json` bytes. The project
  lists hashes of every dependent asset, so snapshot/parameters/assets enter
  this digest without being confused with expression identity.

R export and R validation share `.sc_project_identity(object, assay,
counts_layer, normalized_layer, cluster_column)`, returning at least
`fingerprint`, `algorithm`, `assay`, `countsLayer`, `normalizedLayer`,
`clusterColumn`, `cellCount`, `featureCount`, `cellsHash`, `featuresHash`,
`membershipHash`, `countsHash`, and `dataHash`. All digests are lowercase SHA256.
Normalized layer may explicitly be NULL. Genuine counts must exist and contain
finite nonnegative integers. Missing/ambiguous/split layers and a selected
assay missing any object cell are rejected with helpful explicit remediation.

## Portable evidence project directory / zip

`manifest.json`:

```json
{"schema":"scagentkit.project-bundle.v1","projectId":"study-A",
 "sourceFingerprint":"sha256","bundleDigest":"sha256",
 "files":[{"path":"project.json","bytes":123,"sha256":"sha256"}]}
```

`project.json`:

```json
{"schema":"scagentkit.project.v1","projectId":"study-A","displayName":"Study A",
 "identity":{"algorithm":"scagentkit.source.v1","fingerprint":"sha256"},
 "cells":[{"cellId":"001","clusterId":"T alpha","qc":{}}],
 "clusters":[{"id":"T alpha","cellIds":["001"]}],
 "embedding":{"name":"umap","points":[{"cellId":"001","x":0,"y":1}]},
 "markers":[],"candidates":[],"models":[],
 "parameters":{},"provenance":{},
 "directed":{"panel":"T_NK.v1","clusters":{}}
}
```

Embedding may explicitly be NULL; the UI displays unavailable. Lists remain
JSON arrays for lengths 0/1. `cells` and cluster scope must agree exactly;
IDs are literal unique strings. The string `NA` is valid; actual missing
membership is rejected. Models/candidates/markers are optional empty arrays,
not fabricated successful calls. Export metadata uses an allowlist. Optional
`sourceAnnotation` stores an explicitly requested original annotation field
as source context, never a human accepted decision or a gold standard.

Optional supplied markers use UI columns `clusterId`, `gene`, `avgLog2FC`,
`pct1`, `pct2`, `pAdj`, `source`; candidates use `clusterId`, `label`, `score`,
`overlap`, `referenceSize`, `markers`, `source`; model records use `clusterId`,
`callId`, `provider`, `mode`, `strictStatus`, `strict`, `posthoc`, `rawText`,
`source`. Absent model results are `not_run`. No URL is downloaded automatically.

Explicit `directed_clusters` controls which clusters get the T/NK RNA panel.
No other lineage gets this program rule by inference or by numeric cluster ID.
For each selected cluster the exporter writes a targeted RNA evidence asset
and records `{path,sha256}` in `directed.clusters[clusterId]`; manifest includes
the file. Without an asset the directed tools are unavailable, with a reason.
Assets use `scAgentKit.directed_expression.v2`, arbitrary exact scopes and
`source.object_fingerprint`; all RNA counts/data and missing/available/QC
records preserve actual measurements. The generic adapter may reuse the
scientific measurement/conclusion functions after explicitly recognizing this
schema, assay/layer provenance and scope. It must not invent a Seurat RDS hash.

No full matrix or RDS is required in the portable evidence project. Project
assets carry only requested evidence. R writeback requires the original
matching object and this verified project directory.

## Lightweight review journal

```json
{"schema":"scagentkit.review-journal.v1","projectId":"study-A",
 "sourceFingerprint":"sha256","bundleDigest":"sha256",
 "events":[],"artifacts":{}}
```

Events are envelopes `{sequence,payload,prevHash,hash}`. `payload` is the
original canonical UTF-8 JSON string, not reserialized for verification.
`hash = SHA256(UTF8(prevHash + "\n" + payload))`; first prevHash is 64 zeros.
Payload retains the current UI event shape: unique id/sequence/kind/createdAt,
requestId/requestDigest, reason, `scope={datasetId,revision,sourceFingerprint,
clusterId,dimension,cellIds}`, plus label/status/supersedes for decisions or
targetEventId for undo. datasetId is projectId; revision is bundleDigest.
Workflow statuses are proposed/reviewed/accepted, dimensions type/state/QC.
Optional `evidenceRefs` refer to immutable artifacts with raw JSON string
payloads, whose SHA256 verifies without cross-language floating-point changes.

Every event scope must match the verified current project. Import may initialize
an empty store or preserve the exact existing envelope prefix and append.
It never truncates or rewrites history/artifacts. Idempotent request IDs,
interprocess locks, atomic writes and size limits are retained. Unknown versions,
duplicate keys/IDs, inconsistent scopes or hashes fail closed. Old PBMC v1/v2
journals lack generic source identity and cannot be used for generic writeback.

## R APIs and writeback

`sc_project_export(object, path, project_id, assay="RNA", counts_layer="counts",
normalized_layer="data", cluster_column="seurat_clusters", reduction="umap",
marker_table=NULL, candidate_table=NULL, model_records=NULL,
source_annotation=NULL, directed_clusters=NULL)` writes a new directory.
It refuses overwrite; processed objects export directly. `reduction=NULL`
explicitly permits no embedding. `normalized_layer=NULL` explicitly permits
counts-only evidence when membership already exists; directed normalization
dependent evidence remains unavailable. `sc_project_prepare` explicitly
performs standard analysis on a copy, records parameters, and removes no cells
by an implicit QC rule. Matrix inputs must be checked before Seurat can rename
duplicate features. AgentSeurat wrapping exactly one Seurat is supported.

`sc_review_validate(object, journal, project, columns=c(type="review_type"))`
returns `valid`, structured errors/warnings, exact ID mapping and coverage.
`sc_review_apply` takes the same arguments, validates again, and returns a
modified copy. Default cell sets are exact, rejecting missing/extra/duplicate
IDs, changed values, features or membership. Different object cell/gene order
and equivalent sparse representations are supported. All new requested label
and companion column names must be absent before any mutation.

Replay picks the latest active decision in each exact dimension/cluster scope:
accepted ordinary labels -> labeled; accepted unknown -> abstained; a current
proposed/reviewed event -> deferred; no current event -> unreviewed. Only accepted
events write labels. Others leave label NA. Companions record review state,
workflow status, decision ID and source/bundle provenance. Undo restores the
correct previous state. Original annotations, factor levels/NA, Idents,
assays/reductions and unrelated metadata remain unchanged. SaveRDS is a separate
explicit operation to a new path, never a side effect of apply.

## Local security / compatibility

ZIP import rejects traversal, absolute/drive paths, duplicate members, symlinks,
unlisted files, unknown schemas, bad checksums and bounded-size/ratio violations.
No full RDS deserialization from the GUI. Host/Origin/CSP/plain-text rendering
remain. Moving an exported directory/zip to another local folder is supported;
no task-2 path occurs in the generic schema. The legacy adapter and stable old
servers remain independent; it is never relabeled as a generic project.
