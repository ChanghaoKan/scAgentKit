# Local synthetic scaling check (2026-10-16)

The scripts use only installed local dependencies and deterministic synthetic
counts; they never download data, configure providers, or call a model. The
fixture fixes 1,000 genes and exactly 20 detected genes per cell (2% density),
with three supplied clusters, normalized values and an existing 2-D reduction.
This measures data handling, not analysis quality or biological scale limits.

Run from the repository root with a new empty output directory:

```sh
R_LIBS=../r-library-performance:/path/to/dependency-library \
  Rscript benchmark/local_performance.R ../evidence/performance-optimized
python3 -B benchmark/local_performance_web.py ../evidence/performance-optimized \
  /absolute/path/to/private-library:/absolute/path/to/dependency-library
```

The R script supports an optional second argument containing an older
`project-export.R` to compare export implementations, and an optional third
argument such as `10000` or `1000,5000,10000` to select sizes. All other calls use
the installed package. Keep each installed package fixed while its projects
are inspected: implementation fingerprints intentionally bind approvals.

## Measured Mac results

Export operations are single measurements; read operations are medians of
three repetitions. Concurrent task activity and cold package loading can add
noise. Baseline is the original exporter before ID alignment; revised output
was byte-for-byte identical for every manifest, project JSON and directed JSON
at all three scales. Existing exporter tests (228 assertions) and the new
shuffled-ID test (51 assertions) passed, with zero failures or skips.

| Cells | Export before / after (s) | One-cluster directed export before / after (s) | Complete R inspect (s) | Open saved result via Python + fresh R (s) | List one child (s) |
|---:|---:|---:|---:|---:|---:|
| 1,000 | 0.209 / 0.194 | 2.084 / 1.388 | 0.130 | 1.618 | 0.331 |
| 5,000 | 1.141 / 0.933 | 13.209 / 5.910 | 0.164 | 1.651 | 0.511 |
| 10,000 | 2.992 / 1.790 | 37.950 / 11.394 | 0.194 | 1.772 | 0.691 |

Verified portable-bundle loading alone took 0.005 / 0.026 / 0.052 seconds.
Fresh result opening used `RunWorkbenchRuntime.describe()`, including the R
bridge and verified evidence projection; it excludes browser rendering,
HTTP and network time. Python peak RSS reached about 76 MiB and R child peak
RSS about 519 MiB at 10,000 cells. These are process lifetime high-water marks,
not per-operation allocations. R's GC heap high-water counters peaked around
1,345 MiB across this longer benchmark process; they are a different metric
from live RSS and include retained allocator heaps. `timings.csv` records each
operation's GC counters and `web-timings.csv` records the RSS measurements.

All sizes created a genuine completed processed-entry project via explicit
manual proposal, approval and resume. They also created a real child project
stopped for strategy review; child listing verifies its parent binding. The
fixture does not time child analysis, raw-data QC, many-child registries,
remote storage, NFS or clusters.

## Changes and remaining costs

- Metadata and embedding resolve literal IDs once, then use integer reads.
  Directed export reads only its small RNA panel into a dense matrix; the full
  assay stays sparse. Missing genes remain null, measured zeros stay zero.
- The just-written `project.json` file record supplies both manifest and bundle
  digests, avoiding a second identical file hash. Every file is still hashed;
  no authoritative input, Seurat or checkpoint verification was removed.
- Profiling five 10,000-cell single-child listings attributed 55% inclusive
  time to digest, 45% to QC-preview verification, 40% to parent verification,
  and 20% to `readRDS`. These overlap and must not be added. Ten complete-parent
  inspections attributed 47% to `readRDS`, 32% to implementation fingerprinting,
  and 24% to digest. A future optimization could reuse an already verified
  immutable parent/implementation within one operation, with explicit checks
  against concurrent changes. Cross-request caches require a separate design.
- QC preview verification rebuilds the typed preview from saved rules and
  evidence, preserving reviewed keep/remove identity. The current benchmark's
  real child exercises that path. No unchecked shortcut was introduced.
- Existing cell-cycle per-cell count hashing took 0.130 / 0.833 / 2.305 seconds.
  It preserves per-cell identity used to verify subsets; it was measured and
  left unchanged. Integer-column batching needs an equivalence fixture before
  changing this separate module.
- The strict JSON loader at 10,000 cells took only about 52 ms for the portable
  bundle, so there is no evidence for replacing its duplicate-key and numeric
  validation parser.

A 100,000-cell run was not performed. Even this 1,000-gene fixture consumed
substantial heap and the execution transport was interrupted once during the
initial long baseline run. Extrapolating a safe 100,000-cell limit or claiming
real 20,000-gene atlas performance from this fixture would be unjustified.

Local evidence is saved in `../evidence/performance-*`, including install and
test logs, baseline/optimized timing CSVs, byte equivalence, component timings,
R profiles and session information. The first baseline was interrupted after
10,000-cell exports; the optimized run completed all operations at all sizes.
