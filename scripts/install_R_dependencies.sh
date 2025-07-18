#!/usr/bin/env bash
# scripts/install_R_dependencies.sh
# Cross-platform R dependencies installer
echo "📦 Installing R dependencies..."
# Detect operating system
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    OS="windows"
else
    OS="unknown"
fi
echo "🔍 Detected OS: $OS"
# Install system dependencies based on OS
case "$OS" in
    "macos")
        echo "📦 Installing macOS dependencies..."
        if command -v brew &>/dev/null; then
            if brew list libgit2 &>/dev/null; then
                echo "✅ libgit2 already installed"
            else
                echo "📦 Installing libgit2..."
                brew install libgit2
            fi
        else
            echo "⚠️  Homebrew not found - some packages may fail to install"
            echo "   Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        fi
        ;;

    "linux")
        echo "📦 Installing Linux dependencies..."

        # Detect package manager
        if command -v apt-get &>/dev/null; then
            echo "📦 Using apt-get (Ubuntu/Debian)..."
            sudo apt-get update
            sudo apt-get install -y r-base r-base-dev libcurl4-openssl-dev libssl-dev libxml2-dev libgit2-dev
        elif command -v yum &>/dev/null; then
            echo "📦 Using yum (CentOS/RHEL)..."
            sudo yum install -y R R-devel curl-devel openssl-devel libxml2-devel libgit2-devel
        elif command -v dnf &>/dev/null; then
            echo "📦 Using dnf (Fedora)..."
            sudo dnf install -y R R-devel libcurl-devel openssl-devel libxml2-devel libgit2-devel
        else
            echo "❌ No supported package manager found"
            echo "   Please install R manually and continue"
        fi
        ;;

    "windows")
        echo "⚠️  Windows detected - please install R manually:"
        echo "   1. Download R from: https://cran.r-project.org/bin/windows/base/"
        echo "   2. Install Rtools: https://cran.r-project.org/bin/windows/Rtools/"
        echo "   3. Restart your terminal and re-run this script"
        ;;

    *)
        echo "⚠️  Unknown OS - attempting to continue with R package installation only"
        ;;
esac
# Check if R is available
if ! command -v Rscript &>/dev/null; then
    echo "❌ Error: Rscript not found"
    echo "   Please install R for your system:"
    echo "   • macOS: brew install r"
    echo "   • Ubuntu/Debian: sudo apt-get install r-base"
    echo "   • CentOS/RHEL: sudo yum install R"
    echo "   • Windows: Download from https://cran.r-project.org/"
    exit 1
fi
echo "✅ R found: $(which Rscript)"
# Install R packages (same for all platforms)
echo "📦 Installing R packages..."
Rscript -e '
  # Set CRAN mirror
  options(repos = c(CRAN = "https://cloud.r-project.org"))

  # Install devtools if needed
  if (!requireNamespace("devtools", quietly = TRUE)) {
    cat("📦 Installing devtools...\n")
    install.packages("devtools")
  }

  # Install required packages
  packages <- c("dplyr", "tidyr", "readr", "stringr")
  for (pkg in packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      cat("📦 Installing", pkg, "...\n")
      install.packages(pkg)
    }
  }

  # Install LULU from GitHub
  cat("📦 Installing LULU from GitHub...\n")
  devtools::install_github("tobiasgf/lulu", upgrade = FALSE)

  # Test installations
  cat("\n🧪 Testing installations...\n")
  test_packages <- c("lulu", "dplyr", "tidyr", "readr", "stringr")
  for (pkg in test_packages) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      cat("✅", pkg, "installed successfully\n")
    } else {
      cat("❌", pkg, "installation failed\n")
    }
  }
'
echo "✅ R dependencies installation complete!"