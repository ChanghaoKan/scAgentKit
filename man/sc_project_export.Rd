\name{sc_project_export}
\alias{sc_project_export}
\title{Export a portable local evidence project}
\usage{
sc_project_export(
  object,
  path,
  project_id,
  assay = "RNA",
  counts_layer = "counts",
  normalized_layer = "data",
  cluster_column = "seurat_clusters",
  reduction = "umap",
  marker_table = NULL,
  candidate_table = NULL,
  model_records = NULL,
  source_annotation = NULL,
  directed_clusters = NULL,
  display_name = project_id,
  metadata_allowlist = c("nCount_RNA", "nFeature_RNA", "percent.mt"),
  parameters = list(),
  provenance = list(),
  archive = FALSE
)
}
\arguments{
\item{object}{A processed Seurat object, or an AgentSeurat containing exactly
one Seurat object. The selected assay must cover every cell in the object.}
\item{path}{A new local project directory. Existing destinations are refused.}
\item{project_id}{An explicit, nonempty project identifier supplied by the
user. This is a literal string, not a filesystem path.}
\item{assay}{Exact assay name used for expression identity and evidence.}
\item{counts_layer}{Exact existing layer containing genuine finite,
nonnegative integer counts. Split layers must first be joined explicitly.}
\item{normalized_layer}{Exact existing normalized expression layer, or
\code{NULL} to export counts-only evidence.}
\item{cluster_column}{Metadata column containing complete cell-to-cluster
membership. IDs are preserved as exact strings; actual missing values are
rejected, while the literal string \code{"NA"} is valid.}
\item{reduction}{Existing two-dimensional embedding to export, or
\code{NULL} to export without an embedding.}
\item{marker_table}{Optional supplied marker records with columns
\code{clusterId}, \code{gene}, \code{avgLog2FC}, \code{pct1}, \code{pct2},
\code{pAdj}, and \code{source}.}
\item{candidate_table}{Optional supplied reference candidate records with
columns \code{clusterId}, \code{label}, \code{score}, \code{overlap},
\code{referenceSize}, \code{markers}, and \code{source}.}
\item{model_records}{Optional supplied model records with fields
\code{clusterId}, \code{callId}, \code{provider}, \code{mode},
\code{strictStatus}, \code{strict}, \code{posthoc}, \code{rawText}, and
\code{source}. Absent records remain absent.}
\item{source_annotation}{Optional original metadata annotation column to
include as source context. This is not an accepted review decision or a gold
standard.}
\item{directed_clusters}{Exact cluster IDs explicitly selected for targeted
T/NK RNA evidence. No clusters are selected by inferred lineage or numeric ID.
\code{NULL} exports no directed expression assets.}
\item{display_name}{Human-readable project name; defaults to \code{project_id}.}
\item{metadata_allowlist}{Metadata field names permitted in exported cell QC.
Only available fields in this list are exported.}
\item{parameters}{A named list of analysis parameters to retain in the snapshot.}
\item{provenance}{A named list of explicitly supplied source context.}
\item{archive}{Logical. If \code{TRUE}, also create
\code{paste0(path, ".zip")}; an existing archive is refused before writing
the directory.}
}
\value{
Invisibly, a list with \code{path}, \code{projectId},
\code{sourceFingerprint}, \code{bundleDigest}, and \code{archive}.
The archive field gives the archive path when requested.
}
\description{
Writes a new local evidence project with a checksummed manifest, a portable
project snapshot, and any explicitly requested targeted expression assets.
The input object is preserved. No normalization, cell filtering, model call,
or network download is performed by export.
}
\details{
The source fingerprint uses \code{scagentkit.source.v1} over all object cells,
exact cell and feature IDs, the chosen assay and layer names, actual counts
and normalized values, and exact cluster membership. Sparse matrices are
canonicalized without expanding the full assay into a dense matrix. Cell
and gene ordering, equivalent sparse representations, and unrelated metadata
do not change the source fingerprint. Expression values and membership do.

The bundle digest is SHA256 of the actual UTF-8 \code{project.json} bytes.
Its references include hashes of every dependent asset. Consequently,
parameters and evidence may change the bundle digest without changing the
expression source identity. \code{manifest.json} lists file byte counts and
SHA256 checksums.

Missing, ambiguous, or split layers and assays missing any object cell are
rejected. Export an already processed object directly, or explicitly call
\code{sc_project_prepare()} to create a prepared copy first.
\code{normalized_layer = NULL} permits counts-only export when cluster
membership already exists; normalization-dependent directed evidence remains
unavailable. Requested directed clusters then produce no assets and the
reason is recorded in \code{parameters$directedUnavailable}.
\code{reduction = NULL} serializes an unavailable embedding as
JSON null. Optional markers, candidates, and models are JSON arrays, including
when empty or containing a single record.

Directed assets use \code{scAgentKit.directed_expression.v2} with exact selected
cluster scopes and the source object fingerprint. Missing measurements remain
null and measured zeros remain zero. The exporter does not invent a Seurat
RDS checksum. No full expression matrix or RDS is required in the portable
project. Subsequent R review validation and writeback require the matching
original object and verified project directory.
}
\seealso{\code{\link{sc_project_prepare}}}
