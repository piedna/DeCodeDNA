# Getting a DOI for DeCodeDNA via Zenodo

A DOI (Digital Object Identifier) makes your repo *formally citable* in journal articles. It's a permanent link that won't break if you rename the repo. Zenodo (run by CERN) gives you one for free, in about 5 minutes.

## Why bother

- Journals require DOIs in reference lists; a bare GitHub URL is not always accepted.
- Each GitHub *release* gets its own DOI plus a "concept DOI" that always points to the latest version.
- Once minted, your work is archived permanently — even if GitHub disappears.

## Step-by-step (one-time setup, ~5 min)

1. **Go to https://zenodo.org** and click **Sign up with GitHub** (top right). Authorize the OAuth prompt.
2. On Zenodo, click your profile (top right) → **GitHub**. You'll see a list of all your GitHub repos.
3. Find **`piedna/DeCodeDNA`** in the list and flip the toggle to **ON**. That's it — Zenodo is now watching the repo.
4. Go back to GitHub → your repo → **Releases** (right sidebar) → **Create a new release**.
   - Tag: `v0.1.0`
   - Title: `DeCodeDNA v0.1.0 — initial public release`
   - Description: short summary of what's in this version.
   - Click **Publish release**.
5. Wait ~1 minute. Zenodo automatically archives the release and mints a DOI.
6. Go back to Zenodo → GitHub page → click your repo → you'll see a DOI badge like:
   `10.5281/zenodo.1234567`
7. Copy the **Markdown badge** Zenodo provides and paste it at the top of `README.md`. Update `CITATION.cff` with the DOI:
   ```yaml
   identifiers:
     - type: doi
       value: 10.5281/zenodo.1234567
   ```

## After setup

Every time you publish a new GitHub release, Zenodo auto-archives it and mints a new version-specific DOI. The "concept DOI" (e.g. `10.5281/zenodo.1234566`) always resolves to the latest version, which is what you cite in papers.

## What citers will see

Once you have a DOI, your citation becomes:

> Aden, [Last Name]. (2025). *DeCodeDNA: Oxford Nanopore eDNA Metabarcoding Pipeline* (v0.1.0). Zenodo. https://doi.org/10.5281/zenodo.XXXXXXX

That's the version journals will accept without complaint.

## Difficulty

Easy. The only thing that ever trips people up is forgetting to flip the toggle in step 3 *before* creating the release — Zenodo only catches releases made after the toggle is on. If you already created a release, just edit it (or cut a new tag `v0.1.1`) and Zenodo will pick it up.
