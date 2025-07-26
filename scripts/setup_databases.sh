#!/bin/bash

# DeCodeDNA Database Auto-Detection Script
# Automatically detects USB or local databases and configures environment

echo "🔍 Detecting available databases..."

# Check local databases first (students should build their own)
if [[ -d "../databases/kraken2_db" ]]; then
  echo "💻 Using local databases at: ../databases/"
  echo "✅ Local databases found!"
  echo ""
  echo "🚀 Ready to run pipeline with local databases!"
  return 0
fi

# Check USB second (fallback for students)
for usb_mount in "/Volumes/DeCodeDNA_DB" "/Volumes/DeCodeDNA" "/media/$USER/DeCodeDNA_DB" "/media/$USER/DeCodeDNA" "/mnt/DeCodeDNA_DB" "/mnt/DeCodeDNA"; do
  if [[ -d "$usb_mount/databases/kraken2_db" ]]; then
    export DB_ROOT="$usb_mount/databases/kraken2_db"
    export BLAST_DB_ROOT="$usb_mount/databases/blast_db"
    echo "📱 Found USB databases at: $usb_mount"
    echo "🔧 Environment variables set for this session!"
    echo ""
    echo "Creating .database_config for persistent settings..."
    echo "export DB_ROOT=\"$usb_mount/databases/kraken2_db\"" > .database_config
    echo "export BLAST_DB_ROOT=\"$usb_mount/databases/blast_db\"" >> .database_config
    echo "✅ Database paths configured!"
    echo ""
    echo "🚀 Ready to run pipeline with USB databases!"
    return 0
  fi
done

# No databases found
echo "❌ No databases found!"
echo ""
echo "📋 Recommended approach:"
echo "  1️⃣  Build local databases: bash scripts/01_build_dbs_kraken_blastn.sh"
echo "  2️⃣  Or insert USB drive with pre-built databases"
echo "  3️⃣  Or copy from USB to local: cp -r /Volumes/DeCodeDNA/databases ../"
echo ""
echo "💡 For FHL course: Build local first, USB drives provided as backup"