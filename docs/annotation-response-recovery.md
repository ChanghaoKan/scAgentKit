# Complete annotation responses and recovery

The coordinator now requests at most five marker citations, an 80-character
label and a 240-character rationale for each cluster. The default provider output
cap is 4096 tokens; an explicit caller cap still takes precedence. The schema
continues to require every literal cluster exactly once, validates all cited
markers against that cluster, and permits `Unknown`. These response limits do
not restrict richer manual review notes.

A cut-off response is rejected and retained with its usage and cost. Strings are
never completed or joined to make a truncated response appear valid. Provider
completion metadata is recorded when available; absence is reported explicitly.
An output token count equal to the cap alone does not establish a finish reason.

## Recover a failed annotation without repeating QC

Changing the implementation or provider generation settings changes the binding.
Do not edit an old state, configuration, approval or ledger to bypass that check.
Use the existing processed entry in a new project, with the verified analysis
checkpoint as input and the failed project's provenance as the skip reason:

```r
old <- sc_run_inspect(old_project)
# Read the analysis path/SHA from the validated old state and verify its bytes.
new <- sc_run(
  analysis_checkpoint, new_project,
  start_stage = "processed", processed_reason = provenance_text,
  context = old$context, provider = provider_with_4096_output_tokens,
  budget = 0.05, review = list(allow_external = TRUE),
  annotation_column = "deepseek_review"
)
```

This reuses QC, normalization, PCA, clusters and UMAP. The current processed
entry computes local markers/evidence again and exits at a new aggregate transfer
review. Inspect that exact preview and approve its new hash before one explicitly
authorized annotation call. Review the complete typed result and approve its
separate annotation hash before local finalization. Keep the old failed project,
response and costs as part of the audit; its QC approval is provenance, not an
approval of the new transfer. Do not use `retry = TRUE` on the old project.

For a bounded public PBMC recovery, use a separate one-call driver: assert an
empty new ledger before sending, refuse automatic retries, reserve at most the
authorized $0.05, and verify the old project remains byte-identical. A valid
mechanical writeback is a provisional result requiring scientific review.
