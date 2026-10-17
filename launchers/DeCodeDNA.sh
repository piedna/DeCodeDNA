#!/usr/bin/env bash
# Linux: run ./DeCodeDNA.sh (or double-click and choose "Run") to start DeCodeDNA.
exec bash "$(dirname "$(readlink -f "$0")")/lib/launcher.sh" "$@"
