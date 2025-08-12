#!/usr/bin/env bash
set -euo pipefail

# ─── usage ────────────────────────────────────────────────────────────────
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <DENOISE_DIR> <OUTPUT_DIR>"
  echo "Example: $0 results/04_denoise results/05_taxonomy"
  echo ""
  echo "Environment variables:"
  echo "  SUBSET_COUNT - Limit number of sequences to process (default: 0 = all sequences)"
  echo "  Example: export SUBSET_COUNT=1000"
  exit 1
fi
DENOISE_DIR="$1"
OUTPUT_DIR="$2"

# ─── locate project & databases (SELF-CONTAINED) ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Database locations (created by script 01)
BLAST_DB_ROOT="${BLAST_DB_ROOT:-$PROJECT_ROOT/../databases/blast_db}"
KRAKEN_DB_ROOT="${DB_ROOT:-$PROJECT_ROOT/../databases/kraken2_db}"

# Set BLASTDB environment for taxonomy support
export BLASTDB="$BLAST_DB_ROOT"

echo " DeCodeDNA Taxonomic Assignment - BLAST + TaxonKit LCA + KRAKEN2"
echo "════════════════════════════════════════════════════════════════════════"
echo " Denoise input:    $DENOISE_DIR"
echo " Output directory: $OUTPUT_DIR"
echo " BLAST databases:  $BLAST_DB_ROOT"
echo " Kraken2 databases: $KRAKEN_DB_ROOT"
echo " BLASTDB environment: $BLASTDB"
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

echo " Organized output structure:"
echo "   • BLAST results    → $BLAST_DIR"
echo "   • Kraken2 results  → $KRAKEN_DIR"
echo "   • Final taxonomy   → $TAXONOMY_DIR" 
echo "   • Krona plots      → $KRONA_DIR"
echo "   • Temp files       → $TEMP_DIR"
echo ""

# ─── find and combine input files from multi-database structure ─────────
echo " Looking for multi-database denoised files..."

# Check for nested directory structure (common issue)
ACTUAL_DENOISE_DIR="$DENOISE_DIR"
if [[ -d "$DENOISE_DIR/results" ]] && [[ -d "$DENOISE_DIR/results/04_denoise" ]]; then
  echo "   Detected nested directory structure"
  ACTUAL_DENOISE_DIR="$DENOISE_DIR/results/04_denoise"
  echo "   Using: $ACTUAL_DENOISE_DIR"
elif [[ ! -d "$DENOISE_DIR/12s" ]] && [[ ! -d "$DENOISE_DIR/coi" ]] && [[ ! -d "$DENOISE_DIR/mitofish" ]]; then
  echo "❌ Error: No database directories found in $DENOISE_DIR"
  echo "Expected: $DENOISE_DIR/{12s,coi,mitofish}/"
  echo "Available:"
  ls -la "$DENOISE_DIR/" || echo "Directory not accessible"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
# ─── DYNAMIC SAMPLE DETECTION ─────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo " Detecting REAL sample names from OTU tables..."
REAL_SAMPLE_NAMES=()
SAMPLE_HEADER=""

# Find the first available OTU table to get real sample names
FIRST_OTU_TABLE=""
for db in 12s coi mitofish; do
  potential_table="$ACTUAL_DENOISE_DIR/$db/otu_table_${db}_vsearch_lulu_curated.csv"
  if [[ -f "$potential_table" ]]; then
    FIRST_OTU_TABLE="$potential_table"
    echo "  Detecting sample names from: $(basename "$FIRST_OTU_TABLE")"
    break
  fi
done

if [[ -f "$FIRST_OTU_TABLE" ]]; then
    # Extract the real header and sample names
    SAMPLE_HEADER=$(head -n1 "$FIRST_OTU_TABLE")
    echo "  ✓ Real sample header detected: $SAMPLE_HEADER"
    
    # Parse sample names (skip first column which is OTU_ID) - macOS compatible
    IFS=',' read -ra HEADER_ARRAY <<< "$SAMPLE_HEADER"
    for i in "${!HEADER_ARRAY[@]}"; do
        if [[ $i -gt 0 ]]; then  # Skip first column (OTU_ID)
            sample_name="${HEADER_ARRAY[$i]}"
            # Clean up sample name (remove quotes and X prefix)
            sample_name=$(echo "$sample_name" | sed 's/^"//; s/"$//; s/^X//')
            REAL_SAMPLE_NAMES+=("$sample_name")
        fi
    done
    
    echo "  ✓ Detected ${#REAL_SAMPLE_NAMES[@]} real samples: ${REAL_SAMPLE_NAMES[*]}"
else
    echo "  ⚠️  No OTU tables found, using fallback sample names"
    REAL_SAMPLE_NAMES=("18" "2" "4")
    SAMPLE_HEADER="OTU_ID,X18,X2,X4"
fi

# Create sample name variables for later use
SAMPLE_COUNT=${#REAL_SAMPLE_NAMES[@]}
echo "   Processing $SAMPLE_COUNT samples with real names"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── COMBINE VSEARCH FILES FROM ALL DATABASES ────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

# Combine all vsearch representative sequences from all databases
VSEARCH_REP_FASTA="$TEMP_DIR/all_databases_vsearch_representatives.fasta"
> "$VSEARCH_REP_FASTA"

# Combine all vsearch OTU tables from all databases  
VSEARCH_OTU_TABLE="$TEMP_DIR/all_databases_vsearch_otu_table.csv"
echo "$SAMPLE_HEADER" > "$VSEARCH_OTU_TABLE"

databases_found_vsearch=0

for db in 12s coi mitofish; do
  db_dir="$ACTUAL_DENOISE_DIR/$db"
  if [[ -d "$db_dir" ]]; then
    echo "   Found database directory: $db"
    
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
  exit 1
else
  echo "✔ Combined vsearch representatives: $VSEARCH_REP_FASTA"
  echo "✔ Combined vsearch OTU table: $VSEARCH_OTU_TABLE"
  
  # Show vsearch summary
  vsearch_rep_count=$(grep -c "^>" "$VSEARCH_REP_FASTA")
  vsearch_otu_count=$(tail -n +2 "$VSEARCH_OTU_TABLE" | wc -l)
  echo " vsearch dataset: $vsearch_rep_count sequences, $vsearch_otu_count OTUs from $databases_found_vsearch databases"
fi

echo ""

# ─── SUBSET OPTION - LIMIT SEQUENCES IF REQUESTED ─────────────────────────
THREADS="${THREADS:-8}"
EVALUE="${EVALUE:-1e-40}"
MAX_HITS="${MAX_HITS:-50}"
SUBSET_COUNT="${SUBSET_COUNT:-0}"  # Default to 0 (no limit)

if [[ "$SUBSET_COUNT" -gt 0 ]]; then
  echo " Subsetting to $SUBSET_COUNT sequences (SUBSET_COUNT=$SUBSET_COUNT)"
  
  # Create subset FASTA file
  VSEARCH_SUBSET_FASTA="$TEMP_DIR/vsearch_subset_${SUBSET_COUNT}.fasta"
  
  # Use seqtk to randomly sample sequences (if available)
  if command -v seqtk >/dev/null 2>&1; then
    echo "   • Using seqtk for random sampling..."
    seqtk sample "$VSEARCH_REP_FASTA" "$SUBSET_COUNT" > "$VSEARCH_SUBSET_FASTA"
  else
    # Fallback: take first N sequences
    echo "   • Taking first $SUBSET_COUNT sequences (seqtk not available for random sampling)"
    awk -v count="$SUBSET_COUNT" '
      /^>/ { if (seq_count >= count) exit; seq_count++ }
      { print }
    ' "$VSEARCH_REP_FASTA" > "$VSEARCH_SUBSET_FASTA"
  fi
  
  vsearch_subset_count=$(grep -c "^>" "$VSEARCH_SUBSET_FASTA")
  echo "   ✓ Created subset with $vsearch_subset_count sequences"
else
  # Use ALL sequences (original behavior)
  VSEARCH_SUBSET_FASTA="$VSEARCH_REP_FASTA"
  vsearch_subset_count=$(grep -c "^>" "$VSEARCH_SUBSET_FASTA")
  echo " Using ALL $vsearch_subset_count vsearch sequences for analysis (no subset limit)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 1: BLAST ANALYSIS ───────────
# ═══════════════════════════════════════════════════════════════════════════

echo " PART 1: BLAST ANALYSIS "
echo "════════════════════════════════════════════════════════════════"

# Create combined BLAST output following your approach
COMBINED_BLAST_OUT="$BLAST_DIR/otu_euk_blast_combined.out"

echo "=== Running BLAST against all databases for TaxonKit LCA processing ==="

# Run BLAST against all databases and combine results
> "$COMBINED_BLAST_OUT"
for DB in 12s coi mitofish; do
  echo "--- BLAST against $DB database ---"
  DB_PATH="$BLAST_DB_ROOT/$DB/$DB"
  
  if [[ ! -f "${DB_PATH}.nsq" && ! -f "${DB_PATH}.nin" ]]; then
    echo "❌ BLAST DB not found: $DB_PATH"
    continue
  fi

  BLAST_OUT="$BLAST_DIR/vsearch_${DB}_blast_hits.tsv"
  
  echo "   • Running BLAST (top $MAX_HITS hits, e-value $EVALUE)..."
  blastn -task megablast \
         -db "$DB_PATH" \
         -query "$VSEARCH_SUBSET_FASTA" \
         -max_target_seqs "$MAX_HITS" \
         -evalue "$EVALUE" \
         -perc_identity 96 \
         -word_size 30 \
         -culling_limit 50 \
         -outfmt '6 sscinames scomnames qseqid sseqid pident length mismatch gapopen qcovus qstart qend sstart send evalue bitscore staxids qlen qcovs' \
         -num_threads "$THREADS" \
         -out "$BLAST_OUT"

  hit_count=$(wc -l < "$BLAST_OUT" 2>/dev/null || echo "0")
  echo "   ✓ Found $hit_count BLAST hits → $BLAST_OUT"
  
  # Append to combined file
  cat "$BLAST_OUT" >> "$COMBINED_BLAST_OUT"
done

combined_hit_count=$(wc -l < "$COMBINED_BLAST_OUT" 2>/dev/null || echo "0")
echo "✓ Combined BLAST results: $combined_hit_count total hits → $COMBINED_BLAST_OUT"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 2: TAXONKIT LCA PROCESSING ────────
# ═══════════════════════════════════════════════════════════════════════════

echo " PART 2: TaxonKit LCA Processing "
echo "════════════════════════════════════════════════════════════════"

# Check if TaxonKit is available
if command -v taxonkit >/dev/null 2>&1; then
  echo "✅ TaxonKit found - processing BLAST results for LCA consensus"
  
  # Comprehensive LCA processing following co-author's approach
  CDIR="$OUTPUT_DIR" VSEARCH_OTU_TABLE="$VSEARCH_OTU_TABLE" python3 <<'PYCODE'
import os, subprocess, pandas as pd
from datetime import datetime

CD = os.environ["CDIR"]
BLAST = os.path.join(CD, "01_blast_results/otu_euk_blast_combined.out")
T1 = os.path.join(CD, "00_temp_files/taxids_for_lca.txt")
RAW = os.path.join(CD, "00_temp_files/lca_raw.txt")
LIN = os.path.join(CD, "00_temp_files/lca_lineage.txt")
DB_OUT = os.path.join(CD, "03_final_taxonomy/Comprehensive_OTU_Database.csv")
ABUNDANCE_OUT = os.path.join(CD, "03_final_taxonomy/TaxonKit_LCA_species_abundance.csv")

# Read OTU table for sample names
otu_table_file = os.environ["VSEARCH_OTU_TABLE"]
otu_data = pd.read_csv(otu_table_file)
otu_data.columns = [col.strip().strip('"') for col in otu_data.columns]
otu_data.iloc[:, 0] = otu_data.iloc[:, 0].astype(str).str.strip().str.strip('"')

print(f"Processing OTU table: {otu_data.shape[0]} OTUs, {otu_data.shape[1]-1} samples")

# Read BLAST results
cols = ["Taxon","CommonName","Hash","Accession","pident","length",
        "mismatch","gapopen","qcovus","qstart","qend","sstart","send",
        "evalue","bitscore","staxids","qlen","qcovs"]

if os.path.exists(BLAST) and os.path.getsize(BLAST) > 0:
    df = pd.read_csv(BLAST, sep="\t", names=cols, dtype=str)
    df["pident"] = df["pident"].astype(float)
    print(f"Loaded {len(df)} BLAST hits")
else:
    print("No BLAST results found")
    exit(1)

# Remove unconfirmed sequences (like co-author's script)
df = df[~df['Accession'].str.match('^(XM_|XP_|XR_)', na=False)]
print(f"After removing unconfirmed sequences: {len(df)} hits")

# Apply hierarchical filtering (exactly like co-author's script)
SP_THOLD = 97  # Species threshold
result_list = {}

for hash_id in df['Hash'].unique():
    hash_hits = df[df['Hash'] == hash_id]
    
    # Step 1: 100% identity
    selected_hits = hash_hits[hash_hits['pident'] == 100]
    
    # Step 2: >99.3% identity
    if len(selected_hits) == 0:
        selected_hits = hash_hits[hash_hits['pident'] > 99.3]
    
    # Step 3: >98% identity
    if len(selected_hits) == 0:
        selected_hits = hash_hits[hash_hits['pident'] > 98]
    
    # Step 4: >96% identity
    if len(selected_hits) == 0:
        selected_hits = hash_hits[hash_hits['pident'] > 96]
    
    # Step 5: >94% identity
    if len(selected_hits) == 0:
        selected_hits = hash_hits[hash_hits['pident'] > 94]
    
    # Step 6: Use all hits
    if len(selected_hits) == 0:
        selected_hits = hash_hits
    
    result_list[hash_id] = selected_hits

# Combine selected data
selected_data = pd.concat(result_list.values(), ignore_index=True)
print(f"After hierarchical filtering: {len(selected_data)} selected hits")

# Compute max pident per Hash
max_pident_df = selected_data.groupby('Hash')['pident'].max().reset_index()
max_pident_df.columns = ['Hash', 'Max_pident']

# Build taxid list for LCA
a = (selected_data[['Hash', 'staxids']]
     .dropna()
     .drop_duplicates()
     .groupby('Hash')['staxids']
     .apply(lambda x: ' '.join(x).replace(';', ' '))
     .reset_index()
     .rename(columns={'staxids': 'tax_list'}))

# Summarize other fields like co-author's script
tax_list_df = (selected_data[['Hash', 'Taxon']]
               .dropna()
               .drop_duplicates()
               .groupby('Hash')['Taxon']
               .apply(lambda x: ', '.join(x))
               .reset_index()
               .rename(columns={'Taxon': 'Tax_list'}))

mismatch_df = (selected_data[['Hash', 'mismatch']]
               .dropna()
               .drop_duplicates()
               .groupby('Hash')['mismatch']
               .apply(lambda x: ', '.join(x))
               .reset_index()
               .rename(columns={'mismatch': 'Mismatches'}))

acc_df = (selected_data[['Hash', 'Accession']]
          .dropna()
          .drop_duplicates()
          .groupby('Hash')['Accession']
          .apply(lambda x: ', '.join(x))
          .reset_index()
          .rename(columns={'Accession': 'AccessionNumbers'}))

# Write taxids for TaxonKit LCA
with open(T1, "w") as w:
    for _, row in a.iterrows():
        w.write(f"{row['Hash']}\t{row['tax_list']}\n")

print(f"Wrote taxid input for {len(a)} OTUs")

# Run TaxonKit
subprocess.run(["taxonkit", "lca", "-i", "2", "-o", RAW, T1], check=True)
subprocess.run(["taxonkit", "reformat", "-I", "3", "-o", LIN, RAW], check=True)

# Load LCA results
lca = pd.read_csv(LIN, sep="\t", header=None,
                  names=["Hash", "BlastTaxIDs", "LCA_taxid", "Lineage"],
                  dtype=str).fillna("")

ranks = ["Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"]
lineage_parts = lca['Lineage'].str.split(';', expand=True)
for i, rank in enumerate(ranks):
    lca[rank] = lineage_parts[i] if i < lineage_parts.shape[1] else ""

# Merge everything together (like co-author's script)
f = (tax_list_df
     .merge(mismatch_df, on='Hash', how='left')
     .merge(lca, on='Hash', how='left')
     .merge(acc_df, on='Hash', how='left')
     .merge(max_pident_df, on='Hash', how='left')
     .fillna(''))

# Filter out empty orders (like co-author's script)
f = f[f['Order'] != '']

# Apply species threshold logic
f['Species'] = f.apply(lambda row: '' if row['Max_pident'] < SP_THOLD else row['Species'], axis=1)

# Create BestTaxon with hierarchical fallback
def get_best_taxon(row):
    if row['Species'] and row['Species'] != '':
        return row['Species']
    elif row['Genus'] and row['Genus'] != '':
        return row['Genus']
    elif row['Family'] and row['Family'] != '':
        return row['Family']
    elif row['Order'] and row['Order'] != '':
        return row['Order']
    else:
        return 'unclassified'

f['BestTaxon'] = f.apply(get_best_taxon, axis=1)

# Add haplotype numbers (like co-author's script)
f['HaplotypeNumber'] = f.groupby('BestTaxon').cumcount() + 1

# Add sequences and date
f['Sequence'] = ''  # Add sequences later if needed
f['DateAdded'] = datetime.now().strftime('%Y-%m-%d')

# Reorder columns like co-author's output
column_order = ['Hash', 'BestTaxon', 'HaplotypeNumber', 'Tax_list', 'Mismatches', 
                'BlastTaxIDs', 'LCA_taxid', 'Kingdom', 'Phylum', 'Class', 'Order', 
                'Family', 'Genus', 'Species', 'AccessionNumbers', 'Max_pident', 
                'Sequence', 'DateAdded']

f = f.reindex(columns=column_order).fillna('')

# Save comprehensive database
f.to_csv(DB_OUT, index=False)
print(f"✅ Saved comprehensive database: {DB_OUT} ({len(f)} records)")

# Create species abundance matrix for backwards compatibility
def extract_final_species(row):
    if row['Species'] and row['Species'] != '':
        return row['Species']
    elif row['Genus'] and row['Genus'] != '':
        return f"{row['Genus']} sp."
    elif row['Family'] and row['Family'] != '':
        return f"{row['Family']} family"
    else:
        return "unclassified"

f['final_species'] = f.apply(extract_final_species, axis=1)

# Merge with OTU abundances
otu_long = otu_data.melt(id_vars=[otu_data.columns[0]], 
                        var_name='Sample', 
                        value_name='Count')
otu_long.columns = ['Hash', 'Sample', 'Count']

result = otu_long.merge(f[['Hash', 'final_species']], on='Hash', how='left')
result['final_species'] = result['final_species'].fillna('unclassified')

# Create species abundance matrix
species_matrix = result.groupby(['final_species', 'Sample'])['Count'].sum().reset_index()
species_wide = species_matrix.pivot(index='final_species', columns='Sample', values='Count').fillna(0)
species_wide = species_wide.reset_index()

# Save species abundance matrix
species_wide.to_csv(ABUNDANCE_OUT, index=False)
print(f"✅ Saved species abundance matrix: {ABUNDANCE_OUT} ({len(species_wide)} species)")

print("\n🎉 TaxonKit LCA analysis complete with comprehensive database!")
PYCODE

  echo "✅ TaxonKit LCA analysis complete!"

else
  echo "⚠️  TaxonKit not found - skipping LCA analysis"
  echo "    Install with: conda install -c bioconda taxonkit"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 3: KRAKEN2 ANALYSIS (FOLLOWING OLD SCRIPT) ─────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo " PART 3: KRAKEN2 ANALYSIS"
echo "═══════════════════════════════════════════════════════════════════════"

# Check for Kraken2 and KronaTools
echo " Checking required tools..."
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
  echo ""
  echo " Creating per-sample FASTA files for Kraken2..."
  
  # Use the working Python script from your old script
  cat > "$TEMP_DIR/split_fasta_by_sample.py" << 'EOF'
#!/usr/bin/env python3
import sys
import pandas as pd
from collections import defaultdict

def split_fasta_by_sample(otu_table_file, fasta_file, sample_names, output_dir):
    """Split combined FASTA into per-sample files based on OTU abundance"""
    
    # Read OTU table
    print(f"Reading OTU table: {otu_table_file}")
    otu_data = pd.read_csv(otu_table_file)
    
    # Clean column names
    otu_data.columns = [col.strip().strip('"') for col in otu_data.columns]
    otu_data.iloc[:, 0] = otu_data.iloc[:, 0].astype(str).str.strip().str.strip('"')
    
    print(f"OTU table columns: {list(otu_data.columns)}")
    print(f"Sample names provided: {sample_names}")
    
    # Create sample-to-OTU mapping
    sample_otus = defaultdict(list)
    
    for _, row in otu_data.iterrows():
        otu_id = row.iloc[0]  # First column is OTU_ID
        
        for sample in sample_names:
            # Look for column matching sample (with or without X prefix)
            sample_col = None
            for col in otu_data.columns[1:]:  # Skip OTU_ID column
                if col == sample or col == f"X{sample}":
                    sample_col = col
                    break
            
            if sample_col and row[sample_col] > 0:
                abundance = int(row[sample_col])
                # Add OTU to sample list (repeat for abundance)
                for _ in range(abundance):
                    sample_otus[sample].append(otu_id)
    
    # Read FASTA and split by sample
    print(f"Reading FASTA: {fasta_file}")
    fasta_sequences = {}
    
    with open(fasta_file, 'r') as f:
        current_header = None
        current_seq = ""
        
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                if current_header and current_seq:
                    # Extract OTU_ID from header
                    otu_id = current_header[1:]  # Remove >
                    fasta_sequences[otu_id] = current_seq
                
                current_header = line
                current_seq = ""
            else:
                current_seq += line
        
        # Process last sequence
        if current_header and current_seq:
            otu_id = current_header[1:]
            fasta_sequences[otu_id] = current_seq
    
    print(f"Found {len(fasta_sequences)} FASTA sequences")
    
    # Write per-sample FASTA files
    for sample in sample_names:
        sample_fasta = f"{output_dir}/vsearch_{sample}_sequences.fasta"
        
        with open(sample_fasta, 'w') as f:
            written_count = 0
            for otu_id in sample_otus[sample]:
                if otu_id in fasta_sequences:
                    f.write(f">{otu_id}_{written_count}\n")
                    f.write(f"{fasta_sequences[otu_id]}\n")
                    written_count += 1
        
        print(f"Created {sample_fasta} with {written_count} sequences")

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python3 split_fasta_by_sample.py <otu_table> <fasta_file> <sample_names> <output_dir>")
        sys.exit(1)
    
    otu_table_file = sys.argv[1]
    fasta_file = sys.argv[2]
    sample_names = sys.argv[3].split(',')
    output_dir = sys.argv[4]
    
    split_fasta_by_sample(otu_table_file, fasta_file, sample_names, output_dir)
EOF

  # Create per-sample FASTA files
  sample_names_str=$(IFS=','; echo "${REAL_SAMPLE_NAMES[*]}")
  python3 "$TEMP_DIR/split_fasta_by_sample.py" \
    "$VSEARCH_OTU_TABLE" \
    "$VSEARCH_SUBSET_FASTA" \
    "$sample_names_str" \
    "$TEMP_DIR"
  
  echo ""
  echo "=== Running Kraken2 on per-sample sequences ==="
  
  for DB in 12s coi mitofish; do
    echo "--- Kraken2 against $DB database ---"
    KRAKEN_DB_PATH="$KRAKEN_DB_ROOT/$DB"
    
    if [[ ! -d "$KRAKEN_DB_PATH" ]] || [[ ! -f "$KRAKEN_DB_PATH/taxo.k2d" ]]; then
      echo "❌ Kraken2 DB not found: $KRAKEN_DB_PATH"
      continue
    fi
    
    # Run Kraken2 for each sample separately
    for sample in "${REAL_SAMPLE_NAMES[@]}"; do
      sample_fasta="$TEMP_DIR/vsearch_${sample}_sequences.fasta"
      
      if [[ -f "$sample_fasta" ]] && [[ -s "$sample_fasta" ]]; then
        echo "   • Running Kraken2 for sample $sample against $DB..."
        
        KRAKEN_OUT="$KRAKEN_DIR/vsearch_${sample}_${DB}_kraken2_output.txt"
        KRAKEN_REPORT="$KRAKEN_DIR/vsearch_${sample}_${DB}_kraken2_report.txt"
        
        kraken2 --db "$KRAKEN_DB_PATH" \
                --threads "$THREADS" \
                --output "$KRAKEN_OUT" \
                --report "$KRAKEN_REPORT" \
                "$sample_fasta"
        
        # Count classifications
        classified_count=$(grep -c "^C" "$KRAKEN_OUT" 2>/dev/null || echo "0")
        total_count=$(wc -l < "$KRAKEN_OUT" 2>/dev/null || echo "0")
        
        if [[ "$total_count" -gt 0 ]]; then
          classification_rate=$(echo "scale=1; $classified_count * 100 / $total_count" | bc -l 2>/dev/null || echo "0")
        else
          classification_rate="0"
        fi
        
        echo "     ✓ Sample $sample: $classified_count/$total_count classified (${classification_rate}%)"
        
        # Create per-sample Krona plot
        if [[ "${SKIP_KRONA:-false}" != "true" ]] && [[ -s "$KRAKEN_REPORT" ]]; then
          echo "     • Creating Krona plot for sample $sample..."
          
          KRONA_HTML="$KRONA_DIR/vsearch_sample_${sample}_${DB}_krona.html"
          
          # Convert Kraken2 report to Krona format
          cat > "$TEMP_DIR/kraken2_to_krona.py" << 'KRONA_EOF'
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
KRONA_EOF

          # Convert and create Krona plot
          krona_input="$TEMP_DIR/vsearch_${sample}_${DB}_krona_input.txt"
          python3 "$TEMP_DIR/kraken2_to_krona.py" "$KRAKEN_REPORT" "$krona_input"
          
          if [[ -s "$krona_input" ]]; then
            ktImportText -o "$KRONA_HTML" "$krona_input"
            echo "     ✓ Sample $sample Krona plot → $(basename "$KRONA_HTML")"
          else
            echo "     ⚠️  No data for sample $sample Krona plot"
          fi
        fi
      else
        echo "   ⚠️  No sequences for sample $sample - skipping"
      fi
    done
  done
else
  echo "⚠️  Skipping Kraken2 analysis - kraken2 not found"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── PART 4: PROCESS TAXONOMIC RESULTS ─────────────
# ═══════════════════════════════════════════════════════════════════════════

echo " PART 4: PROCESSING TAXONOMIC RESULTS"
echo "═══════════════════════════════════════════════════════════════════"

# Create comprehensive taxonomy processing script following the old script exactly
cat > "$TEMP_DIR/process_complete_taxonomy.R" << 'EOF'
library(dplyr)
library(readr)
library(tidyr)
library(stringr)

# Read command line arguments
args <- commandArgs(trailingOnly = TRUE)
otu_file <- args[1]
blast_dir <- args[2] 
kraken_dir <- args[3]
taxonomy_dir <- args[4]
sample_names_str <- args[5]

sample_names <- unlist(strsplit(sample_names_str, ","))
cat(" Processing taxonomic results for samples:", paste(sample_names, collapse = ", "), "\n\n")

# Read OTU table
cat("Reading OTU table:", otu_file, "\n")
otu_data <- read_csv(otu_file, show_col_types = FALSE)

# Clean column names and remove quotes
names(otu_data)[1] <- "OTU_ID"
otu_data$OTU_ID <- gsub('"', '', otu_data$OTU_ID)

# Clean sample column names (remove X prefix)
for (i in 2:ncol(otu_data)) {
  names(otu_data)[i] <- sub("^X", "", names(otu_data)[i])
}

cat("Cleaned column names:", paste(names(otu_data), collapse = ", "), "\n")

# Convert to long format
otu_long <- otu_data %>%
  pivot_longer(-OTU_ID, names_to = "Sample", values_to = "Count") %>%
  filter(Count > 0)

cat("Processing", nrow(otu_long), "OTU abundance records\n\n")

# ═══ PROCESS BLAST RESULTS ═══
cat(" Processing BLAST results...\n")
blast_summary <- data.frame()

for (db in c("12s", "coi", "mitofish")) {
  blast_file <- file.path(blast_dir, paste0("vsearch_", db, "_blast_hits.tsv"))
  
  if (file.exists(blast_file) && file.size(blast_file) > 0) {
    # Read BLAST results with exact column names from your script
    blast_data <- read_tsv(blast_file, 
      col_names = c("Taxon", "CommonName", "Hash", "Accession", "pident", "length", 
                   "mismatch", "gapopen", "qcovus", "qstart", "qend", "sstart", 
                   "send", "evalue", "bitscore", "staxids", "qlen", "qcovs"),
      col_types = cols(), show_col_types = FALSE)
    
    # Rename Hash to OTU_ID for consistency
    blast_data <- blast_data %>% rename(OTU_ID = Hash)
    
    # Take best hit per OTU (highest bitscore)
    best_hits <- blast_data %>%
      group_by(OTU_ID) %>%
      arrange(desc(bitscore), desc(pident)) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      mutate(
        # Use Taxon field directly as species name
        species = ifelse(is.na(Taxon) | Taxon == "", 
                        paste0("unknown_", row_number()), 
                        Taxon),
        database = db,
        assignment_status = "classified"
      ) %>%
      select(OTU_ID, species, pident, bitscore, database, assignment_status)
    
    cat("  • BLAST", db, ":", nrow(best_hits), "OTUs classified\n")
    
    # Merge with abundance data
    taxonomy_result <- otu_long %>%
      left_join(best_hits, by = "OTU_ID") %>%
      mutate(
        species = ifelse(is.na(species), "unclassified", species),
        database = db,
        assignment_status = ifelse(is.na(assignment_status), "unclassified", assignment_status)
      ) %>%
      select(OTU_ID, Sample, Count, species, pident, bitscore, database, assignment_status)
    
    # Create species abundance matrix for BLAST
    blast_species_matrix <- taxonomy_result %>%
      filter(assignment_status == "classified") %>%
      group_by(species, Sample) %>%
      summarise(Count = sum(Count), .groups = "drop") %>%
      pivot_wider(names_from = Sample, values_from = Count, values_fill = 0) %>%
      arrange(desc(rowSums(select(., -species))))
    
    # Save BLAST results
    blast_classified_file <- file.path(taxonomy_dir, paste0("BLAST_vsearch_", db, "_classified_species.csv"))
    blast_full_file <- file.path(taxonomy_dir, paste0("BLAST_vsearch_", db, "_full_taxonomy.csv"))
    
    if (nrow(blast_species_matrix) > 0) {    
      write_csv(blast_species_matrix, blast_classified_file)
      write_csv(taxonomy_result, blast_full_file)
    }
    
    # Add to summary
    classified_otus <- sum(taxonomy_result$assignment_status == "classified")
    total_otus <- length(unique(taxonomy_result$OTU_ID))
    classification_rate <- round(100 * classified_otus / total_otus, 1)
    
    blast_summary <- bind_rows(blast_summary, data.frame(
      database = db,
      method = "vsearch",
      assignment_method = "BLAST",
      total_otus = total_otus,
      classified_otus = classified_otus,
      classification_rate = classification_rate,
      unique_species = nrow(blast_species_matrix)
    ))
  }
}

# ═══ PROCESS KRAKEN2 RESULTS (PER-SAMPLE) ═══
cat("\n Processing per-sample Kraken2 results...\n")
kraken_summary <- data.frame()

for (db in c("12s", "coi", "mitofish")) {
  # Combine per-sample Kraken2 results
  all_kraken_results <- data.frame()
  
  for (sample in sample_names) {
    kraken_file <- file.path(kraken_dir, paste0("vsearch_", sample, "_", db, "_kraken2_output.txt"))
    kraken_report_file <- file.path(kraken_dir, paste0("vsearch_", sample, "_", db, "_kraken2_report.txt"))
    
    if (file.exists(kraken_file) && file.size(kraken_file) > 0) {
      # Read Kraken2 output for this sample
      kraken_data <- read_tsv(kraken_file,
        col_names = c("classified", "OTU_ID", "taxid", "length", "lca_mapping"),
        col_types = cols(), show_col_types = FALSE)
      
      # Read Kraken2 report for taxonomic names
      if (file.exists(kraken_report_file)) {
        kraken_taxa <- read_tsv(kraken_report_file,
          col_names = c("percentage", "clade_reads", "direct_reads", "rank", "taxid", "name"),
          col_types = cols(), show_col_types = FALSE) %>%
          mutate(name = trimws(name)) %>%
          filter(rank %in% c("S", "G")) %>%
          select(taxid, name)
        
        # Join classifications with taxonomic names
        sample_kraken_classified <- kraken_data %>%
          filter(classified == "C") %>%
          left_join(kraken_taxa, by = "taxid") %>%
          mutate(
            species = as.character(ifelse(is.na(name), paste0("taxid_", taxid), name)),
            database = db,
            sample = sample,
            assignment_status = "classified"
          ) %>%
          select(OTU_ID, species, taxid, database, sample, assignment_status)
        
        all_kraken_results <- bind_rows(all_kraken_results, sample_kraken_classified)
      }
    }
  }
  
  if (nrow(all_kraken_results) > 0) {
    cat("  • Kraken2", db, ":", nrow(all_kraken_results), "OTUs classified across all samples\n")
    
    # Merge with abundance data
    kraken_taxonomy_result <- otu_long %>%
      left_join(all_kraken_results, by = "OTU_ID") %>%
      mutate(
        species = ifelse(is.na(species), "unclassified", species),
        database = db,
        assignment_status = ifelse(is.na(assignment_status), "unclassified", assignment_status)
      ) %>%
      select(OTU_ID, Sample, Count, species, taxid, database, assignment_status)
    
    # Create species abundance matrix for Kraken2
    kraken_species_matrix <- kraken_taxonomy_result %>%
      filter(assignment_status == "classified") %>%
      group_by(species, Sample) %>%
      summarise(Count = sum(Count), .groups = "drop") %>%
      pivot_wider(names_from = Sample, values_from = Count, values_fill = 0) %>%
      arrange(desc(rowSums(select(., -species))))
    
    # Save Kraken2 results
    kraken_classified_file <- file.path(taxonomy_dir, paste0("Kraken2_vsearch_", db, "_classified_species.csv"))
    kraken_full_file <- file.path(taxonomy_dir, paste0("Kraken2_vsearch_", db, "_full_taxonomy.csv"))
    
    if (nrow(kraken_species_matrix) > 0) {
      write_csv(kraken_species_matrix, kraken_classified_file)
    }
    write_csv(kraken_taxonomy_result, kraken_full_file)
    
    # Add to summary
    classified_otus <- sum(kraken_taxonomy_result$assignment_status == "classified")
    total_otus <- length(unique(kraken_taxonomy_result$OTU_ID))
    classification_rate <- round(100 * classified_otus / total_otus, 1)
    
    kraken_summary <- bind_rows(kraken_summary, data.frame(
      database = db,
      method = "vsearch",
      assignment_method = "KRAKEN2",
      total_otus = total_otus,
      classified_otus = classified_otus,
      classification_rate = classification_rate,
      unique_species = nrow(kraken_species_matrix)
    ))
  }
}

# ═══ CREATE FINAL COMPARISON SUMMARY ═══
cat("\n Creating method summary...\n")
overall_summary <- bind_rows(blast_summary, kraken_summary)

if (nrow(overall_summary) > 0) {
  write_csv(overall_summary, file.path(taxonomy_dir, "Comprehensive_Method_Comparison.csv"))
  
  cat("\n Method Summary:\n")
  print(overall_summary)
}

cat("\n✅ Taxonomy processing complete!\n")
EOF

# Process results
echo "   • Processing comprehensive taxonomic results..."
Rscript "$TEMP_DIR/process_complete_taxonomy.R" \
  "$VSEARCH_OTU_TABLE" \
  "$BLAST_DIR" \
  "$KRAKEN_DIR" \
  "$TAXONOMY_DIR" \
  "$sample_names_str"

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ─── FINAL SUMMARY AND RESULTS ────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

echo " COMPREHENSIVE TAXONOMIC ASSIGNMENT COMPLETE!"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo " Results organized in:"
echo "    BLAST results      → $BLAST_DIR"
echo "    Kraken2 results    → $KRAKEN_DIR"
echo "    Final taxonomy     → $TAXONOMY_DIR" 
echo "    Krona plots        → $KRONA_DIR"
echo "    Temp files         → $TEMP_DIR"
echo ""

echo " Key output files with REAL sample names (${REAL_SAMPLE_NAMES[*]}):"
echo ""

# Show TaxonKit LCA results
echo " TaxonKit LCA Results:"
lca_file="$TAXONOMY_DIR/TaxonKit_LCA_species_abundance.csv"
comprehensive_db="$TAXONOMY_DIR/Comprehensive_OTU_Database.csv"

if [[ -f "$lca_file" ]]; then
  species_count=$(tail -n +2 "$lca_file" | wc -l 2>/dev/null || echo "0")
  echo "   ✅ TaxonKit_LCA_species_abundance.csv - $species_count species (CONSENSUS TAXONOMY)"
fi

if [[ -f "$comprehensive_db" ]]; then
  otu_count=$(tail -n +2 "$comprehensive_db" | wc -l 2>/dev/null || echo "0")
  echo "   ✅ Comprehensive_OTU_Database.csv - $otu_count OTUs with full traceability"
else
  echo "   ⚠️  No TaxonKit LCA results generated"
fi

echo ""

# Show BLAST results
echo " BLAST Best Hit Results:"
for db in 12s coi mitofish; do
  blast_file="$TAXONOMY_DIR/BLAST_vsearch_${db}_classified_species.csv"
  if [[ -f "$blast_file" ]]; then
    species_count=$(tail -n +2 "$blast_file" | wc -l 2>/dev/null || echo "0")
    echo "   • BLAST_vsearch_${db}_classified_species.csv - $species_count species"
  fi
done

echo ""

# Show KRAKEN2 results
echo " KRAKEN2 Results:"
for db in 12s coi mitofish; do
  kraken_file="$TAXONOMY_DIR/Kraken2_vsearch_${db}_classified_species.csv"
  if [[ -f "$kraken_file" ]]; then
    species_count=$(tail -n +2 "$kraken_file" | wc -l 2>/dev/null || echo "0")
    echo "   • Kraken2_vsearch_${db}_classified_species.csv - $species_count species"
  fi
done

echo ""

# Show per-sample Krona plots
echo " Per-Sample Krona Plots:"
krona_found=false
for sample in "${REAL_SAMPLE_NAMES[@]}"; do
  for db in 12s coi mitofish; do
    krona_file="$KRONA_DIR/vsearch_sample_${sample}_${db}_krona.html"
    if [[ -f "$krona_file" ]]; then
      echo "   • Sample ${sample} ${db}: vsearch_sample_${sample}_${db}_krona.html"
      krona_found=true
    fi
  done
done

if [[ "$krona_found" != "true" ]]; then
  echo "   ⚠️  No per-sample Krona plots (KRAKEN2 not run or no classifications)"
fi

echo ""

# Show method comparison
echo " Method Performance:"
if [[ -f "$TAXONOMY_DIR/Comprehensive_Method_Comparison.csv" ]]; then
  echo "   • Comprehensive_Method_Comparison.csv - Compare all methods"
  echo ""
  echo " Method Ranking (by classification power):"
  echo "   1. TaxonKit LCA + Hierarchical Fallback - Robust consensus taxonomy (RECOMMENDED)"
  echo "   2. BLAST Best Hit - Single best match per database"
  echo "   3. Kraken2 - K-mer based classification"
fi

echo ""
echo "  PIPELINE FEATURES:"
echo "   ✅ TaxonKit LCA with hierarchical fallback (Species → Genus → Family → Order)"
echo "   ✅ Comprehensive OTU database with full traceability"
echo "   ✅ Per-sample Kraken2 analysis with Krona visualizations"
if [[ "$SUBSET_COUNT" -gt 0 ]]; then
  echo "   ✅ LIMITED to $SUBSET_COUNT sequences (SUBSET_COUNT=$SUBSET_COUNT)"
else
  echo "   ✅ NO sequence subset limit - uses ALL sequences"
fi
echo "   ✅ Multi-hit filtering (100%, 99.3%, 98%, 96%, 94% thresholds)"
echo "   ✅ Species threshold filtering (97% identity for species assignments)"
echo "   ✅ Sample-specific abundance preservation: ${REAL_SAMPLE_NAMES[*]}"
echo "   ✅ Species × sample abundance matrices"
echo "   ✅ Compatible with both custom_cci and ont_native workflows"
echo ""
echo " Analysis complete! Key results:"
echo "   • Comprehensive_OTU_Database.csv - Complete OTU annotation database"
echo "   • TaxonKit_LCA_species_abundance.csv - Robust species abundance matrix"
echo "   • BLAST_vsearch_*_classified_species.csv - Database-specific species tables"
echo "   • *_krona.html - Interactive taxonomic visualizations"
echo "   • Comprehensive_Method_Comparison.csv - Compare all methods"
echo ""
echo " 🎉 Pipeline complete! Ready for biological interpretation."
echo ""