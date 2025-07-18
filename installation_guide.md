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
#If you have a Windows machine, go to cmd, type. Mac users, just go to terminal 
wsl -- install
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

#### 🐧 Linux (partitioned in Windows) Installation
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

## 🚀 Quick Setup

### For FHL Class (with USB drives):

**If you're in the FHL course with provided USB drives:**

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

# 6. Connect USB drive and setup pre-built databases
source scripts/setup_databases.sh

# 7. Verify installation works (5 minutes)
bash scripts/02_quick_look_clean.sh mock/ results/installation_test
```

**✅ This setup gets you working immediately with pre-built databases!**

### For Independent Users:

**If you're setting up on your own without pre-built databases:**

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

# 6. Build databases (this will take ~1.5 hours)
bash scripts/01_build_dbs_kraken_blastn.sh

# 7. Verify installation works (5-10 minutes)
bash scripts/02_quick_look_clean.sh mock/ results/installation_test
```

**✅ This setup builds everything from scratch for complete independence!**

**📖 For usage instructions:** See the main [README.md](README.md) file.

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
# Run the external tools installation script
bash scripts/install_external_tools.sh
```

**What this script installs:**

**✅ Automatic Installation (2 tools):**
- **amplicon_sorter** - Advanced consensus sequence calling for ONT amplicons
- **ONTbarcoder2.3** - GUI application for demultiplexing custom CCI barcodes

**📋 Manual Installation Required (1 tool):**
- **Dorado** - Oxford Nanopore SUP basecaller (requires manual download from GitHub)

**Expected output - you should see:**
```
🔧 Installing External Tools for DeCodeDNA...
📁 Creating tools directory at: ~/eDNA_workshop/tools/

📥 Installing amplicon_sorter...
✅ amplicon_sorter installed successfully

📥 Downloading ONTbarcoder2.3...
✅ ONTbarcoder2.3 downloaded successfully
   📱 Location: ~/eDNA_workshop/tools/ONTbarcoder2.3.app

📋 Manual Installation Required:
🔗 Please download Dorado from: https://github.com/nanoporetech/dorado/releases
📋 Choose the appropriate installer for your system:
   • macOS Apple Silicon: dorado-X.X.X-osx-arm64.zip
   • macOS Intel: dorado-X.X.X-osx-x64.zip
   • Linux x64: dorado-X.X.X-linux-x64.tar.gz
   • Linux ARM64: dorado-X.X.X-linux-arm64.tar.gz
   • Windows: dorado-X.X.X-win64.zip

💡 After downloading, extract to ~/eDNA_workshop/tools/ and follow GitHub instructions

🔍 Verifying installations...
✅ amplicon_sorter: Found
❌ dorado: Not found (manual installation required)

✅ External tools setup complete!
```

### Step 6: Database Setup (Choose Your Approach)

#### Option A: Use Pre-built Databases (Classroom/USB)
```bash
# For FHL class or if you have pre-built database USB drives
source scripts/setup_databases.sh

# This will auto-detect USB drives and configure database paths
```

#### Option B: Build Databases from Scratch
```bash
# Build all reference databases (takes ~1.5 hours)
echo "🗄️ Building reference databases..."
bash scripts/01_build_dbs_kraken_blastn.sh 2>&1 | tee database_build.log
```

---

## 🧪 Testing Your Installation

### Test 1: Verify Tools Work
```bash
# Make sure you're in the right environment
conda activate decode-dna

# Test that all core tools are accessible
echo "🔍 Testing core pipeline tools..."

# Make sure scripts are executable
chmod +x scripts/*.sh

# Setup databases (USB or local)
source scripts/setup_databases.sh

# Test basic pipeline functionality (should complete in 5-10 minutes)
echo "🧪 Running installation verification test..."
bash scripts/02_quick_look_clean.sh mock/ results/installation_test

# Check if basic output was created
if [[ -f "results/installation_test/mitofish/combined_clean_mitofish.krona.html" ]]; then
  echo "✅ Installation test successful!"
  echo "🌐 Test results created at: results/installation_test/"
else
  echo "❌ Installation test failed - check error messages above"
fi
```

### Test 2: Verify R Integration
```bash
# Test R packages work
echo "🧪 Testing R package integration..."
bash scripts/03_consensus_sort.sh results/installation_test results/test_consensus
bash scripts/04_denoise.sh results/test_consensus results/test_denoise

# Check R-based denoising worked
if [[ -f "results/test_denoise/mitofish/otu_table_mitofish_lulu_curated.csv" ]]; then
  echo "✅ R integration test successful!"
else
  echo "❌ R integration test failed - check R package installation"
fi
```

### Test 3: Full Pipeline Test
```bash
# Test complete pipeline including taxonomic assignment
echo "🔬 Testing full taxonomic assignment..."
bash scripts/05_taxonomic_assignment.sh results/test_denoise results/test_full

if [[ -f "results/test_full/03_final_taxonomy/Overall_Method_Comparison.csv" ]]; then
  echo "✅ Full pipeline test successful!"
  echo "🌐 Open Krona plots: results/test_full/04_krona_plots/*.html"
else
  echo "❌ Full pipeline test failed - check database setup"
fi
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

**Database setup fails**
```bash
# Check if USB drive is connected and mounted
ls /Volumes/

# Try manual database detection
source scripts/setup_databases.sh

# If no USB, build databases locally
bash scripts/01_build_dbs_kraken_blastn.sh
```

**R package installation fails**
```bash
# Install R packages manually
R
> install.packages("devtools")
> devtools::install_github("tobiasgf/lulu")
> quit()
```

**Krona taxonomy setup fails**
```bash
# Manual Krona setup
mkdir -p $CONDA_PREFIX/opt/krona/taxonomy
cd $CONDA_PREFIX/opt/krona/taxonomy
curl -O https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz
tar -xzf taxdump.tar.gz
echo "Manual Krona taxonomy setup complete"
```

**Scripts not executable**
```bash
# Make sure scripts can be run
chmod +x scripts/*.sh
ls -la scripts/
# Should show -rwxr-xr-x permissions
```

**Pipeline running slowly during testing**
```bash
# Speed up testing by using smaller datasets
export SUBSET_COUNT=500 THREADS=2
bash scripts/02_quick_look_clean.sh mock/ results/fast_test
```

---

## 🎓 For Instructors

### Pre-Class Setup
1. **Test complete installation** on instructor machine
2. **Build databases** ahead of time (1.5 hours): `bash scripts/01_build_dbs_kraken_blastn.sh`
3. **Prepare USB drives** with pre-built databases (copy databases folder to USB)
4. **Test USB detection** with `source scripts/setup_databases.sh`

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

# Connect USB drive and test
source scripts/setup_databases.sh
bash scripts/02_quick_look_clean.sh mock/ results/class_test
```

### Common Student Issues
- **Conda not installed**: Guide through miniconda installation
- **Permission errors**: `chmod +x scripts/*.sh`
- **Environment conflicts**: `conda deactivate` then `conda activate decode-dna`
- **Database not found**: Ensure USB drive is connected, try `source scripts/setup_databases.sh`
- **R package fails**: Run `bash scripts/install_R_dependencies.sh` again

---

## 📞 Support

### Getting Help
1. **Check this guide** for common installation solutions
2. **Verify environment**: `conda activate decode-dna && conda list`
3. **Test database detection**: `source scripts/setup_databases.sh`
4. **Contact instructors**: `ednacollab@uw.edu`

### Reporting Issues
When reporting installation problems, include:
- Operating system and version (`uname -a`)
- Conda version (`conda --version`)
- Database setup method used (USB vs local build)
- Error messages (full output)
- Steps that led to the error

---

**Installation complete! **

**📖 Next step:** See [README.md](README.md) for usage instructions and pipeline customization options.