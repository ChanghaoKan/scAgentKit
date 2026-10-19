# scAgentKit

**English** · [简体中文](README.zh-CN.md)

scAgentKit is designed to help researchers with a biological background spend less time maintaining a single-cell RNA-seq workflow. Starting from counts and sample facts or an RDS file containing counts/Seurat, it guides QC, basic analysis and annotation through a saved, reviewable project.

You receive a new Seurat object with counts, sample metadata, reductions and reviewed labels, plus marker tables, figures and the evidence and reasons behind decisions. QC, integration and clustering still require study judgement; default settings are starting points. FASTQ processing is upstream. Research-specific trajectory, communication and regulatory-network analyses are downstream and are not run automatically.

## Analysis workflow

<img src="docs/diagrams/project-analysis-flow.svg" alt="Development raw-count workflow: automatic local analyses pause for strategy, measured clustering and annotation approvals; optional paths are explicit" width="1000">

[English diagram](docs/diagrams/project-analysis-flow.svg) · [中文流程图](docs/diagrams/project-analysis-flow.zh-CN.svg) · [Diagram source](docs/diagrams/generate_project_flow.py)

This diagram describes the **fixed-commit developer preview**, installed separately below.
The published v0.6.0 archive uses the [two-approval release protocol](docs/RELEASE_060_PROTOCOL.md);
it does not include the preview's default measured-clustering gate or new controls.

### What runs automatically, and where you decide

Automatic local work validates counts/metadata, measures QC and prepares evidence.
After you approve the plan, it runs the approved analyses and the ordinary resolution
scan/tree. It pauses at three separate scientific decisions:

| Gate | Inspect these figures and evidence | Your decision |
| --- | --- | --- |
| [**1. Initial strategy**](#gate-strategy) | QC distributions, sample/group comparisons, candidate cell retention and proposed PC/method rules. Actual PCA is still pending. | Choose QC and the complete analysis plan; **Save**, inspect the updated review, then **Approve and continue**. |
| [**2. Measured clustering**](#gate-clustering) | Computed PC curve/crossings, cluster tree, marker contrasts and sample composition. Tree edges show shared cells, not lineage. | Select an **actually scanned resolution**. Save any edit, review it and independently approve before final membership/markers are bound. |
| [**3. Annotation**](#gate-annotation) | Cluster markers, applicable mean/pct panels, reference support/provenance, conflicts and missing evidence. | Supply labels or **Unknown**, confidence and reasons. **Save complete proposal**, inspect all populations, then **Approve annotation and continue**. |

After the third approval, the project writes the new Seurat object and exports.
Saving a draft, correcting facts or reopening a project does not grant approval.
Automation executes your recorded choices; it does not establish biological truth.

Optional methods need explicit selection and suitable inputs. PC k±5, resampling,
extra resolution extension, sample-consensus HVGs and experimental QC draft
preselection are off by default; the ordinary scan/tree remains part of the raw
workflow. Model requests need separate exact-transfer consent. SoupX/decontX are
**separate R-only APIs** that return corrected counts for a new project, with no
browser correction action and no replacement of original counts/checkpoints.
See the [methods and limits](docs/SCIENTIFIC_METHODS_APPENDIX.md) and
[operator guide](docs/SCIENTIFIC_REVIEW_QUICKSTART.md) for detail.

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

## Developer preview

The published v0.6.0 default uses **two approvals**; follow the
[matching release protocol](docs/RELEASE_060_PROTOCOL.md). The diagram and steps
below instead describe the **unreleased fixed-commit preview** at `265e3263c8fa0ee9fff5bf019ceb270d08530350`.
No preview release archive is published. Its package version still reads
0.6.0, so record the source commit as well as the dependency environment.

For the preview, first prepare the release dependencies above. In a separate
source directory, fetch and check out this exact commit:

```sh
git clone --no-checkout https://github.com/ChanghaoKan/scAgentKit.git scagentkit-preview-source
git -C scagentkit-preview-source checkout --detach 265e3263c8fa0ee9fff5bf019ceb270d08530350
```

In a **fresh R session**, install that source into a separate private library
using the already prepared dependencies, then execute the public small-data
three-gate software tutorial:

```r
preview_sha <- "265e3263c8fa0ee9fff5bf019ceb270d08530350"
source_dir <- normalizePath("scagentkit-preview-source", mustWork=TRUE)
stopifnot(identical(system2("git", c("-C", shQuote(source_dir), "rev-parse", "HEAD"),
  stdout=TRUE), preview_sha))
preview_lib <- path.expand("~/R/scagentkit-preview-library")
dir.create(preview_lib, recursive=TRUE, showWarnings=FALSE)
.libPaths(c(preview_lib, path.expand("~/R/scagentkit-library"), .libPaths()))
remotes::install_local(source_dir, lib=preview_lib,
  dependencies=FALSE, upgrade="never", build=FALSE)
library(scAgentKit, lib.loc=preview_lib)
stopifnot(identical(normalizePath(find.package("scAgentKit")),
  normalizePath(file.path(preview_lib, "scAgentKit"))))
source(system.file("examples", "three-gate-analysis.R", package="scAgentKit"))
checked <- three_gate_analysis(tempfile("scagentkit-three-gates-"))
checked$receipt
```

The receipt must report `complete`, three approval kinds (strategy, strategy,
annotation), 80 cells and zero provider calls. This fixture retains the ordinary
resolution scan; its limited PCs/features, disabled UMAP and Unknown labels are
explicit software controls, not study recommendations. Keep the old project's
original environment; use new directories for this preview. See the
[English operator guide](docs/SCIENTIFIC_REVIEW_QUICKSTART.md) and
[three-gate R protocol](docs/R_ANALYSIS_PROTOCOL.md).

## Analysis protocol

This section requires the fixed preview above. Before the first `sc_start()`, choose
manual or model-assisted initialization. The default creates a manual project:
no provider, zero model budget; you supply labels and confidence. To use a model,
initialize its provider/model/settings/budget with `sc_analyze()` or `sc_run()`
first, following [configuration and consent](docs/UNIFIED_MODEL_REVIEW.md#what-remains-in-the-starting-r-call),
then reopen that saved input with `sc_start(..., model_suggestions="configured")`.
Those settings are immutable; the browser cannot add a provider to a manual project.

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

For an existing RDS file containing raw counts or a Seurat object, use the file path
(`sc_start()` does not accept an in-memory Seurat object):

```r
input <- "a.rds"
service <- sc_start(input, project_dir, context=context)
```

Use a new `project_dir` for each new analysis. Starting from counts reruns basic analysis; [processed-object reuse](workbench/README.md) is an explicit alternative.

New raw strategy projects keep ordinary normalization/global-vst HVGs/PCA, the internal 80% PC policy, the ordinary resolution scan and cluster tree. PC k±5, 80% resampling, extra resolution extension, sample-consensus HVGs and automatic QC draft preselection are off until explicitly enabled. Applicable sample QC, elbow, citation direction and Fisher/BH evidence remain available. Classic mean/detection panels default to explicitly declared human blood/PBMC or pancreas; unsupported declarations and absent genes stay unavailable/missing, never guessed. Cross-sample/mixed-lineage expression extensions remain opt-in. SoupX/decontX stay separate optional R-only calls. See the [default and opt-in guide](docs/SCIENTIFIC_REVIEW_QUICKSTART.md).

### 2. Review the strategy and run basic analysis

<a id="gate-strategy"></a>

At **gate 1**, check study facts, measured QC distributions and projected cell
retention, grouped by sample/QC role when declared. Missing roles stay pooled or
unavailable. The initial keep-all quality choice does not certify QC; `nCount >= 1`
only removes all-zero input. High counts, ribosomal or haemoglobin expression do
not authorize automatic deletion, and raw MEX import is not empty-droplet calling.

**Use candidate in local draft** changes the draft only. Save the complete plan,
inspect the rebuilt evidence, then approve. Saving facts is also separate from
scientific approval. Missing optional doublet/batch facts or dependencies leave
that path unexecuted and disclosed; a selected unsupported method needs revision.

<a id="gate-clustering"></a>

The approved foundation runs locally, then the ordinary resolution scan pauses
at **gate 2**. Inspect the computed PC evidence, tree, marker contrasts and sample
composition; choose an actually scanned resolution, save changes and approve the
measured strategy. Neither the PC rule nor the resolution comparisons identify a
biological optimum. Model assistance is optional and the default makes no request.
You can close the page and reopen the same project later. Method definitions and
boundaries are in [analysis strategy support](docs/ANALYSIS_STRATEGY_SUPPORT.md)
and the [methods appendix](docs/SCIENTIFIC_METHODS_APPENDIX.md).

### 3. Prepare and review annotations

<a id="gate-annotation"></a>

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

- [English operator guide](docs/SCIENTIFIC_REVIEW_QUICKSTART.md)
- [Version-matched v0.6.0 protocol](docs/RELEASE_060_PROTOCOL.md)
- [R-only preview protocol with public PBMC3k](docs/R_ANALYSIS_PROTOCOL.md)
- [10x MEX, sample tables and keyed cell metadata](docs/TENX_INPUT.md)
- [Analysis strategy and supported methods](docs/ANALYSIS_STRATEGY_SUPPORT.md)
- [Annotation evidence and decisions](docs/ANNOTATION_REVIEW.md)
- [Browser and remote server setup](workbench/README.md)
- [Researcher protocol — 中文](docs/RESEARCHER_PROTOCOL_ZH.md)
- [Documentation index](docs/README.md)

R help: `?sc_start`, `?sc_analyze`, `help(package="scAgentKit")`.

[Version history](NEWS.md) · [License](LICENSE.md)
