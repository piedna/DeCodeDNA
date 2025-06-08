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

---
## Pipeline Workflow Overview

```mermaid
flowchart TB
  subgraph I [Wet Lab]
    MC[Mock community prep]
    MC --> MinION[MinION sequencing]
  end

  subgraph II [Basecalling]
    MinION --> SUP[SUP Basecalling]
  end

  subgraph III [Quick Look]
    SUP --> Kraken1[Raw Kraken2/Bracken<br/>Test thresholds (c = 0.05–1.0)]
  end

  subgraph IV [Consensus / Sort]
    Kraken1 --> Cons[Consensus: Amplicon_sorter, ProName, Decona/CD-hit/OBITools]
  end

  subgraph V [Denoise]
    Cons --> LULU[Self-BLAST & LULU filter]
  end

  subgraph VI [Taxonomic Assignment]
    LULU --> BLAST[BLAST + LCA]
    LULU --> Kraken2[2nd-Round Kraken2]
  end
