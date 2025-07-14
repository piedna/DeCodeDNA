#!/usr/bin/env bash
set -eo pipefail

# ─── USAGE ─────────────────────────────────────────────────────────
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <FASTQ_DIR> <OUTPUT_DIR>"
  exit 1
fi
FASTQ_DIR="$1"
OUTPUT_DIR="$2"

# ─── PROJECT & DB ROOT ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DB_ROOT="${DB_ROOT:-$PROJECT_ROOT/../kraken2_db}"

# ─── WHICH KRAKEN2 DBs ─────────────────────────────────────────────
DBS=(12s coi mitofish)

# ─── THREADS & CONFIDENCE ─────────────────────────────────────────
THREADS="${THREADS:-8}"
CONFIDENCE="${CONFIDENCE:-0.05}"

# ─── SANITY: kraken2 must exist ───────────────────────────────────
if ! command -v kraken2 &>/dev/null; then
  echo "Error: kraken2 not found. Install via: conda install -c bioconda kraken2"
  exit 1
fi

# ─── OPTIONAL: KronaTools? ─────────────────────────────────────────
USE_KRONA=0
if command -v ktImportTaxonomy &>/dev/null && command -v ktImportText &>/dev/null; then
  USE_KRONA=1
else
  echo "Warning: KronaTools not found → skipping Krona charts"
fi

# ─── MAKE OUTPUT DIRS ─────────────────────────────────────────────
for db in "${DBS[@]}"; do
  mkdir -p "$OUTPUT_DIR/$db"
done

# ─── MAIN LOOP: each FASTQ (.gz) in FASTQ_DIR ─────────────────────
shopt -s nullglob
for fq in "$FASTQ_DIR"/*.fastq "$FASTQ_DIR"/*.fastq.gz; do
  sample="$(basename "$fq")"
  sample="${sample%%.*}"      # strip .fastq or .fastq.gz
  echo
  echo "▶ Sample: $sample"

  for db in "${DBS[@]}"; do
    DB_PATH="$DB_ROOT/$db"
    OUT_DIR="$OUTPUT_DIR/$db"

    echo "  • Kraken2 → $db"
    kraken2 \
      --db "$DB_PATH" \
      --threads "$THREADS" \
      --confidence "$CONFIDENCE" \
      --report "$OUT_DIR/${sample}_${db}.report.txt" \
      --output "$OUT_DIR/${sample}_${db}.output.txt" \
      --classified-out "$OUT_DIR/${sample}_${db}_classified.fq" \
      --unclassified-out "$OUT_DIR/${sample}_${db}_unclassified.fq" \
      "$fq"
    echo "    ✓ ${db} done"

    if [[ "$USE_KRONA" -eq 1 ]]; then
      echo "    • Generating Krona chart for $db…"
      
      # Check if required files exist
      if [[ ! -f "$OUT_DIR/${sample}_${db}.report.txt" ]]; then
        echo "      ERROR: Missing $OUT_DIR/${sample}_${db}.report.txt"
        continue
      fi
      
      # Use ktImportText with the Kraken2 report file (not output file)
      OUTPUT_FILE="$OUT_DIR/${sample}_${db}.krona.html"
      
      echo "      Running ktImportText..."
      ktImportText \
        -o "$OUTPUT_FILE" \
        "$OUT_DIR/${sample}_${db}.report.txt" || {
          echo "      ERROR: ktImportText failed for $db"
          continue
        }
      
      echo "      ✓ Krona HTML: $OUTPUT_FILE"
    fi
  done
done

echo
echo " Quick look complete!"
echo " Results under: $OUTPUT_DIR/{${DBS[*]}}"
