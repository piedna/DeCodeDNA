# DeCodeDNA app: install and start

DeCodeDNA runs in your web browser. Behind the scenes everything runs in
Docker, so it works the same on macOS, Windows and Linux.

## 1. Install Docker (once)

| Your computer | Install |
|---|---|
| macOS (Intel or Apple Silicon) | [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) |
| Windows 10/11 | [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) (choose the WSL 2 option) |
| Linux | [Docker Engine](https://docs.docker.com/engine/install/), then `sudo usermod -aG docker $USER` and log in again |

Start Docker Desktop once and wait until it says it is running. Under
**Settings → Resources → Memory**, give it at least 8 GB (16 GB is better).

## 2. Start DeCodeDNA

Download `DeCodeDNA-launchers.zip` from the
[latest release](https://github.com/piedna/DeCodeDNA/releases/latest), unzip it, and:

| Your computer | Double-click |
|---|---|
| macOS | `DeCodeDNA.command`. The first time, **right-click → Open** and confirm. |
| Windows | `DeCodeDNA.bat` |
| Linux | `DeCodeDNA.sh` (or run `./DeCodeDNA.sh` in a terminal) |

The first time it asks for two folders:

1. **Workspace**: where your FASTQ/FASTA folders are. Results go into `results/` inside it.
2. **Database folder**: contains `kraken2_db/` and `blast_db/`. No databases yet?
   Pick an empty folder with ~200 GB free and build them from the app (step 1).

It then downloads the DeCodeDNA image (once, a few GB) and opens the app in your browser.
Keep the launcher window open while you work; press **Enter** there, or **Quit** in the app, to stop.

Next time it remembers your folders and offers **Change folders**.

## The five steps in the app

1. **Databases**: check what is installed, pick 12S / COI / MitoFish, set CPU threads and low-memory mode, or build the databases.
2. **Quality & quick look**: choose your input folder and a run name, pick a filtering preset, start. Tick
   *Continue automatically through steps 3–5* to run the whole pipeline in one go.
3. **Consensus**: vsearch clustering (similarity threshold).
4. **Denoise**: LULU curation.
5. **Taxonomy & results**: BLAST + TaxonKit + Kraken2, then a species × sample table, Krona plots and links to every result file.

Each run keeps `run_info.txt` (all settings and tool versions) and `gui_history.jsonl` for your methods section.

## Troubleshooting

- **"Docker is not running"**: start Docker Desktop and wait for it to finish starting, then try again.
- **Docker asks to share a folder**: allow it. DeCodeDNA can only see the two folders you chose.
- **Slow Kraken2 / out of memory**: give Docker more memory, or leave *Low-memory mode* on *Automatic* in step 1.
- **Use another image or version**: set `DECODEDNA_IMAGE`, e.g. `DECODEDNA_IMAGE=ghcr.io/piedna/decodedna:0.2.0 ./DeCodeDNA.sh`.
- **Stop from a terminal**: `./DeCodeDNA.sh --stop` (Windows: `DeCodeDNA.bat -Stop`).
