# Install system dependencies first (macOS)
echo " Installing system dependencies..."

if brew list libgit2 &>/dev/null; then
  echo "✅ libgit2 already installed"
else
  echo " Installing libgit2..."
  brew install libgit2
fi

# Install LULU package for denoising
echo " Installing LULU R package..."
Rscript -e '
  if (!requireNamespace("devtools", quietly = TRUE)) {
    install.packages("devtools", repos = "https://cloud.r-project.org")
  }
  devtools::install_github("tobiasgf/lulu", upgrade = FALSE)
  
  # Install readr if not already installed
  if (!requireNamespace("readr", quietly = TRUE)) {
    install.packages("readr", repos = "https://cloud.r-project.org")
  }

  # Install tidyr if not already installed
  if (!requireNamespace("tidyr", quietly = TRUE)) {
    install.packages("tidyr", repos = "https://cloud.r-project.org")
  }

  # Install stringr if not already installed
  if (!requireNamespace("stringr", quietly = TRUE)) {
    install.packages("stringr", repos = "https://cloud.r-project.org")
  }

  # Install dplyr if not already installed
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    install.packages("dplyr", repos = "https://cloud.r-project.org")
  }

  # Test installation
  if (requireNamespace("lulu", quietly = TRUE)) {
    cat("✅ LULU installed successfully\n")
  } else {
    cat("❌ LULU installation failed\n")
  }

  # Test installation
  if (requireNamespace("tidyr", quietly = TRUE)) {
    cat("✅ tidyr installed successfully\n")
  } else {
    cat("❌ tidyr installation failed\n")
  }

  # Test installation
  if (requireNamespace("stringr", quietly = TRUE)) {
    cat("✅ stringr installed successfully\n")
  } else {
    cat("❌ stringr installation failed\n")
  }

  # Test installation
  if (requireNamespace("readr", quietly = TRUE)) {
    cat("✅ readr installed successfully\n")
  } else {
    cat("❌ readr installation failed\n")
  }

  if (requireNamespace("dplyr", quietly = TRUE)) {
    cat("✅ dplyr installed successfully\n")
  } else {
    cat("❌ dplyr installation failed\n")
  }
'