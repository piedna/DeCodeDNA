#!/bin/bash
# Script to convert EFPQ bases that were converted by ONTBarcoder

# Process all .fa files
for i in *.fa; do
    # Check if file exists (handles case where no .fa files exist)
    if [[ -f "$i" ]]; then
        echo "Processing: $i"
        sed -i.bak \
            -e '/^>/!{s/E/A/g; s/F/G/g; s/Q/C/g; s/P/T/g;}' \
            "$i"
        echo "Completed: $i"
    fi
done