#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────
# 00_build_dbs_kraken_blastn.sh
# Builds three Kraken 2 DBs (12s, coi, mitofish) with fresh NCBI taxonomy,
# then three BLAST DBs (same markers) with cleaned FASTA headers.
# ────────────────────────────────────────────────────────────────────

# 0) Force using your decode-dna conda env no matter how this script is invoked
ENV_ROOT="$HOME/miniconda/envs/decode-dna"
export PATH="$ENV_ROOT/bin:$PATH"

# 1) User‐configurable paths & threads
WORK="$HOME/Downloads/test_fhl"
FASTA_ROOT="$WORK/db_fasta"
BLAST_CLEAN="$WORK/db_fasta_clean"
KRAKEN_DB="$WORK/kraken2_db"
BLAST_DB="$WORK/blast_db"
THREADS=15

# 2) Prepare directory structure
mkdir -p \
  "$FASTA_ROOT" \
  "$BLAST_CLEAN" \
  "$KRAKEN_DB"/{12s,coi,mitofish} \
  "$BLAST_DB"/{12s,coi,mitofish}

# 3) Download & unpack the three FASTA sources
cd "$FASTA_ROOT"

echo ">>> Downloading FASTAs"
curl -sL -o midori_12s.zip  \
  "https://www.reference-midori.info/download/Databases/GenBank265_2025-03-08/BLAST/uniq/fasta/MIDORI2_UNIQ_NUC_GB265_srRNA_BLAST.fasta.zip"
unzip -q midori_12s.zip && rm midori_12s.zip
mv MIDORI2_UNIQ_NUC_GB265_srRNA_BLAST.fasta midori_12s.fasta

curl -sL -o midori_coi.zip  \
  "https://www.reference-midori.info/download/Databases/GenBank265_2025-03-08/BLAST/uniq/fasta/MIDORI2_UNIQ_NUC_GB265_CO1_BLAST.fasta.zip"
unzip -q midori_coi.zip && rm midori_coi.zip
mv MIDORI2_UNIQ_NUC_GB265_CO1_BLAST.fasta  midori_coi.fasta

curl -sL -o mifish.zip \
  "https://mitofish.aori.u-tokyo.ac.jp/species/detail/download/?filename=download%2F/complete_partial_mitogenomes.zip"
unzip -q mifish.zip && rm mifish.zip
mv mito-all mifish.fasta

echo "✔ FASTAs ready in $FASTA_ROOT"
echo

# 4) Build each Kraken 2 DB with **fresh** NCBI taxonomy
#    (avoids accession2taxid complaints)
for DB in 12s coi mitofish; do
  echo ">>> Building Kraken2 DB for marker: $DB"
  TARGET="$KRAKEN_DB/$DB"
  mkdir -p "$TARGET"

  # a) download NCBI taxonomy here
  echo "  • Downloading NCBI taxonomy into $TARGET/taxonomy/"
  kraken2-build --download-taxonomy \
                --db "$TARGET"

  # b) add our library
  FASTA="$FASTA_ROOT/${DB}.fasta"
  echo "  • Adding FASTA library: $FASTA"
  kraken2-build --add-to-library "$FASTA" \
                --db "$TARGET" \
                --no-masking

  # c) build the DB
  echo "  • Building database with $THREADS threads"
  kraken2-build --build \
                --db "$TARGET" \
                --threads "$THREADS" \
                --no-masking

  echo "  Kraken2 DB $DB done."
  echo
done

# 5) Sanity‐check one Kraken2 DB (12S)
echo ">>> Sanity‐check Kraken2 12s"
echo -e "taxid\tcount\n2759\t10\n4932\t5" > "$WORK/test_kraken2_12s.tsv"
kraken2 --db "$KRAKEN_DB/12s" \
        --report "$WORK/kraken2_12s.report" \
        "$WORK/test_kraken2_12s.tsv"
echo "  ✔ report in $WORK/kraken2_12s.report"
echo

# 6) Clean headers & build BLAST DBs
#    We rewrite each header to MARK_N, strip non-ACGT, to satisfy makeblastdb limits.
for MARK in 12s coi mitofish; do
  echo ">>> Cleaning & building BLAST DB for marker: $MARK"

  # pick inputs
  case "$MARK" in
    12s)      IN="$FASTA_ROOT/midori_12s.fasta"; TITLE="MIDORI 12S" ;;
    coi)      IN="$FASTA_ROOT/midori_coi.fasta"; TITLE="MIDORI COI" ;;
    mitofish) IN="$FASTA_ROOT/mifish.fasta";     TITLE="MiFish mitogenomes" ;;
  esac

  CLEAN="$BLAST_CLEAN/${MARK}.fasta"
  OUT="$BLAST_DB/$MARK"
  mkdir -p "$OUT"

  echo "  • Rewriting headers → $CLEAN"
  awk -v mark="$MARK" '
    BEGIN { RS=">"; ORS="" ; count=0 }
    NR>1 {
      count++
      header = ">" mark "_" count "\n"
      seq="" 
      # join & strip to ACGT only
      for(i=2;i<=NF;i++) {
        gsub(/[^ACGT]/,"",$i)
        seq=seq $i
      }
      if(length(seq)) print header seq "\n"
    }
  ' "$IN" > "$CLEAN"

  echo "  • Running makeblastdb → $OUT/$MARK"
  makeblastdb \
    -in "$CLEAN" \
    -dbtype nucl \
    -parse_seqids \
    -title "$TITLE" \
    -out "$OUT/$MARK"

  echo "  BLAST DB $MARK built."
  echo
done

# 7) Sanity‐check BLAST 12S
echo ">>> Sanity‐check BLAST 12S"
echo -e ">test\nACGTACGTACGT" > "$WORK/test_blast_query.fasta"
blastn \
  -db "$BLAST_DB/12s/12s" \
  -query "$WORK/test_blast_query.fasta" \
  -outfmt "6 qseqid sseqid pident length" | head
echo

echo " All Kraken2 DBs:    $KRAKEN_DB/{12s,coi,mitofish}"
echo " All BLAST   DBs:    $BLAST_DB/{12s,coi,mitofish}"