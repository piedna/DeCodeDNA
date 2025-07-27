#!/usr/bin/env bash
set -eo pipefail

# ─── USAGE ─────────────────────────────────────────────────────────────────
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <FASTQ_OR_FASTA_DIR> <OUTPUT_DIR>"
  echo "Example: $0 mock/demux/demultiplexed/ results/02_quicklook"
  echo "Note: Accepts both FASTQ and FASTA files (for post-demux workflow)"
  exit 1
fi
INPUT_DIR="$1"
OUTPUT_DIR="$2"

# ─── PROJECT & DB ROOT (SELF-CONTAINED) ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Database locations (created by script 01)
DB_ROOT="${DB_ROOT:-$PROJECT_ROOT/../databases/kraken2_db}"

# ─── WHICH KRAKEN2 DBs ─────────────────────────────────────────────────────
DBS=(12s coi mitofish)

# ─── THREADS & CONFIDENCE ─────────────────────────────────────────────────
THREADS="${THREADS:-8}"
CONFIDENCE="${CONFIDENCE:-0.05}"

# ─── QUALITY & LENGTH FILTERING PARAMETERS ────────────────────────────────
QUALITY_THRESHOLD="${QUALITY_THRESHOLD:-12}"   # Q12 quality threshold
MIN_LENGTH="${MIN_LENGTH:-100}"                # minimum read length
MAX_LENGTH="${MAX_LENGTH:-500}"                # maximum read length (initial broad filter)

echo "🔬 DeCodeDNA Quality Control & Classification"
echo "═══════════════════════════════════════════════════════════════════"

# Detect multiplexing workflow from input directory name
WORKFLOW_TYPE="unknown"
if [[ "$INPUT_DIR" == *"ont_native"* ]] || [[ "$INPUT_DIR" == *"native"* ]]; then
  WORKFLOW_TYPE="ONT Native Barcoding"
elif [[ "$INPUT_DIR" == *"custom_cci"* ]] || [[ "$INPUT_DIR" == *"cci"* ]] || [[ "$INPUT_DIR" == *"demux"* ]]; then
  WORKFLOW_TYPE="Custom CCI Barcoding"
else
  WORKFLOW_TYPE="Auto-detected from files"
fi

echo "🔹 Workflow:         $WORKFLOW_TYPE"
echo "🔹 Input dir:        $INPUT_DIR"
echo "🔹 Output dir:       $OUTPUT_DIR"
echo "🔹 Database root:    $DB_ROOT"
echo "🔹 Quality filter:   Q≥$QUALITY_THRESHOLD (FASTQ only)"
echo "🔹 Length filter:    ${MIN_LENGTH}-${MAX_LENGTH} bp"
echo ""

# ─── SANITY: required tools must exist ────────────────────────────────────
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

# ─── OPTIONAL: KronaTools? ─────────────────────────────────────────────────
USE_KRONA=0
if command -v ktImportTaxonomy &>/dev/null && command -v ktImportText &>/dev/null; then
  USE_KRONA=1
  echo "✅ KronaTools found"
else
  echo "⚠️  Warning: KronaTools not found → skipping Krona charts"
fi

# ─── OPTIONAL: amplicon_sorter? ────────────────────────────────────────────
USE_AMPLICON_SORTER=0
AMPLICON_SORTER_CMD=""

# Check for amplicon_sorter in multiple locations
if command -v amplicon_sorter &>/dev/null; then
  USE_AMPLICON_SORTER=1
  AMPLICON_SORTER_CMD="amplicon_sorter"
  echo "✅ amplicon_sorter found (in PATH)"
elif [[ -f "$PROJECT_ROOT/../tools/amplicon_sorter/amplicon_sorter.py" ]]; then
  USE_AMPLICON_SORTER=1
  AMPLICON_SORTER_CMD="python3 $PROJECT_ROOT/../tools/amplicon_sorter/amplicon_sorter.py"
  echo "✅ amplicon_sorter found (as Python script)"
elif [[ -f "$PROJECT_ROOT/tools/amplicon_sorter/amplicon_sorter.py" ]]; then
  USE_AMPLICON_SORTER=1
  AMPLICON_SORTER_CMD="python3 $PROJECT_ROOT/tools/amplicon_sorter/amplicon_sorter.py"
  echo "✅ amplicon_sorter found (as Python script)"
else
  echo "⚠️  Warning: amplicon_sorter not found → skipping length distribution plots"
  echo "   Looked for:"
  echo "   - amplicon_sorter in PATH"
  echo "   - $PROJECT_ROOT/../tools/amplicon_sorter/amplicon_sorter.py"
  echo "   - $PROJECT_ROOT/tools/amplicon_sorter/amplicon_sorter.py"
fi

# ─── CHECK INPUT DIRECTORY & AUTO-SETUP ───────────────────────────────────
if [[ ! -d "$INPUT_DIR" ]]; then
  echo "❌ Error: Input directory not found: $INPUT_DIR"
  
  # Check if user is trying to use custom CCI workflow but hasn't set up folders
  if [[ "$INPUT_DIR" == *"custom_cci_barcodes/demultiplexed"* ]]; then
    OLD_DEMUX_PATH="$PROJECT_ROOT/demux/demultiplexed"
    
    echo ""
    echo "🔍 Looking for demux files to set up custom CCI workflow..."
    echo "   Checking: $OLD_DEMUX_PATH"
    
    if [[ -d "$OLD_DEMUX_PATH" ]] && [[ -n "$(ls -A "$OLD_DEMUX_PATH"/*.fa 2>/dev/null)" ]]; then
      echo "   ✅ Found existing demux files!"
      echo ""
      echo "🔄 Setting up custom_cci_barcodes automatically..."
      echo "   Source: $OLD_DEMUX_PATH"
      echo "   Target: $INPUT_DIR"
      
      # Create target directory
      mkdir -p "$INPUT_DIR"
      
      # Count and copy files
      file_count=$(ls "$OLD_DEMUX_PATH"/*.fa 2>/dev/null | wc -l)
      echo "   📊 Copying $file_count .fa files..."
      
      if [[ "$file_count" -gt 0 ]]; then
        cp "$OLD_DEMUX_PATH"/*.fa "$INPUT_DIR/"
        echo "   ✅ Files copied successfully"
        
        # Verify copy worked
        copied_count=$(ls "$INPUT_DIR"/*.fa 2>/dev/null | wc -l)
        echo "   📊 Verification: $copied_count files in target directory"
        
        # Show sample files
        echo "   📋 Sample files copied:"
        ls "$INPUT_DIR"/*.fa | head -3 | sed 's/^/     /'
        if [[ "$file_count" -gt 3 ]]; then
          echo "     ... and $((file_count - 3)) more files"
        fi
        echo ""
      else
        echo "   ❌ No .fa files found to copy"
        exit 1
      fi
    else
      echo "   ❌ No demux files found at $OLD_DEMUX_PATH"
      echo ""
      echo "💡 Manual setup required:"
      echo "   1. Place your .fa files in: $INPUT_DIR"
      echo "   2. Or copy from demux: cp demux/demultiplexed/*.fa $INPUT_DIR/"
      exit 1
    fi
  else
    echo ""
    echo "💡 Setup suggestions:"
    echo "   • For ONT native: Place FASTQ files in ont_native_barcodes/"
    echo "   • For custom CCI: Place .fa files in custom_cci_barcodes/demultiplexed/"
    echo "   • Or manually copy your demux files to: $INPUT_DIR"
    exit 1
  fi
fi

# ─── MAKE OUTPUT DIRS ─────────────────────────────────────────────────────
FILTERED_DIR="$OUTPUT_DIR/filtered"
mkdir -p "$FILTERED_DIR"
for db in "${DBS[@]}"; do
  mkdir -p "$OUTPUT_DIR/$db"
done

echo ""

# ─── AUTO-RUN EFPQ CONVERSION IF NEEDED ────────────────────────────────────
# Check if we have .fa files that need EFPQ conversion
shopt -s nullglob
fa_files=("$INPUT_DIR"/*.fa)
if [[ ${#fa_files[@]} -gt 0 ]]; then
  echo "🔄 Detected .fa files - running EFPQ conversion automatically..."
  echo "   Found ${#fa_files[@]} .fa files that need EFPQ conversion"
  
  # Save current directory
  ORIGINAL_DIR=$(pwd)
  
  # Run EFPQ conversion in the input directory
  cd "$INPUT_DIR"
  if bash "$PROJECT_ROOT/scripts/EFPQ_ontbarcoder_convert.sh"; then
    echo "   ✅ EFPQ base conversion completed"
    
    # The original EFPQ script only converts bases, doesn't rename files
    # So we need to rename .fa → .fasta here
    echo "   • Renaming .fa files to .fasta..."
    renamed_count=0
    for fa_file in *.fa; do
      if [[ -f "$fa_file" ]]; then
        fasta_file="${fa_file%.fa}.fasta"
        mv "$fa_file" "$fasta_file"
        echo "     $fa_file → $fasta_file"
        renamed_count=$((renamed_count + 1))
      fi
    done
    
    echo "   ✅ File renaming complete ($renamed_count files)"
    
    # Verify conversion worked
    fasta_count=$(ls *.fasta 2>/dev/null | wc -l || echo "0")
    echo "   📊 Created $fasta_count .fasta files"
    
    if [[ "$fasta_count" -eq 0 ]]; then
      echo "   ❌ No .fasta files created after conversion"
      echo "   🔧 Files in directory:"
      ls -la | head -10
    fi
  else
    echo "   ❌ EFPQ conversion script failed"
    cd "$ORIGINAL_DIR"
    exit 1
  fi
  
  # Return to original directory
  cd "$ORIGINAL_DIR"
  echo ""
fi

# ─── DETECT FILE TYPES ─────────────────────────────────────────────────────
shopt -s nullglob
fastq_files=("$INPUT_DIR"/*.fastq "$INPUT_DIR"/*.fastq.gz "$INPUT_DIR"/*.fq "$INPUT_DIR"/*.fq.gz)
fasta_files=("$INPUT_DIR"/*.fasta "$INPUT_DIR"/*.fas)

total_files=$((${#fastq_files[@]} + ${#fasta_files[@]}))

if [[ $total_files -eq 0 ]]; then
  echo "❌ No FASTQ or FASTA files found in $INPUT_DIR"
  echo "   Looking for: *.fastq, *.fastq.gz, *.fq, *.fq.gz, *.fasta, *.fa, *.fas"
  echo "   Available files:"
  ls -la "$INPUT_DIR/" | head -10
  exit 1
fi

echo "Found $total_files file(s) to process:"
for fq in "${fastq_files[@]}"; do
  echo "  • $(basename "$fq") (FASTQ)"
done
for fa in "${fasta_files[@]}"; do
  echo "  • $(basename "$fa") (FASTA)"
done

# Detect input type
if [[ ${#fastq_files[@]} -gt 0 ]]; then
  INPUT_TYPE="FASTQ"
  input_files=("${fastq_files[@]}")
  echo "📊 Input type: FASTQ (quality filtering will be applied)"
else
  INPUT_TYPE="FASTA" 
  input_files=("${fasta_files[@]}")
  echo "📊 Input type: FASTA (quality filtering skipped - assumes pre-filtered)"
fi

echo ""

# ─── MAIN LOOP: process each file ─────────────────────────────────────────
for input_file in "${input_files[@]}"; do
  sample="$(basename "$input_file")"
  sample="${sample%.*}"      # strip first extension
  sample="${sample%.*}"      # strip second extension if .gz
  echo
  echo "▶ Sample: $sample"

  # ─── STEP 1: Quality and Length Filtering (or Format Conversion) ─────────
  filtered_file="$FILTERED_DIR/${sample}_filtered.fastq"
  
  if [[ "$INPUT_TYPE" == "FASTQ" ]]; then
    echo "  • Quality & length filtering..."
    echo "    Input stats:"
    seqkit stats "$input_file" | tail -n +2 | sed 's/^/      /'
    
    seqkit seq \
      -Q "$QUALITY_THRESHOLD" \
      -m "$MIN_LENGTH" \
      -M "$MAX_LENGTH" \
      -g \
      "$input_file" \
      -o "$filtered_file"
    
    echo "    Filtered stats:"
    seqkit stats "$filtered_file" | tail -n +2 | sed 's/^/      /'
  else
    filtered_file="$FILTERED_DIR/${sample}_filtered.fasta"
    
    echo "  • Copying FASTA (no filtering - already filtered pre-demux)..."
    echo "    Input stats:"
    seqkit stats "$input_file" | tail -n +2 | sed 's/^/      /'
    
    # Just copy the file (no length filtering - already done pre-demux)
    cp "$input_file" "$filtered_file"
    
    echo "    Output stats:"
    seqkit stats "$filtered_file" | tail -n +2 | sed 's/^/      /'
    echo "    ✓ FASTA copied: $filtered_file"
  fi
  
  echo "    ✓ Processed file: $filtered_file"

  # ─── STEP 1.5: Generate Length Distribution PDF ───────────────────────────
  if [[ "$USE_AMPLICON_SORTER" -eq 1 ]]; then
    echo "    • Generating length distribution PDF..."
    
    # Convert to FASTA temporarily for amplicon_sorter (regardless of input type)
    temp_fa="$FILTERED_DIR/${sample}_temp.fasta"
    if [[ "$INPUT_TYPE" == "FASTQ" ]]; then
      seqkit fq2fa "$filtered_file" -o "$temp_fa"
    else
      cp "$filtered_file" "$temp_fa"
    fi
    
    # Generate histogram PDF using amplicon_sorter
    $AMPLICON_SORTER_CMD \
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
    echo "      ⚠️  amplicon_sorter not available, skipping length distribution"
  fi

  # ─── STEP 2: Kraken2 Taxonomic Classification ─────────────────────────────
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
    
    # Run Kraken2 without --classified-out (which doesn't work with FASTA)
kraken2 \
  --db "$DB_PATH" \
  --threads "$THREADS" \
  --confidence "$CONFIDENCE" \
  --report "$OUT_DIR/${sample}_${db}.report.txt" \
  --output "$OUT_DIR/${sample}_${db}.output.txt" \
  "$filtered_file"

# Extract classified sequences manually
echo "    • Extracting classified sequences from Kraken2 output..."

# Extract classified sequences (those marked with 'C') - only if they exist
if grep -q "^C" "$OUT_DIR/${sample}_${db}.output.txt"; then
  grep "^C" "$OUT_DIR/${sample}_${db}.output.txt" | cut -f2 > "$OUT_DIR/${sample}_${db}_classified_ids.txt"
  seqkit grep -f "$OUT_DIR/${sample}_${db}_classified_ids.txt" "$filtered_file" -o "$OUT_DIR/${sample}_${db}_classified.fasta"
else
  # Create empty file if no classified sequences
  touch "$OUT_DIR/${sample}_${db}_classified.fasta"
fi

# Extract unclassified sequences (those marked with 'U') - only if they exist
if grep -q "^U" "$OUT_DIR/${sample}_${db}.output.txt"; then
  grep "^U" "$OUT_DIR/${sample}_${db}.output.txt" | cut -f2 > "$OUT_DIR/${sample}_${db}_unclassified_ids.txt"
  seqkit grep -f "$OUT_DIR/${sample}_${db}_unclassified_ids.txt" "$filtered_file" -o "$OUT_DIR/${sample}_${db}_unclassified.fasta"
else
  # Create empty file if no unclassified sequences
  touch "$OUT_DIR/${sample}_${db}_unclassified.fasta"
fi

# Clean up temp ID files
rm -f "$OUT_DIR/${sample}_${db}_classified_ids.txt" "$OUT_DIR/${sample}_${db}_unclassified_ids.txt"
    echo "    ✓ ${db} classification done"

    # ─── STEP 2.5: Convert Kraken2 output to proper FASTA format ─────
    echo "    • Converting Kraken2 output to proper FASTA format..."

    # Handle classified output
    if [[ -s "$OUT_DIR/${sample}_${db}_classified.fasta" ]]; then
      temp_classified="$OUT_DIR/${sample}_${db}_classified_temp.fasta"
      mv "$OUT_DIR/${sample}_${db}_classified.fasta" "$temp_classified"
      
      # Use seqkit to convert any format to clean FASTA
      seqkit fq2fa "$temp_classified" -o "$OUT_DIR/${sample}_${db}_classified.fasta" 2>/dev/null || {
        # Fallback: robust AWK for Kraken2 format
        awk '
        /^@/ { 
          header = $1
          gsub(/^@/, ">", header)
          print header
          getline
          print $0
          getline  # skip + line
          getline  # skip quality line
        }
        ' "$temp_classified" > "$OUT_DIR/${sample}_${db}_classified.fasta"
      }
      
      rm "$temp_classified"
      echo "      ✓ Classified FASTA converted"
    fi

    # Handle unclassified output
    if [[ -s "$OUT_DIR/${sample}_${db}_unclassified.fasta" ]]; then
      temp_unclassified="$OUT_DIR/${sample}_${db}_unclassified_temp.fasta"
      mv "$OUT_DIR/${sample}_${db}_unclassified.fasta" "$temp_unclassified"
      
      seqkit fq2fa "$temp_unclassified" -o "$OUT_DIR/${sample}_${db}_unclassified.fasta" 2>/dev/null || {
        awk '
        /^@/ { 
          header = $1
          gsub(/^@/, ">", header)
          print header
          getline
          print $0
          getline
          getline
        }
        ' "$temp_unclassified" > "$OUT_DIR/${sample}_${db}_unclassified.fasta"
      }
      
      rm "$temp_unclassified"
      echo "      ✓ Unclassified FASTA converted"
    fi

    # Final validation with seqkit
    if command -v seqkit &>/dev/null; then
      if [[ -s "$OUT_DIR/${sample}_${db}_classified.fasta" ]]; then
        echo "    • Final validation with seqkit..."
        if seqkit stats "$OUT_DIR/${sample}_${db}_classified.fasta" >/dev/null 2>&1; then
          echo "      ✓ Classified FASTA passes seqkit validation"
        else
          echo "      ❌ Classified FASTA failed seqkit validation"
          echo "      Checking file content:"
          head -6 "$OUT_DIR/${sample}_${db}_classified.fasta" | sed 's/^/        /'
          
          # Emergency fix: strip problematic characters
          echo "      🔧 Applying emergency fix..."
          sed -i.bak 's/[-]//g' "$OUT_DIR/${sample}_${db}_classified.fasta"
          echo "      ✓ Emergency fix applied (removed dashes)"
        fi
      fi
    fi

    # ─── STEP 3: Generate Krona Charts ────────────────────────────────────
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
echo " • Processed input:           $INPUT_TYPE files"
echo " • Filtered sequences         → $FILTERED_DIR/"
if [[ "$USE_AMPLICON_SORTER" -eq 1 ]]; then
  echo " • Length distribution PDFs   → $FILTERED_DIR/<sample>_length_dist/"
fi
echo " • Kraken2 classification     → $OUTPUT_DIR/{${DBS[*]}}"
echo " • Fish-classified sequences  → $OUTPUT_DIR/mitofish/*_classified.fasta"
if [[ "$USE_KRONA" -eq 1 ]]; then
  echo " • Interactive Krona plots    → $OUTPUT_DIR/*/*.krona.html"
fi
echo
echo "🔗 Next step:"
echo " bash scripts/03_consensus_sort.sh $OUTPUT_DIR results/03_consensus"
echo ""