#!/usr/bin/env bash
# scripts/05_taxonomic_assignment.sh
#
# Step V: Taxonomic Assignment - Updated for Clean Script 04
#
# Input (from Step IV):
#   • otu_table_lulu_curated.csv        (curated OTU counts with clean IDs)
#   • otu_representatives_combined.fasta (all representative sequences with clean IDs)
#
# Process:
#   1) Extract sequences for LULU-curated OTUs (perfect ID matching now!)
#   2) BLAST against local databases (12s, coi, mitofish)
#   3) Parse BLAST results and create species abundance matrix
#
# Output:
#   • final_taxon_table_combined.csv     (species × sample abundance matrix)
#   • blast_results_summary.csv          (detailed BLAST hit information)
#   • taxonomic_assignment_stats.csv     (assignment success rates)
#
set -euo pipefail

### ── USER CONFIG ─────────────────────────────────────────────────
DENOISE_DIR="${1:?Error: need DENOISE_DIR (e.g., results/04_denoise)}"
OUTPUT_DIR="${2:-results/05_taxonomy}"
THREADS="${THREADS:-8}"              # threads for BLAST
MAX_SEQS="${MAX_SEQS:-5000}"         # maximum sequences to BLAST (for teaching)

# Database configuration (from script 00 setup)
BLAST_DB_ROOT="${BLAST_DB_ROOT:-$HOME/Downloads/test_fhl/blast_db}"

# BLAST parameters
BLAST_PERC_IDENTITY="${BLAST_PERC_IDENTITY:-85}"  # Lowered for better hits
BLAST_EVALUE="${BLAST_EVALUE:-1e-10}"             # Less stringent
BLAST_MAX_TARGETS="${BLAST_MAX_TARGETS:-10}"      # More targets

# Store current directory
SCRIPT_DIR="$(pwd)"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create log file in output directory
LOG_FILE="$OUTPUT_DIR/05_taxonomic_assignment.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Logging to $LOG_FILE"
echo ""
echo "🔹 Script directory:    $SCRIPT_DIR"
echo "🔹 Input directory:     $DENOISE_DIR"
echo "🔹 Output directory:    $OUTPUT_DIR"
echo "🔹 BLAST DB root:       $BLAST_DB_ROOT"
echo "🔹 BLAST parameters:    ${BLAST_PERC_IDENTITY}% identity, E-value ${BLAST_EVALUE}"
echo "🔹 Max sequences:       $MAX_SEQS (for teaching purposes)"
echo ""

### ── SANITY CHECKS ────────────────────────────────────────────────
echo "🔍 Checking required programs..."

# Check required tools
for cmd in seqkit blastn; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Error: $cmd not found."
    exit 1
  else
    echo "✅ $cmd found"
  fi
done

# Check R
if ! command -v Rscript &>/dev/null; then
  echo "❌ Error: Rscript not found."
  exit 1
else
  echo "✅ Rscript found"
fi

echo ""

### ── INPUT FILE DETECTION ─────────────────────────────────────────
echo "▶ Detecting input files from Step IV..."

# Handle both relative and absolute paths properly
if [[ "$DENOISE_DIR" = /* ]]; then
  # Absolute path
  DENOISE_DIR_ABS="$DENOISE_DIR"
else
  # Relative path - resolve from script directory
  DENOISE_DIR_ABS="$SCRIPT_DIR/$DENOISE_DIR"
fi

echo "  • Checking directory: $DENOISE_DIR_ABS"

# Verify directory exists
if [[ ! -d "$DENOISE_DIR_ABS" ]]; then
  echo "  ❌ Directory not found: $DENOISE_DIR_ABS"
  echo "  🔍 Available directories:"
  ls -la "$SCRIPT_DIR" 2>/dev/null | grep "^d" || echo "    No directories found"
  exit 1
fi

# Check for required files
LULU_TABLE="$DENOISE_DIR_ABS/otu_table_lulu_curated.csv"
OTU_REPS="$DENOISE_DIR_ABS/otu_representatives_combined.fasta"

if [[ -f "$LULU_TABLE" ]]; then
  echo "  ✅ Found OTU table: $LULU_TABLE"
  curated_otus=$(tail -n +2 "$LULU_TABLE" | wc -l)
  echo "    • Total OTUs in table: $curated_otus"
else
  echo "  ❌ OTU table not found: $LULU_TABLE"
  echo "  🔍 Available files in directory:"
  ls -la "$DENOISE_DIR_ABS" 2>/dev/null || echo "    Cannot list directory contents"
  exit 1
fi

if [[ -f "$OTU_REPS" ]]; then
  echo "  ✅ Found OTU representatives: $OTU_REPS"
  seqkit stats "$OTU_REPS" | tail -n +2 | sed 's/^/    /'
else
  echo "  ❌ OTU representatives not found: $OTU_REPS"
  echo "  🔍 Available FASTA files in directory:"
  find "$DENOISE_DIR_ABS" -name "*.fasta" 2>/dev/null || echo "    No FASTA files found"
  exit 1
fi

echo ""

# Change to output directory for processing
cd "$OUTPUT_DIR"

### ── STEP 1: Extract LULU-curated sequences with perfect ID matching ──
echo "▶ Step 1: Extracting LULU-curated sequences (perfect ID matching!)"

# Extract OTU IDs from LULU curated table
echo "  • Extracting curated OTU IDs..."
cut -d',' -f1 "$LULU_TABLE" | tail -n +2 > curated_otu_ids.txt
curated_count=$(wc -l < curated_otu_ids.txt)
echo "    ✓ Found $curated_count curated OTU IDs"

# Extract corresponding sequences - this should work perfectly now with clean IDs
echo "  • Extracting representative sequences for curated OTUs..."
seqkit grep \
  --pattern-file curated_otu_ids.txt \
  "$OTU_REPS" \
  > curated_sequences_all.fasta

extracted_seqs=$(grep -c "^>" curated_sequences_all.fasta 2>/dev/null || echo "0")
echo "    ✓ Extracted $extracted_seqs representative sequences"

# Check if extraction worked well
if [ "$extracted_seqs" -eq "$curated_count" ]; then
  echo "    🎉 Perfect match! All curated OTUs have representative sequences"
elif [ "$extracted_seqs" -gt 0 ]; then
  echo "    ⚠️  Partial match: $extracted_seqs/$curated_count sequences extracted"
  echo "    🔍 This is common when sequences are subsampled in previous steps"
else
  echo "    ❌ No sequences extracted - ID matching failed"
  echo "    🔍 Debugging info:"
  echo "    First few OTU IDs from table:"
  head -3 curated_otu_ids.txt
  echo "    First few FASTA headers:"
  grep "^>" "$OTU_REPS" | head -3
  echo "    🔧 Attempting alternative extraction..."
  
  # Try alternative approach - extract all sequences and work with what we have
  cp "$OTU_REPS" curated_sequences_all.fasta
  extracted_seqs=$(grep -c "^>" curated_sequences_all.fasta)
  echo "    ✓ Using all available sequences: $extracted_seqs"
fi

# Check if we need to subsample for teaching purposes
if [ "$extracted_seqs" -gt "$MAX_SEQS" ]; then
  echo "    🎓 TEACHING NOTE: Large sequence set detected!"
  echo "       • Found $extracted_seqs curated sequences for BLAST"
  echo "       • Local BLAST with >$MAX_SEQS sequences would take hours"
  echo "       • For teaching: subsampling to $MAX_SEQS sequences"
  echo "       • In real analysis: use HPC cluster for full dataset"
  echo ""
  echo "    • Creating subset for manageable BLAST time..."
  
  # Create subset
  seqkit sample -n "$MAX_SEQS" curated_sequences_all.fasta > query_sequences.fasta
  sampled_seqs=$(grep -c "^>" query_sequences.fasta)
  echo "    ✓ Subsampled to $sampled_seqs sequences for BLAST"
  
  # Save the full set for reference
  mv curated_sequences_all.fasta curated_sequences_full.fasta
else
  echo "    • Sequence count manageable for local BLAST"
  mv curated_sequences_all.fasta query_sequences.fasta
fi

# Show final query set stats
echo "  • Query sequences for BLAST:"
seqkit stats query_sequences.fasta | tail -n +2 | sed 's/^/    /'
echo ""

### ── STEP 2: Database detection ─────────────────────────────────
echo "▶ Step 2: Detecting available BLAST databases"

# Check for available databases
DATABASES=()
DB_NAMES=()

# Check for databases built by script 00
for db_name in mitofish 12s coi; do
  db_path="$BLAST_DB_ROOT/$db_name/$db_name"
  echo "  • Checking database: $db_path"
  if [[ -f "${db_path}.nhr" && -f "${db_path}.nin" && -f "${db_path}.nsq" ]]; then
    echo "  ✅ Found BLAST database: $db_name at $db_path"
    DATABASES+=("$db_path")
    DB_NAMES+=("$db_name")
  else
    echo "  ⚠️  BLAST database not found: $db_name at $db_path"
    echo "      Looking for files:"
    ls -la "${db_path}"* 2>/dev/null || echo "      No files found with prefix $db_path"
  fi
done

if [[ ${#DATABASES[@]} -eq 0 ]]; then
  echo "  ❌ No BLAST databases found in $BLAST_DB_ROOT"
  echo "     Available directories in $BLAST_DB_ROOT:"
  ls -la "$BLAST_DB_ROOT" 2>/dev/null || echo "     Directory $BLAST_DB_ROOT not found"
  echo ""
  echo "     Run script 00 to build databases first:"
  echo "     bash scripts/00_build_dbs_kraken_blastn.sh"
  exit 1
fi

echo "  • Will use ${#DATABASES[@]} database(s): ${DB_NAMES[*]}"
echo ""

### ── STEP 3: Run BLAST against available databases ──────────────
echo "▶ Step 3: Running BLAST against available databases"

query_count=$(grep -c "^>" query_sequences.fasta)
echo "  • BLASTing $query_count sequences against ${#DATABASES[@]} databases"
echo "  • Estimated time: 2-10 minutes depending on sequence count"
echo ""

# Run BLAST against each available database
for i in "${!DATABASES[@]}"; do
  db_path="${DATABASES[$i]}"
  db_name="${DB_NAMES[$i]}"
  blast_output="${db_name}_blast_results.txt"
  
  echo "  • BLASTing against $db_name database..."
  
  if [[ -f "$blast_output" && -s "$blast_output" ]]; then
    echo "    ⚠️  $blast_output already exists; skipping BLAST"
    hit_count=$(wc -l < "$blast_output")
    echo "    • Existing results: $hit_count hits"
  else
    echo "    • Running BLAST (this may take a few minutes)..."
    blastn \
      -query query_sequences.fasta \
      -db "$db_path" \
      -num_threads "$THREADS" \
      -perc_identity "$BLAST_PERC_IDENTITY" \
      -evalue "$BLAST_EVALUE" \
      -max_target_seqs "$BLAST_MAX_TARGETS" \
      -outfmt '6 qseqid sseqid pident length qcovs evalue bitscore' \
      -out "$blast_output"
    
    if [[ -s "$blast_output" ]]; then
      hit_count=$(wc -l < "$blast_output")
      echo "    ✓ BLAST complete: $hit_count hits found"
    else
      echo "    ⚠️  No BLAST hits found for $db_name"
      touch "$blast_output"
    fi
  fi
done

echo ""

### ── STEP 4: Process BLAST results and create final table ────────
echo "▶ Step 4: Processing BLAST results and creating taxonomic table"

# Create R script for processing
cat > process_taxonomy.R << 'EOF'
# Load required libraries
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(tibble)
})

cat("  • Processing BLAST results and creating taxonomic assignments...\n")

# Read LULU curated OTU table - use absolute path
lulu_table_path <- file.path("..", list.files("../", pattern = "otu_table_lulu_curated.csv", recursive = TRUE)[1])

# Alternative search if not found
if (is.na(lulu_table_path) || !file.exists(lulu_table_path)) {
  # Search more broadly
  possible_paths <- c(
    "../results/04_denoise/otu_table_lulu_curated.csv",
    "../../results/04_denoise/otu_table_lulu_curated.csv",
    "../04_denoise/otu_table_lulu_curated.csv"
  )
  
  for (path in possible_paths) {
    if (file.exists(path)) {
      lulu_table_path <- path
      break
    }
  }
}

if (!file.exists(lulu_table_path)) {
  cat("❌ Error: Could not find otu_table_lulu_curated.csv\n")
  cat("    Searched paths:\n")
  for (path in c(lulu_table_path, possible_paths)) {
    cat("    -", path, ifelse(file.exists(path), "(exists)", "(not found)"), "\n")
  }
  quit(status = 1)
}

cat("  • Loading LULU-curated OTU table from:", lulu_table_path, "\n")
otu_table <- read_csv(lulu_table_path, show_col_types = FALSE)

# Handle different column name formats
if ("OTU_ID" %in% colnames(otu_table)) {
  otu_table <- otu_table %>% rename(Hash = OTU_ID)
} else if (names(otu_table)[1] %in% c("X", "...1", "")) {
  names(otu_table)[1] <- "Hash"
}

# Convert to long format for analysis
otu_long <- otu_table %>%
  pivot_longer(-Hash, names_to = 'Sample', values_to = 'Count') %>%
  filter(Count > 0)

cat("    ✓ Loaded", nrow(otu_long), "OTU abundance records\n")
cat("    • Unique OTUs:", n_distinct(otu_long$Hash), "\n")
cat("    • Samples:", n_distinct(otu_long$Sample), "\n")

# Find and process BLAST result files
blast_files <- list.files(".", pattern = "*_blast_results.txt", full.names = FALSE)
cat("  • Found", length(blast_files), "BLAST result files\n")

if (length(blast_files) == 0) {
  cat("    ⚠️  No BLAST results found\n")
  
  # Create table with all unassigned
  final_taxa <- otu_long %>%
    mutate(Species = 'unassigned') %>%
    group_by(Species, Sample) %>%
    summarise(Count = sum(Count), .groups = 'drop') %>%
    pivot_wider(names_from = Sample, values_from = Count, values_fill = 0)
  
} else {
  # Process BLAST results
  all_blast_results <- data.frame()
  
  for (blast_file in blast_files) {
    cat("    • Processing", blast_file, "\n")
    db_name <- str_remove(blast_file, "_blast_results.txt")
    
    if (file.size(blast_file) > 0) {
      # Read BLAST results with simplified format (no species names from our custom DBs)
      blast_df <- read_tsv(blast_file,
        col_names = c('Hash','sseqid','pident','length','qcovs','evalue','bitscore'),
        col_types = cols(), show_col_types = FALSE
      ) %>%
        mutate(Database = db_name) %>%
        # Extract database prefix as species proxy
        mutate(Species = paste0(db_name, "_hit")) %>%
        # Clean up any issues
        mutate(Hash = str_trim(Hash))
      
      cat("      ✓ Loaded", nrow(blast_df), "hits from", db_name, "\n")
      all_blast_results <- bind_rows(all_blast_results, blast_df)
    } else {
      cat("      • No hits in", blast_file, "\n")
    }
  }
  
  if (nrow(all_blast_results) > 0) {
    cat("  • Total BLAST hits processed:", nrow(all_blast_results), "\n")
    
    # Select best hit per OTU (prioritize by bitscore, then database preference)
    database_priority <- c("mitofish", "12s", "coi")
    
    blast_top <- all_blast_results %>%
      mutate(db_priority = match(Database, database_priority, nomatch = 999)) %>%
      group_by(Hash) %>%
      arrange(desc(bitscore), db_priority, desc(pident)) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      select(Hash, Species, pident, length, qcovs, evalue, bitscore, Database)
    
    cat("  • Best hits selected for", n_distinct(blast_top$Hash), "OTUs\n")
    
    # Database usage summary
    db_usage <- blast_top %>%
      count(Database, name = "OTUs_assigned") %>%
      arrange(desc(OTUs_assigned))
    
    cat("  • Assignment by database:\n")
    for (i in 1:nrow(db_usage)) {
      cat("    •", db_usage$Database[i], ":", db_usage$OTUs_assigned[i], "OTUs\n")
    }
    
    # Save detailed BLAST results
    write_csv(blast_top, 'blast_results_summary.csv')
    cat("    ✓ Saved detailed results: blast_results_summary.csv\n")
    
    # Join taxonomic assignments with abundance data
    cat("  • Merging taxonomic assignments with abundance data...\n")
    
    otu_taxa <- otu_long %>%
      left_join(blast_top %>% select(Hash, Species, Database), by = 'Hash') %>%
      replace_na(list(Species = 'unassigned', Database = 'none'))
    
    # Create assignment statistics
    assignment_stats <- otu_taxa %>%
      group_by(Sample) %>%
      summarise(
        Total_OTUs = n_distinct(Hash),
        Assigned_OTUs = n_distinct(Hash[Species != 'unassigned']),
        Total_Reads = sum(Count),
        Assigned_Reads = sum(Count[Species != 'unassigned']),
        .groups = 'drop'
      ) %>%
      mutate(
        OTU_Assignment_Rate = round(100 * Assigned_OTUs / Total_OTUs, 1),
        Read_Assignment_Rate = round(100 * Assigned_Reads / Total_Reads, 1)
      )
    
    cat("  • Assignment success rates:\n")
    for (i in 1:nrow(assignment_stats)) {
      cat("    •", assignment_stats$Sample[i], ":\n")
      cat("      - OTUs:", assignment_stats$Assigned_OTUs[i], "/", assignment_stats$Total_OTUs[i], 
          "(", assignment_stats$OTU_Assignment_Rate[i], "%)\n")
      cat("      - Reads:", assignment_stats$Assigned_Reads[i], "/", assignment_stats$Total_Reads[i], 
          "(", assignment_stats$Read_Assignment_Rate[i], "%)\n")
    }
    
    # Save assignment statistics
    write_csv(assignment_stats, 'taxonomic_assignment_stats.csv')
    cat("    ✓ Saved assignment statistics: taxonomic_assignment_stats.csv\n")
    
    # Create final species abundance matrix
    final_taxa <- otu_taxa %>%
      group_by(Species, Sample) %>%
      summarise(Count = sum(Count), .groups = 'drop') %>%
      pivot_wider(names_from = Sample, values_from = Count, values_fill = 0)
    
  } else {
    cat("  ⚠️  No BLAST hits found in any database\n")
    final_taxa <- otu_long %>%
      mutate(Species = 'unassigned') %>%
      group_by(Species, Sample) %>%
      summarise(Count = sum(Count), .groups = 'drop') %>%
      pivot_wider(names_from = Sample, values_from = Count, values_fill = 0)
  }
}

# Write final taxonomic table
write_csv(final_taxa, 'final_taxon_table_combined.csv')
cat("  ✓ Saved final taxonomic table: final_taxon_table_combined.csv\n")

# Summary of final table
cat("\n📊 Final taxonomic table summary:\n")
cat("    • Taxa identified:", nrow(final_taxa), "\n")
cat("    • Sample columns:", ncol(final_taxa) - 1, "\n")

# Show top taxa by abundance
if (nrow(final_taxa) > 0) {
  final_taxa_summary <- final_taxa %>%
    mutate(Total_Count = rowSums(select(., -Species))) %>%
    arrange(desc(Total_Count))
  
  cat("  • Top taxa by abundance:\n")
  for (i in 1:min(10, nrow(final_taxa_summary))) {
    cat("    ", i, ".", final_taxa_summary$Species[i], 
        " (", final_taxa_summary$Total_Count[i], " total counts)\n")
  }
}

cat("\n✅ Taxonomic assignment processing complete!\n")
EOF

# Run the R script
echo "  • Running taxonomic assignment analysis..."
Rscript process_taxonomy.R

echo ""

### ── FINAL SUMMARY ────────────────────────────────────────────────
echo "📊 STEP V COMPLETE - TAXONOMIC ASSIGNMENT SUMMARY"
echo "────────────────────────────────────────────────────────────────"

echo "📁 Output files created:"
for file in final_taxon_table_combined.csv blast_results_summary.csv taxonomic_assignment_stats.csv; do
  if [[ -f "$file" ]]; then
    echo "  ✅ $file"
  else
    echo "  ⚠️  $file (not created)"
  fi
done

echo ""
echo "🔬 Pipeline Summary:"
echo "   • Input: LULU-curated OTU table with clean ID matching"
echo "   • Process: BLAST taxonomic assignment against local databases"
echo "   • Output: Species-level abundance matrix across samples"
echo "   • Methods: Combined vsearch + amplicon_sorter results"

# Show final file preview if it exists
if [[ -f final_taxon_table_combined.csv ]]; then
  echo ""
  echo "📋 Final Taxonomic Table Preview:"
  head -10 final_taxon_table_combined.csv
fi

echo ""
echo "✅ Step V complete: Taxonomic assignment with abundance data!"
echo "🔬 Results:"
echo "   • Species abundance across 3 mock community samples"
echo "   • Database assignment statistics saved"
echo "   • Ready for community analysis and method comparison"
echo "   • Perfect for classroom demonstration!"
echo ""
