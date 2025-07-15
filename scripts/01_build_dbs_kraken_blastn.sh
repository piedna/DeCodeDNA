#!/usr/bin/env bash
set -euo pipefail

# ─── Configurable paths & threads ───────────────────────────────────────────
WORK="$HOME/Downloads/test_fhl"
FASTA_ROOT="$WORK/db_fasta"
BLAST_DB="$WORK/blast_db"
THREADS="${THREADS:-15}"

# ─── Prepare directory structure ────────────────────────────────────────────
mkdir -p "$FASTA_ROOT" "$BLAST_DB"

# ─── Kraken2 build (now enabled for teaching class!) ─────────────────────
COMMON_TAX="$WORK/kraken2_db/common_taxonomy"
KRAKEN_DB="$WORK/kraken2_db"

echo
echo "=== Building Kraken2 DBs ==="
echo "🔍 Checking for Kraken2..."

if command -v kraken2-build >/dev/null 2>&1; then
  echo "✅ kraken2-build found"
  
  # Create common taxonomy directory if it doesn't exist
  mkdir -p "$COMMON_TAX"
  
  # Check if taxonomy files exist
  if [[ ! -f "$COMMON_TAX/names.dmp" ]] || [[ ! -f "$COMMON_TAX/nodes.dmp" ]]; then
    echo "📥 Downloading NCBI taxonomy files..."
    cd "$COMMON_TAX"
    wget -q ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz
    tar -xzf taxdump.tar.gz
    rm taxdump.tar.gz
    cd - >/dev/null
    echo "✅ Taxonomy files downloaded"
  else
    echo "✅ Taxonomy files already exist"
  fi
  
  # Create accession2taxid mapping (simplified for teaching)
  if [[ ! -f "$COMMON_TAX/accession2taxid.map" ]]; then
    echo "📝 Creating simplified accession2taxid mapping..."
    # Create a basic mapping file for teaching purposes
    echo -e "accession\taccession.version\ttaxid" > "$COMMON_TAX/accession2taxid.map"
    echo "✅ Basic mapping created"
  fi
  
  for DB in 12s coi mitofish; do
    TARGET="$KRAKEN_DB/$DB"
    echo
    echo "🔨 Building Kraken2 DB for $DB..."
    
    if [[ -f "$TARGET/taxo.k2d" ]]; then
      echo "   ⚠️  Kraken2 DB already exists for $DB - skipping"
      continue
    fi
    
    mkdir -p "$TARGET/taxonomy"
    
    # Link taxonomy files
    ln -sf "$COMMON_TAX"/*.dmp "$TARGET/taxonomy/" 2>/dev/null || true
    ln -sf "$COMMON_TAX/accession2taxid.map" "$TARGET/accession2taxid.map" 2>/dev/null || true
    
    # Use the cleaned FASTA files we created for BLAST
    CLEAN_FASTA="$CLEAN_DIR/${DB}.fasta"
    
    if [[ -f "$CLEAN_FASTA" ]]; then
      echo "   • Adding sequences to library..."
      kraken2-build --add-to-library "$CLEAN_FASTA" --db "$TARGET" --no-masking
      
      echo "   • Building database (this may take 5-15 minutes)..."
      kraken2-build --build --db "$TARGET" --threads "$THREADS" --no-masking
      
      echo "   ✅ Kraken2 DB built for $DB"
    else
      echo "   ❌ Cleaned FASTA not found: $CLEAN_FASTA"
      echo "      Make sure BLAST databases are built first"
    fi
  done
  
  echo "✅ All Kraken2 DBs completed"
  
else
  echo "❌ kraken2-build not found - skipping Kraken2 databases"
  echo "   Install with: conda install -c bioconda kraken2"
  echo "   Kraken2 analysis in script 05 will be skipped"
fi

# ─── Build BLAST DBs with taxonomic names preserved ─────────────────────────
echo
echo "=== Building BLAST DBs with taxonomic names ==="
CLEAN_DIR="$WORK/db_fasta_clean"
mkdir -p "$CLEAN_DIR"

for MARK in 12s coi mitofish; do
  case "$MARK" in
    12s)
      IN_FASTA="$FASTA_ROOT/midori_12s.fasta"
      TITLE="MIDORI 12S"
      ;;
    coi)
      IN_FASTA="$FASTA_ROOT/midori_coi.fasta"
      TITLE="MIDORI COI"
      ;;
    mitofish)
      IN_FASTA="$FASTA_ROOT/mifish.fasta"
      TITLE="MiFish mitogenomes"
      ;;
  esac

  CLEAN_FASTA="$CLEAN_DIR/${MARK}.fasta"
  OUT_DIR="$BLAST_DB/$MARK"
  mkdir -p "$OUT_DIR"

  echo
  echo "=== Cleaning & building BLAST DB for $MARK ==="
  echo "  Original FASTA: $IN_FASTA"
  echo "  Cleaned FASTA:  $CLEAN_FASTA"
  echo "  Output DB dir:  $OUT_DIR"
  echo "  • Processing sequences and creating unique headers..."

  # Create Python script to process FASTA files
  cat > process_fasta.py << 'EOF'
import sys
import re
import os

input_file = os.environ['IN_FASTA']
output_file = os.environ['CLEAN_FASTA']
marker = os.environ['MARK']

counter = 0
seen_headers = set()
processed_count = 0

with open(input_file, 'r') as f:
    content = f.read()

# Split by '>' and remove empty first element
sequences = [s for s in content.split('>') if s.strip()]

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
        
        # Final check - ensure this exact header hasn't been used
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

  # Set environment variables and run the Python script
  export IN_FASTA="$IN_FASTA"
  export CLEAN_FASTA="$CLEAN_FASTA"
  export MARK="$MARK"
  python3 process_fasta.py

  # Show sample headers
  echo "  Sample headers created:"
  head -5 "$CLEAN_FASTA" | grep "^>" || echo "  No headers to show"

  # Check for duplicates before building DB
  echo "  • Checking for duplicate headers..."
  duplicate_count=$(grep "^>" "$CLEAN_FASTA" | sort | uniq -d | wc -l)
  if [ "$duplicate_count" -gt 0 ]; then
    echo "  ⚠️  Found $duplicate_count duplicate headers - this shouldn't happen!"
    grep "^>" "$CLEAN_FASTA" | sort | uniq -d | head -3
  else
    echo "  ✅ No duplicate headers found"
  fi

  # Build the BLAST DB
  echo "  • Building BLAST database..."
  if makeblastdb \
    -in "$CLEAN_FASTA" \
    -dbtype nucl \
    -parse_seqids \
    -title "$TITLE" \
    -out "$OUT_DIR/$MARK" \
    -max_file_sz 3GB; then
    echo "✅ BLAST DB built for $MARK at $OUT_DIR/$MARK"
  else
    echo "❌ BLAST DB build failed for $MARK"
    echo "  Checking first few headers for issues:"
    head -10 "$CLEAN_FASTA"
    exit 1
  fi
  
  # Clean up
  rm -f process_fasta.py
  unset IN_FASTA CLEAN_FASTA MARK
done

echo
echo "🎉 All BLAST DBs with species names are now built under:"
echo "   $BLAST_DB/{12s,coi,mitofish}"
echo
echo "📊 Database summary:"
for db in 12s coi mitofish; do
  if [ -f "$BLAST_DB/$db/$db.nsq" ]; then
    echo "  ✅ $db database: Ready"
  else
    echo "  ❌ $db database: Failed"
  fi
done
