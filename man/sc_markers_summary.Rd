\name{sc_markers_summary}
\alias{sc_markers_summary}
\title{Filter and rank a supplied marker table}
\usage{
sc_markers_summary(obj, top_n = 30, log2fc_cut = 1, padj_cut = 0.05, output_path = NULL)
}
\arguments{
\item{obj}{Full marker data.frame.}
\item{top_n, log2fc_cut, padj_cut}{Existing strict summary settings.}
\item{output_path}{Optional explicit summary text file; default writes nothing.}
}
\description{Filter and rank a supplied marker table}
\value{Filtered data.frame with summary_lines and cycling_score attributes.}
