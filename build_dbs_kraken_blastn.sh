#!/usr/bin/env bash
set -euo pipefail

# ─── 0) Point at your decode-dna env (no activate hooks) ───
ENV_ROOT="$HOME/miniconda/envs/decode-dna"
export PATH="$ENV_ROOT/bin:$PATH"

# ─── 1) Configurable paths & threads ───
WORK="$HOME/Downloads/test_fhl"
FASTA_ROOT="$WORK/db_fasta"
KRAKEN_DB="$WORK/kraken2_db"
BLAST_DB="$WORK/blast_db"
THREADS=15

# ─── 2) Prepare directory structure ───
mkdir -p \
  "$FASTA_ROOT" \
  "$KRAKEN_DB/common_taxonomy" \
  "$KRAKEN_DB"/{12s,coi,mitofish}/taxonomy \
  "$BLAST_DB"/{12s,coi,mitofish}

# ─── 3) Download & unpack FASTAs ───
cd "$FASTA_ROOT"

## 3a) 12S (srRNA) from MIDORI UNIQUE
curl -L -o midori_12s.zip \
  "https://www.reference-midori.info/download/Databases/GenBank265_2025-03-08/BLAST/uniq/fasta/MIDORI2_UNIQ_NUC_GB265_srRNA_BLAST.fasta.zip"
unzip -q midori_12s.zip && rm midori_12s.zip
mv MIDORI2_UNIQ_NUC_GB265_srRNA_BLAST.fasta 12s.fasta

## 3b) COI from MIDORI UNIQUE
curl -L -o midori_coi.zip \
  "https://www.reference-midori.info/download/Databases/GenBank265_2025-03-08/BLAST/uniq/fasta/MIDORI2_UNIQ_NUC_GB265_CO1_BLAST.fasta.zip"
unzip -q midori_coi.zip && rm midori_coi.zip
mv MIDORI2_UNIQ_NUC_GB265_CO1_BLAST.fasta coi.fasta

## 3c) MiFish mitogenomes
curl -L -o mifish.zip \
  "https://mitofish.aori.u-tokyo.ac.jp/species/detail/download/?filename=download%2F/complete_partial_mitogenomes.zip"
unzip -q mifish.zip && rm mifish.zip
mv mito-all mitofish.fasta

# ─── 4) Fetch & extract NCBI taxonomy (once) ───
cd "$KRAKEN_DB/common_taxonomy"

## 4a) Download taxonomy dump
curl -L -o taxdump.tar.gz \
  https://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz
tar -xzf taxdump.tar.gz && rm taxdump.tar.gz

## 4b) Download accession→taxid map
curl -L -o nucl_gb.accession2taxid.gz \
  ftp://ftp.ncbi.nih.gov/pub/taxonomy/accession2taxid/nucl_gb.accession2taxid.gz
gunzip nucl_gb.accession2taxid.gz
mv nucl_gb.accession2taxid accession2taxid.map

# ─── 5) Build each Kraken 2 DB ───
for DB in 12s coi mitofish; do
  echo
  echo "=== Building Kraken2 DB: $DB ==="
  TARGET="$KRAKEN_DB/$DB"

  # 5a) Symlink shared taxonomy dumps
  ln -sf "$KRAKEN_DB/common_taxonomy/"*.dmp "$TARGET/taxonomy/"

  # 5b) Symlink accession→taxid map
  ln -sf "$KRAKEN_DB/common_taxonomy/accession2taxid.map" \
        "$TARGET/accession2taxid.map"

  # 5c) Add the correct FASTA library
  FASTA="$FASTA_ROOT/${DB}.fasta"
  echo "--> Adding library: $FASTA"
  kraken2-build --add-to-library "$FASTA" --db "$TARGET"

  # 5d) Build with threads
  echo "--> Building $DB with $THREADS threads"
  kraken2-build --build --db "$TARGET" --threads "$THREADS"

  echo "✅ Finished Kraken2 DB: $DB"
done

# ─── 6) Sanity‐check Kraken2 12S ───
echo -e "taxid\tcount\n2759\t10\n4932\t5" > "$WORK"/test_kraken2_12s.tsv
kraken2 --db "$KRAKEN_DB/12s" --report "$WORK"/kraken2_12s.report "$WORK"/test_kraken2_12s.tsv

# ─── 7) Build three BLAST DBs with makeblastdb ───
echo
echo "=== Building BLAST DBs ==="

## 7a) 12S
makeblastdb \
  -in "$FASTA_ROOT/12s.fasta" \
  -dbtype nucl \
  -out "$BLAST_DB/12s/12s" \
  -parse_seqids \
  -title "MIDORI 12S"

## 7b) COI
makeblastdb \
  -in "$FASTA_ROOT/coi.fasta" \
  -dbtype nucl \
  -out "$BLAST_DB/coi/coi" \
  -parse_seqids \
  -title "MIDORI COI"

## 7c) MiFish
makeblastdb \
  -in "$FASTA_ROOT/mitofish.fasta" \
  -dbtype nucl \
  -out "$BLAST_DB/mitofish/mitofish" \
  -parse_seqids \
  -title "MiFish mitogenomes"

# ─── 8) Sanity-check BLAST 12S ───
echo -e ">test\nACGTACGTACGT" > "$WORK"/test_blast_query.fasta
blastn \
  -db "$BLAST_DB/12s/12s" \
  -query "$WORK"/test_blast_query.fasta \
  -outfmt "6 qseqid sseqid pident length" | head

echo
echo "🎉 All Kraken2 & BLAST DBs built under:"
echo "    Kraken2: $KRAKEN_DB/{12s,coi,mitofish}"
echo "    BLAST:   $BLAST_DB/{12s,coi,mitofish}"