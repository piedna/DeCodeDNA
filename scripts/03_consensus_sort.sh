#!/usr/bin/env bash
# scripts/03_consensus_sort.sh
#
# Step III: Consensus / Sort
#
# Input:
#   A directory of classified FASTQ files (e.g. fish‐only FASTQ from Step II)
#
# Process:
#   1) Convert FASTQ → FASTA with seqkit
#   2) (Optional) Example VSEARCH clustering
#   3) Consensus building with Amplicon Sorter
#
# Tools:
#   - seqkit
#       A fast toolkit for FASTA/Q manipulation. Here we use `seqkit fq2fa`
#       to convert FASTQ files into FASTA for downstream clustering.
#   - vsearch
#       Example OTU clustering (not required for final pipeline; may be slow
#       on large datasets).
#   - amplicon_sorter
#       Rapid ASV/consensus-building script (not yet on Bioconda/PyPI, so
#       install manually—see below).  
#       **Supports read subsampling**: if you know you have a low-diversity dataset,
#       you can sample fewer reads to approximate the full set of variants,
#       greatly speeding consensus calling when compute resources are limited.
#
# BEFORE YOU RUN:
#   1) Create & activate a fresh env:
#         conda create -n asorter-env python=3.10 -y
#         conda activate asorter-env
#
#   2) Install seqkit & vsearch from Bioconda:
#         conda install -c conda-forge -c bioconda seqkit vsearch -y
#
#   3) Install Amplicon Sorter manually:
#         git clone https://github.com/avierstr/amplicon_sorter.git
#         cp amplicon_sorter/amplicon_sorter.py $CONDA_PREFIX/bin/amplicon_sorter
#         chmod +x $CONDA_PREFIX/bin/amplicon_sorter
#
#   Now you should have `seqkit`, `vsearch`, and `amplicon_sorter` on your PATH
#
set -euo pipefail

### ── USER CONFIG ─────────────────────────────────────────────────
FASTQ_DIR="${1:?Error: need FASTQ_DIR}"
OUTPUT_DIR="${2:?Error: need OUTPUT_DIR}"

# Amplicon Sorter parameters (tweak for your marker)
MINLEN="${MINLEN:-100}"        # min amplicon length (bp)
MAXLEN="${MAXLEN:-200}"        # max amplicon length (bp)
MAXREADS="${MAXREADS:-30000}"  # subsample depth (reads) via --maxreads
THREADS="${THREADS:-8}"        # processes per job

# ── Amplicon Sorter similarity thresholds explained:
# These three thresholds control how “tight” your clustering is at each step:
#   1. SSG (Similar Species Groups) = 90%
#      • Bundles reads ≥90% identical into broad “species-group” bins (coarse filter).
#   2. SS (Similar Species) = 95%
#      • Splits reads ≥95% identical into species-level clusters within groups (fine filter).
#   3. SC (Similar Consensus) = 98%
#      • Merges sequences ≥98% identical into final consensus ASVs (strictest collapse).
SSG="${SSG:-90}"   # coarse grouping (% identity)
SS="${SS:-95}"     # species-level clustering (% identity)
SC="${SC:-98}"     # consensus merge (% identity)

# directories
FASTA_DIR="$OUTPUT_DIR/fasta"
VSEARCH_DIR="$OUTPUT_DIR/vsearch_example"
ASORTER_DIR="$OUTPUT_DIR/amplicon_sorter"

mkdir -p "$FASTA_DIR" "$VSEARCH_DIR" "$ASORTER_DIR"

### ── SANITY CHECKS ────────────────────────────────────────────────
for cmd in seqkit amplicon_sorter; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' not found. Did you install it as described above?"
    exit 1
  fi
done

# vsearch is optional
if ! command -v vsearch &>/dev/null; then
  echo "Warning: vsearch not found; skipping VSEARCH example"
  USE_VSEARCH=0
else
  USE_VSEARCH=1
fi

echo
echo "🔹 FASTQ input:     $FASTQ_DIR"
echo "🔹 Output base dir: $OUTPUT_DIR"
echo

### ── 1) Convert FASTQ → FASTA -------------------------------
echo "▶ Converting all FASTQ → FASTA → $FASTA_DIR …"
for fq in "$FASTQ_DIR"/*.fastq "$FASTQ_DIR"/*.fastq.gz; do
  [[ -e "$fq" ]] || continue
  sample=$(basename "$fq" | sed 's/\(.fastq.*\)//')
  fa="$FASTA_DIR/${sample}.fasta"
  echo "  • $sample → $fa"
  seqkit fq2fa "$fq" -o "$fa"
done
echo "    ✓ Conversion complete"
echo

### ── 2) VSEARCH clustering (optional example) ------------------
if [[ "$USE_VSEARCH" -eq 1 ]]; then
  echo "▶ Example VSEARCH clustering (not recommended on large files)"
  mkdir -p "$VSEARCH_DIR"
  for fa in "$FASTA_DIR"/*.fasta; do
    sample=$(basename "$fa" .fasta)
    derep="$VSEARCH_DIR/${sample}_derep.fasta"
    centroids="$VSEARCH_DIR/${sample}_clustered.fasta"
    echo "  → $sample: derep → cluster"
    vsearch --derep_fulllength "$fa" \
            --output "$derep" \
            --sizeout --minuniquesize 1
    vsearch --cluster_fast "$derep" \
            --id 0.98 \
            --centroids "$centroids"
  done
  echo "    ✓ VSEARCH example complete"
  echo
fi

### ── 3) Amplicon Sorter consensus building ----------------------
ASCRIPT=$(which amplicon_sorter)
echo "▶ Amplicon Sorter consensus (depth=$MAXREADS, len=${MINLEN}-${MAXLEN}bp)"
for fa in "$FASTA_DIR"/*.fasta; do
  sample=$(basename "$fa" .fasta)
  outdir="$ASORTER_DIR/${sample}_amplicons"
  rm -rf "$outdir"
  echo
  echo "  → JOB: $sample"
  echo "    python3 $ASCRIPT \\"
  echo "      --input                '$fa' \\"
  echo "      --minlength            $MINLEN \\"
  echo "      --maxlength            $MAXLEN \\"
  echo "      --maxreads             $MAXREADS \\"
  echo "      --allreads             \\"
  echo "      --random               \\"
  echo "      --nprocesses           $THREADS \\"
  echo "      --similar_species_groups $SSG \\"
  echo "      --similar_species      $SS \\"
  echo "      --similar_consensus    $SC \\"
  echo "      --outputfolder         '$outdir'"
  python3 "$ASCRIPT" \
    --input                "$fa" \
    --minlength            "$MINLEN" \
    --maxlength            "$MAXLEN" \
    --maxreads             "$MAXREADS" \
    --allreads \
    --random \
    --nprocesses           "$THREADS" \
    --similar_species_groups "$SSG" \
    --similar_species      "$SS" \
    --similar_consensus    "$SC" \
    --outputfolder         "$outdir"
  echo "    ✓ Done: $outdir"
done

echo
echo "Step III complete!"
echo
echo "Results:"
echo " • FASTA                          → $FASTA_DIR/*.fasta"
if [[ "$USE_VSEARCH" -eq 1 ]]; then
  echo " • VSEARCH derep + cluster        → $VSEARCH_DIR/"
fi
echo " • Amplicon Sorter outputs:"
echo "     $ASORTER_DIR/<sample>_amplicons/consensus_sequences.fasta"
echo
echo "Next steps:"
echo " – Inspect each *_amplicons folder for consensus_sequences.fasta"
echo " – Feed these ASVs into Step IV (denoise)."
echo