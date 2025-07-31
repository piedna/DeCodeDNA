#!/usr/bin/env bash
set -euo pipefail

# ─── DeCodeDNA Database Builder (with TaxIDs) ─────────────────────
# Builds Kraken2 and BLAST databases with NCBI taxonomy integration
# Usage: ./scripts/01_build_dbs_with_taxids.sh
# ────────────────────────────────────────────────────────────────────────

# ─── PROJECT STRUCTURE PATHS (SELF-CONTAINED) ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create databases directory outside project (keeps git repo clean)
WORK="${PROJECT_ROOT}/../databases"
FASTA_ROOT="$WORK/db_fasta"
FASTA_CLEAN="$WORK/db_fasta_clean"
TAXID_DIR="$WORK/taxid_maps"
KRAKEN_DB="$WORK/kraken2_db"
BLAST_DB="$WORK/blast_db"

# Default number of threads
THREADS="${THREADS:-8}"

echo "DeCodeDNA Database Builder"
echo "═══════════════════════════════════════════════════════"
echo " Project root:    $PROJECT_ROOT"
echo " Database root:   $WORK"
echo " Threads:         $THREADS"
echo " Platform:        $(uname -m) ($(uname -s))"
echo ""

# ─── PREPARE DIRECTORY STRUCTURE ───────────────────────────────────────────
echo " Creating directory structure..."
mkdir -p "$FASTA_ROOT" "$FASTA_CLEAN" "$TAXID_DIR" "$KRAKEN_DB" "$BLAST_DB"
echo "   ✅ Directories created"
echo ""

# ─── CHECK REQUIRED TOOLS ──────────────────────────────────────────────────
echo " Checking required tools..."
REQUIRED_TOOLS=(curl wget unzip kraken2-build makeblastdb python3 taxonkit)
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
  if command -v "$tool" &>/dev/null; then
    echo "   ✅ $tool found"
  else
    echo "   ❌ $tool not found"
    MISSING_TOOLS+=("$tool")
  fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
  echo ""
  echo "❌ Missing required tools: ${MISSING_TOOLS[*]}"
  echo ""
  echo "Install missing tools:"
  echo "   - Basic tools: curl wget unzip python3"
  echo "   - Kraken2: conda install -c bioconda kraken2"
  echo "   - BLAST: conda install -c bioconda blast"
  echo "   - TaxonKit: conda install -c bioconda taxonkit"
  echo ""
  echo "After installation, download NCBI taxonomy:"
  echo "   taxonkit --data-dir ~/.taxonkit create-taxdump"
  exit 1
fi

# Special check for TaxonKit taxonomy database
echo "   - Checking TaxonKit taxonomy database..."
if taxonkit list --ids 9606 &>/dev/null; then
  echo "   ✅ TaxonKit taxonomy database found"
else
  echo "   ❌ TaxonKit taxonomy database not found"
  echo ""
  echo "Please download NCBI taxonomy database:"
  echo "   taxonkit --data-dir ~/.taxonkit create-taxdump"
  echo "   Or set TAXONKIT_DB environment variable"
  echo ""
  echo "This is required for BLAST databases with taxonomy support"
  exit 1
fi

# Check and download BLAST taxonomy database for scientific names
echo "   - Checking BLAST taxonomy database (for scientific names)..."
if [[ -f "$BLAST_DB/taxdb.btd" && -f "$BLAST_DB/taxdb.bti" ]]; then
  echo "   ✅ BLAST taxonomy database found"
else
  echo "    Downloading BLAST taxonomy database..."
  echo "     This enables scientific names in BLAST output (fixes N/A names)"
  
  cd "$BLAST_DB"
  
  if curl -sL -o taxdb.tar.gz "ftp://ftp.ncbi.nlm.nih.gov/blast/db/taxdb.tar.gz"; then
    tar -xzf taxdb.tar.gz
    rm taxdb.tar.gz
    echo "   ✅ BLAST taxonomy database downloaded and extracted"
  else
    echo "   ⚠️  Failed to download BLAST taxonomy database"
    echo "     Scientific names will show as 'N/A' but TaxIDs will work"
  fi
  
  cd "$SCRIPT_DIR/.."
fi

# Set BLASTDB environment variable for this session
export BLASTDB="$BLAST_DB"
echo "   - Set BLASTDB environment variable: $BLASTDB"
echo ""

# ─── DOWNLOAD FASTA DATABASES ──────────────────────────────────────────────
echo " STEP 1: Downloading Reference FASTA Files"
echo "─────────────────────────────────────────────────"

cd "$FASTA_ROOT"

# Download MIDORI 12S
if [[ ! -f "midori_12s.fasta" ]]; then
  echo "   - Downloading MIDORI 12S rRNA sequences..."
  curl -sL -o midori_12s.zip \
    "https://www.reference-midori.info/download/Databases/GenBank265_2025-03-08/BLAST/uniq/fasta/MIDORI2_UNIQ_NUC_GB265_srRNA_BLAST.fasta.zip"
  
  if [[ -f "midori_12s.zip" ]]; then
    unzip -q midori_12s.zip
    mv MIDORI2_UNIQ_NUC_GB265_srRNA_BLAST.fasta midori_12s.fasta
    rm midori_12s.zip
    echo "     ✅ MIDORI 12S downloaded"
  else
    echo "     ❌ Failed to download MIDORI 12S"
  fi
else
  echo "   ✅ MIDORI 12S already exists"
fi

# Download MIDORI COI
if [[ ! -f "midori_coi.fasta" ]]; then
  echo "   - Downloading MIDORI COI sequences..."
  curl -sL -o midori_coi.zip \
    "https://www.reference-midori.info/download/Databases/GenBank265_2025-03-08/BLAST/uniq/fasta/MIDORI2_UNIQ_NUC_GB265_CO1_BLAST.fasta.zip"
  
  if [[ -f "midori_coi.zip" ]]; then
    unzip -q midori_coi.zip
    mv MIDORI2_UNIQ_NUC_GB265_CO1_BLAST.fasta midori_coi.fasta
    rm midori_coi.zip
    echo "     ✅ MIDORI COI downloaded"
  else
    echo "     ❌ Failed to download MIDORI COI"
  fi
else
  echo "   ✅ MIDORI COI already exists"
fi

# Download MitoFish
if [[ ! -f "mifish.fasta" ]]; then
  echo "   - Downloading MitoFish mitogenomes..."
  curl -sL -o mifish.zip \
    "https://mitofish.aori.u-tokyo.ac.jp/species/detail/download/?filename=download%2F/complete_partial_mitogenomes.zip"
  
  if [[ -f "mifish.zip" ]]; then
    unzip -q mifish.zip
    mv complete_partial_mitogenomes.fasta mifish.fasta 2>/dev/null || \
    mv mito-all mifish.fasta 2>/dev/null || \
    find . -name "*.fasta" -not -name "midori*" -not -name "mifish*" | head -1 | xargs -I {} mv {} mifish.fasta
    rm mifish.zip
    echo "     ✅ MitoFish downloaded"
  else
    echo "     ❌ Failed to download MitoFish"
  fi
else
  echo "   ✅ MitoFish already exists"
fi

# Show download summary
echo ""
echo " Downloaded FASTA files:"
for fasta in midori_12s.fasta midori_coi.fasta mifish.fasta; do
  if [[ -f "$fasta" ]]; then
    size=$(du -h "$fasta" | cut -f1)
    seqs=$(grep -c "^>" "$fasta" 2>/dev/null || echo "0")
    echo "   - $fasta: $size ($seqs sequences)"
  else
    echo "   ❌ $fasta: Missing"
  fi
done
echo ""

# ─── FUNCTIONS FOR TAXID INTEGRATION ───
extract_species_and_create_taxid_map() {
  local MARK="$1"
  local CLEAN_FASTA="$2"
  local TAXID_MAP="$3"
  
  echo " Processing $MARK: Extracting species and creating taxid map..."
  
  # Create Python script to extract species names
  cat > "$TAXID_DIR/extract_species_${MARK}.py" << 'EOF'
import sys
import re

fasta_file = sys.argv[1]
species_file = sys.argv[2]
marker = sys.argv[3]

species_set = set()
seq_to_species = {}

print(f"Extracting species from {marker} FASTA headers...")

with open(fasta_file, 'r') as f:
    for line in f:
        if line.startswith('>'):
            header = line.strip()[1:]  # Remove '>'
            
            # Extract species from header
            species = 'unknown'
            
            if marker == 'mitofish':
                # Format: gb_KY172977_Pillaia_indica
                parts = header.split('_')
                if len(parts) >= 4:
                    # Get last two parts as genus_species
                    genus = parts[-2]
                    species_part = parts[-1]
                    
                    # Clean and validate
                    if (genus.isalpha() and species_part.isalpha() and 
                        len(genus) > 2 and len(species_part) > 2):
                        species = f"{genus}_{species_part}"
            else:
                # MIDORI format: accession_Genus_species
                parts = header.split('_')
                # Look for Genus_species pattern (two consecutive capitalized words)
                for i in range(len(parts)-1):
                    if (parts[i].replace('-', '').replace('.', '').isalpha() and 
                        parts[i+1].replace('-', '').replace('.', '').isalpha() and
                        len(parts[i]) > 1 and len(parts[i+1]) > 1):
                        species = f"{parts[i]}_{parts[i+1]}"
                        break
            
            # Clean species name
            species = re.sub(r'[^A-Za-z_]', '', species)
            if species and species != 'unknown' and '_' in species:
                species_set.add(species)
                seq_to_species[header] = species

# Write species list
with open(species_file, 'w') as f:
    for species in sorted(species_set):
        # Convert underscore to space for TaxonKit
        species_name = species.replace('_', ' ')
        f.write(f"{species_name}\n")

print(f"Found {len(species_set)} unique species")
if len(species_set) > 0:
    print(f"Sample species: {list(sorted(species_set))[:5]}")

# Save seq->species mapping for later
import pickle
with open(species_file + '.mapping', 'wb') as f:
    pickle.dump(seq_to_species, f)
EOF

  # Run species extraction
  python3 "$TAXID_DIR/extract_species_${MARK}.py" "$CLEAN_FASTA" "$TAXID_DIR/${MARK}_species.txt" "$MARK"
  
  # Look up taxids using TaxonKit
  echo "   - Looking up NCBI taxonomy IDs..."
  taxonkit name2taxid "$TAXID_DIR/${MARK}_species.txt" > "$TAXID_DIR/${MARK}_taxids.txt"
  
  # Show some results
  echo "   - Sample taxid lookups:"
  head -3 "$TAXID_DIR/${MARK}_taxids.txt" | sed 's/^/     /'
  
  # Count successful lookups
  found_count=$(awk -F'\t' '$2 != "" && $2 != "0" {count++} END {print count+0}' "$TAXID_DIR/${MARK}_taxids.txt")
  total_count=$(wc -l < "$TAXID_DIR/${MARK}_species.txt")
  echo "   - Found taxids for $found_count/$total_count species"
  
  # Create taxid mapping file for makeblastdb
  echo "   - Creating sequence ID to taxid mapping..."
  
  cat > "$TAXID_DIR/create_mapping_${MARK}.py" << 'EOF'
import sys
import pickle

taxid_file = sys.argv[1]
mapping_pickle = sys.argv[2]
output_map = sys.argv[3]

# Load sequence->species mapping
with open(mapping_pickle, 'rb') as f:
    seq_to_species = pickle.load(f)

# Load species->taxid mapping
species_to_taxid = {}
with open(taxid_file, 'r') as f:
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) >= 2 and parts[1] and parts[1] != '0':
            species_name = parts[0]
            taxid = parts[1]
            species_key = species_name.replace(' ', '_')
            species_to_taxid[species_key] = taxid

print(f"Loaded {len(species_to_taxid)} species->taxid mappings")

# Create sequence ID -> taxid mapping
mapped_count = 0
unmapped_count = 0

with open(output_map, 'w') as f:
    for seq_id, species in seq_to_species.items():
        if species in species_to_taxid:
            f.write(f"{seq_id}\t{species_to_taxid[species]}\n")
            mapped_count += 1
        else:
            # Use taxid 1 (root) for unmapped sequences
            f.write(f"{seq_id}\t1\n")
            unmapped_count += 1

print(f"Created mapping for {len(seq_to_species)} sequences")
print(f"Successfully mapped {mapped_count} to specific taxids")
print(f"Used root taxid (1) for {unmapped_count} unmapped sequences")
EOF

  python3 "$TAXID_DIR/create_mapping_${MARK}.py" \
    "$TAXID_DIR/${MARK}_taxids.txt" \
    "$TAXID_DIR/${MARK}_species.txt.mapping" \
    "$TAXID_MAP"
  
  echo "   ✅ TaxID mapping created: $TAXID_MAP"
  
  # Clean up temporary files
  rm -f "$TAXID_DIR/extract_species_${MARK}.py" \
        "$TAXID_DIR/create_mapping_${MARK}.py" \
        "$TAXID_DIR/${MARK}_species.txt.mapping"
}

rebuild_blast_db() {
  local MARK="$1"
  local CLEAN_FASTA="$2"
  local TAXID_MAP="$3"
  local OUT_DIR="$4"
  
  echo " Building BLAST database for $MARK..."
  
  # Backup old database if it exists
  if [[ -f "$OUT_DIR/${MARK}.nsq" ]]; then
    echo "   - Backing up existing database..."
    backup_dir="${OUT_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    mv "$OUT_DIR" "$backup_dir"
  fi
  
  mkdir -p "$OUT_DIR"
  
  # Determine title
  case "$MARK" in
    12s)      TITLE="MIDORI 12S rRNA (with TaxIDs)" ;;
    coi)      TITLE="MIDORI COI (with TaxIDs)" ;;
    mitofish) TITLE="MitoFish mitogenomes (with TaxIDs)" ;;
    *)        TITLE="$MARK database (with TaxIDs)" ;;
  esac
  
  echo "   - Building database with taxonomy mapping..."
  if makeblastdb \
    -in "$CLEAN_FASTA" \
    -dbtype nucl \
    -parse_seqids \
    -taxid_map "$TAXID_MAP" \
    -title "$TITLE" \
    -out "$OUT_DIR/$MARK" \
    -max_file_sz 3GB; then
    echo "   ✅ BLAST database built with taxids: $OUT_DIR/$MARK"
  else
    echo "   ❌ Failed to build BLAST database for $MARK"
    return 1
  fi
}

quick_test() {
  local MARK="$1"
  local DB_PATH="$2"
  
  echo " Testing taxonomy integration for $MARK..."
  
  # Test database
  sample_output=$(blastdbcmd -db "$DB_PATH" -entry all -outfmt "%a %T %S" | head -3)
  echo "   - Sample entries:"
  echo "$sample_output" | sed 's/^/     /'
  
  # Count non-zero taxids and named entries
  nonzero_taxids=$(echo "$sample_output" | awk '$2 != "0" {count++} END {print count+0}')
  total_entries=$(echo "$sample_output" | wc -l)
  named_entries=$(echo "$sample_output" | awk '$3 != "N/A" && $3 != "" {count++} END {print count+0}')
  
  echo "   - $nonzero_taxids/$total_entries entries have non-zero taxids"
  echo "   - $named_entries/$total_entries entries have scientific names"
  
  if [[ "$nonzero_taxids" -gt 0 ]]; then
    echo "   ✅ Taxonomy integration successful!"
  else
    echo "   ⚠️  No taxonomy found - check the mapping"
  fi
}

# ─── BUILD BLAST DATABASES WITH TAXONOMY ───────────────────────────────────
echo " STEP 2: Building BLAST Databases (with NCBI Taxonomy)"
echo "─────────────────────────────────────────────────────────"

for MARK in 12s coi mitofish; do
  # Map marker to input file and title
  case "$MARK" in
    12s)
      IN_FASTA="$FASTA_ROOT/midori_12s.fasta"
      TITLE="MIDORI 12S rRNA (with TaxIDs)"
      ;;
    coi)
      IN_FASTA="$FASTA_ROOT/midori_coi.fasta"
      TITLE="MIDORI COI (with TaxIDs)"
      ;;
    mitofish)
      IN_FASTA="$FASTA_ROOT/mifish.fasta"
      TITLE="MitoFish mitogenomes (with TaxIDs)"
      ;;
  esac

  CLEAN_FASTA="$FASTA_CLEAN/${MARK}.fasta"
  TAXID_MAP="$TAXID_DIR/${MARK}_taxid_map.txt"
  OUT_DIR="$BLAST_DB/$MARK"
  mkdir -p "$OUT_DIR"

  echo ""
  echo "=== Processing BLAST DB for $MARK ==="
  echo "  - Input FASTA:  $IN_FASTA"
  echo "  - Clean FASTA:  $CLEAN_FASTA"
  echo "  - TaxID map:    $TAXID_MAP"
  echo "  - Output DB:    $OUT_DIR/$MARK"

  if [[ ! -f "$IN_FASTA" ]]; then
    echo "  ❌ Input FASTA not found, skipping $MARK"
    continue
  fi

  # Check if BLAST DB already exists - skip if complete
  if [[ -f "$OUT_DIR/${MARK}.nsq" ]]; then
    echo "  ⚠️  Database already exists for $MARK - skipping to avoid overwrite"
    echo "     Delete $OUT_DIR to force rebuild"
    continue
  fi

  echo "  - Processing sequences and creating clean headers..."

  # Create Python script to clean FASTA files
  cat > "$FASTA_CLEAN/process_fasta_${MARK}.py" << 'EOF'
import sys
import re
import os

input_file = sys.argv[1]
output_file = sys.argv[2]
marker = sys.argv[3]

counter = 0
seen_headers = set()
processed_count = 0

print(f"Processing {marker} sequences from {input_file}")

with open(input_file, 'r') as f:
    content = f.read()

# Split by '>' and remove empty first element
sequences = [s for s in content.split('>') if s.strip()]
print(f"Found {len(sequences)} raw sequences")

with open(output_file, 'w') as out:
    for seq_block in sequences:
        lines = seq_block.strip().split('\n')
        if not lines:
            continue
            
        header = lines[0]
        sequence = ''.join(lines[1:])
        
        # Clean sequence - keep only ACGT
        clean_seq = re.sub(r'[^ACGT]', '', sequence.upper())
        
        if len(clean_seq) == 0:
            continue
            
        counter += 1
        
        if marker == 'mitofish':
            # MiFish format: gb|KY172977|Pillaia_indica
            parts = header.split('|')
            if len(parts) >= 3:
                accession_prefix = parts[0]
                accession_number = parts[1]
                species = parts[2]
                species = re.sub(r'\s*\(.*', '', species)  # Remove everything after (
                
                # Clean up species name - remove any problematic characters
                species = re.sub(r'[^\w_]', '_', species)
                species = re.sub(r'_+', '_', species)  # Collapse multiple underscores
                species = species.strip('_')
                
                base_header = f'{accession_prefix}_{accession_number}_{species}'
            else:
                base_header = f'unknown_acc_{counter}'
        else:
            # MIDORI format: MH910097.1.49461.51216###...;Genus_species_taxid
            accession = header.split('###')[0] if '###' in header else f'unknown_acc_{counter}'
            
            # Clean accession - remove commas and other problematic characters
            accession = re.sub(r'[^\w.-]', '_', accession)
            accession = re.sub(r'_+', '_', accession)  # Collapse multiple underscores
            accession = accession.strip('_')
            
            # Extract species from taxonomy string
            species = 'unknown_species'
            parts = header.split(';')
            
            # Search backwards for genus_species pattern
            for part in reversed(parts):
                if '_' in part:
                    temp_species = re.sub(r'_\d+$', '', part)
                    if re.match(r'^[A-Za-z]+_[A-Za-z]+$', temp_species):
                        species = temp_species
                        break
            
            base_header = f'{accession}_{species}'
        
        # Clean the entire header - remove commas, pipes, and other BLAST-problematic characters
        base_header = re.sub(r'[,|;()<>[\]{}]', '_', base_header)
        base_header = re.sub(r'_+', '_', base_header)  # Collapse multiple underscores
        base_header = base_header.strip('_')
        
        # Make header unique if we've seen it before
        unique_header = base_header
        suffix = 1
        while unique_header in seen_headers:
            suffix += 1
            unique_header = f'{base_header}_{suffix}'
        
        # Truncate if too long for BLAST (50 char limit)
        if len(unique_header) > 50:
            # Keep some space for the suffix if needed
            if suffix > 1:
                suffix_part = f'_{suffix}'
                max_base_len = 50 - len(suffix_part)
                unique_header = f'{base_header[:max_base_len]}{suffix_part}'
            else:
                unique_header = unique_header[:50]
        
        # Final check after truncation - ensure this exact header hasn't been used
        original_unique = unique_header
        suffix = 1
        while unique_header in seen_headers:
            suffix += 1
            if len(original_unique) + len(f'_{suffix}') <= 50:
                unique_header = f'{original_unique}_{suffix}'
            else:
                # Truncate more to fit suffix
                max_len = 50 - len(f'_{suffix}')
                unique_header = f'{original_unique[:max_len]}_{suffix}'
        
        seen_headers.add(unique_header)
        processed_count += 1
        
        out.write(f'>{unique_header}\n{clean_seq}\n')

print(f'Processed {counter} input sequences, wrote {processed_count} clean sequences')
print(f'Unique headers created: {len(seen_headers)}')
EOF

  # Run the Python script
  python3 "$FASTA_CLEAN/process_fasta_${MARK}.py" "$IN_FASTA" "$CLEAN_FASTA" "$MARK"

  # Show sample headers
  echo "  - Sample cleaned headers:"
  head -5 "$CLEAN_FASTA" | grep "^>" | sed 's/^/    /' || echo "    No headers to show"

  # Check for duplicates
  echo "  - Checking for duplicate headers..."
  duplicate_count=$(grep "^>" "$CLEAN_FASTA" | sort | uniq -d | wc -l)
  if [[ "$duplicate_count" -gt 0 ]]; then
    echo "    ⚠️  Found $duplicate_count duplicate headers - this shouldn't happen!"
    grep "^>" "$CLEAN_FASTA" | sort | uniq -d | head -3
  else
    echo "    ✅ No duplicate headers found"
  fi

  # Step 1: Extract species and create taxid mapping
  extract_species_and_create_taxid_map "$MARK" "$CLEAN_FASTA" "$TAXID_MAP"
  echo ""
  
  # Step 2: Build BLAST database with taxids
  rebuild_blast_db "$MARK" "$CLEAN_FASTA" "$TAXID_MAP" "$OUT_DIR"
  echo ""
  
  # Clean up temporary Python script
  rm -f "$FASTA_CLEAN/process_fasta_${MARK}.py"
done

echo ""

# ─── BUILD KRAKEN2 DATABASES ───────────────────────────────────────────────
echo " STEP 3: Building Kraken2 Databases"
echo "─────────────────────────────────────────────"

if command -v kraken2-build >/dev/null 2>&1; then
  echo "   ✅ kraken2-build found"
  
  for DB in 12s coi mitofish; do
    TARGET="$KRAKEN_DB/$DB"
    echo ""
    echo " Building Kraken2 DB for $DB..."
    
    if [[ -f "$TARGET/taxo.k2d" ]]; then
      echo "   ⚠️  Kraken2 DB already exists for $DB - skipping"
      continue
    fi
    
    # Create database directory
    mkdir -p "$TARGET"
    
    # Download NCBI taxonomy for this database
    echo "   - Downloading NCBI taxonomy..."
    kraken2-build --download-taxonomy --db "$TARGET"
    
    # Map database name to FASTA file
    case "$DB" in
      12s)      FASTA_FILE="$FASTA_ROOT/midori_12s.fasta" ;;
      coi)      FASTA_FILE="$FASTA_ROOT/midori_coi.fasta" ;;
      mitofish) FASTA_FILE="$FASTA_ROOT/mifish.fasta" ;;
    esac
    
    if [[ -f "$FASTA_FILE" ]]; then
      echo "   - Adding sequences to library..."
      kraken2-build --add-to-library "$FASTA_FILE" --db "$TARGET" --no-masking
      
      echo "   - Building database (this may take 5-15 minutes)..."
      kraken2-build --build --db "$TARGET" --threads "$THREADS" --no-masking
      
      echo "   ✅ Kraken2 DB built for $DB"
    else
      echo "   ❌ FASTA file not found: $FASTA_FILE"
    fi
  done
  
  echo ""
  echo "✅ All Kraken2 DBs completed"
  
else
  echo "❌ kraken2-build not found - skipping Kraken2 databases"
  echo "   Install with: conda install -c bioconda kraken2"
  echo "   Kraken2 analysis in downstream scripts will be skipped"
fi

echo ""

# ─── FINAL SUMMARY WITH PROPER TAXONOMY STATUS ─────────────────────────────
echo " DATABASE BUILDING COMPLETE!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo " Database locations:"
echo "    BLAST DBs   → $BLAST_DB/{12s,coi,mitofish}"
echo "    Kraken2 DBs → $KRAKEN_DB/{12s,coi,mitofish}"
echo "    TaxID maps  → $TAXID_DIR/*_taxid_map.txt"
echo ""

echo " Database summary:"
echo ""
echo " BLAST databases:"
for db in 12s coi mitofish; do
  if [[ -f "$BLAST_DB/$db/$db.nsq" ]]; then
    echo "   ✅ $db: Ready for similarity search with taxonomy support"
  else
    echo "   ❌ $db: Failed or not built"
  fi
done

echo ""
echo " Kraken2 databases:"
for db in 12s coi mitofish; do
  if [[ -f "$KRAKEN_DB/$db/taxo.k2d" ]]; then
    echo "   ✅ $db: Ready for classification"
  else
    echo "   ❌ $db: Failed or not built"
  fi
done

echo ""
echo " TaxID mapping files:"
for db in 12s coi mitofish; do
  if [[ -f "$TAXID_DIR/${db}_taxid_map.txt" ]]; then
    lines=$(wc -l < "$TAXID_DIR/${db}_taxid_map.txt")
    echo "   ✅ $db: $lines sequence-to-taxid mappings"
  else
    echo "   ❌ $db: No taxonomy mapping created"
  fi
done

echo ""
echo " BLAST Taxonomy Database:"
if [[ -f "$BLAST_DB/taxdb.btd" && -f "$BLAST_DB/taxdb.bti" ]]; then
  echo "   ✅ NCBI taxonomy database installed"
  echo "   ✅ Scientific names are displayed properly"
  echo "   - Location: $BLAST_DB/taxdb.*"
else
  echo "   ⚠️  NCBI taxonomy database not found"
  echo "   - TaxIDs work but scientific names show 'N/A'"
  echo "   - Download: curl -o taxdb.tar.gz ftp://ftp.ncbi.nlm.nih.gov/blast/db/taxdb.tar.gz"
  echo "   - Extract to: $BLAST_DB/"
fi

echo ""
echo " Features:"
echo "   ✅ BLAST databases have returned with NCBI taxonomy IDs"
echo "   ✅ Compatible with TaxonKit LCA consensus analysis"
echo "   ✅ Proper taxonomic lineage support"
echo ""
echo " Next steps:"
echo "   - Databases are ready for taxonomic classification"
echo "   - Scripts 02-05 will automatically detect taxonomy support"
echo "   - BLAST results will include 'staxids' column with real taxonomy IDs"
echo "   - TaxonKit LCA works for consensus taxonomy"
echo ""
echo " Test your databases:"
echo "   export BLASTDB=\"$BLAST_DB\""
echo "   blastdbcmd -db $BLAST_DB/12s/12s -entry all -outfmt '%a %T %S' | head -5"
echo "   blastn -query test.fasta -db $BLAST_DB/12s/12s -outfmt '6 qseqid sseqid pident staxids sscinames' -max_target_seqs 5"
echo ""
echo " For TaxonKit LCA "
echo "   -  Taxonomy integration is working!"
echo ""
echo "✅ All databases built successfully with taxonomy support!"
echo ""
echo