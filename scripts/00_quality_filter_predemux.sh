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
    echo "  $0 your_basecalled.fastq filtered_for_demux.fastq"
    echo "  $0 00_basecalled/basecalling_demo.fastq"
    echo ""
    echo "Purpose: Quality filter pooled FASTQ before ONTbarcoder demultiplexing"
    echo "Note: ONTbarcoder removes quality scores, so filter first!"
    exit 1
fi

INPUT_FASTQ="$1"
OUTPUT_FASTQ="${2:-${INPUT_FASTQ%.*}_filtered_for_demux.fastq}"

# ─── PROJECT PATHS ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create output directory if needed
OUTPUT_DIR="$(dirname "$OUTPUT_FASTQ")"
mkdir -p "$OUTPUT_DIR"

# ─── QUALITY FILTERING PARAMETERS ─────────────────────────────────────────
QUALITY_THRESHOLD="${QUALITY_THRESHOLD:-12}"   # Q12 quality threshold
MIN_LENGTH="${MIN_LENGTH:-100}"                # minimum read length
MAX_LENGTH="${MAX_LENGTH:-500}"                # maximum read length

echo "🔬 Pre-Demultiplexing Quality Filter"
echo "═══════════════════════════════════════"
echo "🔹 Input FASTQ:      $INPUT_FASTQ"
echo "🔹 Output FASTQ:     $OUTPUT_FASTQ"
echo "🔹 Quality filter:   Q≥$QUALITY_THRESHOLD"
echo "🔹 Length filter:    ${MIN_LENGTH}-${MAX_LENGTH} bp"
echo ""

# ─── SANITY CHECKS ────────────────────────────────────────────────────────
if [[ ! -f "$INPUT_FASTQ" ]]; then
    echo "❌ Error: Input FASTQ not found: $INPUT_FASTQ"
    echo ""
    echo "Available options:"
    echo "   • Use existing basecalled file"
    echo "   • Run basecalling demo first: bash scripts/00_basecall_demo.sh"
    echo "   • Skip to mock data: bash scripts/02_quick_look_clean.sh mock/ results/02_quicklook"
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
    echo "📊 Filtering Results:"
    echo "   • Input reads:     $input_reads"
    echo "   • Output reads:    $output_reads"
    echo "   • Retention rate:  ${retention_rate}%"
fi

echo ""
echo "✅ Pre-demultiplexing quality filter complete!"
echo ""
echo "📁 Output ready for ONTbarcoder:"
echo "   $OUTPUT_FASTQ"
echo ""
echo "🔗 Next steps:"
echo "   1. Demultiplex with ONTbarcoder2.3 GUI using: $OUTPUT_FASTQ"
echo "   2. After demux: bash scripts/02_quick_look_clean.sh demux/demultiplexed/ results/02_quicklook"
echo ""
echo "💡 Alternative - Skip demux and use mock data:"
echo "   bash scripts/02_quick_look_clean.sh mock/ results/02_quicklook"
echo ""