# DeCodeDNA

**Oxford Nanopore eDNA Metabarcoding Pipeline for Friday Harbor Lab Class 2025**

A complete, educational bioinformatics pipeline for analyzing environmental DNA (eDNA) using Oxford Nanopore long-read sequencing technology. Designed for Friday Harbor Labs' (FHL) eDNA summer course by [The eDNA Collaborative](https://www.ednacollab.org)

---

## 🧬 What is DeCodeDNA?

DeCodeDNA transforms raw Oxford Nanopore sequencing data into species identification and abundance estimates. From raw POD5 basecalling through consensus calling, LULU‐denoising and taxonomic assignment, you get OTU tables and visual plot results with educational insights at every step.

**Key Features:**
- 🚀 **Two complete workflows** for ONT Native and Custom CCI barcoding
- 🔬 **Dual clustering approaches** (fast vsearch + thorough, ONT-suited amplicon_sorter)  
- 🧹 **LULU denoising** with co-occurrence filtering
- 📊 **Method comparisons** (BLAST vs Kraken2, multiple databases)
- 🎓 **Educational focus** with timing estimates and explanations
- 📱 **Interactive visualizations** via Krona plots

---

## 🔬 Pipeline Overview

```mermaid
flowchart TB
  %% Define styling for different stages
  classDef workflow fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000
  classDef prep fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000
  classDef analysis fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px,color:#000
  classDef results fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#000

  %% Data preparation
  subgraph prep ["🗄️ Setup (One-time)"]
    direction TB
    DB["01: Build Databases<br/>MIDORI + MitoFish<br/>(~1-2 hours)"]
  end

  %% Two workflow inputs
  subgraph workflows ["🔄 Choose Your Input Workflow"]
    direction LR
    A["🔹 ONT Native<br/>Standard barcoding<br/>Ready FASTQ files"]
    B["🔹 Custom CCI<br/>Custom primers<br/>Requires demultiplexing"]
  end

  %% Core analysis pipeline (shared)
  subgraph analysis ["🔬 Core Analysis Pipeline (Both Workflows)"]
    direction LR
    E["02: Quality Control<br/>& Classification<br/>(~3-5 min)"]
    F["03: Consensus<br/>Building<br/>(~5-8 min)"]
    G["04: LULU<br/>Denoising<br/>(~3-7 min)"]
    H["05: Taxonomic<br/>Assignment<br/>(~5-10 min)"]
    E --> F --> G --> H
  end

  %% Results
  subgraph results ["📊 Results & Visualization"]
    direction TB
    I["Species Lists<br/>& Abundance Tables"]
    J["Interactive Krona Plots<br/>& Method Comparisons"]
  end

  %% Connect workflows
  DB -.-> analysis
  A --> analysis
  B --> analysis
  analysis --> results

  %% Apply styling
  class A,B workflow
  class DB prep
  class E,F,G,H analysis
  class I,J results
```

**Pipeline Scripts:**
- **Script 00:** Basecalling demo (optional)
- **Script 01:** Database building (one-time setup)
- **Scripts 02-05:** Core analysis pipeline (both workflows)

---

## 🔄 Choose Your Workflow

DeCodeDNA supports **two distinct barcoding approaches**. Choose the one that matches your PCR and barcoding setup:

### 🔹 Workflow A: ONT Native Barcoding
**For samples using Oxford Nanopore's official barcoding kits**
- Uses ONT Native Barcoding Kits (NBD114.96, PBC096, etc.)
- Samples are already demultiplexed during basecalling
- **Best for**: Two-step PCR workflows, users who don't design their own barcodes

```bash
# Quick start - ONT Native Workflow
cd workflows/ont_native_barcodes/
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_results/02_quicklook
# Continue with scripts 03, 04, 05...
```

### 🔹 Workflow B: Custom CCI Barcoding  
**For samples using custom primer-barcode combinations**
- Requires manual demultiplexing with ONTbarcoder2.3 GUI
- Includes quality filtering and EFPQ base conversion
- **Best for**: One-step PCR workflows, custom primer designs, research applications

```bash
# Complete custom CCI workflow
cd workflows/custom_cci_barcodes/
# Step 1: Quality filter raw data
bash ../../scripts/00_quality_filter_predemux.sh 00_raw_data/test_fhl_customcci.fastq 01_filtered/quality_filtered.fastq

# Step 2: Manual demultiplexing (GUI)
# Use ONTbarcoder2.3 with 01_filtered/quality_filtered.fastq
# Output to: 02_demultiplexed/

# Step 3: Continue with core pipeline
bash ../../scripts/02_quick_look_clean.sh 02_demultiplexed/ ../../results/custom_cci_results/02_quicklook
# Continue with scripts 03, 04, 05...
```

**📖 Detailed workflow instructions:** [ONT Native README](workflows/ont_native_barcodes/README_ont_native.md) | [Custom CCI README](workflows/custom_cci_barcodes/README_custom_cci.md)

---

## 🛠️ Installation

### Quick Setup (5-10 minutes)
```bash
# 1. Clone repository
git clone https://github.com/piedna/DeCodeDNA.git
cd DeCodeDNA

# 2. Create conda environment
conda env create -f environment.yml
conda activate decode-dna

# 3. Setup tools and databases
bash scripts/install_krona_taxonomy.sh
bash scripts/install_R_dependencies.sh
bash scripts/install_external_tools.sh

# 4. Setup databases (choose one)
# Option A: Use pre-built databases (classroom)
source scripts/setup_databases.sh

# Option B: Build databases from scratch (1-2 hours)
bash scripts/01_build_dbs_kraken_blastn.sh
```

**💡 Detailed installation guide:** [`installation_guide.md`](installation_guide.md)

---

## 🎓 For Students: Course Progression

### Learning Path for FHL Course

**📋 Course Workflow Strategy:**
1. **Start with Workflow A (ONT Native)** → Learn pipeline basics with mock data
2. **Practice with Workflow B mock data** → Understand custom CCI processing  
3. **Apply Workflow B to real samples** → Analyze your actual field collections

### Which Mock Data to Use?

**Workflow A Mocks** (Learning the pipeline):
- Uses pre-demultiplexed data (easier to start)
- Focus on understanding analysis steps
- Perfect for first-time users

**Workflow B Mocks** (Practice custom workflow):
- Includes demultiplexing step
- Learn ONTbarcoder2.3 GUI
- Prepare for real sample analysis

**Real Samples** (Final analysis):
- Use Workflow B for your field collections
- Apply everything you've learned
- Generate results for your research

### Common Commands

**ONT Native Workflow (Learning):**
```bash
cd workflows/ont_native_barcodes/
bash ../../scripts/02_quick_look_clean.sh . ../../results/ont_native_results/02_quicklook
bash ../../scripts/03_consensus_sort.sh ../../results/ont_native_results/02_quicklook ../../results/ont_native_results/03_consensus
bash ../../scripts/04_denoise.sh ../../results/ont_native_results/03_consensus ../../results/ont_native_results/04_denoise
bash ../../scripts/05_taxonomic_assignment.sh ../../results/ont_native_results/04_denoise ../../results/ont_native_results/05_taxonomy
```

**Custom CCI Workflow (Real samples):**
```bash
cd workflows/custom_cci_barcodes/
bash ../../scripts/02_quick_look_clean.sh 02_demultiplexed/ ../../results/custom_cci_results/02_quicklook
bash ../../scripts/03_consensus_sort.sh ../../results/custom_cci_results/02_quicklook ../../results/custom_cci_results/03_consensus
bash ../../scripts/04_denoise.sh ../../results/custom_cci_results/03_consensus ../../results/custom_cci_results/04_denoise
bash ../../scripts/05_taxonomic_assignment.sh ../../results/custom_cci_results/04_denoise ../../results/custom_cci_results/05_taxonomy
```

```mermaid
flowchart TB
  %% Define styling for different stages
  classDef workflow fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000
  classDef prep fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000
  classDef analysis fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px,color:#000
  classDef results fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#000

  %% Data preparation
  subgraph prep ["🗄️ Setup (One-time)"]
    direction TB
    DB["01: Build Databases<br/>MIDORI + MitoFish<br/>(~1-2 hours)"]
  end

  %% Two workflow inputs
  subgraph workflows ["🔄 Choose Your Input Workflow"]
    direction LR
    A["🔹 ONT Native<br/>Standard barcoding<br/>Ready FASTQ files"]
    B["🔹 Custom CCI<br/>Custom primers<br/>Requires demultiplexing"]
  end

  %% Core analysis pipeline (shared)
  subgraph analysis ["🔬 Core Analysis Pipeline (Both Workflows)"]
    direction LR
    E["02: Quality Control<br/>& Classification<br/>(~3-5 min)"]
    F["03: Consensus<br/>Building<br/>(~5-8 min)"]
    G["04: LULU<br/>Denoising<br/>(~3-7 min)"]
    H["05: Taxonomic<br/>Assignment<br/>(~5-10 min)"]
    E --> F --> G --> H
  end

  %% Results
  subgraph results ["📊 Results & Visualization"]
    direction TB
    I["Species Lists<br/>& Abundance Tables"]
    J["Interactive Krona Plots<br/>& Method Comparisons"]
  end

  %% Connect workflows
  DB -.-> analysis
  A --> analysis
  B --> analysis
  analysis --> results

  %% Apply styling
  class A,B workflow
  class DB prep
  class E,F,G,H analysis
  class I,J results
```

**Pipeline Scripts:**
- **Script 00:** Basecalling demo (optional)
- **Script 01:** Database building (one-time setup)
- **Scripts 02-05:** Core analysis pipeline (both workflows)

---

## 📊 Expected Results

### File Outputs
```
results/
├── [workflow]_results/
│   ├── 02_quicklook/               # Quality control & initial classification
│   ├── 03_consensus/               # Sequence clustering results
│   ├── 04_denoise/                 # Error-corrected sequences
│   │   └── [database]/             # Database-specific results
│   │       └── otu_representatives_[database]_vsearch.fasta  # ⭐ Filtered consensus sequences
│   └── 05_taxonomy/                # Final species identification
│       ├── 03_final_taxonomy/      # Species abundance tables ⭐
│       └── 04_krona_plots/         # Interactive visualizations ⭐
```

### Key Result Files
- **Consensus sequences**: `04_denoise/*/otu_representatives_*_vsearch.fasta` - Filtered sequences ready for custom analysis (haplotyping, phylogenetics)
- **Species tables**: `*_classified_species.csv` - Final abundance matrices
- **Interactive plots**: `*_krona_plot.html` - Open in browser for exploration
- **Method comparison**: `Overall_Method_Comparison.csv` - BLAST vs Kraken2 performance

---

## ⚙️ Customization

**Environment Variables (set before running):**
```bash
# Quality & length filtering
export QUALITY_THRESHOLD=15        # Default: 12
export MIN_LENGTH=150              # Default: 100  
export MAX_LENGTH=350              # Default: 500

# Database selection  
export DATABASES="12s coi mitofish" # Default: all three

# Performance tuning
export THREADS=16                  # Default: 8
export SUBSET_COUNT=1000           # Default: 2000
```

**Example custom run:**
```bash
export QUALITY_THRESHOLD=18 MIN_LENGTH=200 MAX_LENGTH=300 DATABASES="mitofish"
bash scripts/02_quick_look_clean.sh workflows/ont_native_barcodes/ results/custom_analysis/02_quicklook
```

---

## 🎯 For Instructors: Course Design

### Class Session Structure

**Session Planning (Total: ~3-4 hours across multiple phases):**

| Phase | Activity | Duration | Focus |
|-------|----------|----------|-------|
| **Phase 1** | Setup + Workflow A | 2 hours | Pipeline basics, mock data |
| **Phase 2** | Workflow B practice | 1.5 hours | Custom CCI, ONTbarcoder |
| **Phase 3** | Real sample analysis | Variable | Student research data |

### Pre-Class Preparation

**Essential Setup (Do 1-2 days before):**
1. **Test complete installation** on instructor machine
2. **Build or copy databases** (1-2 hours): `bash scripts/01_build_dbs_kraken_blastn.sh`
3. **Prepare USB drives** with databases for offline use
4. **Test both workflows** with provided mock data

**Student Machine Setup (Phase 1):**
```bash
# Quick classroom setup
conda env create -f environment.yml
conda activate decode-dna
bash scripts/install_krona_taxonomy.sh
source scripts/setup_databases.sh

# Verify installation
cd workflows/ont_native_barcodes/
bash ../../scripts/02_quick_look_clean.sh . ../../results/class_test/02_quicklook
```

### Teaching Strategy

**Progressive Learning Path:**
- **Phase 1**: Start with Workflow A (simpler, builds confidence)
- **Phase 2**: Introduce Workflow B (real-world skills)  
- **Phase 3**: Apply to student research data (practical application)

**Key Teaching Moments:**
- **Method comparison**: Show why multiple approaches matter
- **Quality control**: Emphasize importance of filtering steps
- **Result interpretation**: Guide students through Krona plots
- **Troubleshooting**: Use common errors as learning opportunities

---

## 🔧 Troubleshooting

### Common Issues

**"No demultiplexed files found"**
- Check workflow directory structure
- Ensure you're in the correct workflow folder
- Verify ONTbarcoder output is in `02_demultiplexed/`

**"Database not found"**
- Run: `source scripts/setup_databases.sh`
- Check USB drive connection
- Build local databases: `bash scripts/01_build_dbs_kraken_blastn.sh`

**"conda: command not found"**
- Install miniconda first
- Restart terminal after installation
- See [`installation_guide.md`](installation_guide.md) for details

### Workflow-Specific Help
- **ONT Native issues**: See `workflows/ont_native_barcodes/README_ont_native.md`
- **Custom CCI issues**: See `workflows/custom_cci_barcodes/README_custom_cci.md`

---

## 📞 Support & Citation

### Getting Help
- **Installation issues**: [`installation_guide.md`](installation_guide.md)
- **Workflow questions**: Check workflow-specific READMEs
- **Course support**: `ednacollab@uw.edu`
- **Bug reports**: [GitHub Issues](https://github.com/piedna/DeCodeDNA/issues)

### Citation
```bibtex
@software{decodedna2025,
  title={DeCodeDNA: Oxford Nanopore eDNA Metabarcoding Pipeline},
  author={Ip, Y.C.A. and The eDNA Collaborative},
  year={2025},
  url={https://github.com/piedna/DeCodeDNA}
}
```

---

# 📋 Technical Reference

*Detailed technical information for advanced users and instructors*

## 💻 System Requirements

- **OS:** macOS or Linux (Windows via WSL2)
- **RAM:** 8GB minimum, 16GB+ recommended
- **Storage:** 10GB+ free space for results, 200GB for local databases
- **Dependencies:** Managed via conda (see `environment.yml`)

## 🛠️ Core Dependencies

| Tool | Purpose | Educational Value |
|------|---------|-------------------|
| **Dorado** | Fast, HAC, SUP basecalling for Oxford Nanopore data | Learn basecalling trade-offs |
| **SeqKit** | FASTA/Q utilities, statistics, quality filtering | Sequence manipulation basics |
| **Kraken2** | Rapid k-mer-based taxonomic classification | Fast classification methods |
| **VSEARCH** | Fast clustering & sequence comparison | Clustering algorithms |
| **BLAST** | Sequence alignment & taxonomic assignment | Similarity-based classification |
| **LULU (R)** | Post-clustering error correction | Bioinformatics error correction |
| **Krona** | Interactive HTML taxonomic visualizations | Data visualization principles |
| **amplicon_sorter** | Advanced consensus calling for ONT data | ONT-specific processing |
| **ONTbarcoder** | Demultiplex custom CCI barcodes | Custom barcode handling |

## 📊 Detailed Output Structure

```
results/
├── [workflow]_results/
│   ├── 02_quicklook/                    # Quality control & initial classification
│   │   ├── filtered/                    # Quality-filtered sequences
│   │   │   ├── *_filtered.fastq        # Sequences passing Q≥12, length filters
│   │   │   └── *_length_dist/           # Length distribution plots (PDF)
│   │   └── mitofish/                    # Fish-classified sequences + reports
│   │       ├── *_mitofish.report.txt    # Kraken2 classification report
│   │       ├── *_classified.fasta       # Fish-identified sequences
│   │       ├── *_unclassified.fasta     # Non-fish sequences
│   │       └── *.krona.html             # Interactive taxonomic plots
│   ├── 03_consensus/                    # Sequence clustering results  
│   │   ├── vsearch_clustering/          # Fast local clustering
│   │   │   └── mitofish/               # Database-specific results
│   │   │       ├── *_dereplicated.fasta # Dereplicated sequences
│   │   │       ├── *_vsearch_consensus.fasta # Representative sequences
│   │   │       └── *_clusters/          # Individual cluster files
│   │   └── amplicon_sorter_consensus.fasta # High-quality consensus (pre-computed)
│   ├── 04_denoise/                     # Error-corrected sequences
│   │   └── mitofish/                   # Database-specific denoised results
│   │       ├── otu_table_*_lulu_curated.csv       # Final OTU abundance tables
│   │       ├── otu_table_*_lulu_discarded.csv     # Removed sequences
│   │       ├── otu_representatives_*.fasta        # Representative sequences
│   │       └── otu_self_blast_*.out              # Self-alignment results
│   └── 05_taxonomy/                    # Final species identification
│       ├── 01_blast_results/            # BLAST taxonomic assignments
│       │   └── *_blast_hits.tsv         # Best BLAST matches per method
│       ├── 02_kraken2_results/          # Kraken2 classifications  
│       │   ├── *_kraken2_output.txt     # Classification details
│       │   └── *_kraken2_report.txt     # Summary reports
│       ├── 03_final_taxonomy/           # Species abundance matrices
│       │   ├── BLAST_vsearch_*_classified_species.csv   # Final OTU tables ⭐
│       │   ├── Kraken2_vsearch_*_classified_species.csv # Alternative classifications
│       │   └── Overall_Method_Comparison.csv  # Performance summary
│       └── 04_krona_plots/              # Interactive HTML visualizations ⭐
│           └── *_krona_plot.html        # Method-specific taxonomic plots
```

## ⚙️ Advanced Customization

### All Available Parameters

| Parameter | Description | Default | Example Custom |
|-----------|-------------|---------|----------------|
| `QUALITY_THRESHOLD` | Minimum Phred quality score | 12 | 18 (stricter) |
| `MIN_LENGTH` | Minimum sequence length (bp) | 100 | 150 (eDNA standard) |
| `MAX_LENGTH` | Maximum sequence length (bp) | 500 | 350 (12S specific) |
| `DATABASES` | Which reference databases to use | "12s coi mitofish" | "mitofish" (fish only) |
| `THREADS` | CPU cores for parallel processing | 8 | 16 (high-end machine) |
| `SUBSET_COUNT` | Max sequences for taxonomy (speed) | 2000 | 1000 (demo mode) |
| `CONFIDENCE` | Kraken2 confidence threshold | 0.05 | 0.1 (conservative) |
| `VSEARCH_SIMILARITY` | Clustering similarity threshold | 0.97 | 0.95 (looser clustering) |

### Example Configurations

**🚀 Fast Demo Mode (Classroom):**
```bash
export DATABASES="mitofish" THREADS=4 SUBSET_COUNT=500
# Fastest analysis for demonstrations
```

**🐟 Standard eDNA Analysis:**
```bash
export QUALITY_THRESHOLD=15 MIN_LENGTH=150 MAX_LENGTH=350 DATABASES="12s coi mitofish"
# Typical environmental DNA settings
```

**🧬 Complete Mitochondrial Genomes:**
```bash
export QUALITY_THRESHOLD=18 MIN_LENGTH=15000 MAX_LENGTH=18000 DATABASES="mitofish"
# For complete mitochondrial genome analysis
```

**⚙️ High-Performance Server:**
```bash
export THREADS=32 SUBSET_COUNT=10000 CONFIDENCE=0.1
# Maximum performance with conservative classification
```

## 🗄️ Database Information

### Database Specifications
- **MIDORI 12S**: GenBank release 265 (2025-03-08), ~2.3M sequences
- **MIDORI COI**: GenBank release 265 (2025-03-08), ~8.1M sequences  
- **MitoFish**: Complete & partial mitogenomes (July 2025), ~85K sequences
- **Total size**: ~158GB (Kraken2: 120GB, BLAST: 38GB)

### Setup Options for Classrooms

**Option A: Auto-Detection (Recommended)**
```bash
source scripts/setup_databases.sh
# Automatically finds USB or local databases
```

**Option B: USB Drive Setup**
```bash
export DB_ROOT="/Volumes/DeCodeDNA_DB/databases/kraken2_db"
export BLAST_DB_ROOT="/Volumes/DeCodeDNA_DB/databases/blast_db"
```

**Option C: Local Copy (Fast Analysis)**
```bash
cp -r /Volumes/DeCodeDNA_DB/databases ../
# No exports needed - faster analysis
```

## 🔬 Scientific Background

### Key Publications

- **Wood & Langmead (2019)** - *Genome Biology* - Kraken2: Improved metagenomic analysis
- **Frøslev et al. (2017)** - *Nature Methods* - LULU: Post-clustering curation algorithm  
- **Altschul et al. (1990)** - *Journal of Molecular Biology* - Basic Local Alignment Search Tool
- **Vierstraete et al. (2021)** - *Bioinformatics* - amplicon_sorter for ONT data
- **Rognes et al. (2016)** - *PeerJ* - VSEARCH: Versatile sequence clustering

### Pipeline Philosophy

- **Educational Transparency**: All parameters documented and adjustable
- **Method Comparison**: Multiple approaches provide validation and insights
- **Quality Focus**: Rigorous filtering and error correction throughout
- **Reproducibility**: Version-controlled environments and standardized workflows
- **Accessibility**: Designed for both beginners and advanced users

---

**Developed for Friday Harbor Labs eDNA Course 2025**  
*Making eDNA analysis accessible through dual workflow design*