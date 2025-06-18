#!/usr/bin/env bash
# scripts/01_basecall_and_demux.sh
#
# A beginner-friendly pipeline to:
#   1) (Optional) Convert FAST5 → POD5
#   2) Download the latest SUP model for Dorado
#   3) SUP basecalling to FASTQ
#   4) Demultiplex with the ONT native barcode kit
#   5) Trim barcodes off each demultiplexed FASTQ (recommended)
#
# Before you start:
#  • Install Dorado from https://github.com/nanoporetech/dorado
#  • Install pod5 via pip:   pip install pod5
#  • Ensure your input directory contains one subfolder per sample,
#    each with either FAST5 files OR a POD5 file.
#
# Usage:
#   bash scripts/01_basecall_and_demux.sh <INPUT_DIR> <OUTPUT_DIR>
#
# Example:
#   bash scripts/01_basecall_and_demux.sh \
#     /path/to/my/raw_data/   \
#     /path/to/output_folder/

set -euo pipefail
# ─── SAFETY FLAGS ─────────────────────────────────────────────────────────────
# -e: exit immediately if a command exits with a non-zero status
# -u: treat unset variables as an error and exit immediately
# -o pipefail: pipeline fails if any command fails (not just the last)

# ─── USER CONFIGURATION ────────────────────────────────────────────────────────

# Path to Dorado binaries (adjust if you installed elsewhere)
DORADO_BIN="${DORADO_BIN:-/opt/dorado/bin}"

# Pod5 converter tool (install with `pip install pod5`)
POD5_TOOL="${POD5_TOOL:-pod5}"

# Which Dorado model to use:
#  • SUP = highest accuracy
#  • HAC = faster, slightly lower accuracy
MODEL="${MODEL:-dna_r10.4.1_e8.2_400bps_sup@v5.0.0}"
# If you prefer HAC, uncomment the next line:
# MODEL="dna_r10.4.1_e8.2_400bps_hac@v5.0.0"

# ONT native barcoding kit for demultiplexing
KIT_NAME="${KIT_NAME:-SQK-NBD114-24}"
# (Use EXP-PBC096 for the 96-barcode kit.)
# If using custom designed barcodes, demux using ONTbarcoder, cutadapt, OBITools instead

# List the sample subfolders under your INPUT_DIR.
# Each folder should be named e.g. "ONT009", "ONT010", etc.
SAMPLES=( "ONT009" "ONT010" "ONT011" "ONT008" )

# ────────────────────────────────────────────────────────────────────────────────

# ─── ARGUMENT CHECK ─────────────────────────────────────────────────────────────
# $# is the number of positional arguments passed to the script
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <INPUT_DIR> <OUTPUT_DIR>"
  exit 1
fi

INPUT_DIR="$1"   # first argument: path to raw FAST5 or POD5 folders
OUTPUT_DIR="$2"  # second argument: where all outputs will go

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# ─── SANITY CHECKS ─────────────────────────────────────────────────────────────
if ! command -v "$DORADO_BIN"/dorado &>/dev/null; then
  echo "Error: dorado not found at $DORADO_BIN"
  echo "Please install from: https://github.com/nanoporetech/dorado"
  exit 1
fi

if ! command -v "$POD5_TOOL" &>/dev/null; then
  echo "Error: pod5 tool not installed"
  echo "Install with: pip install pod5"
  exit 1
fi

echo "🔹 INPUT_DIR:  $INPUT_DIR"
echo "🔹 OUTPUT_DIR: $OUTPUT_DIR"
echo

# ─── DOWNLOAD LATEST DORADO MODEL ──────────────────────────────────────────────
echo "▶ Downloading Dorado model: $MODEL"
if ! "$DORADO_BIN"/dorado download --model "$MODEL"; then
  echo "Error: Failed to download Dorado model $MODEL"
  exit 1
fi
echo "    ✓ Model is ready"
echo

# ─── PROCESS EACH SAMPLE ───────────────────────────────────────────────────────
for S in "${SAMPLES[@]}"; do
  echo "── Processing sample: $S ─────────────────────────────────"
  RAW_PATH="$INPUT_DIR/$S"

  # 1) Convert FAST5 → POD5 if FAST5 files exist
  # compgen -G returns success if any files match the glob pattern
  if compgen -G "$RAW_PATH"/*.fast5 >/dev/null; then
    POD5_PATH="$OUTPUT_DIR/pod5/${S}.pod5"
    mkdir -p "$(dirname "$POD5_PATH")"
    echo "  • Converting FAST5 → POD5 → $POD5_PATH"
    if ! "$POD5_TOOL" convert fast5 -o "$POD5_PATH" --recursive "$RAW_PATH"; then
      echo "Error: FAST5→POD5 conversion failed for $RAW_PATH"
      exit 1
    fi
    [[ -f "$POD5_PATH" ]] || { echo "Error: POD5 file not found at $POD5_PATH"; exit 1; }
  else
    POD5_PATH="$RAW_PATH"
    echo "  • Skipping conversion, assuming POD5 directory: $POD5_PATH"
  fi

  # 2) Basecalling → FASTQ
  OUT_FASTQ="$OUTPUT_DIR/${S}_sup.fastq"
  echo "  • Basecalling (SUP) → $OUT_FASTQ"
  if ! "$DORADO_BIN"/dorado basecaller "$MODEL" "$POD5_PATH" --emit-fastq > "$OUT_FASTQ"; then
    echo "Error: Basecalling failed for sample $S"
    exit 1
  fi
  echo "    ✓ Basecalling complete"

  # 3) Demultiplex → one FASTQ per barcode
  DEMUX_DIR="$OUTPUT_DIR/${S}_demux"
  mkdir -p "$DEMUX_DIR"
  echo "  • Demultiplexing with kit $KIT_NAME → $DEMUX_DIR"
  if ! "$DORADO_BIN"/dorado demux --kit-name "$KIT_NAME" --output-dir "$DEMUX_DIR" "$OUT_FASTQ"; then
    echo "Error: Demultiplexing failed for sample $S"
    exit 1
  fi
  echo "    ✓ Demultiplexing complete"

  # 4) Trim barcodes off each demuxed FASTQ (recommended)
  echo "  • Trimming barcode sequences in $DEMUX_DIR"
  for FQ in "$DEMUX_DIR"/*.fastq; do
    BASENAME="$(basename "$FQ" .fastq)"
    OUT_TRIM="$DEMUX_DIR/${BASENAME}_trimmed.fastq"
    if ! "$DORADO_BIN"/dorado trim --sequencing-kit "$KIT_NAME" "$FQ" "$OUT_TRIM"; then
      echo "Error: Trimming failed for $FQ"
      exit 1
    fi
    echo "    – Trimmed $(basename "$OUT_TRIM")"
  done
  echo "    ✓ Trimming complete"
  echo

done

echo "DONE! All samples processed successfully."
