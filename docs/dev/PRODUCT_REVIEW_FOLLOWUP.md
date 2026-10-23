# Product review follow-up

This development change addresses the fifteen findings from the October 2026
product review. The review followed **question requirements → delete → simplify
→ accelerate feedback → automate**. Its scope included researcher entry, study
facts, scientific decisions, model consent, draft continuity, recovery, child
analysis, results, resource management and executable acceptance.

The necessary outcomes remain: exact input identity, review of the analysis
plan, review of measured clustering, review of annotations, and independently
saved results. Saving changed parameters rebuilds the evidence before approval.
The existing combined approval/continuation actions remain available. These
requirements protect different scientific decisions and are retained.

| Finding | Implemented correction | Retained boundary |
| --- | --- | --- |
| F01 — R library precedence | Explicit R library order is applied to both `R_LIBS` and `R_LIBS_USER` at launch, preflight and worker boundaries. | Matching package/runtime, implementation and checkpoint verification remain mandatory. |
| F02 — unfinished annotation loss | Initial manual worksheets are shown directly and can be downloaded/imported after tab storage is lost. Imports validate project, input, revision, evidence, clusters, citations and field limits. | A worksheet is non-authoritative. A complete proposal must still be saved, inspected and approved. |
| F03 — recovery guidance | A derived recovery panel explains the stopping condition, last verified progress, uncertain delivery and explicit next action. | No automatic resend, credential replacement, archive rebinding or lock removal. Recovery remains an explicit operation in the existing engine. |
| F04 — input-dependent reopen | `sc_start(project_dir=...)` reopens protected checkpoints and saved configuration. Original MEX/RDS import options need not be reconstructed. | Changed content at a recorded original source path is rejected. No new input binding, schema migration or implementation-hash rewrite. |
| F05 — portable researcher evidence | Results include a readable researcher report, `audit.json`, and the same audit projection in `Seurat@misc$scAgentKit`. They record actual decisions, label counts, origins, accounting, environment versions and checkpoint hashes. | These projections are not the authoritative ledger, a complete environment archive or biological validation. |
| F06 — ambiguous stage names | Main status names the next task and distinguishes plan review from measured-clustering review. Engine status stays in the disclosed fingerprint section and a machine-readable attribute. Guidance includes the existing combined action. | No new saved workflow state or approval shortcut. |
| F07 — buried current decision | Current plan, impact, blockers and decision precede disclosed alternatives. Parameter groups start collapsed; earlier strategy/annotation records move into disclosures when another decision is current. Detailed saved evidence remains available. | Researchers still inspect the evidence appropriate to their decision. Layout measurements do not establish human task-time improvement. |
| F08 — dead QC preselection | Delete the inactive checkbox, automatic preselection function, unused backend preselection field and obsolete acceptance expectations. Candidates require explicit selection. | Conservative starting policy, thresholds, measurements and explicit Save/Approve semantics remain unchanged. |
| F09 — hidden startup mode | Print resolved model mode, provider/model/destination, transfer consent, credential readiness and method software readiness. Align maintained default descriptions. | Keep current exact-one-key autodetection; explicit `provider="manual"` is deterministic. Existing provider/transfer policy stays fixed. Startup sends no request. |
| F10 — study tissue overloaded as reference key | `annot_act_scopes()` lists pinned keys; `reference_tissue` / `reference_review$tissue` explicitly selects reference scope separately from unchanged study tissue. Both are recorded. | This optional selection is a scientific scope choice. Defaults, exact bundled matching, original fields and no cross-species/all-tissue fallback remain. |
| F11 — opaque input mismatch | Validate multi-sample feature headers before reading matrices. Report bounded missing, extra and conflicting feature/key counts with sample names. | Never silently intersect/union features, repair keys, aggregate genes or infer metadata roles. |
| F12 — late method readiness | Startup probes the existing supported doublet/Harmony adapters without scoring and reports software availability separately from design and review requirements. Existing scientific assessment remains visible. | No auto-install, downgrade, source/signature relaxation or negative biological conclusion from unavailable software. |
| F13 — inaccessible/inconsistent child route | Expose an explicit separate `subcluster_workspace` in the installed entry. Use common Review for child annotation, Cell scope for selection/application, and show completed-parent setup guidance. | Independent raw-count children, exact cell IDs, frozen completed parent, separate derived output and no nested children. No child is created by reopening. |
| F14 — misplaced storage/archiving | Put storage outside optional model controls. Document stop/copy/hash/environment preservation, reuse the audit checkpoint index and supply a whole-directory manifest procedure. | Archiving remains explicit and manual. Measurement is neither free-space checking nor a hard filesystem quota. No checkpoint pruning or new archive service. |
| F15 — docs/acceptance drift | Align maintained version/default/reopen instructions and real-browser assertions. Exercise conservative QC, direct worksheet entry, portable drafts and combined continuation. | Preserve historical reports and frozen `benchmark/evaluation-v1/` evidence. |

The Project workbench also includes the requested interactive workflow map.
Hover, keyboard focus and touch selection expose how QC and other proposals are
formed, their saved evidence and review boundary. The optional ReAct path
distinguishes current traces, historical traces and simulations; configured
provider names are never used as proof that a model ran.

## Verification scope

Use the matching installed source archive for the browser journey. The targeted
R checks cover reopening without original inputs, separate child workspace,
reference scope, MEX preflight, annotation preparation, controls and portable
output identity. Python tests cover local service/worker, format, recovery and
request boundaries. DOM checks exercise production rendering and draft guards.
See the pull request for the executed results and any failures or skips.

Live paid provider calls, clean macOS installation, a browser child-writeback
journey, large public-data throughput, human usability studies and biological
accuracy are separate validation. None is established by mock, synthetic or
small bundled-data checks. Existing projects require their original matching
software environment; this development version does not migrate them.
