# scAgentKit development container
#
# Pins the R base image and package release references. CRAN/Bioconductor
# dependencies are resolved when the image is built; use a lockfile or image
# digest as well if exact environment reconstruction is required.
#
# Build:
#   docker build -t scagentkit:0.4.0 .
#
# Run interactively (with your scratch dir mounted and API key passed in):
#   docker run --rm -it \
#     -v $(pwd):/workspace \
#     -w /workspace \
#     -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
#     scagentkit:0.4.0 R
#
# Run a script:
#   docker run --rm -v $(pwd):/workspace -w /workspace scagentkit:0.4.0 \
#     Rscript analysis.R

FROM rocker/r-ver:4.4.2

LABEL maintainer="Changhao Kan <kch_ynu@163.com>"
LABEL org.opencontainers.image.source="https://github.com/ChanghaoKan/scAgentKit"
LABEL org.opencontainers.image.version="0.4.0"

# System libs needed for Seurat, hdf5, png/jpeg I/O, httr2, magick
RUN apt-get update && apt-get install -y --no-install-recommends \
        libhdf5-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libpng-dev \
        libjpeg-dev \
        libtiff-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libcairo2-dev \
        libgit2-dev \
        libmagick++-dev \
        pandoc \
        git \
    && rm -rf /var/lib/apt/lists/*

# Installer helpers
RUN R -e "install.packages(c('remotes', 'BiocManager'))"

# Bioconductor deps that scAgentKit Suggests
RUN R -e "BiocManager::install(c('scDblFinder', 'SingleCellExperiment'), ask = FALSE, update = FALSE)"

# Core scAgentKit Imports + key Suggests
RUN R -e "install.packages(c( \
        'Seurat', 'dplyr', 'tibble', 'ggplot2', 'Matrix', 'qs2', \
        'harmony', 'clustree', 'base64enc', 'httr2', 'magick', 'png', \
        'readxl', 'jsonlite', 'future', 'future.apply', \
        'ontologyIndex', 'testthat', 'knitr', 'rmarkdown'), \
        repos = 'https://cloud.r-project.org')"

# SeuratData (GitHub)
RUN R -e "remotes::install_github('satijalab/seurat-data', upgrade = 'never')"

# Install the shared core explicitly before the local package. Override the
# release reference at build time only when testing a compatible core branch.
ARG AGENTOMICS_CORE_REF=v0.1.1
RUN R -e "remotes::install_github('ChanghaoKan/agentomicsCore@${AGENTOMICS_CORE_REF}', upgrade = 'never', dependencies = c('Depends', 'Imports'))"

# Install scAgentKit from the local build context.
COPY . /tmp/scAgentKit
RUN R -e "remotes::install_local('/tmp/scAgentKit', upgrade = 'never', dependencies = FALSE)" \
    && rm -rf /tmp/scAgentKit

WORKDIR /workspace

CMD ["R"]
