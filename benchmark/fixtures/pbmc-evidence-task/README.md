# Public PBMC evidence-transfer task

This small local reference is a manually curated coarse grouping of marker
examples in the [Seurat PBMC3k tutorial](https://satijalab.org/seurat/articles/pbmc3k_tutorial),
section “Assigning cell type identity to clusters” (page inspected 2026-10-18).
It preserves the listed marker facts, groups related tutorial names into broad
lineages for this software task, and declares human / peripheral-blood scope.
It is not a comprehensive reference atlas, calibrated classifier or independent
per-cell ground truth. The tutorial's cluster numbers are deliberately omitted.
No reference candidate is automatically assigned, and a single-marker 100%
coverage remains weak evidence. Unknown and coarse decisions are valid outputs.
The source's dataset redistribution license is not inferred from a paper license.

Compare baseline 19ad4a6 with the iteration using the same raw public PBMC3k RDS,
this exact file/hash, the same explicit QC/PC/clustering choices and one task:
inspect the B-lineage candidate supported by this cluster's MS4A1 marker, record
an analyst interpretation/reason and qualitative confidence, explicitly retain
other groups Unknown, save one complete proposal and approve it separately.

Record actual scripted manual field edits, evidence transcription actions,
artifact/tab transitions and candidate-control actions separately. Do not count
an automatically moved label/citation as a human edit. Do not turn developer
walkthrough counts, runtime or automation into real-user time savings. Keep the
same rationale/uncertainty and complete-proposal review requirement in both arms.
Use the [offline contract](../../../docs/dev/OFFLINE_COMPARISON_CONTRACT.md) for
scientific comparison prerequisites; these PBMC labels are a case, not accuracy.
