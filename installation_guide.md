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

### Required Software
- **Conda/Miniconda**: Package manager ([Download here](https://docs.conda.io/en/latest/miniconda.html))
- **Git**: Version control (usually pre-installed on macOS/Linux)

---

## 🚀 Quick Setup (Minimal)

**For students who just want to run the pipeline on mock data:**

```bash
# 1. Create workspace and clone repository
mkdir ~/eDNA_workshop && cd ~/eDNA_workshop
git clone https://github.com/piedna/DeCodeDNA.git && cd DeCodeDNA

# 2. Make scripts executable (important!)
chmod +x scripts/*.sh

# 3. Install environment
conda env create -f environment.yml
conda activate decode-dna

# 4. Install R package for denoising
Rscript -e 'if(!require(devtools)) install.packages("devtools"); devtools::install_github("tobiasgf/lulu")'

# 5. Test with mock data (skip basecalling, start from step 2)
bash scripts/02_quick_look_clean.sh mock/basecalled_fastq/ results/02_quicklook
```

**✅ This minimal setup lets you run steps 2-5 of the pipeline on example data!**

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
# ├── basecalled_fastq/               # Ready-to-use sequences (START HERE)
# │   ├── test_fhl_200k_1.fastq      # Sample replicate 1 (~200k reads)
# │   ├── test_fhl_200k_2.fastq      # Sample replicate 2
# │   ├── test_fhl_200k_3.fastq      # Sample replicate 3
# │   └── README.txt                 # Data description
# └── mock_amplicon_sorter_clustered_consensus_*.fasta  # Pre-computed server results
#
# 🎓 File Format Explanation:
# • FAST5: Original Oxford Nanopore format (HDF5-based, slower)
# • POD5: Modern format (faster, default in current MinKNOW)
# • FASTQ: Basecalled sequences ready for analysis
# • Pre-computed consensus: High-quality results from server processing
#
# 💡 For classroom: Use basecalled_fastq/ files to focus on bioinformatics
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

### Step 2: Conda Environment
```bash
# Create environment from file
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

### Step 3: Install R Packages
```bash
# Install LULU package for denoising
echo "Installing LULU R package..."
Rscript -e '
  if (!requireNamespace("devtools", quietly = TRUE)) {
    install.packages("devtools", repos = "https://cloud.r-project.org")
  }
  devtools::install_github("tobiasgf/lulu", upgrade = FALSE)
  
  # Test installation
  if (requireNamespace("lulu", quietly = TRUE)) {
    cat("✅ LULU installed successfully\n")
  } else {
    cat("❌ LULU installation failed\n")
  }
'
```

### Step 4: External Tools
```bash
# Create tools directory
mkdir -p ../tools
cd ../tools

echo "Installing external tools..."

# A) Dorado (Oxford Nanopore basecaller)
echo "📥 Installing Dorado..."
# Visit https://github.com/nanoporetech/dorado/releases for latest version
# Example for macOS ARM64:
curl -L -o dorado.tar.gz "https://github.com/nanoporetech/dorado/releases/download/v1.0.2/dorado-1.0.2-osx-arm64.tar.gz"
tar xzf dorado.tar.gz
cp dorado-*/bin/dorado $CONDA_PREFIX/bin/
chmod +x $CONDA_PREFIX/bin/dorado
rm -rf dorado* # cleanup
echo "✅ Dorado installed to $CONDA_PREFIX/bin/dorado"

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
echo "   Location: $(pwd)/ONTbarcoder2.3.app"

# Return to main directory
cd ../DeCodeDNA

# Verify external tools
echo "🔍 Verifying external tool installation..."
for tool in dorado amplicon_sorter; do
  if command -v $tool >/dev/null; then
    echo "✅ $tool: $(which $tool)"
  else
    echo "❌ $tool: not found"
  fi
done
```

### Step 5: Reference Databases
```bash
# Build all reference databases
echo "🗄️ Building reference databases..."
echo "⏰ This will take 20-30 minutes and download ~2GB of data"
echo "💡 Tip: Run this in the background or during a break"

# Option A: Run in foreground with logging
./scripts/01_build_dbs_kraken_blastn.sh 2>&1 | tee database_build.log

# Option B: Run in background
# nohup ./scripts/01_build_dbs_kraken_blastn.sh > database_build.log 2>&1 &
# tail -f database_build.log  # Watch progress

echo "✅ Database building initiated"
echo "📁 Databases will be created in ../databases/"
echo "📋 Monitor progress: tail -f database_build.log"
```

---

## 🧪 Testing Your Installation

### Test 1: Environment Check
```bash
conda activate decode-dna

# Check Python packages
python -c "
import sys
packages = ['biopython', 'matplotlib', 'pandas', 'numpy']
for pkg in packages:
    try:
        __import__(pkg)
        print(f'✅ {pkg}')
    except ImportError:
        print(f'❌ {pkg}')
"

# Check R packages
Rscript -e "
if (requireNamespace('lulu', quietly=TRUE)) {
  cat('✅ LULU R package\n')
} else {
  cat('❌ LULU R package\n')
}
"
```

### Test 2: Mock Data Pipeline
```bash
# Quick test run (should complete in 5-10 minutes)
echo "🧪 Testing pipeline with mock data..."

# Make sure scripts are executable
chmod +x scripts/*.sh

# Step 2: Quick classification (using pre-basecalled FASTQ files)
bash scripts/02_quick_look_clean.sh mock/basecalled_fastq/ results/test_02

# Step 3: Consensus building  
bash scripts/03_consensus_sort.sh results/test_02 results/test_03

# Step 4: Denoising
bash scripts/04_denoise.sh results/test_03 results/test_04

# Check results
if [[ -f "results/test_04/otu_table_lulu_curated.csv" ]]; then
  echo "✅ Pipeline test successful!"
  echo "📊 Results in results/test_04/"
  echo "🧬 Found $(tail -n +2 results/test_04/otu_table_lulu_curated.csv | wc -l) curated OTUs"
else
  echo "❌ Pipeline test failed"
  echo "🔍 Check error messages above"
fi
```

### Test 3: Full Pipeline (if databases are built)
```bash
# Only run if databases exist
if [[ -d "../databases/blast_db" ]]; then
  echo "🔬 Testing full taxonomic assignment..."
  bash scripts/05_taxonomic_assignment.sh results/test_04 results/test_05
  
  if [[ -f "results/test_05/03_final_taxonomy/method_comparison_summary.csv" ]]; then
    echo "✅ Full pipeline test successful!"
    echo "🌐 Open Krona plots: results/test_05/04_krona_plots/*.html"
  fi
else
  echo "⏩ Skipping taxonomic assignment test (databases not built yet)"
fi
```

---

## 📚 Usage Examples

### Complete Workflow
```bash
# Always start by activating environment
conda activate decode-dna

# For mock data (no basecalling needed):
bash scripts/02_quick_look_clean.sh mock/basecalled_fastq/ results/02_quicklook
bash scripts/03_consensus_sort.sh results/02_quicklook results/03_consensus  
bash scripts/04_denoise.sh results/03_consensus results/04_denoise
bash scripts/05_taxonomic_assignment.sh results/04_denoise results/05_taxonomy

# For real POD5 data (includes basecalling):
bash scripts/00_basecall_and_demux.sh   # First time setup + basecalling
bash scripts/02_quick_look_clean.sh your_fastq_dir/ results/02_quicklook
# ... continue with steps 3-5
```

### Customization Options
```bash
# Faster processing for teaching (fewer sequences)
export SUBSET_COUNT=1000
export THREADS=4

# Different quality thresholds
export QUALITY_THRESHOLD=15  # Default: 12
export MIN_LENGTH=200        # Default: 100

# Enable amplicon_sorter local execution (may hang)
RUN_AMPLICON_SORTER=1 bash scripts/03_consensus_sort.sh results/02_quicklook results/03_consensus
```

---

## 🔧 Troubleshooting

### Common Installation Issues

**"conda: command not found"**
```bash
# Install Miniconda first
curl -O https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh
bash Miniconda3-latest-MacOSX-x86_64.sh
# Restart terminal, then retry
```

**Environment creation fails**
```bash
# Try with mamba (faster)
conda install mamba -c conda-forge
mamba env create -f environment.yml

# Or update conda first
conda update conda
conda env create -f environment.yml
```

**"pod5 illegal hardware instruction"**
```bash
# This is expected on ARM64 Macs
# Scripts handle this gracefully - pod5 conversion is optional
echo "✅ This is expected and handled automatically"
```

**R package installation fails**
```bash
# Install R packages manually
R
> install.packages("devtools")
> devtools::install_github("tobiasgf/lulu")
> quit()
```

**Database build fails**
```bash
# Check available space
df -h .

# Check internet connection
curl -I https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz

# Retry with verbose output
bash -x scripts/01_build_dbs_kraken_blastn.sh
```

### Performance Issues

**Pipeline running slowly**
```bash
# Reduce dataset size
export SUBSET_COUNT=500

# Use fewer CPU threads  
export THREADS=2

# Check system resources
top
# Look for high CPU/memory usage
```

**Large file handling**
```bash
# Clean up intermediate files
rm -rf results/*/00_temp_files/

# Monitor disk space
du -sh results/
df -h .
```

---

## 🎓 For Instructors

### Pre-Class Setup
1. **Test complete installation** on instructor machine
2. **Build databases** ahead of time (20-30 minutes)
3. **Prepare USB drives** with key files for offline installation
4. **Test network capacity** for simultaneous downloads

### Class Day Shortcuts
```bash
# Quick student setup (5 minutes)
mkdir ~/eDNA_workshop && cd ~/eDNA_workshop
git clone https://github.com/piedna/DeCodeDNA.git && cd DeCodeDNA
chmod +x scripts/*.sh  # Make scripts executable
conda env create -f environment.yml
conda activate decode-dna

# Copy pre-built databases (if available)
# cp -r /path/to/shared/databases ../databases

# Start with mock data analysis (use pre-basecalled FASTQ files)
bash scripts/02_quick_look_clean.sh mock/basecalled_fastq/ results/02_quicklook
```

### Student Support
- **Common issues**: Have solutions ready for conda/R problems
- **Backup plan**: Pre-computed results for each step
- **Timing**: Allow extra time for installations
- **Resources**: Monitor network/CPU usage during class

---

## 🔄 Maintenance

### Updating the Pipeline
```bash
# Update repository
git pull origin main

# Update conda environment
conda env update -f environment.yml

# Update R packages  
Rscript -e 'devtools::install_github("tobiasgf/lulu", upgrade=TRUE)'
```

### Cleaning Up
```bash
# Remove temporary files
find results/ -name "00_temp_files" -type d -exec rm -rf {} +

# Remove old environments
conda env remove -n decode-dna-old

# Clean conda cache
conda clean --all
```

---

## 📞 Support

### Getting Help
1. **Check this guide** for common solutions
2. **Review script comments** for step-specific guidance
3. **Check GitHub issues** for known problems
4. **Contact instructors**: `ednacollab@uw.edu`

### Reporting Issues
When reporting problems, include:
- Operating system and version
- Conda environment export: `conda env export > my_environment.yml`
- Error messages (full output)
- Steps to reproduce the issue

---

**Installation complete! 🎉**

You're ready to analyze eDNA data with the DeCodeDNA pipeline.