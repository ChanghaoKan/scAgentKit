\name{annot_import_act}
\alias{annot_import_act}
\title{Import an explicit local ACT marker reference without network access}
\usage{annot_import_act(path = NULL, species, tissue, columns = NULL,
  source_version = NULL, source_date = NULL, sha256 = NULL, sheet = NULL)}
\arguments{
\item{path}{Local CSV/TSV/TXT/XLSX file; no automatic download.}
\item{species}{Explicit human or mouse.}
\item{tissue}{Nonempty actual tissue; literal case insensitive filter.}
\item{columns}{Named character mapping from species, tissue, cell_type, marker and pmid to actual source headers. Defaults to exact canonical headers.}
\item{source_version,source_date}{Known publisher version and ISO YYYY-MM-DD date; NULL records unavailable.}
\item{sha256}{Optional expected local file digest, not publisher authentication.}
\item{sheet}{Explicit XLSX sheet name/index; no first sheet is guessed.}}
\value{Scoped local reference preserving original PMID strings, source rows, observed SHA256 and unverified publisher provenance.}
\description{Import a lawfully obtained ACT table. No database is bundled, mirrored or silently replaced. ACT is an independent marker source; Cell Ontology remains a separate exact-ID dictionary. Invalid HTTPS certificates are never bypassed. Missing or zero-scope reference data does not establish biological absence.}
