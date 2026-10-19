\name{annot_act_reference}
\alias{annot_act_reference}
\title{Load the pinned private ACT snapshot offline}
\usage{annot_act_reference(species, tissue)}
\arguments{
\item{species}{Explicit human or mouse scope.}
\item{tissue}{Actual tissue, matched exactly after trimming and case folding. No all-tissue fallback.}}
\value{A marker reference retaining original PMID strings, source rows/files/URLs and pinned snapshot provenance. Zero matches return an empty scoped table with a notice.}
\description{Private local development build only. Verifies compressed and original SHA256 and never downloads data or constructs a model client. Database redistribution permission is unconfirmed; paper citation or open-access status is not assigned as its license. New modern projects use this default; explicit reference=NULL opts out. Existing projects keep saved references and approvals.}
