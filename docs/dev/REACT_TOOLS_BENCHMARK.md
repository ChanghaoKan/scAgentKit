# Historical stage-1 read-only evidence benchmark

This report describes the recorded stage-1 implementation. Its original driver
is retained at the [recorded source revision](https://github.com/ChanghaoKan/scAgentKit/blob/8afd4a694d07c92550cda1c314811d6e83affe37/tools/benchmark-react-tools.R).
Current development uses `tools/create-react-benchmark-fixture.R` to prepare
synthetic data and `tools/benchmark-react-session.R` to measure the current
verified session worker. No current disk-cache or per-call worker claim is made
from these historical timings.

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
