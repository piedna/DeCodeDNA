# DeCodeDNA Installation & Setup Guide

**Detailed setup assistance for the DeCodeDNA eDNA pipeline**

🏠 **[← Return to Main README](README.md)** | 📖 **For workflow instructions and usage, see [README.md](README.md)**

This guide provides **detailed installation assistance** and **troubleshooting support** for setting up DeCodeDNA. For basic workflow instructions and course information, refer to the [main README.md](README.md).

---

## 📖 Quick Navigation

- **🚀 [Basic Setup](#-basic-setup)** - Essential installation steps
- **🔧 [Detailed Installation](#-detailed-installation)** - Platform-specific instructions  
- **🗄️ [Database Options](#️-database-setup-options)** - Choose your approach
- **🔧 [Troubleshooting](#-troubleshooting)** - Common issues and solutions
- **🎓 [For Instructors](#-for-instructors)** - Classroom management tips

**📌 New to DeCodeDNA?** Start with the [main README.md](README.md) for course overview and workflow selection.

---

## 🚀 Basic Setup

**If you just want to get started quickly, see the [installation section in README.md](README.md#️-installation).** This guide provides detailed assistance when you encounter issues.

### Prerequisites Check
```bash
# Check if you have the basics
conda --version      # If this fails, see detailed conda installation below
git --version        # Should be installed on most systems
```

**✅ If conda works:** Continue with [main README installation](README.md#️-installation)  
**❌ If conda fails:** Follow [detailed conda installation](#-step-0-install-condaminiconda-if-not-already-installed) below

---

## 🔧 Detailed Installation

### 📋 System Requirements

| Component | Requirement | Recommended | Notes |
|-----------|-------------|-------------|-------|
| **OS** | macOS, Linux, Windows WSL2 | macOS/Linux native | Windows requires WSL2 setup |
| **RAM** | 8GB minimum | 16GB+ | More RAM = faster processing |
| **Storage** | 10GB free minimum | 200GB+ | 200GB needed for local databases |
| **Internet** | Stable connection | High-speed | ~2GB database downloads |
| **CPU** | 4+ cores | 8+ cores | More cores = faster analysis |

---

## 🐍 Step 0: Install Conda/Miniconda (If Not Already Installed)

**Most important step!** Conda manages all our software dependencies automatically.

### Check if Conda is Already Installed
```bash
# For Windows users without WSL
wsl --install
# Then restart and continue in WSL terminal

# For Mac/Linux users
conda --version

# If you see a version number, skip to "Basic Setup" in main README
# If you get "command not found", continue with installation below
```

### Install Miniconda (Recommended)

1. **Go to the Miniconda download page**: https://www.anaconda.com/download/success
2. **Click on "Miniconda Installers"** 
3. **Select the installer suitable for your computer:**
   - **macOS Apple Silicon (M1/M2/M3/M4)**: `Miniconda3-latest-MacOSX-arm64.sh`
   - **macOS Intel**: `Miniconda3-latest-MacOSX-x86_64.sh`
   - **Linux**: `Miniconda3-latest-Linux-x86_64.sh`

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

# For Ubuntu/Debian - install unzip if needed
sudo apt update && sudo apt install zip unzip

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

## 🗄️ Database Setup Options

**For workflow instructions after setup, see [README.md](README.md#-pipeline-overview)**

### For FHL Students: Two Approaches

**🎓 Recommended Learning Path:**
1. **Try Option B first** (build databases yourself - excellent learning experience)
2. **Fallback to Option A** if disk space is limited (~200GB required)
3. **USB drives available** as backup option during class

### Option A: Use Pre-built Databases (Classroom/USB)
**Perfect when:** Limited disk space, shared classroom resources, quick setup needed

```bash
# Auto-detect and setup databases from USB drives
source scripts/setup_databases.sh

# This script will:
# - Detect connected USB drives with databases
# - Set up environment variables automatically
# - Verify database accessibility
# - No local storage required
```

**Expected output:**
```
🔍 Scanning for database drives...
✅ Found database drive at: /Volumes/DeCodeDNA_DB/
🗄️ Setting up Kraken2 databases...
🧬 Setting up BLAST databases...
✅ Database setup complete!
```

### Option B: Build Databases from Scratch
**Perfect when:** Learning database structure, sufficient disk space, research independence

```bash
# Build all reference databases (takes ~1.5 hours, requires ~200GB space)
bash scripts/01_build_dbs_kraken_blastn.sh 2>&1 | tee database_build.log

# This will download and build:
# - MIDORI 12S database (~40GB)
# - MIDORI COI database (~80GB) 
# - MitoFish database (~80GB)
# - Both Kraken2 and BLAST formats
```

**What you'll learn:**
- How reference databases are structured
- FASTA sequence processing and indexing
- Database size and performance trade-offs
- Independence from pre-built resources

### Option C: Hybrid Approach
**Perfect when:** Learning priorities with practical constraints

```bash
# Build one database locally (learning experience)
export DATABASES="mitofish"
bash scripts/01_build_dbs_kraken_blastn.sh

# Use USB for others (save time/space)
source scripts/setup_databases.sh
```

---

## 🔧 Detailed Tool Installation

### External Tools Setup
```bash
# Install additional tools required for complete pipeline
bash scripts/install_external_tools.sh
```

**What this installs:**

### ✅ Automatic Installation
- **amplicon_sorter**: Advanced consensus sequence calling optimized for ONT amplicons
- **ONTbarcoder2.3**: GUI application for demultiplexing custom CCI barcodes

### 📋 Manual Installation Required
- **Dorado**: Oxford Nanopore SUP basecaller (requires manual download)

**For Dorado manual installation:**
1. Visit: https://github.com/nanoporetech/dorado/releases
2. Download appropriate version:
   - **macOS Apple Silicon**: `dorado-X.X.X-osx-arm64.zip`
   - **macOS Intel**: `dorado-X.X.X-osx-x64.zip`
   - **Linux x64**: `dorado-X.X.X-linux-x64.tar.gz`
3. Extract to `~/eDNA_workshop/tools/`
4. Follow GitHub installation instructions

### R Dependencies Setup
```bash
# Install R packages for denoising
bash scripts/install_R_dependencies.sh
```

**What this installs:**
- `lulu` - Post-clustering error correction
- `dplyr`, `tidyr`, `readr`, `stringr` - Data manipulation
- System dependencies (libgit2 on macOS)

### Krona Taxonomy Setup
```bash
# Setup Krona taxonomy for visualizations
bash scripts/install_krona_taxonomy.sh
```

**What this does:**
- Downloads NCBI taxonomy database (~50MB)
- Sets up Krona directory structure
- Handles common installation failures automatically

---

## 🔧 Troubleshooting

### Common Installation Issues

#### "conda: command not found"
```bash
# If you just installed conda, restart terminal first, then:
source ~/miniconda3/bin/activate
conda init
# Restart terminal again
```

#### Environment Creation Fails
```bash
# Update conda first
conda update conda

# Try with mamba (faster package manager)
conda install mamba -c conda-forge
mamba env create -f environment.yml

# If still fails, create minimal environment
conda create -n decode-dna python=3.9
conda activate decode-dna
conda install -c conda-forge -c bioconda kraken2 vsearch blast seqkit
```

#### Database Setup Issues

**USB drive not detected:**
```bash
# Check mounted drives
ls /Volumes/          # macOS
ls /media/            # Linux

# Manual USB setup if auto-detection fails
export DB_ROOT="/path/to/your/usb/databases/kraken2_db"
export BLAST_DB_ROOT="/path/to/your/usb/databases/blast_db"
```

**Local database build fails:**
```bash
# Check disk space first
df -h

# Common fixes:
# 1. Ensure sufficient space (200GB+)
# 2. Check internet connection
# 3. Try building one database at a time:
export DATABASES="mitofish"
bash scripts/01_build_dbs_kraken_blastn.sh
```

#### R Package Installation Fails
```bash
# Install packages manually
R
> install.packages("devtools")
> devtools::install_github("tobiasgf/lulu")
> install.packages(c("dplyr", "tidyr", "readr", "stringr"))
> quit()

# For macOS Homebrew conflicts:
brew install libgit2
```

#### Krona Taxonomy Setup Fails
```bash
# Manual Krona setup
mkdir -p $CONDA_PREFIX/opt/krona/taxonomy
cd $CONDA_PREFIX/opt/krona/taxonomy
curl -O https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz
tar -xzf taxdump.tar.gz
rm taxdump.tar.gz
echo "✅ Manual Krona taxonomy setup complete"
```

#### Scripts Not Executable
```bash
# Make sure all scripts can be run
find scripts/ -name "*.sh" -exec chmod +x {} \;

# Verify permissions
ls -la scripts/
# Should show -rwxr-xr-x permissions
```

#### Pipeline Running Slowly
```bash
# Speed up for testing/demos
export SUBSET_COUNT=500 THREADS=4 DATABASES="mitofish"
bash scripts/02_quick_look_clean.sh mock/ results/fast_test
```

### Memory and Performance Issues

#### Out of Memory Errors
```bash
# Reduce resource usage
export THREADS=2 SUBSET_COUNT=1000

# Check available memory
free -h        # Linux
vm_stat        # macOS
```

#### Slow Processing
```bash
# Optimize for your system
export THREADS=$(nproc)          # Linux - use all cores
export THREADS=$(sysctl -n hw.ncpu)  # macOS - use all cores

# For slower machines
export THREADS=4 SUBSET_COUNT=500
```

### Platform-Specific Issues

#### macOS Issues
```bash
# Xcode command line tools missing
xcode-select --install

# Homebrew conflicts with conda
conda activate decode-dna  # Always activate first

# Apple Silicon compatibility
export ARCHFLAGS="-arch arm64"
```

#### Linux Issues
```bash
# Missing system dependencies
sudo apt update
sudo apt install build-essential curl wget git unzip

# WSL2 specific
wsl --set-default-version 2
```

#### Windows WSL2 Issues
```bash
# Enable WSL2
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Update WSL2 kernel
# Download from: https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi
```

---

## 🎓 For Instructors

### Pre-Class Preparation Checklist

#### 1-2 Days Before Class:
- [ ] **Test complete installation** on instructor machine
- [ ] **Build or obtain databases** (1.5 hours if building locally)
- [ ] **Prepare USB drives** with pre-built databases
- [ ] **Test both workflows** with mock data
- [ ] **Verify network access** for downloads during class

#### Day of Class:
- [ ] **USB drives ready** with databases
- [ ] **Backup installation files** for offline setup
- [ ] **Test example commands** work on classroom network
- [ ] **Prepare troubleshooting stations** for common issues

### Classroom Setup Strategy

#### Quick Student Setup (15-20 minutes):
```bash
# Essential classroom setup sequence
mkdir ~/eDNA_workshop && cd ~/eDNA_workshop
git clone https://github.com/piedna/DeCodeDNA.git && cd DeCodeDNA
chmod +x scripts/*.sh
conda env create -f environment.yml
conda activate decode-dna
bash scripts/install_krona_taxonomy.sh
bash scripts/install_R_dependencies.sh

# Connect USB drive and test
source scripts/setup_databases.sh
bash scripts/02_quick_look_clean.sh workflows/ont_native_barcodes/ results/class_test
```

#### Time-Saving Strategies:
- **Pre-built environments**: Create conda environment packages
- **USB database distribution**: Pass drives around class
- **Staged setup**: Students do basic setup before class
- **Pair programming**: Partner stronger/weaker students

### Common Student Issues & Solutions

#### Installation Problems:
| Issue | Quick Fix | Detailed Solution |
|-------|-----------|-------------------|
| Conda missing | `source ~/miniconda3/bin/activate` | [Conda installation](#-step-0-install-condaminiconda-if-not-already-installed) |
| Permission errors | `chmod +x scripts/*.sh` | File permissions section |
| Database not found | `source scripts/setup_databases.sh` | [Database setup](#️-database-setup-options) |
| R packages fail | `bash scripts/install_R_dependencies.sh` | [R troubleshooting](#r-package-installation-fails) |
| Environment conflicts | `conda deactivate && conda activate decode-dna` | Environment management |

#### Teaching Moments:
- **Database structure**: Show students what references look like
- **Quality control**: Explain why filtering steps matter
- **Method comparison**: Use different approaches as learning tools
- **Error handling**: Turn problems into debugging lessons

### Performance Optimization for Classroom

#### Fast Demo Mode:
```bash
# Quick setup for demonstrations
export DATABASES="mitofish" THREADS=4 SUBSET_COUNT=500
```

#### Bandwidth Management:
```bash
# Pre-download large files
# Share USB drives to reduce network load
# Use cached conda environments
```

#### Hardware Considerations:
- **8GB RAM minimum** per machine
- **Network bandwidth** for 20+ simultaneous downloads
- **Disk space** planning (10GB minimum, 200GB for full setup)

---

## 📞 Support & Resources

### Getting Help

**For installation issues:**
1. **Check this troubleshooting guide** first
2. **Verify system requirements** are met
3. **Try the common solutions** for your specific error
4. **Contact course support**: `ednacollab@uw.edu`

### Reporting Installation Problems

**When reporting issues, please include:**
- Operating system and version (`uname -a`)
- Conda version (`conda --version`)
- Full error messages (copy-paste)
- Steps that led to the error
- Hardware specifications (RAM, storage)

### Additional Resources

- **🏠 [Main README](README.md)**: Workflow instructions and course overview
- **📖 [ONT Native Workflow](workflows/ont_native_barcodes/README_ont_native.md)**: 12S fish community analysis
- **📖 [Custom CCI Workflow](workflows/custom_cci_barcodes/README_custom_cci.md)**: D-loop custom barcode analysis
- **🔬 [Course Support](mailto:ednacollab@uw.edu)**: Direct instructor assistance

### Online Resources

- **DeCodeDNA Repository**: https://github.com/piedna/DeCodeDNA
- **Conda Documentation**: https://docs.conda.io/
- **Oxford Nanopore Community**: https://community.nanoporetech.com/
- **eDNA Collaborative**: https://www.ednacollab.org

---

## ✅ Installation Complete!

**🎉 Successfully installed?** Return to the [main README.md](README.md) for:
- **📖 [Workflow selection](README.md#-choose-your-workflow)**: ONT Native vs Custom CCI
- **🚀 [Pipeline overview](README.md#-pipeline-overview)**: Understanding the analysis steps  
- **🎓 [Course progression](README.md#-for-students-course-progression)**: Learning path for FHL students
- **📊 [Expected results](README.md#-expected-results)**: Understanding your outputs

**🔧 Still having issues?** Check the [troubleshooting section](#-troubleshooting) above or contact course support.

**📖 Ready to analyze eDNA data?** The [main README](README.md) has everything you need for successful analysis!

---

*Installation guide for DeCodeDNA eDNA pipeline - Friday Harbor Labs 2025*