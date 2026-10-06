# Review local CellMarker and AI annotation evidence together

Start with `sc_run()` and a supplied local reference. The coordinator saves the
actual marker evidence, local database candidates, current typed proposal and
optional historical model response as distinct evidence sources. Review the
whole annotation proposal once, then Continue approved local computation. You do
not need to confirm each cluster separately or move an RDS/ZIP to the browser.
Database overlap and agreement between suggestions do not establish biological
identity.

The optional helper [cm2-evidence-review.R](../inst/examples/cm2-evidence-review.R)
uses the same R interfaces. Its CLI uses synthetic data only, no provider and a
zero budget. Installing this checkout and selecting its R library is required.
The validation below belongs to the historical CellMarker-evidence increment,
not a fresh release-candidate check. See the
[release checklist](RELEASE_CANDIDATE_CHECKLIST.md) for current-source results.

Mac validation completed: `R CMD check --no-manual --ignore-vignettes` reported
`Status: OK`, with 2569 passing checks and no failures, warnings or skipped tests;
seven unavailable optional Suggests were reported as INFO. The full suite includes
107 focused core and 28 integration assertions. The unchanged Python production
hash retains the earlier 220 passing tests with zero skips; 33 offline UI checks
also passed.

Actual Chrome and R validation passed five cases on the existing public PBMC
processed object: 2638 cells and nine clusters. Its base analysis was reused
without rerunning it, and markers were computed once. Nine historical DeepSeek
independent response JSON files were imported readonly; no new model request was
made. The current whole proposal retained `Unknown` in fresh output columns:
this validates software behavior, not cell identities. Changing database top-N
from five to three invalidated the old approval, which was actually rejected.
Whole-plan decisions, hallucinated-gene rejection, CSRF protection, local Continue,
fresh-R/server-restart byte-identical no-ops and 45 unchanged source-file hashes
were verified. New API calls and cost were zero. The report is
`evidence/cm2-evidence-browser/public-pbmc-browser/joint-evidence-browser-report.json`
(`passed=true`); final Seurat SHA256 is
`88456cd527a6744d9e2fddbd5141482925dd9bf286f2485e90ec78606af0cfd2`.

The first check failure is retained: a legacy test expected the database-mode
field to say `independent`. The test was corrected to distinguish
`local_marker_reference` from AI prompt mode and gained two assertions. No new
Linux/HPC or Windows validation is claimed for this increment.

## Existing processed study: one starting call

Set nonsecret paths to your already processed Seurat RDS, a durable **new** project
directory and an approved local marker-reference CSV. The paths below are read
only when you run the example. They do not download a database or contact a
provider. For raw counts, use the same reference arguments with
`start_stage="qc"` and the [first-run QC flow](FIRST_RUN.md).

```r
library(scAgentKit)
source(system.file("examples", "cm2-evidence-review.R", package = "scAgentKit"))

input_path <- Sys.getenv("SC_PROCESSED_RDS")
project_dir <- Sys.getenv("SC_PROJECT_DIR")
reference_path <- Sys.getenv("SC_LOCAL_REFERENCE_CSV")
stopifnot(nzchar(input_path), file.exists(input_path), nzchar(project_dir),
          nzchar(reference_path), file.exists(reference_path))

# These must describe the actual study and metadata columns in its source object.
context <- list(species = "human", tissue = "Peripheral blood",
  columns = list(sample = "sample_id", capture = "capture_id", condition = "condition"),
  notes = "Describe the actual study, assay, treatment and relevant limitations here.")
reference <- annot_load_reference(reference_path)
options <- list(ai_mode = "independent", top_n = 5L,
  symbol_aliases = setNames(character(), character()),
  label_map = setNames(character(), character()),
  label_relations = data.frame(child = character(), parent = character(),
    lineage = character(), stringsAsFactors = FALSE))
# For the exact pinned CM2 subset, add the provenance declarations described
# below before starting. Other inputs need their own verified declarations.

run <- cm2_evidence_start(input_path, project_dir, context = context,
  reference = reference, reference_review = options, annotation_history = NULL,
  start_stage = "processed", cluster_column = "seurat_clusters",
  processed_reason = "Explain the verified previous normalization, reductions and cluster provenance; reuse that existing analysis.",
  annotation_column = "cm2_reviewed_identity", provider = NULL, budget = 0)
view <- cm2_evidence_inspect(project_dir)
```

Replace the context, layer/cluster names and provenance with verified values.
Omit undeclared metadata roles instead of inventing columns. A capture is not
automatically a donor, and a biological condition is not automatically a batch.
Processed entry reuses base analysis and computes marker evidence for the chosen
current cluster membership. Choose a fresh annotation column; prior labels stay
in their existing columns.

Without a provider or manual proposal the run returns
`awaiting_configuration` at `annotation_propose`. Create an explicit unresolved
proposal from its saved actual clusters, review it, and continue:

```r
sc_run_propose(project_dir, cm2_evidence_unknown(view), reviewer = "your analyst ID",
  reason = "Initial manual Unknown proposal for evidence review; no model call.")
view <- cm2_evidence_inspect(project_dir)
view$annotation_review$details$annotations[[1]]$joint_evidence

# Optional: revise the complete typed proposal after inspecting all clusters.
replacement <- view$annotation_review$details$canonical_proposal
# Edit selected label/confidence/rationale/markers entries with justified values.
# A specific label must cite this cluster's supplied marker evidence.
cm2_evidence_decide(project_dir, view, "revise", reviewer = "your analyst ID",
  reason = "Explain the complete replacement and retained uncertainty.", proposal = replacement)
view <- cm2_evidence_inspect(project_dir)  # new hashes/revision after any change

approved <- cm2_evidence_decide(project_dir, view, "approve",
  reviewer = "your analyst ID", reason = "Accept this exact whole proposal and its limitations.")
run <- cm2_evidence_continue(project_dir, approved)
stopifnot(run$status == "complete")
final <- readRDS(run$output$seurat)
```

Keep `Unknown` or a justified coarser label when evidence is insufficient. Reject
with `action="reject"` if the displayed proposal should not be applied. Approval
saves a decision; Continue is the separate local computation action. Both use
the exact inspected project/input/revision, and review additionally binds the
proposal and evidence hashes. A changed reference or revised proposal requires a
new inspection and approval. Saved helper snapshots are conveniences, not the
authoritative state.

## Reference scope, symbols and label relationships

A local reference needs `cell_type` and `marker`; meaningful scoped matching also
needs `species` and `tissue` columns and corresponding context. Human and mouse
references can be supplied explicitly for their matching species. This example
does not fetch a mouse export or claim the pinned human-blood subset supports
mouse, other tissues or arbitrary organisms.

Species and tissue matching is trimmed, case-insensitive **exact** matching.
Reference tissue `all` is an explicit broad declaration. `Blood` does not silently
include `Peripheral blood` or `Venous blood`. Missing scope, a scope mismatch,
empty reference and no overlap remain visible. Select the actual tissue in
context; do not relabel reference tissues solely to manufacture agreement.

`symbol_aliases` is a caller-supplied named character vector from observed symbol
to canonical symbol. It resolves only those explicit aliases and deduplicates
canonical reference genes for scoring. There is no automatic HGNC lookup or
protein-alias substitution. `label_map` supplies explicit naming equivalences.
`label_relations` supplies `child`, `parent`, and optional `lineage` columns to
distinguish declared granularity or lineage relationships. These declarations
are study inputs, not automatic Cell Ontology reasoning. Empty maps are valid;
unsupported relationships remain unresolved. Cyclic or contradictory declarations
are rejected.

The displayed score is `unique marker hits / unique reference genes`, a
reference-marker coverage quantity. It is not a calibrated probability or
annotation accuracy. Candidate ties, supplied marker statistics, matching and
missing cited genes and source provenance support review. A gene missing from
top-marker evidence does **not** prove absent expression or provide negative
biological evidence. Low/medium/high confidence is qualitative.

`ai_mode="independent"` excludes database candidates from the current model's
aggregate evidence branch. This separates prompt inputs; it does not make the
model an independent biological validation. `ai_mode="guided"` includes local
database candidates in the model input, so agreement depends on that database.
A manual proposal remains manual in either mode. Continue never requests a
model; a new provider request requires explicit R resume and the existing exact
aggregate-transfer approval and budget gates. See [FIRST_RUN.md](FIRST_RUN.md)
for environment-based provider configuration. No paid call is needed here.

## Optional historical model evidence

History defaults to `NULL`. If you already have authorized local model responses,
extract their rows yourself, preserving the response's literal cluster IDs,
labels, qualitative confidence, rationale and cited markers. Keep unavailable or
invalid responses unavailable. The importer does not generate or repair a model
answer and does not turn history into an automatically accepted current proposal.

```r
# historical_rows is your explicitly reviewed, caller-extracted list of rows:
# list(clusterId="literal ID", label="...", confidence="low|medium|high",
#      rationale="...", markers=list("actual cited symbol", ...))
# response_paths names their readonly local JSON files, not URLs or credentials.
historical_source_path <- Sys.getenv("SC_HISTORY_SOURCE_RDS")
stopifnot(nzchar(historical_source_path), file.exists(historical_source_path))
history <- cm2_evidence_history(annotations = historical_rows,
  response_paths = response_paths, source_object_path = historical_source_path,
  source_cluster_column = "seurat_clusters", provider = recorded_provider,
  model = recorded_model, reference_dependency = recorded_reference_dependency,
  note = "Record extraction decisions, original response dates and any omissions; no new model request.")
# Supply annotation_history=history to the starting call above, or update the
# still-unapplied annotation evidence as shown below.
```

The source RDS must be the actual historical source object. The coordinator
hashes the local JSON files and source object and compares exact cell IDs and
cell-to-cluster membership against current evidence. File hashes establish
source bytes; they do not prove your extraction or the model's biology is correct.
Record `reference_dependency` as `independent`, `guided` or `unknown` from the
actual original prompt; do not assume that the current mode describes history.
Missing historical clusters, citations absent from current supplied markers,
unverified/mismatched scope and database dependency are disclosed. Only verified
scope is eligible for historical comparison, and history is marked
`new_request=FALSE`.

The located public PBMC history is a **2638-cell, 9-cluster** run from 2026-10-02.
Its DeepSeek/Grok guided and independent files include 33 `http_success`, one
request failure and two invalid-schema responses. It cannot be applied by cluster
number to the later **2527-cell, 6-cluster** project. These are historical responses,
not new calls in this increment; neither HTTP success nor a model label establishes
validated cell identity.

## Replace a reference before annotation writeback

Use the public operation instead of editing saved RDS/config/journal files:

```r
view <- cm2_evidence_inspect(project_dir)
updated_reference <- annot_load_reference(updated_reference_path)
sc_run_set_reference(project_dir, reference = updated_reference,
  project_id = view$project_id, input_hash = view$input_hash,
  expected_revision = view$revision, reviewer = "your analyst ID",
  reason = "Explain the new local reference, scope or mapping and its provenance.",
  reference_review = updated_options)
# Supply annotation_history=history explicitly if replacing historical evidence.
view <- cm2_evidence_inspect(project_dir)
# If configuration needs a proposal, supply a typed one with sc_run_propose().
# Otherwise review/revise the republished proposal. Approve its whole fresh
# snapshot and Continue, as above.
```

The operation accepts `annotation_propose` or `annotation_apply` only, before an
`annotation_apply` checkpoint has completed; a running or completed project is
not eligible. It retains completed analysis/markers, records the update reason
and revokes the previous annotation approval. With an existing manual proposal
it republishes a fresh review locally; otherwise it returns
`awaiting_configuration` for a typed proposal. It returns status, not an approval.
Omitting `annotation_history` retains history; explicit `annotation_history=NULL`
removes it. `reference_review=NULL` retains the previous options. The operation
does not submit a model request or accept the replacement proposal. If annotation
was already written, use the
[executed annotation undo flow](ANNOTATION_REVIEW.md) to reopen review; do not
overwrite its state or apply a stale decision.

The [loopback workbench](../workbench/RUN_REVIEW_QUICKSTART.md) displays the same
per-cluster evidence and approves the whole saved annotation proposal. Reference
replacement and historical import remain explicit R operations. The optional
browser Continue runs approved local computation asynchronously and stops at a
missing manual/provider proposal; no browser API key or model request is involved.

## Pinned CM2 provenance and licensing

The existing local human export is pinned as CellMarker 2.0, not silently replaced
by a live newer database. Its official provenance identifies
[CellMarker 2.0](https://bio-bigdata.hrbmu.edu.cn/CellMarker2.0/index.html), the
[download page](https://bio-bigdata.hrbmu.edu.cn/CellMarker2.0/CellMarker_download.html)
and [Hu et al., DOI 10.1093/nar/gkac947](https://academic.oup.com/nar/article/51/D1/D870/6775381).
The retained HTTP source was the paper's `117.50.127.228/CellMarker` entry point.
These links identify the source; they do not prove current live download bytes
equal the pinned local file.

The local files and sidecars, retained outside the repository for authorized
analysis, are:

| Local artifact | SHA256 |
| --- | --- |
| `Cell_marker_Human.xlsx` | `bf52b8cd60df60f17a7c6b8a59d0bbb74ec78612f11cd11990f15e4eedb7d842` |
| `cellmarker2_human_normal_blood.csv` | `c1428d56ca52ad1c8e28207d93c4e50004d466e780fd717a032372d483b225a2` |
| `cellmarker2_human_normal_blood_manifest.json` | `c3a517036c5d50b0054a4fd342481ce5081be188d23a41128dc6f1044df7b93a` |

The manifest records 2026-10-02T21:29:07Z retrieval, 2022-09-28 HTTP Last-Modified,
source/output hashes, exact subset rules and source-row provenance. The 3816-row
CSV covers human `Blood`, `Peripheral blood` and `Venous blood` records selected
by `Normal` database categories. `Normal` is not evidence of a healthy donor.
The gene column is the supplied **Symbol**; missing symbols are excluded rather
than replaced with protein aliases from the XLSX `marker` column. No independent
HGNC alias verification or cell-level ground truth is implied.

For this pinned input, add provenance **before the starting call**, rather than
guessing it from the CSV filename. For an eligible existing project, pass the
updated options through `sc_run_set_reference()` and inspect its new snapshot:

```r
# These declarations apply only to the exact pinned input described above.
options$provenance <- list(version = "CellMarker 2.0", license = "unknown",
  source_url = "http://117.50.127.228/CellMarker/CellMarker_download_files/file/Cell_marker_Human.xlsx",
  retrieved_at = "2026-10-02T21:29:07Z",
  original_sha256 = "bf52b8cd60df60f17a7c6b8a59d0bbb74ec78612f11cd11990f15e4eedb7d842",
  source_sha256 = "c1428d56ca52ad1c8e28207d93c4e50004d466e780fd717a032372d483b225a2",
  preparation_note = "Human Normal blood subset; marker genes come from Symbol, missing Symbol excluded; see the retained preparation manifest.")
stopifnot(identical(digest::digest(file = reference_path, algo = "sha256"),
                    options$provenance$source_sha256))
attr(reference, "marker_column") <- "Symbol (original XLSX); marker (prepared CSV)"
```

The paper is CC BY 4.0. An explicit reuse/redistribution license for the separately
hosted database export was not established from the official pages or paper;
public download access is not treated as a database redistribution license. The
reference stays local and is not bundled into this repository or published as a
database dump. This local coverage matcher is not the CellMarker ACT algorithm,
and ACT, automatic ontology mapping, automatic symbol correction and biological
accuracy validation are outside this increment.

## Synthetic CLI: separate R processes, no API

With this package installed, copy its example path and choose a new temporary
project directory:

```sh
example=$(Rscript --vanilla -e 'cat(system.file("examples", "cm2-evidence-review.R", package="scAgentKit"))')
project=$(mktemp -d "${TMPDIR:-/tmp}/scagentkit-cm2-demo.XXXXXX")
Rscript --vanilla "$example" "$project" demo
Rscript --vanilla "$example" "$project" inspect
# Optional synthetic rationale revision; inspect again if used.
Rscript --vanilla "$example" "$project" revise
Rscript --vanilla "$example" "$project" inspect
Rscript --vanilla "$example" "$project" approve
Rscript --vanilla "$example" "$project" inspect
Rscript --vanilla "$example" "$project" continue
Rscript --vanilla "$example" "$project" output
```

The CLI's planted toy programs and toy reference demonstrate the mechanism; they
are not PBMC, CellMarker records or recommended biological labels. Its proposal
retains `Unknown`. `refresh-reference` is an optional **before-writeback** toy
reference-setting change: inspect, update, inspect the new snapshot, and approve
again before Continue. Repeated completed Continue uses a fresh inspection and
does not authorize an extra model request.
