#!/usr/bin/env bash
# scripts/write_run_info.sh
#
# Writes run_info.txt into a step's output folder: when it ran, which DeCodeDNA version (git commit),
# tool versions, the settings that change results, and which reference databases were used.
# Called at the end of steps 04 and 05, so every results folder says exactly how it was made.
#
# Usage: bash scripts/write_run_info.sh <output_dir> <step_name>

OUT="${1:?need output dir}"
STEP="${2:-step}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT"
F="$OUT/run_info.txt"

ver() { "$@" 2>&1 | head -1 | tr -d '\r'; }

{
  echo "DeCodeDNA run info: $STEP"
  echo "date:            $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "host:            $(uname -sm)"
  if git -C "$PROJECT_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    echo "decodedna:       $(git -C "$PROJECT_ROOT" describe --tags --always --dirty 2>/dev/null) ($(git -C "$PROJECT_ROOT" log -1 --format=%cd --date=short))"
  else
    echo "decodedna:       (not a git checkout)"
  fi
  echo
  echo "## Settings"
  for v in DATABASES THREADS QUALITY_THRESHOLD MIN_LENGTH MAX_LENGTH CONFIDENCE VSEARCH_SIMILARITY \
           OTU_MODE OTU_SIMILARITY MIN_OTU_READS LULU_MAX_OTUS SUBSET_COUNT DB_ROOT BLAST_DB_ROOT DATABASE_DIR; do
    printf "%-19s %s\n" "$v:" "${!v:-(default)}"
  done
  echo
  echo "## Tools"
  command -v vsearch  >/dev/null && echo "vsearch:  $(ver vsearch --version | sed 's/,.*//')"
  command -v seqkit   >/dev/null && echo "seqkit:   $(ver seqkit version)"
  command -v kraken2  >/dev/null && echo "kraken2:  $(ver kraken2 --version)"
  command -v blastn   >/dev/null && echo "blastn:   $(ver blastn -version)"
  command -v taxonkit >/dev/null && echo "taxonkit: $(ver taxonkit version)"
  command -v Rscript  >/dev/null && echo "R:        $(ver Rscript --version)"
  command -v Rscript  >/dev/null && echo "lulu:     $(Rscript -e 'cat(as.character(tryCatch(packageVersion("lulu"), error=function(e) "not installed")))' 2>/dev/null)"
  echo
  echo "## Reference databases (folder, files, total size, newest file date)"
  for root in "${BLAST_DB_ROOT:-}" "${DB_ROOT:-}"; do
    [ -n "$root" ] && [ -d "$root" ] || continue
    for d in $DATABASES; do
      p="$root/$d"; [ -e "$p" ] || continue
      p=$(cd "$p" && pwd -P)
      n=$(find "$p" -maxdepth 1 -type f | wc -l | tr -d ' ')
      sz=$(du -sh "$p" 2>/dev/null | cut -f1)
      newest=$(find "$p" -maxdepth 1 -type f -exec ls -l --time-style=+%Y-%m-%d {} + 2>/dev/null | awk '{print $6}' | sort | tail -1)
      idx=$(ls "$p"/*.nin "$p"/*.nal "$p"/hash.k2d 2>/dev/null | head -1)
      sum=""; [ -n "$idx" ] && sum=" md5($(basename "$idx"))=$( (md5sum "$idx" 2>/dev/null || md5 -q "$idx") | cut -c1-32)"
      echo "$d  $p  $n files  $sz  $newest$sum"
    done
  done
} > "$F"
echo "   • Run details written to $F"
