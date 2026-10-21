# Research scope and claims

Version 2, 2026-10-20. This document defines the intended scope and the evidence
needed to support research claims. Planned features and experiments are not
validated results. Implementation status is recorded in the stage reports and
[paper milestone plan](PAPER_MILESTONE_PLAN.md).

## Purpose

scAgentKit is an LLM-assisted workflow for foundational single-cell RNA-seq
analysis. It makes decisions from quality control to annotation explicit: the
model proposes a decision with inspectable evidence, and a researcher reviews
and approves it. The intended outputs are an annotated Seurat object and the
records needed to audit and reproduce the analysis.

## Users and scope

The intended users are researchers with biological expertise and limited
bioinformatics experience who need to interpret, report and reuse their results.

The workflow covers raw count matrices through annotated Seurat objects,
including the associated audit evidence. Research-specific downstream analyses
such as trajectories, cell communication, regulatory networks, differential
expression between conditions and cell-composition comparisons are outside this
scope. Condition-signal diagnostics assess whether foundational processing has
removed experimental-design information; they do not constitute a downstream
condition differential-expression workflow.

The paper milestone does not add analysis types, MCP entry points or local models.

## Principal claims and required evidence

| Claim | Intended behavior | Required evidence |
| --- | --- | --- |
| Biologically appropriate decisions | Multi-sample QC; eligible, researcher-approved thresholds for diagnostic clusters; batch-correction decisions based on experimental design and observed effects; doublet and cell-cycle handling appropriate to the research question | Prespecified perturbations covering low-RNA populations, absent/real/confounded batch effects, sample-depth differences, doublets and cell cycle; separate reporting of technical mixing and biological preservation |
| Explicit, reproducible decisions | Visible, editable and traceable decisions on QC, doublets, cell cycle, batches, resolution and annotation; replay with fixed inputs, decisions and environment | Repeated-run stability, end-to-end comparisons using identical inputs and API-free replay; recorded random seeds and environments. Temperature 0 is not a guarantee of deterministic online responses |
| Verifiable evidence | Claims checked against statistics from the dataset using deterministic validators | Citation validity, performance by confidence category and abstention. Valid formatting or statistical citations do not establish that an entire biological explanation is correct |

Supporting features include model drafts and rationales before each of the three
approval gates, ReAct investigation of difficult clusters, independent comparisons
with local ACT references filtered by species and tissue, and CL mapping. Inputs
include multiple samples, raw or filtered 10x matrices, sample tables and RDS
files, with explicit design declarations and persistent project recovery.
Rule-based fallback and researcher approval apply throughout. Saving a draft
does not approve it, and models cannot grant approval.

## Comparison boundaries

Candidate annotation comparators include GPTCelltype, CASSIA, CellTypeAgent and
mLLMCelltype. Annotation comparisons must hold cells, clusters, markers and the
underlying model fixed. Candidate autonomous agents, including CellAgent and
Biomni, require verification of the tested version and applicable functions.
A tool's category alone does not establish its capabilities.

Comparative descriptions should state that a tested tool "does not expose X as
an explicit, reviewable decision" rather than assert that it "does not consider
X". Each specific comparison requires a primary source for the tested version.
scAgentKit covers more foundational analysis decisions than annotation-only
workflows and aims to improve reliability through approval and deterministic validation.
A claim that it is more reliable than autonomous agents requires a formal
comparison.

The project does not claim the highest annotation accuracy, full automation or
support for arbitrary downstream analyses. Broader scope does not establish
better accuracy. Same-model annotation comparisons and raw-count end-to-end
comparisons must be reported separately.

## Additional claims

| Claim | Evidence and limitations |
| --- | --- |
| LLM assistance adds value | `accept_drafts` versus `rule_defaults`, and ReAct on/off ablations; subsequent human studies of acceptance rates, time and agreement. Scripted acceptance is not a human acceptance rate |
| ACT adds value | ACT on/off ablations and the association between reference conflicts and errors; unassessed cases reported separately. Association does not establish causation |
| Annotation is competitive | Comparison with at least one qualified LLM annotation tool using the same underlying model and benchmark, alongside a reference classifier; coverage and denominators reported |
| The workflow supports sustained research use | Published research cases from the authors and records from external evaluators, together with the planned 1.0 work on portable audit records and project updates. One trial run is insufficient |
| Evaluation data were unseen by the model | Verifiable provenance for the maintainer's unpublished holdout, separation from development and two independently frozen label sets. Public data first released after model training are a preferred supplement |

Efficient review and error detection both require evaluation. Researchers should
usually be able to accept an appropriate draft with one action while retaining
the ability to inspect and reject errors. Additional confirmation dialogs alone
do not establish better control.
