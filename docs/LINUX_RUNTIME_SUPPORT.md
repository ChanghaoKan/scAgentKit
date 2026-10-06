# Linux runtime support and validation scope

This increment starts from release-candidate commit
`bd8f799da7f51d97b8614399bb5a633176dc4b46` and adds one explicitly audited
doublet-runtime pair. The supported adapter contract and completed execution
evidence are separate. **Final Linux v3 full check is Status OK**, exit 0,
**7379 PASS / 0 FAIL / 0 WARN / 2 runtime-specific SKIP**. Bounded real-method
workflows and a Mac browser-free CLI loop passed. Linux v2 ended with
**2 NOTEs**; it and earlier failures remain retained. Prior Mac/Linux totals
in the [release checklist](RELEASE_CANDIDATE_CHECKLIST.md) remain evidence
for their named versions.

## Declared optional-method combinations

| Method | Accepted runtime | Guard and current evidence |
| --- | --- | --- |
| Modern doublet adapter | Exactly scDblFinder **1.26.7**, with a valid xgboost version **>=3.1** | Existing accepted canonical function hashes and backend floor retained; prior Mac execution remains versioned evidence |
| Additional doublet adapter | Exactly scDblFinder **1.22.0** and xgboost **1.7.11.1** | Three official canonical identities match the current Linux namespace; three real projects plus fresh R verification completed; no other legacy backend/version is accepted |
| Harmony | Audited Harmony **2.0.5** | Fixed official archive privately built/loaded; bounded real workflow completed in four fresh R processes; no integration efficacy claim |

Both doublet adapters require the declared droplet/raw-count, capture, rate and
scoring-applicability inputs. Every capture must complete three audited training
and three prediction successes. Warning, swallowed upstream fallback, changed
function shape, unknown version, incompatible backend or incomplete audit fails
closed. No heuristic doublet scores or guessed release compatibility are used.
The [doublet guide](DOUBLET_REVIEW.md) lists the exact canonical function hashes
and the joint scientific review requirements.

The existing authorized Linux environment has R **4.5.1**, Seurat **5.4.0**,
SeuratObject **5.3.0**, testthat **3.2.3**, scDblFinder **1.22.0** and xgboost
**1.7.11.1**. Its three installed scDblFinder function identities match the
official audited release. The new acceptance does not infer that arbitrary
Linux installations, dependencies or patched namespaces behave identically.

The modern package route inspected in this audit is Bioconductor **3.23** with
the R **4.6** series and newer `scrapper` aggregation APIs. The scDblFinder
DESCRIPTION's direct R floor alone does not establish compatibility with a mixed
R 4.5.1/Bioconductor stack. The current older Linux stack lacks the needed
`scrapper` route; older aggregation signatures differ and a newer dependency
also raises its `beachmat` requirement. This is why the audited existing pair is
accepted explicitly rather than forcing an upgrade of R/Bioconductor or
weakening source guards.

## Official sources and private installation

The retained source audit identifies these exact official archives:

| Archive | SHA256 |
| --- | --- |
| [scDblFinder 1.22.0, Bioconductor 3.21](https://bioconductor.org/packages/3.21/bioc/src/contrib/scDblFinder_1.22.0.tar.gz) | `1af9f77ab7257a021c94fafa82a63982cbcf279707a76a56a146d9388732d622` |
| [xgboost 1.7.11.1, CRAN archive](https://cran.r-project.org/src/contrib/Archive/xgboost/xgboost_1.7.11.1.tar.gz) | `c15b631be77ae17fef46166abffb3336738a812c219d82c601bc70664a88d7c5` |
| [Harmony 2.0.5, CRAN](https://cran.r-project.org/src/contrib/harmony_2.0.5.tar.gz) | `907a3c4808656f6bad5a8e314704f92a0cb159ae298390315d5c73794d9a0c6c` |

These recorded URLs/hashes identify the inspected bytes, not a command to
download a floating latest release. Source and dependency receipts are retained
in the task workspace under `evidence/linux-rc-closure`, including
`deps-audit.json`, the official source receipts and source-shape audit.

Select an isolated private R library for this exact checkout and the approved
optional dependencies. Preserve other active projects' libraries. The Harmony
build in this audit used the fixed official archive and a private library; it
did not update the global library or automatically upgrade Bioconductor. If a
compatible dependency is already available, record its installed path/version
instead of reinstalling everything. A generic latest-version
`BiocManager::install("scDblFinder")` is not a compatibility procedure.

For an already downloaded and verified source archive, the private-library
installation pattern is:

```sh
linux_rc_library=/absolute/path/to/new/private-library
verified_source_archive=/absolute/path/to/verified/package_version.tar.gz
mkdir -p "$linux_rc_library"
R_ENVIRON_USER=/dev/null R_PROFILE_USER=/dev/null R_LIBS_USER="$linux_rc_library" \
  R CMD INSTALL --library="$linux_rc_library" "$verified_source_archive"
```

This is a template, not an instruction to replace the current working runtime.
Install the checkout using the same library as described in the
[release checklist](RELEASE_CANDIDATE_CHECKLIST.md#install-this-checkout-separately-from-the-user-library).
Record the actual R executable, `.libPaths()`, installed package path, source
archive hashes and implementation fingerprint. Build/load success is distinct
from a real algorithm run and a complete check. No source guard may be disabled
to make an incompatible installation appear supported.

## Saved evidence and historical compatibility

New doublet evidence stores the exact scDblFinder/xgboost pair, canonical source
hashes and each capture's fit/predict audit. Reviewing completed evidence uses
that saved provenance; it does not choose hashes from whatever optional package
is installed in the reviewing process, and it does not refit the classifier.

An older record without the explicit adapter-pair field is accepted only when
its saved versions identify scDblFinder **1.26.7** and a valid xgboost **>=3.1**,
with the expected hashes and successful audits. Missing/unknown versions or an
unversioned legacy record require regeneration and fresh review. An explicitly
unexecuted unsupported record stays unsupported: it cannot claim classifier
execution or invented source identities. Installing a supported pair does not
automatically migrate old approvals, repair changed inputs or override a changed
implementation fingerprint.

## Current execution checkpoint

| Evidence | Actual scope at this checkpoint |
| --- | --- |
| Linux runtime/source preflight | R 4.5.1, Seurat 5.4.0/Object 5.3.0 and accepted legacy pair observed; official canonical identities matched; private Harmony 2.0.5 installed |
| Baseline `bd8f799` diagnostic | 46/51 files completed; 4595 passing assertions, zero failures/errors/warnings, two skipped blocks; five 120-second integration-file timeouts. Partial coverage, not a successful full check |
| Current test driver | Actual testthat 3.2.3 reporter behavior checked; diagnostic explicitly clears `R_TESTS`; old timeout cause remains unestablished |
| Prior failed attempts | First Mac: 7387 PASS/3 FAIL/1 SKIP; first Linux: 7376 PASS/3 FAIL/2 SKIP. Same stale fixture-version assertions, corrected only in the test. Source-cache preflight rejection and first legacy-helper canonical-order assertion also retained |
| Mac v2 full R check | Status OK; 7390 PASS/0 FAIL/0 WARN/1 SKIP; 491.581 s. Legacy genuine acceptance skipped on modern 1.26.7/3.2.1.1 runtime; four unavailable optional Suggests are INFO |
| Linux v2 full R check | exit 0; 1350.359 s; 7379 PASS/0 FAIL/0 WARN/2 SKIP (modern 1.26.7 genuine checks); **Status: 2 NOTEs** for hidden .gitignore and nonstandard CITATION.cff; sealed source unchanged/read-only |
| Linux v2 Python | 300 total: 284 passed, 16 skipped, zero failures/errors; skips require external real-evidence/expression fixtures or an Rscript-unavailable case |
| Actual legacy doublet workflow | Three new projects and fresh R verification passed: public 2700→2511; synthetic A/B each 440→438, literal captures each 220→219; per-capture 3 successful fits/3 predictions, exact joins, old annotations and durable no-op resume |
| Actual Harmony 2.0.5 workflow | Four fresh R modes passed, 120→119 cells, harmony neighbors and manual Unknown; later aggregate reused these unchanged receipts without rerunning Harmony |
| V3 packaging change | Only .Rbuildignore adds `^\.gitignore$`; all other 341 source files, production and tests match v2. New runner builds a mutable byte-exact copy while sealing reference source, checking built flags before the long full check |
| Mac v3 packaging | Status OK/exit 0/18.541 s with --no-tests; this did not rerun the 7390 full-suite assertions |
| Linux v3 final check | **Status OK**, exit 0 / 1325.37 s; 7379 PASS/0 FAIL/0 WARN/2 SKIP. Exact 52 tests and standard runner, forbidden metadata absent, all five stages passed; source/sealed reference/mutable build copy unchanged |
| Linux v3 Python | 300 total: 284 passed/16 skipped/0 failures/errors; 97.39 s (98.043 s wrapper). Explicit real-fixture omissions and isolated unavailable Rscript are recorded |
| First Linux independent diagnostic | Complete 52 files/427 blocks, 7376 PASS/3 FAIL/0 errors/warnings/2 SKIP in 1452.367 s; same retained stale fixture failures, not a passing run |
| Mac browser-free CLI | Seven fresh R commands plus corrected fresh verification passed; 180→172 synthetic cells, Unknown new columns, exact raw counts/cell order/old annotations and no-provider durable resume. First helper path failure retained; no source/example change |
| Scheduler/HPC, Windows and other sites | Not established; templates and one existing Linux environment do not prove broader deployment support |

V2 checked all 342 source files (52 R test files), canonical manifest
`07422fc6fc2360a5098a8b314528302e0f093bac95cce3e938af9c4c05dfd4a8`.
V3 packaging canonical manifest is
`42e315b27fb0e779456710023608af95db25bf2248a887abdeea48f8c664884b`;
the 52-test-file manifest is unchanged. Exact checked source is local commit
`21e451bef0dbc137c9251da5aaafc4385d6d3346`. Full checks used --no-manual and
--ignore-vignettes. Mac v3 additionally used --no-tests and did not repeat
the Mac full suite. Linux runtime skips are the two modern-pair genuine
tests at test-run-doublet-engine.R:265:3 and :352:3: installed 1.22.0,
while 1.26.7 is required. The legacy genuine test ran. The sole missing optional
Suggests package is ontologyIndex, reported as INFO, not warning/NOTE, in the
actual `linux-v3-skip-detail-observed.json` receipt. Python skips retain their 3 frozen-evidence, 1 paired-evidence,
2 cache, 1 isolated-Rscript and 9 real-expression fixture reasons. Receipts
are under `evidence/linux-rc-closure`, notably the combined `linux-v3-final-accepted.json`,
`actual-linux-final-observed.json` and `headless-cli-mac-verify-v2/summary.json`.
Incremental model calls/cost are zero; prior conservative occupancy remains
US$0.07910195. This closure read no credential file and wrote no keys.

The diagnostic checkpoint and final acceptance have separate source/runtime
receipts. A successful test-file prefix is not a successful suite. Failed,
interrupted or timed-out reports remain alongside later results; final receipts
must identify actual omissions, warnings/INFO/skips, selected library and source
equivalence rather than replacing those reports with a passing claim.

This work makes no model API call or biological calibration claim. Scores remain
algorithm predictions rather than calibrated doublet probabilities, and source
or software validation does not establish cell identity or treatment preservation.
