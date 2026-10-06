\name{sc_run_subcluster_scope}
\alias{sc_run_subcluster_scope}
\alias{sc_run_subcluster_inspect}
\alias{sc_run_subcluster_list}
\title{Inspect frozen parent scope, registered children and exact apply evidence}
\usage{
sc_run_subcluster_scope(parent_project, clusters = NULL,
  cluster_column = NULL)

sc_run_subcluster_inspect(child_project, column = "sc_subtype",
  outside = "NA", supersedes = NULL)

sc_run_subcluster_list(parent_project, workspace)
}
\arguments{
\item{parent_project}{Completed parent run directory. The parent must have a journal-bound reviewed output and unambiguous literal cell IDs. This increment supports one parent-to-child level only.}
\item{clusters}{Optional unique character vector of exact parent cluster labels. NULL lists available labels and counts. Numeric row positions, duplicates and absent labels are rejected.}
\item{cluster_column}{Optional explicit parent metadata membership column for inspection. NULL uses the parent's configured cluster column. Creation uses that configured column.}
\item{child_project}{Independent child run created by \code{sc_run_subcluster}.}
\item{column}{Fresh subtype label column in a derived parent copy. The associated confidence, rationale, source-child and child-cluster columns must also be free of conflicts.}
\item{outside}{Outside-scope value policy. This increment supports the literal string \code{"NA"} only: actual NA values are retained outside the exact approved child scope.}
\item{supersedes}{Optional current active application ID belonging to this child and target column, authorizing a new immutable replacement version. It is not permission to merge or replace another child's application. An undone application is already inactive and cannot be superseded.}
\item{workspace}{Existing operator-selected child workspace outside the parent. Only immediate real child directories with verified matching parent provenance are registered.}
}
\description{Returns local exact-scope evidence without approving a proposal, running analysis, calling a provider or writing a derived object. Parent input, revision, cluster membership, counts and output bind the frozen origin; current child annotations and output bind apply evidence.}
\details{The whole-parent \code{parent_scope_hash} is independent of the selected cluster list. A selected preview separately records the union count and selection hash. Creation freezes the actual ordered literal cell IDs; parent cluster numbers are never parent row positions or child-to-parent cell mappings.

Child inspection includes its normal run status, origin, parent-current flag, integration revision, immutable application history and an apply snapshot when the child is complete and applicable. The apply snapshot contains both required action fields and display summaries. Pass only documented action fields to \code{sc_run_subcluster_apply}; do not blindly \code{do.call} with every displayed field.

The registry is a local operator interface. Its absolute project/output paths must not be accepted as browser arguments: the workbench uses registered project IDs and resolves their current matching provenance. Foreign children are not authorized merely because their cell IDs overlap. Stale parent authority is reported and blocks further child actions.}
\value{\code{sc_run_subcluster_scope} returns parent identity, whole-parent fingerprints, configured membership, species/tissue context, cluster counts and optional selection preview. \code{sc_run_subcluster_inspect} returns \code{run}, \code{origin}, \code{parent_current}, optional parent error, \code{integration_revision}, \code{applications} and optional \code{apply_snapshot}. \code{sc_run_subcluster_list} returns the verified parent-bound child registry, with local paths for R/operator use.}
\seealso{\code{sc_run_subcluster}, \code{sc_run_subcluster_apply}, \code{sc_run_subcluster_undo}, \code{sc_run_inspect}, \code{sc_run_review}, \code{sc_run_continue}}
