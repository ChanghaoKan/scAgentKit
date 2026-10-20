\name{sc_react_eval}
\alias{sc_react_eval}
\title{Evaluate saved baseline and ReAct annotation drafts}
\usage{
sc_react_eval(project, truth, external = list(), label_map = NULL,
  allowed_ancestors = character(), obo_path = NULL, output_dir = NULL)
}
\arguments{
\item{project}{Project with a completed ReAct annotation session.}
\item{truth}{CSV path or data frame with cell_id or cluster_id and label. Dual cell truth may instead supply label_author and label_independent. Optional cl_id columns must agree with exact mappings.}
\item{external}{Named list of external CSV paths or data frames in the same label format. Independently clustered results must use cell IDs.}
\item{label_map}{Named character map, or list of prediction and truth maps. Existing evaluation-v1 map sections are accepted; unresolved coarse names require an explicitly frozen CL mapping.}
\item{allowed_ancestors}{Meaningful CL IDs frozen before evaluation. Only these ancestors within three is_a edges receive hierarchical credit. Empty means exact credit only.}
\item{obo_path}{Local CL ontology file, or NULL for the bundled snapshot.}
\item{output_dir}{New output directory. NULL creates a fresh project evaluation directory.}
}
\description{Scores all clusters and ReAct-targeted clusters with explicit mapping coverage and denominators. Unmapped predictions are excluded from primary accuracy and counted as errors in strict accuracy. Unknown predictions remain in both denominators.}
\value{Versioned metrics, per-cluster outcomes, steps, fallback distribution, recorded usage and cost, configuration and provenance, exported as CSV and JSON.}
\details{Cell labels require at least 80 percent mapped coverage and an 80 percent majority among mapped labels for cluster truth. Dual human truth is reconciled without consulting predictions, using exact agreement or a unique nearest allowed common ancestor. Disagreements are recorded separately. Cost totals are recorded subtotals with unknown-call counts; baseline accounting includes all annotation-purpose project calls. This evaluator does not call a provider or approve results.}
