# Compare and replay saved annotations

ReAct checks evidence before proposing a label. Its output is still a draft:
you review and approve it at the usual third gate. Evaluation and replay below
do not approve or change your analysis, and do not require an API key.

## Compare labels

Provide a CSV with `cell_id,label`, or `cluster_id,label` for the project's
saved clusters. Cell IDs must match the saved analysis. Use cell IDs when an
external method has different clusters.

```r
result <- sc_react_eval(
  "my-project", truth = "truth.csv",
  external = list(SingleR = "singler.csv", CellTypist = "celltypist.csv")
)
result$metrics
result$output_dir
```

The output compares the original draft, ReAct draft and external predictions.
It reports all clusters and the difficult clusters selected for evidence checks,
with cell-level results alongside cluster-level results. Human edits after the
draft are not included. Cluster labels require 80% mapped coverage and an 80%
majority among mapped cell labels.

Exact labels are mapped through the local Cell Ontology reference, whose source
is recorded in the evaluation. An optional
`label_map` resolves dataset-specific names; explicit `cl_id` columns are checked
against the label mapping. Freeze maps before looking at results. Unmapped
predictions are excluded from primary accuracy and counted as errors in the
strict accuracy shown beside it. Unknown labels count in both. Coverage and
denominators are always reported.

For parent-class scoring, supply a frozen `allowed_ancestors` vector of meaningful
CL IDs. A prediction may be up to three parent edges above truth; predicting
an unsupported subtype does not earn parent credit. Broad universal roots do
not earn credit. Without this vector, only exact matches receive credit.

For two independently prepared human annotations, provide
`cell_id,label_author,label_independent`, optionally `cl_id_author` and
`cl_id_independent`. Consensus uses exact agreement or a unique nearest common
allowed parent. Disagreements are excluded from primary cell truth and listed
separately; results against each annotator are also exported. These annotations
must be frozen before the tool first runs on the held-out data.

Outputs include steps, fallback reasons, tool configuration, mapping provenance,
recorded tokens and costs. Unknown cost is identified explicitly. Baseline cost
currently covers all annotation-purpose calls in the project; the additional
ReAct cost is restricted to the saved session. External CSVs do not establish
external runtime or cost, which must be collected separately. No cost forecast
or budget reservation is performed.

## Replay without a model

```r
replay <- sc_react_replay("my-project")
replay$matches
replay$differences
```

Replay reconstructs the complete saved conversation, reruns read-only evidence
tools and checks citations. It returns the original draft and any differences.
It never sends the conversation to a provider. Keep the project checkpoints and
the same scientific software version; changed or missing inputs block replay.
Later human edits are not part of the original draft.

Cache-hit flags do not affect matching. Time-dependent failures can differ when
rerun. A saved rejection before dispatch may lack a provider receipt; replay
reports that its environment-dependent cause cannot be verified. Neither case
is silently reported as an exact match.
