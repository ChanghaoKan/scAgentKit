\name{annot_match_reference}
\alias{annot_match_reference}
\title{Match an explicit marker table against a local reference}
\usage{
annot_match_reference(obj, reference, top_n_candidates = 5)
}
\arguments{
\item{obj}{Filtered marker data.frame with cluster and gene columns.}
\item{reference}{Local reference data.frame with cell_type and marker columns.}
\item{top_n_candidates}{Maximum positive-overlap candidates per cluster.}
}
\description{Match an explicit marker table against a local reference}
\value{Candidate data.frame, with all_matches and reference_provenance attributes. Scores are reference-marker coverage, not label confidence or approval.}
