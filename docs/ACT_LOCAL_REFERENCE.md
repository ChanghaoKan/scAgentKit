# Local ACT reference input

ACT is the default marker reference selected for new projects. Cell Ontology remains the separate CLID dictionary. ACT is an independent integrated source, not a CellMarker download mirror. No ACT database is included in this package.

The official HTTPS download page is https://xteam.xbio.top/ACT/download.jsp. The Mac verification on 2026-10-19 stopped because its certificate had expired. No official data file, actual header/schema, release version/date or database redistribution license was verified. Do not bypass a certificate warning. Use a lawfully held original ACT download or wait for the publisher to restore valid HTTPS.

`annot_import_act()` accepts an original CSV, TSV/TXT (tab separated), or XLSX with an explicit column mapping (and an explicit sheet name/index for XLSX). Since the official file has not been inspected, no guessed official column names are built into the adapter. A faithful UTF-8 TSV/CSV export may instead use exactly these five headers:

```text
species	tissue	cell_type	marker	pmid
```

Each row declares its actual species/tissue, cell type, marker gene symbol and original PMID string. Keep missing PMID values blank rather than inventing a citation. Retain the original source file and supply the column mapping if its headers differ; the importer keeps original field strings and source row numbers. Human/Homo sapiens and mouse/Mus musculus are recognized without cross-species mapping. An actual tissue is required; `all` is never used as a fallback.

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
