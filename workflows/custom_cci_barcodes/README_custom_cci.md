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
