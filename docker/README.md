# DeCodeDNA in Docker (macOS, Windows, Linux)

> Prefer buttons? The double-click launchers in [`../launchers`](../launchers/README.md) start the same
> image with a browser interface (`decodedna gui`).

One image contains every tool the pipeline needs (Kraken2, BLAST+, vsearch,
TaxonKit, SeqKit, Krona, R + LULU, amplicon_sorter), the NCBI taxonomy used by
Krona/TaxonKit, and the example data. It runs the same on Intel and
Apple Silicon / ARM machines.

The reference databases (~200 GB) are **not** inside the image. You keep them in
a folder on your computer (or USB drive) and mount it at `/databases`.

## 1. Install Docker

| OS | Install |
|----|---------|
| macOS | [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) |
| Windows 10/11 | [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) (WSL 2 backend) |
| Linux | [Docker Engine](https://docs.docker.com/engine/install/) |

In Docker Desktop, open **Settings → Resources** and give Docker at least
8 GB of memory (16 GB recommended). Kraken2 loads databases into memory; if you
cannot spare the RAM, set `KRAKEN_MEMORY_MAPPING=true` (slower, reads from disk).

## 2. Get the image

```bash
docker pull ghcr.io/piedna/decodedna:latest
```

Or build it yourself from the repository root:

```bash
docker build -f docker/Dockerfile -t ghcr.io/piedna/decodedna:latest .
```

## 3. Run

Two folders are mounted into the container:

- your **workspace** (input data + results) at `/work`
- your **database folder** (contains `kraken2_db/` and `blast_db/`) at `/databases`

macOS / Linux:

```bash
docker run --rm -it \
  -v "$PWD":/work \
  -v /Volumes/DeCodeDNA_DB/databases:/databases \
  ghcr.io/piedna/decodedna:latest check
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/work" `
  -v "E:\databases:/databases" `
  ghcr.io/piedna/decodedna:latest check
```

On Linux, add `--user "$(id -u):$(id -g)"` so result files are owned by you.

### Commands

```text
decodedna gui                           Browser interface on port 8080 (add -p 127.0.0.1:8080:8080)
decodedna check                         Check tools and reference databases
decodedna build-db                      Build databases into /databases (1-2 h, ~200 GB)
decodedna qc         <input> <out>      Script 02: quality filter + Kraken2 quick look
decodedna consensus  <02_dir> <out>     Script 03: vsearch consensus
decodedna denoise    <03_dir> <out>     Script 04: LULU denoising
decodedna taxonomy   <04_dir> <out>     Script 05: BLAST/TaxonKit/Kraken2 + Krona
decodedna run-all    <input> <run_dir>  Scripts 02 -> 05 in one go
decodedna example    <run_dir>          run-all on the bundled 12S mock data
```

Paths are paths *inside* the container, so anything in your workspace is under `/work`:

```bash
# whole pipeline on your own FASTQ folder, results in ./results/my_run
docker run --rm -it -v "$PWD":/work -v /path/to/databases:/databases \
  ghcr.io/piedna/decodedna:latest run-all /work/my_fastq /work/results/my_run

# try it on the example data first
docker run --rm -it -v "$PWD":/work -v /path/to/databases:/databases \
  ghcr.io/piedna/decodedna:latest example /work/results/example
```

Settings are passed as environment variables with `-e`, for example
`-e DATABASES=mitofish -e MIN_LENGTH=150 -e MAX_LENGTH=350`. Run
`docker run --rm ghcr.io/piedna/decodedna:latest help` for the full list.

`run-all` writes `run_info.txt` into the run folder with every setting, the tool
versions and the NCBI taxonomy snapshot date, for your methods section.

## Not included

- **Dorado basecalling** (`00_basecall_and_demux.sh`) runs best natively with a GPU; use the
  conda install for that step.
- **ONTbarcoder** is a separate desktop GUI (macOS build linked by `install_external_tools.sh`).
