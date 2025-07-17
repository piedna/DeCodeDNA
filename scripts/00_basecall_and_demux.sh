#!/usr/bin/env bash
# scripts/00_basecall_and_demux.sh
#
# A beginner-friendly pipeline for ONT basecalling:
#   1) Check Dorado installation
#   2) Download models (FAST, HAC, SUP) to Dorado folder
#   3) Convert FAST5 → POD5 (demonstration)
#   4) Basecalling with FAST model (GPU + CPU demonstration)
#   5) Basic QC stats
#
# For teaching: Shows both GPU and CPU basecalling approaches
# Real demultiplexing done separately with ONTbarcoder2.3 GUI
#
# Usage: Just run ./00_basecall_and_demux.sh
# Prerequisites: Dorado should be in eDNA_workshop/tools/

set -euo pipefail

# ─── PROJECT STRUCTURE PATHS ───────────────────────────────────────────────────
# Set paths relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"

# Input directory (contains fast5/ and pod5_barcode50/ folders)
INPUT_DIR="$PROJECT_ROOT/mock"

# Output directory (will be created)
OUTPUT_DIR="$PROJECT_ROOT/00_basecalled"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# ─── DORADO CONFIGURATION ──────────────────────────────────────────────────────

# Look for Dorado in tools directory
TOOLS_DIR="$WORKSPACE_ROOT/tools"

# Try to find Dorado installation automatically
DORADO_ROOT=""
DORADO_BIN=""

# Look for common Dorado directory patterns in tools
for dorado_dir in "$TOOLS_DIR"/dorado-* "$TOOLS_DIR"/dorado; do
  if [[ -d "$dorado_dir" && -f "$dorado_dir/bin/dorado" ]]; then
    DORADO_ROOT="$dorado_dir"
    DORADO_BIN="$dorado_dir/bin"
    break
  fi
done

# If not found in subdirectory, check if dorado binary is directly in tools
if [[ -z "$DORADO_ROOT" && -f "$TOOLS_DIR/dorado" ]]; then
  DORADO_ROOT="$TOOLS_DIR"
  DORADO_BIN="$TOOLS_DIR"
fi

# Model storage within Dorado installation
if [[ -n "$DORADO_ROOT" ]]; then
  MODEL_DIR="$DORADO_ROOT/models"
else
  MODEL_DIR="$TOOLS_DIR/dorado_models"
fi

# Models to download and demonstrate
MODELS=( 
  "dna_r10.4.1_e8.2_400bps_fast@v5.0.0"    # FAST model (for teaching)
  "dna_r10.4.1_e8.2_400bps_hac@v5.0.0"     # HAC model  
  "dna_r10.4.1_e8.2_400bps_sup@v5.0.0"     # SUP model
)

# Model to actually run (FAST for speed in classroom)
RUN_MODEL="dna_r10.4.1_e8.2_400bps_fast@v5.0.0"

# Test datasets (relative to INPUT_DIR)
FAST5_DIR="fast5"          # For FAST5→POD5 conversion demo
POD5_DIR="pod5_barcode50"  # For actual basecalling

echo "🧬 ONT Basecalling Pipeline for Teaching"
echo "════════════════════════════════════════"
echo "🔹 Project root:     $PROJECT_ROOT"
echo "🔹 Tools directory:  $TOOLS_DIR"
echo "🔹 Input directory:  $INPUT_DIR"
echo "🔹 Output directory: $OUTPUT_DIR"
echo "🔹 Dorado location:  $DORADO_ROOT"
echo "🔹 Platform:         $(uname -m) ($(uname -s))"
echo ""

# ─── STEP 1: CHECK DORADO INSTALLATION ─────────────────────────────────────────
echo "📥 STEP 1: Checking Dorado Installation"
echo "───────────────────────────────────────────"

if [[ -n "$DORADO_BIN" && -f "$DORADO_BIN/dorado" ]]; then
  echo "   ✅ Dorado found at: $DORADO_BIN/dorado"
  
  # Test Dorado
  if "$DORADO_BIN/dorado" --version &>/dev/null; then
    DORADO_VERSION=$("$DORADO_BIN/dorado" --version 2>/dev/null | head -1 || echo "Dorado")
    echo "   📋 Version: $DORADO_VERSION"
  else
    echo "   ⚠️  Dorado found but version check failed"
  fi
else
  echo "❌ Dorado not found in tools directory"
  echo ""
  echo "📋 Please ensure Dorado is installed in the correct location:"
  echo "   Expected locations:"
  echo "   • $TOOLS_DIR/dorado-*/bin/dorado (extracted from archive)"
  echo "   • $TOOLS_DIR/dorado (if renamed)"
  echo "   • $TOOLS_DIR/dorado (if binary placed directly)"
  echo ""
  echo "   Current tools directory structure:"
  if [[ -d "$TOOLS_DIR" ]]; then
    ls -la "$TOOLS_DIR/" | head -10
  else
    echo "   ❌ Tools directory not found: $TOOLS_DIR"
    echo "   💡 Create it with: mkdir -p $TOOLS_DIR"
  fi
  echo ""
  echo "   Download Dorado from: https://github.com/nanoporetech/dorado/releases"
  echo "   Extract to: $TOOLS_DIR/"
  exit 1
fi

# Check pod5 tools (standalone tool, not part of Dorado)
if ! command -v pod5 &>/dev/null; then
  echo "🔄 Installing pod5 tools..."
  if command -v pip &>/dev/null; then
    pip install pod5
  elif command -v pip3 &>/dev/null; then
    pip3 install pod5
  else
    echo "❌ pip not found - please install pod5 manually: pip install pod5"
    exit 1
  fi
  echo "   ✅ pod5 tools installed"
else
  echo "   ✅ pod5 tools found"
fi

# Verify installation
if ! "$DORADO_BIN/dorado" --version &>/dev/null; then
  echo "❌ Dorado installation verification failed"
  exit 1
fi

echo "   ✅ All tools ready!"
echo ""

# ─── STEP 2: DOWNLOAD MODELS TO DORADO FOLDER ─────────────────────────────────
echo "📦 STEP 2: Downloading Basecalling Models"
echo "─────────────────────────────────────────────"

# Create model directory in Dorado installation
mkdir -p "$MODEL_DIR"
echo "   📁 Model download location: $MODEL_DIR"

# Change to model directory for downloads
cd "$MODEL_DIR"

for MODEL in "${MODELS[@]}"; do
  echo "   • Downloading $MODEL..."
  if "$DORADO_BIN/dorado" download --model "$MODEL"; then
    echo "     ✅ $MODEL ready"
  else
    echo "     ⚠️  Failed to download $MODEL (continuing...)"
  fi
done

# Return to original directory
cd - >/dev/null

echo "   ✅ Model downloads complete"
echo "   📂 Models stored in: $MODEL_DIR"
echo ""

# ─── STEP 3: FAST5 → POD5 CONVERSION (EDUCATIONAL DEMO - COMMENTED OUT) ───────
echo "📚 STEP 3: FAST5 → POD5 Conversion (Educational Purpose Only)"
echo "─────────────────────────────────────────────────────────────────"

FAST5_PATH="$INPUT_DIR/$FAST5_DIR"
CONVERTED_POD5_DIR="$INPUT_DIR/pod5_converted"

if [[ -d "$FAST5_PATH" ]] && compgen -G "$FAST5_PATH"/*.fast5 >/dev/null; then
  echo "   📁 Found FAST5 files in: $FAST5_PATH"
  ls -la "$FAST5_PATH"/*.fast5 | head -3
  
  echo ""
  echo "   📚 EDUCATIONAL NOTE: FAST5 → POD5 Conversion"
  echo "      • FAST5: Legacy Oxford Nanopore format (HDF5-based, slower)"
  echo "      • POD5: Modern format (faster, more efficient, default in MinKNOW)"
  echo "      • Modern MinKNOW generates POD5 files directly - no conversion needed!"
  echo ""
  echo "   💡 For reference, the conversion command would be:"
  echo "      mkdir -p $CONVERTED_POD5_DIR"
  echo "      pod5 convert fast5 $FAST5_PATH/*.fast5 --output-dir $CONVERTED_POD5_DIR --one-to-one"
  echo ""
  echo "   ⏭️  Skipping conversion - using existing POD5 files for basecalling demo"
  
  # Commented out conversion code (kept for educational reference)
  # echo "   🔄 Converting FAST5 → POD5..."
  # echo "      This demonstrates the conversion process for teaching"
  # echo "      Using standalone pod5 tool (not part of Dorado)"
  # 
  # # Create conversion output directory
  # mkdir -p "$CONVERTED_POD5_DIR"
  # 
  # # Try conversion using standalone pod5 tool
  # if pod5 convert fast5 "$FAST5_PATH"/*.fast5 --output-dir "$CONVERTED_POD5_DIR" --one-to-one; then
  #   echo "   ✅ Conversion complete → $CONVERTED_POD5_DIR/"
  #   echo "      Converted files:"
  #   ls -la "$CONVERTED_POD5_DIR/" | head -5
  # else
  #   echo "   ⚠️  Conversion failed (continuing with existing POD5 files)"
  #   echo "      Note: This can happen on some systems - we'll use existing POD5 files"
  # fi
else
  echo "   📁 No FAST5 files found at $FAST5_PATH"
  echo "   📚 EDUCATIONAL NOTE: Modern workflows use POD5 directly from MinKNOW"
  echo "      Legacy conversion command: pod5 convert fast5 *.fast5 --output-dir converted/"
fi

echo ""

# ─── STEP 4: BASECALLING DEMONSTRATION ─────────────────────────────────────────
echo "🧬 STEP 4: Basecalling Demonstration"
echo "───────────────────────────────────────"

POD5_PATH="$INPUT_DIR/$POD5_DIR"

if [[ ! -d "$POD5_PATH" ]]; then
  echo "❌ POD5 directory not found: $POD5_PATH"
  echo "   Expected to find POD5 files for basecalling"
  exit 1
fi

echo "   📁 POD5 input directory: $POD5_PATH"
POD5_COUNT=$(find "$POD5_PATH" -name "*.pod5" | wc -l)
echo "   📊 Found $POD5_COUNT POD5 files"

if [[ "$POD5_COUNT" -eq 0 ]]; then
  echo "❌ No POD5 files found in $POD5_PATH"
  exit 1
fi

# Show file stats
echo "   📋 POD5 file details:"
ls -lh "$POD5_PATH"/*.pod5 | head -3

echo ""
echo "🖥️  APPROACH 1: GPU Basecalling (if available)"
echo "─────────────────────────────────────────────────"

GPU_OUTPUT="$OUTPUT_DIR/gpu_basecalling.fastq"
echo "   🚀 Attempting GPU basecalling with $RUN_MODEL..."
echo "      Output: $GPU_OUTPUT"

# Try GPU basecalling (will fall back to CPU if no GPU)
GPU_START_TIME=$(date +%s)
if "$DORADO_BIN/dorado" basecaller "$MODEL_DIR/$RUN_MODEL" "$POD5_PATH" --emit-fastq > "$GPU_OUTPUT" 2>/dev/null; then
  GPU_END_TIME=$(date +%s)
  GPU_DURATION=$((GPU_END_TIME - GPU_START_TIME))
  echo "   ✅ GPU basecalling completed in ${GPU_DURATION}s"
  
  # Show stats
  if [[ -s "$GPU_OUTPUT" ]]; then
    READ_COUNT=$(grep -c "^@" "$GPU_OUTPUT" || echo "0")
    FILE_SIZE=$(du -h "$GPU_OUTPUT" | cut -f1)
    echo "      📊 Reads: $READ_COUNT"
    echo "      📁 Size: $FILE_SIZE"
  fi
else
  echo "   ⚠️  GPU basecalling failed or no GPU available"
  rm -f "$GPU_OUTPUT"
fi

echo ""
echo "💻 APPROACH 2: CPU Basecalling (very slow)"
echo "─────────────────────────────────────────────────"

CPU_OUTPUT="$OUTPUT_DIR/cpu_basecalling.fastq"
echo "   🔄 Running CPU basecalling with $RUN_MODEL..."
echo "      Output: $CPU_OUTPUT"
echo "      Note: This will be slower but works on all machines"

CPU_START_TIME=$(date +%s)
if "$DORADO_BIN/dorado" basecaller "$MODEL_DIR/$RUN_MODEL" "$POD5_PATH" --device cpu --emit-fastq > "$CPU_OUTPUT"; then
  CPU_END_TIME=$(date +%s)
  CPU_DURATION=$((CPU_END_TIME - CPU_START_TIME))
  echo "   ✅ CPU basecalling completed in ${CPU_DURATION}s"
  
  # Show stats
  if [[ -s "$CPU_OUTPUT" ]]; then
    READ_COUNT=$(grep -c "^@" "$CPU_OUTPUT" || echo "0")
    FILE_SIZE=$(du -h "$CPU_OUTPUT" | cut -f1)
    echo "      📊 Reads: $READ_COUNT"
    echo "      📁 Size: $FILE_SIZE"
    
    # Show sample reads
    echo "      📝 Sample reads:"
    head -8 "$CPU_OUTPUT" | sed 's/^/         /'
  fi
else
  echo "   ❌ CPU basecalling failed"
  exit 1
fi

echo ""

# ─── STEP 5: COMPARISON AND QC ─────────────────────────────────────────────────
echo "📊 STEP 5: Results Summary"
echo "─────────────────────────────"

echo "🎯 Teaching Summary:"
echo "   📦 Models downloaded: ${#MODELS[@]} (FAST, HAC, SUP)"
echo "   📚 Conversion concept: FAST5 → POD5 explained (modern MinKNOW uses POD5)"
echo "   🧬 Basecalling demo: FAST model for speed"
echo ""

echo "⚡ Performance Comparison:"
if [[ -f "$GPU_OUTPUT" && -f "$CPU_OUTPUT" ]]; then
  echo "   🖥️  GPU basecalling: ${GPU_DURATION}s"
  echo "   💻 CPU basecalling: ${CPU_DURATION}s"
  
  if [[ "$GPU_DURATION" -lt "$CPU_DURATION" ]]; then
    SPEEDUP=$(echo "scale=1; $CPU_DURATION / $GPU_DURATION" | bc -l 2>/dev/null || echo "N/A")
    echo "   🚀 GPU speedup: ${SPEEDUP}x faster"
  fi
elif [[ -f "$CPU_OUTPUT" ]]; then
  echo "   💻 CPU basecalling: ${CPU_DURATION}s (GPU not available)"
fi

echo ""
echo "📁 Output Files Created:"
echo "   📂 $OUTPUT_DIR/"
if [[ -f "$GPU_OUTPUT" ]]; then
  echo "   ├── gpu_basecalling.fastq (GPU results)"
fi
if [[ -f "$CPU_OUTPUT" ]]; then
  echo "   ├── cpu_basecalling.fastq (CPU results)"
fi
echo ""
echo "   📂 $INPUT_DIR/"
echo "   ├── fast5/ (original FAST5 files - for educational reference)"
echo "   └── pod5_barcode50/ (modern POD5 files used for basecalling)"

echo ""
echo "🎓 For the Class:"
echo "   • Modern MinKNOW generates POD5 files directly (no conversion needed)"
echo "   • Compare GPU vs CPU basecalling performance"
echo "   • Understand different model types (FAST/HAC/SUP trade-offs)"
echo "   • Ready FASTQ files for downstream demultiplexing"
echo ""
echo "🔗 Next Steps:"
echo "   • Use ONTbarcoder2.3 GUI for demultiplexing"
echo "   • Quality filtering and taxonomic assignment"
echo "   • Continue with scripts 01-05 for eDNA analysis"
echo ""
echo "✅ Basecalling pipeline complete!"

# ─── FINAL FILE CHECK ──────────────────────────────────────────────────────────
echo "🔍 Final Output Verification:"
for output_file in "$GPU_OUTPUT" "$CPU_OUTPUT"; do
  if [[ -f "$output_file" ]]; then
    echo "   ✅ $(basename "$output_file"): $(wc -l < "$output_file") lines"
  fi
done

echo ""
echo "📂 Project Organization:"
echo "   ✅ Models stored in: $MODEL_DIR"
echo "   ✅ Dorado integrated in tools structure"
echo "   ✅ No hardcoded user paths required"
echo "   ✅ Focus on modern POD5 workflow"
echo ""