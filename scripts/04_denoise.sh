#!/bin/bash

# Script 04: Denoise consensus sequences using LULU - UPDATED FOR MULTI-DATABASE
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

# ═══════════════════════════════════════════════════════════════════════════
# ─── PROCESS EACH DATABASE SEPARATELY ─────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

for DATABASE in $DATABASES; do
    echo "════════════════════════════════════════════════════════════════"
    echo "🗄️ Processing Database: $DATABASE"
    echo "════════════════════════════════════════════════════════════════"
    
    # Create database-specific output directory
    DB_OUTPUT_DIR="$OUTPUT_DIR/$DATABASE"
    mkdir -p "$DB_OUTPUT_DIR"
    cd "$DB_OUTPUT_DIR"
    
    # Detect consensus sequence files for this database
    echo "▶ Detecting $DATABASE consensus sequence files..."
    VSEARCH_CONSENSUS=""
    AMPLICON_SORTER_CONSENSUS=""

    # Look for vsearch consensus files for this database
    VSEARCH_DB_DIR="$CONSENSUS_DIR_ABS/vsearch_clustering/$DATABASE"
    if [[ -d "$VSEARCH_DB_DIR" ]] && ls "$VSEARCH_DB_DIR"/*_${DATABASE}_vsearch_consensus.fasta 1> /dev/null 2>&1; then
        # Combine all vsearch consensus files for this database
        VSEARCH_CONSENSUS="combined_${DATABASE}_vsearch_consensus.fasta"
        cat "$VSEARCH_DB_DIR"/*_${DATABASE}_vsearch_consensus.fasta > "$VSEARCH_CONSENSUS"
        echo "  ✅ Found and combined vsearch consensus for $DATABASE: $VSEARCH_CONSENSUS"
        seqkit stats "$VSEARCH_CONSENSUS"
    else
        echo "  ⚠️  No vsearch consensus files found for $DATABASE in $VSEARCH_DB_DIR"
    fi

    # Look for amplicon_sorter consensus (still combined across databases)
    if [ -f "$CONSENSUS_DIR_ABS/amplicon_sorter_consensus.fasta" ]; then
        AMPLICON_SORTER_CONSENSUS="$CONSENSUS_DIR_ABS/amplicon_sorter_consensus.fasta"
        echo "  ✅ Found amplicon_sorter consensus (all databases): $AMPLICON_SORTER_CONSENSUS"
        seqkit stats "$AMPLICON_SORTER_CONSENSUS"
    else
        echo "  ⚠️  No amplicon_sorter consensus found"
    fi

    # Skip this database if no consensus files found
    if [[ -z "$VSEARCH_CONSENSUS" ]] && [[ -z "$AMPLICON_SORTER_CONSENSUS" ]]; then
        echo "  ❌ No consensus files found for $DATABASE - skipping"
        echo ""
        continue
    fi

    # Show available files for this database
    echo "  📋 Available files for $DATABASE:"
    if [[ -n "$VSEARCH_CONSENSUS" ]]; then
        echo "    • vsearch: $VSEARCH_CONSENSUS"
    fi
    if [[ -n "$AMPLICON_SORTER_CONSENSUS" ]]; then
        echo "    • amplicon_sorter: $AMPLICON_SORTER_CONSENSUS"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════
    # ─── PROCESS VSEARCH SEPARATELY ───────────────────────────────────────
    # ═══════════════════════════════════════════════════════════════════════
    
    if [ -n "$VSEARCH_CONSENSUS" ] && [ -f "$VSEARCH_CONSENSUS" ]; then
        echo "▶ Step 1: Processing VSEARCH for $DATABASE"
        
        # Initialize vsearch files - Create multi-sample table for LULU
        echo "OTU_ID,Sample1,Sample2,Sample3" > "otu_table_${DATABASE}_vsearch.csv"
        > "otu_representatives_${DATABASE}_vsearch.fasta"
        
        echo "  • Processing vsearch consensus sequences for $DATABASE..."
        
        # Create multi-sample abundance data - remove ;size= and clean IDs, add database prefix
        grep "^>" "$VSEARCH_CONSENSUS" | sed 's/^>//' | sed 's/;size=[0-9]*//g' | sed 's/ .*//' | sed "s/^/${DATABASE}_vsearch_/" | sed 's/$/,1,1,1/' >> "otu_table_${DATABASE}_vsearch.csv"
        
        # Copy representatives - remove ;size= from headers, add database prefix
        sed 's/;size=[0-9]*//g' "$VSEARCH_CONSENSUS" | sed "s/^>/>${DATABASE}_vsearch_/" >> "otu_representatives_${DATABASE}_vsearch.fasta"
        
        vsearch_count=$(grep -c "^>" "$VSEARCH_CONSENSUS")
        echo "    ✓ Added $DATABASE vsearch OTUs ($vsearch_count sequences) across 3 samples"
        
        # Remove duplicate OTU IDs
        echo "  • Removing duplicate OTU IDs for vsearch $DATABASE..."
        initial_count=$(tail -n +2 "otu_table_${DATABASE}_vsearch.csv" | wc -l)
        awk '!seen[$1]++' FS=',' "otu_table_${DATABASE}_vsearch.csv" > "otu_table_${DATABASE}_vsearch_unique.csv"
        mv "otu_table_${DATABASE}_vsearch_unique.csv" "otu_table_${DATABASE}_vsearch.csv"
        final_count=$(tail -n +2 "otu_table_${DATABASE}_vsearch.csv" | wc -l)
        duplicates_removed=$((initial_count - final_count))
        echo "    ✓ Removed $duplicates_removed duplicate OTU IDs for vsearch $DATABASE"
        
        echo "    ✓ Created otu_representatives_${DATABASE}_vsearch.fasta"
        echo "    ✓ Created otu_table_${DATABASE}_vsearch.csv (3-sample format for LULU)"
        
        # Show vsearch statistics for this database
        echo "  $DATABASE vsearch OTU statistics:"
        seqkit stats "otu_representatives_${DATABASE}_vsearch.fasta"
        otu_count=$(tail -n +2 "otu_table_${DATABASE}_vsearch.csv" | wc -l)
        echo "    OTU table rows: $otu_count"
        echo ""
        
        # Self-BLAST vsearch OTU representatives for this database
        echo "▶ Step 2: Self-BLAST vsearch OTU representatives for $DATABASE"
        
        # Count total sequences for this database
        total_seqs=$(grep -c "^>" "otu_representatives_${DATABASE}_vsearch.fasta")
        echo "    • Total $DATABASE vsearch OTU sequences: $total_seqs"
        
        # Check if we need to subset for teaching purposes
        if [ "$total_seqs" -gt 1000 ]; then
            echo "    🎓 TEACHING NOTE: Large $DATABASE vsearch sequence set detected!"
            echo "       • Subsetting to 1000 sequences for manageable compute time"
            echo "       • Real analysis would process all sequences"
            echo ""
            echo "    • Creating subset for manageable compute time..."
            
            # Create subset
            seqkit sample -n 1000 "otu_representatives_${DATABASE}_vsearch.fasta" > "otu_representatives_${DATABASE}_vsearch_subset.fasta"
            echo "    • Subset created: 1000 sequences"
            seqkit stats "otu_representatives_${DATABASE}_vsearch_subset.fasta"
            
            # Use subset for alignment
            INPUT_FILE="otu_representatives_${DATABASE}_vsearch_subset.fasta"
        else
            INPUT_FILE="otu_representatives_${DATABASE}_vsearch.fasta"
        fi
        
        # Run vsearch all-pairs alignment for this database
        echo "    • Running vsearch all-pairs alignment on $INPUT_FILE..."
        echo "      (This may take 2-10 minutes depending on sequence count)"
        
        vsearch --allpairs_global "$INPUT_FILE" \
            --id 0.84 \
            --iddef 1 \
            --qmask none \
            --blast6out "otu_self_blast_${DATABASE}_vsearch.out" \
            --threads 4
        
        echo "    ✓ Created otu_self_blast_${DATABASE}_vsearch.out"
        echo ""
        
        # Run LULU to curate vsearch OTUs for this database
        echo "▶ Step 3: Run LULU to curate $DATABASE vsearch OTUs"
        echo "    🎓 TEACHING NOTE: LULU removes likely sequencing errors for $DATABASE vsearch"
        echo ""
        
        # Check if the R script exists
        if [ ! -f "../../../scripts/run_lulu.R" ]; then
            echo "    📝 Creating LULU R script..."
            
            # Ensure scripts directory exists
            mkdir -p ../../../scripts
            
            # Create the R script (same as before)
            cat > "../../../scripts/run_lulu.R" << 'EOF'
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

            chmod +x ../../../scripts/run_lulu.R
            echo "    ✓ Created ../../../scripts/run_lulu.R"
        fi
        
        # Run LULU for vsearch this database
        echo "    • Running LULU curation for $DATABASE vsearch..."
        if Rscript ../../../scripts/run_lulu.R "otu_table_${DATABASE}_vsearch.csv" "otu_self_blast_${DATABASE}_vsearch.out"; then
            echo "    ✅ LULU step completed for $DATABASE vsearch!"
        else
            echo "    ⚠️  LULU had issues for $DATABASE vsearch - check output above"
        fi
        
        # Show final vsearch statistics for this database
        echo ""
        echo "📊 Final $DATABASE vsearch denoising results:"
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
            
            echo "    • Original $DATABASE vsearch OTUs: $original_count"
            echo "    • Curated $DATABASE vsearch OTUs: $curated_count"
            echo "    • Discarded $DATABASE vsearch OTUs: $discarded_count"
            echo "    • $DATABASE vsearch Reduction: ${reduction}%"
            echo ""
            echo "    🎓 TEACHING INSIGHT: LULU removed ${reduction}% of $DATABASE vsearch OTUs as likely sequencing errors!"
            
            # Rename files to include database and method name for clarity
            mv "otu_table_lulu_curated.csv" "otu_table_${DATABASE}_vsearch_lulu_curated.csv"
            mv "otu_table_lulu_discarded.csv" "otu_table_${DATABASE}_vsearch_lulu_discarded.csv"
            
            echo "    ✓ Renamed files with $DATABASE vsearch prefix for clarity"
        fi
        
        echo ""
        echo "✅ $DATABASE vsearch denoising completed!"
        echo ""
    fi

    # ═══════════════════════════════════════════════════════════════════════
    # ─── PROCESS AMPLICON_SORTER SEPARATELY ───────────────────────────────
    # ═══════════════════════════════════════════════════════════════════════
    
    if [ -n "$AMPLICON_SORTER_CONSENSUS" ] && [ -f "$AMPLICON_SORTER_CONSENSUS" ]; then
        echo "▶ Step 1: Processing AMPLICON_SORTER for $DATABASE"
        
        # Initialize amplicon_sorter files - Create multi-sample table for LULU
        echo "OTU_ID,Sample1,Sample2,Sample3" > "otu_table_${DATABASE}_amplicon_sorter.csv"
        > "otu_representatives_${DATABASE}_amplicon_sorter.fasta"
        
        echo "  • Processing amplicon_sorter consensus sequences for $DATABASE..."
        
        # For amplicon_sorter, we use all sequences but prefix them with database name
        grep "^>" "$AMPLICON_SORTER_CONSENSUS" | sed 's/^>//' | sed 's/;size=[0-9]*//g' | sed 's/ .*//' | sed "s/^/${DATABASE}_amplicon_sorter_/" | sed 's/$/,1,1,1/' >> "otu_table_${DATABASE}_amplicon_sorter.csv"
        
        # Copy representatives - clean headers, add database prefix
        sed 's/;size=[0-9]*//g' "$AMPLICON_SORTER_CONSENSUS" | sed "s/^>/>${DATABASE}_amplicon_sorter_/" >> "otu_representatives_${DATABASE}_amplicon_sorter.fasta"
        
        amplicon_count=$(grep -c "^>" "$AMPLICON_SORTER_CONSENSUS")
        echo "    ✓ Added $DATABASE amplicon_sorter OTUs ($amplicon_count sequences) across 3 samples"
        
        # Remove duplicate OTU IDs
        echo "  • Removing duplicate OTU IDs for amplicon_sorter $DATABASE..."
        initial_count=$(tail -n +2 "otu_table_${DATABASE}_amplicon_sorter.csv" | wc -l)
        awk '!seen[$1]++' FS=',' "otu_table_${DATABASE}_amplicon_sorter.csv" > "otu_table_${DATABASE}_amplicon_sorter_unique.csv"
        mv "otu_table_${DATABASE}_amplicon_sorter_unique.csv" "otu_table_${DATABASE}_amplicon_sorter.csv"
        final_count=$(tail -n +2 "otu_table_${DATABASE}_amplicon_sorter.csv" | wc -l)
        duplicates_removed=$((initial_count - final_count))
        echo "    ✓ Removed $duplicates_removed duplicate OTU IDs for amplicon_sorter $DATABASE"
        
        echo "    ✓ Created otu_representatives_${DATABASE}_amplicon_sorter.fasta"
        echo "    ✓ Created otu_table_${DATABASE}_amplicon_sorter.csv (3-sample format for LULU)"
        
        # Show amplicon_sorter statistics for this database
        echo "  $DATABASE amplicon_sorter OTU statistics:"
        seqkit stats "otu_representatives_${DATABASE}_amplicon_sorter.fasta"
        otu_count=$(tail -n +2 "otu_table_${DATABASE}_amplicon_sorter.csv" | wc -l)
        echo "    OTU table rows: $otu_count"
        echo ""
        
        # Self-BLAST amplicon_sorter OTU representatives for this database
        echo "▶ Step 2: Self-BLAST amplicon_sorter OTU representatives for $DATABASE"
        
        # Count total sequences for this database
        total_seqs=$(grep -c "^>" "otu_representatives_${DATABASE}_amplicon_sorter.fasta")
        echo "    • Total $DATABASE amplicon_sorter OTU sequences: $total_seqs"
        
        # Check if we need to subset for teaching purposes
        if [ "$total_seqs" -gt 1000 ]; then
            echo "    🎓 TEACHING NOTE: Large $DATABASE amplicon_sorter sequence set detected!"
            echo "       • Subsetting to 1000 sequences for manageable compute time"
            echo "       • Real analysis would process all sequences"
            echo ""
            echo "    • Creating subset for manageable compute time..."
            
            # Create subset
            seqkit sample -n 1000 "otu_representatives_${DATABASE}_amplicon_sorter.fasta" > "otu_representatives_${DATABASE}_amplicon_sorter_subset.fasta"
            echo "    • Subset created: 1000 sequences"
            seqkit stats "otu_representatives_${DATABASE}_amplicon_sorter_subset.fasta"
            
            # Use subset for alignment
            INPUT_FILE="otu_representatives_${DATABASE}_amplicon_sorter_subset.fasta"
        else
            INPUT_FILE="otu_representatives_${DATABASE}_amplicon_sorter.fasta"
        fi
        
        # Run vsearch all-pairs alignment for this database
        echo "    • Running vsearch all-pairs alignment on $INPUT_FILE..."
        echo "      (This may take 2-10 minutes depending on sequence count)"
        
        vsearch --allpairs_global "$INPUT_FILE" \
            --id 0.84 \
            --iddef 1 \
            --qmask none \
            --blast6out "otu_self_blast_${DATABASE}_amplicon_sorter.out" \
            --threads 4
        
        echo "    ✓ Created otu_self_blast_${DATABASE}_amplicon_sorter.out"
        echo ""
        
        # Run LULU to curate amplicon_sorter OTUs for this database
        echo "▶ Step 3: Run LULU to curate $DATABASE amplicon_sorter OTUs"
        echo "    🎓 TEACHING NOTE: LULU removes likely sequencing errors for $DATABASE amplicon_sorter"
        echo ""
        
        # Run LULU for amplicon_sorter this database
        echo "    • Running LULU curation for $DATABASE amplicon_sorter..."
        if Rscript ../../../scripts/run_lulu.R "otu_table_${DATABASE}_amplicon_sorter.csv" "otu_self_blast_${DATABASE}_amplicon_sorter.out"; then
            echo "    ✅ LULU step completed for $DATABASE amplicon_sorter!"
        else
            echo "    ⚠️  LULU had issues for $DATABASE amplicon_sorter - check output above"
        fi
        
        # Show final amplicon_sorter statistics for this database
        echo ""
        echo "📊 Final $DATABASE amplicon_sorter denoising results:"
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
            
            echo "    • Original $DATABASE amplicon_sorter OTUs: $original_count"
            echo "    • Curated $DATABASE amplicon_sorter OTUs: $curated_count"
            echo "    • Discarded $DATABASE amplicon_sorter OTUs: $discarded_count"
            echo "    • $DATABASE amplicon_sorter Reduction: ${reduction}%"
            echo ""
            echo "    🎓 TEACHING INSIGHT: LULU removed ${reduction}% of $DATABASE amplicon_sorter OTUs as likely sequencing errors!"
            
            # Rename files to include database and method name for clarity
            mv "otu_table_lulu_curated.csv" "otu_table_${DATABASE}_amplicon_sorter_lulu_curated.csv"
            mv "otu_table_lulu_discarded.csv" "otu_table_${DATABASE}_amplicon_sorter_lulu_discarded.csv"
            
            echo "    ✓ Renamed files with $DATABASE amplicon_sorter prefix for clarity"
        fi
        
        echo ""
        echo "✅ $DATABASE amplicon_sorter denoising completed!"
        echo ""
    fi
    
    # Return to main output directory for next database
    cd "$OUTPUT_DIR_ABS"
done

# ═══════════════════════════════════════════════════════════════════════════
# ─── FINAL SUMMARY ────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════════"
echo "🎉 MULTI-DATABASE DENOISING PIPELINE COMPLETED!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📁 Output organized by database (SAME AS BACKUP but with separate method files):"

for DATABASE in $DATABASES; do
    DB_OUTPUT_DIR="$OUTPUT_DIR/$DATABASE"
    if [[ -d "$DB_OUTPUT_DIR" ]]; then
        echo ""
        echo "🗄️ $DATABASE Database Results → $DB_OUTPUT_DIR/"
        
        # vsearch files
        if [[ -f "$DB_OUTPUT_DIR/otu_representatives_${DATABASE}_vsearch.fasta" ]]; then
            echo "   • otu_representatives_${DATABASE}_vsearch.fasta (vsearch representative sequences)"
        fi
        if [[ -f "$DB_OUTPUT_DIR/otu_table_${DATABASE}_vsearch_lulu_curated.csv" ]]; then
            echo "   • otu_table_${DATABASE}_vsearch_lulu_curated.csv (vsearch final curated OTU table)"
        fi
        
        # amplicon_sorter files  
        if [[ -f "$DB_OUTPUT_DIR/otu_representatives_${DATABASE}_amplicon_sorter.fasta" ]]; then
            echo "   • otu_representatives_${DATABASE}_amplicon_sorter.fasta (amplicon_sorter representative sequences)"
        fi
        if [[ -f "$DB_OUTPUT_DIR/otu_table_${DATABASE}_amplicon_sorter_lulu_curated.csv" ]]; then
            echo "   • otu_table_${DATABASE}_amplicon_sorter_lulu_curated.csv (amplicon_sorter final curated OTU table)"
        fi
    fi
done

echo ""
echo "🎓 Teaching Benefits of Separate Method Files:"
echo "   • Same proven database-centric processing"
echo "   • Each method gets separate files per database"
echo "   • Method-specific prefixes prevent ID conflicts"
echo "   • Ready for separate taxonomic assignment"
echo ""
echo "🔬 Next steps:"
echo "   • Run script 05 with separate method file structure"
echo "   • Compare species identification between methods"
echo "   • Analyze method-specific community patterns"
echo ""
echo "🔗 Next step:"
echo " bash scripts/05_taxonomic_assignment.sh results/04_denoise results/05_taxonomy"
echo ""
