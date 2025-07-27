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

## 🎓 Learning Progression

**For FHL Course Strategy:**
1. **First**: Complete ONT Native workflow (learn pipeline basics with 12S data)
2. **Then**: Practice Custom CCI demultiplexing (understand the process)  
3. **Finally**: Analyze real Custom CCI data (apply to your research samples)

### **Why Start with ONT Native?**
- Simpler workflow helps you learn the core pipeline steps
- Pre-demultiplexed data lets you focus on bioinformatics concepts
- Shorter amplicons (12S ~200-300bp) process faster for learning

### **Why 2500bp D-loop Mock Data?**
- **Research relevance**: Mitochondrial control region is highly variable for species ID
- **Technical challenge**: Longer reads test quality filtering and consensus calling
- **Phylogenetic value**: Suitable for species identification and detailed haplotyping
- **Real-world preparation**: Similar to what you'd encounter in actual research projects
- **Method comparison**: Shows how pipeline handles different amplicon lengths

---

## 📁 Files in this directory:

```
workflows/custom_cci_barcodes/
├── 00_raw_data/
│   └── test_fhl_customcci.fastq    # Raw pooled data (all samples together)
├── 01_filtered/                    # Quality-filtered data (created by pipeline)
├── 02_demultiplexed/              # Pre-demultiplexed mock data (for robust pipeline analysis)
│   ├── sample1.fa                 # Individual sample files (ready for analysis)
│   ├── sample2.fa                 # Real demultiplexed data
│   └── sample3.fa
├── 02_demultiplexed_demo/         # Practice directory (ONTbarcoder output for learning)
└── demux_config/
    └── demux_sheet.csv            # Demultiplexing configuration example
```

### **File Purposes:**
- **Raw pooled data**: All samples sequenced together, requiring separation
- **Pre-demultiplexed data**: Ready-to-use mock data for pipeline learning
- **Practice demo directory**: For ONTbarcoder demultiplexing practice
- **Demux configuration**: CSV file mapping barcodes to sample names
- **2500bp D-loop sequences**: Long mitochondrial control region data for advanced analysis

---

## 🚀 Complete Workflow Options

### **OPTION A: Practice Demultiplexing (Learning Exercise)**

**Purpose**: Learn the demultiplexing process with ONTbarcoder2.3 GUI  
**Time**: ~15-20 minutes  
**Best for**: Understanding custom barcode tag handling

```bash
# Navigate to this directory first
cd workflows/custom_cci_barcodes/

# Step 1: Quality filter raw pooled data (3-5 min)
# • Removes low-quality reads before demultiplexing (improves accuracy)
# • Input: Raw pooled FASTQ | Output: Quality-filtered pooled data
bash ../../scripts/00_quality_filter_predemux.sh 00_raw_data/test_fhl_customcci.fastq

# Step 2: Manual demultiplexing practice with GUI (10-15 min)
# • Use ONTbarcoder2.3 GUI to separate samples by barcode sequences
# • Input: 01_filtered/quality_filtered.fastq
# • Config: demux_config/demux_sheet.csv  
# • Output: 02_demultiplexed_demo/*.fa (practice files)
# • NOTE: This is for learning only - pipeline uses pre-demultiplexed data

# Step 3: Base conversion practice (1-2 min)
# • Convert ONTbarcoder output format for pipeline compatibility
cd 02_demultiplexed_demo/
bash ../../../scripts/EFPQ_ontbarcoder_convert.sh
cd ..
```

### **OPTION B: Full Pipeline Analysis (Robust Results)**

**Purpose**: Complete analysis with pre-demultiplexed mock data  
**Time**: ~15-20 minutes  
**Best for**: Learning the core pipeline and getting reliable results

```bash
# Navigate to this directory first
cd workflows/custom_cci_barcodes/

# Core pipeline analysis using robust pre-demultiplexed data (15-20 min)
# • Same 4-step analysis as ONT Native workflow
# • Quality control → Consensus → Denoising → Taxonomy
bash ../../scripts/02_quick_look_clean.sh 02_demultiplexed/ ../../results/custom_cci_02_quicklook
bash ../../scripts/03_consensus_sort.sh ../../results/custom_cci_02_quicklook ../../results/custom_cci_03_consensus
bash ../../scripts/04_denoise.sh ../../results/custom_cci_03_consensus ../../results/custom_cci_04_denoise
bash ../../scripts/05_taxonomic_assignment.sh ../../results/custom_cci_04_denoise ../../results/custom_cci_05_taxonomy

# View results
open ../../results/custom_cci_05_taxonomy/04_krona_plots/*.html
```

### **OPTION C: Complete Workflow (Advanced)**

**Purpose**: Full experience from raw data through analysis  
**Time**: ~25-35 minutes  
**Best for**: Research preparation and complete workflow mastery

```bash
# Combine both options for complete experience
# 1. Practice demultiplexing (Option A steps 1-3)
# 2. Then run pipeline analysis (Option B)
# 3. Compare results between practice and robust data
```

---

## 🎓 What you'll learn:

### **Workflow Management Skills:**
- **Pre-demultiplexing quality filtering**: Why filter before sample separation
- **Manual demultiplexing**: Using ONTbarcoder2.3 GUI for custom barcode schemes
- **File format conversion**: Handling ONTbarcoder EFPQ output format
- **Custom primer design**: Understanding primer-barcode combinations
- **Data flow management**: Practice vs production data handling

### **Advanced Bioinformatics Expertise:**
- **Long amplicon analysis**: Working with 2500bp mitochondrial sequences vs 200-300bp
- **Quality assessment**: Managing longer reads and their unique challenges
- **Complete pipeline mastery**: End-to-end processing from raw data to species tables
- **Research applications**: Preparing for real-world custom eDNA projects
- **Method comparison**: Understanding when custom approaches are worth the complexity

### **Technical Skills:**
- **Custom barcode design principles**: Hamming distance, error resilience
- **ONT-specific considerations**: Error profiles and correction strategies
- **Research workflow planning**: Wet lab → bioinformatics integration
- **Troubleshooting**: Debugging demultiplexing and format conversion issues

---

## 📊 Expected results:

### **From Practice Demultiplexing (Option A):**
- **Experience**: Understanding ONTbarcoder2.3 GUI workflow
- **File handling**: Practice with EFPQ format conversion
- **Skills**: Demultiplexing troubleshooting and optimization

### **From Pipeline Analysis (Option B):**
- **Demultiplexed samples**: 3-4 individual sample files from 2500bp D-loop data
- **Species identified**: 10-30 fish species from mitochondrial control region sequences
- **Processing time**: 15-20 minutes for core pipeline
- **Comparative data**: Results to compare with ONT Native 12S workflow

### **Key Learning Outcomes:**
- Understand when to use custom vs standard barcode approaches
- Master manual demultiplexing for research applications
- Analyze longer amplicons and their unique challenges
- Prepare for processing your own field collection data
- Appreciate the trade-offs between standardized and custom approaches

---

## 🔧 Demultiplexing Guide

### **Step-by-Step ONTbarcoder2.3 Usage:**

**📖 Tool Documentation:** [ONTbarcoder GitHub Repository](https://github.com/HeatherKates/ONTbarcoder)

1. **Open ONTbarcoder2.3 GUI application**
2. **Load input file**: `01_filtered/quality_filtered.fastq`
3. **Load demux sheet**: `demux_config/demux_sheet.csv`
4. **Configure settings**:
   - Output directory: `02_demultiplexed_demo/` (for practice)
   - File format: FASTA (.fa)
   - Quality threshold: Default (12)
   - **Advanced tip**: Adjust threshold based on your barcode design quality
5. **Run demultiplexing** (5-10 minutes)
6. **Verify output**: Check for individual sample files in output directory
7. **Convert format**: Run EFPQ conversion script for pipeline compatibility

### **Demux Sheet Format (demux_config/demux_sheet.csv):**
```csv
sample_name,barcode_sequence
sample1,AACGTTAACGTTAACGTT
sample2,TTGCAATTGCAATTGCAA
sample3,CCGTAACCGTAACCGTAA
```

### **Quality vs Assignment Trade-offs:**
- **Higher thresholds (15-18)**: More accurate assignments, fewer total reads
- **Lower thresholds (8-12)**: More reads assigned, potential for more errors
- **Sweet spot (12-15)**: Balance accuracy and yield for most applications

### **Optimizing Demultiplexing Success:**
- **Barcode design**: Ensure sufficient Hamming distance between sequences (≥3 differences)
- **Quality thresholds**: Balance between assignment rate and accuracy
- **Primer-barcode junction**: Verify clean transitions in your design
- **Error correction**: Consider redundancy in barcode design for ONT error profiles
- **Read quality**: Pre-filtering improves downstream assignment accuracy

### **Troubleshooting Demultiplexing:**
- **No output files**: 
  - Check barcode sequences match your primer design exactly
  - Verify file paths and permissions
  - Ensure demux sheet format is correct
- **Low assignment rates**: 
  - Adjust quality threshold (try 10-15 range)
  - Verify primer-barcode junction sequences
  - Check for insufficient Hamming distance between barcodes
  - Review raw data quality distribution
- **EFPQ format issues**: 
  - Ensure base conversion step is completed before pipeline
  - Check that EFPQ_ontbarcoder_convert.sh script is accessible
- **Poor separation**: 
  - Consider redesigning barcodes with better error resilience
  - Review barcode placement and primer design
  - Test with known positive controls

---

## 🆚 Custom CCI vs ONT Native Comparison

| Feature | Custom CCI Workflow | ONT Native Workflow |
|---------|-------------------|-------------------|
| **PCR Steps** | One-step (primer + barcode) | Two-step (amplify → tag) |
| **Demultiplexing** | Manual (ONTbarcoder2.3) | Automated (MinKNOW/Dorado) |
| **Primer Design** | Complete flexibility | Limited to ONT kits |
| **Sample Capacity** | Unlimited (custom design) | 24-96 samples (kit limited) |
| **Mock Data** | 2500bp D-loop sequences | 200-300bp 12S sequences |
| **Learning Curve** | Steeper (more steps) | Gentler (ready data) |
| **Research Value** | High (real-world skills) | Medium (standardized) |
| **Processing Time** | 25-35 minutes (full) | 15-20 minutes |
| **Cost per Sample** | Lower (bulk reagents) | Higher (kit costs) |
| **Troubleshooting** | More complex | More standardized |
| **Applications** | Research, novel targets | Standardized surveys |

---

## 🔬 When to Choose Custom CCI

### **Best Applications:**
- **Novel target genes**: When standard primers don't exist
- **Large-scale studies**: 100+ samples benefit from cost efficiency
- **Specific organism groups**: Designing taxon-specific primers
- **Research projects**: When flexibility outweighs standardization
- **One-step workflows**: Simplifying wet lab procedures

### **Consider ONT Native Instead:**
- **Learning bioinformatics**: Focus on analysis over technical steps
- **Small sample sizes**: ≤24 samples where kit costs are reasonable
- **Standardized targets**: Well-established gene regions (12S, COI)
- **Quick surveys**: When speed trumps customization
- **Collaborative projects**: Ensuring reproducibility across labs

---

## 💡 Next Steps & Applications

### **Immediate Next Steps:**
1. **Complete this workflow** with the 2500bp D-loop mock data
2. **Compare results** with ONT Native workflow outcomes
3. **Analyze differences** in species detection between amplicon lengths
4. **Practice troubleshooting** demultiplexing issues

### **Research Applications:**
1. **Design custom primers** for your target organisms/genes
2. **Plan barcode schemes** with sufficient Hamming distances
3. **Apply to field samples** using your custom CCI approach
4. **Advanced analysis**: Use consensus sequences for phylogenetics or haplotyping

### **Advanced Techniques:**
- **Haplotype analysis**: Longer amplicons enable detailed genetic variation studies
- **Phylogenetic reconstruction**: 2500bp sequences provide better resolution
- **Population genetics**: Custom primers can target specific variable regions
- **Metabarcoding optimization**: Design primers for your specific ecosystem

---

## 🔗 Related Workflows & Resources

### **Course Progression:**
- **Prerequisites**: Complete [ONT Native workflow](../ont_native_barcodes/README_ont_native.md) first
- **Next step**: Apply Custom CCI to your field collection data
- **Advanced**: Combine results with phylogenetic analysis tools

### **Technical Resources:**
- **Main documentation**: [DeCodeDNA README.md](../../README.md)
- **Installation guide**: [installation_guide.md](../../installation_guide.md)
- **Database setup**: Scripts 01 in main README
- **Troubleshooting**: Comprehensive guide in main README

### **Scientific Background:**
- **Custom primer design**: Review amplicon length vs taxonomic resolution trade-offs
- **Barcode optimization**: Study Hamming distance calculations for your application
- **ONT error profiles**: Understand systematic errors for better primer design
- **Comparative genomics**: Use longer amplicons for detailed evolutionary studies

---

**📖 For comprehensive installation, database setup, and troubleshooting, see the [main README.md](../../README.md)**

**💡 Remember**: This workflow builds advanced skills for research applications. Start with ONT Native for pipeline basics, then return here for custom design mastery!