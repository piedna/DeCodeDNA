# Changelog

## 0.2.0 (unreleased)

Changes found while benchmarking DeCodeDNA against DECONA on the FHL 2025 workshop data.
The old behaviour can still be selected where it changes results.

### Changed
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

### Added
- **`MIN_OTU_READS` (default 10):** OTUs with fewer reads than this across all samples are dropped as
  likely errors. `0` keeps everything.
- **`otu_build_summary_<db>.tsv` (Script 04):** reads and OTUs at each stage of OTU building.
- **`Read_assignment_summary.csv` (Script 05):** the share of reads in the OTU table that TaxonKit LCA
  assigned at species, genus, family or higher level, all against the same denominator.
- **`run_info.txt` (Scripts 04 and 05):** date, DeCodeDNA version (git commit), tool versions, the settings
  that affect results, and the reference databases used (location, size, date, index checksum).
- GUI: settings for OTU building (`OTU_MODE`, `MIN_OTU_READS`); LULU default shown as 0 (all OTUs).
- README: note on matching `DATABASES` to the marker (e.g. `DATABASES=coi` for COI runs).

## 0.1.0

First public release, used for the Friday Harbor Labs eDNA course (2025). DOI: 10.5281/zenodo.20453273
