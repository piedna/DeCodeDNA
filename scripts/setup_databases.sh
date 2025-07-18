#!/bin/bash

# DeCodeDNA Database Auto-Detection Script
# Automatically detects USB or local databases and configures environment

echo "🔍 Detecting available databases..."

# Check USB first (common mount points across OS)
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

# Check local databases
if [[ -d "../databases/kraken2_db" ]]; then
  echo "💻 Using local databases"
  echo "✅ Local databases found at: ../databases/"
  echo ""
  echo "🚀 Ready to run pipeline with local databases!"
else
  echo "❌ No databases found!"
  echo ""
  echo "📋 Please choose one option:"
  echo "  1️⃣  Insert USB drive with pre-built databases"
  echo "  2️⃣  Build databases locally: bash scripts/01_build_dbs_kraken_blastn.sh"
  echo "  3️⃣  Copy from USB to local: cp -r /Volumes/DeCodeDNA_DB/databases ../"
  echo ""
  echo "💡 For FHL course: USB drives with 158GB databases are provided"
fi