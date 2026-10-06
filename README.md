# scAgentKit

Start with `sc_run(input, project_dir, context = ...)` on the machine holding
your data. Inspect the saved evidence and typed proposals, approve a specific
version, then resume. Checkpoints, decision history, tables, figures and a new
Seurat object stay on that machine. A browser is optional; routine analysis
needs no manual RDS transfer or ZIP export/import.

**[中文研究者操作协议：安装、公开 PBMC 练习、自己的数据、AI、网页与服务器](docs/RESEARCHER_PROTOCOL_ZH.md)**

This is the experimental `0.5.0.9000` development version. Successful execution,
AI suggestions and marker-reference agreement do not establish optimal QC or
biological identity. No provider, no external-transfer permission and zero
budget are the defaults.

## Install the development version

Use a separate R library. R >= 4.2, Seurat >= 5, SeuratObject, Matrix and
agentomicsCore >= 0.1.1 are among the dependencies in [DESCRIPTION](DESCRIPTION).
The basic route needs Imports/Depends, not every optional algorithm in Suggests.

```r
private_lib <- path.expand("~/R/scagentkit-preview-library")
dir.create(private_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(private_lib, .libPaths()))
if (!requireNamespace("remotes", quietly = TRUE))
  install.packages("remotes", lib = private_lib, repos = "https://cloud.r-project.org")
remotes::install_github("ChanghaoKan/scAgentKit@main", lib = private_lib,
  dependencies = c("Depends", "Imports"), upgrade = "never", build = FALSE)
library(scAgentKit, lib.loc = private_lib)
packageVersion("scAgentKit")
packageDescription("scAgentKit")$RemoteSha  # record the installed source
```

`main` can change: pin a verified full commit SHA for repeatable installation.
Keep the same implementation/library when resuming a project. The protocol
separates declared minimums, measured Mac versions and historical Linux checks;
your HPC environment is not assumed tested. Python is needed only for the
optional checkout-based web service.

## First complete run: public PBMC, offline mock

The installed tutorial uses genuine sparse counts in the public
[SeuratObject `pbmc_small` fixture](https://satijalab.github.io/seurat-object/reference/pbmc_small.html)
(230 genes, 80 cells; a PBMC3k subset). Its permissive QC, five PCs, resolution
and `Unknown` labels are software controls, **not study recommendations**.
It makes no API request and assumes no donor/capture information.

```r
source(system.file("examples", "researcher-pbmc.R", package = "scAgentKit"))
project_dir <- file.path(getwd(), "public-pbmc-first-project")  # new durable directory
mock <- make_researcher_pbmc_mock()
run <- researcher_pbmc_start(project_dir, mock)

view <- researcher_pbmc_inspect(project_dir)
view$strategy_review$details  # read QC/analysis and expected retention
researcher_pbmc_decide(project_dir, view, reviewer = "tutorial-reviewer",
  reason = "Reviewed the public fixture and software-control plan.")
run <- researcher_pbmc_resume(project_dir, mock)

view <- researcher_pbmc_inspect(project_dir)
view$annotation_review$details  # inspect markers and unresolved mock labels
researcher_pbmc_decide(project_dir, view, reviewer = "tutorial-reviewer",
  reason = "Retain Unknown/low; this tutorial makes no identity claim.")
done <- researcher_pbmc_resume(project_dir, mock)
stopifnot(identical(done$status, "complete"))
final_object <- readRDS(done$output$seurat)
done$output
```

Approval saves a decision; the separate resume executes approved work. R may
exit at either review point. Another process can inspect/resume the same
directory; attach an in-memory callback again for new requests. Reinspect after
any revision. Do not automatically approve proposals for private data.

## Your matrix, Seurat object or local RDS

Provide genuine named genes × cells raw counts, a Seurat object or its local
RDS path. Explicitly select ambiguous layers; normalized/scale layers are not
counts. Declare only metadata roles that actually exist and have been checked:

```r
context <- list(species = "human", tissue = "Peripheral blood",
  columns = list(sample = "sample_id", capture = "capture_id",
                 donor = "donor_id", condition = "condition"),
  research_goal = "State the question being studied.",
  notes = "Describe processing, enrichment and limitations; mark unknowns.")
run <- sc_run(seu, "/durable/path/to/new-project", context = context,
  strategy = TRUE, provider = NULL, budget = 0,
  review = list(allow_external = FALSE), annotation_column = "sc_reviewed_identity")
view <- sc_run_inspect("/durable/path/to/new-project")
```

Replace `seu`, the directory and columns with your actual inputs. A bare matrix
has no study metadata: omit `columns`, or create Seurat and attach verified
metadata by literal cell ID first. Ca/Ctrl is not inferred as batch; capture is
not donor. Without a manual proposal/provider this saves diagnostics and stops
at `awaiting_configuration`.

The [protocol](docs/RESEARCHER_PROTOCOL_ZH.md) shows manual proposals, exact
approval/resume, QC/PC/resolution edits and a processed-Seurat entry that reuses
basic analysis. Batch correction defaults to `none`; optional methods have
explicit applicability and runtime guards.

## Optional AI and web review

DeepSeek/Grok providers read `DEEPSEEK_API_KEY`/`XAI_API_KEY` in the analysis
process; an explicit `chat_fn` is also supported. Keep credentials outside
scripts, objects, bundles, logs and browser fields. Approve the exact aggregate
payload before transmission, then review the scientific proposal separately.
Raw counts and barcodes are excluded from provider payloads; group names and
context can still reveal sensitive information. Budget reservations, usage
holds and cached requests persist. There is no automatic paid retry.
See [AI configuration and consent](docs/RESEARCHER_PROTOCOL_ZH.md#6-配置-ai发送同意与费用).

From a verified source checkout, select the same Rscript/library as analysis:

```sh
python3 -B workbench/server.py --run-project /durable/path/to/project \
  --rscript /absolute/path/to/Rscript --r-library /absolute/path/to/r-library \
  --local-continue --port 8774
```

Open `http://127.0.0.1:8774/workbench`. Without `--local-continue`, compute in R.
Model dispatch is a separate operator opt-in. Server access uses an authorized
SSH tunnel; no public listening, firewall changes or automatic scheduler
submission. [Web/server instructions](docs/RESEARCHER_PROTOCOL_ZH.md#8-同一项目的可选网页与服务器运行)
include supported flags and a scheduler template.

[Annotation/CM2 review](docs/RESEARCHER_PROTOCOL_ZH.md#9-注释复核cellmarker-20-与证据来源)
keeps DB, AI/manual and source evidence visible. CellMarker files are not
bundled; use a verified, permitted local reference and record provenance.
[Child projects](docs/RESEARCHER_PROTOCOL_ZH.md#10-选定子群修正背景保存新的父对象)
support reviewed context corrections and exact-ID labels in a **new** parent
RDS with versioned apply/undo.

The toolkit does not determine the best QC/PC/resolution or cell identity;
it does not offer arbitrary R execution, general literature chat, ambient-RNA
correction or automatic merging of overlapping children.
[Troubleshooting and feedback](docs/RESEARCHER_PROTOCOL_ZH.md#12-常见停点与反馈)
cover saved-state recovery and safe reproductions. Advanced guides and installed
examples remain under `docs/` and `inst/examples/`.
