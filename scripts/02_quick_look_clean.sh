#!/usr/bin/env bash
set -eo pipefail

# ─── USAGE ─────────────────────────────────────────────────────────
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <FASTQ_DIR> <OUTPUT_DIR>"
  echo "Example: $0 mock/basecalled_fastq/ results/02_quicklook"
  exit 1
fi
FASTQ_DIR="$1"
OUTPUT_DIR="$2"

# ─── PROJECT & DB ROOT (SELF-CONTAINED) ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Database locations (created by script 01)
DB_ROOT="${DB_ROOT:-$PROJECT_ROOT/../databases/kraken2_db}"

# ─── WHICH KRAKEN2 DBs ─────────────────────────────────────────────
DBS=(12s coi mitofish)

# ─── THREADS & CONFIDENCE ─────────────────────────────────────────
THREADS="${THREADS:-8}"
CONFIDENCE="${CONFIDENCE:-0.05}"

# ─── QUALITY & LENGTH FILTERING PARAMETERS ────────────────────────
QUALITY_THRESHOLD="${QUALITY_THRESHOLD:-12}"   # Q12 quality threshold
MIN_LENGTH="${MIN_LENGTH:-100}"                # minimum read length
MAX_LENGTH="${MAX_LENGTH:-500}"                # maximum read length (initial broad filter)

echo "🔬 DeCodeDNA Quality Control & Classification"
echo "═══════════════════════════════════════════════"
echo "🔹 Input FASTQ dir:  $FASTQ_DIR"
echo "🔹 Output dir:       $OUTPUT_DIR"
echo "🔹 Database root:    $DB_ROOT"
echo "🔹 Quality filter:   Q≥$QUALITY_THRESHOLD"
echo "🔹 Length filter:    ${MIN_LENGTH}-${MAX_LENGTH} bp"
echo ""

# ─── SANITY: required tools must exist ────────────────────────────
echo "🔍 Checking required tools..."
for cmd in kraken2 seqkit; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Error: $cmd not found."
    if [[ "$cmd" == "seqkit" ]]; then
      echo "   Install via: conda install -c bioconda seqkit"
    elif [[ "$cmd" == "kraken2" ]]; then
      echo "   Install via: conda install -c bioconda kraken2"
    fi
    exit 1
  else
    echo "✅ $cmd found"
  fi
done

# ─── OPTIONAL: KronaTools? ─────────────────────────────────────────
USE_KRONA=0
if command -v ktImportTaxonomy &>/dev/null && command -v ktImportText &>/dev/null; then
  USE_KRONA=1
  echo "✅ KronaTools found"
else
  echo "⚠️  Warning: KronaTools not found → skipping Krona charts"
fi

# ─── CHECK INPUT DIRECTORY ─────────────────────────────────────────
if [[ ! -d "$FASTQ_DIR" ]]; then
  echo "❌ Error: Input directory not found: $FASTQ_DIR"
  echo "   Expected to find FASTQ files for analysis"
  exit 1
fi

# ─── MAKE OUTPUT DIRS ─────────────────────────────────────────────
FILTERED_DIR="$OUTPUT_DIR/filtered"
mkdir -p "$FILTERED_DIR"
for db in "${DBS[@]}"; do
  mkdir -p "$OUTPUT_DIR/$db"
done

echo ""

# ─── MAIN LOOP: each FASTQ (.gz) in FASTQ_DIR ─────────────────────
shopt -s nullglob
fastq_files=("$FASTQ_DIR"/*.fastq "$FASTQ_DIR"/*.fastq.gz "$FASTQ_DIR"/*.fq "$FASTQ_DIR"/*.fq.gz)

if [[ ${#fastq_files[@]} -eq 0 ]]; then
  echo "❌ No FASTQ files found in $FASTQ_DIR"
  echo "   Looking for: *.fastq, *.fastq.gz, *.fq, *.fq.gz"
  echo "   Available files:"
  ls -la "$FASTQ_DIR/" | head -10
  exit 1
fi

echo "Found ${#fastq_files[@]} FASTQ file(s) to process:"
for fq in "${fastq_files[@]}"; do
  echo "  • $(basename "$fq")"
done
echo ""

for fq in "${fastq_files[@]}"; do
  sample="$(basename "$fq")"
  sample="${sample%.*}"      # strip first extension
  sample="${sample%.*}"      # strip second extension if .gz
  echo
  echo "▶ Sample: $sample"

  # ─── STEP 1: Quality and Length Filtering ─────────────────────────
  filtered_fq="$FILTERED_DIR/${sample}_filtered.fastq"
  
  echo "  • Quality & length filtering..."
  echo "    Input stats:"
  seqkit stats "$fq" | tail -n +2 | sed 's/^/      /'
  
  seqkit seq \
    -Q "$QUALITY_THRESHOLD" \
    -m "$MIN_LENGTH" \
    -M "$MAX_LENGTH" \
    -g \
    "$fq" \
    -o "$filtered_fq"
  
  echo "    Filtered stats:"
  seqkit stats "$filtered_fq" | tail -n +2 | sed 's/^/      /'
  echo "    ✓ Filtered FASTQ: $filtered_fq"

  # ─── STEP 1.5: Generate Length Distribution PDF ───────────────────
  if command -v amplicon_sorter &>/dev/null; then
    echo "    • Generating length distribution PDF..."
    
    # Convert filtered FASTQ to FASTA temporarily for amplicon_sorter
    temp_fa="$FILTERED_DIR/${sample}_temp.fasta"
    seqkit fq2fa "$filtered_fq" -o "$temp_fa"
    
    # Generate histogram PDF using amplicon_sorter
    python3 "$(which amplicon_sorter)" \
      --input "$temp_fa" \
      --minlength "$MIN_LENGTH" \
      --maxlength "$MAX_LENGTH" \
      --histogram_only \
      --outputfolder "$FILTERED_DIR/${sample}_length_dist" || {
        echo "      ⚠️  Length distribution generation failed, continuing..."
      }
    
    # Clean up temp file
    rm -f "$temp_fa"
    echo "      ✓ Length distribution: $FILTERED_DIR/${sample}_length_dist/"
  else
    echo "      ⚠️  amplicon_sorter not found, skipping length distribution"
  fi

  # ─── STEP 2: Kraken2 Taxonomic Classification ─────────────────────
  for db in "${DBS[@]}"; do
    DB_PATH="$DB_ROOT/$db"
    OUT_DIR="$OUTPUT_DIR/$db"

    echo "  • Kraken2 → $db"
    
    # Check if database exists
    if [[ ! -d "$DB_PATH" ]] || [[ ! -f "$DB_PATH/taxo.k2d" ]]; then
      echo "    ❌ Kraken2 database not found: $DB_PATH"
      echo "       Run script 01 to build databases first"
      continue
    fi
    
    kraken2 \
      --db "$DB_PATH" \
      --threads "$THREADS" \
      --confidence "$CONFIDENCE" \
      --report "$OUT_DIR/${sample}_${db}.report.txt" \
      --output "$OUT_DIR/${sample}_${db}.output.txt" \
      --classified-out "$OUT_DIR/${sample}_${db}_classified.fasta" \
      --unclassified-out "$OUT_DIR/${sample}_${db}_unclassified.fasta" \
      "$filtered_fq"
    echo "    ✓ ${db} done"

    # ─── STEP 2.5: Convert Kraken2 output to proper FASTA format ─────
    echo "    • Converting Kraken2 output to proper FASTA format..."
    
    # Convert classified output to proper FASTA
    if [[ -s "$OUT_DIR/${sample}_${db}_classified.fasta" ]]; then
      temp_classified="$OUT_DIR/${sample}_${db}_classified_temp.fasta"
      mv "$OUT_DIR/${sample}_${db}_classified.fasta" "$temp_classified"
      awk 'NR%2==1 {print ">"$1} NR%2==0 {print}' "$temp_classified" > "$OUT_DIR/${sample}_${db}_classified.fasta"
      rm "$temp_classified"
      echo "      ✓ Classified FASTA converted"
    fi
    
    # Convert unclassified output to proper FASTA
    if [[ -s "$OUT_DIR/${sample}_${db}_unclassified.fasta" ]]; then
      temp_unclassified="$OUT_DIR/${sample}_${db}_unclassified_temp.fasta"
      mv "$OUT_DIR/${sample}_${db}_unclassified.fasta" "$temp_unclassified"
      awk 'NR%2==1 {print ">"$1} NR%2==0 {print}' "$temp_unclassified" > "$OUT_DIR/${sample}_${db}_unclassified.fasta"
      rm "$temp_unclassified"
      echo "      ✓ Unclassified FASTA converted"
    fi

    # ─── STEP 3: Generate Krona Charts ────────────────────────────────
    if [[ "$USE_KRONA" -eq 1 ]]; then
      echo "    • Generating Krona chart for $db…"
      
      # Check if required files exist
      if [[ ! -f "$OUT_DIR/${sample}_${db}.report.txt" ]]; then
        echo "      ERROR: Missing $OUT_DIR/${sample}_${db}.report.txt"
        continue
      fi
      
      # Use ktImportText with the Kraken2 report file
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
echo "✅ Quality control and classification complete!"
echo
echo "📊 Results summary:"
echo " • Filtered FASTQ files       → $FILTERED_DIR/"
echo " • Length distribution PDFs   → $FILTERED_DIR/<sample>_length_dist/"
echo " • Kraken2 classification     → $OUTPUT_DIR/{${DBS[*]}}"
echo " • Fish-classified sequences  → $OUTPUT_DIR/mitofish/*_classified.fasta"
if [[ "$USE_KRONA" -eq 1 ]]; then
  echo " • Interactive Krona plots    → $OUTPUT_DIR/*/*.krona.html"
fi
echo
echo "🔗 Next step:"
echo " bash scripts/03_consensus_sort.sh $OUTPUT_DIR results/03_consensus"
echo ""
