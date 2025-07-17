#!/usr/bin/env bash
set -euo pipefail

# install_krona_taxonomy.sh
# Downloads and sets up NCBI taxonomy database for Krona visualizations
# Usage: bash scripts/install_krona_taxonomy.sh

echo "📊 Setting up Krona taxonomy..."

# Create taxonomy directory
mkdir -p $CONDA_PREFIX/opt/krona/taxonomy
cd $CONDA_PREFIX/opt/krona/taxonomy

echo "   🔄 Method 1: Try automatic update first..."
# Try the automatic method first
if ktUpdateTaxonomy.sh; then
    echo "   ✅ Automatic taxonomy update successful!"
else
    echo "   ⚠️  Automatic update failed, using manual method..."
    
    echo "   📥 Method 2: Manual download and setup..."
    
    # Download taxonomy dump manually using HTTPS (more reliable than FTP)
    echo "      • Downloading taxdump.tar.gz from NCBI..."
    if curl -L -o taxdump.tar.gz "https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz"; then
        echo "      ✅ Download successful ($(du -h taxdump.tar.gz | cut -f1))"
        
        # Extract the taxonomy files
        echo "      • Extracting taxonomy files..."
        tar -xzf taxdump.tar.gz
        
        # Verify key files were extracted
        if [[ -f "names.dmp" && -f "nodes.dmp" ]]; then
            echo "      ✅ Extraction successful"
            
            # Now run ktUpdateTaxonomy.sh to process the extracted files
            echo "      • Processing taxonomy data with Krona..."
            ktUpdateTaxonomy.sh --only-build || {
                echo "      ⚠️  Processing failed, but basic files are available"
            }
        else
            echo "      ❌ Extraction failed - key files missing"
            ls -la
        fi
    else
        echo "      ❌ Download failed"
        echo "      💡 Manual fallback: Download from https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz"
        echo "         and extract to: $CONDA_PREFIX/opt/krona/taxonomy/"
    fi
fi

# Verify the final setup
echo ""
echo "🔍 Verifying Krona taxonomy setup..."
ls -la

# Check for required files
required_files=("names.dmp" "nodes.dmp")
missing_files=()

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "   ✅ $file: $(du -h "$file" | cut -f1)"
    else
        echo "   ❌ $file: Missing"
        missing_files+=("$file")
    fi
done

# Check for processed Krona files
if [[ -f "taxonomy.tab" ]]; then
    echo "   ✅ taxonomy.tab: $(du -h taxonomy.tab | cut -f1) (Krona processed)"
else
    echo "   ⚠️  taxonomy.tab: Missing (Krona processing incomplete)"
fi

if [[ ${#missing_files[@]} -eq 0 ]]; then
    echo ""
    echo "   ✅ Krona taxonomy setup complete!"
    echo "   📁 Taxonomy files ready in: $CONDA_PREFIX/opt/krona/taxonomy/"
else
    echo ""
    echo "   ⚠️  Setup partially complete - missing: ${missing_files[*]}"
    echo "   💡 Krona plots may still work with available files"
fi

echo ""
echo "🧪 Testing Krona functionality..."
echo -e "10\tBacteria\n5\tArchaea" > /tmp/test_krona_input.txt

if ktImportText -o /tmp/test_krona.html /tmp/test_krona_input.txt 2>/dev/null; then
    echo "   ✅ Krona basic functionality works!"
    rm -f /tmp/test_krona_input.txt /tmp/test_krona.html
else
    echo "   ❌ Krona functionality test failed"
    echo "   💡 Krona plots will be skipped in the pipeline"
fi

echo ""
echo "✅ Krona taxonomy installation complete!"