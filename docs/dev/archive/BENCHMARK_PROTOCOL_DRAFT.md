# Scientific benchmark protocol — draft, not results

This is the next experiment proposal for the frozen single-service baseline
`99d88481614ec54902b28b4a217ca2067ba382c2`. It does not certify scientific
accuracy or Linux/HPC operation. The existing PBMC work is **development data**;
synthetic controls and mock responses establish software behavior only. No
expression matrix, sequencing archive, private data or provider key was read
for this draft. Public repository metadata and bounded file-size/archive-index
requests were read on 2026-10-05; **zero inference-provider calls** were made.

## Small, independent public candidates

Selection is provisional until the metadata/rights gates below pass. These two
studies are independent of the current PBMC development runs and of each other.
Both concern pancreas, so this pilot cannot establish generalization across
tissues. Published studies may have appeared in model training; “held out” means
held out from our local tuning, not proven absent from foundation-model training.

| Candidate | Verified input, annotations and size | Metadata and remaining gap |
| --- | --- | --- |
| Human: Baron et al., GSE84133, **GSM2230757** | GEO's sample record explicitly describes unnormalized UMI counts: CSV columns 1–3 are cell identifier, barcode and author cell-type assignment; remaining columns are genes. HEAD confirms **5,670,823 bytes** for the gzip file. Strip the label column into an evaluator-only table before creating any analysis object. Matrix dimensions and label coverage remain unmeasured. | Human pancreatic islets, inDrop; this sample is a declared donor specimen with non-T2D status. Number/identity of physical captures and processing batches are not established by the inspected sample record. A GSM accession must not be treated as a capture. |
| Mouse: Tabula Muris, **FACS/Pancreas-counts.csv**, Figshare v1 | Author release supplies gene counts, separate cell annotations and plate metadata under **CC BY 4.0**. Official index: FACS.zip **304,170,230 bytes**, annotations_FACS.csv **4,321,940**, metadata_FACS.csv **10,665**. A 65,557-byte HTTP 206 archive-directory read confirms the pancreas member is **13,900,535 compressed / 99,571,196 uncompressed bytes**. No count table was read. | Metadata has distinct plate.barcode, mouse.id, tissue, subtissue, FACS.selection and mouse.sex fields. Mouse identity is not plate identity. Condition, processing-day and any pooled-specimen relationships need the publication/author mapping; do not parse age/condition from an ID string. Smart-seq2 read counts are not droplet UMIs. |

Primary source links: [GEO human sample, including count-format description](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSM2230757&targ=self&form=text&view=full),
[GEO count file](https://ftp.ncbi.nlm.nih.gov/geo/samples/GSM2230nnn/GSM2230757/suppl/GSM2230757_human1_umifm_counts.csv.gz),
[Baron publication](https://pubmed.ncbi.nlm.nih.gov/27667365/),
[Tabula Muris author release](https://figshare.com/articles/dataset/Single-cell_RNA-seq_data_from_Smart-seq2_sequencing_of_FACS_sorted_cells/5715040),
[versioned release metadata and sizes](https://api.figshare.com/v2/articles/5715040),
[plate metadata](https://ndownloader.figshare.com/files/10038310),
[author ingestion/annotation repository](https://github.com/czbiohub-sf/tabula-muris),
[Tabula Muris publication](https://www.nature.com/articles/s41586-018-0590-4).

Rights are route-specific. The [HCA copy of the Baron study](https://explore.data.humancellatlas.org/projects/f86f1ab4-1fbb-4510-ae35-3ffd752d4dfc)
explicitly licenses downloaded/exported data under CC BY 4.0. The inspected GEO
record did not state a standalone dataset license: [NCBI molecular-data policy](https://www.ncbi.nlm.nih.gov/home/about/policies/)
places no repository restrictions but does not transfer submitter rights. Record
the selected route, attribution and applicable terms before provisioning or
redistributing data; do not assign the HCA license to a GEO file by assumption.
HCA's displayed 14 donor entities differ from the paper's four human donors/two
mouse strains and need reconciliation, not a claim of 14 independent replicates.

Preferred provisioning is an automatic, bounded extraction of the one mouse
member plus its two metadata files and the human gzip: approximately **24 MB of
source payload**, plus small directory/header requests. Only archive-directory
range support has been verified; targeted member extraction is **not implemented
or validated**. A future loader must reject a server ignoring Range, check ZIP
member CRC, and hash the actual extracted bytes. The publisher's whole-archive
MD5 is not a locally computed archive hash when only one member is fetched.
The 304 MB archive is a disclosed fallback, not an automatic download. There is
no manual ZIP transfer in the proposed user workflow.

## Freeze before measuring held-out outcomes

1. Snapshot the release-candidate commit, package/library fingerprints, R/Python
   versions, OS/BLAS, source adapters and evaluator. Record each source URL,
   accession/version, bytes, license and SHA256 of the files actually read.
2. Reconcile a cell-keyed metadata table with explicit sample/specimen, capture,
   donor/animal, technical batch and condition columns plus field-level sources.
   Preserve unknown fields as unknown; validate exact cell IDs and joins. No
   positional joins, duplicate IDs or inferred condition-as-batch mapping.
3. Select all cells if a candidate has at most 2,000 cells; otherwise choose the
   first 2,000 by SHA256 of `protocol-v1|accession|literal_cell_id`, ordered by
   hash then literal ID. Save the IDs before opening labels or measuring method
   outcomes. Selection is a pilot sampling rule, not a full capture: automatic
   capture-size doublet-rate inference is disabled for this subset.
4. A separate evaluator stores author labels and a **predeclared** broad/fine
   vocabulary, synonym/ontology mapping and ambiguous/unlabeled status. Labels,
   their class count, author cluster IDs and reference cell-type proportions
   never enter the analysis Seurat object, context, prompt or parameter choice.
   Baron’s identifier/barcode relationship must be validated and saved explicitly.
5. Freeze raw-count assay/layer, mitochondrial feature definitions by species,
   QC grouping/prefilter policy, normalization/HVG/PCA/graph/clustering settings,
   seeds, marker filters, reference provenance, prompts, schemas and generation
   limits. Do not tune a threshold, PC count or resolution to held-out labels.
   QC exclusions cannot be chosen to improve annotation agreement.
   Omit accession IDs/paper titles from model prompts; supply only the declared
   species, tissue, protocol and experimental design. This reduces recall cues
   without proving that published data were absent from model training.
6. Register planned comparisons and metrics locally before the first outcome
   read. Changes after unblinding create a new protocol version and mark this
   pair as development data; select new independent studies for a later claim.

The two-study pilot reports descriptive agreement. Cells are not independent
biological replicates. Report results by specimen/animal and study, with paired
method differences on the same cells. Cell bootstraps must not become donor-level
confidence intervals. With a single human specimen, no human donor-generalization
interval or provider-superiority claim is supportable. Three frozen numerical
seeds can assess computational stability without creating more biological
replicates; paid response replication is a separate experiment.

## Comparisons and scientific boundaries

| Comparison | Frozen design | What it can establish |
| --- | --- | --- |
| Wrapper fidelity | Native Seurat5 and coordinator, same selected counts, supported operations, decisions and seeds | Same-cell/partition agreement, recorded numerical tolerances, marker consistency and replay. It does not measure whether the choices are biologically optimal. |
| QC sensitivity | Keep-all versus the available, explicitly recorded MAD presets on identical declared QC pools; default prefilter none | Retention, metric tails, empty-group guards and changes in downstream populations. Author QC cutoffs are a comparator, not cell-quality truth. Read-count thresholds cannot be copied from PBMC UMI thresholds. |
| Annotation baseline | Local marker-reference matching with a valid, versioned species/tissue reference; manual blinded marker review reported separately | Agreement with author labels, reference coverage and reviewer effort. The bundled example reference is not a valid biological baseline. If a usable reference is absent, report the baseline as blocked. |
| Provider/evidence comparison | DeepSeek and Grok; guided versus independent annotation, same frozen clusters/markers/context for each provider | Provider and reference-guidance effects on the measured pilot. Guided responses see the same saved DB candidates; agreement with DB is not independent confirmation. |

The coordinator’s annotation summary has one array covering all clusters and
supports guided/independent evidence modes. Its main suggestion path makes one
whole-stage request. The legacy `annot_llm_annotate` per-cluster path is a separate
experiment and must not be counted as one request. Preparing identical sibling
projects from a validated processed object/evidence snapshot, with explicit
processed-entry provenance, avoids recomputing the foundation for each provider;
this benchmark adapter still requires implementation and a leakage check.

Audit every reference for the candidate study, duplicate donors/cells, labels or
study-derived marker lists. A tissue marker DB citing a held-out study is a
potential information dependency; either exclude those records before freezing
or report the dependency and avoid an independent-reference claim. A reference
classifier trained on the same study is likewise ineligible as an independent
baseline. Do not add SingleR/CellTypist downloads or training to this first pilot.

Doublet detection is skipped for unknown human captures and this plate-based
mouse pilot; no scDblFinder accuracy conclusion follows. Harmony is skipped
until a defensible technical-batch design with nonconfounded biological groups
is available. Cell-cycle regression and feature/Harmony ablations need separate
protocols. MAD is a supported heuristic, not scientifically validated here;
[OSCA QC guidance](https://bioconductor.org/books/release/OSCA.basic/quality-control.html)
describes assumptions and risks of removing valid low-RNA/high-mitochondrial
populations. Independent project notes and gene-explanation chat are outside
this frozen version; initialize research context/notes and review saved marker,
expression/reference evidence without adding an explanation API.

## Keep format, abstention and biology separate

Use the exact implementation schema `scagentkit.annotation.v1`; preserve the raw
reply and label. The evaluator canonicalizes only supported `unknown`/
`unannotated` tokens, case-insensitively after trimming, to **Unknown**. Missing,
malformed or foreign-cluster responses remain failures, not silent Unknowns.
Freeze the evaluator vocabulary before responses. A valid known label with
admissible marker citations is not proof of correct biology.

| Metric | Denominator / interpretation |
| --- | --- |
| API/schema/citation validity | All scheduled attempts, including dispatch, timeout, parse and unsupported-operation failures. Gene-in-evidence checks measure grounding to the supplied list, not cell-type specificity or literature truth. |
| Reference-label availability | Author-labeled/evaluable cells divided by all selected cells; report ambiguous/unlabeled cells separately and their QC retention. |
| Annotation coverage | Retained evaluable cells receiving a valid non-Unknown prediction / all retained evaluable cells. Report Unknown, API/schema failure and unmappable-label fractions separately. |
| Conditional label agreement | Correct predefined author-label matches / all valid non-Unknown predictions on retained evaluable cells; unmappable known labels are nonmatches, not dropped denominators. Undefined when coverage is zero. Report broad and fine mapping separately, plus confusion matrices/per-type precision and recall with abstentions counted as misses for recall. |
| End-to-end correct-label yield | Correct retained predictions / originally selected evaluable cells; show QC exclusion and abstention next to it. This is yield relative to author labels, **not QC accuracy**. |
| Partition/stability | ARI/NMI against author labels and across frozen numerical seeds, explicitly labeled clustering agreement. Do not relabel these as annotation accuracy or map predicted cell types to truth using an outcome-optimized permutation. |
| QC impact / resources | Retention by declared pool and, evaluator-only, author type; eligible/removed scopes, warnings, runtime, peak memory where measured, tokens, known costs and unresolved holds. No quality truth means no QC sensitivity/specificity/accuracy. |

Save model suggestions before human revision and score them separately from
approved final labels. A blinded reviewer logs decisions/reasons and time; final
agreement does not become unassisted AI agreement. Conflicting author labels or
marker evidence are adjudicated with the frozen rules, with unresolved biology
retained as uncertainty rather than forced into a positive result.

## Calls and budget: proposal only

Current provider calls/cost for this draft are **0 / US$0**. All offline baselines,
mechanism replay and payload preparation run first. Only preview-approved public
aggregate QC/markers/expression plus restrained research context may be sent;
no count matrices, barcodes, author truth or individual metadata. Freeze the
actual payload hash and inspect its contents before any future external call.

| Later experiment | Maximum attempts, no automatic retries | Planning reserve ceiling |
| --- | --- | --- |
| First annotation comparison | 2 datasets × 2 providers × 2 evidence modes × 1 response = **8** whole-stage requests | **US$1.20**, using a proposed US$0.15/attempt reservation |
| Optional QC/strategy choices | Up to 1 QC + 1 strategy request for each dataset/provider = **8 additional**; a combined joint node must not be double-counted | **US$1.20 additional**, US$2.40 combined ceiling |
| Separate stochastic annotation replication | 3 responses per annotation comparison = **24 annotation** requests; with the optional 8 choices, **32 total** | **US$4.80 combined ceiling**; not included in the first pilot |

These are reservations, **not verified token-price estimates or authorization**.
Before live execution, resolve the exact available model IDs and their official
current prices, tokenize the frozen requests, set output caps, and calculate the
uncached worst case as `sum(input_tokens * input_rate + output_cap * output_rate)
/ 1e6`, with explicit margin and existing unknown-usage holds. The US$0.15
reservation is acceptable only if that calculation fits it; otherwise reduce
scope or obtain a revised budget before dispatch. Reconcile the shared authorized
development ledger; do not treat a per-project budget as a global account limit.
The initial preparation target is at most 12,000 input tokens and a 4,000-token
annotation output cap per attempt, with thinking/search/tools disabled. If a
complete supported payload cannot fit, preparation stops for a separately
budgeted design change; no silent marker/cluster truncation or extra chunk calls.
Cached replay is not a new attempt; use explicit request IDs and retain invalid
responses and conservative holds without automatic retry.

Keep the existing requested IDs (`deepseek-flash`, thinking disabled, and
`grok-4.20-0309-non-reasoning`) pending availability revalidation; do not silently
substitute another model. The [official DeepSeek announcement](https://www.deepseek.com/en/news/deepseek-v4-1-flash/)
currently describes `deepseek-flash` as V4.1-Flash, while the
[official Grok catalog](https://docs.x.ai/developers/models) prominently lists
newer models and did not establish availability/pricing of this legacy target
in the inspected page. Record requested/reported IDs, endpoint, UTC time,
generation settings, finish status, usage, cost and price-page snapshot. An alias
or reported ID cannot guarantee immutable server weights. Legacy-model
availability and exact pricing are **live-comparison blockers**, not a reason to
read keys or send a discovery inference now.

## Next executable work, in order

1. Finish the latest-source private-library release audit and resolve its
   must-fixes. Keep Mac evidence distinct from any actual Linux executor run.
2. Reconcile the two candidates' rights/metadata and implement the bounded
   download/import plus label-isolated evaluator in a new benchmark directory;
   do not overwrite development PBMC projects or install into user libraries.
3. Freeze source/input/context/reference/selection/evaluator hashes; run the
   matched offline Seurat/coordinator baseline, QC sensitivity and R restart
   replay. Validate exact-ID preservation and missing-truth behavior first.
4. Prepare all comparison payloads and the model/price/token/call ledger for
   review. Run providers only after that concrete scope and budget are approved.
5. Publish one compact report with completed/blocked/not-run rows and measured
   outcomes, uncertainty, resource use and source hashes. Software-test totals
   support reliability; they do not replace these scientific measurements.
