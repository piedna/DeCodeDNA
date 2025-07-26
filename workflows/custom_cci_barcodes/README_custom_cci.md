# Custom CCI Barcode Tags Workflow

**Complete workflow for custom primer-barcode combinations**

✅ **Perfect for**: One-step PCR workflows, custom primer designs, research applications  
🎯 **Goal**: Complete wet lab → bioinformatics pipeline with manual demultiplexing  
📊 **Dataset**: 2500bp D-loop fish mock data (mitochondrial control region)

---

## 🧬 What are Custom CCI Barcode Tags?

**Custom CCI (Custom Concatenated Index) Barcode Tags** combine your custom primers with unique barcode sequences in a single PCR step:
- **One-step PCR**: Amplify target + add custom barcodes simultaneously
- **Research flexibility**: Design primers for any gene region or organism group
- **Unlimited multiplexing**: Scale from dozens to thousands of samples (not limited to 24/96 like ONT Native)
- **Manual demultiplexing**: Requires ONTbarcoder2.3 GUI for sample separation
- **Complete control**: Full customization of primer and barcode combinations

### **Advanced Design Principles:**
- **Hamming distance optimization**: Sufficient sequence differences between barcodes ensure accurate sample assignment
- **ONT error-aware design**: Custom primers incorporate redundancy bases and strategic positioning to combat Oxford Nanopore's specific error profile
- **Center randomization**: Unique central regions improve demultiplexing accuracy
- **Longer shelf life**: These are stored pretty stably under the wet-laboratory settings

### **The Demultiplexing Challenge:**
Improving demultiplexing rates for custom barcodes remains an active area of research and optimization. While more complex than standardized approaches, the investment in custom design provides long-term flexibility and research independence.

**vs ONT Native**: ONT Native uses Oxford Nanopore's standardized barcode kits (limited to 24-96 samples) with two-step PCR and automated demultiplexing

---

## 📁 Files in this directory:

```
workflows/custom_cci_barcodes/
├── 00_raw_data/
│   └── test_fhl_customcci.fastq    # Raw pooled data (all samples together)
├── 01_filtered/                    # Quality-filtered data (created by pipeline)
├── 02_demultiplexed/              # ONTbarcoder output (you create this)
│   ├── sample1.fa                 # Individual sample files
│   ├── sample2.fa                 # (after demultiplexing)
│   └── sample3.fa
└── demux_config/
    └── demux_sheet.csv            # Demultiplexing configuration
```

### **File Purposes:**
- **Raw pooled data**: All samples sequenced together, requiring separation
- **Demux configuration**: CSV file mapping barcodes to sample names
- **Individual samples**: Separated files ready for analysis after demultiplexing
- **2500bp D-loop mock data**: Long mitochondrial control region sequences for educational purposes

---

## 🚀 Complete workflow (25-35 minutes):

```bash
# Navigate to this directory first
cd workflows/custom_cci_barcodes/

# Step 1: Quality filter raw pooled data (3-5 min)
# • Removes low-quality reads before demultiplexing (improves accuracy)
# • Input: Raw pooled FASTQ | Output: Quality-filtered pooled data
bash ../../scripts/00_quality_filter_predemux.sh 00_raw_data/test_fhl_customcci.fastq 01_filtered/quality_filtered.fastq

# Step 2: Manual demultiplexing with GUI (5-10 min)
# • Use ONTbarcoder2.3 GUI to separate samples by barcode sequences
# • Input: 01_filtered/quality_filtered.fastq
# • Config: demux_config/demux_sheet.csv  
# • Output: 02_demultiplexed/*.fa (individual sample files)

# Step 3: Base conversion (1-2 min)
# • Convert ONTbarcoder output format for pipeline compatibility
# • Required: ONTbarcoder outputs EFPQ format, pipeline needs standard FASTA
cd 02_demultiplexed/
bash ../../../scripts/EFPQ_ontbarcoder_convert.sh
cd ..

# Step 4: Core pipeline analysis (15-20 min)
# • Same 4-step analysis as ONT Native workflow
# • Quality control → Consensus → Denoising → Taxonomy
bash ../../scripts/02_quick_look_clean.sh 02_demultiplexed/ ../../results/custom_cci_results/02_quicklook
bash ../../scripts/03_consensus_sort.sh ../../results/custom_cci_results/02_quicklook ../../results/custom_cci_results/03_consensus
bash ../../scripts/04_denoise.sh ../../results/custom_cci_results/03_consensus ../../results/custom_cci_results/04_denoise
bash ../../scripts/05_taxonomic_assignment.sh ../../results/custom_cci_results/04_denoise ../../results/custom_cci_results/05_taxonomy

# Step 5: View results
open ../../results/custom_cci_results/05_taxonomy/04_krona_plots/*.html
```

---

## 🎓 What you'll learn:

### **Advanced Workflow Skills:**
- **Pre-demultiplexing quality filtering**: Why filter before sample separation
- **Manual demultiplexing**: Using ONTbarcoder2.3 GUI for custom barcode schemes
- **File format conversion**: Handling ONTbarcoder EFPQ output format
- **Custom primer design**: Understanding primer-barcode combinations

### **Bioinformatics Expertise:**
- **Long amplicon analysis**: Working with 2500bp mitochondrial sequences
- **Quality assessment**: Managing longer reads and their challenges
- **Complete pipeline mastery**: End-to-end processing from raw data to species tables
- **Research applications**: Preparing for real-world custom eDNA projects

---

## 📊 Expected results:

- **Demultiplexed samples**: 3-4 individual sample files from pooled data
- **Species identified**: 10-30 fish species from 2500bp D-loop sequences
- **Processing time**: 25-35 minutes total (including demultiplexing)
- **Skills gained**: Complete wet lab → analysis workflow for custom designs

### **Key Learning Outcomes:**
- Understand when to use custom vs standard barcode approaches
- Master manual demultiplexing for research applications
- Analyze longer amplicons (2500bp vs 200-300bp in ONT Native)
- Prepare for processing your own field collection data

---

## 🔧 Demultiplexing Guide

### **Step-by-Step ONTbarcoder2.3 Usage:**

**📖 Tool Documentation:** [ONTbarcoder GitHub Repository](https://github.com/HeatherKates/ONTbarcoder)

1. **Open ONTbarcoder2.3 GUI application**
2. **Load input file**: `01_filtered/quality_filtered.fastq`
3. **Load demux sheet**: `demux_config/demux_sheet.csv`
4. **Configure settings**:
   - Output directory: `02_demultiplexed/`
   - File format: FASTA (.fa)
   - Quality threshold: Default (12)
   - **Advanced tip**: Adjust threshold based on your barcode design quality
5. **Run demultiplexing** (5-10 minutes)
6. **Verify output**: Check for individual sample files in `02_demultiplexed/`

### **Demux Sheet Format (demux_config/demux_sheet.csv):**
```csv
sample_name,barcode_sequence
sample1,AACGTTAACGTTAACGTT
sample2,TTGCAATTGCAATTGCAA
sample3,CCGTAACCGTAACCGTAA
```

### **Optimizing Demultiplexing Success:**
- **Barcode design**: Ensure sufficient Hamming distance between sequences
- **Quality thresholds**: Balance between assignment rate and accuracy
- **Primer-barcode junction**: Verify clean transitions in your design
- **Error correction**: Consider redundancy in barcode design for ONT error profiles

### **Troubleshooting Demultiplexing:**
- **No output files**: Check barcode sequences match your primer design exactly
- **Low assignment rates**: 
  - Adjust quality threshold (try 10-15 range)
  - Verify primer-barcode junction sequences
  - Check for insufficient Hamming distance between barcodes
- **EFPQ format issues**: Ensure base conversion step (Step 3) is completed
- **Poor separation**: Consider redesigning barcodes with better error resilience

---

## 🆚 Custom CCI vs ONT Native Comparison

| Feature | Custom CCI Workflow | ONT Native Workflow |
|---------|-------------------|-------------------|
| **PCR Steps** | One-step (primer + barcode) | Two-step (amplify → tag) |
| **Demultiplexing** | Manual (ONTbarcoder2.3) | Automated (MinKNOW/Dorado) |
| **Primer Design** | Complete flexibility | Limited to ONT kits |
| **Mock Data** | 2500bp D-loop sequences | 200-300bp 12S sequences |
| **Learning Curve** | Steeper (more steps) | Gentler (ready data) |
| **Research Value** | High (real-world skills) | Medium (standardized) |
| **Processing Time** | 25-35 minutes | 15-20 minutes |

---

## 💡 Next steps:

1. **Complete this workflow** with the 2500bp D-loop mock data
2. **Compare results** with ONT Native workflow outcomes
3. **Design custom primers** for your target organisms/genes
4. **Apply to field samples** using your custom CCI approach
5. **Advanced analysis**: Use consensus sequences for phylogenetics or haplotyping

---

## 🔗 Related Workflows

- **Start here if**: You need custom primer designs or one-step PCR workflows
- **Try ONT Native first**: If you're new to eDNA bioinformatics ([ONT Native README](../ont_native_barcodes/README_ont_native.md))
- **Advanced applications**: Custom CCI is ideal for research projects requiring specific primer combinations

**📖 See [main README.md](../../README.md) for installation, database setup, and comprehensive troubleshooting.**