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
