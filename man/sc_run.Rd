\name{sc_run}
\alias{sc_run}
\alias{sc_run_inspect}
\alias{sc_run_approve}
\alias{sc_run_reject}
\alias{sc_run_resume}
\alias{sc_run_propose}
\alias{sc_run_undo}
\alias{sc_run_unlock}
\alias{sc_run_accept}
\alias{sc_run_qc_preview}
\alias{sc_run_qc_review}
\alias{sc_run_review}
\title{Server-side resumable analysis with typed human approvals}
\usage{
sc_run(input, project_dir, context = list(), provider = NULL,
  chat_fn = NULL, budget = 0, review = list(),
  start_stage = c("qc", "processed"), processed_reason = NULL,
  assay = "RNA", counts_layer = "counts", normalized_layer = "data",
  cluster_column = "seurat_clusters", analysis = list(), reference = NULL,
  annotation_column = "sc_annotation", qc_proposal = NULL,
  annotation_proposal = NULL, qc_preview = list(),
  reference_review = list(), annotation_history = NULL,
  strategy = FALSE, strategy_proposal = NULL, cycle_diagnostics = NULL,
  doublet_diagnostics = NULL, qc_mad = NULL,
  subcluster_origin = NULL, subcluster_creation = NULL,
  .subcluster_lock_owner = NULL)
sc_run_inspect(project_dir)
sc_run_approve(project_dir, proposal_hash, reviewer, reason = "",
  preview_hash = NULL, expected_revision = NULL)
sc_run_reject(project_dir, proposal_hash, reviewer, reason,
  preview_hash = NULL, expected_revision = NULL)
sc_run_qc_preview(project_dir, sensitivity = NULL, gene_panels = NULL,
  reviewer = NULL, reason = NULL, proposal_hash = NULL,
  preview_hash = NULL, expected_revision = NULL)
sc_run_qc_review(project_dir, action, proposal_hash, preview_hash,
  expected_revision, reviewer, reason, proposal = NULL,
  sensitivity = NULL, gene_panels = NULL)
sc_run_review(project_dir, action, kind, project_id, input_hash,
  proposal_hash, review_hash, expected_revision, reviewer, reason,
  proposal = NULL, sensitivity = NULL, gene_panels = NULL,
  decision_id = NULL)
sc_run_resume(project_dir, provider = NULL, chat_fn = NULL, retry = FALSE)
sc_run_propose(project_dir, proposal, reviewer, reason)
sc_run_undo(project_dir, decision_id, reviewer, reason)
sc_run_unlock(project_dir, token, reason)
sc_run_accept(project_dir, reviewer, reason)
}
\arguments{
\item{input}{Named genuine raw counts matrix, Seurat object, or local RDS path.}
\item{project_dir}{Server-side directory. Creation requires no existing run.}
\item{context}{Named user facts with explicitly declared human/Homo sapiens or mouse/Mus musculus species, tissue, notes, optional research_goal and design (type, technical_batch logical, notes), and columns mapping sample, qc_group, capture, batch, group, condition and donor roles to actual metadata columns. Missing facts are disclosed, never inferred as metadata.}
\item{strategy}{Logical opt-in to a concentrated typed QC/analysis strategy review. Legacy flow remains the default. Raw strategy requires canonical counts/data layers and at least 21 projected retained cells; default cluster output is a fresh sc_strategy_clusters column.}
\item{cycle_diagnostics}{Optional explicit list with gene_set from \code{sc_cycle_gene_set}, column_prefix, seed, scale_factor, nbin, ctrl, min_genes and min_fraction. Requires strategy mode and explicit human/mouse context. Scores use a fixed full-input pre-QC reference. The centrally reviewed cycle method defaults to none; full/difference require exact approval and applicable saved scores. Processed entry supports diagnostics and none only.}
\item{doublet_diagnostics}{Optional explicit configuration for capture-specific raw-count scDblFinder evidence in strategy mode. Requires human/mouse droplet scRNA-seq, nonempty input_source, empty_droplets_removed = TRUE, an actual capture column matching context or an explicit single loading unit, and a sourced manual expected rate or supported standard-10x estimate. Automatic estimation additionally requires technology = "10x_chromium_standard" and full_called_cohort = TRUE declaring the complete original called-cell cohort before quality filtering; its default is FALSE. Sample and donor are not inferred as captures. Bounded nfeatures, dims, artificial_doublets, seed, exactly iter = 3, clusters = FALSE, column_prefix and explicit rate uncertainty sd are supported. The default reviewed choice is keep; remove_predicted requires available saved evidence and exact whole-strategy approval. Processed entry supports keep only. See docs/DOUBLET_REVIEW.md for the full contract and applicability limits.}
\item{qc_mad}{Optional explicit deterministic MAD panel for raw strategy entry. Grouping declares a sourced qc_group or sample metadata column independently of capture/donor, or a sourced single analysis pool. Counts/features use log10(x+1), median and scaled MAD with constant 1.4826; mitochondrial upper tails use original percentages. Six saved presets include keep_all, conservative_and3, three single-indicator choices and any_quality3. Only an available, hash-bound preset in a scagentkit.qc.mad.v1 proposal can execute after central approval. A nested prefilter defaults to none; min_counts requires an explicit integer from 1 through 200, source and preapproved = TRUE. Capture scoring precedes later quality filtering; automatic rates use the original called cohort. Small groups, zero/near-zero MAD or missing measurements block affected presets; high RNA only flags and ribosomal/Hb measurements are diagnostic only. Legacy range semantics remain unchanged when this option is disabled. See docs/MAD_REVIEW.md.}
\item{subcluster_origin, subcluster_creation, .subcluster_lock_owner}{Internal immutable origin, creation receipts and exact current-process initialization lock used by \code{sc_run_subcluster}. Use that scoped creation entry point rather than supplying these fields directly.}
\item{strategy_proposal}{Complete scagentkit.strategy.v1 proposal; supplying it enables strategy. Typed QC, normalization, PC, batch none/manual, resolution and UMAP settings are centrally reviewed. Arbitrary code, automatic Harmony and subcluster operations are unsupported. Optional cycle diagnostics permit approved none/full/difference choices. A complete explicit doublet_diagnostics configuration list enables keep/remove_predicted choices with a recorded reason; removal additionally requires available saved evidence, raw strategy and exact whole-strategy approval. Other doublet operations are unsupported. The legacy qc_doublet wrapper is not invoked. Manual batch handling stops before computation. Processed entry explicitly reuses QC and analysis with null execution settings and permits only doublet keep.}
\item{provider}{Provider name or safe configuration list. Built-in DeepSeek and Grok use runtime environment keys.}
\item{chat_fn}{Explicit in-memory function accepting system and user prompts. Never saved.}
\item{budget}{Project USD reservation limit. Default zero. Unknown accounting holds its reservation.}
\item{review}{Named policy: allow_external permits an exact-payload transfer approval node; preapprove_qc explicitly supplies a typed rule.}
\item{start_stage}{qc for raw input, or processed to reuse existing analysis.}
\item{processed_reason}{Required provenance for processed entry and skipped QC/analysis.}
\item{assay, counts_layer, normalized_layer, cluster_column}{Explicit source assay, genuine raw counts, normalized layer and cluster membership. Ambiguous layers fail closed.}
\item{analysis}{Supported settings passed to \code{sc_project_prepare}.}
\item{reference}{Optional supplied local annotation marker reference.}
\item{reference_review}{Explicit top_n, case-sensitive symbol_aliases, label_map, declared child/parent/lineage label_relations, independent/guided ai_mode and safe provenance. Species/tissue are scoped by declared context. No automatic ontology or alias guessing.}
\item{annotation_history}{Readonly historical import with annotations, response_paths, optional source_object_path and source_cluster_column, provider, model, reference_dependency and note. Source files are hashed and source-object cell/cluster scope is checked; extracted rows remain caller-declared interpretations. No new model call occurs.}
\item{annotation_column}{Fresh output metadata column. The label, confidence and rationale column names are checked against existing metadata and the cluster column before analysis; existing labels are preserved.}
\item{qc_proposal, annotation_proposal, proposal}{Typed QC, annotation or strategy data. The propose helper also accepts a local JSON file path.}
\item{proposal_hash}{Exact current review hash returned by inspect.}
\item{qc_preview}{Local preview options with explicit sensitivity candidates and named gene_panels. These never choose or change the executable QC proposal.}
\item{sensitivity}{Up to six explicit id/proposal comparisons, or NULL to keep the current comparisons.}
\item{gene_panels}{Named character gene vectors for exact availability disclosure only; no expression or quality scoring is performed.}
\item{preview_hash}{Exact saved QC preview fingerprint. Optional in headless decisions because proposal_hash already binds the preview; mandatory in atomic workbench actions.}
\item{expected_revision}{Optional expected state revision for headless actions; mandatory for the workbench.}
\item{action}{approve, reject, revise, QC preview, or executed annotation undo. No review action resumes analysis or contacts a provider.}
\item{kind}{The inspected review kind: qc, strategy or annotation.}
\item{project_id, input_hash}{Exact project identity and original input fingerprint from the inspected review_node.}
\item{review_hash}{Exact immutable QC, strategy or annotation review fingerprint from review_node.}
\item{reviewer, reason}{Analyst identity and rationale recorded in history.}
\item{retry}{Explicitly retry an incomplete/failed stage. Unknown external delivery is never automatically resent.}
\item{decision_id}{Executed annotation approval ID to undo.}
\item{token}{Exact stopped lock owner's token. Remote owner termination must be independently verified.}
}
\description{Diagnoses raw inputs, persists aggregate QC evidence, obtains a typed proposal and returns at review before filtering or basic analysis. Exact approval permits copy-based QC, standard analysis, markers, independent local-reference and model annotation suggestions, then reviewed new metadata and local outputs. No browser or manual archive transfer is required.}
\details{The authoritative state and hash-chained history are atomically committed locally. Input, evidence, provider settings, relevant configuration and implementation fingerprints bind approvals. QC impact is persisted before review and includes exact literal cell scope, independently removed and overlapping conditions, missing measurements, before/after distributions, optional explicit comparisons, and local gene availability. Changes create a fresh preview and proposal hash and append reasons; stale approval is refused. Annotation review persists every cluster's exact cell scope, proposed label, qualitative confidence, rationale, cited and supplied marker statistics, and actually supplied local-reference candidates/provenance. A missing top marker does not establish absent expression; confidence is not a calibrated probability. Saved mock, provider-response and manual artifacts are distinguished. Typed revisions create fresh review snapshots before approval; annotation undo archives previous outputs through the existing supported path. Existing versioned snapshots remain. Checkpoints and request caches permit a new R process to resume without repeating completed stages. External payloads require an explicit transfer approval and transmit aggregate evidence and supplied context, including declared sample/capture labels; private review snapshots are not model payloads. Credentials remain in runtime environment or caller memory. The loopback workbench can review QC, a concentrated strategy, and annotation for one configured run through the same locked R authority. Explicit R resume or the enabled fixed local Continue worker performs supported local computation; review actions alone do not execute it. Headless review remains available. Strategy mode supports fixed or computed-variance PCs and bounded clustering settings, with batch none or an explicit manual stop. Automatic batch integration and subcluster execution are unsupported. Explicit cycle diagnostics and approved none/full/difference scaling choices are supported in raw strategy mode.

Enabled doublet diagnostics retain fixed full-input pre-QC scores by exact cell ID. Scores are not calibrated probabilities, classes are predictions, and homotypic doublets can be missed. Only explicitly approved remove_predicted removes saved predictions within the approved QC scope; high RNA content or cycling alone does not remove cells. At least 100 cells per capture, 200 raw counts per cell, enough expressed features and compatible dimensions are scoring applicability prerequisites, never automatic QC filters. An inapplicable reference records Unknown/NA for all input cells and supports keep only. Missing dependencies or a strict scDblFinder 1.26.7 algorithm/audit failure remain recoverable failures without a heuristic fallback. Diagnostics parameters are immutable; changing them requires a fresh project. Changing the reviewed keep/remove choice creates a fresh whole-strategy hash and invalidates necessary downstream analysis while reusing the fixed diagnostics and QC reference. Existing doublet and annotation metadata are preserved in fresh output columns. Local exact-ID scores and selection tables are not model payloads.

Computed artifacts are EXECUTED, while sc_run_accept records explicit RESULT_ACCEPTED scientific assessment. See docs/ANALYSIS_STRATEGY_SUPPORT.md, docs/DOUBLET_REVIEW.md, docs/ANNOTATION_REVIEW.md, docs/QC-review.md and docs/SERVER_FIRST.md for workflows and limitations.}
\value{Status, current stage, revision, diagnostics, proposal and hash when awaiting review, and output paths when complete. Unlock returns invisible TRUE.}
