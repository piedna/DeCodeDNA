#!/bin/bash

# Script 04: Denoise consensus sequences using LULU 
# Usage: bash scripts/04_denoise.sh <consensus_dir> <output_dir>

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: bash scripts/04_denoise.sh <consensus_dir> <output_dir>"
    echo "Example: bash scripts/04_denoise.sh results/03_consensus results/04_denoise"
    exit 1
fi

CONSENSUS_DIR="$1"
OUTPUT_DIR="$2"

# Which databases to process
DATABASES="${DATABASES:-12s coi mitofish}"

# Create log file inside the output directory
mkdir -p "$OUTPUT_DIR"
LOG_FILE="$OUTPUT_DIR/04_denoise.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Threads ("auto" by default: all cores but one, see resources.sh)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resources.sh"
# How OTUs are built from the per-sample clusters made in step 03:
#   shared     (default) pool every sample's clusters, cluster them once, then count each sample's
#              reads against the shared OTUs. One OTU = the same sequence group in every sample.
#   per_sample (old behaviour, v0.1) every unique per-sample cluster sequence becomes its own OTU.
OTU_MODE="${OTU_MODE:-shared}"
OTU_SIMILARITY="${OTU_SIMILARITY:-${VSEARCH_SIMILARITY:-0.97}}"
# Drop OTUs with fewer reads than this across all samples (0 = keep everything)
MIN_OTU_READS="${MIN_OTU_READS:-10}"
# LULU input cap: 0 = use all OTUs (default). Set e.g. 1000 for a fast classroom run.
LULU_MAX_OTUS="${LULU_MAX_OTUS:-0}"
# Minimum % identity for LULU to treat an OTU as an error copy of a more abundant co-occurring OTU.
# 97 (default) merges only near-identical OTUs. LULU's own default is 84; with the cleaner consensus
# sequences from step 03 that also merged distinct, co-occurring species in our tests (FHL MFU subset:
# 589 of 850 OTUs merged and 32 low-read taxa lost at 84, against 2 OTUs merged at 97).
export LULU_MIN_MATCH="${LULU_MIN_MATCH:-97}"

echo "Logging to $LOG_FILE"
echo ""
echo " Consensus input:  $CONSENSUS_DIR"
echo " Output directory: $OUTPUT_DIR"
echo " Processing databases: $DATABASES"
echo " OTU mode:         $OTU_MODE (similarity $OTU_SIMILARITY, min reads per OTU $MIN_OTU_READS)"
echo " LULU OTU cap:     $LULU_MAX_OTUS (0 = all OTUs), min. match $LULU_MIN_MATCH%"
echo ""
case "$OTU_MODE" in shared|per_sample) ;; *) echo "❌ OTU_MODE must be 'shared' or 'per_sample' (got '$OTU_MODE')"; exit 1;; esac

# Store absolute paths
CONSENSUS_DIR_ABS=$(cd "$CONSENSUS_DIR" && pwd)
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS=$(cd "$OUTPUT_DIR" && pwd)

echo " Absolute paths resolved:"
echo "   • CONSENSUS_DIR_ABS: $CONSENSUS_DIR_ABS"
echo "   • OUTPUT_DIR_ABS: $OUTPUT_DIR_ABS"
echo ""

# Check required programs
echo " Checking required programs..."
command -v seqkit >/dev/null 2>&1 && echo "✅ seqkit found" || { echo "❌ seqkit not found"; exit 1; }
command -v vsearch >/dev/null 2>&1 && echo "✅ vsearch found" || { echo "❌ vsearch not found"; exit 1; }
command -v Rscript >/dev/null 2>&1 && echo "✅ Rscript found" || { echo "❌ Rscript not found"; exit 1; }
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PROCESS EACH DATABASE SEPARATELY ─────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

LULU_SCRIPT="$OUTPUT_DIR_ABS/00_scripts/run_lulu.R"
curated_tables=0

for DATABASE in $DATABASES; do
    echo "════════════════════════════════════════════════════════════════"
    echo "️ Processing Database: $DATABASE"
    echo "════════════════════════════════════════════════════════════════"
    
    # Create database-specific output directory
    DB_OUTPUT_DIR="$OUTPUT_DIR_ABS/$DATABASE"
    mkdir -p "$DB_OUTPUT_DIR"
    cd "$DB_OUTPUT_DIR"
    
    echo " Working in: $DB_OUTPUT_DIR"
    
    # Look for vsearch clustering directory
    VSEARCH_DB_DIR="$CONSENSUS_DIR_ABS/vsearch_clustering/$DATABASE"
    echo " Checking vsearch directory: $VSEARCH_DB_DIR"
    
    if [[ ! -d "$VSEARCH_DB_DIR" ]]; then
        echo "  ❌ No vsearch clustering directory found for $DATABASE - skipping"
        echo ""
        continue
    fi

    # Find consensus files for this database
    shopt -s nullglob
    consensus_files=("$VSEARCH_DB_DIR"/*_${DATABASE}_vsearch_consensus.fasta)
    
    if [[ ${#consensus_files[@]} -eq 0 ]]; then
        echo "  ❌ No consensus files found for $DATABASE - skipping"
        echo ""
        continue
    fi
    
    echo "  ✅ Found ${#consensus_files[@]} consensus files for $DATABASE"
    
    # ═══════════════════════════════════════════════════════════════════════
    # ─── CREATE SIMPLE ABUNDANCE TABLE ───────────────────────────────────
    # ═══════════════════════════════════════════════════════════════════════
    
    echo "▶ Step 1: Creating abundance table for $DATABASE with individual sample columns"
    
    # Get sample names from consensus files
    SAMPLE_NAMES=()
    for consensus_file in "${consensus_files[@]}"; do
        sample_name=$(basename "$consensus_file")
        sample_name=$(echo "$sample_name" | sed 's/_all_.*$//')
        SAMPLE_NAMES+=("$sample_name")
    done
    
    echo "    Detected samples: ${SAMPLE_NAMES[*]}"
    
    # Create header with real sample names
    HEADER="OTU_ID"
    for sample in "${SAMPLE_NAMES[@]}"; do
        HEADER="$HEADER,$sample"
    done
    echo "$HEADER" > "otu_table_${DATABASE}_vsearch.csv"
    echo "    ✅ Created header: $HEADER"
    
    sample_names_str=$(IFS=','; echo "${SAMPLE_NAMES[*]}")

    if [[ "$OTU_MODE" == "shared" ]]; then
        # ── Shared OTUs across samples ───────────────────────────────────
        # 1. pool every sample's clusters, keeping their read counts (size=) and sample name
        POOLED="pooled_${DATABASE}_sample_clusters.fasta"
        > "$POOLED"
        for idx in "${!consensus_files[@]}"; do
            awk -v s="${SAMPLE_NAMES[$idx]}" '
                /^>/ { n++; size = 1; if (match($0, /size=[0-9]+/)) size = substr($0, RSTART + 5, RLENGTH - 5)
                       print ">" s "." n ";size=" size ";sample=" s ";"; next }
                { print }' "${consensus_files[$idx]}" >> "$POOLED"
        done
        pooled_seqs=$(grep -c "^>" "$POOLED" || echo 0)
        pooled_reads=$(grep "^>" "$POOLED" | sed 's/.*;size=\([0-9]*\);.*/\1/' | awk '{s+=$1} END {print s+0}')
        echo "    Pooled $pooled_seqs per-sample clusters representing $pooled_reads reads"

        # 2. cluster once across all samples (largest clusters seed first)
        vsearch --cluster_size "$POOLED" \
            --id "$OTU_SIMILARITY" \
            --sizein --sizeout \
            --relabel OTU_ \
            --centroids "otu_centroids_${DATABASE}_all.fasta" \
            --threads "$THREADS" --quiet

        # 3. count each sample's reads against the shared OTUs
        vsearch --usearch_global "$POOLED" \
            --db "otu_centroids_${DATABASE}_all.fasta" \
            --id "$OTU_SIMILARITY" \
            --sizein \
            --otutabout "otutab_${DATABASE}_all.tsv" \
            --notmatched "unmatched_${DATABASE}.fasta" \
            --threads "$THREADS" --quiet

        # 4. drop OTUs below MIN_OTU_READS and write the files steps 04-05 use
        python3 - "$DATABASE" "$MIN_OTU_READS" "$sample_names_str" "$pooled_reads" << 'PYTHON_EOF'
import sys, csv
db, min_reads, samples, pooled_reads = sys.argv[1], int(sys.argv[2]), sys.argv[3].split(","), int(sys.argv[4])
rows = {}
with open(f"otutab_{db}_all.tsv") as fh:
    r = csv.reader(fh, delimiter="\t")
    head = next(r)[1:]
    for line in r:
        rows[line[0]] = dict(zip(head, map(int, line[1:])))
seqs, name = {}, None
with open(f"otu_centroids_{db}_all.fasta") as fh:
    for line in fh:
        line = line.strip()
        if line.startswith(">"):
            name = line[1:].split(";")[0]; seqs[name] = []
        elif name:
            seqs[name].append(line)
order = sorted(rows, key=lambda k: (-sum(rows[k].values()), int(k.split("_")[-1])))
kept = [k for k in order if sum(rows[k].values()) >= min_reads]
reads_all = sum(sum(v.values()) for v in rows.values())
reads_kept = sum(sum(rows[k].values()) for k in kept)
with open(f"otu_table_{db}_vsearch.csv", "w") as fh:
    fh.write("OTU_ID," + ",".join(samples) + "\n")
    for k in kept:
        fh.write(k + "," + ",".join(str(rows[k].get(s, 0)) for s in samples) + "\n")
for fn in (f"otu_representatives_{db}_vsearch.fasta", f"combined_{db}_vsearch_consensus.fasta"):
    with open(fn, "w") as fh:
        for k in kept:
            fh.write(f">{k}\n{''.join(seqs[k])}\n")
with open(f"otu_build_summary_{db}.tsv", "w") as fh:
    fh.write("step\totus\treads\n")
    fh.write(f"reads entering step 04 (from step 03 clusters)\t\t{pooled_reads}\n")
    fh.write(f"shared OTUs, all\t{len(rows)}\t{reads_all}\n")
    fh.write(f"shared OTUs with >= {min_reads} reads\t{len(kept)}\t{reads_kept}\n")
print(f"    {len(rows)} shared OTUs ({reads_all} reads); kept {len(kept)} with >= {min_reads} reads ({reads_kept} reads)")
if pooled_reads > reads_all:
    print(f"    {pooled_reads - reads_all} reads did not match any OTU at the chosen similarity (see unmatched_{db}.fasta)")
PYTHON_EOF
    else
        # ── Legacy route (v0.1): one OTU per unique per-sample cluster sequence ──
    # Combine all consensus sequences and create representatives
    COMBINED_CONSENSUS="combined_${DATABASE}_vsearch_consensus.fasta"
    > "$COMBINED_CONSENSUS"
    > "otu_representatives_${DATABASE}_vsearch.fasta"
    
    # Create Python script to handle abundance extraction properly
    cat > "create_abundance_table.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
import sys
import re
from collections import defaultdict

def process_consensus_files(consensus_files, sample_names, database):
    """Process consensus files and create abundance table"""
    
    print(f"Processing {len(consensus_files)} consensus files for {database}")
    print(f"Sample names: {sample_names}")
    
    # Store all sequences and their sample origins
    sequence_to_samples = defaultdict(list)
    all_sequences = []
    otu_counter = 1
    
    # Process each sample's consensus file
    for i, consensus_file in enumerate(consensus_files):
        sample_name = sample_names[i]
        print(f"Processing {sample_name}: {consensus_file}")
        
        with open(consensus_file, 'r') as f:
            current_seq = ""
            current_header = ""
            
            for line in f:
                line = line.strip()
                if line.startswith('>'):
                    # Process previous sequence
                    if current_seq:
                        # Extract abundance from header (size=X)
                        size_match = re.search(r';size=(\d+)', current_header)
                        abundance = int(size_match.group(1)) if size_match else 1
                        
                        # Store sequence and its abundance for this sample
                        sequence_to_samples[current_seq].append((sample_name, abundance))
                    
                    current_header = line
                    current_seq = ""
                else:
                    current_seq += line
            
            # Process last sequence
            if current_seq:
                size_match = re.search(r';size=(\d+)', current_header)
                abundance = int(size_match.group(1)) if size_match else 1
                sequence_to_samples[current_seq].append((sample_name, abundance))
    
    print(f"Found {len(sequence_to_samples)} unique sequences")
    
    # Create abundance matrix
    abundance_matrix = []
    otu_counter = 1
    
    for sequence, sample_abundances in sequence_to_samples.items():
        otu_id = f"OTU_{otu_counter}"
        
        # Initialize abundance for all samples to 0
        abundances = {sample: 0 for sample in sample_names}
        
        # Fill in actual abundances
        for sample_name, abundance in sample_abundances:
            abundances[sample_name] += abundance
        
        # Create row for OTU table
        row = [otu_id] + [str(abundances[sample]) for sample in sample_names]
        abundance_matrix.append(row)
        
        # Add to combined FASTA
        all_sequences.append((otu_id, sequence))
        
        otu_counter += 1
    
    return abundance_matrix, all_sequences

def write_files(abundance_matrix, all_sequences, sample_names, database):
    """Write OTU table and representatives files"""
    
    # Write OTU table
    otu_table_file = f"otu_table_{database}_vsearch.csv"
    with open(otu_table_file, 'a') as f:  # Append to existing header
        for row in abundance_matrix:
            f.write(','.join(row) + '\n')
    
    print(f"Created {otu_table_file} with {len(abundance_matrix)} OTUs")
    
    # Write representatives
    rep_file = f"otu_representatives_{database}_vsearch.fasta"
    combined_file = f"combined_{database}_vsearch_consensus.fasta"
    
    with open(rep_file, 'w') as rep_f, open(combined_file, 'w') as comb_f:
        for otu_id, sequence in all_sequences:
            rep_f.write(f">{otu_id}\n{sequence}\n")
            comb_f.write(f">{otu_id}\n{sequence}\n")
    
    print(f"Created {rep_file} and {combined_file}")
    
    # Show first few rows
    print(f"\nFirst few OTU abundance rows:")
    for i, row in enumerate(abundance_matrix[:3]):
        print(f"  {row}")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 create_abundance_table.py <database> <sample_names> <consensus_files>")
        sys.exit(1)
    
    database = sys.argv[1]
    sample_names = sys.argv[2].split(',')
    consensus_files = sys.argv[3].split('|')
    
    print(f"Creating abundance table for {database}")
    
    # Process files
    abundance_matrix, all_sequences = process_consensus_files(consensus_files, sample_names, database)
    
    # Write output files
    write_files(abundance_matrix, all_sequences, sample_names, database)
    
    print(f"Abundance table creation completed for {database}")
PYTHON_EOF
    
    # Prepare arguments for Python script
    consensus_files_str=$(IFS='|'; echo "${consensus_files[*]}")
    
    # Run Python script
    python3 create_abundance_table.py "$DATABASE" "$sample_names_str" "$consensus_files_str"
    fi
    
    echo "    ✅ Created otu_table_${DATABASE}_vsearch.csv with real sample-specific abundance"
    echo "    ✅ Created otu_representatives_${DATABASE}_vsearch.fasta"
    
    # Show statistics
    echo "  $DATABASE vsearch OTU statistics:"
    seqkit stats "otu_representatives_${DATABASE}_vsearch.fasta" 2>/dev/null || echo "    No sequences found"
    otu_count=$(tail -n +2 "otu_table_${DATABASE}_vsearch.csv" | wc -l)
    echo "    OTU table rows: $otu_count"
    echo "    Sample columns: ${#SAMPLE_NAMES[@]} (${SAMPLE_NAMES[*]})"
    
    # Preview the table
    echo "     Table preview:"
    head -5 "otu_table_${DATABASE}_vsearch.csv"
    echo ""
    
    # ═══════════════════════════════════════════════════════════════════════
    # ─── SELF-BLAST AND LULU ──────────────────────────────────────────────
    # ═══════════════════════════════════════════════════════════════════════
    
    echo "▶ Step 2: Self-BLAST vsearch OTU representatives for $DATABASE"
    
    total_seqs=$(grep -c "^>" "otu_representatives_${DATABASE}_vsearch.fasta" 2>/dev/null || echo "0")
    echo "    • Total $DATABASE vsearch OTU sequences: $total_seqs"
    
    if [[ "$total_seqs" -gt 0 ]]; then
        if [ "$LULU_MAX_OTUS" -gt 0 ] && [ "$total_seqs" -gt "$LULU_MAX_OTUS" ]; then
            echo "    Creating subset of $LULU_MAX_OTUS OTUs for teaching purposes (set LULU_MAX_OTUS=0 to use all)..."
            seqkit sample -n "$LULU_MAX_OTUS" "otu_representatives_${DATABASE}_vsearch.fasta" > "otu_representatives_${DATABASE}_vsearch_subset.fasta"
            INPUT_FILE="otu_representatives_${DATABASE}_vsearch_subset.fasta"
        else
            INPUT_FILE="otu_representatives_${DATABASE}_vsearch.fasta"
        fi
        
        echo "    • Matching OTUs against each other for LULU (vsearch --usearch_global --self)..."
        # Match list for LULU: every OTU against every other OTU, in both directions
        # (as recommended by the LULU authors). Columns: query, target, % identity.
        vsearch --usearch_global "$INPUT_FILE" \
            --db "$INPUT_FILE" \
            --self \
            --id 0.84 \
            --iddef 1 \
            --qmask none \
            --userout "otu_self_blast_${DATABASE}_vsearch.out" \
            --userfields query+target+id \
            --maxaccepts 0 \
            --query_cov 0.9 \
            --maxhits 10 \
            --threads "$THREADS"
        
        echo "    ✅ Created otu_self_blast_${DATABASE}_vsearch.out"
        
        # Run LULU
        echo "▶ Step 3: Run LULU to curate $DATABASE vsearch OTUs"
        
        # Create R script if needed
        # Always write a fresh copy, so a re-run into the same folder never uses an older version
        if true; then
            mkdir -p "$(dirname "$LULU_SCRIPT")"
            cat > "$LULU_SCRIPT" << 'LULU_EOF'
#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 2) {
    cat("Usage: Rscript run_lulu.R <otu_table.csv> <blast_results.out>\n")
    quit(status = 1)
}

# Load required libraries
suppressMessages({
    if (!require("lulu", quietly = TRUE)) {
        cat("Installing lulu package...\n")
        if (!require("devtools", quietly = TRUE)) {
            install.packages("devtools", repos = "https://cran.r-project.org")
        }
        library(devtools)
        install_github("tobiasgf/lulu")
        library(lulu)
    }
})

otu_table_file <- args[1]
blast_file <- args[2]

cat(" Reading OTU table:", otu_table_file, "\n")
otu_table <- read.csv(otu_table_file, row.names = 1, header = TRUE, stringsAsFactors = FALSE)

cat(" OTU table dimensions:", nrow(otu_table), "rows x", ncol(otu_table), "columns\n")
cat(" Sample names:", paste(colnames(otu_table), collapse = ", "), "\n")

# Show first few rows
cat(" First few abundance rows:\n")
print(head(otu_table, 3))

# Check abundance stats
abundance_sums <- rowSums(otu_table)
abundance_vars <- apply(otu_table, 1, var)
cat(" Abundance stats - Min:", min(abundance_sums), "Max:", max(abundance_sums), "Mean variation:", round(mean(abundance_vars), 2), "\n")

# Ensure numeric
for (i in 1:ncol(otu_table)) {
    if (!is.numeric(otu_table[,i])) {
        otu_table[,i] <- as.numeric(otu_table[,i])
    }
}

if (nrow(otu_table) == 0 || any(is.na(otu_table))) {
    cat("❌ Error: OTU table has invalid data\n")
    quit(status = 1)
}

cat(" Reading BLAST results:", blast_file, "\n")
blast_results <- read.table(blast_file, header = FALSE, sep = "\t", stringsAsFactors = FALSE, comment.char = "")

if (nrow(blast_results) == 0) {
    cat("⚠️  Warning: Empty BLAST results - copying original table\n")
    write.csv(otu_table, "otu_table_lulu_curated.csv")
    empty_discarded <- otu_table[0, , drop = FALSE]
    write.csv(empty_discarded, "otu_table_lulu_discarded.csv")
    cat("✅ Original table saved as curated\n")
    quit(status = 0)
}

# LULU needs three columns: query OTU, matched OTU, % identity
blast_results <- blast_results[, 1:3]
colnames(blast_results) <- c("query", "subject", "identity")

cat(" BLAST results:", nrow(blast_results), "alignments\n")

cat(" Running LULU curation...\n")
tryCatch({
    lulu_result <- lulu(otu_table, blast_results, 
                       minimum_ratio_type = "min", 
                       minimum_ratio = 1, 
                       minimum_match = as.numeric(Sys.getenv("LULU_MIN_MATCH", "97")), 
                       minimum_relative_cooccurence = 0.95)
    
    write.csv(lulu_result$curated_table, "otu_table_lulu_curated.csv")
    discarded_table <- otu_table[row.names(otu_table) %in% lulu_result$discarded_otus, , drop = FALSE]
    write.csv(discarded_table, "otu_table_lulu_discarded.csv")
    if (!is.null(lulu_result$otu_map)) write.csv(lulu_result$otu_map, "otu_lulu_map.csv")
    
    cat("\n LULU Results Summary:\n")
    cat("    • Original OTUs:", nrow(otu_table), "\n")
    cat("    • Curated OTUs:", nrow(lulu_result$curated_table), "\n")
    cat("    • Discarded OTUs:", length(lulu_result$discarded_otus), "\n")
    reduction <- round((1 - nrow(lulu_result$curated_table)/nrow(otu_table)) * 100, 1)
    cat("    • Reduction:", reduction, "%\n")
    
    # Show final result preview
    cat("\n Final curated table preview:\n")
    print(head(lulu_result$curated_table, 3))
    
    cat("    ✅ LULU curation completed!\n")
    
}, error = function(e) {
    cat("❌ LULU error:", as.character(e), "\n")
    cat("    Copying original table as fallback...\n")
    
    write.csv(otu_table, "otu_table_lulu_curated.csv")
    empty_discarded <- otu_table[0, , drop = FALSE]
    write.csv(empty_discarded, "otu_table_lulu_discarded.csv")
    cat("    ✅ Fallback completed\n")
})
LULU_EOF
            chmod +x "$LULU_SCRIPT"
        fi
        
        # Run LULU
        echo "    • Running LULU curation for $DATABASE vsearch..."
        if Rscript "$LULU_SCRIPT" "otu_table_${DATABASE}_vsearch.csv" "otu_self_blast_${DATABASE}_vsearch.out"; then
            echo "    ✅ LULU step completed for $DATABASE vsearch!"
        else
            echo "    ⚠️  LULU had issues for $DATABASE vsearch"
        fi
        
        # Show final results
        echo ""
        echo " Final $DATABASE vsearch denoising results:"
        if [ -f "otu_table_lulu_curated.csv" ]; then
            curated_count=$(tail -n +2 otu_table_lulu_curated.csv | wc -l)
            
            if [ -f "otu_table_lulu_discarded.csv" ]; then
                discarded_count=$(tail -n +2 otu_table_lulu_discarded.csv | wc -l)
            else
                discarded_count=0
            fi
            
            echo "    • Curated $DATABASE vsearch OTUs: $curated_count"
            echo "    • Discarded $DATABASE vsearch OTUs: $discarded_count"
            
            # Rename files
            mv "otu_table_lulu_curated.csv" "otu_table_${DATABASE}_vsearch_lulu_curated.csv"
            mv "otu_table_lulu_discarded.csv" "otu_table_${DATABASE}_vsearch_lulu_discarded.csv"
            
            curated_tables=$((curated_tables + 1))
            echo "    ✅ Renamed files with $DATABASE vsearch prefix"
            
            # Show FINAL table
            echo "     FINAL TABLE with proper sample-specific abundance:"
            head -5 "otu_table_${DATABASE}_vsearch_lulu_curated.csv"
        fi
    else
        echo "    ⚠️  No sequences found for $DATABASE vsearch - skipping BLAST and LULU"
    fi
    
    echo ""
    echo "✅ $DATABASE vsearch denoising completed!"
    echo ""
    
    # Return to main output directory
    cd "$OUTPUT_DIR_ABS"
done

# ═══════════════════════════════════════════════════════════════════════════
# ─── FINAL SUMMARY ────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

if [[ $curated_tables -eq 0 ]]; then
    echo "❌ Error: LULU produced no curated OTU tables (input: $CONSENSUS_DIR_ABS, databases: $DATABASES)"
    exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo " DENOISING COMPLETED!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo " Output with proper sample-specific abundance:"

for DATABASE in $DATABASES; do
    DB_OUTPUT_DIR="$OUTPUT_DIR_ABS/$DATABASE"
    if [[ -d "$DB_OUTPUT_DIR" ]]; then
        echo ""
        echo "️ $DATABASE Database Results → $DB_OUTPUT_DIR/"
        
        if [[ -f "$DB_OUTPUT_DIR/otu_representatives_${DATABASE}_vsearch.fasta" ]]; then
            echo "   • otu_representatives_${DATABASE}_vsearch.fasta"
        fi
        if [[ -f "$DB_OUTPUT_DIR/otu_table_${DATABASE}_vsearch_lulu_curated.csv" ]]; then
            echo "   • otu_table_${DATABASE}_vsearch_lulu_curated.csv"
            
            # Show header and verify abundance
            if [[ -f "$DB_OUTPUT_DIR/otu_table_${DATABASE}_vsearch_lulu_curated.csv" ]]; then
                echo "      Final table with proper sample columns:"
                head -3 "$DB_OUTPUT_DIR/otu_table_${DATABASE}_vsearch_lulu_curated.csv"
                echo ""
            fi
        fi
    fi
done


echo ""
echo " Next steps:"
echo "   • Run script 05 with separate method file structure"
echo "   • Compare species identification between methods"
echo "   • Analyze method-specific community patterns"
echo "   ✅ Ready for script 05"
echo ""
echo " Next step:"
# Detect workflow from OUTPUT_DIR path
if [[ "$OUTPUT_DIR_ABS" == *"ont_native"* ]]; then
  echo " bash scripts/05_taxonomic_assignment.sh $OUTPUT_DIR_ABS results/ont_native_05_taxonomy"
elif [[ "$OUTPUT_DIR_ABS" == *"custom_cci"* ]]; then
  echo " bash scripts/05_taxonomic_assignment.sh $OUTPUT_DIR_ABS results/custom_cci_05_taxonomy"
else
  echo " bash scripts/05_taxonomic_assignment.sh $OUTPUT_DIR_ABS results/05_taxonomy"
fi
echo ""

bash "$(dirname "${BASH_SOURCE[0]}")/write_run_info.sh" "$OUTPUT_DIR_ABS" "04_denoise" || true
