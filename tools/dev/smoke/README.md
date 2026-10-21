# Public PBMC3k ReAct smoke

This manual driver is not run by CI and does nothing when sourced. It reuses
`benchmark/evaluation-v1/input-manifest.json` and requires the matching official
10x archive plus its verified MEX members. No tutorial labels enter analysis.

```r
source("tools/dev/smoke/react-real.R")
react_real_smoke("/path/to/filtered_gene_bc_matrices/hg19", "/new/project",
  provider="deepseek", model="YOUR_QUALIFIED_MODEL_ID",
  confirmed=TRUE, accept_drafts=TRUE,
  archive="/path/to/pbmc3k-filtered.tar.gz")
```

Configure the provider key in the R process beforehand. The chosen recipient
receives only the existing validated aggregate evidence and research context.
No key is read from a credential file by this script. Costs are recorded after
calls, with no monetary reservation or cap. Existing per-cluster/session turn
and timeout limits apply. Interrupted or invalid calls stop this driver; it
never restarts a project or automatically resends a request.

`accept_drafts=TRUE` explicitly selects the benchmark policy. Each saved draft
is adopted and then separately approved using the existing public review API,
with reviewer `benchmark-policy:accept_drafts`. This is software smoke testing,
not human review of biological correctness and not an auto-approval package API.
Use `provider="mock"` for a zero-API preparation run on the same public input.

The project contains `smoke-receipt.json`: final status, actual elapsed time,
recorded token usage/cost (unknown entries counted separately), tool calls,
review hashes, fallback information and API-free replay agreement. A stopped
project is preserved for diagnosis. The receipt does not claim accuracy: this
PBMC3k input has no independent truth labels in this protocol.
