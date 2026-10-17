#!/bin/bash
# macOS: double-click to start DeCodeDNA.
# First time: right-click → Open, then confirm (macOS asks once for files downloaded from the internet).
exec /bin/bash "$(dirname "$0")/lib/launcher.sh" "$@"
