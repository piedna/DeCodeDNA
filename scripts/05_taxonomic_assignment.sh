#!/usr/bin/env bash
# scripts/05_taxonomic_assignment.sh
#
# Step V: Taxonomic Assignment
#
# Input:
#   • lulu_filtered_otu_table_combined.csv  (curated OTU counts, wide format)
#   • otu_representatives_combined.fasta    (all OTU representative sequences)
#
# Process:
#   1) Extract kept OTU hashes & subset survivors FASTA
#   2) BLAST survivors against the MitoFish database
#   3) Parse BLAST results and join with OTU counts in R to produce final abundance matrix
#
# Output:
#   • final_taxon_table_combined.csv       (species × sample abundance matrix)
#
# Tools:
#   - seqkit         (for FASTA subset)
#   - blast+ (blastn, makeblastdb)
#   - Rscript        (requires R packages: dplyr, tidyr, readr, tibble, stringr)
#
# BEFORE YOU RUN:
#   If you’re using the Conda-based pipeline, install BLAST+ and R via Conda:
#
#     conda create -n taxo-env \
#       python=3.10 seqkit blast r-base r-lulu \
#       r-dplyr r-tidyr r-readr r-tibble r-stringr \
#       -c conda-forge -c bioconda -y
#     conda activate taxo-env
#
#   Then download (or place) the MitoFish FASTA:
#
#     wget https://mitofish.aori.u-tokyo.ac.jp/contents/download/mito-all.fasta
#
#   Build the BLAST database:
#
#     makeblastdb \
#       -in mito-all.fasta \
#       -dbtype nucl \
#       -parse_seqids \
#       -out mitofish_db
#
#   Verify:
#     ls mitofish_db.*
#     blastn -db mitofish_db -query mito-all.fasta -max_target_seqs 1 -outfmt 6 | head
#
set -euo pipefail

### ── USER CONFIG ─────────────────────────────────────────────────
BASE_DIR="${1:?Error: need BASE_DIR with your OTU files}"
MITO_DB="${2:-mitofish_db}"    # BLAST DB prefix
THREADS="${3:-8}"              # threads for BLAST
LOGFILE="${LOGFILE:-05_taxo.log}"

cd "$BASE_DIR"
echo "Logging to $LOGFILE"
echo | tee "$LOGFILE"

### ── 1) Extract & subset survivors ---------------------------------
echo "▶ Step 1: Extracting kept OTU hashes" | tee -a "$LOGFILE"
cut -d',' -f1 lulu_filtered_otu_table_combined.csv | tail -n +2 > kept_hashes.txt
echo "  • $(wc -l < kept_hashes.txt) hashes → kept_hashes.txt" | tee -a "$LOGFILE"

echo "▶ Step 1b: Subsetting survivor sequences" | tee -a "$LOGFILE"
seqkit grep -nr -f kept_hashes.txt otu_representatives_combined.fasta \
  2>&1 | tee -a "$LOGFILE" > otu_survivors.fasta
echo "  • $(grep -c '^>' otu_survivors.fasta) survivors → otu_survivors.fasta" | tee -a "$LOGFILE"

echo | tee -a "$LOGFILE"

### ── 2) BLAST survivors → MitoFish -----------------------------------
echo "▶ Step 2: BLAST survivors against MitoFish DB ($MITO_DB)" | tee -a "$LOGFILE"
if [[ -s survivors.blast ]]; then
  echo "  • survivors.blast already exists; skipping BLAST" | tee -a "$LOGFILE"
else
  blastn \
    -query otu_survivors.fasta \
    -db "$MITO_DB" \
    -num_threads "$THREADS" \
    -perc_identity 95 \
    -evalue 1e-20 \
    -max_target_seqs 10 \
    -outfmt '6 qseqid sscinames pident length qcovs evalue bitscore' \
    > survivors.blast 2>&1 | tee -a "$LOGFILE"
  echo "  • BLAST complete → survivors.blast" | tee -a "$LOGFILE"
fi

echo | tee -a "$LOGFILE"

### ── 3) Parse BLAST & build final table in R -----------------------
echo "▶ Step 3: Parsing BLAST & finalizing taxon table in R" | tee -a "$LOGFILE"
Rscript <<'EOF' 2>&1 | tee -a "$LOGFILE"
library(dplyr)
library(tidyr)
library(readr)
library(stringr)
library(tibble)

# 3a) Pivot OTU counts to long form
counts_wide <- read_csv('lulu_filtered_otu_table_combined.csv', col_types = cols(OTU = col_character()))
counts_long <- counts_wide %>%
  rename(Hash = OTU) %>%
  pivot_longer(-Hash, names_to = 'SampleMethod', values_to = 'nReads') %>%
  filter(nReads > 0)

# 3b) Read BLAST hits and pick best per OTU
blast_df <- read_tsv('survivors.blast',
  col_names = c('Hash','Species','pident','length','qcovs','evalue','bitscore'),
  col_types = cols()
)
blast_top <- blast_df %>%
  group_by(Hash) %>%
  slice_max(bitscore, n = 1, with_ties = FALSE) %>%
  ungroup()

# 3c) Join species and fill missing
otu_taxa <- counts_long %>%
  left_join(blast_top %>% select(Hash, Species), by = 'Hash') %>%
  replace_na(list(Species = 'unassigned'))

# 3d) Pivot back to species × sample matrix
final_taxa <- otu_taxa %>%
  group_by(Species, SampleMethod) %>%
  summarise(nReads = sum(nReads), .groups = 'drop') %>%
  pivot_wider(names_from = SampleMethod, values_from = nReads, values_fill = 0)

# 3e) Write out
write_csv(final_taxa, 'final_taxon_table_combined.csv')
cat('Wrote final_taxon_table_combined.csv\n')
EOF

echo | tee -a "$LOGFILE"
echo "Step V complete: final_taxon_table_combined.csv generated" | tee -a "$LOGFILE"