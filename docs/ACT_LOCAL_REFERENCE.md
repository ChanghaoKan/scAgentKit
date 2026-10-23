# Bundled ACT snapshot

This build contains lossless deterministic gzip copies of the
user-supplied Human/Mouse merged TSVs. No network access is used for default loading.
New `sc_analyze()`/raw `sc_start()` projects and new processed browser entries
select the matching reference at creation and save it as a checksummed project
artifact. No reference is injected when reopening an existing project.
`sc_analyze(..., reference=NULL)` explicitly opts out; a supplied custom reference
wins. Low-level `sc_run()` keeps its existing explicit-reference behavior.

```r
ref <- annot_act_reference(species="human", tissue="Blood")
attr(ref, "act_snapshot")  # original/compressed SHA, sources, schema and citation
x <- sc_analyze(input, "new-project",
  context=list(species="human", tissue="Blood"), provider="manual")
```

Declared human/mouse species and exact trimmed case-insensitive tissue are required.
`Blood` does not also select Blood vessel/plasma/serum. Unknown tissues produce a
visible zero-match notice and an empty scoped reference, never all-tissue fallback.
No ortholog inference, marker recasing, PMID rewriting or row deduplication is done
in the pinned source. Marker expansion retains original field strings, row numbers,
SourceFile and SourceURL. First annotation still receives independent marker-only
evidence; reference comparison and at most one explicitly authorized guided review
come afterward. Three scientific approvals remain separate.

## Fixed provenance

`inst/extdata/references/act-private-2026-10-20/PROVENANCE.json` records the supplied
download date 2026-10-20, Human743295B/3767rows and Mouse598641B/2721rows, seven
columns, source HTTP paths, compressed and raw SHA256, original download manifest
and the unknown publisher release/date. Download date is not a database release
date, and local hashes do not authenticate the publisher. Both original files
remain unchanged in the user’s outputs directory.

Citation: Quan F et al. Annotation of cell types (ACT): a convenient web server
for cell type annotation. Genome Medicine15,91(2023).
DOI: [10.1186/s13073-023-01249-5](https://link.springer.com/article/10.1186/s13073-023-01249-5);
PMID37924118. This identifies the ACT publication, not a verified match between
this 2026 download and the paper’s original data version. Use
`citation("scAgentKit")` for the full reference.

## Separate study and reference tissue

```r
annot_act_scopes("human")  # exact keys and source-row counts; selects nothing
sc_start(input, "new-project",
  context=list(species="human", tissue="Peripheral blood", research_goal="..."),
  reference_tissue="Blood", provider="manual")
# R entry: sc_analyze(..., reference_review=list(tissue="Blood"))
```

This is an explicit scientific reference-scope choice. It preserves the original
study description, records both values in reference provenance, and never guesses
that PBMC or peripheral blood means a particular database key. Default matching
is unchanged. No all-tissue or cross-species fallback is introduced. Existing
projects use their saved reference; an evidence revision before annotation
application uses `sc_run_set_reference(..., reference_review=list(tissue="Blood",
strict_scope=TRUE))` with the inspected bindings, reviewer and reason.

## Existing projects and implementation identity

This development version changes the execution fingerprint because it adds
explicit reference-scope configuration and portable output projections. Keep the
original package/dependency environment for existing projects. The new version
does not migrate projects or rewrite configuration, implementation hashes or
approvals. New projects require new review. The browser runtime also requires its
matching installation and manifest.

Explicit local import with `annot_import_act(path, ...)` is unchanged. Its tissue
filter is literal substring; use the bundled loader above for exact matching.
