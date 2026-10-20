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

Pending execution against the installed stage-1 implementation. Do not claim a
performance pass until measurements and package versions are recorded here.
