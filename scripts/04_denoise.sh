#!/usr/bin/env bash
# scripts/04_denoise.sh
#
# Step IV: Denoise with LULU
#
# Input:
#   • otu_representatives_combined.fasta  (merged ASVs with read counts)
#   • otu_table_combined.csv             (Sample, Method, Hash, nReads)
#
# Process:
#   1) Self-BLAST OTU reps (optional QC)
#   2) Run LULU algorithm for OTU curation
#   3) Sanity checks on retention & clustering
#
# Output:
#   • lulu_filtered_otu_table_combined.csv  (curated wide-format OTU table)
#
# Tools:
#   - vsearch
#       Used to self-align OTU reps and produce the LULU matchlist.
#   - Rscript
#       Requires R packages: lulu, dplyr, tidyr, readr, tibble, stringr.
#
# BEFORE YOU RUN:
#   1) Create & activate a fresh env:
#        conda create -n lulu-env \
#          python=3.10 vsearch r-base r-lulu \
#          r-dplyr r-tidyr r-readr r-tibble r-stringr \
#          -c conda-forge -y
#        conda activate lulu-env
#
#   2) Ensure you have:
#        • otu_representatives_combined.fasta
#        • otu_table_combined.csv
#
set -euo pipefail

### ── USER CONFIG ─────────────────────────────────────────────────
BASE_DIR="${1:?Error: need BASE_DIR with your OTU files}"
THREADS="${2:-8}"   # threads for vsearch self-BLAST
LOGFILE="${LOGFILE:-04_denoise.log}"

cd "$BASE_DIR"
echo "Logging to $LOGFILE"
echo | tee "$LOGFILE"
echo "🔹 Base directory: $BASE_DIR" | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

### ── 1) Self-BLAST OTU reps (optional QC) --------------------------
echo "▶ Step 1: Self-BLAST OTU representatives" | tee -a "$LOGFILE"
if [[ -f otu_representatives_combined.fasta ]]; then
  vsearch \
    --allpairs_global otu_representatives_combined.fasta \
    --id 0.84 \
    --blast6out otu_self_blast_combined.out \
    --threads "$THREADS" 2>&1 | tee -a "$LOGFILE"
  echo "    ✓ Created otu_self_blast_combined.out" | tee -a "$LOGFILE"
else
  echo "⚠️  otu_representatives_combined.fasta not found; skipping self-BLAST" | tee -a "$LOGFILE"
fi

echo | tee -a "$LOGFILE"

### ── 2) Run LULU algorithm for OTU curation ------------------------
echo "▶ Step 2: Run LULU to curate OTUs" | tee -a "$LOGFILE"
Rscript <<'EOF' 2>&1 | tee -a "$LOGFILE"
# Load required libraries
library(lulu)
library(dplyr)
library(tidyr)
library(readr)
library(tibble)
library(stringr)

# Read inputs
otu_long  <- read_csv('otu_table_combined.csv',
                      col_types = cols(
                        Sample = col_character(),
                        Method = col_character(),
                        Hash   = col_character(),
                        nReads = col_double()
                      ))
matchlist <- read_table2('otu_self_blast_combined.out',
                         col_names = c('qseqid','sseqid','pident'),
                         col_types = cols())

# Summarize & pivot
otu_sum  <- otu_long %>%
  group_by(Sample, Method, Hash) %>%
  summarise(nReads = sum(nReads), .groups = 'drop')

otu_wide <- otu_sum %>%
  unite(SampleMethod, Sample, Method, sep = '_') %>%
  pivot_wider(names_from = SampleMethod,
              values_from = nReads,
              values_fill = 0) %>%
  column_to_rownames('Hash')

# Run LULU
res <- lulu(otu_wide, matchlist,
            minimum_ratio_type         = 'min',
            minimum_ratio              = 1,
            minimum_match              = 84,
            minimum_relative_cooccurence = 0.95)
cat('    ✓ Discarded OTUs:', res$discarded_count, '\n')

# Write filtered OTU table
write_csv(as.data.frame(res$curated_table) %>% rownames_to_column('OTU'),
          'lulu_filtered_otu_table_combined.csv')
cat('    ✓ Wrote lulu_filtered_otu_table_combined.csv\n')
EOF

echo | tee -a "$LOGFILE"

### ── 3) Sanity checks on retention & clustering --------------------
echo "▶ Step 3: Sanity checks on retention & cluster metrics" | tee -a "$LOGFILE"
Rscript <<'EOF' 2>&1 | tee -a "$LOGFILE"
library(readr)
library(dplyr)
library(tidyr)
library(stringr)

# Load raw and curated tables
raw_long  <- read_csv('otu_table_combined.csv')
lulu_wide <- read_csv('lulu_filtered_otu_table_combined.csv',
                      col_types = cols(OTU = col_character()))

# Raw statistics
cat('  • RAW rows:    ', nrow(raw_long),
    '| distinct OTUs:', n_distinct(raw_long$Hash), '\n')

# Reads per SampleMethod before
raw_sums <- raw_long %>%
  unite(SampleMethod, Sample, Method, sep = '_') %>%
  group_by(SampleMethod) %>%
  summarise(RawReads = sum(nReads), .groups = 'drop')

# Reads per SampleMethod after
lulu_sums <- lulu_wide %>%
  select(-OTU) %>%
  summarise(across(everything(), sum)) %>%
  pivot_longer(everything(), names_to = 'SampleMethod', values_to = 'LULUReads')

# Combine & calculate retention percentages
check_df <- full_join(raw_sums, lulu_sums, by = 'SampleMethod') %>%
  mutate(pct_retained = 100 * LULUReads / RawReads)

cat('  • Retention min/med/max (%): ',
    min(check_df$pct_retained), '/',
    median(check_df$pct_retained), '/',
    max(check_df$pct_retained), '\n')
EOF

echo | tee -a "$LOGFILE"
echo "Step IV complete: lulu_filtered_otu_table_combined.csv generated" | tee -a "$LOGFILE"