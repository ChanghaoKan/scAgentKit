\name{annot_query_cellmarker}
\alias{annot_query_cellmarker}
\title{Import a locally obtained CellMarker 2.0 table with explicit scope}
\usage{
annot_query_cellmarker(species, tissue = NULL, cancer_only = FALSE,
  force_refresh = FALSE, url = NULL,
  local_file = NULL, sha256 = NULL)
}
\arguments{
\item{species}{One of human or mouse; applied to the table species column.}
\item{tissue}{Required nonempty literal tissue filter, case insensitive.}
\item{cancer_only}{Restrict to non-Normal cancer context when TRUE.}
\item{force_refresh}{TRUE requests automatic refresh, which is unavailable and rejected; use a local_file.}
\item{url}{Only the fixed official HTTPS URL is recognized; no mirrors.}
\item{local_file}{Explicit path to a lawfully obtained local XLSX file.}
\item{sha256}{Optional expected local SHA256; this is a user input check, not a verified publisher pin.}
}
\value{Scoped marker reference with local provenance and explicit zero-match status.}
\description{Automatic retrieval is waiting for a verified fixed official HTTPS asset. No CellMarker database is bundled or redistributed. If the source permits access, download through its official browser page and pass the local path. A local digest identifies the input without proving publisher authenticity or granting redistribution rights.}
\details{Official page: \url{https://bio-bigdata.hrbmu.edu.cn/CellMarker2.0/CellMarker_download.html}. The package does not fall back to HTTP, IP mirrors, arbitrary URLs, latest URLs or first-use hash trust. Both species and tissue are explicit; zero matches never expand to all tissues. Gene symbols use Symbol, then gene_symbol, then marker (which may contain protein aliases).}
