#!/usr/bin/env bash
# scripts/02_quick_look.sh
#
# Quick Look pipeline (Kraken2 + Bracken) on basecalled & demuxed FASTQ
#
# 1) Classify against MiFish (fish‐only) database
# 2) (Optional) Re‐estimate abundances with Bracken
# 3) Classify against core‐nt (vertebrate) database
#
# Usage:
#   bash scripts/02_quick_look.sh <FASTQ_DIR> <OUTPUT_DIR>
#
# Example:
#   bash scripts/02_quick_look.sh mock test_results/02_quick_look
#
# BEFORE YOU RUN:
# • Install Kraken2 & Bracken via Conda:
#     conda install -c bioconda kraken2 bracken
#
# • Download & build your databases once:
#
#   ## MiFish (fish mitochondria)
#   # 1. Download `mitofish_all_mitogenomes.fasta` from:
#   #    https://mitofish.aori.u-tokyo.ac.jp/download/
#   # 2. Build Kraken2 DB:
#   kraken2-build --download-taxonomy --db ~/kraken2_db/mitofish
#   kraken2-build --add-to-library mitofish_all_mitogenomes.fasta --db ~/kraken2_db/mitofish
#   kraken2-build --build --db ~/kraken2_db/mitofish
#
#   ## Core‐NT (vertebrate RefSeq)
#   # 1. Download taxonomy + vertebrate library:
#   kraken2-build --download-taxonomy --db ~/kraken2_db/core_nt
#   kraken2-build --download-library vertebrate --db ~/kraken2_db/core_nt
#   kraken2-build --build --db ~/kraken2_db/core_nt
#
# After building, you should have directories like:
#   ~/kraken2_db/mitofish/{library,hash.k2d,opts.k2d,seqid2taxid.map}
#   ~/kraken2_db/core_nt/{library,hash.k2d,opts.k2d,seqid2taxid.map}
#
set -euo pipefail

### ── USER CONFIG ─────────────────────────────────────────────
# Point these to your built Kraken2 databases:
MITOFISH_DB="${MITOFISH_DB:-$HOME/kraken2_db/mitofish}"
CORE_NT_DB   "${CORE_NT_DB:-$HOME/kraken2_db/core_nt}"

# Number of threads & confidence threshold (0.05 = 5%)
THREADS="${THREADS:-8}"
CONFIDENCE="${CONFIDENCE:-0.05}"

# Read length (bp) for Bracken abundance re‐estimation
READ_LEN="${READ_LEN:-100}"

FASTQ_DIR="$1"
OUTPUT_DIR="$2"
### ─────────────────────────────────────────────────────────────

#  sanity: do we have kraken2?
if ! command -v kraken2 &>/dev/null; then
  echo "Error: kraken2 not found. Install with:"
  echo "  conda install -c bioconda kraken2"
  exit 1
fi

#  optional: do we have bracken?
if ! command -v bracken &>/dev/null; then
  echo " bracken not found; abundance re‐estimation will be skipped"
  USE_BRACKEN=0
else
  USE_BRACKEN=1
fi

mkdir -p "$OUTPUT_DIR"/mitofish "$OUTPUT_DIR"/core_nt

for FASTQ in "$FASTQ_DIR"/*.fastq "$FASTQ_DIR"/*.fastq.gz; do
  [[ -e "$FASTQ" ]] || continue
  BASENAME=$(basename "$FASTQ" | sed 's/\(.fastq.*\)//')
  echo
  echo " Processing sample: $BASENAME"

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
done

echo
echo " Quick Look complete!"
echo "  • Fish‐only outputs:   $OUTPUT_DIR/mitofish/"
echo "  • Vertebrate outputs:  $OUTPUT_DIR/core_nt/"
echo
echo " Next you can:"
echo "    1) inspect the MiFish‐classified FASTQ (`*_classified.fq`) for downstream, fish‐only analyses"
echo "    2) use the Bracken table (`*.bracken.tsv`) or the Kraken2 reports for abundance summaries"


#Resulting output file organization
#results/02_quick_look/
#├── mitofish/
#│   ├── SAMPLE_mitofish.output.txt        # raw Kraken2 calls
#│   ├── SAMPLE_mitofish.report.txt        # species × counts summary
#│   ├── SAMPLE_mitofish_classified.fq     # fish reads only for downstream
#│   ├── SAMPLE_mitofish_unclassified.fq   # everything else
#│   └── SAMPLE_mitofish.bracken.tsv       # Bracken‐refined abundances
#└── core_nt/
#    ├── SAMPLE_core_nt.output.txt         # raw Kraken2 calls
#    └── SAMPLE_core_nt.report.txt         # vertebrate summary