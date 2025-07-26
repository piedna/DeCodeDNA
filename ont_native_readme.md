# ONT Native Barcoding Workflow

**For samples using Oxford Nanopore's official barcoding kits**

---

## 📋 When to Use This Workflow

✅ **Use ONT Native when you have:**
- Samples barcoded with ONT Native Barcoding Kits (NBD114.96, PBC096, EXP-NBD104, etc.)
- Already demultiplexed FASTQ files (one file per sample)
- Standard Oxford Nanopore sequencing workflow
- Ready-to-analyze sequence data

❌ **Don't use this workflow if:**
- You have custom primer-barcode combinations → Use Custom CCI Workflow
- You have pooled/multiplexed data that needs demultiplexing → Use Custom CCI Workflow
- You need to do manual barcode assignment → Use Custom CCI Workflow

---

## 📁 Directory Contents

```
workflows/ont_native_barcodes/
├── README_ont_native.md           # This file
├── test_fhl_200k_1.fastq         # Sample 1 (200k reads, ready for analysis)
├── test_fhl_200k_2.fastq         # Sample 2 (200k reads, ready for analysis)  
├── test_fhl_200k_3.fastq         # Sample 3 (200k reads, ready for analysis)
├── fast5/                        # Educational: Legacy FAST5 files
├── pod5_barcode50/               # Educational: Modern POD5 files
└── precomputed/                  # Pre-computed server results for comparison
    ├── mock_amplicon_sorter_clustered_consensus_1.fasta
    ├── mock_amplicon_sorter_clustered_consensus_2.fasta
    └── mock_amplicon_sorter_clustered_consensus_3.fasta
```

---

## 🚀 Quick Start (15-20 minutes)

### Prerequisites
```bash
# Ensure you're in the main DeCodeDNA directory
cd DeCodeDNA/
conda activate decode-dna
source scripts/setup_databases.sh
```

### Run Complete Pipeline
```bash
# Navigate to ONT Native workflow directory
cd workflows/ont_native_barcodes/

# Step 1: Quality control & taxonomic classification (3-5 min)
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_results/02_quicklook

# Step 2: Consensus sequence building (5-8 min)  
bash ../../scripts/03_consensus_sort.sh ../../results/ont_native_results/02_quicklook ../../results/ont_native_results/03_consensus

# Step 3: LULU denoising (3-7 min)
bash ../../scripts/04_denoise.sh ../../results/ont_native_results/03_consensus ../../results/ont_native_results/04_denoise

# Step 4: Final taxonomic assignment (5-10 min)
bash ../../scripts/05_taxonomic_assignment.sh ../../results/ont_native_results/04_denoise ../../results/ont_native_results/05_taxonomy
```

### View Results
```bash
# Final species tables
ls ../../results/ont_native_results/05_taxonomy/03_final_taxonomy/*.csv

# Interactive Krona plots (open in browser)
open ../../results/ont_native_results/05_taxonomy/04_krona_plots/*.html
```

---

## 🔬 What This Workflow Does

### Input Data (Mock Fish Community)
- **3 replicate samples** from the same fish community
- **~200,000 sequences per sample** (12S fish metabarcoding)
- **Quality-filtered** and ready for analysis
- **Representative of real eDNA samples**

### Analysis Steps

**🔹 Script 02: Quality Control & Classification**
- Applies additional quality filtering (Q≥12, 100-500bp)
- Initial taxonomic classification with Kraken2
- Length distribution analysis
- Separates fish sequences from contaminants

**🔹 Script 03: Consensus Building**
- **vsearch clustering**: Fast local approach (runs automatically)
- **amplicon_sorter**: Advanced server-optimized approach (pre-computed results provided)
- Demonstrates different clustering philosophies

**🔹 Script 04: LULU Denoising**  
- Removes PCR artifacts and sequencing errors
- Co-occurrence analysis between samples
- Filters out low-abundance noise

**🔹 Script 05: Taxonomic Assignment**
- **BLAST similarity search** against multiple databases (12S, COI, MitoFish)
- **Kraken2 k-mer classification** for comparison
- **Interactive Krona plots** for visualization
- **Species abundance matrices** for downstream analysis

---

## 📊 Expected Results

### File Structure After Analysis
```
results/ont_native_results/
├── 02_quicklook/                  # Quality control results
│   ├── filtered/                  # Quality-filtered FASTQ files
│   └── mitofish/                  # Fish-classified sequences
├── 03_consensus/                  # Clustering results
│   ├── vsearch_clustering/        # Local clustering results
│   └── amplicon_sorter_consensus.fasta  # Server-optimized results
├── 04_denoise/                    # LULU-denoised OTUs
│   └── mitofish/                  # Database-specific results
│       └── otu_table_mitofish_vsearch_lulu_curated.csv  ⭐
└── 05_taxonomy/                   # Final taxonomic assignment
    ├── 03_final_taxonomy/         # Species abundance tables ⭐
    │   └── BLAST_vsearch_mitofish_classified_species.csv
    └── 04_krona_plots/            # Interactive visualizations ⭐
        └── *.html
```

### Key Output Files

**📋 Species Abundance Tables:**
```csv
species,test_fhl_200k_1,test_fhl_200k_2,test_fhl_200k_3
Sebastes_alutus,45,52,38
Gadus_macrocephalus,23,18,29
Theragra_chalcogramma,67,71,63
...
```

**🍩 Interactive Krona Plots:**
- Per-sample taxonomic composition
- Hierarchical visualization (Kingdom → Species)
- Click to explore different taxonomic levels

---

## ⚙️ Customization Options

### Adjust Filtering Parameters
```bash
# Stricter quality filtering
export QUALITY_THRESHOLD=18 MIN_LENGTH=200 MAX_LENGTH=300

# Focus on specific database
export DATABASES="mitofish"

# Use more CPU cores
export THREADS=16

# Process fewer sequences for speed
export SUBSET_COUNT=1000

# Then run pipeline normally
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_custom/02_quicklook
```

### Single Database Analysis
```bash
# Focus only on MitoFish database (fastest)
export DATABASES="mitofish"
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_mitofish/02_quicklook
# Continue with remaining scripts...
```

---

## 🎓 Educational Features

### Clustering Comparison
- **vsearch**: Fast, conservative clustering (many small clusters)
- **amplicon_sorter**: Thorough, ONT-optimized (fewer high-quality clusters)
- **Compare results** to understand clustering trade-offs

### Database Comparison  
- **12S rRNA**: Fish-specific, highly conserved
- **COI**: Universal barcode, more variable
- **MitoFish**: Complete mitogenomes, comprehensive

### Method Comparison
- **BLAST**: Similarity-based, precise identification
- **Kraken2**: k-mer based, faster classification
- **Compare performance** in `Overall_Method_Comparison.csv`

---

## 🔧 Troubleshooting

### Common Issues

**"No FASTQ files found"**
```bash
# Check you're in the right directory
pwd  # Should end with: /DeCodeDNA/workflows/ont_native_barcodes

# List available files
ls *.fastq
```

**"Database not found"**
```bash
# Return to main directory and setup databases
cd ../../
source scripts/setup_databases.sh
cd workflows/ont_native_barcodes/
```

**"Scripts not executable"**
```bash
# Make scripts executable
chmod +x ../../scripts/*.sh
```

**"Low classification rate"**
- Normal for mock data - some sequences are non-fish contaminants
- Check `mitofish/` folder for fish-specific results
- Krona plots show taxonomic breakdown

### Performance Issues

**Pipeline running slowly?**
```bash
# Use subset for faster analysis
export SUBSET_COUNT=500 THREADS=4
```

**Out of memory errors?**
```bash
# Reduce memory usage
export THREADS=2 MAX_LENGTH=400
```

---

## 📈 Interpreting Results

### Quality Control (Script 02)
- **Retention rate**: % of sequences passing quality filters (expect 60-90%)
- **Classification rate**: % of sequences identified as fish (expect 30-70%)
- **Length distribution**: Should show peak around your target amplicon size

### Clustering (Script 03)
- **vsearch clusters**: Typically 100-500 clusters per sample
- **amplicon_sorter**: Typically 50-200 high-quality clusters per sample
- **Server results show**: What amplicon_sorter produces with more resources

### Denoising (Script 04)
- **OTU reduction**: LULU typically removes 20-50% of low-abundance OTUs
- **Retained abundance**: >95% of sequence abundance should be retained
- **Cross-sample consistency**: Similar species should appear across replicates

### Taxonomic Assignment (Script 05)
- **Species diversity**: Expect 10-30 fish species in mock community
- **Method agreement**: BLAST and Kraken2 should show similar patterns
- **Database differences**: Different databases may identify different species

---

## 🔗 Next Steps

### After Running This Workflow
1. **Explore Krona plots** - Interactive taxonomic visualization
2. **Compare with Custom CCI** - Run same data through Custom CCI workflow
3. **Analyze method performance** - Review `Overall_Method_Comparison.csv`
4. **Interpret biological results** - Which fish species are present?

### For Real Data
1. **Adjust parameters** based on your amplicon target
2. **Use appropriate databases** for your taxonomic group
3. **Include negative controls** for contamination assessment
4. **Validate with known species** if available

---

**🎯 This workflow demonstrates the complete ONT eDNA analysis pipeline with minimal setup requirements!**