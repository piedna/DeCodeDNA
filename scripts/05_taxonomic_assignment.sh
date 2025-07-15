#!/usr/bin/env bash
set -euo pipefail

# ─── usage ────────────────────────────────────────────────────────────────
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <DENOISE_DIR> <OUTPUT_DIR>"
  exit 1
fi
DENOISE_DIR="$1"
OUTPUT_DIR="$2"

# ─── locate project & databases ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BLAST_DB_ROOT="${BLAST_DB_ROOT:-$PROJECT_ROOT/../blast_db}"
KRAKEN_DB_ROOT="${KRAKEN_DB_ROOT:-$PROJECT_ROOT/../kraken2_db}"

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

# ─── find input files ────────────────────────────────────────────────────
REP_FASTA=$(find "$DENOISE_DIR" -maxdepth 1 -type f -iname "*.fasta" | head -n1 || true)
if [[ -z "$REP_FASTA" ]]; then
  echo "❌ Error: no .fasta file found in $DENOISE_DIR"
  exit 1
fi
echo "✔ Found reps FASTA: $REP_FASTA"

OTU_TABLE=$(find "$DENOISE_DIR" -maxdepth 1 -type f \( -iname "*.csv" -o -iname "*.tsv" \) \
  | grep -v -i discarded | head -n1 || true)
if [[ -z "$OTU_TABLE" ]]; then
  echo "❌ Error: no .csv or .tsv OTU table found in $DENOISE_DIR"
  exit 1
fi
echo "✔ Found OTU table: $OTU_TABLE"

# ─── subset sequences for teaching speed ─────────────────────────────────
SUBSET_COUNT="${SUBSET_COUNT:-2000}"
SUBSET_FASTA="$TEMP_DIR/query_sequences_subset${SUBSET_COUNT}.fasta"
echo "🎓 Creating subset of $SUBSET_COUNT sequences for classroom speed"
awk -v N="$SUBSET_COUNT" '
  BEGIN { RS=">"; ORS="" }
  NR>1 && N-->0 { print ">" $0 }
' "$REP_FASTA" > "$SUBSET_FASTA"

subset_count=$(grep -c "^>" "$SUBSET_FASTA")
echo "   ✓ Using $subset_count sequences for analysis"
echo ""

# ─── blast parameters ────────────────────────────────────────────────────
THREADS="${THREADS:-8}"
EVALUE="${EVALUE:-1e-20}"
MAX_HITS="${MAX_HITS:-5}"

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 1: BLAST ANALYSIS ───────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🧬 PART 1: BLAST TAXONOMIC ASSIGNMENT"
echo "════════════════════════════════════════"

# ─── run BLAST against each database ─────────────────────────────────────
for DB in 12s coi mitofish; do
  echo "=== BLAST against $DB database ==="
  DB_PATH="$BLAST_DB_ROOT/$DB/$DB"
  
  if [[ ! -f "${DB_PATH}.nsq" && ! -f "${DB_PATH}.nin" ]]; then
    echo "❌ BLAST DB not found: $DB_PATH"
    continue
  fi

  BLAST_OUT="$BLAST_DIR/${DB}_blast_hits.tsv"
  
  echo "   • Running BLAST (top $MAX_HITS hits)..."
  blastn -task megablast \
         -db "$DB_PATH" \
         -query "$SUBSET_FASTA" \
         -max_target_seqs "$MAX_HITS" \
         -evalue "$EVALUE" \
         -outfmt "6 qseqid sseqid pident length bitscore staxids stitle" \
         -num_threads "$THREADS" \
         -out "$BLAST_OUT"

  hit_count=$(wc -l < "$BLAST_OUT" 2>/dev/null || echo "0")
  echo "   ✓ Found $hit_count BLAST hits → $BLAST_OUT"
done

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 2: KRAKEN2 ANALYSIS ─────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🦠 PART 2: KRAKEN2 TAXONOMIC CLASSIFICATION"
echo "═══════════════════════════════════════════════"

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
  # ─── run Kraken2 against available databases ────────────────────────────
  for DB in 12s coi mitofish; do
    echo ""
    echo "=== Kraken2 classification against $DB database ==="
    KRAKEN_DB_PATH="$KRAKEN_DB_ROOT/$DB"
    
    if [[ ! -d "$KRAKEN_DB_PATH" ]] || [[ ! -f "$KRAKEN_DB_PATH/taxo.k2d" ]]; then
      echo "❌ Kraken2 DB not found: $KRAKEN_DB_PATH"
      echo "   Run script 00 with Kraken2 enabled to build databases"
      continue
    fi

    KRAKEN_OUT="$KRAKEN_DIR/${DB}_kraken2_output.txt"
    KRAKEN_REPORT="$KRAKEN_DIR/${DB}_kraken2_report.txt"
    
    echo "   • Running Kraken2 classification..."
    kraken2 --db "$KRAKEN_DB_PATH" \
            --threads "$THREADS" \
            --output "$KRAKEN_OUT" \
            --report "$KRAKEN_REPORT" \
            "$SUBSET_FASTA"

    # Count classifications
    classified_count=$(grep -c "^C" "$KRAKEN_OUT" 2>/dev/null || echo "0")
    total_count=$(wc -l < "$KRAKEN_OUT" 2>/dev/null || echo "0")
    
    if [[ "$total_count" -gt 0 ]]; then
      classification_rate=$(echo "scale=1; $classified_count * 100 / $total_count" | bc -l 2>/dev/null || echo "0")
    else
      classification_rate="0"
    fi
    
    echo "   ✓ Classified $classified_count/$total_count sequences (${classification_rate}%)"
    echo "   ✓ Results → $KRAKEN_OUT"
    echo "   ✓ Report  → $KRAKEN_REPORT"

    # ─── create Krona plot ───────────────────────────────────────────────
    if [[ "${SKIP_KRONA:-false}" != "true" ]] && [[ -s "$KRAKEN_REPORT" ]]; then
      echo "   • Creating Krona plot..."
      KRONA_HTML="$KRONA_DIR/${DB}_krona_plot.html"
      
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
      krona_input="$TEMP_DIR/${DB}_krona_input.txt"
      python3 "$TEMP_DIR/kraken2_to_krona.py" "$KRAKEN_REPORT" "$krona_input"
      
      if [[ -s "$krona_input" ]]; then
        ktImportText -o "$KRONA_HTML" "$krona_input"
        echo "   ✓ Krona plot → $KRONA_HTML"
      else
        echo "   ⚠️  No data for Krona plot (no classifications)"
      fi
    fi
  done
else
  echo "⚠️  Skipping Kraken2 analysis - kraken2 not found"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 3: PROCESS AND COMBINE RESULTS ─────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "📊 PART 3: PROCESSING TAXONOMIC RESULTS"
echo "═══════════════════════════════════════════"

# ─── create comprehensive taxonomy processing script ─────────────────────
cat > "$TEMP_DIR/process_complete_taxonomy.R" << 'EOF'
library(dplyr)
library(readr)
library(tidyr)

# Read command line arguments
args <- commandArgs(trailingOnly = TRUE)
otu_file <- args[1]
blast_dir <- args[2] 
kraken_dir <- args[3]
taxonomy_dir <- args[4]

cat("📊 Processing comprehensive taxonomic results...\n\n")

# Read OTU table
cat("Reading OTU table:", otu_file, "\n")
otu_data <- read_csv(otu_file, show_col_types = FALSE)

# Clean column names and remove quotes
names(otu_data)[1] <- "OTU_ID"
otu_data$OTU_ID <- gsub('"', '', otu_data$OTU_ID)

# Convert to long format
otu_long <- otu_data %>%
  pivot_longer(-OTU_ID, names_to = "Sample", values_to = "Count") %>%
  filter(Count > 0)

cat("Processing", nrow(otu_long), "OTU abundance records\n\n")

# ═══ PROCESS BLAST RESULTS ═══
cat("🧬 Processing BLAST results...\n")
blast_summary <- data.frame()

for (db in c("12s", "coi", "mitofish")) {
  blast_file <- file.path(blast_dir, paste0(db, "_blast_hits.tsv"))
  
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
        species = hit_id,
        database = db,
        method = "BLAST",
        assignment_status = "classified"
      ) %>%
      select(OTU_ID, species, pct_identity, bitscore, database, method, assignment_status)
    
    cat("  •", db, ":", nrow(best_hits), "OTUs classified\n")
    
    # Merge with abundance data
    taxonomy_result <- otu_long %>%
      left_join(best_hits, by = "OTU_ID") %>%
      mutate(
        species = ifelse(is.na(species), "unclassified", species),
        database = db,
        method = "BLAST",
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
    blast_classified_file <- file.path(taxonomy_dir, paste0("BLAST_", db, "_classified_species.csv"))
    blast_full_file <- file.path(taxonomy_dir, paste0("BLAST_", db, "_full_taxonomy.csv"))
    
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
      method = "BLAST",
      total_otus = total_otus,
      classified_otus = classified_otus,
      classification_rate = classification_rate,
      unique_species = nrow(blast_species_matrix)
    ))
  }
}

# ═══ PROCESS KRAKEN2 RESULTS ═══
cat("\n🦠 Processing Kraken2 results...\n")
kraken_summary <- data.frame()

for (db in c("12s", "coi", "mitofish")) {
  kraken_file <- file.path(kraken_dir, paste0(db, "_kraken2_output.txt"))
  kraken_report_file <- file.path(kraken_dir, paste0(db, "_kraken2_report.txt"))
  
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
          method = "Kraken2",
          assignment_status = "classified"
        ) %>%
        select(OTU_ID, species, taxid, database, method, assignment_status)
      
      cat("  •", db, ":", nrow(kraken_classified), "OTUs classified\n")
      
      # Merge with abundance data
      kraken_taxonomy_result <- otu_long %>%
        left_join(kraken_classified, by = "OTU_ID") %>%
        mutate(
          species = ifelse(is.na(species), "unclassified", species),
          database = db,
          method = "Kraken2",
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
      kraken_classified_file <- file.path(taxonomy_dir, paste0("Kraken2_", db, "_classified_species.csv"))
      kraken_full_file <- file.path(taxonomy_dir, paste0("Kraken2_", db, "_full_taxonomy.csv"))
      
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
        method = "Kraken2",
        total_otus = total_otus,
        classified_otus = classified_otus,
        classification_rate = classification_rate,
        unique_species = nrow(kraken_species_matrix)
      ))
    }
  }
}

# ═══ CREATE COMPARISON SUMMARY ═══
cat("\n📈 Creating method comparison summary...\n")
method_comparison <- bind_rows(blast_summary, kraken_summary)

if (nrow(method_comparison) > 0) {
  write_csv(method_comparison, file.path(taxonomy_dir, "method_comparison_summary.csv"))
  
  cat("\n📊 Method Comparison Summary:\n")
  print(method_comparison)
} else {
  cat("⚠️  No results to compare\n")
}

cat("\n✅ Comprehensive taxonomy processing complete!\n")
EOF

# Run the comprehensive R script
echo "   • Processing BLAST and Kraken2 results..."
Rscript "$TEMP_DIR/process_complete_taxonomy.R" "$OTU_TABLE" "$BLAST_DIR" "$KRAKEN_DIR" "$TAXONOMY_DIR"

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── FINAL SUMMARY AND RESULTS ────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo "🎉 COMPREHENSIVE TAXONOMIC ASSIGNMENT COMPLETE!"
echo "════════════════════════════════════════════════════"
echo ""
echo "📁 Results organized in:"
echo "   🧬 BLAST results      → $BLAST_DIR/"
echo "   🦠 Kraken2 results    → $KRAKEN_DIR/"
echo "   📊 Final taxonomy     → $TAXONOMY_DIR/"
echo "   🍩 Krona plots        → $KRONA_DIR/"
echo "   🗂️  Temp files        → $TEMP_DIR/"
echo ""

echo "📋 Key output files:"

echo ""
echo "🧬 BLAST Results:"
for db in 12s coi mitofish; do
  blast_classified_file="$TAXONOMY_DIR/BLAST_${db}_classified_species.csv"
  if [[ -f "$blast_classified_file" ]]; then
    species_count=$(tail -n +2 "$blast_classified_file" | wc -l 2>/dev/null || echo "0")
    echo "   • BLAST_${db}_classified_species.csv - $species_count species"
  fi
done

if [[ "${SKIP_KRAKEN:-false}" != "true" ]]; then
  echo ""
  echo "🦠 Kraken2 Results:"
  for db in 12s coi mitofish; do
    kraken_classified_file="$TAXONOMY_DIR/Kraken2_${db}_classified_species.csv"
    if [[ -f "$kraken_classified_file" ]]; then
      species_count=$(tail -n +2 "$kraken_classified_file" | wc -l 2>/dev/null || echo "0")
      echo "   • Kraken2_${db}_classified_species.csv - $species_count species"
    fi
  done
fi

if [[ "${SKIP_KRONA:-false}" != "true" ]]; then
  echo ""
  echo "🍩 Krona Plots:"
  for db in 12s coi mitofish; do
    krona_file="$KRONA_DIR/${db}_krona_plot.html"
    if [[ -f "$krona_file" ]]; then
      echo "   • ${db}_krona_plot.html - Open in browser for interactive visualization"
    fi
  done
fi

echo ""
echo "📈 Method Comparison:"
if [[ -f "$TAXONOMY_DIR/method_comparison_summary.csv" ]]; then
  echo "   • method_comparison_summary.csv - Compare BLAST vs Kraken2 performance"
fi

echo ""
echo "🎓 For the class:"
echo "   • Compare BLAST vs Kraken2 classification methods"
echo "   • Visualize taxonomic composition with Krona plots"
echo "   • Understand why COI = 0 for 12S mock community data"
echo "   • See effects of quality filtering on taxonomic assignments"
echo ""
echo "🔗 Next steps:"
echo "   • Open Krona HTML files in browser for interactive exploration"
echo "   • Analyze species abundance patterns across samples"
echo "   • Compare classification rates between methods and databases"
echo ""
