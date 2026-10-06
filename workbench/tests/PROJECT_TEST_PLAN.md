# Portable project and review round-trip acceptance

The R package exports a verified evidence project from an explicitly selected
Seurat object or prepares a copy from genuine counts. The optional local GUI
reviews that project. R validates the exported review journal against the
original object before returning a copy with new metadata columns.

Project identity, source fingerprint and bundle digest serve different purposes.
The source fingerprint covers exact cell/gene IDs, selected assay/layer values
and membership. It survives reordering and equivalent sparse representations;
it changes when the relevant source changes. The bundle digest covers the
evidence snapshot. Existing annotations are source context, and accepted is a
human workflow status rather than a biological truth claim.

## Prerequisites and artifact boundary

Use Python 3.9+, an existing R installation with the package dependencies,
and an existing Chrome/Playwright/Node installation for browser QA. The runtime
GUI needs neither Node nor an active R session. These commands install nothing
and make no model request. Keep outputs outside the repository in a fresh
directory; none of the tests use the live workbench journals or browser profile.

The real PBMC test requires the frozen processed 2,638-cell Seurat object and
phase-one evidence root. They are local inputs, excluded from Git. The independent
synthetic fixture uses 120 cells, 1,000 genes and literal string cluster IDs,
including `001`, `1`, `NA`, `B alpha` and Chinese text. It has no model records.
The counts-only fixture contains 60 cells and 500 genes; explicit preparation
must retain its two deliberately low-count cells. Synthetic measurements and
authored markers exercise mechanics, not biological accuracy.

Set the following to existing local installations and inputs:

```sh
SCAGENTKIT_REPO=$(pwd)
SCAGENTKIT_R_LIBRARY=/path/to/existing/R/library
SCAGENTKIT_PBMC_RDS=/path/to/frozen/scagentkit_fixed_seurat.rds
SCAGENTKIT_RESULTS_ROOT=/path/to/frozen/phase1/results
SCAGENTKIT_NODE=/path/to/node
SCAGENTKIT_PLAYWRIGHT=/path/to/playwright
SCAGENTKIT_CHROME=/path/to/chrome
SCAGENTKIT_QA_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/scagentkit-project-qa.XXXXXX")
```

On the development Mac the already installed QA tools are:

```sh
SCAGENTKIT_NODE=/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node
SCAGENTKIT_PLAYWRIGHT=/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright
SCAGENTKIT_CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
```

Do not put credentials, `Documents/API.R`, truth tables, model response dumps,
matrices, RDS files, exported projects or screenshot reports into Git. Inspect
permissions and licenses separately before sharing any data artifact. Tests do
not use Sites, Library, external APIs or the user's browser profile.

## Generate portable fixtures and run the real browser loop

From the repository root, generate a new fixture directory. This script reads
the supplied PBMC RDS without modifying it and creates independent synthetic
objects. Explicit preparation and its requested/effective parameters remain in
the exported project.

```sh
Rscript --vanilla workbench/tests/create_project_fixtures.R \
  --output "$SCAGENTKIT_QA_ROOT/fixtures" \
  --r-library "$SCAGENTKIT_R_LIBRARY" \
  --pbmc-rds "$SCAGENTKIT_PBMC_RDS"

"$SCAGENTKIT_NODE" workbench/tests/browser_project.mjs \
  --fixtures "$SCAGENTKIT_QA_ROOT/fixtures" \
  --output "$SCAGENTKIT_QA_ROOT/browser-project" \
  --r-library "$SCAGENTKIT_R_LIBRARY" \
  --pbmc-rds "$SCAGENTKIT_PBMC_RDS" \
  --playwright "$SCAGENTKIT_PLAYWRIGHT" \
  --chrome "$SCAGENTKIT_CHROME"
```

The harness owns an ephemeral loopback server, private cache/journals and a new
headless Chrome profile. It blocks non-loopback browser requests and stops its
server on exit. It imports a relocated project ZIP, switches projects, makes
reasoned decisions, undoes them, refreshes, exports/imports actual browser
downloads, and invokes R against those exact downloaded journals.

`project-browser-report.json`, screenshots, downloaded journals and
`r-writeback-*.json` are retained in the fresh output directory. The R oracle
independently replays active human decisions and checks each cell by literal ID,
including the type/state/QC dimensions. The real PBMC review checks all 2,638
cells, with the accepted unknown confined to cluster 6's exact 155-cell set.

| Round-trip observation | Required evidence |
| --- | --- |
| Real and independent input | PBMC 2,638 cells/9 clusters; synthetic 120 cells/1,000 genes; no project-specific source edit |
| Exact IDs | `001` differs from `1`; literal `NA` is valid while actual missing membership rejects |
| Honest missing evidence | No embedding remains unavailable; zero model calls stay `not_run`; source annotations do not become human decisions |
| Scope and selection | List/embedding selection yields the same exact cluster cell set; dimensions remain separate |
| Applicable RNA panel | Only explicitly selected clusters expose the exported panel; missing genes remain unavailable and measured zeros remain zeros |
| Review boundary | Execute/adopt prepares a draft; an explicit reason and Record are required; existing accepted human decisions survive |
| Human outcomes | Accepted label, accepted unknown, deferred proposed/reviewed and unreviewed remain distinct |
| Durable history | Repeated activation is idempotent; undo appends a compensation; original envelopes and immutable artifacts are retained |
| Portability | Relocation, browser refresh, server restart and export/import preserve project identity and complete journal history |
| Two browser tabs | Reads, directed evidence, writes and exports remain bound to each tab's own project despite another tab changing selection |
| Counts-only preparation | All 60 cells survive, including the low-count cells; the GUI displays the genuine computed embedding and preparation parameters |
| R writeback | Every cell maps by ID; only active accepted labels write; original metadata, factor levels/NA, Idents, assays, reductions and wrapper history survive |
| Local rendering | Supplied names/model text render literally; no page errors, remote assets or external browser requests |
| Stale or corrupt input | Changed project bytes/source or damaged history cannot silently apply; original journals remain preserved/read only |

## Twelve rejection and invariance gates

The R tests, independent R oracle, Python tests and browser suite jointly cover
these gates. Rejection must leave the input object, source evidence and saved
journal unchanged. Cell/gene permutation and equivalent dense/sparse matrices
are positive controls and must pass exact ID-based writeback.

| Gate | Expected behavior and coverage |
| --- | --- |
| 1. Wrong object with the same barcodes | Changed genuine counts reject by source fingerprint; R review tests and browser-triggered R oracle |
| 2. Changed normalized measurements or features | Changed selected data values or gene IDs reject; R identity/review tests |
| 3. Changed membership | Same cells moved between clusters reject; R review tests and independent oracle |
| 4. Incomplete or duplicate scope | Missing/extra/duplicate cells, duplicate genes, unsorted or mismatched event cell sets reject; R/Python tests |
| 5. Missing or ambiguous source | Absent/split layers, default-assay subsets or actual missing membership reject; no silent layer join, counts substitution or membership repair |
| 6. Invalid counts or renamed IDs | Negative, fractional or non-finite counts and duplicate matrix IDs reject before Seurat construction; no implicit feature renaming |
| 7. Column conflict | Label or companion-name collision rejects the whole write before mutation; R review tests and oracle |
| 8. Invalid workflow or history | Unknown dimensions/statuses, duplicate IDs/request conflicts, dangling supersedes/undo, altered envelopes or rehashed invalid scopes reject |
| 9. Invalid JSON or schema | Duplicate decoded keys, object/array confusion and unknown journal/project versions reject; legacy PBMC journals cannot acquire generic writeback identity |
| 10. Invalid directed artifact | Wrong source fingerprint, cluster/cell scope, checksum, non-finite values or unavailable-as-zero fabrication reject |
| 11. Unsafe project archive | Traversal, absolute/drive paths, duplicate or case-colliding members, symlinks, unlisted files and bad checksums reject before promotion |
| 12. Excessive or changed input | ZIP ratio/size or HTTP upload limits reject; changed cached bytes/source mark stale or read only; two-tab writes cannot cross projects |

The hash chain detects corruption and inconsistent edits. It is not a digital
signature and does not authenticate a deliberately rewritten journal by its
local owner.

## Python and R regression checks

Run the generic Python suite independently of private PBMC inputs:

```sh
python3 -B -m unittest discover -s workbench/tests -p 'test_project*.py' -v
```

For the full Python suite supply the frozen legacy evidence and previously
verified phase-three expression export. That expression directory contains
`expression.json` and `manifest.json`; it is an external fixture, not a new
model request. Without the real fixtures some legacy checks intentionally skip;
that does not constitute complete real-data regression acceptance.

```sh
SCAGENTKIT_EXPRESSION_ROOT=/path/to/verified/phase3-expression-directory

SCAGENTKIT_TEST_RESULTS="$SCAGENTKIT_RESULTS_ROOT" \
SCAGENTKIT_RESULTS="$SCAGENTKIT_RESULTS_ROOT" \
SCAGENTKIT_TEST_EXPRESSION="$SCAGENTKIT_EXPRESSION_ROOT/expression.json" \
SCAGENTKIT_EXPRESSION_DIR="$SCAGENTKIT_EXPRESSION_ROOT" \
SCAGENTKIT_TEST_RDS="$SCAGENTKIT_PBMC_RDS" \
R_LIBS_USER="$SCAGENTKIT_R_LIBRARY" \
python3 -B -m unittest discover -s workbench/tests -v
```

Build/check the R package from a temporary directory to keep generated archives
and check outputs outside Git. The workbench is excluded from the R package
build. Dependencies must already be installed; this command performs no install.

```sh
(
  cd "$SCAGENTKIT_QA_ROOT"
  R_LIBS_USER="$SCAGENTKIT_R_LIBRARY" \
    R CMD build --no-build-vignettes "$SCAGENTKIT_REPO"
  R_LIBS_USER="$SCAGENTKIT_R_LIBRARY" _R_CHECK_FORCE_SUGGESTS_=false \
    R CMD check --no-manual --ignore-vignettes scAgentKit_*.tar.gz
)
```

The phase-four local package check passed with `Status: OK` and 1,095 testthat
assertions, zero failures/warnings/skips. It used `--ignore-vignettes`; vignette
execution and PDF manuals were not verified. Missing optional suggested
packages were reported as information with `_R_CHECK_FORCE_SUGGESTS_=false`.
A check with normal vignette execution requires the existing optional tools and
vignette dependencies and should be recorded separately.

Retain the original real-data GUI tests using new artifact directories:

```sh
"$SCAGENTKIT_NODE" workbench/tests/browser_smoke.mjs \
  --results-root "$SCAGENTKIT_RESULTS_ROOT" \
  --output "$SCAGENTKIT_QA_ROOT/browser-legacy" \
  --playwright "$SCAGENTKIT_PLAYWRIGHT" --chrome "$SCAGENTKIT_CHROME"

"$SCAGENTKIT_NODE" workbench/tests/browser_directed.mjs \
  --results-root "$SCAGENTKIT_RESULTS_ROOT" \
  --directed-source "$SCAGENTKIT_PBMC_RDS" \
  --r-library "$SCAGENTKIT_R_LIBRARY" \
  --output "$SCAGENTKIT_QA_ROOT/browser-directed" \
  --playwright "$SCAGENTKIT_PLAYWRIGHT" --chrome "$SCAGENTKIT_CHROME"
```

The directed harness copies the RDS before its stale-input test. The smoke
harness copies its evidence allowlist. Both mutate only their own copies and
retain independent reports/screenshots. Existing phase-two/three live sessions
and all frozen input files must remain unchanged.
