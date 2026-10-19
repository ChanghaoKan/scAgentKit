\name{annot_map_to_cl}
\alias{annot_map_to_cl}
\title{Map supplied labels to exact Cell Ontology names or synonyms}
\usage{
annot_map_to_cl(obj, obo_path = NULL, column = NULL, map_cells = TRUE)
}
\arguments{
\item{obj}{Label data.frame or Seurat copy with a saved label column.}
\item{obo_path}{Explicit local CL OBO path; existing documented cache is supported.}
\item{column}{Label column, default label for a table or sc_annotation for Seurat.}
\item{map_cells}{Whether to append IDs to the returned Seurat copy (never project state).}
}
\description{Map supplied labels to exact Cell Ontology names or synonyms}
\value{Table with cl_id/cl_name, or a Seurat copy with cl_id/cl_name metadata. Matching is dictionary support, not semantic validation or scientific approval.}
