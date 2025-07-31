#!/bin/bash

# ─── DeCodeDNA External Tools Installer ────────────────────────────────────
# Installs external tools not available through conda
# Usage: bash scripts/install_external_tools.sh
# ───────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$PROJECT_ROOT/../tools"

echo " Installing External Tools for DeCodeDNA..."
echo " Creating tools directory at: $TOOLS_DIR"
echo ""

# Create tools directory
mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"

# A) amplicon_sorter (auto-install)
echo " Installing amplicon_sorter..."
if command -v amplicon_sorter >/dev/null 2>&1; then
    echo "✅ amplicon_sorter already installed"
else
    git clone https://github.com/avierstr/amplicon_sorter.git
    cp amplicon_sorter/amplicon_sorter.py "$CONDA_PREFIX/bin/amplicon_sorter"
    chmod +x "$CONDA_PREFIX/bin/amplicon_sorter"
    echo "✅ amplicon_sorter installed successfully"
fi
echo ""

# B) ONTbarcoder2.3 (auto-download)
echo " Downloading ONTbarcoder2.3..."
if [[ -d "ONTbarcoder2.3.app" ]]; then
    echo "✅ ONTbarcoder2.3 already downloaded"
else
    curl -L -o ONTbarcoder2.3.zip "https://github.com/asrivathsan/ONTbarcoder/releases/download/2.3.0/ONTbarcoder2.3.0_OSX.zip"
    unzip ONTbarcoder2.3.zip
    rm ONTbarcoder2.3.zip
    echo "✅ ONTbarcoder2.3 downloaded successfully"
fi
echo "   Location: $TOOLS_DIR/ONTbarcoder2.3.app"
echo ""

# C) Dorado (manual instructions)
echo " Manual Installation Required:"
echo " Please download Dorado from: https://github.com/nanoporetech/dorado/releases"
echo " Choose the appropriate installer for your system:"
echo "   • macOS Apple Silicon: dorado-X.X.X-osx-arm64.zip"
echo "   • macOS Intel: dorado-X.X.X-osx-x64.zip"
echo "   • Linux x64: dorado-X.X.X-linux-x64.tar.gz"
echo "   • Linux ARM64: dorado-X.X.X-linux-arm64.tar.gz"
echo "   • Windows: dorado-X.X.X-win64.zip"
echo ""
echo " After downloading, extract to $TOOLS_DIR/ and follow GitHub instructions"
echo ""

# Verification
echo " Verifying installations..."
if command -v amplicon_sorter >/dev/null 2>&1; then
    echo "✅ amplicon_sorter: Found"
else
    echo "❌ amplicon_sorter: Not found"
fi

if command -v dorado >/dev/null 2>&1; then
    echo "✅ dorado: Found"
else
    echo "❌ dorado: Not found (manual installation required)"
fi

echo ""
echo "✅ External tools setup complete!"
echo " Note: Dorado is only needed for basecalling (Script 00)"
echo "   You can run the main pipeline (Scripts 02-05) without it"