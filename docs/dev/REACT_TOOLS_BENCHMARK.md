# Stage 1 read-only evidence tool benchmark

This benchmark measures the four first-version local tools. It does not call a
provider, generate annotations, test annotation accuracy, or run differential
expression. The saved marker statistics are synthetic.
It does not satisfy the separate 1.0 release requirement for a public
50,000-cell dataset completing the full workflow and all three approvals.

Run the current installed development package, with its dependencies available:

```sh
Rscript --vanilla tools/benchmark-react-tools.R \
  --output /absolute/path/to/a-new-benchmark-directory \
  --cells 50000 --features 20000 --density 0.05
```

The script refuses to replace an existing benchmark project. It writes a real
Seurat object and checksummed project checkpoints, then invokes the production
context/dispatcher API. It does not benchmark a mock matrix adapter or a
standalone in-memory helper.

The dataset has 50,000 cells, 20,000 features, 20 clusters and eight samples.
Counts are sparse positive integers at 5% density, approximately 1,000 detected
features per cell; the saved
normalized layer is `log1p(counts / cell_total * 10000)`. Each cluster has 1,000
synthetic saved marker records and a top-30 summary. The ACT lookup uses the
actual bundled human Blood snapshot. Synthetic saved doublet and cycle score
records exercise aggregation of available diagnostics; no classifier or cycle
scorer was run. Cell IDs are synthetic and remain local.

For each tool:

1. A fresh R process loads the installed package and verified checkpoint context.
2. Its first call uses an empty application cache. This is the **cold** call.
3. Three repetitions in that process measure **warm** cache hits.
4. Another fresh R process verifies a persisted **warm restart** cache hit.

The operating-system disk cache is not flushed. Cold application cache must not
be described as cold physical storage. Dispatch timing includes checkpoint SHA
verification, isolated worker startup, computation, output privacy/size checks
and cache writing. Package loading and context loading (including a garbage
collection after temporary input objects are released) are measured separately;
the process wall time also includes R startup/shutdown and, for the first
process, all three warm repetitions.

`environment.json` records CPU, RAM, OS, R/package versions, shape, density,
seed, sample/cluster counts, reference snapshot and checkpoint bytes.
`timings.csv` contains each measurement. `benchmark.json` retains structured
results, statuses and hashes. The benchmark fails if a call fails, exceeds
60 seconds, misses an expected warm cache hit, or returns a changed result hash.
On macOS, each subprocess is wrapped with `/usr/bin/time -l`; its reported
maximum resident set size is retained in bytes. This is a process resource
measurement, not the summed concurrent resident memory of the complete process
tree.

The 60-second ceiling is enforced by the dispatcher using a separately
terminable worker process. The benchmark is an observed bound on the declared
fixture and machine, not a guarantee for every 50,000-cell dataset or filesystem.

## Recorded run

Executed on 2026-10-20 against the installed stage-1 development build:

- Apple M5, 10 logical CPUs, 16 GiB RAM, macOS 26.5.1 arm64.
- R 4.6.1; Seurat 5.6.0; SeuratObject 5.4.0; Matrix 1.7.5;
  callr 3.8.0; agentomicsCore 0.1.1; scAgentKit 0.8.1 with the stage-1 changes.
- Implementation hash:
  `dc7d34210cd191890341613d0a0444e73a2f8dcc964f3200e14cac915d8524a8`.
- Exactly 50,000,000 count nonzeros, density 0.05. Detected-feature
  minimum / lower quartile / median / upper quartile / maximum:
  859 / 979 / 1,000 / 1,021 / 1,152 per cell.
- 565,164,011 bytes of checksummed input/evidence files. Fixture construction
  and checkpoint writing took 106.459 seconds, outside the tool measurements.

All four cold calls, twelve same-process warm calls, and four restarted-process
warm calls succeeded. All expected cache hits were observed; each tool's result
hash remained identical across its five calls. The largest dispatch duration
was 10.328 seconds.

| Tool | Cold dispatch (s) | Warm median, three calls (range, s) | Warm after restart (s) | Cold context load (s) | Largest reported process RSS (GiB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `cluster_markers` | 5.271 | 4.677 (4.646–4.886) | 6.321 | 13.481 | 4.101 |
| `gene_expression` | 10.328 | 4.644 (4.605–4.696) | 5.082 | 12.710 | 3.902 |
| `act_lookup` | 4.972 | 4.625 (4.622–4.628) | 5.377 | 12.345 | 3.825 |
| `cluster_context` | 6.757 | 4.599 (4.585–4.615) | 5.320 | 12.294 | 3.871 |

Warm calls still start an isolated worker and verify the bound checkpoint
checksums. They avoid recomputing tool results; they are not an in-memory
dictionary lookup. Context loading verifies the source object and is a separate
initial cost. Package loading took 0.010–0.014 seconds in these child processes;
additional dependency loading occurs within the measured context/worker work.

The complete manual command took 316.40 seconds. macOS `/usr/bin/time -l`
reported a maximum resident set size of 4,403,494,912 bytes (4.101 GiB), a peak
memory footprint of 7,746,771,160 bytes (7.215 GiB), and zero swaps for the
command. These OS counters describe different memory measures; neither is a
sampled sum of simultaneous RSS across the parent and worker process tree.

The ACT query requested 20 genes from the actual frozen Blood reference; the
fixture reference contains 2,021 expanded marker entries. Expression requested
20 assayed genes, marker retrieval requested 50 rows, and cluster context
included sample proportions, QC and synthetic saved diagnostic-score summaries.
There were no provider requests or API charges.

Raw measurements are committed as
[JSON](benchmarks/react-tools-50k-2026-10-20.json) and
[CSV](benchmarks/react-tools-50k-2026-10-20.csv). They establish the runtime bound
for this declared machine and fixture only. This result does not establish
performance on every 50,000-cell assay, on network storage, or for the deferred
pairwise differential-expression tool.
