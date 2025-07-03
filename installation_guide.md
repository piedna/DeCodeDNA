# DeCodeDNA Installation & Quick-Start Guide

This document will get you from zero to a fully-working DeCodeDNA pipeline on macOS or Linux. It covers:

1. Cloning the repo  
2. Building the primary Conda environment  
3. Populating Krona’s taxonomy  
4. Installing the “one-off” tools (R/LULU, Dorado, Amplicon_sorter, ONTbarcoder)  
5. Running the five-step pipeline end-to-end  

---  

## 1. Clone & Conda environment

```bash
# 1) Clone the DeCodeDNA repo
git clone https://github.com/piedna/DeCodeDNA.git
cd DeCodeDNA

# 2) Create & activate the Conda env
conda env create -f environment.yml
conda activate decode-dna

Your decode-dna env will include:

channels:
  - conda-forge
  - bioconda
  - defaults

dependencies:
  - python>=3.11          # modern Python supported by Bioconda
  - pip                   # for pip-only installs
  - nanofilt=2.8.0        # filter reads by length/quality
  - cutadapt              # primer trimming
  - kraken2               # quick-look taxonomic classification
  - vsearch               # clustering & dereplication
  - cd-hit                # sequence clustering
  - blast                 # NCBI BLAST+
  - taxonkit              # taxonomy utilities
  - seqkit                # FASTA/Q utilities
  - krona                 # interactive HTML taxonomic charts
  - pod5                  # convert legacy FAST5 → POD5
  - clang_osx-64          # macOS C compiler for any builds
  - llvm-openmp           # OpenMP runtime for clang

  # pip-only packages:
  - pip:
    - edlib
    - biopython
    - matplotlib

Once this finishes, you can verify:

which kraken2   # …/envs/decode-dna/bin/kraken2
which vsearch
which cd-hit
which blastn
which taxonkit
which seqkit
which ktImportTaxonomy
which pod5


⸻

2. Populate Krona’s taxonomy

KronaTools ships only the binaries; you must fetch NCBI’s taxonomy dump yourself:

mkdir -p $CONDA_PREFIX/opt/krona/taxonomy
cd        $CONDA_PREFIX/opt/krona/taxonomy
ktUpdateTaxonomy.sh

You should now see files like names.dmp, nodes.dmp, merged.dmp in that folder. All subsequent ktImportTaxonomy or ktImportText runs will produce fully-labeled HTML charts.

⸻

3. Manual post-Conda installs

Some tools aren’t present in Bioconda. We install these once inside the decode-dna env so that every conda activate decode-dna puts them on your $PATH.

A) R + LULU

# install R + the Tidyverse
conda install -c conda-forge \
  r-base=4.2 \
  r-tidyverse \
  r-biocmanager

# install LULU from Bioconductor
R --quiet <<'EOF'
if (!requireNamespace("BiocManager", quietly=TRUE))
  install.packages("BiocManager")
BiocManager::install("lulu")
quit(save="no")
EOF

Your R-based denoise script can now library(lulu) without errors.

⸻

B) Amplicon_sorter

# grab the single-script sorter
cd $HOME/Downloads
git clone https://github.com/avierstr/amplicon_sorter.git

# install into your conda bin/
cp amplicon_sorter/amplicon_sorter.py \
   $CONDA_PREFIX/bin/amplicon_sorter
chmod +x $CONDA_PREFIX/bin/amplicon_sorter

# cleanup (optional)
rm -rf amplicon_sorter

# test
which amplicon_sorter
amplicon_sorter --help


⸻

C) Dorado (Nanopore basecaller)
	1.	Visit the Dorado releases page.
	2.	Download the tarball for your platform (e.g. dorado-1.x.x-osx-arm64.tar.gz).
	3.	Extract & copy the binary:

cd $HOME/Downloads
tar xzf dorado-*.tar.gz
cp dorado-*/bin/dorado $CONDA_PREFIX/bin/
chmod +x               $CONDA_PREFIX/bin/dorado

# test
which dorado
dorado --help



⸻

D) ONTbarcoder (sample demultiplexing)

cd $HOME/Downloads

# download the macOS zip for ONTbarcoder2.3
curl -L -o ONTbarcoder2.3_OSX.zip \
     https://github.com/asrivathsan/ONTbarcoder/releases/download/2.3.0/ONTbarcoder2.3.0_OSX.zip

unzip ONTbarcoder2.3_OSX.zip

# install into your conda bin/
cp ONTbarcoder2.3_OSX/bin/ontbarcoder \
   $CONDA_PREFIX/bin/
chmod +x $CONDA_PREFIX/bin/ontbarcoder

# test
which ontbarcoder
ontbarcoder --help


⸻

4. Run the full five-step pipeline

Everything is now on your $PATH.  From DeCodeDNA/ simply:

bash scripts/01_basecall_and_demux.sh   mock             results/01_basecall
bash scripts/02_quick_look_clean.sh     results/01_basecall results/02_quicklook
bash scripts/03_consensus_sort.sh       results/02_quicklook results/03_consensus
bash scripts/04_denoise.sh              results/03_consensus results/04_denoise
bash scripts/05_taxonomic_assignment.sh results/04_denoise  results/05_taxonomy

Or automate with a tiny wrapper (run_all.sh):

#!/usr/bin/env bash
set -euo pipefail

INPUT="$1"   # e.g. mock/
OUT="$2"     # e.g. results/

bash scripts/01_basecall_and_demux.sh   "$INPUT"         "$OUT/01_basecall"
bash scripts/02_quick_look_clean.sh     "$OUT/01_basecall" "$OUT/02_quicklook"
bash scripts/03_consensus_sort.sh       "$OUT/02_quicklook" "$OUT/03_consensus"
bash scripts/04_denoise.sh              "$OUT/03_consensus" "$OUT/04_denoise"
bash scripts/05_taxonomic_assignment.sh "$OUT/04_denoise"   "$OUT/05_taxonomy"

echo " Pipeline complete! See outputs under $OUT"

Then:

bash run_all.sh mock results


⸻

5. Tips & Troubleshooting
	•	Missing command not found?
Re-run the cp … $CONDA_PREFIX/bin/… steps after you conda activate decode-dna.
	•	Krona charts missing names?
Re-run ktUpdateTaxonomy.sh until names.dmp & nodes.dmp appear.
	•	Want full automation?
Create a scripts/bootstrap_manual_tools.sh that wraps all git clone, curl, cp steps.

###END###

