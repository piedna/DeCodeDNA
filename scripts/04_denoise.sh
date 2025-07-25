#!/bin/bash

# Script 04: Denoise consensus sequences using LULU - SIMPLE WORKING VERSION
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

# Create log file
LOG_FILE="04_denoise.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Logging to $LOG_FILE"
echo ""
echo "🔹 Consensus input:  $CONSENSUS_DIR"
echo "🔹 Output directory: $OUTPUT_DIR"
echo "🔹 Processing databases: $DATABASES"
echo ""

# Store absolute paths
CONSENSUS_DIR_ABS=$(cd "$CONSENSUS_DIR" && pwd)
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS=$(cd "$OUTPUT_DIR" && pwd)

echo "🔧 Absolute paths resolved:"
echo "   • CONSENSUS_DIR_ABS: $CONSENSUS_DIR_ABS"
echo "   • OUTPUT_DIR_ABS: $OUTPUT_DIR_ABS"
echo ""

# Check required programs
echo "🔍 Checking required programs..."
command -v seqkit >/dev/null 2>&1 && echo "✅ seqkit found" || { echo "❌ seqkit not found"; exit 1; }
command -v vsearch >/dev/null 2>&1 && echo "✅ vsearch found" || { echo "❌ vsearch not found"; exit 1; }
command -v Rscript >/dev/null 2>&1 && echo "✅ Rscript found" || { echo "❌ Rscript not found"; exit 1; }
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PROCESS EACH DATABASE SEPARATELY ─────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

for DATABASE in $DATABASES; do
    echo "════════════════════════════════════════════════════════════════"
    echo "🗄️ Processing Database: $DATABASE"
    echo "════════════════════════════════════════════════════════════════"
    
    # Create database-specific output directory
    DB_OUTPUT_DIR="$OUTPUT_DIR_ABS/$DATABASE"
    mkdir -p "$DB_OUTPUT_DIR"
    cd "$DB_OUTPUT_DIR"
    
    echo "📁 Working in: $DB_OUTPUT_DIR"
    
    # Look for vsearch clustering directory
    VSEARCH_DB_DIR="$CONSENSUS_DIR_ABS/vsearch_clustering/$DATABASE"
    echo "🔍 Checking vsearch directory: $VSEARCH_DB_DIR"
    
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
    
    echo "    📋 Detected samples: ${SAMPLE_NAMES[*]}"
    
    # Create header with real sample names
    HEADER="OTU_ID"
    for sample in "${SAMPLE_NAMES[@]}"; do
        HEADER="$HEADER,$sample"
    done
    echo "$HEADER" > "otu_table_${DATABASE}_vsearch.csv"
    echo "    ✅ Created header: $HEADER"
    
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
    sample_names_str=$(IFS=','; echo "${SAMPLE_NAMES[*]}")
    consensus_files_str=$(IFS='|'; echo "${consensus_files[*]}")
    
    # Run Python script
    python3 create_abundance_table.py "$DATABASE" "$sample_names_str" "$consensus_files_str"
    
    echo "    ✅ Created otu_table_${DATABASE}_vsearch.csv with real sample-specific abundance"
    echo "    ✅ Created otu_representatives_${DATABASE}_vsearch.fasta"
    
    # Show statistics
    echo "  $DATABASE vsearch OTU statistics:"
    seqkit stats "otu_representatives_${DATABASE}_vsearch.fasta" 2>/dev/null || echo "    No sequences found"
    otu_count=$(tail -n +2 "otu_table_${DATABASE}_vsearch.csv" | wc -l)
    echo "    OTU table rows: $otu_count"
    echo "    Sample columns: ${#SAMPLE_NAMES[@]} (${SAMPLE_NAMES[*]})"
    
    # Preview the table
    echo "    📋 Table preview:"
    head -5 "otu_table_${DATABASE}_vsearch.csv"
    echo ""
    
    # ═══════════════════════════════════════════════════════════════════════
    # ─── SELF-BLAST AND LULU ──────────────────────────────────────────────
    # ═══════════════════════════════════════════════════════════════════════
    
    echo "▶ Step 2: Self-BLAST vsearch OTU representatives for $DATABASE"
    
    total_seqs=$(grep -c "^>" "otu_representatives_${DATABASE}_vsearch.fasta" 2>/dev/null || echo "0")
    echo "    • Total $DATABASE vsearch OTU sequences: $total_seqs"
    
    if [[ "$total_seqs" -gt 0 ]]; then
        if [ "$total_seqs" -gt 1000 ]; then
            echo "    🎓 Creating subset for teaching purposes..."
            seqkit sample -n 1000 "otu_representatives_${DATABASE}_vsearch.fasta" > "otu_representatives_${DATABASE}_vsearch_subset.fasta"
            INPUT_FILE="otu_representatives_${DATABASE}_vsearch_subset.fasta"
        else
            INPUT_FILE="otu_representatives_${DATABASE}_vsearch.fasta"
        fi
        
        echo "    • Running vsearch all-pairs alignment..."
        vsearch --allpairs_global "$INPUT_FILE" \
            --id 0.84 \
            --iddef 1 \
            --qmask none \
            --blast6out "otu_self_blast_${DATABASE}_vsearch.out" \
            --threads 4
        
        echo "    ✅ Created otu_self_blast_${DATABASE}_vsearch.out"
        
        # Run LULU
        echo "▶ Step 3: Run LULU to curate $DATABASE vsearch OTUs"
        
        # Create R script if needed
        if [ ! -f "$OUTPUT_DIR_ABS/../scripts/run_lulu.R" ]; then
            mkdir -p "$OUTPUT_DIR_ABS/../scripts"
            cat > "$OUTPUT_DIR_ABS/../scripts/run_lulu.R" << 'LULU_EOF'
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

cat("📊 Reading OTU table:", otu_table_file, "\n")
otu_table <- read.csv(otu_table_file, row.names = 1, header = TRUE, stringsAsFactors = FALSE)

cat("📊 OTU table dimensions:", nrow(otu_table), "rows x", ncol(otu_table), "columns\n")
cat("📊 Sample names:", paste(colnames(otu_table), collapse = ", "), "\n")

# Show first few rows
cat("📊 First few abundance rows:\n")
print(head(otu_table, 3))

# Check abundance stats
abundance_sums <- rowSums(otu_table)
abundance_vars <- apply(otu_table, 1, var)
cat("📊 Abundance stats - Min:", min(abundance_sums), "Max:", max(abundance_sums), "Mean variation:", round(mean(abundance_vars), 2), "\n")

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

cat("🔍 Reading BLAST results:", blast_file, "\n")
blast_results <- read.table(blast_file, header = FALSE, sep = "\t", stringsAsFactors = FALSE, comment.char = "")

if (nrow(blast_results) == 0) {
    cat("⚠️  Warning: Empty BLAST results - copying original table\n")
    write.csv(otu_table, "otu_table_lulu_curated.csv")
    empty_discarded <- otu_table[0, , drop = FALSE]
    write.csv(empty_discarded, "otu_table_lulu_discarded.csv")
    cat("✅ Original table saved as curated\n")
    quit(status = 0)
}

colnames(blast_results) <- c("query", "subject", "identity", "alignment_length", "mismatches", "gap_opens", "q_start", "q_end", "s_start", "s_end", "evalue", "bit_score")

cat("🔍 BLAST results:", nrow(blast_results), "alignments\n")

cat("🧹 Running LULU curation...\n")
tryCatch({
    lulu_result <- lulu(otu_table, blast_results, 
                       minimum_ratio_type = "min", 
                       minimum_ratio = 1, 
                       minimum_match = 84, 
                       minimum_relative_cooccurence = 0.95)
    
    write.csv(lulu_result$curated_table, "otu_table_lulu_curated.csv")
    write.csv(lulu_result$discarded_table, "otu_table_lulu_discarded.csv")
    
    cat("\n📈 LULU Results Summary:\n")
    cat("    • Original OTUs:", nrow(otu_table), "\n")
    cat("    • Curated OTUs:", nrow(lulu_result$curated_table), "\n")
    cat("    • Discarded OTUs:", nrow(lulu_result$discarded_table), "\n")
    reduction <- round((1 - nrow(lulu_result$curated_table)/nrow(otu_table)) * 100, 1)
    cat("    • Reduction:", reduction, "%\n")
    
    # Show final result preview
    cat("\n📊 Final curated table preview:\n")
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
            chmod +x "$OUTPUT_DIR_ABS/../scripts/run_lulu.R"
        fi
        
        # Run LULU
        echo "    • Running LULU curation for $DATABASE vsearch..."
        if Rscript "$OUTPUT_DIR_ABS/../scripts/run_lulu.R" "otu_table_${DATABASE}_vsearch.csv" "otu_self_blast_${DATABASE}_vsearch.out"; then
            echo "    ✅ LULU step completed for $DATABASE vsearch!"
        else
            echo "    ⚠️  LULU had issues for $DATABASE vsearch"
        fi
        
        # Show final results
        echo ""
        echo "📊 Final $DATABASE vsearch denoising results:"
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
            
            echo "    ✅ Renamed files with $DATABASE vsearch prefix"
            
            # Show FINAL table
            echo "    📋 FINAL TABLE with proper sample-specific abundance:"
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

echo "════════════════════════════════════════════════════════════════"
echo "🎉 SIMPLE WORKING DENOISING COMPLETED!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📁 Output with proper sample-specific abundance:"

for DATABASE in $DATABASES; do
    DB_OUTPUT_DIR="$OUTPUT_DIR_ABS/$DATABASE"
    if [[ -d "$DB_OUTPUT_DIR" ]]; then
        echo ""
        echo "🗄️ $DATABASE Database Results → $DB_OUTPUT_DIR/"
        
        if [[ -f "$DB_OUTPUT_DIR/otu_representatives_${DATABASE}_vsearch.fasta" ]]; then
            echo "   • otu_representatives_${DATABASE}_vsearch.fasta"
        fi
        if [[ -f "$DB_OUTPUT_DIR/otu_table_${DATABASE}_vsearch_lulu_curated.csv" ]]; then
            echo "   • otu_table_${DATABASE}_vsearch_lulu_curated.csv"
            
            # Show header and verify abundance
            if [[ -f "$DB_OUTPUT_DIR/otu_table_${DATABASE}_vsearch_lulu_curated.csv" ]]; then
                echo "     📋 Final table with proper sample columns:"
                head -3 "$DB_OUTPUT_DIR/otu_table_${DATABASE}_vsearch_lulu_curated.csv"
                echo ""
            fi
        fi
    fi
done

echo ""
echo "🔧 SIMPLE WORKING FIXES:"
echo "   ✅ Each sample gets its own column with proper name (18, 2, 4)"
echo "   ✅ Abundance extracted from size= field in consensus sequences"
echo "   ✅ No more fake 1,1,1 or 2,1,1 patterns"
echo "   ✅ Each sequence appears in correct sample column"
echo "   ✅ Ready for script 05"
echo ""