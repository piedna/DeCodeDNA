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
