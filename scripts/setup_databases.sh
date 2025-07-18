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

# 2️⃣ Define possible external locations (Mac, Linux, WSL)
USB_MOUNTS=(
  "/Volumes/DeCodeDNA_DB/databases"
  "/Volumes/DeCodeDNA/databases"
  "/media/$USER/DeCodeDNA_DB/databases"
  "/media/$USER/DeCodeDNA/databases"
  "/mnt/d/databases"
)

# 3️⃣ Check each USB location
for db_root in "${USB_MOUNTS[@]}"; do
  if [[ -d "$db_root/kraken2_db" ]]; then
    export DB_ROOT="$db_root/kraken2_db"
    export BLAST_DB_ROOT="$db_root/blast_db"
    echo "📱 Found external databases at: $db_root"
    echo "🔧 Environment variables set for this session!"
    echo ""
    echo "Creating .database_config for persistent settings..."
    {
      echo "export DB_ROOT=\"$db_root/kraken2_db\""
      echo "export BLAST_DB_ROOT=\"$db_root/blast_db\""
    } > .database_config
    echo "✅ Database paths configured!"
    echo ""
    echo "🚀 Ready to run pipeline with external databases!"
    return 0 2>/dev/null || exit 0
  fi
done

# Check USB second (fallback for students)
#for usb_mount in "/Volumes/DeCodeDNA_DB" "/Volumes/DeCodeDNA" "/media/$USER/DeCodeDNA_DB" "/media/$USER/DeCodeDNA" "/mnt/DeCodeDNA_DB" "/mnt/DeCodeDNA"; do
 # if [[ -d "$usb_mount/databases/kraken2_db" ]]; then
  #  export DB_ROOT="$usb_mount/databases/kraken2_db"
   # export BLAST_DB_ROOT="$usb_mount/databases/blast_db"
    #echo "📱 Found USB databases at: $usb_mount"
    #echo "🔧 Environment variables set for this session!"
    #echo ""
    #echo "Creating .database_config for persistent settings..."
    #echo "export DB_ROOT=\"$usb_mount/databases/kraken2_db\"" > .database_config
    #echo "export BLAST_DB_ROOT=\"$usb_mount/databases/blast_db\"" >> .database_config
    #echo "✅ Database paths configured!"
    #echo ""
    #echo "🚀 Ready to run pipeline with USB databases!"
    #return 0
  #fi
#done

# No databases found
echo "❌ No databases found!"
echo ""
echo "📋 Recommended approach:"
echo "  1️⃣  Build local databases: bash scripts/01_build_dbs_kraken_blastn.sh"
echo "  2️⃣  Or insert USB drive with pre-built databases"
echo "  3️⃣  Or copy from USB to local: cp -r /Volumes/DeCodeDNA/databases ../"
echo ""
echo "💡 For FHL course: Build local first, USB drives provided as backup"
