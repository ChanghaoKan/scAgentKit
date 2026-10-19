# scAgentKit 0.8.1 — User examples

- `three-gate-analysis.R`: explicit offline public `pbmc_small` software control, three approvals and Unknown labels; no biological recommendation or model call.
- `simple-analysis.R`: installation-check wrapper around that same three-gate helper.
- `full-llm-workflow.R`: configured provider/model, explicit creation-time categories and USD cap, then browser drafts with three human approvals. Sourcing defines a function and sends nothing.
- `tenx-multisample.R`: explicit local MEX sample table and exact metadata joins; no inferred capture or technical batch.
- `subcluster-review.R`: independently reviewed exact-cell child and explicit writeback/undo.

Focused developer and historical drivers live in repository `dev/examples` and are not installed. None of these files installs dependencies or creates credentials. For a study, choose the facts and inspect each saved scientific review; do not reuse the public fixture's scripted approvals.
