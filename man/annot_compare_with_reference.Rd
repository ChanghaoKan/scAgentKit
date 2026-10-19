\name{annot_compare_with_reference}
\alias{annot_compare_with_reference}
\title{Compare saved labels to an explicitly selected reference by exact cell ID}
\usage{
annot_compare_with_reference(obj, reference_col = NULL, author_celltype = NULL, collapse_llm = FALSE, extra_map = NULL,
    label_col = "sc_annotation")
}
\arguments{
\item{obj}{Seurat object; this function never modifies it.}
\item{reference_col}{Explicit reference metadata column, or NULL for external labels.}
\item{author_celltype}{Named external reference vector covering current literal cell IDs.}
\item{collapse_llm}{Explicit logical choice to apply the broad-label utility; default FALSE.}
\item{extra_map}{Optional explicit broad-label mapping.}
\item{label_col}{Explicit predicted/reviewed label column, default sc_annotation.}
}
\description{Compare saved labels to an explicitly selected reference by exact cell ID}
\value{Descriptive comparison list, not biological accuracy or identity validation.}
