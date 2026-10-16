#!/usr/bin/env bash
# DeCodeDNA launcher for macOS and Linux.
# Starts the DeCodeDNA container with your workspace + database folders and
# opens the interface in your browser. Used by DeCodeDNA.command / DeCodeDNA.sh.
#
# Options:  --change-folders   pick the workspace / database folders again
#           --stop             stop a running DeCodeDNA
# Env:      DECODEDNA_IMAGE    image to run (default ghcr.io/piedna/decodedna:latest)
set -uo pipefail

IMAGE="${DECODEDNA_IMAGE:-ghcr.io/piedna/decodedna:latest}"
NAME="decodedna-gui"
CONFIG_DIR="$HOME/.decodedna"
CONFIG="$CONFIG_DIR/launcher.conf"
OS="$(uname -s)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." 2>/dev/null && pwd)"

# ─── dialogs (native when available, terminal otherwise) ────────────────────
osa_quote() { local s="${1//\\/\\\\}"; printf '"%s"' "${s//\"/\\\"}"; }

info() {
  echo "$1"
  if [[ "$OS" == Darwin ]]; then
    osascript -e "display dialog $(osa_quote "$1") with title \"DeCodeDNA\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1
  elif command -v zenity >/dev/null 2>&1; then
    zenity --info --title=DeCodeDNA --width=420 --text="$1" 2>/dev/null
  elif command -v kdialog >/dev/null 2>&1; then
    kdialog --title DeCodeDNA --msgbox "$1" 2>/dev/null
  fi
}

fail() {
  info "$1"
  [[ -t 0 ]] && read -r -p "Press Enter to close." _
  exit 1
}

# ask_choice "question" "default button" "other button" → prints the chosen label
ask_choice() {
  local q="$1" a="$2" b="$3" out
  if [[ "$OS" == Darwin ]]; then
    out=$(osascript -e "button returned of (display dialog $(osa_quote "$q") with title \"DeCodeDNA\" buttons {$(osa_quote "$b"), $(osa_quote "$a")} default button $(osa_quote "$a") giving up after 30)" 2>/dev/null)
    [[ -z "$out" ]] && out="$a"
    echo "$out"
  elif command -v zenity >/dev/null 2>&1; then
    if zenity --question --title=DeCodeDNA --width=420 --text="$q" --ok-label="$a" --cancel-label="$b" 2>/dev/null; then echo "$a"; else echo "$b"; fi
  elif command -v kdialog >/dev/null 2>&1; then
    if kdialog --title DeCodeDNA --yes-label "$a" --no-label "$b" --yesno "$q" 2>/dev/null; then echo "$a"; else echo "$b"; fi
  else
    local r
    read -r -p "$q [Enter = $a, c = $b] " r
    if [[ "$r" == c* || "$r" == C* ]]; then echo "$b"; else echo "$a"; fi
  fi
}

# choose_folder "prompt" → prints an absolute folder path (empty if cancelled)
choose_folder() {
  local prompt="$1" out=""
  if [[ "$OS" == Darwin ]]; then
    out=$(osascript -e "POSIX path of (choose folder with prompt $(osa_quote "$prompt"))" 2>/dev/null)
  elif command -v zenity >/dev/null 2>&1; then
    out=$(zenity --file-selection --directory --title="$prompt" 2>/dev/null)
  elif command -v kdialog >/dev/null 2>&1; then
    out=$(kdialog --title "$prompt" --getexistingdirectory "$HOME" 2>/dev/null)
  else
    echo "$prompt" >&2
    read -r -p "Folder path: " out
    out="${out/#\~/$HOME}"
  fi
  out="${out%/}"
  [[ -n "$out" && -d "$out" ]] && (cd "$out" && pwd)
}

open_url() {
  if [[ "$OS" == Darwin ]]; then open "$1"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1 &
  else echo "Open this address in your browser: $1"
  fi
}

# ─── docker ─────────────────────────────────────────────────────────────────
ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    local url="https://docs.docker.com/get-started/get-docker/"
    info "DeCodeDNA needs Docker, which is not installed.

The Docker download page will open now. Install Docker Desktop (or Docker Engine on Linux), start it once, then open DeCodeDNA again."
    open_url "$url"
    exit 1
  fi
  if docker info >/dev/null 2>&1; then return; fi

  if [[ "$OS" == Darwin ]]; then
    echo "Starting Docker Desktop…"
    open -a Docker 2>/dev/null || true
  elif docker info 2>&1 | grep -qi "permission denied"; then
    fail "Docker is installed but your user may not use it.

Run this once in a terminal, then log out and back in:
  sudo usermod -aG docker \$USER"
  else
    echo "Waiting for Docker to start (on Linux: sudo systemctl start docker)…"
  fi
  local i
  for i in $(seq 1 90); do
    docker info >/dev/null 2>&1 && return
    sleep 2
  done
  fail "Docker is not running. Start Docker Desktop (or the Docker service), wait until it says it is running, then open DeCodeDNA again."
}

ensure_image() {
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then return; fi
  echo "Downloading DeCodeDNA ($IMAGE). This happens once and can take a few minutes…"
  if docker pull "$IMAGE"; then return; fi
  if [[ -f "$REPO_ROOT/docker/Dockerfile" ]]; then
    local c
    c=$(ask_choice "Could not download $IMAGE.

Build it from this copy of the DeCodeDNA repository instead? This takes about 10–20 minutes." "Build" "Cancel")
    if [[ "$c" == Build ]]; then
      docker build -f "$REPO_ROOT/docker/Dockerfile" -t "$IMAGE" "$REPO_ROOT" && return
      fail "Building the DeCodeDNA image failed. See the messages in this window."
    fi
  fi
  fail "Could not download the DeCodeDNA image ($IMAGE). Check your internet connection and try again."
}

container_port() {
  docker port "$NAME" 8080/tcp 2>/dev/null | head -1 | awk -F: '{print $NF}'
}

container_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" == true ]]
}

# ─── folders ────────────────────────────────────────────────────────────────
WORKSPACE=""
DATABASES=""

load_config() {
  [[ -f "$CONFIG" ]] || return 1
  # shellcheck disable=SC1090
  source "$CONFIG"
  [[ -d "$WORKSPACE" && -d "$DATABASES" ]]
}

pick_folders() {
  info "Choose your DeCodeDNA workspace folder.

Put your FASTQ/FASTA folders here; results are saved in a 'results' folder inside it."
  WORKSPACE=$(choose_folder "Choose your DeCodeDNA workspace folder")
  [[ -n "$WORKSPACE" ]] || fail "No workspace folder chosen."

  info "Now choose your reference database folder (the one that contains 'kraken2_db' and 'blast_db').

No databases yet? Choose an empty folder with ~200 GB free; you can build them from the app."
  DATABASES=$(choose_folder "Choose the DeCodeDNA database folder")
  [[ -n "$DATABASES" ]] || fail "No database folder chosen."

  mkdir -p "$CONFIG_DIR"
  printf 'WORKSPACE=%q\nDATABASES=%q\n' "$WORKSPACE" "$DATABASES" > "$CONFIG"
}

# ─── main ───────────────────────────────────────────────────────────────────
main() {
  echo "DeCodeDNA launcher"
  echo "──────────────────"
  ensure_docker

  if [[ "${1:-}" == "--stop" ]]; then
    docker stop "$NAME" >/dev/null 2>&1 && echo "DeCodeDNA stopped." || echo "DeCodeDNA was not running."
    exit 0
  fi

  if container_running; then
    local port; port=$(container_port)
    echo "DeCodeDNA is already running."
    open_url "http://localhost:$port"
    exit 0
  fi
  docker rm -f "$NAME" >/dev/null 2>&1 || true

  if [[ "${1:-}" == "--change-folders" ]] || ! load_config; then
    pick_folders
  else
    local c
    c=$(ask_choice "Start DeCodeDNA with these folders?

Workspace:  $WORKSPACE
Databases:  $DATABASES" "Start" "Change folders")
    [[ "$c" == "Change folders" ]] && pick_folders
  fi

  ensure_image

  local mem
  mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
  if [[ "$mem" =~ ^[0-9]+$ && "$mem" -gt 0 && "$mem" -lt 7500000000 ]]; then
    echo "Note: Docker may use only $((mem / 1024 / 1024 / 1024)) GB of memory. DeCodeDNA will read databases from disk (slower)."
    echo "      To give it more: Docker Desktop → Settings → Resources → Memory."
  fi

  local user_args=()
  if [[ "$OS" == Linux ]]; then user_args=(--user "$(id -u):$(id -g)"); fi

  echo "Starting DeCodeDNA…"
  if ! docker run -d --rm --name "$NAME" \
      -p 127.0.0.1:0:8080 \
      -v "$WORKSPACE":/work \
      -v "$DATABASES":/databases \
      -e HOST_WORKSPACE="$WORKSPACE" \
      -e HOST_DATABASES="$DATABASES" \
      ${user_args[@]+"${user_args[@]}"} \
      "$IMAGE" gui >/dev/null; then
    fail "DeCodeDNA could not start. If Docker asks for permission to share these folders, allow it and try again."
  fi

  local port="" i
  for i in $(seq 1 60); do
    port=$(container_port)
    if [[ -n "$port" ]] && curl -fs "http://127.0.0.1:$port/api/state" >/dev/null 2>&1; then break; fi
    container_running || { docker logs "$NAME" 2>&1 | tail -20; fail "DeCodeDNA stopped while starting. See the messages in this window."; }
    sleep 1
  done
  [[ -n "$port" ]] || fail "DeCodeDNA did not start in time."

  local url="http://localhost:$port"
  open_url "$url"
  echo
  echo "✅ DeCodeDNA is running at $url"
  echo "   Workspace: $WORKSPACE"
  echo "   Databases: $DATABASES"
  echo
  echo "Keep this window open while you work. Press Enter here (or Quit in the app) to stop DeCodeDNA."
  while container_running; do
    if [[ ! -t 0 ]]; then sleep 2; continue; fi
    if read -r -t 2 _ 2>/dev/null; then
      echo "Stopping DeCodeDNA…"
      docker stop "$NAME" >/dev/null 2>&1
      break
    fi
  done
  echo "DeCodeDNA has stopped. You can close this window."
}

main "$@"
