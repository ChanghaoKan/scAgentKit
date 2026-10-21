# Evidence checks during annotation

This guide describes the development version. Start a new project with
`sc_start(input, project_dir, context=..., provider=...)`. In interactive R,
confirm aggregate data transfer once; the browser then prepares drafts for
review. Noninteractive callers can use the installed `full-llm-workflow.R`
example to record explicit confirmation. Strict per-request confirmation remains
available with `review=list(allow_external=TRUE)`.

The first gate includes diagnostic QC and batch evidence. These diagnostic
clusters are not final cell types; final analysis is recomputed after approval.
The second gate reviews actual clustering evidence. At the third gate, the
model first proposes labels independently of ACT, then local ACT evidence is
compared with them. `react="auto"` checks clusters with low confidence, Unknown
labels or ACT conflicts. `react="all"` checks every cluster; `react="off"`
keeps the one-shot draft and local comparison. Reopening uses saved settings.

Evidence checks may inspect saved markers, expression summaries, ACT entries
and cluster context. They cannot change your data or approve a decision.
Expression-only results are marked untested; tested supporting markers must
pass the deterministic citation rules. Limited evidence should lead to a broad
label or Unknown. You can keep or edit the draft before approving it.

Open the annotation row's evidence-check section to see what was queried,
what it returned and the draft conclusion. Citation links jump to the matching
step. The summary shows tool calls, recorded usage/cost and fallback reasons.
Missing cost is unknown, not zero. Limits are six turns per cluster, sixty per
session and three minutes per cluster. New default startup records usage and
cost after calls, without counting estimates, reservations or a monetary cap.

If a model cannot use tools, times out, reaches a limit or returns an invalid
draft, the saved one-shot draft remains available and the reason is displayed.
If there was no valid first draft, manual annotation remains available. A
request whose delivery is uncertain is never automatically resent. Integrity
errors still block continuation rather than silently replacing evidence.

For a local demonstration, source `react-three-gate-mock.R` from the installed
examples and call `react_three_gate_mock(new_project_dir, new_input_rds_path)`.
It uses public `pbmc_small`, explicitly scripted approvals and no external model.
It is software acceptance, not biological validation; do not reuse its automatic
approval policy on your own research data.

[Compare labels and replay without an API key](REACT_EVALUATION.md).
