# Gene links in the workbench

Explicit human data retains exact-symbol GeneCards links. Explicit mouse data now shows the original saved symbol, a separate mouse MGI link, and every human ortholog/candidate supplied by a fixed local official mapping. Links are optional external evidence; they do not establish an annotation or verify that an external entry exists.

The central review and saved-project workbench use the run's declared `context$species`. Generic bundles use an explicit saved `context.species` or `parameters.context.species`. Human and mouse aliases documented by the coordinator are accepted; missing/other species is inert. Neither capitalization nor a reference database's organism determines species.

## Mouse snapshot and coverage

The bundled, data-only `ortholog-map.js` snapshot is `mgi-mouse-human-2026-10-05.v1`, SHA256 `64a75b87f51acc7080470da3a8806aa3146855bb4f5b5983a835086e7d7a054c`. It loads locally before the shared helper; missing/invalid data makes mouse links unavailable while human links remain usable.

[MGI's reports](https://www.informatics.jax.org/downloads/reports/index.html) supply 20,183 mouse records and 28,880 pairs. The [protein-coding report](https://www.informatics.jax.org/downloads/reports/HOM_ProteinCoding.rpt) supplies 16,536 distinct recorded one-to-one pairs; Last-Modified 2026-10-05 12:00:29 GMT, SHA256 `2bc350fc189dfd68e2caecebaff0f9a3db18959956e5bb3008981635f87f68c9`. The [HMD report](https://www.informatics.jax.org/downloads/reports/HMD_HumanPhenotype.rpt) supplies the remaining 12,344 conservative `homology_group_candidate` pairs; Last-Modified 2026-10-05 12:00:26 GMT, SHA256 `3caceb612e6c9054a714044589fb3dd960d84f24bff5cdf0bab2b4381358c0a7`. HMD-only pairs are never relabelled as certified one-to-one orthologs. Phenotype content is excluded.

All candidates remain visible for the 1,754 multi-candidate records. Exact canonical symbols take priority over case-sensitive official aliases. Twenty aliases cover only three official mouse pages: Ptprc, Lyz2 and Adh1. For example Lyz2/Lysm maps to LYZ as a recorded candidate, while LysM is unmatched; Adh1 has ADH1A/B/C and H2-Ab1 has HLA-DQB1/2. Unmatched means not found in this snapshot, not absence of an ortholog. Published conflicting mouse NCBI IDs for Slc35f3 remain null with both source values preserved.

Attribution: Mouse Genome Informatics (MGI), The Jackson Laboratory; orthology information from Alliance of Genome Resources. MGI data and annotations are [CC BY4.0](https://www.informatics.jax.org/mgihome/other/copyright.shtml). [Full provenance](../workbench/data/mouse-orthologs/provenance.json) records retrieval times, source hashes, exact alias/group assertions, coverage and limitations. [Offline rebuild instructions](../workbench/data/mouse-orthologs/README.md) use pinned public input bytes; no automatic snapshot refresh or download occurs.

## Click and external-content boundaries

GeneCards primarily presents human entries and can include mouse ortholog/model information. It must not be described as containing no mouse information. The [official orthologs guide](https://docs.genecards.org/genecards/guide/genecard/orthologs) is the relevant guide; automated retrieval returned403 and its body was not verified. Mouse links open a supplied human symbol's `/card/<encoded-symbol>` beside its own MGI record. The [official MGI linking guide](https://www.informatics.jax.org/mgihome/other/link_instructions.shtml) supports `/accession/<encoded-MGI-ID>`.

Only an active click navigates outward, disclosing that selected human symbol or MGI accession and normal browser/network information to the site. Rendering/refreshing makes no external fetch, preconnect, list upload or expression transfer. All links use fixed HTTPS origins, encoded path segments, `target="_blank"`, `rel="noopener noreferrer"` and `referrerpolicy="no-referrer"`. Original marker/citation symbols and decisions are unchanged.

Native Chrome acceptance checks actual popup destinations, safe attributes, refresh and citation preservation with every external request intercepted locally. URL construction and click destination do not prove remote content access, entry existence or biological correctness. This increment adds no gene-explanation model, scraping or scientific mouse validation.
