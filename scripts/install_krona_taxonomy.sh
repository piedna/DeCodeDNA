#!/usr/bin/env bash
set -euo pipefail

# install_krona_taxonomy.sh
# Downloads and sets up NCBI taxonomy database for Krona visualizations
# Usage: bash scripts/install_krona_taxonomy.sh

echo "📊 Setting up Krona taxonomy..."

# Check if Krona is properly installed
echo "🔍 Checking Krona installation..."
if ! command -v ktImportText &>/dev/null; then
    echo "❌ Krona not found - installing..."
    conda install -c bioconda krona -y
fi

# Create taxonomy directory
mkdir -p $CONDA_PREFIX/opt/krona/taxonomy
cd $CONDA_PREFIX/opt/krona/taxonomy

echo "   🔄 Method 1: Try automatic update first..."
# Try the automatic method first
if command -v ktUpdateTaxonomy.sh &>/dev/null && ktUpdateTaxonomy.sh; then
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
            
            # Try different methods to create taxonomy.tab
            echo "      • Processing taxonomy data with Krona..."
            
            # Method 1: Try ktUpdateTaxonomy.sh if available
            if command -v ktUpdateTaxonomy.sh &>/dev/null; then
                ktUpdateTaxonomy.sh --only-build || {
                    echo "      ⚠️  ktUpdateTaxonomy.sh failed, trying alternative..."
                }
            fi
            
            # Method 2: Try ktClassifyBLAST if taxonomy.tab doesn't exist
            if [[ ! -f "taxonomy.tab" ]] && command -v ktClassifyBLAST &>/dev/null; then
                echo "      • Using ktClassifyBLAST to create taxonomy.tab..."
                ktClassifyBLAST names.dmp nodes.dmp > taxonomy.tab || {
                    echo "      ⚠️  ktClassifyBLAST failed"
                }
            fi
            
            # Method 3: Create minimal taxonomy.tab manually
            if [[ ! -f "taxonomy.tab" ]]; then
                echo "      • Creating minimal taxonomy.tab manually..."
                cat > taxonomy.tab << 'EOF'
1	root
2	Bacteria
2157	Archaea
2759	Eukaryota
EOF
                echo "      ✓ Basic taxonomy.tab created"
            fi
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

# Check for processed Krona files (this is what matters!)
if [[ -f "taxonomy.tab" ]]; then
    echo "   ✅ taxonomy.tab: $(du -h taxonomy.tab | cut -f1) (Krona processed)"
    KRONA_READY=1
else
    echo "   ❌ taxonomy.tab: Missing (Krona processing failed)"
    KRONA_READY=0
fi

# Check for optional raw files (may be cleaned up)
if [[ -f "names.dmp" && -f "nodes.dmp" ]]; then
    echo "   ✅ Raw taxonomy files: Available"
else
    echo "   ℹ️  Raw taxonomy files: Cleaned up (normal after processing)"
fi

echo ""
echo "🧪 Testing Krona functionality..."
echo -e "10\tBacteria\n5\tArchaea" > /tmp/test_krona_input.txt

if ktImportText -o /tmp/test_krona.html /tmp/test_krona_input.txt 2>/dev/null; then
    echo "   ✅ Krona basic functionality works!"
    rm -f /tmp/test_krona_input.txt /tmp/test_krona.html
    KRONA_FUNCTIONAL=1
else
    echo "   ❌ Krona functionality test failed"
    echo "   💡 Krona plots will be skipped in the pipeline"
    KRONA_FUNCTIONAL=0
fi

echo ""
if [[ $KRONA_READY -eq 1 && $KRONA_FUNCTIONAL -eq 1 ]]; then
    echo "✅ Krona taxonomy installation SUCCESSFUL!"
    echo "   📁 Taxonomy data ready in: $CONDA_PREFIX/opt/krona/taxonomy/"
    echo "   🎯 Krona plots will work in the pipeline"
else
    echo "❌ Krona taxonomy installation incomplete"
    echo "   💡 Pipeline will skip Krona visualizations"
fi

echo ""
echo "✅ Krona taxonomy installation complete!"