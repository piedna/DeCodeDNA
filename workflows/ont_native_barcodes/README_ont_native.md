# ONT Native Barcode Tags Workflow

**Quick start for ONT Native Barcode Tags (standard workflow)**

✅ **Perfect for**: Two-step PCR workflows, non-custom primer tag design needed  
🎯 **Goal**: Focus on bioinformatics analysis with ready-to-go data  
📊 **Dataset**: 12S fish community mock data (~200-300bp amplicons)

---

## 🧬 What is ONT Native Barcode Tags?

**ONT Native Barcode Tags** use Oxford Nanopore's official barcoding system (they call it "Native" because it's built into their platform):
- **eDNA workflow-compatible kits**: NBD114.24, NBD114.96, EXP-PBC096 
- **Two-step PCR**: Amplify target → Add ONT barcode tags → Sequence
- **Integrated demultiplexing**: Built into MinKNOW GUI or Dorado command line
- **Ready-to-analyze**: Demultiplexing happens during basecalling, no manual steps

**vs Custom CCI**: Custom primer-barcode combinations require manual demultiplexing with ONTbarcoder2.3

---

## 📁 Files in this directory:

```
workflows/ont_native_barcodes/
├── test_fhl_100k_3.fastq       # 100K read subset - fast demo/testing
├── test_fhl_150k_2.fastq       # 150K read subset - medium analysis  
├── test_fhl_200k_1.fastq       # 200K read subset - full analysis
├── fast5/                      # Legacy FAST5 files (educational)
├── pod5_barcode50/             # Modern POD5 files (basecalling demo)
└── precomputed/                # Server pre-clustered results (time-saving mock analyses)
    └── mock_amplicon_sorter_clustered_consensus_*.fasta
```

### **File Purposes:**
- **Mock community data**: Fish community samples for educational purposes
- **Different read subsets**: Various sizes from the same dataset for different exercises
- **FAST5/POD5**: Educational files for understanding ONT data formats (optional Script 00)
- **Server pre-clustered**: Time-saving pre-processed results for comparison

---

## 🚀 Run the complete pipeline (15-20 minutes):

```bash
# Navigate to this directory first
cd workflows/ont_native_barcodes/

# Step 1: Quality control & taxonomic classification (3-5 min)
# • Filters sequences by quality/length, classifies against fish databases
# • Input: Raw FASTQ | Output: Filtered sequences + classification reports
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_results/02_quicklook

# Step 2: Consensus building (5-8 min)  
# • vsearch: Fast clustering | amplicon_sorter: Advanced clustering (demo commands)
# • Input: Classified sequences | Output: Consensus sequences for analysis
bash ../../scripts/03_consensus_sort.sh ../../results/ont_native_results/02_quicklook ../../results/ont_native_results/03_consensus

# Step 3: LULU denoising (3-7 min)
# • Removes sequencing errors using co-occurrence patterns
# • Input: Consensus sequences | Output: Curated OTU tables
bash ../../scripts/04_denoise.sh ../../results/ont_native_results/03_consensus ../../results/ont_native_results/04_denoise

# Step 4: Final taxonomic assignment (5-10 min)
# • BLAST + Kraken2 classification with interactive visualizations  
# • Input: Denoised sequences | Output: Species tables + Krona plots
bash ../../scripts/05_taxonomic_assignment.sh ../../results/ont_native_results/04_denoise ../../results/ont_native_results/05_taxonomy

# Step 5: View results
open ../../results/ont_native_results/05_taxonomy/04_krona_plots/*.html
```

---

## 🎓 What you'll learn:

### **Core Bioinformatics Skills:**
- **Quality assessment**: Understanding ONT data characteristics
- **Taxonomic classification**: Multiple database approaches (12S, COI, MitoFish)
- **Sequence clustering**: vsearch vs amplicon_sorter comparison
- **Error correction**: LULU algorithm for removing artifacts
- **Data visualization**: Interactive Krona plots for exploring results

### **ONT-Specific Knowledge:**
- **File formats**: FAST5 (legacy) vs POD5 (modern)
- **Barcode tag workflows**: How native barcoding simplifies analysis
- **Performance trade-offs**: Local vs server-optimized processing

---

## 📊 Expected results:

- **Species identified**: 10-30 fish species from mock community
- **Processing time**: 15-20 minutes total (excluding optional basecalling demo)
- **Output files**: 
  - Species abundance tables (`*_classified_species.csv`)
  - Interactive taxonomic plots (`*.krona.html`)
  - Consensus sequences for further analysis (`otu_representatives_*.fasta`)

---

## 🔧 Demultiplexing Context

**Why these files are "ready-to-go":**

ONT Native workflows include **integrated demultiplexing** that happens during basecalling:

### **Option 1: MinKNOW GUI (Real-time)**
- Toggle demultiplexing **during sequencing with live basecalling** in MinKNOW interface
- Select your barcode kit → automatic sample separation
- Get individual sample files directly from sequencer

### **Option 2: Dorado Command Line (Post-sequencing)**
```bash
# During basecalling (recommended)
dorado basecaller [model] [pod5_dir] --kit-name SQK-NBD114-24 --emit-fastq

# Or post-basecalling demultiplexing  
dorado demux --output-dir demux_output --kit-name EXP-PBC096 --emit-fastq basecalled.fastq
```

**Supported kits:** NBD114.24, NBD114.96, EXP-PBC096

**Result:** Individual sample files (like our `test_fhl_*` files) ready for analysis - no manual demultiplexing needed!

---

## 💡 Next steps:

1. **Master this workflow** with the 12S mock data
2. **Try different file sizes** (100K vs 200K reads) to see performance differences  
3. **Move to Custom CCI workflow** for practice with manual demultiplexing
4. **Apply to your real samples** using the Custom CCI approach

**📖 See [main README.md](../../README.md) for advanced customization and troubleshooting options.**