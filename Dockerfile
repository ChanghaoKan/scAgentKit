# scAgentKit reproducibility container
#
# Pins R + Seurat + Bioconductor + scAgentKit dependencies so anyone with
# Docker can rerun the published analyses without dependency drift.
#
# Build:
#   docker build -t scagentkit:0.2.0 .
#
# Run interactively (with your scratch dir mounted and API key passed in):
#   docker run --rm -it \
#     -v $(pwd):/workspace \
#     -w /workspace \
#     -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
#     scagentkit:0.2.0 R
#
# Run a script:
#   docker run --rm -v $(pwd):/workspace -w /workspace scagentkit:0.2.0 \
#     Rscript analysis.R

FROM rocker/r-ver:4.4.2

LABEL maintainer="Changhao Kan <kch_ynu@163.com>"
LABEL org.opencontainers.image.source="https://github.com/ChanghaoKan/scAgentKit"
LABEL org.opencontainers.image.version="0.2.0"

# System libs needed for Seurat, hdf5, png/jpeg I/O, httr2, magick
RUN apt-get update && apt-get install -y --no-install-recommends \
        libhdf5-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libpng-dev \
        libjpeg-dev \
        libtiff5-dev \
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

# CRAN deps (rocker pins the snapshot for reproducibility)
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

# scAgentKit itself — install from the local context. Override to a tag
# in CI by passing --build-arg SCA_REF=v0.2.0.
ARG SCA_REF=HEAD
COPY . /tmp/scAgentKit
RUN R -e "remotes::install_local('/tmp/scAgentKit', upgrade = 'never', dependencies = TRUE)" \
    && rm -rf /tmp/scAgentKit

WORKDIR /workspace

CMD ["R"]
