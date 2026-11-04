# Changelog

## 0.2.0 (unreleased)

Changes found while benchmarking DeCodeDNA against DECONA on the FHL 2025 workshop data.
The old behaviour can still be selected where it changes results.

### Changed
- **Script 03 keeps a consensus for each cluster (`REPRESENTATIVE=consensus`, new default).**
  In 0.1 each cluster was represented by its seed read (`vsearch --centroids`), which is one raw nanopore
  read with its sequencing errors, so fewer clusters matched reference sequences closely and more reads stopped
  at genus or family. Script 03 now writes the consensus of all reads in the cluster (`vsearch --consout`).
  `REPRESENTATIVE=centroid` gives the 0.1 behaviour.
- **Script 03 no longer writes one file per cluster.** `--clusters` produced a separate file for every
  cluster (millions of small files on real runs), and no later step used them. `WRITE_CLUSTER_MAP=true`
  writes the same information as one `.uc` table per sample instead.
- **Threads are worked out automatically (`THREADS=auto`, new default):** all CPU cores but one, within any
  Docker or cgroup limit. A number still sets it exactly. Defaults were fixed at 4 or 8 before.
- **Script 03 clusters several samples at the same time (`PARALLEL_SAMPLES=auto`)** when there are enough
  cores and free memory, splitting the threads between them. `PARALLEL_SAMPLES=1` runs one at a time.
- **Kraken2 memory mapping is decided automatically (`KRAKEN_MEMORY_MAPPING=auto`, new default):** a
  database is read from disk only when it would use more than about 60% of the free memory.
- **Large intermediate files are cleaned up as the run goes (`KEEP_INTERMEDIATES=false`, new default).**
  Script 02 removes the filtered reads and the EFPQ-converted copies once the classified reads are written,
  and gzip-compresses the Kraken2 per-read output and the unclassified reads; Script 03 removes the
  dereplicated reads after clustering. On the FHL COI run, Script 02 output had been about 3.7 times the
  size of the input reads. `KEEP_INTERMEDIATES=true` keeps everything as before.
- **Script 04 builds shared OTUs across samples (`OTU_MODE=shared`, new default).**
  In 0.1, every unique per-sample cluster sequence became its own OTU, so the same organism had a
  different OTU in each sample and real datasets produced hundreds of thousands of OTUs
  (about 360,000 for the FHL 12S run). Script 04 now pools the clusters from all samples (keeping their
  read counts), clusters them once at `OTU_SIMILARITY`, and counts each sample's reads against those
  shared OTUs with `vsearch --usearch_global --otutabout`. Set `OTU_MODE=per_sample` to get the 0.1 behaviour.
- **LULU now uses all OTUs by default (`LULU_MAX_OTUS=0`).** In 0.1 the default was a random subset of
  1,000 OTUs, which on real data meant LULU removed almost nothing. A subset is still available for
  quick classroom runs, e.g. `LULU_MAX_OTUS=1000`.
- The all-against-all OTU comparison before LULU now uses `THREADS` instead of a fixed 4 threads.
- **Script 01 builds much smaller Kraken2 databases.** Each database used to keep its own copy of the NCBI
  taxonomy download (about 47 GB, mostly accession-to-taxid tables), although classification only uses the
  `*.k2d` files (for the FHL 2025 builds: 12S 49 MB, COI 161 MB). The download is now made once, shared by the
  three databases and removed at the end (`KEEP_KRAKEN_TAXONOMY=true` keeps it), and each database is cleaned
  with `kraken2-build --clean`. Existing databases can be cleaned the same way.

### Fixed
- **LULU never removed any OTU.** The match list was made with `vsearch --allpairs_global`, which lists
  each pair of OTUs once. Because OTUs were sorted by abundance, the larger OTU was always listed first,
  and LULU (which looks up each OTU as a possible error of a larger one) never found a match. The match
  list now comes from `vsearch --usearch_global --self` (query, target, % identity, both directions),
  as recommended by the LULU authors. This affected all 0.1 results: LULU curation had no effect.
- `otu_table_<db>_vsearch_lulu_discarded.csv` was always empty because the script read an output LULU
  does not produce. It now lists the discarded OTUs, and `otu_lulu_map.csv` records which OTU each
  discarded OTU was merged into.
- The LULU R script is rewritten on every run, so a re-run never uses an older copy.
- Script 05 stopped with "sample_names_str: unbound variable" when run with `SKIP_KRAKEN=true`; the sample
  list is now set before the Kraken2 section.

### Added
- **`MIN_OTU_READS` (default 10):** OTUs with fewer reads than this across all samples are dropped as
  likely errors. `0` keeps everything.
- **`otu_build_summary_<db>.tsv` (Script 04):** reads and OTUs at each stage of OTU building.
- **`Read_assignment_summary.csv` (Script 05):** the share of reads in the OTU table that TaxonKit LCA
  assigned at species, genus, family or higher level, all against the same denominator.
- **`run_info.txt` (Scripts 03, 04 and 05):** date, computer (cores, free memory), DeCodeDNA version (git commit), tool versions, the settings
  that affect results, and the reference databases used (location, size, date, checksum of a small index file).
- GUI: settings for OTU building (`OTU_MODE`, `MIN_OTU_READS`), the cluster sequence (`REPRESENTATIVE`)
  and keeping intermediate files; LULU default shown as 0 (all OTUs).
- `scripts/resources.sh`: detects CPU cores and free memory on Linux, macOS and in Docker, used by Scripts 02-05.
- README: note on matching `DATABASES` to the marker (e.g. `DATABASES=coi` for COI runs).

## 0.1.0

First public release, used for the Friday Harbor Labs eDNA course (2025). DOI: 10.5281/zenodo.20453273
