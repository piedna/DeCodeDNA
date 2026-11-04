#!/usr/bin/env bash
# scripts/resources.sh
#
# Works out how much of this computer DeCodeDNA can use, so the same scripts run well on a small
# laptop, a big workstation or inside Docker without the user having to choose thread counts.
# Sourced by scripts 02-05 (not run on its own). Works with the old bash 3.2 that ships with macOS.
#
# What it sets (only when the user has not set them already):
#   THREADS            total threads to use. "auto" (default) = all CPU cores but one, so the computer
#                      stays usable. A number keeps that number.
#   PARALLEL_SAMPLES   how many samples step 03 clusters at the same time. "auto" (default) decides
#                      from cores and free memory; 1 = one after another, as before.
#   KRAKEN_MEMORY_MAPPING  "auto" (default) reads a Kraken2 database from disk instead of loading it
#                      into memory when it would not fit comfortably. true/false force it.
#
# Also provides:
#   decodedna_plan_parallel N_ITEMS MIN_THREADS_PER_JOB GB_PER_JOB  -> sets JOBS and JOB_THREADS
#   decodedna_kraken_mmap DB_DIR                                    -> prints true or false

# ---- CPU cores this process may use (respects Docker / cgroup limits and CPU affinity) ----
_decodedna_cpus() {
  local n=""
  n=$(nproc 2>/dev/null) || n=""
  [ -z "$n" ] && n=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || true
  [ -z "$n" ] && n=$(sysctl -n hw.ncpu 2>/dev/null) || true
  [ -z "$n" ] && n=1
  # cgroup v2 CPU quota, e.g. "200000 100000" = 2 CPUs (Docker --cpus=2)
  if [ -r /sys/fs/cgroup/cpu.max ]; then
    local q="" p=""
    read -r q p < /sys/fs/cgroup/cpu.max 2>/dev/null || true
    if [ -n "$q" ] && [ "$q" != "max" ] && [ -n "$p" ] && [ "$p" -gt 0 ] 2>/dev/null; then
      local lim=$(( (q + p - 1) / p ))
      [ "$lim" -ge 1 ] && [ "$lim" -lt "$n" ] && n=$lim
    fi
  fi
  echo "$n"
}

# ---- memory available now, in whole GB (respects Docker / cgroup limits) ----
_decodedna_mem_gb() {
  local kb=""
  if [ -r /proc/meminfo ]; then
    kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    [ -z "$kb" ] && kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo)
    local lim="" cur=0
    if [ -r /sys/fs/cgroup/memory.max ]; then
      lim=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
      cur=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0)
    elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
      lim=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
      cur=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo 0)
    fi
    if [ -n "$lim" ] && [ "$lim" != "max" ] && [ "$lim" -lt 1000000000000000 ] 2>/dev/null; then
      local ckb=$(( (lim - cur) / 1024 ))
      [ "$ckb" -lt "$kb" ] && kb=$ckb
    fi
  elif command -v vm_stat >/dev/null 2>&1; then
    # macOS: free + inactive + speculative pages
    local ps
    ps=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    kb=$(vm_stat | awk -v ps="$ps" '
      /Pages free/ {f=$3} /Pages inactive/ {i=$3} /Pages speculative/ {s=$3}
      END {gsub(/\./,"",f); gsub(/\./,"",i); gsub(/\./,"",s); print int((f+i+s)*ps/1024)}')
  fi
  [ -z "$kb" ] && kb=4194304
  echo $(( kb / 1048576 ))
}

DECODEDNA_CPUS=$(_decodedna_cpus)
DECODEDNA_MEM_GB=$(_decodedna_mem_gb)
[ "$DECODEDNA_MEM_GB" -lt 1 ] 2>/dev/null && DECODEDNA_MEM_GB=1

# ---- THREADS ----
_threads_note="set by you"
if [ -z "${THREADS:-}" ] || [ "${THREADS:-}" = "auto" ]; then
  if [ "$DECODEDNA_CPUS" -le 2 ]; then THREADS=$DECODEDNA_CPUS; else THREADS=$(( DECODEDNA_CPUS - 1 )); fi
  _threads_note="auto: $DECODEDNA_CPUS cores found"
  [ "$DECODEDNA_CPUS" -gt 2 ] && _threads_note="$_threads_note, 1 left free"
fi
case "$THREADS" in ''|*[!0-9]*) echo "❌ THREADS must be a number or 'auto' (got '$THREADS')"; exit 1;; esac
[ "$THREADS" -lt 1 ] && THREADS=1
export THREADS
PARALLEL_SAMPLES="${PARALLEL_SAMPLES:-auto}"
KRAKEN_MEMORY_MAPPING="${KRAKEN_MEMORY_MAPPING:-auto}"
export PARALLEL_SAMPLES KRAKEN_MEMORY_MAPPING

echo " Computer:         $DECODEDNA_CPUS CPU cores, about $DECODEDNA_MEM_GB GB memory free"
echo " Threads:          $THREADS ($_threads_note)"

# decodedna_plan_parallel N_ITEMS MIN_THREADS_PER_JOB GB_PER_JOB
# Splits THREADS over several jobs at once when there is room. Sets JOBS and JOB_THREADS.
decodedna_plan_parallel() {
  local n=$1 minthr=${2:-4} gb=${3:-2}
  [ "$n" -lt 1 ] && n=1
  local ps="${PARALLEL_SAMPLES:-auto}"
  if [ "$ps" = "auto" ]; then
    JOBS=$(( THREADS / minthr ))
    local bymem=$(( DECODEDNA_MEM_GB / gb ))
    [ "$bymem" -lt "$JOBS" ] && JOBS=$bymem
  else
    case "$ps" in ''|*[!0-9]*) echo "❌ PARALLEL_SAMPLES must be a number or 'auto'"; exit 1;; esac
    JOBS=$ps
  fi
  [ "$JOBS" -gt "$n" ] && JOBS=$n
  [ "$JOBS" -gt "$THREADS" ] && JOBS=$THREADS
  [ "$JOBS" -lt 1 ] && JOBS=1
  JOB_THREADS=$(( THREADS / JOBS ))
  [ "$JOB_THREADS" -lt 1 ] && JOB_THREADS=1
  return 0
}

# decodedna_kraken_mmap DB_DIR : true if the database should be read from disk (memory mapping)
decodedna_kraken_mmap() {
  case "${KRAKEN_MEMORY_MAPPING:-auto}" in
    true|false) echo "${KRAKEN_MEMORY_MAPPING}"; return;;
  esac
  local f="$1/hash.k2d" bytes gb
  [ -f "$f" ] || { echo false; return; }
  bytes=$(wc -c < "$f" | tr -d ' ')
  gb=$(( bytes / 1073741824 + 1 ))
  # load into memory only if it uses at most about 60% of the free memory
  if [ $(( gb * 10 )) -gt $(( DECODEDNA_MEM_GB * 6 )) ]; then echo true; else echo false; fi
}

# decodedna_wait_for_slot JOBS : waits until fewer than JOBS background jobs are running (bash 3.2 safe)
decodedna_wait_for_slot() {
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$1" ]; do sleep 1; done
}
