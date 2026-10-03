# Local directed RNA expression evidence

`extract_directed.R` creates a deterministic, versioned evidence bundle for the
PBMC3k cluster-6 NK/CD8 disagreement. It reads the frozen Seurat object locally,
uses the existing **RNA counts** for detection and the existing **RNA data** for
normalized expression, and exports only a targeted panel. It does not normalize,
filter cells, split clusters, read truth labels, or make network requests.

The original source files remain unchanged. The exact provider-input and retained
cell maps and UMAP must agree by **cell_id**, with 2,638 retained cells, 9 clusters,
and exactly 155 cluster-6 cells. Duplicate genes/cells, missing cell maps, zero
denominators, non-finite values, noninteger/negative counts, and inconsistent
counts/data coverage fail extraction.

## Running

Use the existing local R library containing SeuratObject, Matrix, jsonlite and
digest. No system installation is needed. Obtain the core evidence revision from
`EvidenceLoader(results_root).load()["revision"]` and pass it explicitly:

```sh
R_LIBS_USER=/path/to/existing/r-library Rscript --vanilla workbench/extract_directed.R \
  --rds /path/to/results/pbmc3k_verified/scagentkit_fixed_seurat.rds \
  --cells /path/to/results/pbmc3k_reference_inputs/input_cells.csv \
  --labels /path/to/results/pbmc3k_verified/scagentkit_fixed_labels.csv \
  --umap /path/to/results/pbmc3k_verified/scagentkit_fixed_umap.csv \
  --output-dir /path/to/local/phase3-evidence \
  --input-evidence-revision CORE_SHA256 \
  --cluster 6
```

Outputs stay outside Git:

- `expression.json`: versioned evidence, source content hashes, exact local cell
  scope, 24-gene aggregates, cluster-6 per-cell panel/QC/UMAP, coexpression,
  sensitivity checks and candidate controls.
- `expression-manifest.json`: the actual expression-file byte hash and extraction
  provenance.

An identical rerun accepts existing identical bytes. A different bundle cannot
overwrite those files; use a new run directory. Semantic evidence contains no
timestamps or machine-specific paths. Its `package_id` derives from the complete
deterministic content, including actual source/extractor hashes, R/package
versions, layer selection and configurations.

## Measurement and exploratory rules

Missing genes have null counts, detection statistics and normalized distributions;
they are never filled with zero. Measured zero remains zero. A gene absent from a
top-30 marker list has no effect on this full-RNA-layer lookup. Distributions
include all cells and the count-detected subset, with denominator, mean, minimum,
25th/50th/75th/90th percentile and maximum. Quantiles use R type 7.

The panel separates T identity anchors (CD3D, CD3E, CD3G, TRAC, TRBC1, TRBC2), CD8
subtype evidence (CD8A, CD8B), NK identity anchors (KLRD1, KLRF1, NCR1, NCAM1),
nonexclusive FCGR3A, and shared cytotoxic genes. B anchors MS4A1/CD79A/CD79B are
used only to identify expression-based candidate comparator groups.

The primary descriptive gate is at least two detected identity anchors per cell.
CD8A/CD8B, FCGR3A and shared cytotoxic genes do not enter identity gates. Thresholds
1/2/3 are shown for sensitivity. `t_gate` and `nk_gate` describe **observed** gates;
below-threshold detection is not negative biological evidence. The additional
`*_identity_gate_possible` fields are null when missing anchors could change the
gate, true when observed anchors already meet it, and false only when even the
missing-anchor upper bound could not meet it. Missing-anchor coverage is retained.

Only actual nCount_RNA, nFeature_RNA, percent.mt and orig.ident metadata are
exported. `orig.ident` is an observed metadata category, not an independently
verified donor/sample identity. The primary low-depth flag is nCount_RNA <1,000
**or** nFeature_RNA <500, with exact boundaries and lower/higher thresholds shown.
All thresholds are uncalibrated. Low-depth absence of detection does not establish
lineage absence, and no cells are removed. Same-cell T/NK detection does not
establish NKT identity or doublets.

All eight other clusters have panel/QC summaries. Candidate lymphocyte comparator
selection uses observed >=2 T/NK/B anchors in >=20% of a cluster, with 10%/20%/30%
selection sensitivity. Both the all-rest and candidate-comparator denominators are
provided. Controls reuse the same expression/clustering and are correlated and
unverified; they are never selected using author/truth labels.

## Frozen local run and verification

The phase-3 local fixture measured 21/24 genes. TRAC, TRBC1 and TRBC2 were absent
from both saved layers. The primary observed coexpression counts were 13 T-only,
39 NK-only, 2 both and 101 neither. These are descriptive categories, not new cell
annotations. The primary depth flag affected 2/155 cells; the lower/higher flags
affected 0/155 and 24/155. RNA-depth medians were 1,915 UMIs and 890 genes.

Run:

```sh
python3 -m unittest discover -s workbench/tests -p test_expression_export.py -v
```

The tests run synthetic missing/zero, mixed coexpression, invalid counts,
duplicates, zero-denominator and depth-boundary cases. When the external fixture
exists, they verify real scope/hash alignment, every panel distribution,
coexpression rules, actual QC and candidate-control limitations. An independent R
verifier checks every targeted count/normalized value and whitelisted QC value
against the original RNA object without exporting the matrix.

Optional numerical crosscheck of the earlier exploratory pilot:

```sh
python3 workbench/check_expression_crosscheck.py \
  --expression /path/to/local/phase3-evidence/expression.json \
  --pilot-summary /path/to/task-4/evidence/expression_summary.json \
  --output /path/to/local/phase3-evidence/expression-crosscheck.json
```

The frozen run matched 10 common genes across cluster-6/all-rest aggregates in
21 checks (including source SHA256), using a 5e-13 serialization tolerance. This
crosscheck does not import previous judgments or gates and is not independent
biological validation.
