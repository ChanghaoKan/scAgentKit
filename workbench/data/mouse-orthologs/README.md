# Pinned mouse link data

`../../static/ortholog-map.js` is a data-only local snapshot (`mgi-mouse-human-2026-10-05.v1`), derived from public MGI reports and three official mouse Summary pages. It assigns `ScMouseOrthologData` and performs no network requests. Its SHA-256 is `64a75b87f51acc7080470da3a8806aa3146855bb4f5b5983a835086e7d7a054c`.

MGI data and annotations: CC BY 4.0. Attribution: Mouse Genome Informatics (MGI), The Jackson Laboratory; orthology information from the Alliance of Genome Resources. See `provenance.json` for exact URLs, retrieval times, Last-Modified values, source checksums, schema, coverage, verified alias/group assertions and the retained identifier conflict. Phenotype, OMIM, image and expression content are excluded from the asset.

The source reports are public versioned inputs rather than user data. An offline rebuild requires the exact five files and five acquisition receipts named in `build_snapshot.py`. Changed source bytes are rejected. Run:

```sh
python3 workbench/data/mouse-orthologs/build_snapshot.py \
  --input-dir /path/to/pinned-public-source-files \
  --output-dir /path/to/new-rebuild-directory
```

Compare `mouse-orthologs.v1.js` in that output directory with the shipped asset. The script never downloads sources and never reads an analysis project. Acquiring a newer report is a deliberate snapshot update requiring new provenance and validation; loading the workbench never refreshes it automatically.

This mapping is for optional external link display. It is not an annotation reference or an expression translator. Exact aliases cover only Ptprc, Lyz2 and Adh1. HMD-only pairs retain a conservative candidate label; every candidate is shown. See `docs/GENE_LOOKUPS.md` for click disclosure and limitations.
