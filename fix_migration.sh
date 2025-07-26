#!/bin/bash

echo "🔧 Fixing migration issues..."
echo ""

# Fix 1: Move precomputed files properly
echo "📁 Moving precomputed files to correct location..."
if [[ -d "ont_native_barcodes" ]]; then
    # Create precomputed directory first
    mkdir -p workflows/ont_native_barcodes/precomputed
    
    # Move precomputed files
    if ls ont_native_barcodes/mock_amplicon_sorter_*.fasta >/dev/null 2>&1; then
        mv ont_native_barcodes/mock_amplicon_sorter_*.fasta workflows/ont_native_barcodes/precomputed/
        echo "   ✓ Moved precomputed amplicon_sorter files"
    fi
    
    # Remove the now-empty directory
    if [[ -z "$(ls -A ont_native_barcodes/)" ]]; then
        rmdir ont_native_barcodes
        echo "   ✓ Removed empty ont_native_barcodes/ directory"
    else
        echo "   ⚠️  ont_native_barcodes/ still contains files:"
        ls ont_native_barcodes/
    fi
fi

# Fix 2: Clean up other old directories
echo ""
echo "🧹 Cleaning up remaining old directories..."

if [[ -d "custom_cci_barcodes" ]]; then
    if [[ -z "$(ls -A custom_cci_barcodes/)" ]] || [[ "$(ls custom_cci_barcodes/)" == "test.txt" ]]; then
        rm -rf custom_cci_barcodes
        echo "   ✓ Removed empty custom_cci_barcodes/ directory"
    else
        echo "   ⚠️  custom_cci_barcodes/ still contains files:"
        ls custom_cci_barcodes/
    fi
fi

if [[ -d "preloaded_cci_fastq" ]]; then
    if [[ -z "$(ls -A preloaded_cci_fastq/)" ]]; then
        rmdir preloaded_cci_fastq
        echo "   ✓ Removed empty preloaded_cci_fastq/ directory"
    else
        echo "   ⚠️  preloaded_cci_fastq/ still contains files:"
        ls preloaded_cci_fastq/
    fi
fi

# Fix 3: Fix weird {precomputed} directory name issue
echo ""
echo "🔧 Checking for directory name issues..."
if [[ -d "workflows/ont_native_barcodes/{precomputed}" ]]; then
    echo "   ⚠️  Found weird {precomputed} directory - fixing..."
    mv "workflows/ont_native_barcodes/{precomputed}" workflows/ont_native_barcodes/precomputed_fixed
    mv workflows/ont_native_barcodes/precomputed_fixed/* workflows/ont_native_barcodes/precomputed/ 2>/dev/null || true
    rmdir workflows/ont_native_barcodes/precomputed_fixed 2>/dev/null || true
    echo "   ✓ Fixed directory name issue"
fi

# Fix 4: Make sure both workflow READMEs have the complete content
echo ""
echo "📝 Updating workflow READMEs with complete content..."

# Update ONT Native README with more complete content
cat > workflows/ont_native_barcodes/README_ont_native.md << 'EOF'
# ONT Native Barcoding Workflow

**Quick start for ONT Native Barcoding (standard workflow)**

✅ **Perfect for**: FHL students, beginners, standard ONT workflows
🎯 **Goal**: Focus on bioinformatics analysis with ready-to-go data

## 📁 Files in this directory:
- `test_fhl_200k_*.fastq` - Ready-to-analyze mock samples (3 replicates, ~200k reads each)
- `fast5/` - Educational FAST5 files (legacy format)
- `pod5_barcode50/` - Educational POD5 files (modern format)
- `precomputed/` - Server-generated amplicon_sorter results for comparison

## 🚀 Run the complete pipeline (15-20 minutes):
```bash
# Navigate to this directory first
cd workflows/ont_native_barcodes/

# Step 1: Quality control & taxonomic classification (3-5 min)
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_results/02_quicklook

# Step 2: Consensus building (5-8 min)
bash ../../scripts/03_consensus_sort.sh ../../results/ont_native_results/02_quicklook ../../results/ont_native_results/03_consensus

# Step 3: LULU denoising (3-7 min)
bash ../../scripts/04_denoise.sh ../../results/ont_native_results/03_consensus ../../results/ont_native_results/04_denoise

# Step 4: Final taxonomic assignment (5-10 min)
bash ../../scripts/05_taxonomic_assignment.sh ../../results/ont_native_results/04_denoise ../../results/ont_native_results/05_taxonomy

# Step 5: View results
open ../../results/ont_native_results/05_taxonomy/04_krona_plots/*.html
```

## 🎓 What you'll learn:
- Oxford Nanopore data quality assessment
- Taxonomic classification with multiple databases
- Sequence clustering approaches (vsearch vs amplicon_sorter)
- Error correction with LULU algorithm
- Interactive data visualization with Krona plots

## 📊 Expected results:
- **Species identified**: 10-30 fish species
- **Processing time**: 15-20 minutes total
- **Output files**: Species abundance tables + interactive plots

**📖 See main README.md for detailed instructions and customization options.**
EOF

# Update Custom CCI README (just the quick reference part for now)
cat > workflows/custom_cci_barcodes/README_custom_cci.md << 'EOF'
# Custom CCI Barcoding Workflow

**Complete workflow for custom primer-barcode combinations**

✅ **Perfect for**: Advanced users, research applications, custom primer designs
🎯 **Goal**: Complete wet lab → bioinformatics pipeline with manual demultiplexing

## 📁 Directory structure:
- `00_raw_data/` - Raw basecalled FASTQ files (pooled)
- `01_filtered/` - Quality-filtered data (created by pipeline)
- `02_demultiplexed/` - ONTbarcoder output (you create this)
- `demux_config/` - Demultiplexing configuration files

## 🚀 Complete workflow (25-35 minutes):
```bash
# Navigate to this directory first
cd workflows/custom_cci_barcodes/

# Step 1: Quality filter raw pooled data (3-5 min)
bash ../../scripts/00_quality_filter_predemux.sh 00_raw_data/test_fhl_customcci.fastq 01_filtered/quality_filtered.fastq

# Step 2: Manual demultiplexing with GUI (5-10 min)
# - Open ONTbarcoder2.3 GUI
# - Input: 01_filtered/quality_filtered.fastq
# - Demux sheet: demux_config/demux_sheet.csv
# - Output: 02_demultiplexed/*.fa

# Step 3: Base conversion (1-2 min)
cd 02_demultiplexed/
bash ../../../scripts/EFPQ_ontbarcoder_convert.sh
cd ..

# Step 4: Core pipeline analysis (15-20 min)
bash ../../scripts/02_quick_look_clean.sh 02_demultiplexed/ ../../results/custom_cci_results/02_quicklook
bash ../../scripts/03_consensus_sort.sh ../../results/custom_cci_results/02_quicklook ../../results/custom_cci_results/03_consensus
bash ../../scripts/04_denoise.sh ../../results/custom_cci_results/03_consensus ../../results/custom_cci_results/04_denoise
bash ../../scripts/05_taxonomic_assignment.sh ../../results/custom_cci_results/04_denoise ../../results/custom_cci_results/05_taxonomy

# Step 5: View results
open ../../results/custom_cci_results/05_taxonomy/04_krona_plots/*.html
```

## 🎓 What you'll learn:
- Pre-demultiplexing quality filtering strategies
- Manual demultiplexing with ONTbarcoder2.3
- EFPQ base conversion (ONTbarcoder artifact)
- Complete eDNA analysis pipeline
- Custom barcode design principles

## 📊 Expected results:
- **Demultiplexed samples**: 3-4 individual sample files
- **Species identified**: 10-30 fish species per sample
- **Processing time**: 25-35 minutes total
- **Skills gained**: Complete wet lab → analysis workflow

**📖 See main README.md for detailed instructions and troubleshooting.**
EOF

echo "   ✓ Updated workflow READMEs"

echo ""
echo "🔍 Verifying fixes..."

# Check final structure
echo "📁 Final directory structure:"
echo "ONT Native files:"
ls -la workflows/ont_native_barcodes/ | head -10

echo ""
echo "Custom CCI files:"
ls -la workflows/custom_cci_barcodes/

echo ""
echo "Precomputed files:"
ls -la workflows/ont_native_barcodes/precomputed/ 2>/dev/null || echo "   No precomputed directory found"

echo ""
echo "Old directories remaining:"
for old_dir in ont_native_barcodes custom_cci_barcodes preloaded_cci_fastq; do
    if [[ -d "$old_dir" ]]; then
        echo "   ⚠️  $old_dir still exists"
        ls "$old_dir"
    else
        echo "   ✅ $old_dir removed"
    fi
done

echo ""
echo "✅ Migration fixes completed!"
echo ""
echo "🔗 Next steps:"
echo "   1. Test ONT Native workflow: cd workflows/ont_native_barcodes/"
echo "   2. Test Custom CCI workflow: cd workflows/custom_cci_barcodes/"  
echo "   3. Update main README.md with any missing important details"
echo "   4. Commit and push to GitHub when satisfied"