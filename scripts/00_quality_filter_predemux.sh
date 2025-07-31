#!/usr/bin/env bash
# scripts/00_quality_filter_predemux.sh
# Quality filter basecalled FASTQ before ONTbarcoder demultiplexing
# This preserves quality scores for filtering before FASTA conversion

set -euo pipefail

# ─── USAGE ─────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
    echo "Usage: $0 <INPUT_FASTQ> [OUTPUT_FASTQ]"
    echo ""
    echo "Examples:"
    echo "  $0 your_basecalled.fastq"
    echo "  $0 your_basecalled.fastq custom_output.fastq"
    echo "  $0 workflows/custom_cci_barcodes/00_raw_data/test_fhl_customcci.fastq"
    echo ""
    echo "Environment variables for customization:"
    echo "  export QUALITY_THRESHOLD=15    # Default: 12 (higher = stricter)"
    echo "  export MIN_LENGTH=150          # Default: 100"
    echo "  export MAX_LENGTH=300          # Default: 500"
    echo ""
    echo "Purpose: Quality filter pooled FASTQ before ONTbarcoder demultiplexing"
    echo "Note: ONTbarcoder removes quality scores, so filter first!"
    exit 1
fi

INPUT_FASTQ="$1"

# ─── PROJECT PATHS ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── SMART OUTPUT PATH DETECTION ──────────────────────────────────────────
if [[ $# -eq 2 ]]; then
    # User provided custom output path
    OUTPUT_FASTQ="$2"
elif [[ "$INPUT_FASTQ" == *"custom_cci_barcodes"* ]]; then
    # Auto-detect custom_cci workflow and use proper structure
    WORKFLOW_DIR=$(echo "$INPUT_FASTQ" | sed 's|/00_raw_data/.*||')
    OUTPUT_FASTQ="$WORKFLOW_DIR/01_filtered/quality_filtered.fastq"
    echo " Auto-detected Custom CCI workflow"
    echo "    Workflow directory: $WORKFLOW_DIR"
else
    # Default behavior for other workflows
    OUTPUT_FASTQ="${INPUT_FASTQ%.*}_filtered_for_demux.fastq"
fi

# Create output directory if needed
OUTPUT_DIR="$(dirname "$OUTPUT_FASTQ")"
mkdir -p "$OUTPUT_DIR"

# ─── QUALITY FILTERING PARAMETERS (CUSTOMIZABLE VIA EXPORT) ───────────────
QUALITY_THRESHOLD="${QUALITY_THRESHOLD:-12}"   # Q12 quality threshold
MIN_LENGTH="${MIN_LENGTH:-100}"                # minimum read length
MAX_LENGTH="${MAX_LENGTH:-500}"                # maximum read length

echo " Pre-Demultiplexing Quality Filter"
echo "═══════════════════════════════════════"
echo " Input FASTQ:      $INPUT_FASTQ"
echo " Output FASTQ:     $OUTPUT_FASTQ"
echo " Quality filter:   Q≥$QUALITY_THRESHOLD"
echo " Length filter:    ${MIN_LENGTH}-${MAX_LENGTH} bp"
echo ""
echo " Customize filters with:"
echo "   export QUALITY_THRESHOLD=15 MIN_LENGTH=150 MAX_LENGTH=300"
echo ""

# ─── SANITY CHECKS ────────────────────────────────────────────────────────
if [[ ! -f "$INPUT_FASTQ" ]]; then
    echo "❌ Error: Input FASTQ not found: $INPUT_FASTQ"
    echo ""
    echo "Available options:"
    echo "   • Use existing basecalled file"
    echo "   • Run basecalling demo first: bash scripts/00_basecall_demo.sh"
    echo "   • Skip to mock data: bash scripts/02_quick_look_clean.sh workflows/ont_native_barcodes/ results/ont_native_02_quicklook"
    exit 1
fi

if ! command -v seqkit &>/dev/null; then
    echo "❌ Error: seqkit not found"
    echo "   Install via: conda install -c bioconda seqkit"
    exit 1
fi

# ─── QUALITY AND LENGTH FILTERING ─────────────────────────────────────────
echo "▶ Applying quality and length filters..."
echo "   Input stats:"
seqkit stats "$INPUT_FASTQ" | tail -n +2 | sed 's/^/     /'

echo ""
echo "   Filtering (Q≥$QUALITY_THRESHOLD, ${MIN_LENGTH}-${MAX_LENGTH}bp)..."
seqkit seq \
    -Q "$QUALITY_THRESHOLD" \
    -m "$MIN_LENGTH" \
    -M "$MAX_LENGTH" \
    -g \
    "$INPUT_FASTQ" \
    -o "$OUTPUT_FASTQ"

echo ""
echo "   Output stats:"
seqkit stats "$OUTPUT_FASTQ" | tail -n +2 | sed 's/^/     /'

# ─── CALCULATE FILTERING STATS ────────────────────────────────────────────
input_reads=$(seqkit stats "$INPUT_FASTQ" | tail -n +2 | awk '{print $4}' | tr -d ',')
output_reads=$(seqkit stats "$OUTPUT_FASTQ" | tail -n +2 | awk '{print $4}' | tr -d ',')

if [[ "$input_reads" -gt 0 ]]; then
    retention_rate=$(echo "scale=1; $output_reads * 100 / $input_reads" | bc -l 2>/dev/null || echo "N/A")
    echo ""
    echo " Filtering Results:"
    echo "   • Input reads:     $input_reads"
    echo "   • Output reads:    $output_reads"
    echo "   • Retention rate:  ${retention_rate}%"
fi

# ─── AUTO-SETUP ONTBARCODER DIRECTORIES & COPY FILES ─────────────────────
echo ""
echo " Setting up ONTbarcoder directories and files..."

# Detect if we're working with custom_cci_barcodes workflow
if [[ "$OUTPUT_FASTQ" == *"custom_cci_barcodes"* ]]; then
    # Extract the workflow directory path
    WORKFLOW_DIR=$(echo "$OUTPUT_FASTQ" | sed 's|/01_filtered/.*||')
    
    echo "   Detected Custom CCI workflow: $WORKFLOW_DIR"
    
    # Create ONTbarcoder demo output directory (for student practice)
    ONTBARCODER_DEMO_OUTPUT="$WORKFLOW_DIR/02_demultiplexed_demo"
    mkdir -p "$ONTBARCODER_DEMO_OUTPUT"
    echo "   ✅ Created ONTbarcoder demo directory: $ONTBARCODER_DEMO_OUTPUT"
    
    # Note: The real 02_demultiplexed directory should already exist with pre-demultiplexed data
    ONTBARCODER_REAL_OUTPUT="$WORKFLOW_DIR/02_demultiplexed"
    if [[ -d "$ONTBARCODER_REAL_OUTPUT" ]]; then
        echo "   ✅ Real demultiplexed directory exists: $ONTBARCODER_REAL_OUTPUT"
    else
        echo "   ⚠️  Real demultiplexed directory not found: $ONTBARCODER_REAL_OUTPUT"
    fi
    
    # Create demux_config directory
    DEMUX_CONFIG_DIR="$WORKFLOW_DIR/demux_config"
    mkdir -p "$DEMUX_CONFIG_DIR"
    echo "   ✅ Created demux config directory: $DEMUX_CONFIG_DIR"
    
    # Copy filtered FASTQ to demux_config for ONTbarcoder practice
    DEMUX_CONFIG_FASTQ="$DEMUX_CONFIG_DIR/quality_filtered.fastq"
    cp "$OUTPUT_FASTQ" "$DEMUX_CONFIG_FASTQ"
    echo "   ✅ Copied filtered FASTQ to: $DEMUX_CONFIG_FASTQ"
    
    # Check for demultiplexing sheet
    DEMUX_SHEET="$DEMUX_CONFIG_DIR/demux_sheet.csv"
    if [[ -f "$DEMUX_SHEET" ]]; then
        echo "   ✅ Found demultiplexing sheet: $DEMUX_SHEET"
    else
        echo "   ⚠️  Demultiplexing sheet not found: $DEMUX_SHEET"
        echo "       Create this file for ONTbarcoder configuration"
    fi
else
    echo "    Not a custom_cci_barcodes workflow - skipping auto-setup"
fi

echo ""
echo "✅ Pre-demultiplexing quality filter complete!"
echo ""
echo " Files ready for ONTbarcoder practice:"
echo "   • Primary output:   $OUTPUT_FASTQ"
if [[ "$OUTPUT_FASTQ" == *"custom_cci_barcodes"* ]]; then
    echo "   • ONTbarcoder copy: $DEMUX_CONFIG_FASTQ"
fi
echo ""

# ─── ONTBARCODER INSTRUCTIONS ─────────────────────────────────────────────
if [[ "$OUTPUT_FASTQ" == *"custom_cci_barcodes"* ]]; then
    echo "️  ONTbarcoder2.3 GUI Practice Instructions:"
    echo "─────────────────────────────────────────────────"
    echo "⚠️  NOTE: This is for PRACTICE ONLY - the filtered data may not demultiplex well"
    echo ""
    echo "1. Launch ONTbarcoder2.3 GUI application"
    echo "2. Configure settings:"
    echo "   • Input file:           $DEMUX_CONFIG_FASTQ"
    echo "   • Output directory:     $ONTBARCODER_DEMO_OUTPUT"
    if [[ -f "$DEMUX_SHEET" ]]; then
        echo "   • Demultiplexing sheet: $DEMUX_SHEET"
    else
        echo "   • Demultiplexing sheet: CREATE $DEMUX_SHEET"
    fi
    echo "3. Run demultiplexing (practice run)"
    echo ""
    echo " Demo output structure (practice):"
    echo "   $ONTBARCODER_DEMO_OUTPUT/"
    echo "   ├── demultiplexed/"
    echo "   │   ├── sample1_all.fa"
    echo "   │   ├── sample2_all.fa"
    echo "   │   └── sample3_all.fa"
    echo "   └── [other ONTbarcoder files]"
    echo ""
    echo " Real pipeline uses pre-demultiplexed data:"
    echo "   $ONTBARCODER_REAL_OUTPUT/"
    echo "   ├── demultiplexed/           ← Script 02 continues from here"
    echo "   │   ├── 18_all.fa"
    echo "   │   ├── 2_all.fa"
    echo "   │   └── 4_all.fa"
    echo "   └── [existing mock data]"
    echo ""
    echo " Continue with main pipeline using real data:"
    echo "   bash scripts/02_quick_look_clean.sh $WORKFLOW_DIR/02_demultiplexed/demultiplexed/ results/custom_cci_02_quicklook"
    echo ""
    echo " Why two directories?"
    echo "   • $ONTBARCODER_DEMO_OUTPUT → Practice ONTbarcoder workflow"
    echo "   • $ONTBARCODER_REAL_OUTPUT → Continue with robust mock data"
else
    echo " Next steps:"
    echo "   1. Demultiplex with ONTbarcoder2.3 GUI using: $OUTPUT_FASTQ"
    echo "   2. After demux: bash scripts/02_quick_look_clean.sh <demux_output_dir> results/02_quicklook"
fi

echo ""
echo " Alternative - Skip demux practice and use ONT Native mock data:"
echo "   bash scripts/02_quick_look_clean.sh workflows/ont_native_barcodes/ results/ont_native_02_quicklook"
echo ""