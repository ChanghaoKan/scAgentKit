# Developer references

These repository-only documents describe internal contracts, diagnostic drivers and validation evidence. Start a study with the [researcher guide](../SCIENTIFIC_REVIEW_QUICKSTART.md). They are excluded from the R archive.

- [ANALYSIS STRATEGY SUPPORT](ANALYSIS_STRATEGY_SUPPORT.md)
- [ANNOTATION ASSISTANCE](ANNOTATION_ASSISTANCE.md)
- [ANNOTATION REVIEW](ANNOTATION_REVIEW.md)
- [API CONSOLIDATION](API_CONSOLIDATION.md)
- [CELL CYCLE REVIEW](CELL_CYCLE_REVIEW.md)
- [CM2 EVIDENCE REVIEW](CM2_EVIDENCE_REVIEW.md)
- [COMPLETE ANALYSIS WALKTHROUGH](COMPLETE_ANALYSIS_WALKTHROUGH.md)
- [DOUBLET REVIEW](DOUBLET_REVIEW.md)
- [ENVIRONMENT RESTORE](ENVIRONMENT_RESTORE.md)
- [EVALUATION PROTOCOL V1](EVALUATION_PROTOCOL_V1.md)
- [Evaluation protocol v2](EVALUATION_PROTOCOL_V2.md) — approved engineering design; formal experiments not frozen or executed
- [Positioning v2](SCAGENTKIT_POSITIONING_V2.md)
- [Paper milestone and 1.0 plan](PAPER_MILESTONE_PLAN.md)
- [Provider model and usage contract](PROVIDER_MODEL_AND_USAGE_CONTRACT.md)
- [E5 post-run cost reporting](../../benchmark/evaluation-v2/manifests/E5_COST_REPORTING.md)
- [Grok official capability and protocol qualification](../../benchmark/evaluation-v2/manifests/xai-qualification.md)
- [Evaluation v2 framework contract](../../benchmark/evaluation-v2/README.md) — E0 documents only
- [HARMONY PC REVIEW](HARMONY_PC_REVIEW.md)
- [MAD REVIEW](MAD_REVIEW.md)
- [OFFLINE COMPARISON CONTRACT](OFFLINE_COMPARISON_CONTRACT.md)
- [PARAMETER CONTEXT CONTROLS](PARAMETER_CONTEXT_CONTROLS.md)
- [QC-review](QC-review.md)
- [ReAct implementation plan](REACT_IMPLEMENTATION_PLAN.md)
- [Accepted 1.0 gap audit](reports/2026-10-20-1.0-gap-audit.md)
- [E0 stage report](reports/2026-10-20-e0.md)
- [scAgentKit 2A and workflow revision stage report](reports/2026-10-20-scagentkit-2a.md)
- [UNIFIED MODEL REVIEW](UNIFIED_MODEL_REVIEW.md)
- [annotation-response-recovery](annotation-response-recovery.md)

## Implementation reports

- [B1/B2 diagnostics](reports/BIOLOGICAL_DIAGNOSTICS_STAGE_REPORT.md)
- [ReAct loop](reports/2026-10-20-scagentkit-2b.md) · [xAI adapter](reports/2026-10-20-scagentkit-m1-xai.md)
- [Trace interface](reports/REACT_TRACE_UI_STAGE_REPORT.md) · [Evaluation/replay](reports/REACT_4E_STAGE_REPORT.md)
- [Startup](reports/REACT_START_STAGE_REPORT.md) · [Capacity](reports/RESOURCE_CAPACITY_STAGE_REPORT.md)
- [Cancellation and resume](reports/TRIAL_CONTROLS_STAGE_REPORT.md)

Reports describe their recorded commits, not an assurance that every proposed experiment has run.
Use `main` as the integration branch and one short-lived branch per PR. Delete merged remote
branches after checking their recorded heads; keep unfinished work out of the user guides.
