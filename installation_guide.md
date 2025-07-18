# DeCodeDNA Installation & Setup Guide

**Complete setup instructions for FHL eDNA Class 2025**

This guide will take you from a fresh system to a fully functional eDNA analysis pipeline in about 30-45 minutes.

---

## 📋 Prerequisites

### System Requirements
- **Operating System**: macOS (Intel or Apple Silicon) or Linux
- **RAM**: 8GB minimum, 16GB+ recommended
- **Storage**: 10GB+ free space for databases and tools
- **Internet**: Stable connection for downloading databases (~2GB)

---

## 🐍 Step 0: Install Conda/Miniconda (If Not Already Installed)

**Most important step!** Conda manages all our software dependencies automatically.

### Check if Conda is Already Installed
```bash
# Test if conda is installed
conda --version

# If you see a version number, skip to "Quick Setup" below
# If you get "command not found", continue with installation
```

### Install Miniconda (Recommended)

1. **Go to the Miniconda download page**: https://www.anaconda.com/download/success
2. **Click on "Miniconda Installers"** 
3. **Select the installer suitable for your computer:**
   - **macOS Apple Silicon (M1/M2/M3)**: `Miniconda3-latest-MacOSX-arm64.sh`
   - **macOS Intel**: `Miniconda3-latest-MacOSX-x86_64.sh`
   - **Linux**: `Miniconda3-latest-Linux-x86_64.sh`
   - **Windows**: `Miniconda3-latest-Windows-x86_64.exe`

4. **Download and install:**

#### 🍎 macOS Installation
```bash
# Navigate to Downloads folder
cd ~/Downloads

# Run the installer (replace with your downloaded file name)
bash Miniconda3-latest-MacOSX-arm64.sh

# Follow the prompts:
# - Press ENTER to continue
# - Type "yes" to accept the license
# - Press ENTER to install in default location
# - Type "yes" to initialize conda
```

#### 🐧 Linux Installation
```bash
# Navigate to Downloads folder
cd ~/Downloads

# Run the installer
bash Miniconda3-latest-Linux-x86_64.sh

# Follow the prompts:
# - Press ENTER to continue
# - Type "yes" to accept the license
# - Press ENTER to install in default location
# - Type "yes" to initialize conda
```

### 🔄 Restart Your Terminal
**Important:** After installation, close and reopen your terminal window.

### ✅ Verify Installation
```bash
# Test conda installation
conda --version
# Should show: conda 23.x.x or similar

# Test that conda is working
conda info
# Should show conda environment information
```

### 🍎 macOS-Specific Fix (If Needed)
If you encounter this error when running `conda activate`:
```
ERROR: CONDA_BUILD_SYSROOT or SDKROOT has to be set for cross-compiling
```

Run these commands:
```bash
# Install Xcode command line tools
xcode-select --install

# Set SDK root
export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)

# Add to your shell profile to make permanent
echo 'export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)' >> ~/.zshrc
```

---

## 🚀 Quick Setup (Minimal)

**Now that conda is installed, set up the pipeline:**

```bash
# 1. Create workspace and clone repository
mkdir ~/eDNA_workshop && cd ~/eDNA_workshop
git clone https://github.com/piedna/DeCodeDNA.git && cd DeCodeDNA

# 2. Make scripts executable (important!)
chmod +x scripts/*.sh

# 3. Install environment (this will take 5-10 minutes)
conda env create -f environment.yml
conda activate decode-dna

# 4. Setup Krona taxonomy
bash scripts/install_krona_taxonomy.sh

# 5. Install R packages for denoising
bash scripts/install_R_dependencies.sh

# 6. Test with mock data (skip basecalling, start from step 2)
bash scripts/02_quick_look_clean.sh mock/ results/02_quicklook
```

**✅ This minimal setup lets you run steps 2-5 of the pipeline on example data!**

---

## 🎯 Pipeline Customization (No Script Editing Required!)

**The pipeline is fully customizable without editing any scripts.** Just set environment variables before running:

### Quick Setup for Different Data Types

```bash
# For 2000bp mitochondrial data:
export QUALITY_THRESHOLD=18 MIN_LENGTH=1500 MAX_LENGTH=3000 DATABASES="mitofish" THREADS=16

# For standard eDNA samples:
export QUALITY_THRESHOLD=15 MIN_LENGTH=150 MAX_LENGTH=350 DATABASES="12s coi mitofish" THREADS=8

# For fast teaching demos:
export DATABASES="mitofish" THREADS=4 SUBSET_COUNT=500
```

### All Available Options

| Parameter | What it does | Default | Example |
|-----------|--------------|---------|---------|
| `QUALITY_THRESHOLD` | Minimum quality score | 12 | 18 |
| `MIN_LENGTH` | Minimum sequence length | 100 | 1500 |
| `MAX_LENGTH` | Maximum sequence length | 500 | 3000 |
| `DATABASES` | Which databases to use | "12s coi mitofish" | "mitofish" |
| `THREADS` | CPU cores to use | 8 | 16 |
| `SUBSET_COUNT` | Max sequences for taxonomy | 2000 | 1000 |

### How to Use

```bash
# 1. Set your parameters once
export QUALITY_THRESHOLD=18 MIN_LENGTH=1500 MAX_LENGTH=3000 DATABASES="mitofish" THREADS=16

# 2. Check they're set
echo "Quality: $QUALITY_THRESHOLD, Length: $MIN_LENGTH-$MAX_LENGTH, DB: $DATABASES, Threads: $THREADS"

# 3. Run pipeline normally - no script editing needed!
bash scripts/02_quick_look_clean.sh mock/ results/02_quicklook
bash scripts/03_consensus_sort.sh results/02_quicklook results/03_consensus
bash scripts/04_denoise.sh results/03_consensus results/04_denoise
bash scripts/05_taxonomic_assignment.sh results/04_denoise results/05_taxonomy

# 4. Advanced: Enable amplicon_sorter local execution (may hang on local machines)
RUN_AMPLICON_SORTER=1 bash scripts/03_consensus_sort.sh results/02_quicklook results/03_consensus
```

**That's it!** The scripts automatically use your custom parameters.

---

## 🔧 Complete Setup (Full Pipeline)

**For instructors or students who want to run basecalling and work with real data:**

### Step 1: Project Structure
```bash
# Create organized workspace
mkdir ~/eDNA_workshop
cd ~/eDNA_workshop

# Clone main repository
git clone https://github.com/piedna/DeCodeDNA.git
cd DeCodeDNA

# Make all scripts executable (important step!)
chmod +x scripts/*.sh

# Activate your conda environment
conda activate decode-dna

# Your final structure will be:
# ~/eDNA_workshop/
# ├── DeCodeDNA/           # Main repository
# │   ├── scripts/         # Pipeline scripts 00-05 (now executable)
# │   ├── mock/           # Example data (see detailed breakdown below)
# │   └── environment.yml
# ├── databases/          # Reference databases (auto-created)
# ├── tools/              # External tools (manual install)
# └── results/            # Analysis outputs

# 📁 Understanding the Mock Data Directory
# 
# The mock/ folder contains a complete 12S fish community dataset:
#
# mock/
# ├── fast5/                          # Legacy FAST5 files (educational)
# │   ├── FAU66365_465db7b0_6c9b72bf_1.fast5
# │   ├── FAU66365_465db7b0_6c9b72bf_2.fast5
# │   └── FAU66365_465db7b0_6c9b72bf_3.fast5
# ├── pod5_barcode50/                 # Modern POD5 files (for basecalling demo)
# │   ├── FAX02223_pass_barcode50_*.pod5  # 5 files total
# ├── test_fhl_200k_1.fastq          # Sample replicate 1 (~200k reads)
# ├── test_fhl_200k_2.fastq          # Sample replicate 2  
# ├── test_fhl_200k_3.fastq          # Sample replicate 3
# └── mock_amplicon_sorter_clustered_consensus_*.fasta  # Pre-computed server results
#
# 🎓 File Format Explanation:
# • FAST5: Original Oxford Nanopore format (HDF5-based, slower)
# • POD5: Modern format (faster, default in current MinKNOW)
# • FASTQ: Basecalled sequences ready for analysis
# • Pre-computed consensus: High-quality results from server processing
#
# 💡 For classroom: Use mock/ files to focus on bioinformatics
#    rather than spending time on basecalling
#
# 🖥️ Pre-computed Amplicon_sorter Results:
# The mock_amplicon_sorter_clustered_consensus_*.fasta files contain
# high-quality consensus sequences generated on a high-performance server:
# 
# • Generated with: python3 amplicon_sorter.py -i classified.fasta -min 150 -max 350 
#   -ar -ra -maxr 119241 -ssg 95 -ss 97 -sc 98 -np 120
# • Server specs: 120 CPU cores, optimized for ONT amplicon processing
# • Purpose: Show what amplicon_sorter produces vs. local vsearch clustering
# • Usage: Script 03 automatically uses these for comparison with local results
#
# This demonstrates the difference between:
# - vsearch (fast, local, many clusters) 
# - amplicon_sorter (slow, thorough, fewer high-quality clusters)
```

### Step 2: Conda Environment (Already Done in Quick Setup)
```bash
# If you didn't do quick setup, create environment
conda env create -f environment.yml

# Activate environment (do this every time you start work)
conda activate decode-dna

# Verify installation
echo "Checking core tools..."
for tool in python kraken2 vsearch blastn seqkit; do
  if command -v $tool >/dev/null; then
    echo "✅ $tool: $(which $tool)"
  else
    echo "❌ $tool: not found"
  fi
done
```

### Step 3: Setup Krona Taxonomy
```bash
# Run the Krona taxonomy setup script
bash scripts/install_krona_taxonomy.sh
```

**What this script does:**
- Downloads NCBI taxonomy database (~50MB) for Krona visualizations
- Extracts taxonomy files (names.dmp, nodes.dmp, merged.dmp)
- Sets up Krona's taxonomy directory structure
- Handles the common `ktUpdateTaxonomy.sh` failures automatically

**Expected output - you should see:**
```
📊 Setting up Krona taxonomy...
✅ Method 1: Try automatic update first...
⚠️  Automatic update failed, using manual method...
📥 Method 2: Manual download and setup...
      • Downloading taxdump.tar.gz from NCBI...
      ✅ Download successful (50M)
      • Extracting taxonomy files...
      ✅ Extraction successful
✅ names.dmp: 50M
✅ nodes.dmp: 2.1M
✅ Krona taxonomy setup complete!
```

### Step 4: Install R Packages
```bash
# Run the R dependencies installation script
bash scripts/install_R_dependencies.sh
```

**What this script does:**
- Installs system dependencies (libgit2 on macOS)
- Installs essential R packages for the pipeline:
  - `lulu` - For denoising consensus sequences
  - `dplyr` - Data manipulation
  - `tidyr` - Data tidying
  - `readr` - Reading CSV files
  - `stringr` - String manipulation
- Tests each installation to ensure success

**Expected output - you should see:**
```
📦 Installing system dependencies...
✅ libgit2 already installed (or newly installed)
📦 Installing LULU R package...
✅ LULU installed successfully
✅ dplyr installed successfully
✅ tidyr installed successfully
✅ readr installed successfully
✅ stringr installed successfully
```

**If you see any ❌ errors:** The script will try alternative installation methods automatically.

### Step 5: External Tools
```bash
# Create tools directory
mkdir -p ../tools
cd ../tools

echo "Installing external tools..."

# A) Dorado (Oxford Nanopore basecaller) - Manual Download Required
echo "📥 Downloading Dorado..."
echo "🔗 Go to the Dorado GitHub page: https://github.com/nanoporetech/dorado"
echo "📋 Look for the latest release and download the appropriate installer for your system:"
echo "   • macOS Apple Silicon: dorado-X.X.X-osx-arm64.zip"
echo "   • macOS Intel: dorado-X.X.X-osx-x64.zip"  
echo "   • Linux x64: dorado-X.X.X-linux-x64.tar.gz"
echo "   • Linux ARM64: dorado-X.X.X-linux-arm64.tar.gz"
echo "   • Windows: dorado-X.X.X-win64.zip"
echo ""
echo "💡 After downloading, move the installer from ~/Downloads to ~/eDNA_workshop/tools/"
echo "   Then extract and install according to the GitHub instructions"
echo ""

# B) amplicon_sorter  
echo "📥 Installing amplicon_sorter..."
git clone https://github.com/avierstr/amplicon_sorter.git
cp amplicon_sorter/amplicon_sorter.py $CONDA_PREFIX/bin/amplicon_sorter
chmod +x $CONDA_PREFIX/bin/amplicon_sorter
echo "✅ amplicon_sorter installed"

# C) ONTbarcoder2.3 (GUI application)
echo "📥 Downloading ONTbarcoder2.3..."
curl -L -o ONTbarcoder2.3.zip "https://github.com/asrivathsan/ONTbarcoder/releases/download/2.3.0/ONTbarcoder2.3.0_OSX.zip"
unzip ONTbarcoder2.3.zip
echo "✅ ONTbarcoder2.3 downloaded - you can open the app from Finder"
echo "   📱 Location: $(pwd)/ONTbarcoder2.3.app"

# Return to main directory
cd ../DeCodeDNA

# Verify external tools
echo "🔍 Verifying external tool installation..."
for tool in amplicon_sorter; do
  if command -v $tool >/dev/null; then
    echo "✅ $tool: $(which $tool)"
  else
    echo "❌ $tool: not found"
  fi
done

echo "📋 Note: Dorado requires manual installation from GitHub"
```

### Step 6: Reference Databases
```bash
# Build all reference databases (takes ~1.5 hours)
echo "🗄️ Building reference databases..."
./scripts/01_build_dbs_kraken_blastn.sh 2>&1 | tee database_build.log
```

---

## 🧪 Testing Your Installation

### Test 1: Quick Pipeline Test
```bash
# Make sure you're in the right environment
conda activate decode-dna

# Quick test run (should complete in 5-10 minutes)
echo "🧪 Testing pipeline with mock data..."

# Make sure scripts are executable
chmod +x scripts/*.sh

# Run pipeline steps
bash scripts/02_quick_look_clean.sh mock/ results/test_02
bash scripts/03_consensus_sort.sh results/test_02 results/test_03
bash scripts/04_denoise.sh results/test_03 results/test_04

# Check results
if [[ -f "results/test_04/mitofish/otu_table_mitofish_lulu_curated.csv" ]]; then
  echo "✅ Pipeline test successful!"
else
  echo "❌ Pipeline test failed"
fi
```

### Test 2: Full Pipeline (if databases are built)
```bash
# Only run if databases exist
if [[ -d "../databases/blast_db" ]]; then
  echo "🔬 Testing full taxonomic assignment..."
  bash scripts/05_taxonomic_assignment.sh results/test_04 results/test_05
  
  if [[ -f "results/test_05/03_final_taxonomy/Overall_Method_Comparison.csv" ]]; then
    echo "✅ Full pipeline test successful!"
    echo "🌐 Open Krona plots: results/test_05/04_krona_plots/*.html"
  fi
else
  echo "⏩ Skipping taxonomic assignment test (databases not built yet)"
fi
```

---

## 📚 Basic Usage

### Complete Workflow
```bash
# Always start by activating environment
conda activate decode-dna

# Set your parameters (customize for your data)
export QUALITY_THRESHOLD=15 MIN_LENGTH=150 MAX_LENGTH=350 DATABASES="12s coi mitofish" THREADS=8

# For mock data (no basecalling needed):
bash scripts/02_quick_look_clean.sh mock/ results/02_quicklook
bash scripts/03_consensus_sort.sh results/02_quicklook results/03_consensus  
bash scripts/04_denoise.sh results/03_consensus results/04_denoise
bash scripts/05_taxonomic_assignment.sh results/04_denoise results/05_taxonomy

# For real POD5 data (includes basecalling):
bash scripts/00_basecall_and_demux.sh   # First time setup + basecalling
bash scripts/02_quick_look_clean.sh your_fastq_dir/ results/02_quicklook
# ... continue with steps 3-5
```

---

## 🔧 Troubleshooting

### Common Installation Issues

**"conda: command not found"**
```bash
# If you just installed conda, restart your terminal first
# Then try:
source ~/miniconda3/bin/activate
conda init
# Restart terminal again
```

**Environment creation fails**
```bash
# Update conda first
conda update conda

# Try with mamba (faster)
conda install mamba -c conda-forge
mamba env create -f environment.yml
```

**R package installation fails**
```bash
# Install R packages manually
R
> install.packages("devtools")
> devtools::install_github("tobiasgf/lulu")
> quit()
```

**Pipeline running slowly**
```bash
# Reduce dataset size
export SUBSET_COUNT=500

# Use fewer CPU threads  
export THREADS=2
```

---

## 🎓 For Instructors

### Pre-Class Setup
1. **Test complete installation** on instructor machine
2. **Build databases** ahead of time (1.5 hours)
3. **Prepare conda troubleshooting guide** for common student issues

### Class Day Shortcuts
```bash
# Quick student setup (assuming conda works):
mkdir ~/eDNA_workshop && cd ~/eDNA_workshop
git clone https://github.com/piedna/DeCodeDNA.git && cd DeCodeDNA
chmod +x scripts/*.sh
conda env create -f environment.yml
conda activate decode-dna
bash scripts/install_krona_taxonomy.sh
bash scripts/install_R_dependencies.sh

# Start with mock data analysis
bash scripts/02_quick_look_clean.sh mock/ results/02_quicklook
```

---

## 📞 Support

### Getting Help
1. **Check this guide** for common solutions
2. **Review script comments** for step-specific guidance
3. **Contact instructors**: `ednacollab@uw.edu`

### Reporting Issues
When reporting problems, include:
- Operating system and version
- Error messages (full output)
- Steps to reproduce the issue

---

**Installation complete! 🎉**

You're ready to analyze eDNA data with the DeCodeDNA pipeline.