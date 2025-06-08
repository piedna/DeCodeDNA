# DeCodeDNA

**Nanopore eDNA bioinformatics pipeline for FHL class 2025**

---

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/piedna/DeCodeDNA.git

# 2. Enter the project directory
cd DeCodeDNA

# 3. Create the Conda environment
conda env create -f environment.yml

# 4. Activate the environment
conda activate decode-dna

# 5. Run the first step (basecalling) on our example data
bash scripts/01_basecall.sh data/example_fast5/ results/fastq/
