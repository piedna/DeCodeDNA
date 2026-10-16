#!/usr/bin/env python3
"""DeCodeDNA browser interface.

A small web server (Python standard library only) that runs the `decodedna`
pipeline commands as background jobs and serves a single-page UI.

Inside the container:
  /work       the user's workspace (inputs + results), mounted by the launcher
  /databases  the reference database folder, mounted by the launcher

Environment:
  DECODEDNA_WORK     workspace root            (default /work)
  DATABASE_DIR       database root             (default /databases)
  DECODEDNA_ROOT     scripts + example data    (default: parent of this folder)
  DECODEDNA_BIN      pipeline command          (default: decodedna on PATH)
  HOST_WORKSPACE     host path of the workspace, shown to the user
  HOST_DATABASES     host path of the database folder, shown to the user
  DECODEDNA_PORT     port to listen on         (default 8080)
"""

import csv
import datetime as dt
import json
import mimetypes
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATIC = HERE / "static"
ROOT = Path(os.environ.get("DECODEDNA_ROOT", HERE.parent)).resolve()
WORK = Path(os.environ.get("DECODEDNA_WORK", "/work")).resolve()
DB_DIR = Path(os.environ.get("DATABASE_DIR", "/databases")).resolve()
BIN = os.environ.get("DECODEDNA_BIN") or shutil.which("decodedna") or "decodedna"
HOST_WORK = os.environ.get("HOST_WORKSPACE", "")
HOST_DB = os.environ.get("HOST_DATABASES", "")
PORT = int(os.environ.get("DECODEDNA_PORT", "8080"))

RESULTS = WORK / "results"
STATE_DIR = WORK / ".decodedna"
SETTINGS_FILE = STATE_DIR / "settings.json"
ALL_DATABASES = ["12s", "coi", "mitofish"]

EXAMPLES = [
    {"label": "Example: 12S fish mock (ONT native barcodes)",
     "path": str(ROOT / "workflows" / "ont_native_barcodes"),
     "preset": "default"},
    {"label": "Example: D-loop fish mock (Custom CCI, demultiplexed)",
     "path": str(ROOT / "workflows" / "custom_cci_barcodes" / "02_demultiplexed"),
     "preset": "default"},
]

# step key → (decodedna command, output folder, input folder or None for user input)
STEPS = {
    "qc":        ("qc",        "02_quicklook", None),
    "consensus": ("consensus", "03_consensus", "02_quicklook"),
    "denoise":   ("denoise",   "04_denoise",   "03_consensus"),
    "taxonomy":  ("taxonomy",  "05_taxonomy",  "04_denoise"),
}

# UI parameter → (environment variable, type, min, max)
PARAMS = {
    "quality":          ("QUALITY_THRESHOLD",  int,   0, 60),
    "min_length":       ("MIN_LENGTH",         int,   1, 100000),
    "max_length":       ("MAX_LENGTH",         int,   1, 100000),
    "confidence":       ("CONFIDENCE",         float, 0, 1),
    "similarity":       ("VSEARCH_SIMILARITY", float, 0.5, 1),
    "lulu_max_otus":    ("LULU_MAX_OTUS",      int,   0, 10_000_000),
    "evalue":           ("EVALUE",             float, 0, 10),
    "max_hits":         ("MAX_HITS",           int,   1, 10000),
    "subset_count":     ("SUBSET_COUNT",       int,   0, 10_000_000),
    "skip_kraken":      ("SKIP_KRAKEN",        bool,  None, None),
    "skip_krona":       ("SKIP_KRONA",         bool,  None, None),
}

RUN_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$")
SEQ_EXT = (".fastq", ".fastq.gz", ".fq", ".fq.gz", ".fasta", ".fas", ".fa")


class ApiError(Exception):
    def __init__(self, message, status=HTTPStatus.BAD_REQUEST):
        super().__init__(message)
        self.status = status


# ─── paths ──────────────────────────────────────────────────────────────────

def allowed_roots():
    roots = [("Workspace", WORK)]
    if DB_DIR.exists():
        roots.append(("Databases", DB_DIR))
    roots.append(("Examples", ROOT / "workflows"))
    return roots


def resolve_allowed(path_str):
    """Resolve a path and make sure it lies under one of the allowed roots."""
    p = Path(path_str).resolve()
    for _, root in allowed_roots():
        if p == root or root in p.parents:
            return p
    raise ApiError("That folder is outside the workspace.", HTTPStatus.FORBIDDEN)


def host_path(p):
    """Translate a container path to the path the user sees on their computer."""
    p = Path(p)
    for container_root, host_root in ((WORK, HOST_WORK), (DB_DIR, HOST_DB)):
        if host_root and (p == container_root or container_root in p.parents):
            rel = p.relative_to(container_root)
            sep = "\\" if "\\" in host_root else "/"
            return host_root.rstrip("/\\") + ("" if str(rel) == "." else sep + str(rel).replace("/", sep))
    return str(p)


def file_url(p):
    return "/files/" + urllib.parse.quote(str(Path(p).relative_to(WORK)))


# ─── settings ───────────────────────────────────────────────────────────────

def cpu_count():
    try:
        return len(os.sched_getaffinity(0))
    except AttributeError:
        return os.cpu_count() or 4


def memory_gb():
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return round(int(line.split()[1]) / 1024 / 1024, 1)
    except OSError:
        pass
    try:
        out = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, timeout=5)
        return round(int(out.stdout.strip()) / 1024 ** 3, 1)
    except Exception:
        return None


def kraken_db_gb(databases):
    total = 0
    for db in databases:
        f = DB_DIR / "kraken2_db" / db / "hash.k2d"
        if f.exists():
            total += f.stat().st_size
    return round(total / 1024 ** 3, 1)


def default_settings():
    return {"databases": list(ALL_DATABASES), "threads": cpu_count(), "memory_mapping": None}


def load_settings():
    s = default_settings()
    try:
        s.update(json.loads(SETTINGS_FILE.read_text()))
    except (OSError, ValueError):
        pass
    s["databases"] = [d for d in s.get("databases", []) if d in ALL_DATABASES] or list(ALL_DATABASES)
    return s


def save_settings(new):
    s = load_settings()
    if "databases" in new:
        dbs = [d for d in new["databases"] if d in ALL_DATABASES]
        if not dbs:
            raise ApiError("Select at least one database.")
        s["databases"] = dbs
    if "threads" in new:
        s["threads"] = max(1, min(int(new["threads"]), 256))
    if "memory_mapping" in new:
        s["memory_mapping"] = None if new["memory_mapping"] is None else bool(new["memory_mapping"])
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    SETTINGS_FILE.write_text(json.dumps(s, indent=2))
    return s


def effective_memory_mapping(s):
    """Use memory mapping when the user asked for it, or (by default) when the
    selected Kraken2 databases would not fit comfortably in memory."""
    if s.get("memory_mapping") is not None:
        return s["memory_mapping"]
    mem = memory_gb()
    need = kraken_db_gb(s["databases"])
    return bool(mem and need and need > 0.6 * mem)


# ─── jobs ───────────────────────────────────────────────────────────────────

class Job:
    def __init__(self, action, label, args, env, log_path, run=None):
        self.id = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        self.action = action
        self.label = label
        self.args = args
        self.env = env
        self.log_path = Path(log_path)
        self.run = run
        self.status = "running"
        self.returncode = None
        self.started = time.time()
        self.ended = None
        self.proc = None

    def start(self):
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        log = open(self.log_path, "wb")
        env = dict(os.environ, **self.env)
        self.proc = subprocess.Popen(
            [BIN, *self.args], stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
            env=env, cwd=str(WORK), start_new_session=True)
        threading.Thread(target=self._wait, args=(log,), daemon=True).start()

    def _wait(self, log):
        rc = self.proc.wait()
        log.close()
        self.returncode = rc
        self.ended = time.time()
        if self.status != "cancelled":
            self.status = "succeeded" if rc == 0 else "failed"
        record_history(self)

    def cancel(self):
        if self.status == "running" and self.proc:
            self.status = "cancelled"
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def current_step(self):
        """Last '▶ 0X_...' marker printed by decodedna (useful for run-all)."""
        step = None
        try:
            with open(self.log_path, "rb") as f:
                for line in f:
                    if line.startswith("▶ 0".encode()):
                        step = line.decode(errors="replace").split()[1]
        except OSError:
            pass
        return step

    def to_dict(self):
        return {
            "id": self.id, "action": self.action, "label": self.label, "run": self.run,
            "status": self.status, "returncode": self.returncode,
            "started": self.started, "ended": self.ended,
            "elapsed": round((self.ended or time.time()) - self.started),
            "step": self.current_step(), "log": host_path(self.log_path),
        }


JOB_LOCK = threading.Lock()
CURRENT_JOB = None


def record_history(job):
    if not job.run:
        return
    try:
        with open(RESULTS / job.run / "gui_history.jsonl", "a") as f:
            f.write(json.dumps({
                "action": job.action, "args": job.args, "settings": job.env,
                "status": job.status, "returncode": job.returncode,
                "started": dt.datetime.fromtimestamp(job.started).isoformat(timespec="seconds"),
                "ended": dt.datetime.fromtimestamp(job.ended).isoformat(timespec="seconds"),
            }) + "\n")
    except OSError:
        pass


def job_env(params):
    s = load_settings()
    env = {
        "DATABASES": " ".join(s["databases"]),
        "THREADS": str(s["threads"]),
        "DATABASE_DIR": str(DB_DIR),
        "KRAKEN_MEMORY_MAPPING": "true" if effective_memory_mapping(s) else "false",
    }
    for key, value in (params or {}).items():
        if key not in PARAMS or value in ("", None):
            continue
        var, typ, lo, hi = PARAMS[key]
        if typ is bool:
            env[var] = "true" if value else "false"
            continue
        try:
            v = typ(value)
        except (TypeError, ValueError):
            raise ApiError(f"'{value}' is not a valid value for {key.replace('_', ' ')}.")
        if not (lo <= v <= hi):
            raise ApiError(f"{key.replace('_', ' ')} must be between {lo} and {hi}.")
        env[var] = str(v)
    if "MIN_LENGTH" in env and "MAX_LENGTH" in env and int(env["MIN_LENGTH"]) > int(env["MAX_LENGTH"]):
        raise ApiError("Minimum length must be smaller than maximum length.")
    return env


def start_job(body):
    global CURRENT_JOB
    action = body.get("action")
    params = body.get("params") or {}
    env = job_env(params)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")

    if action == "build_db":
        if not os.access(DB_DIR, os.W_OK):
            raise ApiError("The database folder is not writable. Choose a writable folder in the launcher.")
        job = Job(action, "Build reference databases", ["build-db"], env,
                  STATE_DIR / "logs" / f"build-db_{stamp}.log")
    elif action in STEPS or action == "run_all":
        run = body.get("run", "")
        if not RUN_NAME_RE.match(run):
            raise ApiError("Run names may use letters, numbers, '.', '_' and '-' (no spaces).")
        run_dir = RESULTS / run
        if action in ("qc", "run_all"):
            src = body.get("input", "")
            if not src:
                raise ApiError("Choose an input folder with FASTQ or FASTA files.")
            src_path = resolve_allowed(src)
            if count_seq_files(src_path) == 0:
                raise ApiError("The input folder has no FASTQ/FASTA files (.fastq, .fq, .fasta, .fa, optionally .gz).")
            if action == "run_all":
                args = ["run-all", str(src_path), str(run_dir)]
                label = f"Run all steps → {run}"
            else:
                args = ["qc", str(src_path), str(run_dir / STEPS["qc"][1])]
                label = f"Quality filter + quick look → {run}"
        else:
            cmd, out, inp = STEPS[action]
            if not (run_dir / inp).is_dir():
                raise ApiError(f"Run '{run}' has no {inp} folder yet. Run the previous step first.")
            args = [cmd, str(run_dir / inp), str(run_dir / out)]
            label = {"consensus": "Build consensus", "denoise": "Denoise (LULU)",
                     "taxonomy": "Taxonomy + Krona plots"}[action] + f" → {run}"
        job = Job(action, label, args, env, run_dir / "logs" / f"{action}_{stamp}.log", run=run)
    else:
        raise ApiError("Unknown action.")

    with JOB_LOCK:
        if CURRENT_JOB and CURRENT_JOB.status == "running":
            raise ApiError("Another job is still running. Wait for it to finish or cancel it.", HTTPStatus.CONFLICT)
        job.start()
        CURRENT_JOB = job
    return job.to_dict()


# ─── runs & results ─────────────────────────────────────────────────────────

def count_seq_files(folder):
    try:
        return sum(1 for f in Path(folder).iterdir() if f.is_file() and f.name.lower().endswith(SEQ_EXT))
    except OSError:
        return 0


def step_done(run_dir):
    def any_glob(pattern):
        return any(run_dir.glob(pattern))
    return {
        "qc": any_glob("02_quicklook/*/*_classified.fasta"),
        "consensus": any_glob("03_consensus/vsearch_clustering/*/*_vsearch_consensus.fasta"),
        "denoise": any_glob("04_denoise/*/otu_table_*_lulu_curated.csv"),
        "taxonomy": (run_dir / "05_taxonomy/03_final_taxonomy/TaxonKit_LCA_species_abundance.csv").exists(),
    }


def list_runs():
    runs = []
    if RESULTS.is_dir():
        for d in RESULTS.iterdir():
            if d.is_dir() and RUN_NAME_RE.match(d.name):
                runs.append({"name": d.name, "steps": step_done(d), "modified": d.stat().st_mtime,
                             "host_path": host_path(d)})
    runs.sort(key=lambda r: r["modified"], reverse=True)
    return runs


SAMPLE_SUFFIX = re.compile(r"_(12s|coi|mitofish)_vsearch_consensus\.fasta$")
KRONA_STEP5 = re.compile(r"^vsearch_sample_(.+?)_(12s|coi|mitofish)_vsearch_consensus\.fasta_(12s|coi|mitofish)_krona\.html$")
KRONA_STEP2 = re.compile(r"^(.+)_(12s|coi|mitofish)\.krona\.html$")


def krona_label(name):
    m = KRONA_STEP5.match(name) or KRONA_STEP2.match(name)
    return f"{m.group(1)} ({m.group(2)})" if m else name


def read_table(path, limit=500):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    if not rows:
        return {"columns": [], "rows": [], "total": 0}
    header = [SAMPLE_SUFFIX.sub("", h) for h in rows[0]]
    body = rows[1:]
    def total(r):
        try:
            return sum(float(x) for x in r[1:] if x)
        except ValueError:
            return 0
    body.sort(key=total, reverse=True)
    return {"columns": header, "rows": body[:limit], "total": len(body)}


def run_results(run):
    if not RUN_NAME_RE.match(run or ""):
        raise ApiError("Unknown run.")
    run_dir = RESULTS / run
    if not run_dir.is_dir():
        raise ApiError("Unknown run.", HTTPStatus.NOT_FOUND)
    tax = run_dir / "05_taxonomy"
    final = tax / "03_final_taxonomy"
    species = final / "TaxonKit_LCA_species_abundance.csv"
    files = []
    for label, pattern in [
        ("Species × sample table (TaxonKit LCA)", "05_taxonomy/03_final_taxonomy/TaxonKit_LCA_species_abundance.csv"),
        ("Full OTU annotation table", "05_taxonomy/03_final_taxonomy/Comprehensive_OTU_Database.csv"),
        ("Method comparison", "05_taxonomy/03_final_taxonomy/Comprehensive_Method_Comparison.csv"),
        ("BLAST species table", "05_taxonomy/03_final_taxonomy/BLAST_vsearch_*_classified_species.csv"),
        ("Denoised OTU sequences (FASTA)", "04_denoise/*/otu_representatives_*_vsearch.fasta"),
        ("Curated OTU table (LULU)", "04_denoise/*/otu_table_*_lulu_curated.csv"),
        ("Run settings and tool versions", "run_info.txt"),
    ]:
        for p in sorted(run_dir.glob(pattern)):
            files.append({"label": label, "name": p.name, "url": file_url(p), "host_path": host_path(p)})
    krona = [{"name": krona_label(p.name), "url": file_url(p)}
             for p in sorted((tax / "04_krona_plots").glob("*.html"))]
    quicklook_krona = [{"name": krona_label(p.name), "url": file_url(p)}
                       for p in sorted(run_dir.glob("02_quicklook/*/*.krona.html"))]
    logs = [{"name": p.name, "url": file_url(p)} for p in sorted((run_dir / "logs").glob("*.log"), reverse=True)]
    return {
        "run": run, "host_path": host_path(run_dir), "steps": step_done(run_dir),
        "species": read_table(species) if species.exists() else None,
        "files": files, "krona": krona, "quicklook_krona": quicklook_krona, "logs": logs,
    }


def browse(path):
    p = resolve_allowed(path or str(WORK))
    if not p.is_dir():
        raise ApiError("Not a folder.")
    dirs = []
    try:
        for d in sorted(p.iterdir(), key=lambda x: x.name.lower()):
            if d.is_dir() and not d.name.startswith("."):
                dirs.append({"name": d.name, "path": str(d), "seq_files": count_seq_files(d)})
    except PermissionError:
        raise ApiError("No permission to read that folder.", HTTPStatus.FORBIDDEN)
    parent = None
    try:
        parent = str(resolve_allowed(str(p.parent))) if p.parent != p else None
    except ApiError:
        pass
    return {
        "path": str(p), "host_path": host_path(p), "parent": parent, "dirs": dirs,
        "seq_files": count_seq_files(p),
        "roots": [{"label": label, "path": str(r)} for label, r in allowed_roots()],
    }


def check_status():
    s = load_settings()
    env = dict(os.environ, DATABASES=" ".join(ALL_DATABASES), DATABASE_DIR=str(DB_DIR))
    out = subprocess.run([BIN, "check", "--json"], capture_output=True, text=True,
                         stdin=subprocess.DEVNULL, env=env, timeout=120)
    try:
        data = json.loads(out.stdout)
    except ValueError:
        raise ApiError("Could not run the installation check:\n" + (out.stderr or out.stdout)[-2000:],
                       HTTPStatus.INTERNAL_SERVER_ERROR)
    data["selected"] = s["databases"]
    data["database_dir_host"] = HOST_DB or str(DB_DIR)
    data["writable"] = os.access(DB_DIR, os.W_OK)
    return data


def state():
    s = load_settings()
    return {
        "workspace": {"path": str(WORK), "host_path": HOST_WORK or str(WORK)},
        "database_dir": {"path": str(DB_DIR), "host_path": HOST_DB or str(DB_DIR), "exists": DB_DIR.exists()},
        "settings": s,
        "memory_gb": memory_gb(),
        "kraken_db_gb": kraken_db_gb(s["databases"]),
        "memory_mapping_effective": effective_memory_mapping(s),
        "cpus": cpu_count(),
        "examples": EXAMPLES,
        "job": CURRENT_JOB.to_dict() if CURRENT_JOB else None,
        "default_run_name": "run_" + dt.datetime.now().strftime("%Y-%m-%d_%H%M"),
    }


# ─── HTTP ───────────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    server_version = "DeCodeDNA"

    def log_message(self, fmt, *args):
        if os.environ.get("DECODEDNA_GUI_DEBUG"):
            super().log_message(fmt, *args)

    def send_json(self, data, status=HTTPStatus.OK):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path, content_type=None):
        ctype = content_type or mimetypes.guess_type(str(path))[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype in ("application/json", "application/javascript"):
            ctype += "; charset=utf-8"
        size = path.stat().st_size
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with open(path, "rb") as f:
            shutil.copyfileobj(f, self.wfile)

    def read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > 1_000_000:
            raise ApiError("Request too large.")
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            raise ApiError("Invalid JSON.")

    def handle_errors(fn):
        def wrapper(self):
            try:
                fn(self)
            except ApiError as e:
                self.send_json({"error": str(e)}, e.status)
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception as e:  # pragma: no cover - last-resort error report
                self.send_json({"error": f"Internal error: {e}"}, HTTPStatus.INTERNAL_SERVER_ERROR)
        return wrapper

    @handle_errors
    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(url.query)
        arg = lambda k, d="": q.get(k, [d])[0]

        if url.path in ("/", "/index.html"):
            return self.send_file(STATIC / "index.html")
        if url.path.startswith("/static/"):
            p = (STATIC / url.path[len("/static/"):]).resolve()
            if STATIC not in p.parents or not p.is_file():
                raise ApiError("Not found.", HTTPStatus.NOT_FOUND)
            return self.send_file(p)
        if url.path.startswith("/files/"):
            rel = urllib.parse.unquote(url.path[len("/files/"):])
            p = (WORK / rel).resolve()
            if WORK not in p.parents or not p.is_file():
                raise ApiError("Not found.", HTTPStatus.NOT_FOUND)
            ctype = "text/plain" if p.suffix in (".log", ".txt", ".tsv", ".out", ".fasta", ".fa") else None
            return self.send_file(p, ctype)
        if url.path == "/api/state":
            return self.send_json(state())
        if url.path == "/api/check":
            return self.send_json(check_status())
        if url.path == "/api/browse":
            return self.send_json(browse(arg("path")))
        if url.path == "/api/runs":
            return self.send_json(list_runs())
        if url.path == "/api/results":
            return self.send_json(run_results(arg("run")))
        if url.path == "/api/job/log":
            job = CURRENT_JOB
            if not job:
                return self.send_json({"job": None, "text": "", "offset": 0})
            offset = max(0, int(arg("offset", "0") or 0))
            size = job.log_path.stat().st_size if job.log_path.exists() else 0
            if offset > size:
                offset = 0
            # first request: only the tail, so huge logs stay responsive
            if offset == 0 and size > 200_000:
                offset = size - 200_000
            with open(job.log_path, "rb") as f:
                f.seek(offset)
                chunk = f.read(500_000)
            text = chunk.decode(errors="replace")
            if HOST_WORK:
                text = text.replace(str(WORK), HOST_WORK)
            if HOST_DB:
                text = text.replace(str(DB_DIR), HOST_DB)
            return self.send_json({"job": job.to_dict(), "text": text,
                                   "offset": offset + len(chunk)})
        raise ApiError("Not found.", HTTPStatus.NOT_FOUND)

    @handle_errors
    def do_POST(self):
        # Browsers cannot add this header to cross-site requests without a CORS
        # preflight (which we never allow), so other websites cannot start jobs.
        if self.headers.get("X-DeCodeDNA") != "1":
            raise ApiError("Forbidden.", HTTPStatus.FORBIDDEN)
        url = urllib.parse.urlparse(self.path)
        body = self.read_body()
        if url.path == "/api/jobs":
            return self.send_json(start_job(body))
        if url.path == "/api/job/cancel":
            if CURRENT_JOB:
                CURRENT_JOB.cancel()
            return self.send_json({"ok": True})
        if url.path == "/api/settings":
            return self.send_json(save_settings(body))
        if url.path == "/api/shutdown":
            if CURRENT_JOB and CURRENT_JOB.status == "running" and not body.get("force"):
                raise ApiError("A job is still running.", HTTPStatus.CONFLICT)
            if CURRENT_JOB:
                CURRENT_JOB.cancel()
            self.send_json({"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        raise ApiError("Not found.", HTTPStatus.NOT_FOUND)


def main():
    RESULTS.mkdir(parents=True, exist_ok=True)
    host = os.environ.get("DECODEDNA_HOST", "0.0.0.0")
    server = ThreadingHTTPServer((host, PORT), Handler)
    server.daemon_threads = True
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=server.shutdown, daemon=True).start())
    print(f"DeCodeDNA interface running on http://localhost:{PORT}  (workspace: {HOST_WORK or WORK})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    if CURRENT_JOB and CURRENT_JOB.status == "running":
        CURRENT_JOB.cancel()
    print("DeCodeDNA interface stopped.", flush=True)


if __name__ == "__main__":
    sys.exit(main())
