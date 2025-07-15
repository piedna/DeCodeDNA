#!/usr/bin/env bash
# scripts/03_consensus_sort.sh
#
# Step III: Consensus Building - Dual Approach for Teaching
#
# This script demonstrates TWO clustering approaches:
# 1. vsearch: Fast, local clustering (runs automatically)
# 2. amplicon_sorter: Advanced clustering (command provided, but commented out)
#
# Input: Kraken2 results directory from Step II
# Output: 
#   - vsearch consensus sequences (generated locally)
#   - amplicon_sorter command (for demonstration)
#   - Instructions to use pre-computed amplicon_sorter results
#
set -euo pipefail

### ── USER CONFIG ─────────────────────────────────────────────────
KRAKEN_RESULTS_DIR="${1:?Error: need KRAKEN_RESULTS_DIR (e.g., results/02_quicklook)}"
OUTPUT_DIR="${2:?Error: need OUTPUT_DIR}"

# Which Kraken2 database to use for consensus building
DATABASE="${DATABASE:-mitofish}"  # Use mitofish by default (best classification rate)

# Clustering parameters
VSEARCH_SIMILARITY="${VSEARCH_SIMILARITY:-0.97}"  # 97% similarity for vsearch
AMPLICON_MINLEN="${AMPLICON_MINLEN:-150}"         # amplicon_sorter min length
AMPLICON_MAXLEN="${AMPLICON_MAXLEN:-350}"         # amplicon_sorter max length
AMPLICON_MAXREADS="${AMPLICON_MAXREADS:-1000}"    # amplicon_sorter max reads (for local demo)

# Directories
VSEARCH_DIR="$OUTPUT_DIR/vsearch_clustering"
AMPLICON_DIR="$OUTPUT_DIR/amplicon_sorter_demo"
mkdir -p "$VSEARCH_DIR" "$AMPLICON_DIR"

### ── SANITY CHECKS ────────────────────────────────────────────────
echo "🔍 Checking required programs..."

# Check for vsearch
if ! command -v vsearch &>/dev/null; then
  echo "❌ Error: vsearch not found."
  echo "   Install via: conda install -c bioconda vsearch"
  exit 1
else
  echo "✅ vsearch found"
fi

# Check for seqkit
if ! command -v seqkit &>/dev/null; then
  echo "❌ Error: seqkit not found."
  echo "   Install via: conda install -c bioconda seqkit"
  exit 1
else
  echo "✅ seqkit found"
fi

# Check for amplicon_sorter (optional for demo)
if command -v amplicon_sorter &>/dev/null; then
  echo "✅ amplicon_sorter found (available for demo)"
  AMPLICON_AVAILABLE=1
else
  echo "⚠️  amplicon_sorter not found (demo commands will be provided)"
  AMPLICON_AVAILABLE=0
fi

# Check if Kraken2 results exist
KRAKEN_DB_DIR="$KRAKEN_RESULTS_DIR/$DATABASE"
if [[ ! -d "$KRAKEN_DB_DIR" ]]; then
  echo "❌ Error: Kraken2 results not found at $KRAKEN_DB_DIR"
  echo "Available databases:"
  ls -la "$KRAKEN_RESULTS_DIR/"
  exit 1
fi

echo
echo "🔹 Kraken2 results:    $KRAKEN_DB_DIR"
echo "🔹 Using database:     $DATABASE"
echo "🔹 vsearch similarity: $VSEARCH_SIMILARITY"
echo "🔹 Output directory:   $OUTPUT_DIR"
echo

### ── FIND CLASSIFIED FASTA FILES ─────────────────────────────────
echo "▶ Finding fish-classified sequences..."
shopt -s nullglob
classified_files=("$KRAKEN_DB_DIR"/*_classified.fasta)

if [[ ${#classified_files[@]} -eq 0 ]]; then
  echo "❌ No classified .fasta files found in $KRAKEN_DB_DIR"
  echo "Looking for files matching: *_classified.fasta"
  echo "Available files:"
  ls -la "$KRAKEN_DB_DIR/"
  exit 1
fi

echo "Found ${#classified_files[@]} classified file(s):"
for file in "${classified_files[@]}"; do
  echo "  • $(basename "$file")"
  # Show input stats
  if command -v seqkit &>/dev/null; then
    seqkit stats "$file" 2>/dev/null | tail -n +2 | sed 's/^/    /' || {
      echo "    File stats unavailable"
    }
  fi
done
echo

### ── APPROACH 1: VSEARCH CLUSTERING (RUNS LOCALLY) ───────────────
echo "🚀 APPROACH 1: vsearch Clustering (Local Execution)"
echo "   Purpose: Fast, lightweight clustering for immediate results"
echo "   Best for: Mock communities, teaching demonstrations"
echo

for classified_file in "${classified_files[@]}"; do
  # Extract sample name
  sample=$(basename "$classified_file")
  sample="${sample%_${DATABASE}_classified.fasta}"
  
  echo "▶ vsearch clustering: $sample"
  
  # Step 1: Dereplicate sequences
  derep_file="$VSEARCH_DIR/${sample}_dereplicated.fasta"
  echo "  • Dereplicating sequences..."
  vsearch \
    --derep_fulllength "$classified_file" \
    --output "$derep_file" \
    --sizeout \
    --minuniquesize 1
  
  # Step 2: Cluster sequences
  vsearch_consensus="$VSEARCH_DIR/${sample}_vsearch_consensus.fasta"
  echo "  • Clustering at ${VSEARCH_SIMILARITY} similarity..."
  vsearch \
    --cluster_fast "$derep_file" \
    --id "$VSEARCH_SIMILARITY" \
    --centroids "$vsearch_consensus" \
    --clusters "$VSEARCH_DIR/${sample}_clusters"
  
  echo "  ✅ vsearch consensus: $vsearch_consensus"
  
  # Show clustering stats
  if command -v seqkit &>/dev/null; then
    echo "    Clustering results:"
    seqkit stats "$vsearch_consensus" 2>/dev/null | tail -n +2 | sed 's/^/      /' || {
      echo "      Stats unavailable"
    }
  fi
  echo
done

### ── APPROACH 2: AMPLICON_SORTER DEMO (COMMAND PROVIDED) ──────────
echo "🎯 APPROACH 2: amplicon_sorter Demo (Advanced Clustering)"
echo "   Purpose: Sophisticated clustering designed for ONT/eDNA data"
echo "   Best for: Real eDNA samples, final publication results"
echo "   Status: Command provided for demonstration"
echo

for classified_file in "${classified_files[@]}"; do
  sample=$(basename "$classified_file")
  sample="${sample%_${DATABASE}_classified.fasta}"
  
  echo "▶ amplicon_sorter demo: $sample"
  echo "  Input: $classified_file"
  
  # Generate the amplicon_sorter command
  sample_output="$AMPLICON_DIR/${sample}_amplicons"
  
  cat << EOF
  
  📋 amplicon_sorter Command (Copy & Paste to Try):
  ────────────────────────────────────────────────────────────────
  python3 \$(which amplicon_sorter) \\
    -i '$classified_file' \\
    -min $AMPLICON_MINLEN \\
    -max $AMPLICON_MAXLEN \\
    -ar -ra \\
    -maxr $AMPLICON_MAXREADS \\
    -ssg 95 -ss 97 -sc 98 \\
    -np 1 \\
    -o '$sample_output'
  ────────────────────────────────────────────────────────────────
  
  ⚠️  Note: This command may hang locally due to multiprocessing issues.
      For real analysis, run on a server with more resources.
  
EOF

  # Only run if specifically requested and available
  if [[ "${RUN_AMPLICON_SORTER:-0}" -eq 1 && "$AMPLICON_AVAILABLE" -eq 1 ]]; then
    echo "  🔄 Running amplicon_sorter (this may take a while or hang)..."
    python3 "$(which amplicon_sorter)" \
      -i "$classified_file" \
      -min "$AMPLICON_MINLEN" \
      -max "$AMPLICON_MAXLEN" \
      -ar -ra \
      -maxr "$AMPLICON_MAXREADS" \
      -ssg 95 -ss 97 -sc 98 \
      -np 1 \
      -o "$sample_output" || {
        echo "  ❌ amplicon_sorter failed (expected for local execution)"
      }
  else
    echo "  💡 To enable amplicon_sorter execution: RUN_AMPLICON_SORTER=1 bash scripts/03_consensus_sort.sh ..."
  fi
  echo
done

### ── PRE-COMPUTED AMPLICON_SORTER RESULTS ───────────────────────
echo "📁 APPROACH 2B: Pre-computed amplicon_sorter Results"
echo "   For this class, we provide pre-computed amplicon_sorter results:"
echo "   Generated on high-performance server with optimized parameters"
echo

# Check if pre-computed results exist
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRECOMPUTED_FILE="$PROJECT_ROOT/mock/mock_amplicon_sorter_clustered_consensus.fasta"

if [[ -f "$PRECOMPUTED_FILE" ]]; then
  echo "  ✅ Found pre-computed results: $PRECOMPUTED_FILE"
  
  # Copy to output directory for downstream analysis
  cp "$PRECOMPUTED_FILE" "$OUTPUT_DIR/amplicon_sorter_consensus.fasta"
  echo "  📋 Copied to: $OUTPUT_DIR/amplicon_sorter_consensus.fasta"
  
  # Show the exact server command used to generate these results
  cat << 'EOF'
  
  🖥️  Server Command Used to Generate Pre-computed Results:
  ────────────────────────────────────────────────────────────────
  python3 ~/amp_sorter/amplicon_sorter.py \
    -i test_fhl_200k_mitofish_classified.fasta \
    -min 150 \
    -max 350 \
    -ar \
    -ra \
    -maxr 119241 \
    -ssg 95 \
    -ss 97 \
    -sc 98 \
    -np 120 \
    -o fish_consensus_MAX_reads
  ────────────────────────────────────────────────────────────────
  
  📚 Parameter Explanations (Optimized for 12S/mitofish):
  
  Basic Parameters:
  • -min 150, -max 350    : Length filter (150-350bp)
                           Reason: 12S amplicons typically 200-300bp
                           Removes PCR artifacts and incomplete reads
  
  • -ar (--allreads)       : Use all reads in length range
                           Reason: Maximize data for better consensus
  
  • -ra (--random)         : Random sampling when needed
                           Reason: Ensure unbiased representation
  
  • -maxr 119241          : Process ALL classified fish reads
                           Reason: Use complete dataset (not subsampled)
  
  Clustering Thresholds (Conservative for 12S):
  • -ssg 95               : Species groups at 95% similarity
                           Reason: 12S is highly conserved, needs tight grouping
                           Default (~90%) too loose for species resolution
  
  • -ss 97                : Species level at 97% similarity  
                           Reason: 12S allows species-level discrimination
                           More stringent than default (85%) for cleaner clusters
  
  • -sc 98                : Final consensus at 98% similarity
                           Reason: Very tight final clustering
                           Reduces intraspecific variation artifacts
  
  Technical Parameters:
  • -np 120               : 120 CPU threads (server only)
                           Reason: Maximize parallel processing on server
                           Local systems use -np 1 to avoid crashes
  
  🎯 Results: 21 high-quality consensus sequences representing distinct fish species/variants
     Compare with vsearch's 77,393 clusters - same biology, different granularity!
  
EOF
  
  # Show stats
  if command -v seqkit &>/dev/null; then
    echo "    Pre-computed consensus stats:"
    seqkit stats "$PRECOMPUTED_FILE" 2>/dev/null | tail -n +2 | sed 's/^/      /' || {
      echo "      Stats unavailable"
    }
  fi
else
  echo "  ⚠️  Pre-computed results not found at: $PRECOMPUTED_FILE"
  echo "      Please ensure mock_amplicon_sorter_clustered_consensus.fasta is in the mock/ directory"
fi

echo

### ── COMPARISON & NEXT STEPS ──────────────────────────────────────
echo "📊 CLUSTERING COMPARISON SUMMARY"
echo "────────────────────────────────────────────────────────────────"
echo "Two approaches demonstrated:"
echo
echo "1. 🏃 vsearch (Fast & Local):"
echo "   • Results: $VSEARCH_DIR/*_vsearch_consensus.fasta"
echo "   • Pros: Fast, reliable, runs locally"
echo "   • Cons: Conservative clustering, may preserve errors"
echo "   • Use case: Mock communities, quick analysis"
echo
echo "2. 🎯 amplicon_sorter (Advanced & Thorough):"
echo "   • Results: $OUTPUT_DIR/amplicon_sorter_consensus.fasta (pre-computed)"
echo "   • Pros: Sophisticated error correction, designed for ONT data"
echo "   • Cons: Slow locally, requires server resources"
echo "   • Use case: Real eDNA samples, publication-quality results"
echo
echo "📈 For downstream analysis, you can use BOTH:"
echo "   • vsearch results: Compare clustering approaches"
echo "   • amplicon_sorter results: Final biological interpretation"
echo
echo "🔬 Next steps:"
echo "   • Taxonomic assignment of consensus sequences"
echo "   • Compare clustering methods with Krona plots"
echo "   • Species identification and abundance estimation"
echo
echo "✅ Step III complete - Ready for downstream analysis!"
