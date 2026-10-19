# Optional scientific review methods and boundaries

Extra rebuilding experiments are opt-in and run locally. New raw strategy
projects retain ordinary PCA/80% selection, the ordinary resolution scan/tree,
sample QC/elbow/citation/Fisher evidence where applicable, and classic mean/pct
panels for explicitly declared human blood/PBMC or pancreas. Unknown declarations
and absent genes are unavailable/missing, not inferred zeros. PC sensitivity,
resampling, extra resolution extension, sample-consensus HVGs remain off by default. Eligible conservative AND3 draft
selection is described below; incomplete evidence stays keep-all. Cross-sample/mixed-lineage expression
extensions and R-only SoupX/decontX also remain explicit choices. No evidence
display authorizes a data transfer, chooses optimal settings or certifies labels. See the registered
[evaluation protocol](dev/EVALUATION_PROTOCOL_V1.md) and
[operator guide](SCIENTIFIC_REVIEW_QUICKSTART.md). Preset and diagnostic
eligibility are software rules; no biological default benefit is assumed.

| Method | Calculation | Applicability and interpretation |
| --- | --- | --- |
| Within-group cell MAD | log10(count+1)/log10(feature+1), raw MT percent; 3 scaledMAD, explicit groups | Counts/features use lower-tail deletion flags; MT uses its upper tail. Upper RNA bands flag only. Distinct from comparing sample medians. |
| Between-sample QC | One median per declared sample; signed robust z with1.4826 MAD | >=5 comparable samples, complete metrics/nonzero MAD. No automatic sample exclusion; biological design may explain differences. |
| Conservative AND3 draft | Joint low-count, low-feature and high-MT flags only when the complete saved group-specific MAD evidence is eligible | Incomplete/ambiguous evidence retains keep-all. Never OR-autofill. It is an unapproved draft, not independent cell-quality truth; human choices take precedence. |
| Per-sample HVG | Vst2000 (or approved feature count) per sample; frequency descending, median rank ascending (missing rank=nfeatures+1), literal-gene tie break | >=2 declared samples, each>=30 retained cells; explicit approved sample_consensus request. Equal sample influence can obscure sample-specific biology. |
| Reference variance | Exact first cumulative80/85% crossing in first min(50, computed PCs) | Not total expression variance; shortfall and unsupported one-PC crossing remain explicit. |
| Elbow | Maximum perpendicular distance below endpoint chord after scaling both axes to unit ranges | Requires nonconstant decreasing curve and interior knee. Descriptive alternative, no automatic selection. |
| PC sensitivity | Valid unique k-5,k,k+5; same cells/HVG/PCA, recompute graph and clusters; ARI and shared-cell best-Jaccard plus native top-marker Jaccard | Values bounded to actual PC availability, boundary collisions disclosed. Recomputed k control matters; no optimality or causal-identity claim. Unsupported Harmony/cycle pipelines are unavailable. |
| Subsampling | Five80% cell subsets, seeds42..46; rebuild normalization/HVG/scale/PCA/neighbors/clusters | Shared-cell ARI/Jaccard and original-cluster retention separately. Computational stability is not donor replication. No silent rank clipping or alternate pipeline. |
| Resolution extension | Observe approved grid counts and upper-edge ARI; if single partition/boundary change, add missing0.1,1.4,1.6 once | Finite exploratory diagnostics; original approved resolution and membership remain authoritative. |
| Panel expression | Mean log-normalized expression, raw-count detection proportion, inside/outside differences per cluster | Missing gene differs from observed zero. Broad expression (detected in half of cells in>=80% clusters) is a warning, not a semantic label test. |
| Cross-sample expression | For each cluster/sample with>=20 inside and outside cells, positive mean difference and positive detection difference | Report eligible sample count and all per-sample effects, consistency only for>=2 samples. No pseudobulk p-value or donor-level independence claim. |
| Mixed lineage | Per-cell detected panel-gene counts; pairs meet min(2, measured panel genes) each | Exploratory coexpression display, not a doublet, ambient or cell-type classifier. The all-cited-genes review list is excluded from lineage pairs. |
| Citation positivity | Known label requires every cited supplied marker to have saved FC>0 and pct1>pct2 | Minimum numerical support only. Unknown may retain uncertainty/counterevidence; no gene-label semantic proof. |
| Fisher enrichment | Unique query/reference intersection with exact pre-test eligible gene universe; a=overlap,b=query-only,c=reference-only,d=neither; one-sided greater | Native Seurat FoldChange supplies pct prefilter values including its rounding; only supported zero-logFC/both-direction test settings. No universe from significant/top genes. BH across all tested labels per cluster before display. Original hits/coverage ranking remains unchanged. |

Sparse counts stay sparse; exact literal cell/feature joins are validated before
reordering. Reference aliases are applied consistently to query, reference and
background. Changing source counts, IDs or approval artifacts is not an acceptable
way to repair a stale project. Scientific diagnostics are hashed into the saved
cluster scan and require the same subsequent explicit author review; an empty
resolution grid cannot silently disable explicitly requested diagnostics.

## The first-50-PC 80% rule: calculation and source

The default `computed_top50` threshold of **0.80 is a scAgentKit project
heuristic**, retained from its earlier review policy. It is not a Seurat
recommended threshold. The same implementation also offers 0.85 for review.
[Seurat RunPCA](https://satijalab.org/seurat/reference/runpca) documents the
calculation and default storage of 50 PCs; it does not prescribe this 80% rule.
The official [Seurat dimensionality tutorial](https://satijalab.org/seurat/articles/pbmc3k_tutorial.html#determine-the-dimensionality-of-the-dataset)
describes inspecting PCs and an elbow plot when choosing dimensions.

Let `M` be the number of actually saved PCs and `w = min(50, M)`. The variance
of component `i` is its saved standard deviation squared, `v[i] = SD[i]^2`.
For `k` from 1 to `w`, the calculation is:

```text
cumulative_fraction[k] = sum(v[1:k]) / sum(v[1:w])
selected_k = first k with cumulative_fraction[k] >= 0.80
```

Thus the denominator is **the variance sum of the first w saved PCs**. With
20 saved PCs it uses all 20 and records a 30-PC shortfall; it does not invent
missing components. With 60 saved PCs it uses only the first 50. This is not
80% of total expression or total HVG variance. The initial request is also
bounded by the available features and cells; the actual saved count determines
the denominator. Invalid variances are rejected. A crossing at one PC requires
a revised rule or an explicit supported fixed choice; it is not rounded up.

Calculation sources: [R's PCA definition of standard deviations and variances](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/prcomp.html),
the fixed-main [default policy](https://github.com/ChanghaoKan/scAgentKit/blob/2b0827fc04fde28191241c300ab687200df660c8/R/analysis-api.R#L45-L90),
[exact implementation and shortfall handling](https://github.com/ChanghaoKan/scAgentKit/blob/2b0827fc04fde28191241c300ab687200df660c8/R/run-pc-diagnostics.R#L9-L50),
and the project's [earlier policy explanation](dev/HARMONY_PC_REVIEW.md#two-pc-policies-with-the-denominator-disclosed).
These establish the calculation and its project origin, not a universal 80% cutoff.

## Reading QC flags and retention

The saved grouped panel reports disjoint low-count-only, low-feature-only,
high-MT-only and joint flag patterns among each group's pre-score cells.
Overlapping independent flags must not be added to estimate unique removals.
The OR candidate removes the union; the AND candidate removes only the
three-way intersection. Selected retention also accounts separately for the
minimal prefilter and doublet choice. Group denominators and original sample
cell counts remain explicit. Missing flags make intersections unavailable,
rather than a measured zero. QC groups, declared samples and capture units
are distinct roles; none is inferred from condition or donor.

The MT table displays the exact saved median, upper threshold, scaled MAD and
upper-minus-median margin in percentage points. A positive MAD may still imply
a tiny absolute difference. Assess technical precision, flag overlaps and
sample comparisons in study context; there is no universal minimum MT margin,
normality gate or automatic threshold adjustment. Distribution warnings are
interpretive. The keep_all starting proposal is not a completed QC assessment.
Cell-type-specific deletion risk remains unassessed without independent
identity evidence; QC review neither infers author labels nor requires a new
annotation analysis.

The published legacy MAD helper used different semantics (it is retired from this development build): log10(x) for positive
counts/features, deletion at both their low and high tails, and upper-only
MT/ribosomal/haemoglobin deletion with a one-percentage-point scaled-MAD floor.
That helper could pool cells or use explicit groups. The single current engine instead
uses log10(x+1), lower count/feature tails, flag-only high RNA and diagnostic-only
ribosomal/haemoglobin values, without that MT floor. Its existing small-group,
nonfinite and near-zero-MAD availability guards remain unchanged. These are
different software policies, not interchangeable biological recommendations.

## Main annotation marker pool

The native coordinator defaults to FindAllMarkers with both directions enabled,
min.pct=0.25 and logfc.threshold=0. The detection prefilter uses
`max(pct.1, pct.2) >= min.pct`: either side can qualify, not both sides required.
The supplied summary then keeps strict `avg_log2FC > 1` and `p_val_adj < 0.05`,
ranks descending by `pct.1 - pct.2`, and keeps at most 30 genes per cluster.
Explicit marker settings are recorded with native evidence. A manually supplied
table without this provenance is labelled unrecorded rather than assigned the
default policy.

Main-workflow citations and local reference overlap use this selected pool;
they do not range over all assayed or tested genes. A valid supporting gene
outside the top 30 or FC/p-adjusted cutoffs cannot be cited through this pool.
Absence is not absent expression. Reference coverage and Fisher enrichment
remain conditional on query selection, reference curation and the separately
recorded pre-test background. Known-label citations additionally require
positive saved FC and pct.1 greater than pct.2; these numerical guards do not
establish gene-label semantics. This review records and tests the existing
policy without broadening the pool or loosening evidence gates.

## Ambient estimation and correction

The input copy and original count hash are preserved. Corrected counts are
separate returned/output data with exact feature/cell IDs, method/version/seed,
input scope, estimated contamination and before/after UMI/detection totals.
Floating estimates are preserved unless the caller explicitly chooses rounding.
There is no automatic downstream replacement or claim that fewer counts is better.

- SoupX: one declared complete capture, matching raw/filtered counts, at least20
  additional droplets and preliminary clusters; SoupChannel -> setClusters ->
  autoEstCont -> adjustCounts. Refuse a guessed filtered-only background.
- decontX: explicit preliminary clusters; when raw input is supplied, pass only
  additional droplet columns as background, never the called cells. Without
  additional droplets pass NULL and disclose the inferred other-cluster model.
  Contamination estimates can remove real shared/state expression.

Official method documentation: [SoupX vignette](https://cran.r-project.org/web/packages/SoupX/vignettes/pbmcTutorial.html),
[decontX vignette](https://bioconductor.org/packages/release/bioc/vignettes/celda/inst/doc/decontX.html),
[SingleR](https://bioconductor.org/packages/release/bioc/html/SingleR.html),
[celldex reference descriptions](https://bioconductor.org/packages/release/data/experiment/html/celldex.html).
These sources describe methods; they do not validate this branch's implementation
or establish benefit on a particular dataset. Frozen before/after artifacts and
negative/neutral outcomes must be reported separately before default adoption.

## Current computation and reference scope

The raw workflow uses Seurat LogNormalize (scale factor 10,000), VST variable
features and PCA. SCTransform/SCT is not an implemented alternative. Declaring
human or mouse supports the corresponding verified gene/reference handling;
it does not guarantee cycle or doublet eligibility, cross-species marker validity,
or coverage of every tissue. Unsupported/missing mappings are unavailable.

Diagnostic resolution scans use positive native markers with min.pct 0.25 and
logFC threshold 0.25, retaining top 30 per cluster. The selected final clustering
gets the separate full configured marker calculation; scan pruning never replaces
that marker CSV. Adjacent-resolution child contrasts use the actual parent-cell
subset against its other children, with top 10 positive markers and eligibility
limits. The model summary projects this evidence under a measured byte bound,
reports omitted blocks and keeps the full local evidence. Ribosomal/MT/cycle
fractions describe programs, not noisy-cluster or identity classifiers. Resolution
fallbacks require a value actually scanned; no composite optimum is claimed.

The annotation query pool ranks fold change first and detection difference second;
shared ribosomal/MT exclusions are configurable and recorded, with the native full
marker table preserved. ACT coverage deduplicates genes while publication evidence
retains original PMID strings and source rows. Fisher evidence is conditional on a
valid tested-gene universe and supported native marker settings; missing universe
means unavailable, not a substituted enrichment p-value. ACT overlap is not
independent validation of a guided candidate. Exact CL names/EXACT synonyms use the
pinned base ontology; ambiguous, obsolete or unmatched labels keep a missing CLID.
