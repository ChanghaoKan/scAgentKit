# Local ACT reference input

ACT is the default marker reference selected for new projects. Cell Ontology remains the separate CLID dictionary. ACT is an independent integrated source, not a CellMarker download mirror. No ACT database is included in this package.

The official HTTPS download page is https://xteam.xbio.top/ACT/download.jsp. The Mac verification on 2026-10-19 stopped because its certificate had expired. That HTTPS attempt did not verify a file or database license. Subsequently supplied local Human/Mouse tables were inspected and tested; their publisher release version/date and database redistribution license remain unverified. Do not bypass a certificate warning. Use a lawfully held original ACT download or wait for the publisher to restore valid HTTPS.

`annot_import_act()` accepts an original CSV, TSV/TXT (tab separated), or XLSX with an explicit column mapping (and an explicit sheet name/index for XLSX). The adapter never guesses source headers. A faithful UTF-8 TSV/CSV export may instead use exactly these five headers:

```text
species	tissue	cell_type	marker	pmid
```

Each row declares its actual species/tissue, cell type, marker gene symbol and original PMID string. Keep missing PMID values blank rather than inventing a citation. Retain the original source file and supply the column mapping if its headers differ; the importer keeps original field strings and source row numbers. Human/Homo sapiens and mouse/Mus musculus are recognized without cross-species mapping. An actual tissue is required; `all` is never used as a fallback. The native filter is a case-insensitive literal substring: `Blood` also matches `Blood vessel`. If the intended scope is exactly `Blood`, subset the imported tissue values explicitly before project creation.

```r
ref <- annot_import_act("/absolute/path/to/lawfully-held-ACT.tsv",
  species = "human", tissue = "blood",
  source_version = NULL, source_date = NULL)
# For original headers, use columns = c(species="actual species header",
#   tissue="actual tissue header", cell_type="actual cell type header",
#   marker="actual marker header", pmid="actual PMID header").
x <- sc_analyze(input, project_dir, context = context, reference = ref)
```

Use only a known publisher version/date. NULL is recorded as unavailable, not inferred from filesystem timestamps. The SHA256 identifies the local bytes and is not publisher authentication. The database reuse/redistribution license is not established, so do not publish a copy or public mirror from this workflow.

The first model annotation uses only marker/expression aggregates and study context. Saved ACT overlap/coverage and conditional Fisher evidence are compared afterward. Original PMID strings accompany matching candidate markers. At most one separately budgeted guided difference review may follow; it is dependent on ACT and is not independent biological validation. Every complete annotation still requires human approval. If ACT is absent or has zero matching records, the page states that limit and local marker/Unknown rule review remains available.

## Tested local merged-table layout

The supplied Human table had 3,767 rows / 743,295 bytes; Mouse had 2,721 rows /
598,641 bytes. Their headers were `Species`, `Tissue`, `CellType`, `Marker`,
`Resource`, `SourceFile`, `SourceURL`. These observations identify the tested
local layout, not a publisher release. The associated download date is not a
database release date. No raw or derived ACT library is distributed here.

```r
ref <- annot_import_act("/absolute/path/to/ACT_Human_merged.tsv",
  species="human", tissue="Blood", sha256=expected_local_sha256,
  columns=c(species="Species", tissue="Tissue", cell_type="CellType",
            marker="Marker", pmid="Resource"))
ref <- ref[tolower(trimws(ref$tissue)) == "blood", , drop=FALSE]
# Use matching context=list(species="human", tissue="Blood").
```

The five-field adapter preserves original Resource strings and source rows.
`Company` is a source value, not a numeric PMID. SourceFile/SourceURL are extra
columns: retain the merged source and its hash, or explicitly reattach these
columns by `source_row - 1L` in a private local reference. Source URLs and local
hashes do not authenticate the publisher or establish redistribution rights.

Actual installed tests with public `pbmc_small` checked native marker-pool order,
267 conditional Fisher tests and all-label BH correction, exact CL mapping, and
independent annotation before one bounded guided comparison. Counts, literal
cell IDs and original metadata were preserved. The two annotation callbacks
were offline software controls, not biological validation or live model calls.
The files are small enough for a local reference; public bundling awaits an
explicit database redistribution license and verified publisher provenance.
