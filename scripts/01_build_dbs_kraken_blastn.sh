#!/usr/bin/env bash
set -euo pipefail

# ─── DeCodeDNA Database Builder ────────────────────────────────────────────
# Builds Kraken2 and BLAST databases within project structure
# Usage: ./scripts/01_build_dbs_kraken_blastn.sh
# ────────────────────────────────────────────────────────────────────────

# ─── PROJECT STRUCTURE PATHS (SELF-CONTAINED) ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create databases directory outside project (keeps git repo clean)
WORK="${PROJECT_ROOT}/../databases"
FASTA_ROOT="$WORK/db_fasta"
FASTA_CLEAN="$WORK/db_fasta_clean"
KRAKEN_DB="$WORK/kraken2_db"
BLAST_DB="$WORK/blast_db"

# Default number of threads
THREADS="${THREADS:-8}"

echo "🗄️ DeCodeDNA Database Builder"
echo "═══════════════════════════════════════════"
echo "🔹 Project root:    $PROJECT_ROOT"
echo "🔹 Database root:   $WORK"
echo "🔹 Threads:         $THREADS"
echo "🔹 Platform:        $(uname -m) ($(uname -s))"
echo ""

# ─── PREPARE DIRECTORY STRUCTURE ───────────────────────────────────────────
echo "📁 Creating directory structure..."
mkdir -p "$FASTA_ROOT" "$FASTA_CLEAN" "$KRAKEN_DB" "$BLAST_DB"
echo "   ✅ Directories created"
echo ""

# ─── CHECK REQUIRED TOOLS ──────────────────────────────────────────────────
echo "🔍 Checking required tools..."
REQUIRED_TOOLS=(curl wget unzip kraken2-build makeblastdb python3)
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
  echo "   Please install missing tools and try again"
  exit 1
fi
echo ""

# ─── DOWNLOAD FASTA DATABASES ──────────────────────────────────────────────
echo "📥 STEP 1: Downloading Reference FASTA Files"
echo "─────────────────────────────────────────────────"

cd "$FASTA_ROOT"

# Download MIDORI 12S
if [[ ! -f "midori_12s.fasta" ]]; then
  echo "   • Downloading MIDORI 12S rRNA sequences..."
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
  echo "   • Downloading MIDORI COI sequences..."
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
  echo "   • Downloading MitoFish mitogenomes..."
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
echo "📊 Downloaded FASTA files:"
for fasta in midori_12s.fasta midori_coi.fasta mifish.fasta; do
  if [[ -f "$fasta" ]]; then
    size=$(du -h "$fasta" | cut -f1)
    seqs=$(grep -c "^>" "$fasta" 2>/dev/null || echo "0")
    echo "   • $fasta: $size ($seqs sequences)"
  else
    echo "   ❌ $fasta: Missing"
  fi
done
echo ""

# ─── BUILD BLAST DATABASES ─────────────────────────────────────────────────
echo "🧬 STEP 2: Building BLAST Databases"
echo "─────────────────────────────────────────────"

for MARK in 12s coi mitofish; do
  # Map marker to input file and title
  case "$MARK" in
    12s)
      IN_FASTA="$FASTA_ROOT/midori_12s.fasta"
      TITLE="MIDORI 12S rRNA"
      ;;
    coi)
      IN_FASTA="$FASTA_ROOT/midori_coi.fasta"
      TITLE="MIDORI COI"
      ;;
    mitofish)
      IN_FASTA="$FASTA_ROOT/mifish.fasta"
      TITLE="MitoFish mitogenomes"
      ;;
  esac

  CLEAN_FASTA="$FASTA_CLEAN/${MARK}.fasta"
  OUT_DIR="$BLAST_DB/$MARK"
  mkdir -p "$OUT_DIR"

  echo ""
  echo "=== Processing BLAST DB for $MARK ==="
  echo "  • Input FASTA:  $IN_FASTA"
  echo "  • Clean FASTA:  $CLEAN_FASTA"
  echo "  • Output DB:    $OUT_DIR/$MARK"

  if [[ ! -f "$IN_FASTA" ]]; then
    echo "  ❌ Input FASTA not found, skipping $MARK"
    continue
  fi

  # Check if BLAST DB already exists
  if [[ -f "$OUT_DIR/${MARK}.nsq" ]]; then
    echo "  ⚠️  BLAST DB already exists for $MARK - skipping"
    continue
  fi

  echo "  • Processing sequences and creating clean headers..."

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
                
                # Clean up species name
                species = re.sub(r'[^\w_]', '_', species)
                species = re.sub(r'_+', '_', species)
                species = species.strip('_')
                
                base_header = f'{accession_prefix}_{accession_number}_{species}'
            else:
                base_header = f'unknown_acc_{counter}'
        else:
            # MIDORI format: MH910097.1.49461.51216###...;Genus_species_taxid
            accession = header.split('###')[0] if '###' in header else f'unknown_acc_{counter}'
            
            # Clean accession
            accession = re.sub(r'[^\w.-]', '_', accession)
            accession = re.sub(r'_+', '_', accession)
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
        
        # Clean header - remove problematic characters
        base_header = re.sub(r'[,|;()<>[\]{}]', '_', base_header)
        base_header = re.sub(r'_+', '_', base_header)
        base_header = base_header.strip('_')
        
        # Make header unique
        unique_header = base_header
        suffix = 1
        while unique_header in seen_headers:
            suffix += 1
            unique_header = f'{base_header}_{suffix}'
        
        # Truncate if too long for BLAST (50 char limit)
        if len(unique_header) > 50:
            if suffix > 1:
                suffix_part = f'_{suffix}'
                max_base_len = 50 - len(suffix_part)
                unique_header = f'{base_header[:max_base_len]}{suffix_part}'
            else:
                unique_header = unique_header[:50]
        
        seen_headers.add(unique_header)
        processed_count += 1
        
        out.write(f'>{unique_header}\n{clean_seq}\n')

print(f'Processed {counter} input sequences, wrote {processed_count} clean sequences')
print(f'Unique headers created: {len(seen_headers)}')
EOF

  # Run the Python script
  python3 "$FASTA_CLEAN/process_fasta_${MARK}.py" "$IN_FASTA" "$CLEAN_FASTA" "$MARK"

  # Show sample headers
  echo "  • Sample cleaned headers:"
  head -5 "$CLEAN_FASTA" | grep "^>" | sed 's/^/    /' || echo "    No headers to show"

  # Build the BLAST database
  echo "  • Building BLAST database..."
  if makeblastdb \
    -in "$CLEAN_FASTA" \
    -dbtype nucl \
    -parse_seqids \
    -title "$TITLE" \
    -out "$OUT_DIR/$MARK" \
    -max_file_sz 3GB; then
    echo "  ✅ BLAST DB built for $MARK at $OUT_DIR/$MARK"
  else
    echo "  ❌ BLAST DB build failed for $MARK"
    exit 1
  fi
  
  # Clean up temporary Python script
  rm -f "$FASTA_CLEAN/process_fasta_${MARK}.py"
done

echo ""

# ─── BUILD KRAKEN2 DATABASES ───────────────────────────────────────────────
echo "🦠 STEP 3: Building Kraken2 Databases"
echo "─────────────────────────────────────────────"

if command -v kraken2-build >/dev/null 2>&1; then
  echo "   ✅ kraken2-build found"
  
  for DB in 12s coi mitofish; do
    TARGET="$KRAKEN_DB/$DB"
    echo ""
    echo "🔨 Building Kraken2 DB for $DB..."
    
    if [[ -f "$TARGET/taxo.k2d" ]]; then
      echo "   ⚠️  Kraken2 DB already exists for $DB - skipping"
      continue
    fi
    
    # Create database directory
    mkdir -p "$TARGET"
    
    # Download NCBI taxonomy for this database
    echo "   • Downloading NCBI taxonomy..."
    kraken2-build --download-taxonomy --db "$TARGET"
    
    # Map database name to FASTA file
    case "$DB" in
      12s)      FASTA_FILE="$FASTA_ROOT/midori_12s.fasta" ;;
      coi)      FASTA_FILE="$FASTA_ROOT/midori_coi.fasta" ;;
      mitofish) FASTA_FILE="$FASTA_ROOT/mifish.fasta" ;;
    esac
    
    if [[ -f "$FASTA_FILE" ]]; then
      echo "   • Adding sequences to library..."
      kraken2-build --add-to-library "$FASTA_FILE" --db "$TARGET" --no-masking
      
      echo "   • Building database (this may take 5-15 minutes)..."
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

# ─── FINAL SUMMARY ─────────────────────────────────────────────────────────
echo "🎉 DATABASE BUILDING COMPLETE!"
echo "═══════════════════════════════════════════"
echo ""
echo "📁 Database locations:"
echo "   🧬 BLAST DBs   → $BLAST_DB/{12s,coi,mitofish}"
echo "   🦠 Kraken2 DBs → $KRAKEN_DB/{12s,coi,mitofish}"
echo ""

echo "📊 Database summary:"
echo ""
echo "🧬 BLAST databases:"
for db in 12s coi mitofish; do
  if [[ -f "$BLAST_DB/$db/$db.nsq" ]]; then
    echo "   ✅ $db: Ready for similarity search"
  else
    echo "   ❌ $db: Failed or not built"
  fi
done

echo ""
echo "🦠 Kraken2 databases:"
for db in 12s coi mitofish; do
  if [[ -f "$KRAKEN_DB/$db/taxo.k2d" ]]; then
    echo "   ✅ $db: Ready for classification"
  else
    echo "   ❌ $db: Failed or not built"
  fi
done

echo ""
echo "🔗 Next steps:"
echo "   • Databases are ready for taxonomic classification"
echo "   • Scripts 02-05 will automatically find these databases"
echo "   • Run quality control and classification with script 02"
echo ""
echo "✅ All databases built successfully!"
echo ""