# Direct 10x MEX input

For researchers reducing workflow maintenance, the existing `sc_start()` and
`sc_analyze()` entries accept 10x Matrix Exchange directories. The same strategy,
QC, annotation proposal, complete-plan approval and result interfaces apply.
This adapter reads counts and declared study facts; it does not align FASTQ,
call empty droplets, correct ambient RNA, detect doublets or infer study design.
Research-specific advanced analyses remain downstream of the reviewed object.

## One directory

```r
library(scAgentKit)
service <- sc_start("filtered_feature_bc_matrix", "analysis-project",
  sample_id="S1", matrix_kind="filtered",
  context=list(species="human", tissue="Peripheral blood",
    research_goal="Review major populations and retain unresolved identities."))
```

Declare `matrix_kind="raw"` for raw matrices. No directory-name inference is
used. All supplied barcodes are imported, including raw empty/zero-count
barcodes. A `filtered` declaration records what you supplied; it does not verify
upstream cell calling. Measured QC and removal require the existing scientific
review. Reopen with the same source inputs, options and project, omitting context
to use saved facts. A changed import requires a new project. After original
sources are moved, `sc_open()` / `sc_result()` still read the protected project;
reopening via `sc_start()` requires the original source binding.

## Multiple samples in one table

A table combines source paths and study metadata; no separate manifest is needed:

```r
samples <- data.frame(
  sample_id=c("S1", "S2"),
  path=c("counts/control", "counts/treated"),
  matrix_kind=c("filtered", "filtered"),
  donor=c("D1", "D2"), condition=c("control", "treated"))
service <- sc_start(samples, "analysis-project",
  context=list(species="human", tissue="Actual tissue",
    research_goal="Actual study question"))
```

`input` may instead be the path to a quoted CSV or tab-delimited TSV with these
columns. Relative paths resolve from the table's directory (data.frame paths
resolve from R's working directory). Required columns are `sample_id`, `path`,
`matrix_kind`; optional roles are `donor`, `condition`, `batch`, `capture`,
`treatment`, `qc_group`, `group`. Supplied role columns are declared directly;
absent roles/design are not inferred. `sample_id` is not automatically a donor,
capture or technical batch. No batch correction is enabled by importing a table.
IDs must be unique letters/digits/dots/hyphens, beginning with a letter/digit.
Each source directory can occur only once. Source files are never rewritten.

Cell IDs become **`sample_id::barcode`** for both single and multiple samples.
The original barcode is retained as `tenx_barcode`, the explicit sample as
`sample_id`, and input class as `tenx_matrix_kind`. Repeated 10x barcodes across
different samples remain distinct. Reserved separators and duplicate barcodes
within one sample are rejected.

## Exact cell metadata

Optional `cell_metadata` is a data.frame/CSV/TSV with explicit `sample_id` and
`barcode` keys plus additional fields. It must cover every imported barcode
exactly once, including all raw barcodes. Shuffled rows are reordered by these
keys, never by position; missing/extra/duplicate keys fail with a repair message.
A field cannot appear in both sample-level and cell-level tables. Keep it in one
place, and declare any additional role explicitly in `context$columns`.

```r
cells <- data.frame(sample_id=c("S2", "S1"),
  barcode=c("EXACT-BARCODE-2", "EXACT-BARCODE-1"),
  preparation=c("P2", "P1")) # illustrative only: supply every actual cell
# sc_start(samples, "analysis-project", cell_metadata=cells, context=...)
```

## Features, sparse counts and supported files

Each directory must have exactly one plain or gzip `matrix.mtx`,
`features.tsv` (three columns) or legacy `genes.tsv` (two columns), and
`barcodes.tsv`. Files must form a matching MEX set. Matrix entries must be finite,
nonnegative integers before duplicate-coordinate aggregation. Counts stay sparse.
Only exact `Gene Expression` rows are selected from a multimodal feature table;
other modalities and excluded row counts are recorded. Two-column legacy gene
tables are explicitly treated as gene-expression input.

Default `feature_key="name"` retains compatible unique names as analysis keys.
Names containing separators Seurat cannot retain (`_` or `|`) receive neutral
`feature-<ID hash>` analysis keys, without creating biological aliases. Every
member of an original duplicate-name group receives a deterministic suffix from
its original feature ID. No member is privileged and no gene rows/counts merge.
The review summary lists the count and exact mapping of these changes. Feature ID, name and type remain in RNA assay metadata as
`sc_feature_id`, `sc_feature_name`, `sc_feature_type`. `sc_analysis_key` records the actual row key; all original names remain literal.
Ambiguous changed keys are not automatically matched back to symbols. You may explicitly choose `feature_key="id"` when IDs
are unique and compatible (incompatible ID keys fail), but symbol-based mitochondrial/cycle/reference
matches may then be unavailable. Missing mitochondrial matches are reported as
unavailable/NA, not measured zero. There is no inferred ID-to-symbol mapping.

Across samples, the Gene Expression feature **ID sets must match exactly** and
ID/name/type annotations must agree. Row order may differ and is aligned by ID.
No union, intersection or gene dropping is performed to force compatibility.
Resolve incompatible references explicitly outside this adapter and preserve
your mapping/provenance before creating a new project.

## What is saved and shown

The protected input Seurat checkpoint contains an import receipt with sample
paths, source class, per-sample barcode counts, literal prefix policy, selected
feature policy, excluded modalities, source-file SHA256s and metadata alignment.
File tables include their byte hashes; data.frame inputs are captured as parsed
sample facts and aligned metadata hashes. The local review page shows these
facts before approval. They do not enter independent model evidence summaries.

`sc_start()` transports the validated object through a temporary local RDS to
the existing launcher and removes that transport file afterward. Reopening checks
the protected receipt and generated input checksum; only this transport path may
change. Ordinary RDS inputs keep their existing exact path/checksum binding.
Changing table row order can change the original receipt even if the joined
facts would be equivalent: reuse the exact original inputs/options to reopen.
Checksums detect changes; they do not prove an upstream experiment is correct.

The result remains the existing `sc_result("analysis-project")` Seurat object,
with counts, exact sample metadata, reductions and reviewed annotation fields.
The project also retains marker tables, figures and decision/evidence records.
No trajectory, communication or regulatory-network workflow starts by default.
