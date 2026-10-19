\name{qc_split}
\alias{qc_split}
\title{Split a Seurat copy by an explicitly supplied metadata column}
\usage{
qc_split(obj, split_by)
}
\arguments{
\item{obj}{Seurat object.}
\item{split_by}{Explicit complete metadata column; no role inference.}
}
\description{Split a Seurat copy by an explicitly supplied metadata column}
\value{Named list of Seurat objects. Does not fit models or approve QC.}
