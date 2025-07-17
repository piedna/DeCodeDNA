#!/usr/bin/env bash
set -euo pipefail

# ─── usage ────────────────────────────────────────────────────────────────
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <DENOISE_DIR> <OUTPUT_DIR>"
  echo "Example: $0 results/04_denoise results/05_taxonomy"
  exit 1
fi
DENOISE_DIR="$1"
OUTPUT_DIR="$2"

# ─── locate project & databases (SELF-CONTAINED) ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Database locations (created by script 01)
BLAST_DB_ROOT="${BLAST_DB_ROOT:-$PROJECT_ROOT/../databases/blast_db}"
KRAKEN_DB_ROOT="${KRAKEN_DB_ROOT:-$PROJECT_ROOT/../databases/kraken2_db}"

echo "🔬 DeCodeDNA Taxonomic Assignment - SEPARATE METHOD PROCESSING"
echo "═══════════════════════════════════════════════════════════════════"
echo "🔹 Denoise input:    $DENOISE_DIR"
echo "🔹 Output directory: $OUTPUT_DIR"
echo "🔹 BLAST databases:  $BLAST_DB_ROOT"
echo "🔹 Kraken2 databases: $KRAKEN_DB_ROOT"
echo ""

# ─── sanity checks ───────────────────────────────────────────────────────
if [[ ! -d "$DENOISE_DIR" ]]; then
  echo "❌ Error: DENOISE_DIR not found: $DENOISE_DIR"
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

# ─── organize output directories ─────────────────────────────────────────
VSEARCH_DIR="$OUTPUT_DIR/vsearch_results"
AMPLICON_DIR="$OUTPUT_DIR/amplicon_sorter_results"
FINAL_DIR="$OUTPUT_DIR/final_combined_results"
TEMP_DIR="$OUTPUT_DIR/temp_files"

mkdir -p "$VSEARCH_DIR" "$AMPLICON_DIR" "$FINAL_DIR" "$TEMP_DIR"

echo "📁 Organized output structure:"
echo "   • vsearch results      → $VSEARCH_DIR"
echo "   • amplicon_sorter results → $AMPLICON_DIR"
echo "   • Final combined results → $FINAL_DIR"
echo "   • Temp files          → $TEMP_DIR"
echo ""

# ─── subset sequences for teaching speed ─────────────────────────────────
SUBSET_COUNT="${SUBSET_COUNT:-2000}"
THREADS="${THREADS:-8}"
EVALUE="${EVALUE:-1e-20}"
MAX_HITS="${MAX_HITS:-5}"

# ═══════════════════════════════════════════════════════════════════════════
# ─── PROCESS VSEARCH RESULTS ──────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🚀 PROCESSING VSEARCH RESULTS"
echo "══════════════════════════════════════════════════════════════════"

# Find and combine vsearch representative sequences from all databases
VSEARCH_REP_FASTA="$TEMP_DIR/vsearch_all_representatives.fasta"
VSEARCH_OTU_TABLE="$TEMP_DIR/vsearch_all_otu_table.csv"
> "$VSEARCH_REP_FASTA"
echo "OTU_ID,Sample1,Sample2,Sample3" > "$VSEARCH_OTU_TABLE"

databases_found_vsearch=0

for db in 12s coi mitofish; do
  vsearch_db_dir="$DENOISE_DIR/vsearch_$db"
  if [[ -d "$vsearch_db_dir" ]]; then
    echo "📁 Found vsearch database directory: $db"
    
    # Look for representative sequences
    rep_fasta=$(find "$vsearch_db_dir" -name "*representatives_vsearch_${db}.fasta" | head -n1 || true)
    if [[ -n "$rep_fasta" && -f "$rep_fasta" ]]; then
      echo "  ✓ Adding vsearch representatives: $(basename "$rep_fasta")"
      cat "$rep_fasta" >> "$VSEARCH_REP_FASTA"
    fi
    
    # Look for curated OTU table
    otu_table=$(find "$vsearch_db_dir" -name "*vsearch_${db}_lulu_curated.csv" | head -n1 || true)
    if [[ -n "$otu_table" && -f "$otu_table" ]]; then
      echo "  ✓ Adding vsearch OTU table: $(basename "$otu_table")"
      # Skip header and append data
      tail -n +2 "$otu_table" >> "$VSEARCH_OTU_TABLE"
      databases_found_vsearch=$((databases_found_vsearch + 1))
    fi
  fi
done

if [[ $databases_found_vsearch -eq 0 ]]; then
  echo "❌ Error: No vsearch database results found in $DENOISE_DIR"
  echo "Expected structure: $DENOISE_DIR/vsearch_{12s,coi,mitofish}/"
  exit 1
fi

echo "✔ Combined vsearch representatives: $VSEARCH_REP_FASTA"
echo "✔ Combined vsearch OTU table: $VSEARCH_OTU_TABLE"

# Create subset for teaching speed
VSEARCH_SUBSET_FASTA="$TEMP_DIR/vsearch_query_sequences_subset${SUBSET_COUNT}.fasta"
echo "🎓 Creating vsearch subset of $SUBSET_COUNT sequences for classroom speed"
awk -v N="$SUBSET_COUNT" '
  BEGIN { RS=">"; ORS="" }
  NR>1 && N-->0 { print ">" $0 }
' "$VSEARCH_REP_FASTA" > "$VSEARCH_SUBSET_FASTA"

vsearch_subset_count=$(grep -c "^>" "$VSEARCH_SUBSET_FASTA")
echo "   ✓ Using $vsearch_subset_count vsearch sequences for analysis"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PROCESS AMPLICON_SORTER RESULTS ──────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🎯 PROCESSING AMPLICON_SORTER RESULTS"
echo "══════════════════════════════════════════════════════════════════"

# Find and combine amplicon_sorter representative sequences from all databases
AMPLICON_REP_FASTA="$TEMP_DIR/amplicon_sorter_all_representatives.fasta"
AMPLICON_OTU_TABLE="$TEMP_DIR/amplicon_sorter_all_otu_table.csv"
> "$AMPLICON_REP_FASTA"
echo "OTU_ID,Sample1,Sample2,Sample3" > "$AMPLICON_OTU_TABLE"

databases_found_amplicon=0

for db in 12s coi mitofish; do
  amplicon_db_dir="$DENOISE_DIR/amplicon_sorter_$db"
  if [[ -d "$amplicon_db_dir" ]]; then
    echo "📁 Found amplicon_sorter database directory: $db"
    
    # Look for representative sequences
    rep_fasta=$(find "$amplicon_db_dir" -name "*representatives_amplicon_sorter_${db}.fasta" | head -n1 || true)
    if [[ -n "$rep_fasta" && -f "$rep_fasta" ]]; then
      echo "  ✓ Adding amplicon_sorter representatives: $(basename "$rep_fasta")"
      cat "$rep_fasta" >> "$AMPLICON_REP_FASTA"
    fi
    
    # Look for curated OTU table
    otu_table=$(find "$amplicon_db_dir" -name "*amplicon_sorter_${db}_lulu_curated.csv" | head -n1 || true)
    if [[ -n "$otu_table" && -f "$otu_table" ]]; then
      echo "  ✓ Adding amplicon_sorter OTU table: $(basename "$otu_table")"
      # Skip header and append data
      tail -n +2 "$otu_table" >> "$AMPLICON_OTU_TABLE"
      databases_found_amplicon=$((databases_found_amplicon + 1))
    fi
  fi
done

if [[ $databases_found_amplicon -eq 0 ]]; then
  echo "❌ Error: No amplicon_sorter database results found in $DENOISE_DIR"
  echo "Expected structure: $DENOISE_DIR/amplicon_sorter_{12s,coi,mitofish}/"
  exit 1
fi

echo "✔ Combined amplicon_sorter representatives: $AMPLICON_REP_FASTA"
echo "✔ Combined amplicon_sorter OTU table: $AMPLICON_OTU_TABLE"

# Create subset for teaching speed
AMPLICON_SUBSET_FASTA="$TEMP_DIR/amplicon_sorter_query_sequences_subset${SUBSET_COUNT}.fasta"
echo "🎓 Creating amplicon_sorter subset of $SUBSET_COUNT sequences for classroom speed"
awk -v N="$SUBSET_COUNT" '
  BEGIN { RS=">"; ORS="" }
  NR>1 && N-->0 { print ">" $0 }
' "$AMPLICON_REP_FASTA" > "$AMPLICON_SUBSET_FASTA"

amplicon_subset_count=$(grep -c "^>" "$AMPLICON_SUBSET_FASTA")
echo "   ✓ Using $amplicon_subset_count amplicon_sorter sequences for analysis"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 1: BLAST ANALYSIS FOR BOTH METHODS ─────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🧬 PART 1: BLAST TAXONOMIC ASSIGNMENT FOR BOTH METHODS"
echo "════════════════════════════════════════════════════════════════"

# ─── BLAST for vsearch results ───────────────────────────────────────────
echo "=== BLAST Analysis for vsearch Results ==="
VSEARCH_BLAST_DIR="$VSEARCH_DIR/blast_results"
mkdir -p "$VSEARCH_BLAST_DIR"

for DB in 12s coi mitofish; do
  echo "--- BLAST vsearch against $DB database ---"
  DB_PATH="$BLAST_DB_ROOT/$DB/$DB"
  
  if [[ ! -f "${DB_PATH}.nsq" && ! -f "${DB_PATH}.nin" ]]; then
    echo "❌ BLAST DB not found: $DB_PATH"
    echo "   Run script 01 to build databases first"
    continue
  fi

  BLAST_OUT="$VSEARCH_BLAST_DIR/vsearch_${DB}_blast_hits.tsv"
  
  echo "   • Running BLAST for vsearch (top $MAX_HITS hits)..."
  blastn -task megablast \
         -db "$DB_PATH" \
         -query "$VSEARCH_SUBSET_FASTA" \
         -max_target_seqs "$MAX_HITS" \
         -evalue "$EVALUE" \
         -outfmt "6 qseqid sseqid pident length bitscore staxids stitle" \
         -num_threads "$THREADS" \
         -out "$BLAST_OUT"

  hit_count=$(wc -l < "$BLAST_OUT" 2>/dev/null || echo "0")
  echo "   ✓ Found $hit_count vsearch BLAST hits → $BLAST_OUT"
done

# ─── BLAST for amplicon_sorter results ───────────────────────────────────
echo ""
echo "=== BLAST Analysis for amplicon_sorter Results ==="
AMPLICON_BLAST_DIR="$AMPLICON_DIR/blast_results"
mkdir -p "$AMPLICON_BLAST_DIR"

for DB in 12s coi mitofish; do
  echo "--- BLAST amplicon_sorter against $DB database ---"
  DB_PATH="$BLAST_DB_ROOT/$DB/$DB"
  
  if [[ ! -f "${DB_PATH}.nsq" && ! -f "${DB_PATH}.nin" ]]; then
    echo "❌ BLAST DB not found: $DB_PATH"
    continue
  fi

  BLAST_OUT="$AMPLICON_BLAST_DIR/amplicon_sorter_${DB}_blast_hits.tsv"
  
  echo "   • Running BLAST for amplicon_sorter (top $MAX_HITS hits)..."
  blastn -task megablast \
         -db "$DB_PATH" \
         -query "$AMPLICON_SUBSET_FASTA" \
         -max_target_seqs "$MAX_HITS" \
         -evalue "$EVALUE" \
         -outfmt "6 qseqid sseqid pident length bitscore staxids stitle" \
         -num_threads "$THREADS" \
         -out "$BLAST_OUT"

  hit_count=$(wc -l < "$BLAST_OUT" 2>/dev/null || echo "0")
  echo "   ✓ Found $hit_count amplicon_sorter BLAST hits → $BLAST_OUT"
done

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 2: KRAKEN2 ANALYSIS FOR BOTH METHODS ───────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🦠 PART 2: KRAKEN2 TAXONOMIC CLASSIFICATION FOR BOTH METHODS"
echo "═══════════════════════════════════════════════════════════════════════"

# Check for Kraken2 and KronaTools
echo "🔍 Checking required tools..."
if command -v kraken2 >/dev/null 2>&1; then
  echo "✅ kraken2 found"
else
  echo "❌ kraken2 not found - skipping Kraken2 analysis"
  echo "   Install with: conda install -c bioconda kraken2"
  SKIP_KRAKEN=true
fi

if command -v ktImportTaxonomy >/dev/null 2>&1; then
  echo "✅ KronaTools found"
else
  echo "❌ KronaTools not found - plots will be skipped"
  echo "   Install with: conda install -c bioconda krona"
  SKIP_KRONA=true
fi

if [[ "${SKIP_KRAKEN:-false}" != "true" ]]; then
  # ─── Kraken2 for vsearch results ───────────────────────────────────────
  echo ""
  echo "=== Kraken2 Classification for vsearch Results ==="
  VSEARCH_KRAKEN_DIR="$VSEARCH_DIR/kraken2_results"
  mkdir -p "$VSEARCH_KRAKEN_DIR"

  for DB in 12s coi mitofish; do
    echo "--- Kraken2 vsearch against $DB database ---"
    KRAKEN_DB_PATH="$KRAKEN_DB_ROOT/$DB"
    
    if [[ ! -d "$KRAKEN_DB_PATH" ]] || [[ ! -f "$KRAKEN_DB_PATH/taxo.k2d" ]]; then
      echo "❌ Kraken2 DB not found: $KRAKEN_DB_PATH"
      continue
    fi

    KRAKEN_OUT="$VSEARCH_KRAKEN_DIR/vsearch_${DB}_kraken2_output.txt"
    KRAKEN_REPORT="$VSEARCH_KRAKEN_DIR/vsearch_${DB}_kraken2_report.txt"
    
    echo "   • Running Kraken2 classification for vsearch..."
    kraken2 --db "$KRAKEN_DB_PATH" \
            --threads "$THREADS" \
            --output "$KRAKEN_OUT" \
            --report "$KRAKEN_REPORT" \
            "$VSEARCH_SUBSET_FASTA"

    # Count classifications
    classified_count=$(grep -c "^C" "$KRAKEN_OUT" 2>/dev/null || echo "0")
    total_count=$(wc -l < "$KRAKEN_OUT" 2>/dev/null || echo "0")
    
    if [[ "$total_count" -gt 0 ]]; then
      classification_rate=$(echo "scale=1; $classified_count * 100 / $total_count" | bc -l 2>/dev/null || echo "0")
    else
      classification_rate="0"
    fi
    
    echo "   ✓ vsearch classified $classified_count/$total_count sequences (${classification_rate}%)"

    # Create Krona plot for vsearch
    if [[ "${SKIP_KRONA:-false}" != "true" ]] && [[ -s "$KRAKEN_REPORT" ]]; then
      VSEARCH_KRONA_DIR="$VSEARCH_DIR/krona_plots"
      mkdir -p "$VSEARCH_KRONA_DIR"
      KRONA_HTML="$VSEARCH_KRONA_DIR/vsearch_${DB}_krona_plot.html"
      
      # Convert and create Krona plot
      krona_input="$TEMP_DIR/vsearch_${DB}_krona_input.txt"
      cat > "$TEMP_DIR/kraken2_to_krona.py" << 'EOF'
import sys
import re

def kraken2_to_krona(report_file, output_file):
    """Convert Kraken2 report to Krona input format"""
    with open(report_file, 'r') as f, open(output_file, 'w') as out:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 6:
                percentage = float(parts[0])
                clade_reads = int(parts[1])
                taxon_reads = int(parts[2])
                rank_code = parts[3]
                taxid = parts[4]
                name = parts[5].strip()
                
                # Only output entries with actual reads
                if taxon_reads > 0:
                    # Clean up taxonomy name
                    clean_name = re.sub(r'^\s+', '', name)
                    out.write(f"{taxon_reads}\t{clean_name}\n")

if __name__ == "__main__":
    kraken2_to_krona(sys.argv[1], sys.argv[2])
EOF

      python3 "$TEMP_DIR/kraken2_to_krona.py" "$KRAKEN_REPORT" "$krona_input"
      
      if [[ -s "$krona_input" ]]; then
        ktImportText -o "$KRONA_HTML" "$krona_input"
        echo "   ✓ vsearch Krona plot → $KRONA_HTML"
      fi
    fi
  done

  # ─── Kraken2 for amplicon_sorter results ──────────────────────────────
  echo ""
  echo "=== Kraken2 Classification for amplicon_sorter Results ==="
  AMPLICON_KRAKEN_DIR="$AMPLICON_DIR/kraken2_results"
  mkdir -p "$AMPLICON_KRAKEN_DIR"

  for DB in 12s coi mitofish; do
    echo "--- Kraken2 amplicon_sorter against $DB database ---"
    KRAKEN_DB_PATH="$KRAKEN_DB_ROOT/$DB"
    
    if [[ ! -d "$KRAKEN_DB_PATH" ]] || [[ ! -f "$KRAKEN_DB_PATH/taxo.k2d" ]]; then
      echo "❌ Kraken2 DB not found: $KRAKEN_DB_PATH"
      continue
    fi

    KRAKEN_OUT="$AMPLICON_KRAKEN_DIR/amplicon_sorter_${DB}_kraken2_output.txt"
    KRAKEN_REPORT="$AMPLICON_KRAKEN_DIR/amplicon_sorter_${DB}_kraken2_report.txt"
    
    echo "   • Running Kraken2 classification for amplicon_sorter..."
    kraken2 --db "$KRAKEN_DB_PATH" \
            --threads "$THREADS" \
            --output "$KRAKEN_OUT" \
            --report "$KRAKEN_REPORT" \
            "$AMPLICON_SUBSET_FASTA"

    # Count classifications
    classified_count=$(grep -c "^C" "$KRAKEN_OUT" 2>/dev/null || echo "0")
    total_count=$(wc -l < "$KRAKEN_OUT" 2>/dev/null || echo "0")
    
    if [[ "$total_count" -gt 0 ]]; then
      classification_rate=$(echo "scale=1; $classified_count * 100 / $total_count" | bc -l 2>/dev/null || echo "0")
    else
      classification_rate="0"
    fi
    
    echo "   ✓ amplicon_sorter classified $classified_count/$total_count sequences (${classification_rate}%)"

    # Create Krona plot for amplicon_sorter
    if [[ "${SKIP_KRONA:-false}" != "true" ]] && [[ -s "$KRAKEN_REPORT" ]]; then
      AMPLICON_KRONA_DIR="$AMPLICON_DIR/krona_plots"
      mkdir -p "$AMPLICON_KRONA_DIR"
      KRONA_HTML="$AMPLICON_KRONA_DIR/amplicon_sorter_${DB}_krona_plot.html"
      
      # Convert and create Krona plot
      krona_input="$TEMP_DIR/amplicon_sorter_${DB}_krona_input.txt"
      python3 "$TEMP_DIR/kraken2_to_krona.py" "$KRAKEN_REPORT" "$krona_input"
      
      if [[ -s "$krona_input" ]]; then
        ktImportText -o "$KRONA_HTML" "$krona_input"
        echo "   ✓ amplicon_sorter Krona plot → $KRONA_HTML"
      fi
    fi
  done
else
  echo "⚠️  Skipping Kraken2 analysis - kraken2 not found"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 3: PROCESS AND COMBINE RESULTS SEPARATELY ──────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "📊 PART 3: PROCESSING TAXONOMIC RESULTS SEPARATELY"
echo "═══════════════════════════════════════════════════════════════════"

# ─── create comprehensive taxonomy processing script for separate methods ───
cat > "$TEMP_DIR/process_separate_taxonomy.R" << 'EOF'
library(dplyr)
library(readr)
library(tidyr)
library(stringr)

# Read command line arguments
args <- commandArgs(trailingOnly = TRUE)
method <- args[1]  # "vsearch" or "amplicon_sorter"
otu_file <- args[2]
blast_dir <- args[3] 
kraken_dir <- args[4]
output_dir <- args[5]

cat("📊 Processing", method, "taxonomic results...\n\n")

# Read OTU table
cat("Reading", method, "OTU table:", otu_file, "\n")
otu_data <- read_csv(otu_file, show_col_types = FALSE)

# Clean column names and remove quotes
names(otu_data)[1] <- "OTU_ID"
otu_data$OTU_ID <- gsub('"', '', otu_data$OTU_ID)

# Convert to long format
otu_long <- otu_data %>%
  pivot_longer(-OTU_ID, names_to = "Sample", values_to = "Count") %>%
  filter(Count > 0)

cat("Processing", nrow(otu_long), method, "OTU abundance records\n\n")

# ═══ PROCESS BLAST RESULTS ═══
cat("🧬 Processing", method, "BLAST results...\n")
blast_summary <- data.frame()

for (db in c("12s", "coi", "mitofish")) {
  blast_file <- file.path(blast_dir, paste0(method, "_", db, "_blast_hits.tsv"))
  
  if (file.exists(blast_file) && file.size(blast_file) > 0) {
    # Read BLAST results
    blast_data <- read_tsv(blast_file, 
      col_names = c("OTU_ID", "hit_id", "pct_identity", "length", "bitscore", "staxids", "stitle"),
      col_types = cols(), show_col_types = FALSE)
    
    # Take best hit per OTU (highest bitscore)
    best_hits <- blast_data %>%
      group_by(OTU_ID) %>%
      arrange(desc(bitscore), desc(pct_identity)) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      mutate(
        # Extract species from hit_id (database header)
        species = case_when(
          db %in% c("12s", "coi") ~ str_extract(hit_id, "[A-Z][a-z]+_[a-z]+"),
          db == "mitofish" ~ str_extract(hit_id, "(?:gb_[^_]+_)?([A-Z][a-z]+_[a-z]+)") %>% str_remove("gb_[^_]+_"),
          TRUE ~ hit_id
        ),
        # Clean up species names
        species = ifelse(is.na(species) | species == "", 
                        paste0("unknown_", row_number()), 
                        species),
        database = db,
        method = method,
        assignment_status = "classified"
      ) %>%
      select(OTU_ID, species, pct_identity, bitscore, database, method, assignment_status)
    
    cat("  •", method, db, ":", nrow(best_hits), "OTUs classified\n")
    
    # Merge with abundance data
    taxonomy_result <- otu_long %>%
      left_join(best_hits, by = "OTU_ID") %>%
      mutate(
        species = ifelse(is.na(species), "unclassified", species),
        database = db,
        method = method,
        assignment_status = ifelse(is.na(assignment_status), "unclassified", assignment_status)
      ) %>%
      select(OTU_ID, Sample, Count, species, pct_identity, bitscore, database, method, assignment_status)
    
    # Create species abundance matrix for BLAST
    blast_species_matrix <- taxonomy_result %>%
      filter(assignment_status == "classified") %>%
      group_by(species, Sample) %>%
      summarise(Count = sum(Count), .groups = "drop") %>%
      pivot_wider(names_from = Sample, values_from = Count, values_fill = 0) %>%
      arrange(desc(rowSums(select(., -species))))
    
    # Save BLAST results
    blast_classified_file <- file.path(output_dir, paste0("BLAST_", method, "_", db, "_classified_species.csv"))
    blast_full_file <- file.path(output_dir, paste0("BLAST_", method, "_", db, "_full_taxonomy.csv"))
    
    if (nrow(blast_species_matrix) > 0) {
      write_csv(blast_species_matrix, blast_classified_file)
    } else {
      empty_df <- data.frame(species = character(0), Sample1 = numeric(0), Sample2 = numeric(0), Sample3 = numeric(0))
      write_csv(empty_df, blast_classified_file)
    }
    
    write_csv(taxonomy_result, blast_full_file)
    
    # Add to summary
    classified_otus <- sum(taxonomy_result$assignment_status == "classified")
    total_otus <- nrow(taxonomy_result)
    classification_rate <- round(100 * classified_otus / total_otus, 1)
    
    blast_summary <- bind_rows(blast_summary, data.frame(
      database = db,
      method = method,
      total_otus = total_otus,
      classified_otus = classified_otus,
      classification_rate = classification_rate,
      unique_species = nrow(blast_species_matrix)
    ))
  }
}

# ═══ PROCESS KRAKEN2 RESULTS ═══
cat("\n🦠 Processing", method, "Kraken2 results...\n")
kraken_summary <- data.frame()

for (db in c("12s", "coi", "mitofish")) {
  kraken_file <- file.path(kraken_dir, paste0(method, "_", db, "_kraken2_output.txt"))
  kraken_report_file <- file.path(kraken_dir, paste0(method, "_", db, "_kraken2_report.txt"))
  
  if (file.exists(kraken_file) && file.size(kraken_file) > 0) {
    # Read Kraken2 output
    kraken_data <- read_tsv(kraken_file,
      col_names = c("classified", "OTU_ID", "taxid", "length", "lca_mapping"),
      col_types = cols(), show_col_types = FALSE)
    
    # Read Kraken2 report for taxonomic names
    if (file.exists(kraken_report_file)) {
      kraken_taxa <- read_tsv(kraken_report_file,
        col_names = c("percentage", "clade_reads", "direct_reads", "rank", "taxid", "name"),
        col_types = cols(), show_col_types = FALSE) %>%
        mutate(name = trimws(name)) %>%
        filter(rank %in% c("S", "G")) %>%  # Species and Genus level
        select(taxid, name)
      
      # Join classifications with taxonomic names
      kraken_classified <- kraken_data %>%
        filter(classified == "C") %>%  # Only classified sequences
        left_join(kraken_taxa, by = "taxid") %>%
        mutate(
          species = ifelse(is.na(name), paste0("taxid_", taxid), name),
          database = db,
          method = method,
          assignment_status = "classified"
        ) %>%
        select(OTU_ID, species, taxid, database, method, assignment_status)
      
      cat("  •", method, db, ":", nrow(kraken_classified), "OTUs classified\n")
      
      # Merge with abundance data
      kraken_taxonomy_result <- otu_long %>%
        left_join(kraken_classified, by = "OTU_ID") %>%
        mutate(
          species = ifelse(is.na(species), "unclassified", species),
          database = db,
          method = method,
          assignment_status = ifelse(is.na(assignment_status), "unclassified", assignment_status)
        ) %>%
        select(OTU_ID, Sample, Count, species, taxid, database, method, assignment_status)
      
      # Create species abundance matrix for Kraken2
      kraken_species_matrix <- kraken_taxonomy_result %>%
        filter(assignment_status == "classified") %>%
        group_by(species, Sample) %>%
        summarise(Count = sum(Count), .groups = "drop") %>%
        pivot_wider(names_from = Sample, values_from = Count, values_fill = 0) %>%
        arrange(desc(rowSums(select(., -species))))
      
      # Save Kraken2 results
      kraken_classified_file <- file.path(output_dir, paste0("Kraken2_", method, "_", db, "_classified_species.csv"))
      kraken_full_file <- file.path(output_dir, paste0("Kraken2_", method, "_", db, "_full_taxonomy.csv"))
      
      if (nrow(kraken_species_matrix) > 0) {
        write_csv(kraken_species_matrix, kraken_classified_file)
      } else {
        empty_df <- data.frame(species = character(0), Sample1 = numeric(0), Sample2 = numeric(0), Sample3 = numeric(0))
        write_csv(empty_df, kraken_classified_file)
      }
      
      write_csv(kraken_taxonomy_result, kraken_full_file)
      
      # Add to summary
      classified_otus <- sum(kraken_taxonomy_result$assignment_status == "classified")
      total_otus <- nrow(kraken_taxonomy_result)
      classification_rate <- round(100 * classified_otus / total_otus, 1)
      
      kraken_summary <- bind_rows(kraken_summary, data.frame(
        database = db,
        method = method,
        total_otus = total_otus,
        classified_otus = classified_otus,
        classification_rate = classification_rate,
        unique_species = nrow(kraken_species_matrix)
      ))
    }
  }
}

# ═══ CREATE METHOD SUMMARY ═══
cat("\n📈 Creating", method, "method summary...\n")
method_summary <- bind_rows(blast_summary, kraken_summary)

if (nrow(method_summary) > 0) {
  write_csv(method_summary, file.path(output_dir, paste0(method, "_method_summary.csv")))
  
  cat("\n📊", method, "Method Summary:\n")
  print(method_summary)
} else {
  cat("⚠️  No", method, "results to summarize\n")
}

cat("\n✅", method, "taxonomy processing complete!\n")
EOF

# Process vsearch results
echo "   • Processing vsearch taxonomic results..."
VSEARCH_TAXONOMY_DIR="$VSEARCH_DIR/final_taxonomy"
mkdir -p "$VSEARCH_TAXONOMY_DIR"

Rscript "$TEMP_DIR/process_separate_taxonomy.R" \
  "vsearch" \
  "$VSEARCH_OTU_TABLE" \
  "$VSEARCH_BLAST_DIR" \
  "${VSEARCH_KRAKEN_DIR:-$TEMP_DIR}" \
  "$VSEARCH_TAXONOMY_DIR"

# Process amplicon_sorter results
echo ""
echo "   • Processing amplicon_sorter taxonomic results..."
AMPLICON_TAXONOMY_DIR="$AMPLICON_DIR/final_taxonomy"
mkdir -p "$AMPLICON_TAXONOMY_DIR"

Rscript "$TEMP_DIR/process_separate_taxonomy.R" \
  "amplicon_sorter" \
  "$AMPLICON_OTU_TABLE" \
  "$AMPLICON_BLAST_DIR" \
  "${AMPLICON_KRAKEN_DIR:-$TEMP_DIR}" \
  "$AMPLICON_TAXONOMY_DIR"

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 4: CREATE FINAL COMBINED 6-COLUMN OUTPUT ───────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🔄 PART 4: CREATING FINAL COMBINED 6-COLUMN OUTPUT"
echo "════════════════════════════════════════════════════════════════"

# Create R script to combine results into 6-column format
cat > "$TEMP_DIR/create_final_combined.R" << 'EOF'
library(dplyr)
library(readr)
library(tidyr)

args <- commandArgs(trailingOnly = TRUE)
vsearch_dir <- args[1]
amplicon_dir <- args[2]
final_dir <- args[3]

cat("🔄 Creating final combined 6-column results...\n\n")

# Function to read and process method results
read_method_results <- function(method_dir, method_name) {
  results_list <- list()
  
  # Look for BLAST classified species files
  for (db in c("12s", "coi", "mitofish")) {
    for (assignment_method in c("BLAST", "Kraken2")) {
      file_pattern <- paste0(assignment_method, "_", method_name, "_", db, "_classified_species.csv")
      file_path <- file.path(method_dir, file_pattern)
      
      if (file.exists(file_path) && file.size(file_path) > 0) {
        cat("  Reading:", file_pattern, "\n")
        
        data <- read_csv(file_path, show_col_types = FALSE)
        
        # Rename columns to include method suffix
        if (ncol(data) >= 4) {  # species + 3 sample columns
          names(data)[2:4] <- paste0(names(data)[2:4], "_", method_name)
          data$database <- db
          data$assignment_method <- assignment_method
          
          results_list[[paste(assignment_method, method_name, db, sep="_")]] <- data
        }
      }
    }
  }
  
  return(results_list)
}

# Read vsearch results
cat("📊 Reading vsearch results...\n")
vsearch_results <- read_method_results(vsearch_dir, "vsearch")

# Read amplicon_sorter results  
cat("\n🎯 Reading amplicon_sorter results...\n")
amplicon_results <- read_method_results(amplicon_dir, "amplicon_sorter")

# Combine results for each database and assignment method
cat("\n🔄 Combining results into 6-column format...\n")

for (db in c("12s", "coi", "mitofish")) {
  for (assignment_method in c("BLAST", "Kraken2")) {
    cat("  Processing", assignment_method, db, "...\n")
    
    # Get data for this combination
    vsearch_key <- paste(assignment_method, "vsearch", db, sep="_")
    amplicon_key <- paste(assignment_method, "amplicon_sorter", db, sep="_")
    
    vsearch_data <- if (vsearch_key %in% names(vsearch_results)) vsearch_results[[vsearch_key]] else NULL
    amplicon_data <- if (amplicon_key %in% names(amplicon_results)) amplicon_results[[amplicon_key]] else NULL
    
    # Create combined data
    combined_data <- NULL
    
    if (!is.null(vsearch_data) && !is.null(amplicon_data)) {
      # Both methods have data - full join
      combined_data <- full_join(
        select(vsearch_data, species, Sample1_vsearch, Sample2_vsearch, Sample3_vsearch),
        select(amplicon_data, species, Sample1_amplicon_sorter, Sample2_amplicon_sorter, Sample3_amplicon_sorter),
        by = "species"
      )
    } else if (!is.null(vsearch_data)) {
      # Only vsearch data
      combined_data <- vsearch_data %>%
        select(species, Sample1_vsearch, Sample2_vsearch, Sample3_vsearch) %>%
        mutate(
          Sample1_amplicon_sorter = 0,
          Sample2_amplicon_sorter = 0,
          Sample3_amplicon_sorter = 0
        )
    } else if (!is.null(amplicon_data)) {
      # Only amplicon_sorter data
      combined_data <- amplicon_data %>%
        select(species, Sample1_amplicon_sorter, Sample2_amplicon_sorter, Sample3_amplicon_sorter) %>%
        mutate(
          Sample1_vsearch = 0,
          Sample2_vsearch = 0,
          Sample3_vsearch = 0
        )
    }
    
    # Save combined data if we have any
    if (!is.null(combined_data) && nrow(combined_data) > 0) {
      # Replace NA with 0
      combined_data[is.na(combined_data)] <- 0
      
      # Reorder columns: species, Sample1_vsearch, Sample2_vsearch, Sample3_vsearch, Sample1_amplicon_sorter, Sample2_amplicon_sorter, Sample3_amplicon_sorter
      combined_data <- combined_data %>%
        select(species, Sample1_vsearch, Sample2_vsearch, Sample3_vsearch, 
               Sample1_amplicon_sorter, Sample2_amplicon_sorter, Sample3_amplicon_sorter) %>%
        arrange(desc(Sample1_vsearch + Sample2_vsearch + Sample3_vsearch + 
                    Sample1_amplicon_sorter + Sample2_amplicon_sorter + Sample3_amplicon_sorter))
      
      # Save file
      output_file <- file.path(final_dir, paste0("Final_Combined_", assignment_method, "_", db, "_6columns.csv"))
      write_csv(combined_data, output_file)
      
      cat("    ✓ Saved:", basename(output_file), "- ", nrow(combined_data), "species\n")
    } else {
      cat("    ⚠️  No data available for", assignment_method, db, "\n")
    }
  }
}

# Create method comparison summary
cat("\n📈 Creating method comparison summary...\n")
comparison_summary <- data.frame()

# Read method summaries
vsearch_summary_file <- file.path(vsearch_dir, "vsearch_method_summary.csv")
amplicon_summary_file <- file.path(amplicon_dir, "amplicon_sorter_method_summary.csv")

if (file.exists(vsearch_summary_file)) {
  vsearch_summary <- read_csv(vsearch_summary_file, show_col_types = FALSE)
  comparison_summary <- bind_rows(comparison_summary, vsearch_summary)
}

if (file.exists(amplicon_summary_file)) {
  amplicon_summary <- read_csv(amplicon_summary_file, show_col_types = FALSE)
  comparison_summary <- bind_rows(comparison_summary, amplicon_summary)
}

if (nrow(comparison_summary) > 0) {
  write_csv(comparison_summary, file.path(final_dir, "Method_Comparison_Summary.csv"))
  cat("✓ Saved: Method_Comparison_Summary.csv\n")
}

cat("\n✅ Final combined 6-column results created successfully!\n")
EOF

# Run the combination script
echo "   • Creating final combined 6-column results..."
Rscript "$TEMP_DIR/create_final_combined.R" \
  "$VSEARCH_TAXONOMY_DIR" \
  "$AMPLICON_TAXONOMY_DIR" \
  "$FINAL_DIR"

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── FINAL SUMMARY AND RESULTS ────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🎉 COMPREHENSIVE SEPARATE METHOD TAXONOMIC ASSIGNMENT COMPLETE!"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo "📁 Results organized by method:"
echo ""
echo "🚀 vsearch Results → $VSEARCH_DIR/"
echo "   • BLAST results      → $VSEARCH_DIR/blast_results/"
echo "   • Kraken2 results    → $VSEARCH_DIR/kraken2_results/"
echo "   • Final taxonomy     → $VSEARCH_DIR/final_taxonomy/"
echo "   • Krona plots        → $VSEARCH_DIR/krona_plots/"
echo ""
echo "🎯 amplicon_sorter Results → $AMPLICON_DIR/"
echo "   • BLAST results      → $AMPLICON_DIR/blast_results/"
echo "   • Kraken2 results    → $AMPLICON_DIR/kraken2_results/"
echo "   • Final taxonomy     → $AMPLICON_DIR/final_taxonomy/"
echo "   • Krona plots        → $AMPLICON_DIR/krona_plots/"
echo ""
echo "🔄 Final Combined Results (6-column format) → $FINAL_DIR/"

echo ""
echo "📋 Key output files with 6-column format:"
echo "   (Sample1_vsearch, Sample2_vsearch, Sample3_vsearch, Sample1_amplicon_sorter, Sample2_amplicon_sorter, Sample3_amplicon_sorter)"
echo ""

for db in 12s coi mitofish; do
  for method in BLAST Kraken2; do
    final_file="$FINAL_DIR/Final_Combined_${method}_${db}_6columns.csv"
    if [[ -f "$final_file" ]]; then
      species_count=$(tail -n +2 "$final_file" | wc -l 2>/dev/null || echo "0")
      echo "   • Final_Combined_${method}_${db}_6columns.csv - $species_count species"
    fi
  done
done

echo ""
echo "📈 Method Comparison:"
if [[ -f "$FINAL_DIR/Method_Comparison_Summary.csv" ]]; then
  echo "   • Method_Comparison_Summary.csv - Compare vsearch vs amplicon_sorter performance"
fi

if [[ "${SKIP_KRONA:-false}" != "true" ]]; then
  echo ""
  echo "🍩 Krona Plots (Method-specific):"
  echo "   • vsearch plots → $VSEARCH_DIR/krona_plots/"
  echo "   • amplicon_sorter plots → $AMPLICON_DIR/krona_plots/"
fi

echo ""
echo "🎓 For the class:"
echo "   • Compare vsearch vs amplicon_sorter clustering methods"
echo "   • 6-column format allows direct comparison of methods"
echo "   • Visualize method-specific taxonomic composition"
echo "   • Understand why different methods may identify different species"
echo ""
echo "🔗 Next steps:"
echo "   • Open method-specific Krona HTML files for comparison"
echo "   • Analyze species abundance patterns between methods"
echo "   • Compare classification rates and species diversity"
echo "   • Use 6-column files for downstream ecological analysis"
echo ""