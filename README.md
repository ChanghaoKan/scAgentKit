# scAgentKit

scAgentKit is designed to help researchers with a biological background spend less time maintaining a single-cell RNA-seq workflow. Starting from counts and sample facts or a Seurat/RDS object, it guides QC, basic analysis and annotation through a saved, reviewable project.

You receive a new Seurat object with counts, sample metadata, reductions and reviewed labels, plus marker tables, figures and the evidence and reasons behind decisions. QC, integration and clustering still require study judgement; default settings are starting points. FASTQ processing is upstream. Research-specific trajectory, communication and regulatory-network analyses are downstream and are not run automatically.

## Installation

Requires R ≥ 4.2, Seurat ≥ 5 and an existing Python ≥ 3.9 for the browser. Browser resources ship inside the R package. Version `0.6.0` is experimental.

Public Release downloads need no credential. GitHub dependency resolution can
hit the unauthenticated API quota; `remotes` supports an existing `GITHUB_PAT`
in that case. CI uses its existing read-only job token, not a new credential.

Download [scAgentKit_0.6.0.tar.gz](https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.6.0/scAgentKit_0.6.0.tar.gz) from the [v0.6.0 Release](https://github.com/ChanghaoKan/scAgentKit/releases/tag/v0.6.0), then install that archive into your own R library. The asset becomes available only after release publication; a prepared archive or successful CI run does not publish it. See the [release gates](docs/RELEASE_PLAN.md).

Download both assets and verify the archive before installing:

```sh
curl -fL --retry 3 --connect-timeout 30 --max-time 1800 -o scAgentKit_0.6.0.tar.gz https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.6.0/scAgentKit_0.6.0.tar.gz
curl -fL --retry 3 --connect-timeout 30 --max-time 1800 -o SHA256SUMS https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.6.0/SHA256SUMS
shasum -a 256 -c SHA256SUMS  # macOS; on Linux use: sha256sum -c SHA256SUMS
```

Stop on a checksum failure. In a fresh R session, allow enough time for large
dependency downloads and check that the intended private installation loads:

```r
options(timeout=max(1800, getOption("timeout", 60)))
lib <- path.expand("~/R/scagentkit-library")
dir.create(lib, recursive=TRUE, showWarnings=FALSE)
.libPaths(c(lib, .libPaths()))
if (!requireNamespace("remotes", quietly=TRUE))
  install.packages("remotes", repos="https://cloud.r-project.org")
remotes::install_local("scAgentKit_0.6.0.tar.gz", lib=lib,
  dependencies=c("Depends", "Imports"), upgrade="never", build=FALSE)
library(scAgentKit, lib.loc=lib)
stopifnot(as.character(packageVersion("scAgentKit")) == "0.6.0",
  identical(normalizePath(find.package("scAgentKit")),
    normalizePath(file.path(lib, "scAgentKit"))))
packageVersion("scAgentKit")
```

Run from the directory containing the downloaded archive, or give its full path.
An installation log containing `ERROR` is not success: the explicit load,
version and library-path assertions must pass before running the offline check.
This installs required dependencies, including the declared
`ChanghaoKan/agentomicsCore@v0.1.1`. Record the archive SHA256, package versions
and `sessionInfo()` for reproducibility. Do not substitute mutable `main` or an
older tag. Optional methods have their own verified version contracts; see
[installation and runtime support](docs/LINUX_RUNTIME_SUPPORT.md).

## Offline installation check

After installing, run the bundled public-data software example in a new project:

```r
source(system.file("examples", "simple-analysis.R", package="scAgentKit"))
result <- simple_analysis_after(tempfile("scagentkit-offline-"))
stopifnot(inherits(result, "Seurat"), ncol(result) > 0)
```

This example uses `pbmc_small`, explicit software-control approvals and Unknown
labels. It makes no provider call and does not validate biological identities.
The release acceptance job runs the installation commands above in a fresh
`rocker/r-ver` container with empty package libraries, then runs this example;
its complete dependency-install and example logs are retained with the CI run.

### Existing saved projects

Execution and approval require the saved implementation hash to match the
running functions and fingerprinted dependency versions. An older project with
a different hash cannot continue under this release. Preserve its original
project, inputs, package build and dependency environment; restore that exact
environment to continue, or create a new project from the original input and
review it again. Never edit saved hashes, approvals or checkpoints to force a
resume. See [compatibility and deprecation details](NEWS.md).
Author-label metadata priors default to off; using them requires explicit opt-in.
The [v0.6.0 source recipe and restoration limits](docs/ENVIRONMENT_RESTORE.md)
pin the release's R environment and package sources. Match the original archive
and implementation, not just its version number; this is not an automatic
cross-version project migration.

## Analysis protocol

This section describes the development workflow. The new candidate recommendations and fact-correction controls remain unreleased; they are not included in the published v0.6.0 archive.

### 1. Choose counts and declare sample facts

For one 10x MEX directory, declare a unique sample ID and whether the source matrix is raw or filtered:

```r
input <- "filtered_feature_bc_matrix"
project_dir <- "analysis"
context <- list(species="human", tissue="Actual tissue",
  research_goal="Actual study question")
service <- sc_start(input, project_dir, context=context,
  sample_id="S1", matrix_kind="filtered")
```

The local review page opens and R returns control. Expect an import summary and an unapproved strategy. Raw input keeps all supplied barcodes; import does not perform empty-droplet calling. Check source class, cell counts, feature-key changes and metadata alignment before proceeding.

For multiple samples, replace the call above with one table containing both paths and study facts:

```r
input <- data.frame(sample_id=c("S1", "S2"),
  path=c("counts/control", "counts/treated"),
  matrix_kind=c("filtered", "filtered"),
  donor=c("D1", "D2"), condition=c("control", "treated"))
service <- sc_start(input, project_dir, context=context)
```

Cell IDs become `sample_id::barcode`, so repeated barcodes across samples remain distinct. Optional cell metadata joins by exact sample/barcode keys. Gene Expression feature ID sets must match across samples; no feature intersection or aggregation is applied. See [10x input and sample tables](docs/TENX_INPUT.md) for file/table formats, original feature identity and alignment details.

For an existing RDS containing raw counts or a Seurat object, use:

```r
input <- "a.rds"
service <- sc_start(input, project_dir, context=context)
```

Use a new `project_dir` for each new analysis. Starting from counts reruns basic analysis; [processed-object reuse](workbench/README.md) is an explicit alternative.

### 2. Review the strategy and run basic analysis

Check the displayed study facts, measured QC distributions and projected cell retention. The main entry shows the existing MAD candidates for declared sample/QC groups, with their measured thresholds, retention and unavailable reasons. With no declared group it shows pooled, unstratified evidence. The initial keep-all quality choice avoids deleting uncertain cells without study evidence; `nCount >= 1` only excludes all-zero input, not low-quality cells in general. High counts, ribosomal or haemoglobin expression do not authorize automatic deletion. Raw MEX import is not empty-droplet calling.

The local recommendations use measured low-count/low-feature/mitochondrial flag combinations and exact candidate impacts to propose comparisons. They preserve declared ranges and AND/OR logic, disclose equivalent or conflicting choices, and do not rank universal QC policies. Keep-all remains a comparison or explicit deferral, not a completed quality assessment. Edit the candidate or ranges and inspect their impact before approval.

The initial PC policy requests at most 50 components, with a visible smaller request for the proposed cell/feature scope, and suggests the first leading PCs reaching 80% **within the first at most 50 actually computed PCs**. The denominator is their variance sum, not total HVG or transcriptome variance. Before PCA, the panel shows a rule awaiting computation; after PCA it offers the saved actual 80%/85% crossings. An explicit author-selected fixed PC policy is retained. Inspect the computed count, shortfall, exact denominator and candidate status; a one-PC or numerically rank-deficient choice is rejected, not silently repaired. This empirical rule is editable and does not establish an optimal PC count.

Where supported, correct the declared study facts and their source in the recommendations panel. **Saving facts does not approve a scientific plan.** Missing optional doublet/batch facts or dependencies leave that path unavailable; supported work can proceed with it unexecuted, and the result records the unresolved assessment. An unsupported operation already selected in the plan still needs revision.

**Use candidate in local draft** changes the editable draft only. Save the complete strategy to rebuild the exact R review, inspect the updated evidence, then choose **Approve and continue**. The main entry requests a bounded resolution grid. After computing it on the same cells, PCs, neighbour graph and seed, the worker returns to the strategy review with a cluster tree, marker contrasts and sample composition. Edges show shared cells between parameter choices; this is not a lineage tree. Adjacent ARI describes parameter sensitivity, not resampling stability or biological accuracy. Candidate explanations expose marker gaps, sample concentration, splits/merges and equivalent memberships. They supply no combined optimality score or universal winner; 0.5 remains provisional.

With the default raw resolution scan, the three scientific approvals are the **initial complete strategy**, the **measured resolution selection**, and the **annotation proposal**. Select an actually scanned resolution, save any edit to rebuild its review, then approve the measured strategy and continue. This binds final memberships and markers to your choice before annotation preparation. A model may help compare the saved evidence only through the existing exact request approval; it is optional and the default makes no model request. You can close the page and reopen the same project later.

### 3. Prepare and review annotations

Open the annotation worksheet. Each row shows a saved cluster's markers and any configured local reference candidates. Conflicts and missing evidence are flagged; detailed statistics and provenance expand in place.

Enter a label, qualitative confidence, evidence-based rationale and supporting supplied markers for each population. Explicitly selecting a reference candidate can copy its label and same-cluster citations into an untouched row; confidence and interpretation remain yours. Coverage is overlap, not a probability. Use a coarse label or **Unknown** when the evidence is insufficient. The bulk Unknown action requires an entered reason and preserves edited rows.

Choose **Save complete proposal**, inspect all populations together, then **Approve annotation and continue**. Saving a draft does not apply labels. Expect the completed state and result page after approval. A model is optional; the manual path requires no provider. See [annotation assistance](docs/ANNOTATION_ASSISTANCE.md) and [configured model requests](docs/UNIFIED_MODEL_REVIEW.md) for details.

### 4. Retrieve the result

In the same R library environment:

```r
result <- sc_result(project_dir)
Seurat::DimPlot(result, reduction="umap", group.by="sc_annotation", label=TRUE)
table(result$sc_annotation)
sc_open(project_dir)$view$output
```

`result` is the saved final Seurat object, loaded after its recorded file-integrity checks, ready for research-specific follow-up. The project directory also holds markers, metadata, parameters, figures and decision records. Before annotation is complete, `sc_result(project_dir, stage="analysis")` explicitly returns the provisional analysis object.

### 5. Reopen and continue

Use the same package/dependency environment. Repeat the relevant input call with the same project and original inputs/options, omitting context to reuse saved facts:

```r
# For the single-directory example:
sc_start("filtered_feature_bc_matrix", project_dir,
  sample_id="S1", matrix_kind="filtered")
# For the sample-table example: sc_start(input, project_dir)
# For the RDS example: sc_start("a.rds", project_dir)
```

The page shows the saved stage; reopening does not approve or rerun it. Keep the original input binding unchanged for this entry. To inspect saved results independently of the original source location, use `sc_open(project_dir)`, `sc_result(project_dir)`, or `sc_run_open(project_dir)` for the read-only browser.

## More detail

- [R-only protocol with public PBMC3k](docs/R_ANALYSIS_PROTOCOL.md)
- [10x MEX, sample tables and keyed cell metadata](docs/TENX_INPUT.md)
- [Analysis strategy and supported methods](docs/ANALYSIS_STRATEGY_SUPPORT.md)
- [Annotation evidence and decisions](docs/ANNOTATION_REVIEW.md)
- [Browser and remote server setup](workbench/README.md)
- [Researcher protocol — 中文](docs/RESEARCHER_PROTOCOL_ZH.md)
- [Documentation index](docs/README.md)

R help: `?sc_start`, `?sc_analyze`, `help(package="scAgentKit")`.

[Version history](NEWS.md) · [License](LICENSE.md)
