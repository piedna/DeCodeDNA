#!/bin/bash

# migrate_to_new_structure.sh
# Migrates existing DeCodeDNA repository to new dual-workflow structure

echo "🔄 Migrating DeCodeDNA to new dual-workflow structure..."
echo ""

# Check if we're in the right directory
if [[ ! -f "environment.yml" ]] || [[ ! -d "scripts" ]]; then
    echo "❌ Error: Please run this script from the DeCodeDNA root directory"
    echo "   Expected files: environment.yml, scripts/"
    exit 1
fi

echo "✅ Confirmed: Running from DeCodeDNA root directory"
echo ""

# Create new directory structure
echo "📁 Creating new workflow directories..."
mkdir -p workflows/ont_native_barcodes/{precomputed}
mkdir -p workflows/custom_cci_barcodes/{00_raw_data,01_filtered,02_demultiplexed,demux_config}
mkdir -p results/{ont_native_results,custom_cci_results}

echo "   ✓ Created workflows/ont_native_barcodes/"
echo "   ✓ Created workflows/custom_cci_barcodes/"
echo "   ✓ Created results/ structure"
echo ""

# Migrate ONT Native files
echo "📦 Migrating ONT Native Barcoding files..."
if [[ -d "ont_native_barcodes" ]]; then
    # Move FASTQ files
    if ls ont_native_barcodes/*.fastq >/dev/null 2>&1; then
        mv ont_native_barcodes/*.fastq workflows/ont_native_barcodes/
        echo "   ✓ Moved FASTQ files to workflows/ont_native_barcodes/"
    fi
    
    # Move educational files
    if [[ -d "ont_native_barcodes/fast5" ]]; then
        mv ont_native_barcodes/fast5 workflows/ont_native_barcodes/
        echo "   ✓ Moved fast5/ directory"
    fi
    
    if [[ -d "ont_native_barcodes/pod5_barcode50" ]]; then
        mv ont_native_barcodes/pod5_barcode50 workflows/ont_native_barcodes/
        echo "   ✓ Moved pod5_barcode50/ directory"
    fi
    
    # Move precomputed files
    if ls ont_native_barcodes/mock_amplicon_sorter_*.fasta >/dev/null 2>&1; then
        mv ont_native_barcodes/mock_amplicon_sorter_*.fasta workflows/ont_native_barcodes/precomputed/
        echo "   ✓ Moved precomputed amplicon_sorter results"
    fi
    
    # Remove old directory if empty
    if [[ -z "$(ls -A ont_native_barcodes/)" ]]; then
        rmdir ont_native_barcodes
        echo "   ✓ Removed empty ont_native_barcodes/ directory"
    fi
else
    echo "   ⚠️  ont_native_barcodes/ directory not found - creating mock data structure"
fi

# Migrate Custom CCI files  
echo "📦 Migrating Custom CCI Barcoding files..."
if [[ -d "preloaded_cci_fastq" ]]; then
    if ls preloaded_cci_fastq/*.fastq >/dev/null 2>&1; then
        mv preloaded_cci_fastq/*.fastq workflows/custom_cci_barcodes/00_raw_data/
        echo "   ✓ Moved raw FASTQ files to 00_raw_data/"
    fi
    rmdir preloaded_cci_fastq 2>/dev/null
    echo "   ✓ Removed preloaded_cci_fastq/ directory"
fi

if [[ -d "demux" ]]; then
    if [[ -f "demux/demux_sheet.csv" ]]; then
        mv demux/demux_sheet.csv workflows/custom_cci_barcodes/demux_config/
        echo "   ✓ Moved demux_sheet.csv to demux_config/"
    fi
    rmdir demux 2>/dev/null
    echo "   ✓ Removed demux/ directory"
fi

# Remove old directories if they exist and are empty
echo "🧹 Cleaning up old directories..."
for old_dir in custom_cci_barcodes; do
    if [[ -d "$old_dir" ]] && [[ -z "$(ls -A $old_dir/)" ]]; then
        rmdir "$old_dir"
        echo "   ✓ Removed empty $old_dir/ directory"
    fi
done

# Create workflow-specific READMEs
echo "📝 Creating workflow-specific documentation..."

# ONT Native README
cat > workflows/ont_native_barcodes/README_ont_native.md << 'EOF'
# ONT Native Barcoding Workflow

**Quick start for ONT Native Barcoding (standard workflow)**

## Files in this directory:
- `test_fhl_200k_*.fastq` - Ready-to-analyze mock samples (3 replicates)
- `fast5/` - Educational FAST5 files  
- `pod5_barcode50/` - Educational POD5 files
- `precomputed/` - Server-generated amplicon_sorter results

## Run the pipeline:
```bash
# From this directory:
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_results/02_quicklook
bash ../../scripts/03_consensus_sort.sh ../../results/ont_native_results/02_quicklook ../../results/ont_native_results/03_consensus
bash ../../scripts/04_denoise.sh ../../results/ont_native_results/03_consensus ../../results/ont_native_results/04_denoise
bash ../../scripts/05_taxonomic_assignment.sh ../../results/ont_native_results/04_denoise ../../results/ont_native_results/05_taxonomy
```

**Total time:** 15-20 minutes

See main README.md for detailed instructions.
EOF

# Custom CCI README
cat > workflows/custom_cci_barcodes/README_custom_cci.md << 'EOF'
# Custom CCI Barcoding Workflow

**Complete workflow for custom primer-barcode combinations**

## Directory structure:
- `00_raw_data/` - Raw basecalled FASTQ files (pooled)
- `01_filtered/` - Quality-filtered data (created by pipeline)
- `02_demultiplexed/` - ONTbarcoder output (you create this)
- `demux_config/` - Demultiplexing configuration files

## Workflow steps:
```bash
# Step 1: Quality filter (from this directory)
bash ../../scripts/00_quality_filter_predemux.sh 00_raw_data/test_fhl_customcci.fastq 01_filtered/quality_filtered.fastq

# Step 2: Manual demultiplexing (use GUI)
# Open ONTbarcoder2.3 and demultiplex 01_filtered/quality_filtered.fastq
# Output to: 02_demultiplexed/

# Step 3: Base conversion
cd 02_demultiplexed/
bash ../../../scripts/EFPQ_ontbarcoder_convert.sh
cd ..

# Step 4: Run core pipeline
bash ../../scripts/02_quick_look_clean.sh 02_demultiplexed/ ../../results/custom_cci_results/02_quicklook
bash ../../scripts/03_consensus_sort.sh ../../results/custom_cci_results/02_quicklook ../../results/custom_cci_results/03_consensus
bash ../../scripts/04_denoise.sh ../../results/custom_cci_results/03_consensus ../../results/custom_cci_results/04_denoise
bash ../../scripts/05_taxonomic_assignment.sh ../../results/custom_cci_results/04_denoise ../../results/custom_cci_results/05_taxonomy
```

**Total time:** 25-35 minutes

See main README.md for detailed instructions.
EOF

echo "   ✓ Created workflow READMEs"
echo ""

# Update environment.yml (backup first)
echo "⚙️ Updating environment.yml for cross-platform compatibility..."
if [[ -f "environment.yml" ]]; then
    cp environment.yml environment.yml.backup
    echo "   ✓ Backed up original environment.yml"
    
    # Create new cross-platform environment.yml
    cat > environment.yml << 'EOF'
name: decode-dna
channels:
  - conda-forge
  - bioconda
  - defaults
dependencies:
  - python>=3.11          # modern Python that Bioconda supports
  - pip                   # to run pip installs
  - r-base                # R for LULU package
  - r-devtools            # R devtools for installing LULU
  - nanofilt=2.8.0        # to filter quality and length if needed
  - cutadapt              # primer trimming
  - kraken2               # quick look taxonomic classification
  - vsearch               # clustering / dereplication
  - cd-hit                # sequence clustering
  - blast                 # NCBI BLAST+
  - taxonkit              # taxonomy utilities
  - seqkit                # FASTA/Q utilities
  - krona                 # interactive HTML taxonomic charts
  - pod5                  # convert legacy fast5 to pod5

  # Platform-specific compilers (conda will auto-select based on OS)
  - compilers             # Cross-platform compiler metapackage
  - llvm-openmp           # OpenMP support (works on all platforms)

  # everything below will be installed by pip:
  - pip:
    - edlib
    - biopython
    - matplotlib
    - pandas
    - numpy

# Usage:
#   conda env create -f environment.yml
#   conda activate decode-dna

# Platform Detection:
#   conda automatically selects appropriate compilers:
#   - macOS: clang_osx-64, llvm-openmp
#   - Linux: gcc_linux-64, gxx_linux-64  
#   - Windows: vs2019_win-64 (if available)

# The following will be installed manually (outside Conda):
  # - Dorado (basecaller) - Download from Dorado Oxford Nanopore GitHub
  # - amplicon_sorter - Git clone + copy to PATH
  # - ONTBarcoder2.3  - Download GUI application
  # - LULU R package - Install via devtools::install_github("tobiasgf/lulu")
EOF
    echo "   ✓ Updated environment.yml for cross-platform compatibility"
fi

echo ""

# Verify migration
echo "🔍 Verifying migration results..."

# Check ONT Native structure
ont_fastq_count=$(ls workflows/ont_native_barcodes/*.fastq 2>/dev/null | wc -l || echo "0")
echo "   • ONT Native FASTQ files: $ont_fastq_count"

ont_precomputed_count=$(ls workflows/ont_native_barcodes/precomputed/*.fasta 2>/dev/null | wc -l || echo "0")
echo "   • Precomputed files: $ont_precomputed_count"

# Check Custom CCI structure
cci_raw_count=$(ls workflows/custom_cci_barcodes/00_raw_data/*.fastq 2>/dev/null | wc -l || echo "0")
echo "   • Custom CCI raw files: $cci_raw_count"

demux_sheet_exists="❌"
if [[ -f "workflows/custom_cci_barcodes/demux_config/demux_sheet.csv" ]]; then
    demux_sheet_exists="✅"
fi
echo "   • Demux sheet: $demux_sheet_exists"

# Check scripts
script_count=$(ls scripts/*.sh 2>/dev/null | wc -l || echo "0")
echo "   • Pipeline scripts: $script_count"

echo ""
echo "🎉 Migration completed successfully!"
echo ""
echo "📁 New structure summary:"
echo "   • workflows/ont_native_barcodes/     - Ready-to-use ONT Native workflow"
echo "   • workflows/custom_cci_barcodes/     - Complete Custom CCI workflow"
echo "   • results/                           - Organized analysis outputs"
echo "   • scripts/                           - All pipeline scripts (unchanged)"
echo ""
echo "🔗 Next steps:"
echo "   1. Review the updated main README.md"
echo "   2. Test ONT Native workflow: cd workflows/ont_native_barcodes/"
echo "   3. Test Custom CCI workflow: cd workflows/custom_cci_barcodes/"
echo "   4. Update conda environment: conda env update -f environment.yml"
echo ""
echo "✅ Your DeCodeDNA repository is now organized for dual-workflow teaching!"