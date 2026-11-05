#!/usr/bin/env bash
# scripts/03_consensus_sort.sh
#
# Step III: Consensus Building - ABUNDANCE TRACKING + PIPELINE COMPATIBLE
# Creates exact file structure that script 04 expects
#
set -euo pipefail

### ── USER CONFIG ─────────────────────────────────────────────────────
KRAKEN_RESULTS_DIR="${1:?Error: need KRAKEN_RESULTS_DIR (e.g., results/02_quicklook)}"
OUTPUT_DIR="${2:?Error: need OUTPUT_DIR}"

# Which Kraken2 databases to process
DATABASES="${DATABASES:-12s coi mitofish}"

# Clustering parameters
VSEARCH_SIMILARITY="${VSEARCH_SIMILARITY:-0.97}"
# What represents each cluster: "consensus" (default) = consensus of all reads in the cluster
# (vsearch --consout), which averages out nanopore sequencing errors; "centroid" = the cluster's
# seed read (vsearch --centroids), the behaviour of DeCodeDNA 0.1.
REPRESENTATIVE="${REPRESENTATIVE:-consensus}"
case "$REPRESENTATIVE" in consensus|centroid) ;; *) echo "❌ REPRESENTATIVE must be 'consensus' or 'centroid' (got '$REPRESENTATIVE')"; exit 1;; esac
# Write which read went to which cluster (one .uc table per sample). Off by default: large, and not
# used by later steps.
WRITE_CLUSTER_MAP="${WRITE_CLUSTER_MAP:-false}"
# Keep the dereplicated reads after clustering (large; not used by later steps)
KEEP_INTERMEDIATES="${KEEP_INTERMEDIATES:-false}"

# Threads, and how many samples to cluster at the same time (see resources.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/resources.sh"

# Directories - MATCH ORIGINAL 03 STRUCTURE
VSEARCH_DIR="$OUTPUT_DIR/vsearch_clustering"
ABUNDANCE_DIR="$OUTPUT_DIR/abundance_tracking"
mkdir -p "$VSEARCH_DIR" "$ABUNDANCE_DIR"

### ── ABUNDANCE TRACKING FUNCTIONS ──────────────────────────────────────
extract_abundance() {
    local fasta_file="$1"
    if [[ ! -f "$fasta_file" ]]; then echo "0"; return; fi
    grep "^>" "$fasta_file" 2>/dev/null | \
        sed 's/.*size=\([0-9]*\).*/\1/' | \
        awk '{sum+=$1} END {print sum+0}'
}

count_sequences() {
    local fasta_file="$1"
    if [[ ! -f "$fasta_file" ]]; then echo "0"; return; fi
    if [[ "$fasta_file" == *.gz ]]; then
        gzip -cd "$fasta_file" | grep -c "^>" 2>/dev/null || echo "0"
    else
        grep -c "^>" "$fasta_file" 2>/dev/null || echo "0"
    fi
}

### ── SANITY CHECKS ──────────────────────────────────────────────────────
echo "🔍 Checking required programs..."

for cmd in vsearch seqkit bc; do
    if ! command -v $cmd &>/dev/null; then
        echo "❌ Error: $cmd not found."
        exit 1
    else
        echo "✅ $cmd found"
    fi
done

echo
echo "Kraken2 results:    $KRAKEN_RESULTS_DIR"
echo "Processing databases: $DATABASES"
echo "vsearch similarity: $VSEARCH_SIMILARITY"
echo "Cluster sequence:   $REPRESENTATIVE"
echo "Output directory:   $OUTPUT_DIR"
echo "Abundance tracking:  $ABUNDANCE_DIR"
echo

### ── PROCESS EACH DATABASE ──────────────────────────────────────────────
consensus_built=0
for DATABASE in $DATABASES; do
    echo "╔══════════════════════════════════════════════════════════════════════"
    echo "║ Processing Database: $DATABASE"
    echo "╚══════════════════════════════════════════════════════════════════════"
    
    KRAKEN_DB_DIR="$KRAKEN_RESULTS_DIR/$DATABASE"
    if [[ ! -d "$KRAKEN_DB_DIR" ]]; then
        echo "⚠️  Warning: Kraken2 results not found at $KRAKEN_DB_DIR"
        echo "   Skipping database: $DATABASE"
        continue
    fi

    # Create database-specific output directories - MATCH ORIGINAL 03
    DB_VSEARCH_DIR="$VSEARCH_DIR/$DATABASE"
    DB_ABUNDANCE_DIR="$ABUNDANCE_DIR/$DATABASE"
    mkdir -p "$DB_VSEARCH_DIR" "$DB_ABUNDANCE_DIR"

    ### ── FIND CLASSIFIED FASTA FILES ─────────────────────────────────────
    echo "▶ Finding $DATABASE-classified sequences..."
    shopt -s nullglob
    # Script 02 compresses the classified reads (.fasta.gz) unless KEEP_INTERMEDIATES=true
    classified_files=("$KRAKEN_DB_DIR"/*_classified.fasta "$KRAKEN_DB_DIR"/*_classified.fasta.gz)

    if [[ ${#classified_files[@]} -eq 0 ]]; then
        echo "⚠️  No classified .fasta files found in $KRAKEN_DB_DIR"
        continue
    fi

    echo "Found ${#classified_files[@]} classified file(s) for $DATABASE:"
    for file in "${classified_files[@]}"; do
        echo "  • $(basename "$file")"
    done
    echo

    ### ── VSEARCH CLUSTERING WITH ABUNDANCE TRACKING ───────────────────────
    echo "vsearch Clustering for $DATABASE (With Abundance Tracking)"
    echo

    # cluster_one_sample FILE SAMPLE : dereplicate, cluster, write abundance summary
    cluster_one_sample() {
        local classified_file=$1 sample=$2
        local derep_file vsearch_consensus summary_file classified_count derep_seq_count derep_read_count
        local consensus_seq_count consensus_read_count read_retention rep_opt uc_opt
        echo "▶ vsearch clustering: $sample ($DATABASE)"
        # Check for empty classified files
if [[ ! -s "$classified_file" ]]; then
    echo "  ⚠️  Skipping empty classified file: $(basename "$classified_file")"
    return 0
fi
        
        # Step 1: Dereplicate sequences (PRESERVE abundance with --sizeout)
        derep_file="$DB_VSEARCH_DIR/${sample}_${DATABASE}_dereplicated.fasta"
        echo "  • Dereplicating sequences (preserving abundance)..."
        vsearch \
          --derep_fulllength "$classified_file" \
          --output "$derep_file" \
          --sizeout \
          --minuniquesize 1 \
          --threads "$JOB_THREADS"
          
          # Check if dereplication produced any sequences
if [[ ! -s "$derep_file" ]]; then
    echo "  ⚠️  No sequences after dereplication, skipping clustering for $sample"
    return 0
fi
        
        # Step 2: Cluster sequences - CREATE EXACT FILES SCRIPT 04 EXPECTS
        # Script 04 looks for: "*_${DATABASE}_vsearch_consensus.fasta"
        vsearch_consensus="$DB_VSEARCH_DIR/${sample}_${DATABASE}_vsearch_consensus.fasta"
        echo "  • Clustering at ${VSEARCH_SIMILARITY} similarity (keeping the cluster $REPRESENTATIVE)..."
        if [[ "$REPRESENTATIVE" == "consensus" ]]; then rep_opt=(--consout "$vsearch_consensus"); else rep_opt=(--centroids "$vsearch_consensus"); fi
        uc_opt=()
        [[ "$WRITE_CLUSTER_MAP" == "true" ]] && uc_opt=(--uc "$DB_VSEARCH_DIR/${sample}_${DATABASE}_clusters.uc")
        vsearch \
          --cluster_fast "$derep_file" \
          --id "$VSEARCH_SIMILARITY" \
          "${rep_opt[@]}" \
          ${uc_opt[@]+"${uc_opt[@]}"} \
          --sizein \
          --sizeout \
          --threads "$JOB_THREADS"
        
        # Step 3: CREATE ABUNDANCE SUMMARY
        summary_file="$DB_ABUNDANCE_DIR/${sample}_${DATABASE}_abundance_summary.txt"
        echo "  • Creating abundance summary..."
        
        classified_count=$(count_sequences "$classified_file")
        derep_seq_count=$(count_sequences "$derep_file")
        derep_read_count=$(extract_abundance "$derep_file")
        consensus_seq_count=$(count_sequences "$vsearch_consensus")
        consensus_read_count=$(extract_abundance "$vsearch_consensus")
        
        cat > "$summary_file" << EOF
# Abundance Tracking Summary
# Sample: $sample
# Database: $DATABASE
# Generated: $(date)

## Input (Classified sequences from Kraken2)
classified_sequences: $classified_count
classified_reads: $classified_count

## After Dereplication (vsearch --derep_fulllength)
dereplicated_sequences: $derep_seq_count
dereplicated_reads: $derep_read_count

## After Clustering (vsearch --cluster_fast)
consensus_sequences: $consensus_seq_count
consensus_reads: $consensus_read_count

## Files
classified_file: $classified_file
dereplicated_file: $derep_file (removed after clustering unless KEEP_INTERMEDIATES=true)
consensus_file: $vsearch_consensus
EOF
        
        echo "  vsearch consensus: $vsearch_consensus"
        echo "  abundance summary: $summary_file"
        
        # Show abundance-aware stats
        echo "   Abundance Flow Summary:"
        echo "      Input reads:     $classified_count"
        echo "      Derep sequences: $derep_seq_count (representing $derep_read_count reads)"
        echo "      Consensus OTUs:  $consensus_seq_count (representing $consensus_read_count reads)"
        if [[ "$classified_count" -gt 0 && "$consensus_read_count" -gt 0 ]]; then
          read_retention=$(echo "scale=2; $consensus_read_count * 100 / $classified_count" | bc -l 2>/dev/null || echo "N/A")
          echo "      Read retention:  ${read_retention}%"
        fi
        echo
        if [[ "$KEEP_INTERMEDIATES" != "true" ]]; then rm -f "$derep_file"; fi
    }

    decodedna_plan_parallel ${#classified_files[@]} 4 2
    echo "Clustering ${#classified_files[@]} sample(s), $JOBS at a time, $JOB_THREADS thread(s) each"
    echo
    LOG_DIR="$DB_ABUNDANCE_DIR/logs"
    pids=(); pid_samples=()
    for classified_file in "${classified_files[@]}"; do
        sample=$(basename "$classified_file")
        sample="${sample%.gz}"; sample="${sample%_${DATABASE}_classified.fasta}"
        if [[ "$JOBS" -gt 1 ]]; then
            mkdir -p "$LOG_DIR"
            decodedna_wait_for_slot "$JOBS"
            cluster_one_sample "$classified_file" "$sample" > "$LOG_DIR/${sample}.log" 2>&1 &
            pids+=($!); pid_samples+=("$sample")
        else
            cluster_one_sample "$classified_file" "$sample"
        fi
    done
    failed=0; i=0
    while [[ $i -lt ${#pids[@]} ]]; do
        if wait "${pids[$i]}"; then
            cat "$LOG_DIR/${pid_samples[$i]}.log"
        else
            echo "❌ Clustering failed for ${pid_samples[$i]}:"; cat "$LOG_DIR/${pid_samples[$i]}.log"; failed=1
        fi
        i=$((i + 1))
    done
    [[ $failed -eq 0 ]] || { echo "❌ Step 03 stopped: clustering failed for at least one sample (see above)"; exit 1; }
    for f in "$DB_VSEARCH_DIR"/*_"${DATABASE}"_vsearch_consensus.fasta; do
        [[ -s "$f" ]] && consensus_built=$((consensus_built + 1))
    done

    echo "Database $DATABASE processing complete!"
    echo
done

if [[ $consensus_built -eq 0 ]]; then
    echo "❌ Error: no consensus sequences were built (no classified reads found in $KRAKEN_RESULTS_DIR for: $DATABASES)"
    exit 1
fi

export REPRESENTATIVE VSEARCH_SIMILARITY KEEP_INTERMEDIATES
bash "$SCRIPT_DIR/write_run_info.sh" "$OUTPUT_DIR" "03_consensus" || true

### ── FINAL SUMMARY & NEXT STEPS ────────────────────────────────────────
echo "CLUSTERING WITH ABUNDANCE TRACKING COMPLETE"
echo "════════════════════════════════════════════════════════════════════════"
echo "Processed databases: $DATABASES"
echo
echo "ABUNDANCE TRACKING FILES:"
echo "   • Individual summaries: $ABUNDANCE_DIR/*/abundance_summary.txt"
echo
echo "Output structure EXACTLY MATCHES original 03 (04→05 compatible):"
for DATABASE in $DATABASES; do
    if [[ -d "$VSEARCH_DIR/$DATABASE" ]]; then
        echo "   • $DATABASE results: $VSEARCH_DIR/$DATABASE/*_${DATABASE}_vsearch_consensus.fasta"
    fi
done
echo
echo "Key improvement: Abundance preserved with --sizeout flag!"
echo
echo "Next step (guaranteed compatible with scripts 04→05):"
if [[ "$OUTPUT_DIR" == *"ont_native"* ]]; then
    echo " bash scripts/04_denoise.sh $OUTPUT_DIR results/ont_native_04_denoise"
elif [[ "$OUTPUT_DIR" == *"custom_cci"* ]]; then
    echo " bash scripts/04_denoise.sh $OUTPUT_DIR results/custom_cci_04_denoise"
else
    echo " bash scripts/04_denoise.sh $OUTPUT_DIR results/04_denoise"
fi