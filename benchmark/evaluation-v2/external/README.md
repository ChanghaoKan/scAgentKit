# External comparators and result import

**E0 status: format and qualification contract only. No adapter implementation or external run is claimed.** The maintainer runs external tools; scAgentKit does not execute them as model tools.

## Result format

For each original input cell, a local CSV supplies:

```csv
cell_id,retained,cluster,label
example_1,true,0,T cell
example_2,false,,
```

IDs must be unique and aligned to the original input. Deleted cells, tool failure and missing output are distinct. A JSON sidecar records tool name/version, exact source commit or hosted build, parameters, input/output hashes, model/provider, label mapping, retained-cell convention, seed, cost/token/time availability and measurement scope. Unknown cost is null with a reason, never zero. Unsupported decision-level fields are unavailable, not invented.

The interface is the common stability/impact scorer. Annotation-only `cell_id` or `cluster_id` plus `label` baselines also use the shared 4E evaluator; cluster IDs are comparable only with a bound membership hash. A numeric cluster name alone cannot align independently reclustered outputs.

## CellAgent end-to-end comparison

Use the authors' [CellAgent paper](https://arxiv.org/abs/2407.09811) to identify the official implementation or hosted service, then freeze the maintainer-verified repository commit or service build, license, supported inputs, exact provider/model and configuration. A same-name third-party repository is not qualification evidence.

The executable installation/run command remains **unknown until the official implementation and accessible version are verified**. E0 therefore does not publish an invented command. Before admitting this comparator, the maintainer records the exact successful command or hosted operation, dependency environment and a development run, plus the following conversion:

1. Export the tool's retained-cell set, cluster assignment and final label.
2. Join to the frozen original ID universe; translate IDs only through an explicit one-to-one map.
3. Mark retained false only for documented filtering; preserve missing/failed results as separate status records rather than pretending all cells were deleted.
4. Save the standardized CSV and sidecar with hashes; validate them with the same importer and metrics used for scAgentKit.

Once qualified, source/run commands and the column mapping are appended here before the corresponding formal arm is frozen. If official execution remains unavailable, the end-to-end comparison is explicitly unavailable; generic external import can still be implemented. Do not silently substitute another agent.

## Annotation and reference baselines

At least one LLM annotation comparator must support the **same precise DeepSeek or Grok API model as the corresponding primary arm** as scAgentKit. Verify its original source, license, commit, parameter forwarding, evidence input and retry behavior; an advertised provider alone is not sufficient. Fixed-cell/cluster/marker annotation comparisons are separate from raw-counts CellAgent end-to-end comparisons. Information or model mismatches are descriptive and cannot isolate a ReAct effect.

CASSIA exact-model forwarding has passed an offline actual-SDK/HTTP probe for Flash, V4 Pro and Grok4.7; complete installation/live qualification remain pending. Its Flash thinking and Grok effort forwarding gaps, and legacy Chat versus Responses difference, must be resolved or disclosed before freezing each arm. A same-model method comparison does not establish protocol equivalence. Details are in the [qualification record](../manifests/model-qualification.md). Costs include all participating agents and actual retries, reported only after execution under the [cost contract](../manifests/E5_COST_REPORTING.md). SingleR/CellTypist additionally freeze reference/training datasets and type coverage. ACT evidence visibility, marker limits, selected cells and true labels are controlled consistently; truth is never supplied to execution.

Describe another tool as “does not expose X as an explicit, reviewable decision” only when the tested version supports that statement. Do not claim that it “does not consider X” or infer its complete behavior from the tool category.
