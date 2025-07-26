# Custom CCI Barcoding Workflow

**For samples using custom primer-barcode combinations**

---

## 📋 When to Use This Workflow

✅ **Use Custom CCI when you have:**
- Custom primer designs with integrated barcodes
- Pooled/multiplexed samples that need manual demultiplexing  
- Primer-barcode combinations not supported by ONT's standard workflow
- Research applications requiring specific primer sets

❌ **Don't use this workflow if:**
- You have ONT Native Barcoding Kit data → Use ONT Native Workflow
- Your data is already demultiplexed → Use ONT Native Workflow
- You want the simplest analysis path → Use ONT Native Workflow

---

## 📁 Directory Contents

```
workflows/custom_cci_barcodes/
├── README_custom_cci.md           # This file
├── 00_raw_data/                   # Raw basecalled FASTQ (pooled)
│   └── test_fhl_customcci.fastq   # Example pooled FASTQ file
├── 01_filtered/                   # Quality-filtered data (created by pipeline)
├── 02_demultiplexed/              # Post-ONTbarcoder results (created by you)
└── demux_config/                  # Demultiplexing configuration
    └── demux_sheet.csv            # Sample-barcode mapping
```

---

## 🚀 Complete Workflow (25-35 minutes)

### Prerequisites
```bash
# Ensure you're in the main DeCodeDNA directory
cd DeCodeDNA/
conda activate decode-dna
source scripts/setup_databases.sh

# Install ONTbarcoder2.3 (one-time setup)
bash scripts/install_external_tools.sh
```

### Step 1: Quality Filtering (3-5 minutes)
```bash
# Navigate to Custom CCI workflow directory
cd workflows/custom_cci_barcodes/

# Quality filter the pooled FASTQ before demultiplexing
bash ../../scripts/00_quality_filter_predemux.sh \
    00_raw_data/test_fhl_customcci.fastq \
    01_filtered/quality_filtered.fastq
```

**Why filter first?**
- ONTbarcoder converts FASTQ → FASTA (loses quality scores)
- Filter by quality while we still have Q-scores
- Reduces data size for faster demultiplexing

### Step 2: Manual Demultiplexing (5-10 minutes)
```bash
# Open ONTbarcoder2.3 GUI application
open ../../tools/ONTbarcoder2.3.app  # macOS
# or double-click ONTbarcoder2.3.app on other systems
```

**ONTbarcoder2.3 Settings:**
- **Input FASTQ**: `01_filtered/quality_filtered.fastq`
- **Demux Sheet**: `demux_config/demux_sheet.csv`
- **Output Directory**: `02_demultiplexed/`
- **Settings**: Use default parameters
- **Click "Run"**

**Expected Output:**
```
02_demultiplexed/
├── sample_1.fa
├── sample_2.fa  
├── sample_3.fa
└── demux_stats.txt
```

### Step 3: Base Conversion (1-2 minutes)
```bash
# Convert EFPQ bases back to ACGT (ONTbarcoder artifact)
cd 02_demultiplexed/
bash ../../../scripts/EFPQ_ontbarcoder_convert.sh
cd ..
```

**What this does:**
- ONTbarcoder converts A→E, G→F, C→Q, T→P during processing
- This script converts back to standard ACGT bases
- Files remain as .fa format

### Step 4: Core Pipeline Analysis (15-20 minutes)
```bash
# Run the standard DeCodeDNA pipeline on demultiplexed data

# Step 4a: Quality control & taxonomic classification (3-5 min)
bash ../../scripts/02_quick_look_clean.sh \
    02_demultiplexed/ \
    ../../results/custom_cci_results/02_quicklook

# Step 4b: Consensus sequence building (5-8 min)  
bash ../../scripts/03_consensus_sort.sh \
    ../../results/custom_cci_results/02_quicklook \
    ../../results/custom_cci_results/03_consensus

# Step 4c: LULU denoising (3-7 min)
bash ../../scripts/04_denoise.sh \
    ../../results/custom_cci_results/03_consensus \
    ../../results/custom_cci_results/04_denoise

# Step 4d: Final taxonomic assignment (5-10 min)
bash ../../scripts/05_taxonomic_assignment.sh \
    ../../results/custom_cci_results/04_denoise \
    ../../results/custom_cci_results/05_taxonomy
```

### Step 5: View Results
```bash
# Final species tables
ls ../../results/custom_cci_results/05_taxonomy/03_final_taxonomy/*.csv

# Interactive Krona plots (open in browser)
open ../../results/custom_cci_results/05_taxonomy/04_krona_plots/*.html
```

---

## 🔬 Understanding the Custom CCI Process

### Why This Workflow is More Complex
1. **Pooled Data**: All samples sequenced together in one file
2. **Custom Barcodes**: Require manual assignment, not automated
3. **Quality Filtering**: Must be done before demultiplexing to preserve Q-scores
4. **Format Conversion**: ONTbarcoder has specific input/output requirements

### Demux Sheet Format
The `demux_config/demux_sheet.csv` file defines how to separate samples:

```csv
sample_name,forward_tag,reverse_tag,forward_primer,reverse_primer
sample_1,CCATTGTATAAACC,CCATTGTATAAACC,GCCGGTAAAACTCGTGCCAGC,CATAGTGGGGTATCTAATCCCAGTTTG
sample_2,CCGTATAGAGTACC,CCGTATAGAGTACC,GCCGGTAAAACTCGTGCCAGC,CATAGTGGGGTATCTAATCCCAGTTTG
sample_3,CGTATTGCCTAACC,CGTATTGCCTAACC,GCCGGTAAAACTCGTGCCAGC,CATAGTGGGGTATCTAATCCCAGTTTG
```

**Column Explanations:**
- **sample_name**: What you want to call each sample
- **forward_tag/reverse_tag**: Unique barcode sequences for this sample
- **forward_primer/reverse_primer**: PCR primers used (same for all samples)

### Quality Filtering Strategy
```bash
# Default parameters (adjust as needed)
QUALITY_THRESHOLD=12    # Minimum Q-score
MIN_LENGTH=100         # Minimum sequence length  
MAX_LENGTH=500         # Maximum sequence length

# Custom parameters example
export QUALITY_THRESHOLD=15 MIN_LENGTH=150 MAX_LENGTH=350
bash ../../scripts/00_quality_filter_predemux.sh input.fastq output.fastq
```

---

## 📊 Expected Results

### Demultiplexing Success Metrics
```
02_demultiplexed/
├── sample_1.fa         # ~50,000-100,000 sequences
├── sample_2.fa         # ~50,000-100,000 sequences  
├── sample_3.fa         # ~50,000-100,000 sequences
└── demux_stats.txt     # Demultiplexing statistics
```

**Good demultiplexing shows:**
- **Balanced samples**: Similar read counts across samples
- **High assignment rate**: >80% of reads assigned to samples
- **Low unassigned**: <20% unassigned reads

### Final Results Structure
```
results/custom_cci_results/
├── 02_quicklook/                  # Quality control results
├── 03_consensus/                  # Clustering results  
├── 04_denoise/                    # LULU-denoised OTUs
└── 05_taxonomy/                   # Final taxonomic assignment
    ├── 03_final_taxonomy/         # Species abundance tables ⭐
    └── 04_krona_plots/            # Interactive visualizations ⭐
```

### Sample-Specific Results
- **Per-sample Krona plots**: Individual taxonomic composition
- **Cross-sample comparison**: Species presence/absence patterns
- **Abundance matrices**: Quantitative species data

---

## ⚙️ Troubleshooting

### Common Issues

**"ONTbarcoder2.3 won't open"**
```bash
# macOS: Allow unsigned applications
sudo xattr -rd com.apple.quarantine ../../tools/ONTbarcoder2.3.app

# Linux: Check if GUI libraries are installed
sudo apt-get install libgtk-3-0  # Ubuntu/Debian
```

**"No demultiplexed files created"**
- Check demux sheet format (CSV with exact column names)
- Verify barcode sequences are correct
- Try relaxing ONTbarcoder settings (increase mismatch tolerance)
- Check input FASTQ file has sequences

**"EFPQ conversion failed"**
```bash
# Check if files exist
ls 02_demultiplexed/*.fa

# Run conversion manually
cd 02_demultiplexed/
for file in *.fa; do
    sed -i 's/E/A/g; s/F/G/g; s/Q/C/g; s/P/T/g' "$file"
done
cd ..
```

**"Low demultiplexing rate"**
- Verify primer/barcode sequences in demux sheet
- Check if barcodes are present in the data:
  ```bash
  grep -c "CCATTGTATAAACC" 01_filtered/quality_filtered.fastq
  ```
- Consider increasing mismatch tolerance in ONTbarcoder

### Advanced Troubleshooting

**Custom demux sheet for your data:**
1. **Extract barcode sequences** from your wet lab protocol
2. **Update primer sequences** if using different amplicons
3. **Test with subset** of data first
4. **Validate barcode uniqueness** (no overlapping sequences)

**Quality filtering optimization:**
```bash
# For longer amplicons (COI, 16S)
export MIN_LENGTH=500 MAX_LENGTH=800

# For stricter quality
export QUALITY_THRESHOLD=18

# Check filtering stats
seqkit stats 00_raw_data/*.fastq
seqkit stats 01_filtered/*.fastq
```

---

## 🔧 Customization Options

### Adjust Pre-Demux Filtering
```bash
# Stricter filtering (recommended for noisy data)
export QUALITY_THRESHOLD=15 MIN_LENGTH=200 MAX_LENGTH=400
bash ../../scripts/00_quality_filter_predemux.sh \
    00_raw_data/your_data.fastq \
    01_filtered/strict_filtered.fastq

# Lenient filtering (for low-quality libraries)
export QUALITY_THRESHOLD=8 MIN_LENGTH=50 MAX_LENGTH=1000
bash ../../scripts/00_quality_filter_predemux.sh \
    00_raw_data/your_data.fastq \
    01_filtered/lenient_filtered.fastq
```

### Custom Demux Sheet
Create your own `demux_config/my_demux_sheet.csv`:
```csv
sample_name,forward_tag,reverse_tag,forward_primer,reverse_primer
site_A_rep1,ACGTACGTACGT,ACGTACGTACGT,YOUR_FORWARD_PRIMER,YOUR_REVERSE_PRIMER
site_A_rep2,TGCATGCATGCA,TGCATGCATGCA,YOUR_FORWARD_PRIMER,YOUR_REVERSE_PRIMER
site_B_rep1,CGATCGATCGAT,CGATCGATCGAT,YOUR_FORWARD_PRIMER,YOUR_REVERSE_PRIMER
```

### Pipeline Customization  
```bash
# Focus on specific database
export DATABASES="mitofish"

# Use more CPU cores
export THREADS=16

# Process subset for testing
export SUBSET_COUNT=500

# Then run pipeline with custom settings
bash ../../scripts/02_quick_look_clean.sh 02_demultiplexed/ ../../results/custom_test/02_quicklook
```

---

## 🎓 Educational Value

### Skills Demonstrated
- **Manual demultiplexing**: Understanding barcode-based sample separation
- **Quality control workflow**: Multi-step data preparation
- **Format conversions**: FASTQ → FASTA → corrected FASTA
- **GUI tool usage**: Real-world bioinformatics software

### Comparison with ONT Native
- **Flexibility**: Custom primer designs
- **Complexity**: More manual steps required
- **Control**: Fine-tuned barcode assignment
- **Time**: Longer setup, similar analysis time

### Real-World Applications
- **Environmental DNA**: Custom primer sets for specific taxa
- **Ancient DNA**: Modified protocols for degraded samples  
- **Multi-gene approaches**: Different amplicons in same library
- **Research applications**: Novel barcode designs

---

## 📈 Interpreting Results

### Demultiplexing Quality Assessment
- **Assignment rate**: >80% indicates good barcode design
- **Sample balance**: Similar read counts suggest even PCR amplification
- **Unassigned reads**: <20% is acceptable for most applications

### Cross-Sample Analysis
- **Species overlap**: Related samples should share species
- **Unique species**: Different sites may have unique fauna
- **Abundance patterns**: Ecological interpretation of species distributions

### Method Validation
- **Compare with ONT Native**: Run same samples through both workflows
- **Technical replicates**: Assess reproducibility across replicates
- **Positive controls**: Validate with known species mixtures

---

## 🔗 Next Steps

### After Running This Workflow
1. **Compare demultiplexing efficiency** - Review assignment rates
2. **Validate species identifications** - Cross-reference with known fauna
3. **Optimize parameters** - Adjust filtering for your specific application
4. **Scale to real samples** - Apply to your research data

### For Your Own Data
1. **Design barcode scheme** - Ensure unique, non-overlapping barcodes
2. **Create demux sheet** - Map samples to barcode combinations
3. **Test with subset** - Validate workflow before full analysis
4. **Document protocol** - Record successful parameter combinations

### Integration with ONT Native
1. **Compare workflows** - Same data through both pipelines
2. **Benchmark performance** - Speed vs. flexibility trade-offs
3. **Choose optimal approach** - Based on your research needs

---

**🎯 This workflow provides complete control over the demultiplexing process while maintaining the power of the DeCodeDNA analysis pipeline!**