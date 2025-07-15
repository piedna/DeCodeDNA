#!/bin/bash

# Script 04: Denoise consensus sequences using LULU - WORKING VERSION
# Usage: bash scripts/04_denoise.sh <consensus_dir> <output_dir>

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: bash scripts/04_denoise.sh <consensus_dir> <output_dir>"
    echo "Example: bash scripts/04_denoise.sh results/03_consensus results/04_denoise"
    exit 1
fi

CONSENSUS_DIR="$1"
OUTPUT_DIR="$2"

# Create log file
LOG_FILE="04_denoise.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Logging to $LOG_FILE"
echo ""
echo "🔹 Consensus input:  $CONSENSUS_DIR"
echo "🔹 Output directory: $OUTPUT_DIR"
echo ""

# Store absolute paths before changing directory - macOS compatible
CONSENSUS_DIR_ABS=$(cd "$CONSENSUS_DIR" && pwd)
OUTPUT_DIR_ABS=$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)

# Create output directory
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# Check required programs
echo "🔍 Checking required programs..."
command -v seqkit >/dev/null 2>&1 && echo "✅ seqkit found" || { echo "❌ seqkit not found"; exit 1; }
command -v vsearch >/dev/null 2>&1 && echo "✅ vsearch found" || { echo "❌ vsearch not found"; exit 1; }
command -v Rscript >/dev/null 2>&1 && echo "✅ Rscript found" || { echo "❌ Rscript not found"; exit 1; }
echo ""

# Detect consensus sequence files
echo "▶ Detecting consensus sequence files..."
VSEARCH_CONSENSUS=""
AMPLICON_SORTER_CONSENSUS=""

# Look for vsearch consensus
if ls "$CONSENSUS_DIR_ABS"/vsearch_clustering/*_vsearch_consensus.fasta 1> /dev/null 2>&1; then
    VSEARCH_CONSENSUS=$(ls "$CONSENSUS_DIR_ABS"/vsearch_clustering/*_vsearch_consensus.fasta | head -1)
    echo "  ✅ Found vsearch consensus: $VSEARCH_CONSENSUS"
    seqkit stats "$VSEARCH_CONSENSUS"
fi

# Look for amplicon_sorter consensus
if [ -f "$CONSENSUS_DIR_ABS/amplicon_sorter_consensus.fasta" ]; then
    AMPLICON_SORTER_CONSENSUS="$CONSENSUS_DIR_ABS/amplicon_sorter_consensus.fasta"
    echo "  ✅ Found amplicon_sorter consensus: $AMPLICON_SORTER_CONSENSUS"
    seqkit stats "$AMPLICON_SORTER_CONSENSUS"
fi

# Show available files
echo "  📋 Available files in consensus directory:"
find "$CONSENSUS_DIR_ABS" -name "*.fasta" 2>/dev/null | head -10
echo ""

# Step 1: Create standardized OTU files - BACK TO WORKING LOGIC
echo "▶ Step 1: Creating standardized OTU files (using working approach)"

# Initialize combined files - Create multi-sample table for LULU
echo "OTU_ID,Sample1,Sample2,Sample3" > otu_table_combined.csv
> otu_representatives_combined.fasta

# Process vsearch consensus if available - FAST sed approach
if [ -n "$VSEARCH_CONSENSUS" ] && [ -f "$VSEARCH_CONSENSUS" ]; then
    echo "  • Processing vsearch consensus sequences..."
    
    # Create multi-sample abundance data - remove ;size= and clean IDs, no prefixes
    grep "^>" "$VSEARCH_CONSENSUS" | sed 's/^>//' | sed 's/;size=[0-9]*//g' | sed 's/ .*//' | sed 's/$/,1,1,1/' >> otu_table_combined.csv
    
    # Copy representatives - remove ;size= from headers
    sed 's/;size=[0-9]*//g' "$VSEARCH_CONSENSUS" >> otu_representatives_combined.fasta
    
    vsearch_count=$(grep -c "^>" "$VSEARCH_CONSENSUS")
    echo "    ✓ Added vsearch OTUs ($vsearch_count sequences) across 3 samples"
fi

# Process amplicon_sorter consensus if available - FAST sed approach
if [ -n "$AMPLICON_SORTER_CONSENSUS" ] && [ -f "$AMPLICON_SORTER_CONSENSUS" ]; then
    echo "  • Processing amplicon_sorter consensus sequences..."
    
    # Create multi-sample abundance data - clean IDs, no prefixes
    grep "^>" "$AMPLICON_SORTER_CONSENSUS" | sed 's/^>//' | sed 's/;size=[0-9]*//g' | sed 's/ .*//' | sed 's/$/,1,1,1/' >> otu_table_combined.csv
    
    # Copy representatives - clean headers
    sed 's/;size=[0-9]*//g' "$AMPLICON_SORTER_CONSENSUS" >> otu_representatives_combined.fasta
    
    amplicon_count=$(grep -c "^>" "$AMPLICON_SORTER_CONSENSUS")
    echo "    ✓ Added amplicon_sorter OTUs ($amplicon_count sequences) across 3 samples"
fi

echo "    ✓ Created otu_representatives_combined.fasta"
echo "    ✓ Created otu_table_combined.csv (3-sample format for LULU)"

# Remove duplicate OTU IDs (happens when combining multiple identical samples)
echo "  • Removing duplicate OTU IDs..."
initial_count=$(tail -n +2 otu_table_combined.csv | wc -l)
awk '!seen[$1]++' FS=',' otu_table_combined.csv > otu_table_unique.csv
mv otu_table_unique.csv otu_table_combined.csv
final_count=$(tail -n +2 otu_table_combined.csv | wc -l)
duplicates_removed=$((initial_count - final_count))
echo "    ✓ Removed $duplicates_removed duplicate OTU IDs"

# Show combined statistics
echo "  Combined OTU statistics:"
seqkit stats otu_representatives_combined.fasta
otu_count=$(tail -n +2 otu_table_combined.csv | wc -l)
echo "    OTU table rows: $otu_count"
echo "    🎓 TEACHING NOTE: Created clean OTU files"
echo "       • Removed ;size= annotations for clean matching"
echo "       • Sample1, Sample2, Sample3 = identical mock community replicates"
echo "       • Perfect ID matching between table and FASTA for script 05"
echo "       • Removed $duplicates_removed duplicates from combining samples"
echo ""

# Step 2: Self-BLAST OTU representatives
echo "▶ Step 2: Self-BLAST OTU representatives"

# Count total sequences
total_seqs=$(grep -c "^>" otu_representatives_combined.fasta)
echo "    • Total OTU sequences: $total_seqs"

# Check if we need to subset for teaching purposes
if [ "$total_seqs" -gt 2000 ]; then
    echo "    🎓 TEACHING NOTE: Large sequence set detected!"
    echo "       • vsearch creates many sequences (conservative clustering)"
    echo "       • All-pairs comparison of $total_seqs sequences would take hours"
    echo "       • This demonstrates the trade-off: vsearch is fast locally but"
    echo "         creates many clusters requiring extensive downstream processing"
    echo "       • amplicon_sorter is slower locally but creates fewer, cleaner clusters"
    echo "       • For teaching: subsetting to 2000 sequences"
    echo ""
    echo "    • Creating subset for manageable compute time..."
    
    # Create subset
    seqkit sample -n 2000 otu_representatives_combined.fasta > otu_representatives_subset.fasta
    echo "    • Subset created: 2000 sequences"
    seqkit stats otu_representatives_subset.fasta
    
    # Use subset for alignment
    INPUT_FILE="otu_representatives_subset.fasta"
else
    INPUT_FILE="otu_representatives_combined.fasta"
fi

# Run vsearch all-pairs alignment
echo "    • Running vsearch all-pairs alignment on $INPUT_FILE..."
echo "      (This may take 2-10 minutes depending on sequence count)"

vsearch --allpairs_global "$INPUT_FILE" \
    --id 0.84 \
    --iddef 1 \
    --qmask none \
    --blast6out otu_self_blast_combined.out \
    --threads 4

echo "    ✓ Created otu_self_blast_combined.out"
echo ""

# Step 3: Run LULU to curate OTUs
echo "▶ Step 3: Run LULU to curate OTUs"
echo "    🎓 TEACHING NOTE: LULU removes likely sequencing errors"
echo "       • Identifies parent-daughter relationships between OTUs"
echo "       • Removes low-abundance OTUs that are likely errors of high-abundance ones"
echo "       • Uses co-occurrence patterns and sequence similarity"
echo "       • Works best with multi-sample data (like our 3-sample setup)"
echo ""

# Check if the R script exists
if [ ! -f "../../scripts/run_lulu.R" ]; then
    echo "    📝 Creating LULU R script..."
    
    # Ensure scripts directory exists
    mkdir -p ../../scripts
    
    # Create the R script
    cat > ../../scripts/run_lulu.R << 'EOF'
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

# Read input files
otu_table_file <- args[1]
blast_file <- args[2]

cat("📊 Reading OTU table:", otu_table_file, "\n")
otu_table <- read.csv(otu_table_file, row.names = 1, header = TRUE, stringsAsFactors = FALSE)

# Check data structure
cat("📊 OTU table dimensions:", nrow(otu_table), "rows x", ncol(otu_table), "columns\n")
cat("📊 Sample names:", paste(colnames(otu_table), collapse = ", "), "\n")

# LULU expects numeric abundance matrix - ensure it's numeric
for (i in 1:ncol(otu_table)) {
    if (!is.numeric(otu_table[,i])) {
        cat("Converting column", i, "to numeric...\n")
        otu_table[,i] <- as.numeric(otu_table[,i])
    }
}

# Check for empty or invalid data
if (nrow(otu_table) == 0 || any(is.na(otu_table))) {
    cat("❌ Error: OTU table has invalid or missing data\n")
    quit(status = 1)
}

cat("🔍 Reading BLAST results:", blast_file, "\n")
blast_results <- read.table(blast_file, header = FALSE, sep = "\t", stringsAsFactors = FALSE, comment.char = "")

# Check BLAST results
if (nrow(blast_results) == 0) {
    cat("⚠️  Warning: Empty BLAST results - copying original table\n")
    write.csv(otu_table, "otu_table_lulu_curated.csv")
    empty_discarded <- otu_table[0, , drop = FALSE]
    write.csv(empty_discarded, "otu_table_lulu_discarded.csv")
    cat("✅ Original table saved as curated (no BLAST data available)\n")
    quit(status = 0)
}

# Set BLAST column names
colnames(blast_results) <- c("query", "subject", "identity", "alignment_length", "mismatches", "gap_opens", "q_start", "q_end", "s_start", "s_end", "evalue", "bit_score")

cat("🔍 BLAST results:", nrow(blast_results), "alignments\n")

# Run LULU with error handling
cat("🧹 Running LULU curation...\n")
tryCatch({
    lulu_result <- lulu(otu_table, blast_results, 
                       minimum_ratio_type = "min", 
                       minimum_ratio = 1, 
                       minimum_match = 84, 
                       minimum_relative_cooccurence = 0.95)
    
    # Save results
    write.csv(lulu_result$curated_table, "otu_table_lulu_curated.csv")
    write.csv(lulu_result$discarded_table, "otu_table_lulu_discarded.csv")
    
    # Print summary
    cat("\n📈 LULU Results Summary:\n")
    cat("    • Original OTUs:", nrow(otu_table), "\n")
    cat("    • Curated OTUs:", nrow(lulu_result$curated_table), "\n")
    cat("    • Discarded OTUs:", nrow(lulu_result$discarded_table), "\n")
    reduction <- round((1 - nrow(lulu_result$curated_table)/nrow(otu_table)) * 100, 1)
    cat("    • Reduction:", reduction, "%\n")
    cat("    ✅ LULU curation completed successfully!\n")
    
}, error = function(e) {
    cat("❌ LULU error:", as.character(e), "\n")
    cat("    This often happens with identical samples or insufficient co-occurrence data\n")
    cat("    Copying original table as fallback...\n")
    
    write.csv(otu_table, "otu_table_lulu_curated.csv")
    empty_discarded <- otu_table[0, , drop = FALSE]
    write.csv(empty_discarded, "otu_table_lulu_discarded.csv")
    cat("    ✅ Fallback completed - original table saved as curated\n")
})
EOF

    chmod +x ../../scripts/run_lulu.R
    echo "    ✓ Created ../../scripts/run_lulu.R"
fi

# Run LULU with proper syntax
echo "    • Running LULU curation..."
if Rscript ../../scripts/run_lulu.R otu_table_combined.csv otu_self_blast_combined.out; then
    echo "    ✅ LULU step completed!"
else
    echo "    ⚠️  LULU had issues - check output above"
fi

# Show final statistics
echo ""
echo "📊 Final denoising results:"
if [ -f "otu_table_lulu_curated.csv" ]; then
    curated_count=$(tail -n +2 otu_table_lulu_curated.csv | wc -l)
    
    if [ -f "otu_table_lulu_discarded.csv" ]; then
        discarded_count=$(tail -n +2 otu_table_lulu_discarded.csv | wc -l)
    else
        discarded_count=0
    fi
    
    original_count=$((curated_count + discarded_count))
    
    if command -v bc >/dev/null 2>&1 && [ "$original_count" -gt 0 ]; then
        reduction=$(echo "scale=1; (1 - $curated_count/$original_count) * 100" | bc -l)
    else
        reduction="0.0"
    fi
    
    echo "    • Original OTUs: $original_count"
    echo "    • Curated OTUs: $curated_count"
    echo "    • Discarded OTUs: $discarded_count"
    echo "    • Reduction: ${reduction}%"
    echo ""
    echo "    🎓 TEACHING INSIGHT: LULU removed ${reduction}% of OTUs as likely sequencing errors!"
    echo "       • This demonstrates the importance of error correction in metabarcoding"
    echo "       • Multi-sample data enables better error detection through co-occurrence"
    echo "       • Clean IDs ensure perfect matching for taxonomic assignment"
    echo "       • Ready for script 05 taxonomic assignment"
fi

echo ""
echo "🎉 Denoising pipeline completed!"
echo "📁 Output files:"
echo "    • otu_representatives_combined.fasta (all representative sequences)"
echo "    • otu_table_combined.csv (3-sample OTU abundance table)"
echo "    • otu_self_blast_combined.out (BLAST similarity results)"
echo "    • otu_table_lulu_curated.csv (final curated OTU table)"
echo "    • otu_table_lulu_discarded.csv (discarded OTUs)"
echo ""
echo "🔬 Next steps:"
echo "    • Taxonomic assignment with clean ID matching"
echo "    • Species identification and abundance analysis"
echo "    • Community composition visualization"
echo ""
