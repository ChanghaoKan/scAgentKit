\name{sc_cycle_gene_set}
\alias{sc_cycle_gene_set}
\title{Declare a literal, versioned cell-cycle gene set}
\usage{
sc_cycle_gene_set(species, s_genes = NULL, g2m_genes = NULL,
  source = NULL, version = NULL, symbol_mapping = NULL)
}
\arguments{
\item{species}{Explicit human or mouse declaration, ignoring case and surrounding whitespace. Human aliases are human, Homo sapiens, homo_sapiens, homo-sapiens, h. sapiens, h.sapiens, hsapiens and the character string "9606". Mouse aliases are mouse, Mus musculus, mus_musculus, mus-musculus, m. musculus, m.musculus, mmusculus and the character string "10090". Other species are unsupported.}
\item{s_genes, g2m_genes}{Literal, nonempty character vectors for S and G2/M programs. Supply both vectors for a custom gene set, or leave both NULL for the built-in human set. Symbols are matched exactly and case sensitively.}
\item{source, version}{Nonempty provenance strings required for custom lists. The built-in human source and version are fixed and cannot be overridden.}
\item{symbol_mapping}{Optional named character vector mapping every distinct canonical symbol in the two lists to its literal input feature identifier. Names and values must be unique, and the mapping must cover the complete union of declared symbols exactly. No case conversion, synonym search or ortholog inference is performed.}
}
\description{Constructs a hashed species and provenance declaration for the gene_set option of sc_run(cycle_diagnostics = ...). It neither scores cells nor changes an input object.}
\details{
The built-in human set comes only from the installed Seurat package's cc.genes.updated.2019 data. The declaration records source Seurat::cc.genes.updated.2019, version 2019, the installed Seurat package version and a gene-set hash. If the data are unavailable, no fallback is selected. Mouse requires explicit versioned S and G2/M lists; human symbols are never automatically converted to mouse symbols.

Cell-cycle diagnostics require an explicit matching context$species. They score a nonfiltering copy of the full input before approved QC and preserve that scoring reference for retained cells. Program coverage and scoring preconditions determine software applicability, not scientific adequacy. Insufficient evidence yields Unknown phases and NA scores; the reviewed none choice remains available, while full and difference regression are rejected.

The ordinary choices are none to keep cycle signal (the default), or standard full regression using the quantitative S and G2/M scores. Difference regression is advanced and optional: it uses S minus G2/M, targeting phase contrast among cycling cells while retaining the cycling versus noncycling distinction. All choices use the same whole-strategy approval; no extra cycle approval or cell deletion is introduced. A research goal concerning cell cycle or proliferation suggests considering retained signal, but never forces a method or establishes an automatically best choice. See docs/CELL_CYCLE_REVIEW.md.
}
\value{A scagentkit.cycle-gene-set.v1 list containing canonical species, source, version, canonical and input S/G2M vectors, an optional explicit symbol_mapping, built-in package provenance when applicable, and gene_set_hash. Keep the declaration intact.}
\seealso{\code{sc_run}, \code{sc_run_strategy_revise}}
\references{
\href{https://satijalab.org/seurat/articles/cell_cycle_vignette}{Seurat cell-cycle scoring and regression vignette}.
\href{https://satijalab.org/seurat/reference/cellcyclescoring}{Seurat CellCycleScoring reference}.
}
\examples{
human_set <- sc_cycle_gene_set("human")

# Explicit custom provenance; these small lists illustrate the declaration only.
# They do not establish adequate coverage for any dataset.
custom_set <- sc_cycle_gene_set("Homo sapiens",
  s_genes = c("MCM5", "PCNA"),
  g2m_genes = c("CDK1", "TOP2A"),
  source = "Analyst-supplied example lists", version = "example-v1")
}
