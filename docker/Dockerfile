# syntax=docker/dockerfile:1
#
# DeCodeDNA container image: every tool the pipeline needs, one image for
# macOS, Windows (Docker Desktop / WSL2) and Linux, on amd64 and arm64.
#
# Build from the repository root:
#   docker build -f docker/Dockerfile -t decodedna .
#
# Reference databases (~200 GB) are NOT baked in; mount them at /databases.

FROM mambaorg/micromamba:1.5.10

# Pinned third-party sources (bump deliberately, then rebuild)
ARG LULU_COMMIT=50187ba8bb5eb3a36f4509e8dc0a7aeaa63a1e75
ARG AMPLICON_SORTER_COMMIT=bf50ddcceb5d162d95a4fa64ad09c0b3e574001f

# ── conda tools ─────────────────────────────────────────────────────────────
COPY --chown=$MAMBA_USER:$MAMBA_USER docker/environment.docker.yml /tmp/env.yml
RUN micromamba install -y -n base -f /tmp/env.yml && \
    micromamba clean --all --yes && \
    rm /tmp/env.yml

# Make the env active for the RUN steps below
ARG MAMBA_DOCKERFILE_ACTIVATE=1

USER root

# ── LULU (R package, not on CRAN/conda) ─────────────────────────────────────
RUN git clone --quiet https://github.com/tobiasgf/lulu /tmp/lulu && \
    git -C /tmp/lulu checkout --quiet "$LULU_COMMIT" && \
    R CMD INSTALL /tmp/lulu && \
    rm -rf /tmp/lulu && \
    Rscript -e 'library(lulu); library(dplyr); library(readr); library(tidyr); library(stringr)'

# ── amplicon_sorter (length-distribution plots in script 02) ────────────────
RUN mkdir -p /opt/amplicon_sorter && \
    curl -fsSL -o /opt/amplicon_sorter/amplicon_sorter.py \
      "https://raw.githubusercontent.com/avierstr/amplicon_sorter/${AMPLICON_SORTER_COMMIT}/amplicon_sorter.py" && \
    printf '#!/bin/sh\nexec python3 /opt/amplicon_sorter/amplicon_sorter.py "$@"\n' > /opt/conda/bin/amplicon_sorter && \
    chmod +x /opt/conda/bin/amplicon_sorter

# ── NCBI taxonomy for Krona and TaxonKit (snapshot taken at build time) ─────
ENV TAXONKIT_DB=/opt/taxonkit
RUN curl -fsSL -o /tmp/taxdump.tar.gz https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz && \
    mkdir -p "$TAXONKIT_DB" && \
    tar -xzf /tmp/taxdump.tar.gz -C "$TAXONKIT_DB" names.dmp nodes.dmp delnodes.dmp merged.dmp && \
    KRONA_TAX=/opt/conda/opt/krona/taxonomy && \
    mkdir -p "$KRONA_TAX" && \
    mv /tmp/taxdump.tar.gz "$KRONA_TAX/" && \
    tar -xzf "$KRONA_TAX/taxdump.tar.gz" -C "$KRONA_TAX" names.dmp nodes.dmp && \
    ktUpdateTaxonomy.sh --only-build && \
    test -s "$KRONA_TAX/taxonomy.tab" && \
    rm -f "${KRONA_TAX:?}/taxdump.tar.gz" "${KRONA_TAX:?}"/*.dmp && \
    date -u +%Y-%m-%d > /opt/taxonkit/SNAPSHOT_DATE && \
    taxonkit list --ids 9606 >/dev/null

# ── DeCodeDNA scripts + example data ────────────────────────────────────────
COPY scripts/ /opt/decodedna/scripts/
COPY workflows/ont_native_barcodes/README_ont_native.md \
     workflows/ont_native_barcodes/test_fhl_100k_3.fastq \
     workflows/ont_native_barcodes/test_fhl_150k_2.fastq \
     workflows/ont_native_barcodes/test_fhl_200k_1.fastq \
     /opt/decodedna/workflows/ont_native_barcodes/
COPY workflows/ont_native_barcodes/precomputed/ /opt/decodedna/workflows/ont_native_barcodes/precomputed/
COPY workflows/custom_cci_barcodes/README_custom_cci.md /opt/decodedna/workflows/custom_cci_barcodes/
COPY workflows/custom_cci_barcodes/02_demultiplexed/ /opt/decodedna/workflows/custom_cci_barcodes/02_demultiplexed/
COPY docker/decodedna /opt/conda/bin/decodedna
RUN chmod -R a+rX /opt/decodedna /opt/taxonkit && chmod +x /opt/conda/bin/decodedna

# Writable home for any user id (the launchers run as the host user on Linux)
RUN mkdir -p /home/decodedna && chmod 1777 /home/decodedna
ENV HOME=/home/decodedna \
    DECODEDNA_ROOT=/opt/decodedna \
    DATABASE_DIR=/databases \
    MPLBACKEND=Agg

LABEL org.opencontainers.image.title="DeCodeDNA" \
      org.opencontainers.image.description="Oxford Nanopore eDNA metabarcoding pipeline" \
      org.opencontainers.image.source="https://github.com/piedna/DeCodeDNA" \
      org.opencontainers.image.licenses="MIT"

USER $MAMBA_USER
WORKDIR /work
VOLUME ["/work", "/databases"]

ENTRYPOINT ["/usr/local/bin/_entrypoint.sh", "tini", "-g", "--", "decodedna"]
CMD ["help"]
