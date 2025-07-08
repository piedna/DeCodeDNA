# DeCodeDNA Installation & Quick-Start Guide

This document will get you from zero to a fully-working DeCodeDNA pipeline on macOS or Linux. It covers:

1. Cloning the repo; Building the primary Conda environment  
2. Populating Krona’s taxonomy  
3. Installing the “one-off” tools (R/LULU, Dorado, Amplicon_sorter, ONTbarcoder)  
4. Building your Kraken2 & BLAST reference databases  
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

All ktImportTaxonomy or ktImportText runs will produce fully-labeled HTML charts.

KronaTools ships only the binaries; you must fetch NCBI’s taxonomy dump yourself:

# 1) Make the taxonomy folder
mkdir -p $CONDA_PREFIX/opt/krona/taxonomy
cd        $CONDA_PREFIX/opt/krona/taxonomy

# 2) Download the raw NCBI taxonomy dump
#    - on Linux:
wget ftp://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz
#    - on macOS:
curl -O https://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz

# 3) Extract the dump
tar zxvf taxdump.tar.gz

# 4) Generate the Krona files
ktUpdateTaxonomy.sh

# 5) Confirm you now have:
ls
# → citations.dmp  division.dmp  gencode.dmp  merged.dmp  names.dmp
#   nodes.dmp      images.dmp    readme.txt   taxonomy.tab

# 6) Test with a tiny example 

	# Create a mock counts file:
	echo -e "taxid\tcount\n9606\t10\n562\t5" > test.tsv

	# Build a mini-Krona chart:
	ktImportText -o test.html test.tsv

	# Open it in your browser:
	open test.html   # or `xdg-open test.html` on Linux

⸻

3. Manual post-Conda installs

Some of our one-off tools don’t live in Bioconda.  We install them once inside the decode-dna env so that any time you do conda activate decode-dna they’re immediately on your PATH (or— in the case of LULU—available in R).

A) R + LULU
	1.	Create the installer script
From your project root (e.g. ~/Downloads/test_fhl/DeCodeDNA):

nano install_R.sh


	2.	Paste in the following (no edits):

#!/usr/bin/env bash
set -euo pipefail

# 1) Make sure we're in the right env
conda activate decode-dna

# 2) Install R, the Tidyverse, and remotes
conda install -y -c conda-forge \
  r-base=4.2 \
  r-tidyverse \
  r-remotes

# 3) Install lulu from GitHub via remotes
Rscript -e '
  if (!requireNamespace("remotes", quietly=TRUE)) {
    install.packages("remotes", repos="https://cloud.r-project.org")
  }
  remotes::install_github("tobiasgf/lulu", upgrade = FALSE)
'

# 4) Verify the install
Rscript -e '
  if (!"lulu" %in% rownames(installed.packages())) {
    stop("lulu did not install correctly")
  } else {
    cat("lulu version", as.character(packageVersion("lulu")), "installed\n")
  }
'


	3.	Save & exit
	•	Press Ctrl+X, then Y, then Enter.
	
	4.	Make it executable

chmod +x install_R.sh


	5.	Run it

./install_R.sh

You should see something like:

Collecting package metadata (…)
…
lulu version 0.1-3 installed

And now, in any R session inside decode-dna:

library(lulu)

will work without error.

⸻

B) Amplicon_sorter

# Grab the single-script sorter
cd $HOME/Downloads
#Clone the sorter repo (do this only once)
git clone https://github.com/avierstr/amplicon_sorter.git 

# Copy the script into your Conda env’s bin/ so it “belongs” to decode-dna
cp ~/Downloads/amplicon_sorter/amplicon_sorter.py \
   $CONDA_PREFIX/bin/amplicon_sorter

# Fix line endings (strip any CRLF ‘\r’ so the she-bang works correctly)
# Option A: if you have dos2unix installed
dos2unix $CONDA_PREFIX/bin/amplicon_sorter

# Option B: with built-in sed on macOS/BSD
sed -i '' -e $'s/\\r$//' $CONDA_PREFIX/bin/amplicon_sorter

# Make it executable
chmod +x $CONDA_PREFIX/bin/amplicon_sorter

# (Optional) remove the cloned repo cleanup
rm -rf ~/Downloads/amplicon_sorter

# Verify everything is on your PATH
which amplicon_sorter
# → /Users/you/miniconda3/envs/decode-dna/bin/amplicon_sorter

amplicon_sorter --help
# → usage screen appears


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

# open the ONTbarcoder2.3 app, or just open the app in Finder
open ONTbarcoder2.3.app


⸻

4. Build Reference Databases (Kraken 2 + BLAST)

We have provided a single wrapper script in `scripts/00_build_dbs_kraken_blastn.sh` that:

- Downloads and unpacks the three FASTA sets (MIDORI 12S, MIDORI COI, MitoFish mitogenomes)  
- Fetches NCBI taxonomy dump once  
- Builds three Kraken 2 DBs (`12s`, `coi`, `mitofish`) under `~/HOME/kraken2_db`  
- Builds three BLAST DBs under `~/HOME/blast_db`  

### Usage

```bash
# From your project root:
cd DeCodeDNA

# Make the script executable (once):
chmod +x scripts/00_build_dbs_kraken_blastn.sh

# Run it in foreground, capturing output:
./scripts/00_build_dbs_kraken_blastn.sh 2>&1 | tee build_all_dbs.log

# …or in the background:
nohup scripts/00_build_dbs_kraken_blastn.sh > build_all_dbs.log 2>&1 &

# Then watch with:
tail -f build_all_dbs.log

⸻

5. Run the full five-step pipeline

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

X. Tips & Troubleshooting
	•	Missing command not found?
Re-run the cp … $CONDA_PREFIX/bin/… steps after you conda activate decode-dna.
	•	Krona charts missing names?
Re-run ktUpdateTaxonomy.sh until names.dmp & nodes.dmp appear.
	•	Want full automation?
Create a scripts/bootstrap_manual_tools.sh that wraps all git clone, curl, cp steps.

###END###

