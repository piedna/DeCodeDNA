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
echo "════════════════════════════════════════════════════════════════════════"
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
BLAST_DIR="$OUTPUT_DIR/01_blast_results"
KRAKEN_DIR="$OUTPUT_DIR/02_kraken2_results"
TAXONOMY_DIR="$OUTPUT_DIR/03_final_taxonomy"
KRONA_DIR="$OUTPUT_DIR/04_krona_plots"
TEMP_DIR="$OUTPUT_DIR/00_temp_files"

mkdir -p "$BLAST_DIR" "$KRAKEN_DIR" "$TAXONOMY_DIR" "$KRONA_DIR" "$TEMP_DIR"

echo "📁 Organized output structure:"
echo "   • BLAST results    → $BLAST_DIR"
echo "   • Kraken2 results  → $KRAKEN_DIR"
echo "   • Final taxonomy   → $TAXONOMY_DIR" 
echo "   • Krona plots      → $KRONA_DIR"
echo "   • Temp files       → $TEMP_DIR"
echo ""

# ─── find and combine input files from multi-database structure (EXACT SAME LOGIC AS BACKUP) ─────────
echo "🔍 Looking for multi-database denoised files..."

# Check for nested directory structure (common issue)
ACTUAL_DENOISE_DIR="$DENOISE_DIR"
if [[ -d "$DENOISE_DIR/results" ]] && [[ -d "$DENOISE_DIR/results/04_denoise" ]]; then
  echo "  📁 Detected nested directory structure"
  ACTUAL_DENOISE_DIR="$DENOISE_DIR/results/04_denoise"
  echo "  🔄 Using: $ACTUAL_DENOISE_DIR"
elif [[ ! -d "$DENOISE_DIR/12s" ]] && [[ ! -d "$DENOISE_DIR/coi" ]] && [[ ! -d "$DENOISE_DIR/mitofish" ]]; then
  echo "❌ Error: No database directories found in $DENOISE_DIR"
  echo "Expected: $DENOISE_DIR/{12s,coi,mitofish}/"
  echo "Available:"
  ls -la "$DENOISE_DIR/" || echo "Directory not accessible"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
# ─── COMBINE VSEARCH FILES FROM ALL DATABASES ────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

# Combine all vsearch representative sequences from all databases
VSEARCH_REP_FASTA="$TEMP_DIR/all_databases_vsearch_representatives.fasta"
> "$VSEARCH_REP_FASTA"

# Combine all vsearch OTU tables from all databases  
VSEARCH_OTU_TABLE="$TEMP_DIR/all_databases_vsearch_otu_table.csv"
echo "OTU_ID,Sample1,Sample2,Sample3" > "$VSEARCH_OTU_TABLE"

databases_found_vsearch=0

for db in 12s coi mitofish; do
  db_dir="$ACTUAL_DENOISE_DIR/$db"
  if [[ -d "$db_dir" ]]; then
    echo "  📁 Found database directory: $db"
    
    # Look for vsearch representative sequences
    rep_fasta=$(find "$db_dir" -name "*representatives*${db}_vsearch.fasta" | head -n1 || true)
    if [[ -n "$rep_fasta" && -f "$rep_fasta" ]]; then
      echo "    ✓ Adding vsearch representatives: $(basename "$rep_fasta")"
      cat "$rep_fasta" >> "$VSEARCH_REP_FASTA"
    fi
    
    # Look for vsearch curated OTU table
    otu_table=$(find "$db_dir" -name "*${db}_vsearch_lulu_curated.csv" | head -n1 || true)
    if [[ -n "$otu_table" && -f "$otu_table" ]]; then
      echo "    ✓ Adding vsearch OTU table: $(basename "$otu_table")"
      # Skip header and append data
      tail -n +2 "$otu_table" >> "$VSEARCH_OTU_TABLE"
      databases_found_vsearch=$((databases_found_vsearch + 1))
    fi
  fi
done

if [[ $databases_found_vsearch -eq 0 ]]; then
  echo "❌ Error: No vsearch database results found in $ACTUAL_DENOISE_DIR"
  echo "Expected structure: $ACTUAL_DENOISE_DIR/{12s,coi,mitofish}/ with *_vsearch_lulu_curated.csv files"
else
  echo "✔ Combined vsearch representatives: $VSEARCH_REP_FASTA"
  echo "✔ Combined vsearch OTU table: $VSEARCH_OTU_TABLE"
  
  # Show vsearch summary
  vsearch_rep_count=$(grep -c "^>" "$VSEARCH_REP_FASTA")
  vsearch_otu_count=$(tail -n +2 "$VSEARCH_OTU_TABLE" | wc -l)
  echo "📊 vsearch dataset: $vsearch_rep_count sequences, $vsearch_otu_count OTUs from $databases_found_vsearch databases"
fi

# ═══════════════════════════════════════════════════════════════════════════
# ─── COMBINE AMPLICON_SORTER FILES FROM ALL DATABASES ────────────────────
# ═══════════════════════════════════════════════════════════════════════════

# Combine all amplicon_sorter representative sequences from all databases
AMPLICON_REP_FASTA="$TEMP_DIR/all_databases_amplicon_sorter_representatives.fasta"
> "$AMPLICON_REP_FASTA"

# Combine all amplicon_sorter OTU tables from all databases  
AMPLICON_OTU_TABLE="$TEMP_DIR/all_databases_amplicon_sorter_otu_table.csv"
echo "OTU_ID,Sample1,Sample2,Sample3" > "$AMPLICON_OTU_TABLE"

databases_found_amplicon=0

for db in 12s coi mitofish; do
  db_dir="$ACTUAL_DENOISE_DIR/$db"
  if [[ -d "$db_dir" ]]; then
    
    # Look for amplicon_sorter representative sequences
    rep_fasta=$(find "$db_dir" -name "*representatives*${db}_amplicon_sorter.fasta" | head -n1 || true)
    if [[ -n "$rep_fasta" && -f "$rep_fasta" ]]; then
      echo "    ✓ Adding amplicon_sorter representatives: $(basename "$rep_fasta")"
      cat "$rep_fasta" >> "$AMPLICON_REP_FASTA"
    fi
    
    # Look for amplicon_sorter curated OTU table
    otu_table=$(find "$db_dir" -name "*${db}_amplicon_sorter_lulu_curated.csv" | head -n1 || true)
    if [[ -n "$otu_table" && -f "$otu_table" ]]; then
      echo "    ✓ Adding amplicon_sorter OTU table: $(basename "$otu_table")"
      # Skip header and append data
      tail -n +2 "$otu_table" >> "$AMPLICON_OTU_TABLE"
      databases_found_amplicon=$((databases_found_amplicon + 1))
    fi
  fi
done

if [[ $databases_found_amplicon -eq 0 ]]; then
  echo "❌ Error: No amplicon_sorter database results found in $ACTUAL_DENOISE_DIR"
  echo "Expected structure: $ACTUAL_DENOISE_DIR/{12s,coi,mitofish}/ with *_amplicon_sorter_lulu_curated.csv files"
else
  echo "✔ Combined amplicon_sorter representatives: $AMPLICON_REP_FASTA"
  echo "✔ Combined amplicon_sorter OTU table: $AMPLICON_OTU_TABLE"
  
  # Show amplicon_sorter summary
  amplicon_rep_count=$(grep -c "^>" "$AMPLICON_REP_FASTA")
  amplicon_otu_count=$(tail -n +2 "$AMPLICON_OTU_TABLE" | wc -l)
  echo "📊 amplicon_sorter dataset: $amplicon_rep_count sequences, $amplicon_otu_count OTUs from $databases_found_amplicon databases"
fi

# Check if we have at least one method
if [[ $databases_found_vsearch -eq 0 ]] && [[ $databases_found_amplicon -eq 0 ]]; then
  echo "❌ Error: No method results found"
  exit 1
fi

echo ""

# ─── subset sequences for teaching speed ─────────────────────────────────
SUBSET_COUNT="${SUBSET_COUNT:-2000}"
THREADS="${THREADS:-8}"
EVALUE="${EVALUE:-1e-20}"
MAX_HITS="${MAX_HITS:-5}"

# Create subsets for both methods if they exist
if [[ $databases_found_vsearch -gt 0 ]]; then
  VSEARCH_SUBSET_FASTA="$TEMP_DIR/vsearch_query_sequences_subset${SUBSET_COUNT}.fasta"
  echo "🎓 Creating vsearch subset of $SUBSET_COUNT sequences for classroom speed"
  awk -v N="$SUBSET_COUNT" '
    BEGIN { RS=">"; ORS="" }
    NR>1 && N-->0 { print ">" $0 }
  ' "$VSEARCH_REP_FASTA" > "$VSEARCH_SUBSET_FASTA"

  vsearch_subset_count=$(grep -c "^>" "$VSEARCH_SUBSET_FASTA")
  echo "   ✓ Using $vsearch_subset_count vsearch sequences for analysis"
fi

if [[ $databases_found_amplicon -gt 0 ]]; then
  AMPLICON_SUBSET_FASTA="$TEMP_DIR/amplicon_sorter_query_sequences_subset${SUBSET_COUNT}.fasta"
  echo "🎓 Creating amplicon_sorter subset of $SUBSET_COUNT sequences for classroom speed"
  awk -v N="$SUBSET_COUNT" '
    BEGIN { RS=">"; ORS="" }
    NR>1 && N-->0 { print ">" $0 }
  ' "$AMPLICON_REP_FASTA" > "$AMPLICON_SUBSET_FASTA"

  amplicon_subset_count=$(grep -c "^>" "$AMPLICON_SUBSET_FASTA")
  echo "   ✓ Using $amplicon_subset_count amplicon_sorter sequences for analysis"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 1: BLAST ANALYSIS (SAME LOGIC AS BACKUP, BUT FOR BOTH METHODS) ──
# ═══════════════════════════════════════════════════════════════════════════

echo "🧬 PART 1: BLAST TAXONOMIC ASSIGNMENT FOR BOTH METHODS"
echo "════════════════════════════════════════════════════════════════"

# ─── run BLAST against each database for vsearch ────────────────────────
if [[ $databases_found_vsearch -gt 0 ]]; then
  echo "=== BLAST Analysis for vsearch ==="
  for DB in 12s coi mitofish; do
    echo "--- BLAST vsearch against $DB database ---"
    DB_PATH="$BLAST_DB_ROOT/$DB/$DB"
    
    if [[ ! -f "${DB_PATH}.nsq" && ! -f "${DB_PATH}.nin" ]]; then
      echo "❌ BLAST DB not found: $DB_PATH"
      echo "   Run script 01 to build databases first"
      continue
    fi

    BLAST_OUT="$BLAST_DIR/vsearch_${DB}_blast_hits.tsv"
    
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
  echo ""
fi

# ─── run BLAST against each database for amplicon_sorter ─────────────────
if [[ $databases_found_amplicon -gt 0 ]]; then
  echo "=== BLAST Analysis for amplicon_sorter ==="
  for DB in 12s coi mitofish; do
    echo "--- BLAST amplicon_sorter against $DB database ---"
    DB_PATH="$BLAST_DB_ROOT/$DB/$DB"
    
    if [[ ! -f "${DB_PATH}.nsq" && ! -f "${DB_PATH}.nin" ]]; then
      echo "❌ BLAST DB not found: $DB_PATH"
      continue
    fi

    BLAST_OUT="$BLAST_DIR/amplicon_sorter_${DB}_blast_hits.tsv"
    
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
fi

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 2: KRAKEN2 ANALYSIS (SAME LOGIC AS BACKUP, BUT FOR BOTH METHODS) ─
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
  # ─── run Kraken2 against available databases for vsearch ────────────────
  if [[ $databases_found_vsearch -gt 0 ]]; then
    echo ""
    echo "=== Kraken2 Classification for vsearch ==="
    for DB in 12s coi mitofish; do
      echo "--- Kraken2 vsearch against $DB database ---"
      KRAKEN_DB_PATH="$KRAKEN_DB_ROOT/$DB"
      
      if [[ ! -d "$KRAKEN_DB_PATH" ]] || [[ ! -f "$KRAKEN_DB_PATH/taxo.k2d" ]]; then
        echo "❌ Kraken2 DB not found: $KRAKEN_DB_PATH"
        echo "   Run script 01 to build databases first"
        continue
      fi

      KRAKEN_OUT="$KRAKEN_DIR/vsearch_${DB}_kraken2_output.txt"
      KRAKEN_REPORT="$KRAKEN_DIR/vsearch_${DB}_kraken2_report.txt"
      
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
      echo "   ✓ Results → $KRAKEN_OUT"
      echo "   ✓ Report  → $KRAKEN_REPORT"

      # ─── create Krona plot for vsearch ───────────────────────────────────
      if [[ "${SKIP_KRONA:-false}" != "true" ]] && [[ -s "$KRAKEN_REPORT" ]]; then
        echo "   • Creating vsearch Krona plot..."
        KRONA_HTML="$KRONA_DIR/vsearch_${DB}_krona_plot.html"
        
        # Convert Kraken2 report to Krona format
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

        # Convert and create Krona plot
        krona_input="$TEMP_DIR/vsearch_${DB}_krona_input.txt"
        python3 "$TEMP_DIR/kraken2_to_krona.py" "$KRAKEN_REPORT" "$krona_input"
        
        if [[ -s "$krona_input" ]]; then
          ktImportText -o "$KRONA_HTML" "$krona_input"
          echo "   ✓ vsearch Krona plot → $KRONA_HTML"
        else
          echo "   ⚠️  No data for vsearch Krona plot (no classifications)"
        fi
      fi
    done
  fi

  # ─── run Kraken2 against available databases for amplicon_sorter ────────
  if [[ $databases_found_amplicon -gt 0 ]]; then
    echo ""
    echo "=== Kraken2 Classification for amplicon_sorter ==="
    for DB in 12s coi mitofish; do
      echo "--- Kraken2 amplicon_sorter against $DB database ---"
      KRAKEN_DB_PATH="$KRAKEN_DB_ROOT/$DB"
      
      if [[ ! -d "$KRAKEN_DB_PATH" ]] || [[ ! -f "$KRAKEN_DB_PATH/taxo.k2d" ]]; then
        echo "❌ Kraken2 DB not found: $KRAKEN_DB_PATH"
        continue
      fi

      KRAKEN_OUT="$KRAKEN_DIR/amplicon_sorter_${DB}_kraken2_output.txt"
      KRAKEN_REPORT="$KRAKEN_DIR/amplicon_sorter_${DB}_kraken2_report.txt"
      
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
      echo "   ✓ Results → $KRAKEN_OUT"
      echo "   ✓ Report  → $KRAKEN_REPORT"

      # ─── create Krona plot for amplicon_sorter ───────────────────────────
      if [[ "${SKIP_KRONA:-false}" != "true" ]] && [[ -s "$KRAKEN_REPORT" ]]; then
        echo "   • Creating amplicon_sorter Krona plot..."
        KRONA_HTML="$KRONA_DIR/amplicon_sorter_${DB}_krona_plot.html"
        
        # Convert and create Krona plot
        krona_input="$TEMP_DIR/amplicon_sorter_${DB}_krona_input.txt"
        python3 "$TEMP_DIR/kraken2_to_krona.py" "$KRAKEN_REPORT" "$krona_input"
        
        if [[ -s "$krona_input" ]]; then
          ktImportText -o "$KRONA_HTML" "$krona_input"
          echo "   ✓ amplicon_sorter Krona plot → $KRONA_HTML"
        else
          echo "   ⚠️  No data for amplicon_sorter Krona plot (no classifications)"
        fi
      fi
    done
  fi
else
  echo "⚠️  Skipping Kraken2 analysis - kraken2 not found"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 3: PROCESS AND COMBINE RESULTS (SAME R SCRIPT LOGIC AS BACKUP) ──
# ═══════════════════════════════════════════════════════════════════════════

echo "📊 PART 3: PROCESSING TAXONOMIC RESULTS FOR BOTH METHODS"
echo "═══════════════════════════════════════════════════════════════════"

# ─── create comprehensive taxonomy processing script (EXACT SAME AS BACKUP) ───
cat > "$TEMP_DIR/process_complete_taxonomy.R" << 'EOF'
library(dplyr)
library(readr)
library(tidyr)
library(stringr)

# Read command line arguments
args <- commandArgs(trailingOnly = TRUE)
method_name <- args[1]  # "vsearch" or "amplicon_sorter"
otu_file <- args[2]
blast_dir <- args[3] 
kraken_dir <- args[4]
taxonomy_dir <- args[5]

cat("📊 Processing", method_name, "taxonomic results...\n\n")

# Read OTU table
cat("Reading", method_name, "OTU table:", otu_file, "\n")
otu_data <- read_csv(otu_file, show_col_types = FALSE)

# Clean column names and remove quotes
names(otu_data)[1] <- "OTU_ID"
otu_data$OTU_ID <- gsub('"', '', otu_data$OTU_ID)

# Convert to long format
otu_long <- otu_data %>%
  pivot_longer(-OTU_ID, names_to = "Sample", values_to = "Count") %>%
  filter(Count > 0)

cat("Processing", nrow(otu_long), method_name, "OTU abundance records\n\n")

# ═══ PROCESS BLAST RESULTS ═══
cat("🧬 Processing", method_name, "BLAST results...\n")
blast_summary <- data.frame()

for (db in c("12s", "coi", "mitofish")) {
  blast_file <- file.path(blast_dir, paste0(method_name, "_", db, "_blast_hits.tsv"))
  
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
        # FIXED: Extract species from hit_id (database header) instead of using accession
        species = case_when(
          # For 12s and COI databases: format is "accession_Genus_species"
          db %in% c("12s", "coi") ~ str_extract(hit_id, "[A-Z][a-z]+_[a-z]+"),
          # For mitofish database: format is "gb_accession_Genus_species"  
          db == "mitofish" ~ str_extract(hit_id, "(?:gb_[^_]+_)?([A-Z][a-z]+_[a-z]+)") %>% str_remove("gb_[^_]+_"),
          TRUE ~ hit_id
        ),
        # Clean up species names
        species = ifelse(is.na(species) | species == "", 
                        paste0("unknown_", row_number()), 
                        species),
        database = db,
        method = method_name,
        assignment_status = "classified"
      ) %>%
      select(OTU_ID, species, pct_identity, bitscore, database, method, assignment_status)
    
    cat("  •", method_name, db, ":", nrow(best_hits), "OTUs classified\n")
    
    # Merge with abundance data
    taxonomy_result <- otu_long %>%
      left_join(best_hits, by = "OTU_ID") %>%
      mutate(
        species = ifelse(is.na(species), "unclassified", species),
        database = db,
        method = method_name,
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
    blast_classified_file <- file.path(taxonomy_dir, paste0("BLAST_", method_name, "_", db, "_classified_species.csv"))
    blast_full_file <- file.path(taxonomy_dir, paste0("BLAST_", method_name, "_", db, "_full_taxonomy.csv"))
    
    if (nrow(blast_species_matrix) > 0) {
      write_csv(taxonomy_result, blast_full_file)
    
    # Add to summary
    classified_otus <- sum(taxonomy_result$assignment_status == "classified")
    total_otus <- nrow(taxonomy_result)
    classification_rate <- round(100 * classified_otus / total_otus, 1)
    
    blast_summary <- bind_rows(blast_summary, data.frame(
      database = db,
      method = method_name,
      total_otus = total_otus,
      classified_otus = classified_otus,
      classification_rate = classification_rate,
      unique_species = nrow(blast_species_matrix)
    ))
  }
}

# ═══ PROCESS KRAKEN2 RESULTS ═══
cat("\n🦠 Processing", method_name, "Kraken2 results...\n")
kraken_summary <- data.frame()

for (db in c("12s", "coi", "mitofish")) {
  kraken_file <- file.path(kraken_dir, paste0(method_name, "_", db, "_kraken2_output.txt"))
  kraken_report_file <- file.path(kraken_dir, paste0(method_name, "_", db, "_kraken2_report.txt"))
  
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
          method = method_name,
          assignment_status = "classified"
        ) %>%
        select(OTU_ID, species, taxid, database, method, assignment_status)
      
      cat("  •", method_name, db, ":", nrow(kraken_classified), "OTUs classified\n")
      
      # Merge with abundance data
      kraken_taxonomy_result <- otu_long %>%
        left_join(kraken_classified, by = "OTU_ID") %>%
        mutate(
          species = ifelse(is.na(species), "unclassified", species),
          database = db,
          method = method_name,
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
      kraken_classified_file <- file.path(taxonomy_dir, paste0("Kraken2_", method_name, "_", db, "_classified_species.csv"))
      kraken_full_file <- file.path(taxonomy_dir, paste0("Kraken2_", method_name, "_", db, "_full_taxonomy.csv"))
      
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
        method = method_name,
        total_otus = total_otus,
        classified_otus = classified_otus,
        classification_rate = classification_rate,
        unique_species = nrow(kraken_species_matrix)
      ))
    }
  }
}

# ═══ CREATE COMPARISON SUMMARY ═══
cat("\n📈 Creating", method_name, "method summary...\n")
method_comparison <- bind_rows(blast_summary, kraken_summary)

if (nrow(method_comparison) > 0) {
  write_csv(method_comparison, file.path(taxonomy_dir, paste0(method_name, "_method_summary.csv")))
  
  cat("\n📊", method_name, "Method Summary:\n")
  print(method_comparison)
} else {
  cat("⚠️  No", method_name, "results to compare\n")
}

cat("\n✅", method_name, "taxonomy processing complete!\n")
EOF

# Process vsearch results if available
if [[ $databases_found_vsearch -gt 0 ]]; then
  echo "   • Processing vsearch taxonomic results..."
  Rscript "$TEMP_DIR/process_complete_taxonomy.R" \
    "vsearch" \
    "$VSEARCH_OTU_TABLE" \
    "$BLAST_DIR" \
    "$KRAKEN_DIR" \
    "$TAXONOMY_DIR"
  echo ""
fi

# Process amplicon_sorter results if available
if [[ $databases_found_amplicon -gt 0 ]]; then
  echo "   • Processing amplicon_sorter taxonomic results..."
  Rscript "$TEMP_DIR/process_complete_taxonomy.R" \
    "amplicon_sorter" \
    "$AMPLICON_OTU_TABLE" \
    "$BLAST_DIR" \
    "$KRAKEN_DIR" \
    "$TAXONOMY_DIR"
  echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 4: CREATE FINAL 6-COLUMN COMBINED OUTPUT ───────────────────────
# ═══════════════════════════════════────────────────────────════────────────

echo "🔄 PART 4: CREATING FINAL 6-COLUMN COMBINED OUTPUT"
echo "════════════════════════════════════════════════════════════════"

# Create R script to combine results into 6-column format
cat > "$TEMP_DIR/create_6column_output.R" << 'EOF'
library(dplyr)
library(readr)
library(tidyr)

args <- commandArgs(trailingOnly = TRUE)
taxonomy_dir <- args[1]
vsearch_available <- as.logical(args[2])
amplicon_available <- as.logical(args[3])

cat("🔄 Creating final 6-column combined results...\n")
cat("  vsearch available:", vsearch_available, "\n")
cat("  amplicon_sorter available:", amplicon_available, "\n\n")

# Function to read method results
read_method_results <- function(method_name) {
  results <- list()
  
  for (db in c("12s", "coi", "mitofish")) {
    for (assignment_method in c("BLAST", "Kraken2")) {
      file_pattern <- paste0(assignment_method, "_", method_name, "_", db, "_classified_species.csv")
      file_path <- file.path(taxonomy_dir, file_pattern)
      
      if (file.exists(file_path) && file.size(file_path) > 0) {
        cat("  Reading:", file_pattern, "\n")
        
        data <- read_csv(file_path, show_col_types = FALSE)
        
        # Only process if we have the expected columns
        if (ncol(data) >= 4) {  # species + 3 sample columns
          key <- paste(assignment_method, db, sep="_")
          results[[key]] <- data
        }
      }
    }
  }
  
  return(results)
}

# Read results from both methods if available
vsearch_results <- list()
amplicon_results <- list()

if (vsearch_available) {
  cat("📊 Reading vsearch results...\n")
  vsearch_results <- read_method_results("vsearch")
}

if (amplicon_available) {
  cat("\n🎯 Reading amplicon_sorter results...\n")
  amplicon_results <- read_method_results("amplicon_sorter")
}

# Combine results for each database and assignment method
cat("\n🔄 Combining into 6-column format...\n")

for (db in c("12s", "coi", "mitofish")) {
  for (assignment_method in c("BLAST", "Kraken2")) {
    cat("  Processing", assignment_method, db, "...\n")
    
    key <- paste(assignment_method, db, sep="_")
    
    # Get data for this combination
    vsearch_data <- if (key %in% names(vsearch_results)) vsearch_results[[key]] else NULL
    amplicon_data <- if (key %in% names(amplicon_results)) amplicon_results[[key]] else NULL
    
    # Create combined data
    combined_data <- NULL
    
    if (!is.null(vsearch_data) && !is.null(amplicon_data)) {
      # Both methods have data - full join
      combined_data <- full_join(
        select(vsearch_data, species, Sample1, Sample2, Sample3) %>% 
          rename(Sample1_vsearch = Sample1, Sample2_vsearch = Sample2, Sample3_vsearch = Sample3),
        select(amplicon_data, species, Sample1, Sample2, Sample3) %>%
          rename(Sample1_amplicon_sorter = Sample1, Sample2_amplicon_sorter = Sample2, Sample3_amplicon_sorter = Sample3),
        by = "species"
      )
    } else if (!is.null(vsearch_data)) {
      # Only vsearch data
      combined_data <- vsearch_data %>%
        select(species, Sample1, Sample2, Sample3) %>%
        rename(Sample1_vsearch = Sample1, Sample2_vsearch = Sample2, Sample3_vsearch = Sample3) %>%
        mutate(
          Sample1_amplicon_sorter = 0,
          Sample2_amplicon_sorter = 0,
          Sample3_amplicon_sorter = 0
        )
    } else if (!is.null(amplicon_data)) {
      # Only amplicon_sorter data
      combined_data <- amplicon_data %>%
        select(species, Sample1, Sample2, Sample3) %>%
        rename(Sample1_amplicon_sorter = Sample1, Sample2_amplicon_sorter = Sample2, Sample3_amplicon_sorter = Sample3) %>%
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
      
      # Reorder columns in the desired 6-column format
      combined_data <- combined_data %>%
        select(species, Sample1_vsearch, Sample2_vsearch, Sample3_vsearch, 
               Sample1_amplicon_sorter, Sample2_amplicon_sorter, Sample3_amplicon_sorter) %>%
        arrange(desc(Sample1_vsearch + Sample2_vsearch + Sample3_vsearch + 
                    Sample1_amplicon_sorter + Sample2_amplicon_sorter + Sample3_amplicon_sorter))
      
      # Save file
      output_file <- file.path(taxonomy_dir, paste0("Final_", assignment_method, "_", db, "_6columns.csv"))
      write_csv(combined_data, output_file)
      
      cat("    ✓ Saved:", basename(output_file), "- ", nrow(combined_data), "species\n")
    } else {
      cat("    ⚠️  No data available for", assignment_method, db, "\n")
    }
  }
}

# Create overall method comparison summary
cat("\n📈 Creating overall method comparison...\n")
overall_summary <- data.frame()

# Read method summaries
if (vsearch_available) {
  vsearch_summary_file <- file.path(taxonomy_dir, "vsearch_method_summary.csv")
  if (file.exists(vsearch_summary_file)) {
    vsearch_summary <- read_csv(vsearch_summary_file, show_col_types = FALSE)
    overall_summary <- bind_rows(overall_summary, vsearch_summary)
  }
}

if (amplicon_available) {
  amplicon_summary_file <- file.path(taxonomy_dir, "amplicon_sorter_method_summary.csv")
  if (file.exists(amplicon_summary_file)) {
    amplicon_summary <- read_csv(amplicon_summary_file, show_col_types = FALSE)
    overall_summary <- bind_rows(overall_summary, amplicon_summary)
  }
}

if (nrow(overall_summary) > 0) {
  write_csv(overall_summary, file.path(taxonomy_dir, "Overall_Method_Comparison.csv"))
  cat("✓ Saved: Overall_Method_Comparison.csv\n")
  
  cat("\n📊 Final Method Comparison:\n")
  print(overall_summary)
}

cat("\n✅ Final 6-column output created successfully!\n")
cat("\nColumns in final files:\n")
cat("1. species\n")
cat("2. Sample1_vsearch\n")
cat("3. Sample2_vsearch\n")
cat("4. Sample3_vsearch\n")
cat("5. Sample1_amplicon_sorter\n")
cat("6. Sample2_amplicon_sorter\n")
cat("7. Sample3_amplicon_sorter\n")
EOF

# Run the 6-column combination script
echo "   • Creating final 6-column combined files..."
Rscript "$TEMP_DIR/create_6column_output.R" \
  "$TAXONOMY_DIR" \
  "$([[ $databases_found_vsearch -gt 0 ]] && echo "TRUE" || echo "FALSE")" \
  "$([[ $databases_found_amplicon -gt 0 ]] && echo "TRUE" || echo "FALSE")"

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── FINAL SUMMARY AND RESULTS ────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🎉 SEPARATE METHOD TAXONOMIC ASSIGNMENT COMPLETE!"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo "📁 Results organized in:"
echo "   🧬 BLAST results      → $BLAST_DIR"
echo "   🦠 Kraken2 results    → $KRAKEN_DIR"
echo "   📊 Final taxonomy     → $TAXONOMY_DIR" 
echo "   🍩 Krona plots        → $KRONA_DIR"
echo "   🗂️  Temp files        → $TEMP_DIR"
echo ""

echo "📋 Key 6-column output files:"
echo "   Format: species, Sample1_vsearch, Sample2_vsearch, Sample3_vsearch, Sample1_amplicon_sorter, Sample2_amplicon_sorter, Sample3_amplicon_sorter"
echo ""

for db in 12s coi mitofish; do
  for method in BLAST Kraken2; do
    final_file="$TAXONOMY_DIR/Final_${method}_${db}_6columns.csv"
    if [[ -f "$final_file" ]]; then
      species_count=$(tail -n +2 "$final_file" | wc -l 2>/dev/null || echo "0")
      echo "   • Final_${method}_${db}_6columns.csv - $species_count species"
    fi
  done
done

echo ""
echo "📈 Method Comparison:"
if [[ -f "$TAXONOMY_DIR/Overall_Method_Comparison.csv" ]]; then
  echo "   • Overall_Method_Comparison.csv - Compare vsearch vs amplicon_sorter performance"
fi

if [[ "${SKIP_KRONA:-false}" != "true" ]]; then
  echo ""
  echo "🍩 Krona Plots (Method-specific):"
  for db in 12s coi mitofish; do
    if [[ $databases_found_vsearch -gt 0 ]] && [[ -f "$KRONA_DIR/vsearch_${db}_krona_plot.html" ]]; then
      echo "   • vsearch_${db}_krona_plot.html"
    fi
    if [[ $databases_found_amplicon -gt 0 ]] && [[ -f "$KRONA_DIR/amplicon_sorter_${db}_krona_plot.html" ]]; then
      echo "   • amplicon_sorter_${db}_krona_plot.html"
    fi
  done
fi

echo ""
echo "🎓 For the class:"
echo "   • Compare vsearch vs amplicon_sorter clustering methods side-by-side"
echo "   • 6-column format allows direct abundance comparison between methods"
echo "   • Each method processed independently through entire pipeline"
echo "   • Method-specific Krona plots show taxonomic composition differences"
echo ""
echo "🔗 Next steps:"
echo "   • Open Final_*_6columns.csv files to compare method performance"
echo "   • Use 6-column format for ecological analysis (e.g., community composition)"
echo "   • Compare classification rates between vsearch and amplicon_sorter"
echo "   • Analyze which species are detected by one method vs both"
echo ""blast_species_matrix, blast_classified_file)
    } else {
      empty_df <- data.frame(species = character(0), Sample1 = numeric(0), Sample2 = numeric(0), Sample3 = numeric(0))
      write_csv(empty_df, blast_classified_file)
    }
    
    write_csv(#!/usr/bin/env bash
set -euo pipefail

# ─── usage ────────────────────────────────────────────────────────────────
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <DENOISE_DIR> <OUTPUT_DIR>"