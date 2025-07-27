# ONT Native Barcode Tags Workflow

**Quick start for ONT Native Barcode Tags (standard workflow)**

✅ **Perfect for**: Two-step PCR workflows, standardized sample multiplexing, learning bioinformatics basics  
🎯 **Goal**: Master the core eDNA analysis pipeline with ready-to-analyze data  
📊 **Dataset**: 12S fish community mock data (~200-300bp amplicons)

---

## 🧬 What are ONT Native Barcode Tags?

**ONT Native Barcode Tags** use Oxford Nanopore's official barcoding system (they call it "Native" because it's built into their platform):
- **eDNA workflow-compatible kits**: NBD114.24, NBD114.96, EXP-PBC096 
- **Two-step PCR**: Amplify target → Add ONT barcode tags → Sequence
- **Integrated demultiplexing**: Built into MinKNOW GUI or Dorado command line
- **Ready-to-analyze**: Demultiplexing happens during basecalling, no manual steps
- **Standardized approach**: Reproducible across labs and studies

### **Why Start Here?**
- **Learning focus**: Concentrate on bioinformatics without demultiplexing complexity
- **Faster results**: Pre-demultiplexed data means quicker pipeline completion
- **Core concepts**: Master quality control, clustering, and taxonomic assignment
- **Foundation building**: Essential skills before tackling custom approaches

**vs Custom CCI**: Custom primer-barcode combinations require manual demultiplexing with ONTbarcoder2.3 but offer unlimited design flexibility

---

## 🎓 Learning Strategy

### **Course Progression (FHL Recommended Path):**
1. **Start here (ONT Native)** → Learn pipeline basics with 12S mock data
2. **Practice Custom CCI** → Understand manual demultiplexing  
3. **Apply to real samples** → Use Custom CCI for your field collections

### **Why 12S Fish Community Mock Data?**
- **Educational standard**: Well-characterized fish community for learning
- **Manageable size**: ~200-300bp amplicons process quickly
- **Clear results**: Easily interpretable species identifications
- **Method comparison**: Perfect for comparing clustering approaches
- **Foundation knowledge**: Prepares you for longer, more complex amplicons

### **Skills You'll Master:**
- **Pipeline flow**: Understanding the 4-step analysis process
- **Quality assessment**: Recognizing good vs problematic ONT data
- **Method comparison**: vsearch vs amplicon_sorter clustering
- **Result interpretation**: Reading species tables and Krona plots
- **Parameter optimization**: Adjusting thresholds for your data

---

## 📁 Files in this directory:

```
workflows/ont_native_barcodes/
├── test_fhl_100k_3.fastq       # 100K read subset - fast demo/testing (5-10 min)
├── test_fhl_150k_2.fastq       # 150K read subset - medium analysis (10-15 min)
├── test_fhl_200k_1.fastq       # 200K read subset - full analysis (15-20 min)
├── fast5/                      # Legacy FAST5 files (educational)
├── pod5_barcode50/             # Modern POD5 files (basecalling demo)
└── precomputed/                # Pre-computed amplicon_sorter results
    ├── mock_amplicon_sorter_clustered_consensus_1.fasta  # Sample 1 results
    ├── mock_amplicon_sorter_clustered_consensus_2.fasta  # Sample 2 results
    └── mock_amplicon_sorter_clustered_consensus_3.fasta  # Sample 3 results
```

### **File Purposes & Selection Guide:**
- **100K reads (Sample 3)**: Quick demos, testing installation, learning basics
- **150K reads (Sample 2)**: Balanced analysis, good for method comparison
- **200K reads (Sample 1)**: Full analysis, most comprehensive results
- **FAST5/POD5**: Educational files for understanding ONT data formats (optional basecalling demo)
- **Pre-computed results**: Server-generated amplicon_sorter consensus for time-saving comparison

### **Which File Size for What?**
- **First time**: Start with 100K reads to learn the pipeline quickly
- **Learning**: Use 150K reads for balanced analysis and method comparison
- **Research practice**: Use 200K reads for most comprehensive species detection
- **Time constraints**: 100K reads complete in ~10 minutes vs 20 minutes for 200K

---

## 🚀 Complete Pipeline Workflow

### **Quick Start (15-20 minutes with 200K reads):**

```bash
# Navigate to this directory first
cd workflows/ont_native_barcodes/

# Step 1: Quality control & taxonomic classification (3-5 min)
# • Filters sequences by quality (Q≥12) and length (100-500bp)
# • Classifies against fish databases to remove off-target sequences
# • Input: Raw FASTQ | Output: Clean fish sequences + classification reports
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_02_quicklook

# Step 2: Consensus building (5-8 min)  
# • vsearch: Fast local clustering (runs automatically)
# • amplicon_sorter: Advanced ONT-specific clustering (demo commands provided)
# • Input: Classified sequences | Output: Representative consensus sequences
bash ../../scripts/03_consensus_sort.sh ../../results/ont_native_02_quicklook ../../results/ont_native_03_consensus

# Step 3: LULU denoising (3-7 min)
# • Removes sequencing errors and PCR artifacts using co-occurrence patterns
# • Input: Consensus sequences | Output: Curated OTU tables and clean sequences
bash ../../scripts/04_denoise.sh ../../results/ont_native_03_consensus ../../results/ont_native_04_denoise

# Step 4: Final taxonomic assignment (5-10 min)
# • BLAST: Similarity-based assignment against multiple databases
# • Kraken2: K-mer based rapid classification
# • TaxonKit LCA: Consensus taxonomy from multiple BLAST hits (most robust)
# • Krona plots: Interactive visualizations for exploring results
bash ../../scripts/05_taxonomic_assignment.sh ../../results/ont_native_04_denoise ../../results/ont_native_05_taxonomy

# Step 5: View results
open ../../results/ont_native_05_taxonomy/04_krona_plots/*.html
```

### **Fast Demo (10-12 minutes with 100K reads):**

```bash
# Use smaller dataset for quick learning
export SUBSET_COUNT=1000  # Limit taxonomic assignment for speed
bash ../../scripts/02_quick_look_clean.sh . ../../results/demo_02_quicklook
bash ../../scripts/03_consensus_sort.sh ../../results/demo_02_quicklook ../../results/demo_03_consensus
bash ../../scripts/04_denoise.sh ../../results/demo_03_consensus ../../results/demo_04_denoise
bash ../../scripts/05_taxonomic_assignment.sh ../../results/demo_04_denoise ../../results/demo_05_taxonomy
```

### **Custom Parameters (Advanced):**

```bash
# Example: Stricter quality filtering for research
export QUALITY_THRESHOLD=15 MIN_LENGTH=150 MAX_LENGTH=350 DATABASES="mitofish"
bash ../../scripts/02_quick_look_clean.sh . ../../results/strict_02_quicklook
# Continue with remaining steps...
```

---

## 🎓 What You'll Learn

### **Essential Bioinformatics Skills:**
- **Quality assessment**: Understanding ONT data characteristics and quality metrics
- **Taxonomic classification**: Multiple database approaches (12S, COI, MitoFish)
- **Sequence clustering**: vsearch vs amplicon_sorter comparison and trade-offs
- **Error correction**: LULU algorithm for removing sequencing artifacts
- **Data visualization**: Interactive Krona plots for exploring taxonomic results
- **Method validation**: Comparing BLAST vs Kraken2 classification approaches

### **ONT-Specific Knowledge:**
- **File formats**: FAST5 (legacy) vs POD5 (modern) and their uses
- **Barcode tag workflows**: How native barcoding simplifies downstream analysis
- **Performance trade-offs**: Local vs server-optimized processing considerations
- **Read characteristics**: Understanding length distributions and quality patterns

### **Pipeline Management:**
- **Workflow design**: Understanding the 4-step eDNA analysis process
- **Parameter optimization**: Adjusting quality and length thresholds
- **Result interpretation**: Reading OTU tables and abundance matrices
- **Troubleshooting**: Common issues and their solutions

### **Research Preparation:**
- **Method comparison**: When to use different clustering approaches
- **Database selection**: Choosing appropriate reference databases
- **Result validation**: Cross-checking taxonomic assignments
- **Scaling considerations**: From mock data to real research datasets

---

## 📊 Expected Results & Interpretation

### **Typical Outputs:**
- **Species identified**: 10-30 fish species from mock community
- **Processing time**: 
  - 100K reads: ~10-12 minutes
  - 150K reads: ~12-15 minutes  
  - 200K reads: ~15-20 minutes
- **File outputs**: Species abundance tables, interactive plots, consensus sequences

### **Key Result Files:**
- **Species tables**: `*_classified_species.csv` - Final abundance matrices for each method
- **TaxonKit LCA**: `TaxonKit_LCA_species_abundance.csv` - Most robust consensus taxonomy
- **Interactive plots**: `*.krona.html` - Explore taxonomic composition by method
- **Consensus sequences**: `otu_representatives_*.fasta` - For custom downstream analysis
- **Method comparison**: `Overall_Method_Comparison.csv` - Performance summary

### **What to Look For:**
- **Species richness**: How many different fish species were detected
- **Method agreement**: Do BLAST and Kraken2 give similar results?
- **Quality patterns**: Are longer/higher quality reads giving better assignments?
- **Database differences**: How do 12S vs COI vs MitoFish compare?

### **Common Patterns in Mock Data:**
- **Core community**: Consistent species detected across all methods
- **Method-specific detections**: Some species only found by certain approaches
- **Abundance patterns**: Relative frequencies should be consistent
- **Quality relationships**: Better quality reads typically give more confident assignments

---

## 🔧 Understanding ONT Native Workflows

### **Demultiplexing Context:**

**Why these files are "ready-to-go":**

ONT Native workflows include **integrated demultiplexing** that happens during basecalling:

### **Option 1: MinKNOW GUI (Real-time)**
- Toggle demultiplexing **during sequencing with live basecalling** in MinKNOW interface
- Select your barcode kit (NBD114.24, NBD114.96, EXP-PBC096) → automatic sample separation
- Get individual sample files directly from sequencer
- **Best for**: Live monitoring and immediate sample separation

### **Option 2: Dorado Command Line (Post-sequencing)**
```bash
# During basecalling (recommended - one step)
dorado basecaller [model] [pod5_dir] --kit-name SQK-NBD114-24 --emit-fastq

# Or post-basecalling demultiplexing (two steps)
dorado basecaller [model] [pod5_dir] --emit-fastq > pooled.fastq
dorado demux --output-dir demux_output --kit-name EXP-PBC096 --emit-fastq pooled.fastq
```

**Supported kits:** NBD114.24, NBD114.96, EXP-PBC096

**Result:** Individual sample files (like our `test_fhl_*` files) ready for analysis - no manual demultiplexing needed!

### **Workflow Advantages:**
- **Standardized**: Reproducible across labs and studies
- **Automated**: Minimal manual intervention required
- **Optimized**: Oxford Nanopore continuously improves algorithms
- **Educational**: Focus on analysis rather than technical details
- **Scalable**: Easy to process 24-96 samples consistently

### **When to Use ONT Native:**
- **Learning bioinformatics**: Focus on analysis skills
- **Standardized surveys**: Consistent methodology across studies
- **Small-medium studies**: 24-96 samples where kit costs are reasonable
- **Collaborative projects**: Ensuring reproducibility across labs
- **Teaching environments**: Minimize technical complexity

---

## 🆚 Comparison with Custom CCI

| Feature | ONT Native (This Workflow) | Custom CCI Workflow |
|---------|---------------------------|-------------------|
| **Learning curve** | Gentle (focus on analysis) | Steeper (includes demultiplexing) |
| **Setup time** | Quick (ready files) | Longer (demultiplexing step) |
| **Mock data** | 12S fish (~200-300bp) | D-loop fish (~2500bp) |
| **Demultiplexing** | Automated (built-in) | Manual (ONTbarcoder2.3) |
| **Sample capacity** | 24-96 samples (kit limited) | Unlimited (custom design) |
| **Primer flexibility** | Limited to kit compatibility | Complete design freedom |
| **Research applications** | Standardized surveys | Novel targets, large studies |
| **Educational value** | Pipeline mastery | Complete workflow mastery |
| **Best for beginners** | ✅ Yes - start here | After mastering ONT Native |

---

## ⚙️ Advanced Options & Customization

### **Performance Tuning:**
```bash
# Fast demo mode (classroom)
export DATABASES="mitofish" THREADS=4 SUBSET_COUNT=500

# High-quality analysis (research)
export QUALITY_THRESHOLD=15 MIN_LENGTH=150 MAX_LENGTH=350

# Server-optimized (high-performance)
export THREADS=32 SUBSET_COUNT=0 CONFIDENCE=0.1
```

### **Database Selection:**
- **"mitofish"**: Fish-only analysis (fastest)
- **"12s coi"**: Dual-gene approach (comprehensive)
- **"12s coi mitofish"**: All databases (most thorough)

### **File Size Recommendations:**
- **Teaching**: 100K reads for quick demos
- **Learning**: 150K reads for balanced analysis
- **Research practice**: 200K reads for comprehensive results

### **Optional: Basecalling Demo (Script 00):**
```bash
# Educational demonstration of basecalling process
# Uses included POD5 files to show basecalling → FASTQ conversion
bash ../../scripts/00_basecalling_demo.sh pod5_barcode50/
```

---

## 🎯 Next Steps & Progression

### **Immediate Next Steps:**
1. **Complete this workflow** with different file sizes (100K → 150K → 200K)
2. **Compare results** between different read counts and parameter settings
3. **Examine outputs** in detail - understand what each file contains
4. **Practice customization** by adjusting quality thresholds and databases

### **Advanced Learning:**
1. **Try Custom CCI workflow** → Learn manual demultiplexing ([Custom CCI README](../custom_cci_barcodes/README_custom_cci.md))
2. **Compare methodologies** → Understand when to use each approach
3. **Apply to real data** → Use Custom CCI for your field collections
4. **Explore advanced analysis** → Phylogenetics, haplotyping, population genetics

### **Research Applications:**
- **Use these consensus sequences** for downstream phylogenetic analysis
- **Combine multiple samples** to build community matrices
- **Compare with traditional morphological surveys** 
- **Develop site-specific reference databases**

### **Skills Ready for Real Research:**
✅ **Quality assessment** of ONT eDNA data  
✅ **Method comparison** and validation  
✅ **Result interpretation** and visualization  
✅ **Pipeline troubleshooting** and optimization  
✅ **Parameter customization** for specific applications

---

## 🔗 Related Resources & Support

### **Course Materials:**
- **Next step**: [Custom CCI Workflow](../custom_cci_barcodes/README_custom_cci.md)
- **Main documentation**: [DeCodeDNA README.md](../../README.md)
- **Installation guide**: [installation_guide.md](../../installation_guide.md)

### **Technical Support:**
- **Pipeline issues**: Check main README troubleshooting section
- **Database problems**: Run `source scripts/setup_databases.sh`
- **Performance optimization**: Adjust parameters in advanced options above

### **Scientific Background:**
- **12S metabarcoding**: Understand why this gene region is used for fish
- **Clustering algorithms**: Learn about vsearch vs amplicon_sorter trade-offs
- **Error correction**: Study LULU algorithm and co-occurrence patterns
- **Taxonomic assignment**: Compare similarity vs k-mer classification approaches

---

## 💡 Tips for Success

### **First-Time Users:**
- Start with **100K reads** to learn quickly
- Read through outputs carefully to understand what each step produces
- Don't worry about perfect results - focus on understanding the process
- Ask questions about anything that seems unclear

### **Troubleshooting:**
- **No species detected**: Check database setup with `source scripts/setup_databases.sh`
- **Long processing times**: Try smaller file or reduce SUBSET_COUNT
- **Memory issues**: Reduce THREADS parameter or use smaller dataset
- **Missing outputs**: Check file paths and permissions

### **Getting the Most from This Workflow:**
- **Compare file sizes**: See how read count affects species detection
- **Try different parameters**: Understand how thresholds affect results
- **Examine all outputs**: Don't just look at final species tables
- **Prepare for Custom CCI**: This foundation makes advanced workflows easier

**📖 For comprehensive troubleshooting and advanced features, see the [main README.md](../../README.md)**

**🚀 Ready to move on?** Once you've mastered this workflow, you're prepared for [Custom CCI workflow](../custom_cci_barcodes/README_custom_cci.md) and real research applications!