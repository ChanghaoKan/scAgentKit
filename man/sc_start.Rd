\name{sc_start}
\alias{sc_start}
\title{Start or reopen a reviewed analysis in the local browser}
\usage{
sc_start(input, project_dir, context = NULL, checkout = NULL,
  python = NULL, browse = interactive(), reuse_processed = FALSE,
  processed_reason = NULL, cluster_column = "seurat_clusters",
  model_suggestions = c("auto", "off", "configured", "simulate"),
  sample_id = NULL, matrix_kind = NULL, cell_metadata = NULL,
  feature_key = c("name", "id"), scientific_review = NULL,
  provider = NULL, budget = 0, review = list(allow_external = FALSE))
}
\arguments{
\item{scientific_review}{Explicit optional rebuilding/extended expression diagnostics for a new raw project, disabled by default. Applicable declared-human blood/PBMC or pancreas classic panels remain baseline evidence. Reopening cannot replace saved settings.}
\item{input}{Local RDS file containing raw counts or a Seurat object, a 10x MEX directory, or a sample table data.frame/CSV/TSV.}
\item{sample_id,matrix_kind}{For one 10x MEX directory, explicit sample ID and raw/filtered declaration. Sample tables instead require sample_id, path, matrix_kind columns. Optional donor/condition/batch/capture/treatment/qc_group/group columns declare those metadata roles. Filtered is a user declaration, not independent evidence of empty-droplet processing.}
\item{cell_metadata}{Optional data.frame/CSV/TSV keyed by sample_id and barcode. Must cover every imported barcode exactly once; joins use keys rather than row positions. Extra/missing/duplicate keys and overlapping sample/cell fields are rejected.}
\item{feature_key}{Original feature name (default) or compatible ID as analysis row names. ID/name/type and analysis keys are retained in assay metadata. Name mode gives incompatible names neutral technical keys and all duplicate-name members a stable feature-ID hash suffix; the local preapproval import summary lists the exact changes. No gene rows are collapsed. ID keys that Seurat would rename are rejected. ID keys may make symbol-based mitochondrial, cycle and reference evidence unavailable; no mapping is inferred. Across samples, require the same Gene Expression ID set and consistent annotations, then reorder by ID. Other modalities are excluded with counts recorded; no gene intersection/union is applied.}
\item{project_dir}{New project path or the same saved project to reopen.}
\item{context}{Declared species, tissue, research_goal and optional notes, columns and design; required for a new project, otherwise saved context is used.}
\item{checkout}{Optional matching developer checkout, selected explicitly or via options(scAgentKit.checkout=...). Installed package resources are the default.}
\item{model_suggestions}{Operator mode: auto (default; selects configured suggestions or mock simulation from the saved provider), off, configured, or simulate (immutable mock provider only). Preview and exact transfer authorization remain separate from scientific approval.}
\item{provider}{Explicit name/list, including name='openai_compatible' with HTTPS base_url, model and api_key_env. NULL detects exactly one DeepSeek/Grok key; missing or ambiguous keys fall back to manual mode with a notice. Keys are never saved.}
\item{budget}{Explicit nonnegative project USD cap; default zero pending measured real-provider calibration.}
\item{review}{Creation-time list with allow_external=TRUE/FALSE. Omit transfer_consent for strict approval of each external payload. To confirm one creation-time scope, add transfer_consent=list(mode='project', confirmed=TRUE, reviewer='...', reason='...', categories=c('study_context','aggregate_qc','aggregate_markers','aggregate_design','aggregate_expression')). This binds the provider, prompt version and explicit budget. Only requests within these categories skip repeated transfer approval. Payload previews remain available; no scientific approval is granted.}
\item{python}{Existing Python 3.9+ executable, detected by default.}
\item{browse}{Open the URL in the browser; FALSE returns it without browser dispatch.}
\item{reuse_processed}{Explicitly reuse processed layers and clusters. FALSE by default.}
\item{processed_reason}{Required rationale for processed reuse.}
\item{cluster_column}{Saved cluster column for processed reuse.}
}
\value{Invisibly, the service URL, PID, project ID and reuse status.}
\description{Thin R entry into the existing local launcher and review service. Returns control to R. New projects start at strategy review; explicit processed reuse starts at annotation. Neither startup nor reopening approves labels or starts analysis/provider requests. The service allows bound review writes and explicit local continuation. Existing project authority is never replaced.}
\details{Requires the installed R package and Python 3.9+. Browser assets and Python modules ship with the package; the Python interpreter is not included. Runtime asset hashes and R function signatures must match. No software or credentials are installed. The current R executable and library paths are passed to the existing launcher. Repeating the call with the same project reuses its matching live service, or restarts a stopped service. Original RDS path/checksum and saved configuration must match. For 10x, the exact source receipt and generated input checksum must match; temporary adapter paths may differ. Source inputs and import options must be unchanged. The protected input checkpoint retains source provenance. Generated transport RDS files are removed after startup. Use \code{sc_run_open()} for a read-only result viewer.}
