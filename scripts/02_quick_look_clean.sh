#!/usr/bin/env bash
# scripts/02_quick_look.sh
#
# Quick Look pipeline (Kraken2 + Bracken + Krona) on basecalled & demuxed FASTQ
#
# 1) Classify against MiFish (fish-only) database
# 2) (Optional) Re-estimate abundances with Bracken
# 3) Classify against core-nt (vertebrate) database
# 4) Generate interactive Krona charts for both
#
# Usage:
#   bash scripts/02_quick_look.sh <FASTQ_DIR> <OUTPUT_DIR>
#
# Example:
#   bash scripts/02_quick_look.sh mock test_results/02_quick_look
#
# BEFORE YOU RUN:
# • Install via Conda (includes KronaTools):
#     conda install -c bioconda kraken2 bracken krona
#
# • Download & build your Kraken2 DBs once:
#
#   ## MiFish (fish mitochondria)
#   kraken2-build --download-taxonomy --db ~/kraken2_db/mitofish
#   kraken2-build --add-to-library mitofish_all_mitogenomes.fasta --db ~/kraken2_db/mitofish
#   kraken2-build --build --db ~/kraken2_db/mitofish
#
#   ## Core-NT (vertebrate RefSeq)
#   kraken2-build --download-taxonomy --db ~/kraken2_db/core_nt
#   kraken2-build --download-library vertebrate --db ~/kraken2_db/core_nt
#   kraken2-build --build --db ~/kraken2_db/core_nt
#
set -euo pipefail

### ── USER CONFIG ─────────────────────────────────────────────
# Point these to your built Kraken2 databases:
MITOFISH_DB="${MITOFISH_DB:-$HOME/kraken2_db/mitofish}"
CORE_NT_DB="${CORE_NT_DB:-$HOME/kraken2_db/core_nt}"

# Number of threads & confidence threshold (0.05 = 5%)
THREADS="${THREADS:-8}"
CONFIDENCE="${CONFIDENCE:-0.05}"

# Read length (bp) for Bracken abundance re-estimation
READ_LEN="${READ_LEN:-100}"

FASTQ_DIR="$1"
OUTPUT_DIR="$2"
### ─────────────────────────────────────────────────────────────

# sanity: do we have kraken2?
if ! command -v kraken2 &>/dev/null; then
  echo "Error: kraken2 not found. Install with:"
  echo "  conda install -c bioconda kraken2"
  exit 1
fi

# optional: do we have bracken?
if ! command -v bracken &>/dev/null; then
  echo "Warning: bracken not found; abundance re-estimation will be skipped"
  USE_BRACKEN=0
else
  USE_BRACKEN=1
fi

# optional: do we have KronaTools?
if ! command -v ktImportTaxonomy &>/dev/null; then
  echo "Warning: KronaTools not found; Krona charts will be skipped"
  USE_KRONA=0
else
  USE_KRONA=1
fi

# Create output dirs
mkdir -p "$OUTPUT_DIR"/mitofish "$OUTPUT_DIR"/core_nt

for FASTQ in "$FASTQ_DIR"/*.fastq "$FASTQ_DIR"/*.fastq.gz; do
  [[ -e "$FASTQ" ]] || continue
  BASENAME=$(basename "$FASTQ" | sed 's/\(.fastq.*\)//')
  echo
  echo "Processing sample: $BASENAME"

  ### ── 1) Kraken2 → MiFish ───────────────────────────────
  echo "  • Kraken2 (MiFish) → $OUTPUT_DIR/mitofish/"
  kraken2 \
    --db "$MITOFISH_DB" \
    --threads "$THREADS" \
    --confidence "$CONFIDENCE" \
    --report "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.report.txt" \
    --output "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.output.txt" \
    --classified-out "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish_classified.fq" \
    --unclassified-out "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish_unclassified.fq" \
    "$FASTQ"
  echo "    ✓ Kraken2 (MiFish) done"

  ### ── Krona chart for MiFish (if installed) ─────────────
  if [[ "$USE_KRONA" -eq 1 ]]; then
    echo "  • Generating Krona chart for MiFish..."
    ktImportTaxonomy \
      --title "MiFish Kraken2: $BASENAME" \
      --taxa-file "$MITOFISH_DB"/taxonomy/names.dmp \
      --taxonmap-file "$MITOFISH_DB"/taxonomy/nodes.dmp \
      --classification "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.output.txt" \
      --output "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.krona.html"
    echo "    ✓ Krona HTML: $OUTPUT_DIR/mitofish/${BASENAME}_mitofish.krona.html"
  fi

  ### ── 2) Bracken → MiFish (optional) ───────────────────
  if [[ "$USE_BRACKEN" -eq 1 ]]; then
    echo "  • Bracken (MiFish) → $OUTPUT_DIR/mitofish/"
    bracken \
      -d "$MITOFISH_DB" \
      -i "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.report.txt" \
      -o "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.bracken.tsv" \
      -r "$READ_LEN" \
      -l S
    echo "    ✓ Bracken (MiFish) done"

    ### ── Krona chart for Bracken (if installed) ──────────
    if [[ "$USE_KRONA" -eq 1 ]]; then
      awk -F $'\t' 'NR>1 { print $1"\t"$4 }' \
        "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.bracken.tsv" \
        > "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.bracken.krona.txt"
      ktImportText \
        --title "MiFish Abundance (Bracken): $BASENAME" \
        --charttype taxonomy \
        --header 2 \
        --output "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.bracken.krona.html" \
        "$OUTPUT_DIR/mitofish/${BASENAME}_mitofish.bracken.krona.txt"
      echo "      ✓ Bracken Krona: $OUTPUT_DIR/mitofish/${BASENAME}_mitofish.bracken.krona.html"
    fi
  fi

  ### ── 3) Kraken2 → core‐nt ─────────────────────────────
  echo "  • Kraken2 (core-nt) → $OUTPUT_DIR/core_nt/"
  kraken2 \
    --db "$CORE_NT_DB" \
    --threads "$THREADS" \
    --confidence "$CONFIDENCE" \
    --report "$OUTPUT_DIR/core_nt/${BASENAME}_core_nt.report.txt" \
    --output "$OUTPUT_DIR/core_nt/${BASENAME}_core_nt.output.txt" \
    "$FASTQ"
  echo "    ✓ Kraken2 (core-nt) done"

  ### ── Krona chart for core‐nt ───────────────────────────
  if [[ "$USE_KRONA" -eq 1 ]]; then
    echo "  • Generating Krona chart for core-nt..."
    ktImportTaxonomy \
      --title "core-nt Kraken2: $BASENAME" \
      --taxa-file "$CORE_NT_DB"/taxonomy/names.dmp \
      --taxonmap-file "$CORE_NT_DB"/taxonomy/nodes.dmp \
      --classification "$OUTPUT_DIR/core_nt/${BASENAME}_core_nt.output.txt" \
      --output "$OUTPUT_DIR/core_nt/${BASENAME}_core_nt.krona.html"
    echo "    ✓ Krona HTML: $OUTPUT_DIR/core_nt/${BASENAME}_core_nt.krona.html"
  fi

done

echo
echo " Quick Look complete!"
echo
echo "  • Fish-only outputs:   $OUTPUT_DIR/mitofish/"
echo "      - Kraken2 report:        *_mitofish.report.txt"
echo "      - Classified FASTQ:      *_mitofish_classified.fq"
echo "      - Krona chart (Kraken2): *_mitofish.krona.html"
echo "      - Bracken table:         *_mitofish.bracken.tsv"
echo "      - Krona chart (Bracken): *_mitofish.bracken.krona.html"
echo
echo "  • Vertebrate outputs:  $OUTPUT_DIR/core_nt/"
echo "      - Kraken2 report:        *_core_nt.report.txt"
echo "      - Krona chart:           *_core_nt.krona.html"
echo
echo "Next steps for your students:"
echo " 1) Open the *_mitofish.krona.html in a browser to explore fish taxonomy interactively."
echo " 2) (If generated) open *_mitofish.bracken.krona.html for abundance charts."
echo " 3) Open *_core_nt.krona.html for a broader vertebrate overview."
echo " 4) Use the *_classified.fq files for downstream, fish-only analyses."
echo " 5) Use the .report.txt or .bracken.tsv tables for quick abundance summaries."