"use strict";

// ─── helpers ────────────────────────────────────────────────────────────────
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

async function api(path, body) {
  const opts = body === undefined ? {} : {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-DeCodeDNA": "1" },
    body: JSON.stringify(body),
  };
  const res = await fetch(path, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
  return data;
}

let toastTimer;
function toast(msg, isError = false) {
  const t = $("#toast");
  t.textContent = msg;
  t.className = "toast" + (isError ? " error" : "");
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, isError ? 7000 : 3500);
}

function fmtElapsed(s) {
  const m = Math.floor(s / 60), sec = s % 60;
  return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : m ? `${m} min ${sec} s` : `${sec} s`;
}

const STEP_LABELS = { qc: "02 quick look", consensus: "03 consensus", denoise: "04 denoise", taxonomy: "05 taxonomy" };
const STEP_ORDER = ["qc", "consensus", "denoise", "taxonomy"];
const STEP_SCRIPTS = {
  "02_quick_look_clean.sh": "step 2/5: quality & quick look",
  "03_consensus_sort.sh": "step 3/5: consensus",
  "04_denoise.sh": "step 4/5: denoise",
  "05_taxonomic_assignment.sh": "step 5/5: taxonomy",
};
const PRESETS = {
  default: { quality: 12, min_length: 100, max_length: 500 },
  "12s": { quality: 15, min_length: 150, max_length: 350 },
  mito: { quality: 18, min_length: 15000, max_length: 18000 },
};

// ─── state ──────────────────────────────────────────────────────────────────
const S = {
  state: null,
  runs: [],
  selectedRun: localGet("run") || "",
  qcInput: localGet("qcInput") || "",
  job: null,
  logOffset: 0,
  logJobId: null,
  lastJobStatus: null,
};

function localGet(k) { try { return localStorage.getItem("decodedna." + k); } catch { return null; } }
function localSet(k, v) { try { localStorage.setItem("decodedna." + k, v); } catch { /* private mode */ } }

// ─── navigation ─────────────────────────────────────────────────────────────
function show(screen) {
  $$(".steps button").forEach(b => b.classList.toggle("active", b.dataset.screen === screen));
  $$(".screen").forEach(s => { s.hidden = s.id !== "screen-" + screen; });
  localSet("screen", screen);
  if (screen === "databases") loadCheck();
  if (screen === "taxonomy") loadResults();
  $("#main").scrollTop = 0;
}
$$(".steps button").forEach(b => b.addEventListener("click", () => show(b.dataset.screen)));

// ─── 1. databases ───────────────────────────────────────────────────────────
const DB_NAMES = { "12s": "12S (MIDORI)", coi: "COI (MIDORI)", mitofish: "MitoFish" };

async function loadCheck() {
  $("#recheck-btn").disabled = true;
  try {
    const c = await api("/api/check");
    $("#db-folder").textContent = c.database_dir_host + (c.writable ? "" : "  (read-only)");
    const by = (g, n) => c.checks.find(x => x.group === g && x.name === n);
    const rows = Object.keys(DB_NAMES).map(db => {
      const k = by("kraken2", db), b = by("blast", db);
      const cb = h("input", { type: "checkbox", value: db, checked: c.selected.includes(db) });
      cb.addEventListener("change", saveDatabases);
      const mark = x => x && x.ok ? h("span", { class: "ok" }, "✓ found") : h("span", { class: "bad", title: x ? x.detail : "" }, "✗ missing");
      return h("tr", {}, h("td", {}, cb), h("td", {}, DB_NAMES[db]), h("td", {}, mark(k)), h("td", {}, mark(b)));
    });
    $("#db-rows").replaceChildren(...rows);

    const tax = by("blast", "taxdb");
    $("#taxdb-line").replaceChildren(tax && tax.ok
      ? h("span", { class: "ok" }, "✓ BLAST taxonomy names (taxdb) found")
      : h("span", { class: "bad" }, "✗ BLAST taxonomy names (taxdb.btd) missing: species tables would come out empty"));

    const badTools = c.checks.filter(x => x.group === "tool" && !x.ok);
    const nTools = c.checks.filter(x => x.group === "tool").length;
    $("#tools-line").replaceChildren(badTools.length
      ? h("span", { class: "bad" }, "✗ Missing tools: " + badTools.map(x => x.name).join(", "))
      : h("span", { class: "ok" }, `✓ All ${nTools} pipeline tools installed`));

    const selectedOk = c.selected.every(db => by("kraken2", db)?.ok && by("blast", db)?.ok) && tax?.ok;
    $("#tick-databases").classList.toggle("done", selectedOk && !badTools.length);
    $("#build-db-btn").disabled = !c.writable;
  } catch (e) {
    toast(e.message, true);
  } finally {
    $("#recheck-btn").disabled = false;
  }
}

async function saveDatabases() {
  const dbs = $$("#db-rows input:checked").map(x => x.value);
  try {
    await api("/api/settings", { databases: dbs });
    await loadState();
    loadCheck();
  } catch (e) {
    toast(e.message, true);
    loadCheck();
  }
}

function renderPerformance() {
  const st = S.state;
  const s = st.settings;
  $("#threads").value = s.threads;
  $("#threads").max = Math.max(st.cpus, 1);
  $("#threads-hint").textContent = `${st.cpus} CPU cores available to DeCodeDNA.`;
  $("#memory-mapping").value = s.memory_mapping === null ? "auto" : s.memory_mapping ? "on" : "off";
  const mem = st.memory_gb ? `${st.memory_gb} GB memory available` : "Memory size unknown";
  const db = st.kraken_db_gb ? `, selected Kraken2 databases need ${st.kraken_db_gb} GB` : "";
  $("#memory-hint").textContent = `${mem}${db}. Currently ${st.memory_mapping_effective ? "on" : "off"}.`;
}

$("#threads").addEventListener("change", async e => {
  try { await api("/api/settings", { threads: +e.target.value }); await loadState(); }
  catch (err) { toast(err.message, true); }
});
$("#memory-mapping").addEventListener("change", async e => {
  const v = { auto: null, on: true, off: false }[e.target.value];
  try { await api("/api/settings", { memory_mapping: v }); await loadState(); }
  catch (err) { toast(err.message, true); }
});
$("#recheck-btn").addEventListener("click", loadCheck);
$("#build-db-btn").addEventListener("click", () => {
  if (!confirm("Build all reference databases now?\n\nThis downloads several GB, needs ~200 GB of free disk space in the database folder and takes 1–2 hours.")) return;
  startJob({ action: "build_db" });
});

// ─── 2. quality & quick look ────────────────────────────────────────────────
function applyPreset(name) {
  const p = PRESETS[name];
  if (!p) return;
  for (const [k, v] of Object.entries(p)) $("#" + k).value = v;
}
$("#preset").addEventListener("change", e => applyPreset(e.target.value));
["quality", "min_length", "max_length"].forEach(id =>
  $("#" + id).addEventListener("input", () => { $("#preset").value = "custom"; }));

async function setQcInput(path) {
  S.qcInput = path;
  localSet("qcInput", path);
  const label = $("#qc-input-label");
  if (!path) { label.textContent = "No folder chosen"; label.classList.remove("set"); return; }
  try {
    const b = await api("/api/browse?path=" + encodeURIComponent(path));
    label.replaceChildren(b.host_path, " ",
      h("span", { class: "count" }, `· ${b.seq_files} sequence file${b.seq_files === 1 ? "" : "s"}`));
    label.classList.add("set");
  } catch {
    S.qcInput = "";
    label.textContent = "No folder chosen";
    label.classList.remove("set");
  }
}
$("#qc-input-btn").addEventListener("click", async () => {
  const p = await pickFolder(S.qcInput || S.state.workspace.path);
  if (p) setQcInput(p);
});

function collectParams(screenIds) {
  const params = {};
  for (const id of screenIds) {
    for (const el of $$(`#screen-${id} [data-param]`)) {
      params[el.dataset.param] = el.type === "checkbox" ? el.checked : el.value;
    }
  }
  return params;
}

$("#qc-run-btn").addEventListener("click", async () => {
  const run = $("#run-name").value.trim();
  const runAll = $("#run-all").checked;
  if (!S.qcInput) return toast("Choose an input folder first.", true);
  const existing = S.runs.find(r => r.name === run);
  if (existing && (runAll ? Object.values(existing.steps).some(Boolean) : existing.steps.qc)) {
    if (!confirm(`A run called "${run}" already has results. Run again and overwrite them?`)) return;
  }
  const params = collectParams(runAll ? ["qc", "consensus", "denoise", "taxonomy"] : ["qc"]);
  const ok = await startJob({ action: runAll ? "run_all" : "qc", run, input: S.qcInput, params });
  if (ok) { S.selectedRun = run; localSet("run", run); }
});

// ─── runs (steps 3–5) ───────────────────────────────────────────────────────
async function loadRuns() {
  try { S.runs = await api("/api/runs"); } catch { S.runs = []; }
  if (!S.runs.find(r => r.name === S.selectedRun)) S.selectedRun = S.runs[0]?.name || "";
  renderRunSelects();
  renderTicks();
}

function renderTicks() {
  const run = S.runs.find(r => r.name === S.selectedRun);
  for (const k of STEP_ORDER) $("#tick-" + k).classList.toggle("done", !!run?.steps[k]);
}

function renderRunSelects() {
  for (const box of $$(".run-select")) {
    const step = box.dataset.step;
    const prev = STEP_ORDER[STEP_ORDER.indexOf(step) - 1];
    if (!S.runs.length) {
      box.replaceChildren(h("p", { class: "muted" }, "No runs yet. Start with step 2 (Quality & quick look)."));
      continue;
    }
    const sel = h("select", { "aria-label": "Run" },
      S.runs.map(r => h("option", { value: r.name, selected: r.name === S.selectedRun }, r.name)));
    sel.addEventListener("change", () => {
      S.selectedRun = sel.value; localSet("run", sel.value);
      renderRunSelects(); renderTicks();
      if (!$("#screen-taxonomy").hidden) loadResults();
    });
    const run = S.runs.find(r => r.name === S.selectedRun);
    const chips = h("div", { class: "run-steps" },
      STEP_ORDER.map(k => h("span", { class: run?.steps[k] ? "done" : "" }, (run?.steps[k] ? "✓ " : "") + STEP_LABELS[k])));
    const need = run && !run.steps[prev]
      ? h("p", { class: "need warn" }, `This run has no ${STEP_LABELS[prev]} results yet. Run that step first.`)
      : null;
    box.replaceChildren(sel, chips, need || "");
    const btn = $(`[data-run-step="${step}"]`);
    if (btn) btn.disabled = !run || !run.steps[prev];
  }
}

$$("[data-run-step]").forEach(btn => btn.addEventListener("click", () => {
  const step = btn.dataset.runStep;
  const run = S.runs.find(r => r.name === S.selectedRun);
  if (run?.steps[step] && !confirm(`"${run.name}" already has ${STEP_LABELS[step]} results. Run again and overwrite them?`)) return;
  startJob({ action: step, run: S.selectedRun, params: collectParams([step]) });
}));

$("#similarity").addEventListener("input", e => { $("#similarity-val").textContent = (+e.target.value).toFixed(2); });

// ─── 5. results ─────────────────────────────────────────────────────────────
async function loadResults() {
  const box = $("#results");
  if (!S.selectedRun) { box.replaceChildren(); return; }
  let r;
  try { r = await api("/api/results?run=" + encodeURIComponent(S.selectedRun)); }
  catch (e) { box.replaceChildren(h("p", { class: "bad" }, e.message)); return; }

  const parts = [h("h1", {}, "Results: ", r.run),
    h("p", { class: "muted small" }, "Saved on your computer in ", h("code", {}, r.host_path))];

  if (r.species) {
    const t = r.species;
    parts.push(h("div", { class: "card" },
      h("div", { class: "card-head" },
        h("div", {}, h("h2", {}, "Species × sample (reads)"),
          h("span", { class: "muted small" }, `${t.total} taxa, TaxonKit LCA with genus/family fallback`)),
        h("a", { href: r.files.find(f => f.name === "TaxonKit_LCA_species_abundance.csv")?.url, download: "" },
          h("button", { class: "ghost small" }, "Download CSV"))),
      h("div", { class: "table-wrap" },
        h("table", { class: "species" },
          h("thead", {}, h("tr", {}, t.columns.map((c, i) => h("th", {}, i === 0 ? "Taxon" : c)))),
          h("tbody", {}, t.rows.map(row => h("tr", {}, row.map(v => h("td", {}, v)))))))));
  } else if (!r.steps.taxonomy) {
    parts.push(h("p", { class: "muted" }, "No taxonomy results for this run yet."));
  }

  const kronaCard = (title, items) => items.length ? h("div", { class: "card" }, h("h2", {}, title),
    h("div", { class: "chips" }, items.map(k => h("a", { href: k.url, target: "_blank", rel: "noopener" }, k.name)))) : null;
  parts.push(kronaCard("Interactive Krona plots (per sample)", r.krona));
  parts.push(kronaCard("Quick-look Krona plots (step 2, Kraken2 on reads)", r.quicklook_krona));

  if (r.files.length) {
    parts.push(h("div", { class: "card" }, h("h2", {}, "Result files"),
      h("ul", { class: "file-list" }, r.files.map(f => h("li", {},
        h("b", {}, f.label), h("a", { href: f.url, target: "_blank", rel: "noopener" }, f.name),
        h("button", { class: "ghost copy", onclick: () => copy(f.host_path) }, "Copy path"),
        h("code", {}, f.host_path))))));
  }
  if (r.logs.length) {
    parts.push(h("details", { class: "card" }, h("summary", {}, h("h2", {}, "Logs")),
      h("div", { class: "chips" }, r.logs.map(l => h("a", { href: l.url, target: "_blank", rel: "noopener" }, l.name)))));
  }
  box.replaceChildren(h("div", { class: "results" }, parts));
}

async function copy(text) {
  try { await navigator.clipboard.writeText(text); toast("Path copied"); }
  catch { prompt("Copy this path:", text); }
}

// ─── jobs & console ─────────────────────────────────────────────────────────
async function startJob(body) {
  try {
    const job = await api("/api/jobs", body);
    S.job = job;
    resetConsole(job);
    pollLog();
    toast("Started: " + job.label);
    return true;
  } catch (e) {
    toast(e.message, true);
    return false;
  }
}

function resetConsole(job) {
  S.logOffset = 0;
  S.logJobId = job.id;
  $("#console-log").textContent = "";
  $("#console").hidden = false;
  $("#console").classList.remove("collapsed");
  $("#console-toggle").textContent = "Hide log";
  renderJob(job);
}

function renderJob(job) {
  const pill = $("#job-pill");
  if (!job) { pill.hidden = true; return; }
  const running = job.status === "running";
  const stepTxt = job.step && STEP_SCRIPTS[job.step] && job.action === "run_all" ? ` · ${STEP_SCRIPTS[job.step]}` : "";
  const word = { running: "Running", succeeded: "Finished", failed: "Failed", cancelled: "Cancelled" }[job.status];
  pill.hidden = false;
  pill.className = "job-pill " + job.status;
  pill.textContent = `${word}: ${job.label}${running ? stepTxt : ""}`;
  $("#console-title").textContent = job.label;
  $("#console-meta").textContent = `${word.toLowerCase()} · ${fmtElapsed(job.elapsed)}${stepTxt}`;
  $("#console-dot").className = "dot " + job.status;
  $("#console-cancel").hidden = !running;
}

let logTimer;
async function pollLog() {
  clearTimeout(logTimer);
  try {
    const r = await api("/api/job/log?offset=" + S.logOffset);
    if (r.job) {
      if (r.job.id !== S.logJobId) resetConsole(r.job);
      const pre = $("#console-log");
      const atBottom = pre.scrollHeight - pre.scrollTop - pre.clientHeight < 40;
      if (r.text) {
        pre.textContent += r.text;
        if (pre.textContent.length > 400000) pre.textContent = pre.textContent.slice(-300000);
        if (atBottom) pre.scrollTop = pre.scrollHeight;
      }
      S.logOffset = r.offset;
      S.job = r.job;
      renderJob(r.job);
      if (S.lastJobStatus === "running" && r.job.status !== "running") onJobFinished(r.job);
      S.lastJobStatus = r.job.status;
      if (r.job.status === "running") logTimer = setTimeout(pollLog, 1000);
    }
  } catch {
    logTimer = setTimeout(pollLog, 3000);
  }
}

async function onJobFinished(job) {
  if (job.status === "succeeded") {
    toast("Finished: " + job.label);
    $("#console").classList.add("collapsed");
    $("#console-toggle").textContent = "Show log";
  }
  else if (job.status === "failed") toast("Failed: " + job.label + ". See the log for details.", true);
  await loadRuns();
  if (job.action === "build_db") loadCheck();
  if (!$("#screen-taxonomy").hidden) loadResults();
  if (job.status === "succeeded" && (job.action === "run_all" || job.action === "taxonomy")) show("taxonomy");
  else if (job.status === "succeeded" && job.run) {
    const next = { qc: "consensus", consensus: "denoise", denoise: "taxonomy" }[job.action];
    if (next) show(next);
  }
}

$("#console-cancel").addEventListener("click", async () => {
  if (!confirm("Cancel the running job? Partial results stay in the run folder.")) return;
  try { await api("/api/job/cancel", {}); } catch (e) { toast(e.message, true); }
});
$("#console-toggle").addEventListener("click", () => {
  const c = $("#console");
  c.classList.toggle("collapsed");
  const collapsed = c.classList.contains("collapsed");
  $("#console-toggle").textContent = collapsed ? "Show log" : "Hide log";
  $("#console-toggle").setAttribute("aria-expanded", String(!collapsed));
});
$("#job-pill").addEventListener("click", () => {
  $("#console").hidden = false;
  $("#console").classList.remove("collapsed");
  $("#console-toggle").textContent = "Hide log";
});

$("#quit-btn").addEventListener("click", async () => {
  const running = S.job && S.job.status === "running";
  if (!confirm(running ? "A job is still running. Stop it and quit DeCodeDNA?" : "Quit DeCodeDNA? Your results stay in your workspace.")) return;
  try {
    await api("/api/shutdown", { force: running });
    document.body.replaceChildren(h("div", { style: "margin:auto;text-align:center;padding:40px" },
      h("h1", {}, "DeCodeDNA has stopped"), h("p", { class: "muted" }, "You can close this tab. Start it again with the DeCodeDNA launcher.")));
  } catch (e) { toast(e.message, true); }
});

// ─── folder picker ──────────────────────────────────────────────────────────
let pickerResolve, pickerCurrent;
async function pickFolder(start) {
  const dlg = $("#picker");
  await browseTo(start);
  dlg.showModal();
  return new Promise(res => { pickerResolve = res; });
}
$("#picker").addEventListener("close", () => {
  const dlg = $("#picker");
  pickerResolve?.(dlg.returnValue === "ok" ? pickerCurrent : null);
  pickerResolve = null;
});

async function browseTo(path) {
  let b;
  try { b = await api("/api/browse?path=" + encodeURIComponent(path)); }
  catch (e) {
    if (path !== S.state.workspace.path) return browseTo(S.state.workspace.path);
    toast(e.message, true); return;
  }
  pickerCurrent = b.path;
  $("#picker-roots").replaceChildren(...b.roots.map(r => h("button", {
    type: "button", class: b.path === r.path || b.path.startsWith(r.path + "/") ? "active" : "",
    onclick: () => browseTo(r.path),
  }, r.label)));
  $("#picker-path").textContent = b.host_path;
  const items = [];
  if (b.parent) items.push(h("li", {}, h("button", { type: "button", onclick: () => browseTo(b.parent) }, h("span", {}, "⬑  Up one level"), "")));
  for (const d of b.dirs) {
    items.push(h("li", {}, h("button", { type: "button", onclick: () => browseTo(d.path) },
      h("span", {}, "📁  " + d.name),
      d.seq_files ? h("span", { class: "seq" }, `${d.seq_files} sequence file${d.seq_files === 1 ? "" : "s"}`) : "")));
  }
  if (!b.dirs.length) items.push(h("li", { class: "empty" }, "No subfolders."));
  $("#picker-list").replaceChildren(...items);
  $("#picker-count").textContent = b.seq_files
    ? `${b.seq_files} FASTQ/FASTA file${b.seq_files === 1 ? "" : "s"} in this folder`
    : "No FASTQ/FASTA files in this folder";
}

// ─── boot ───────────────────────────────────────────────────────────────────
async function loadState() {
  S.state = await api("/api/state");
  const st = S.state;
  $("#workspace").textContent = "Workspace: " + st.workspace.host_path;
  renderPerformance();
  return st;
}

async function boot() {
  let st;
  try { st = await loadState(); }
  catch (e) { toast("Cannot reach DeCodeDNA: " + e.message, true); return; }

  $("#examples").replaceChildren(...st.examples.map(ex =>
    h("button", { class: "ghost", type: "button", onclick: () => { setQcInput(ex.path); applyPreset(ex.preset); $("#preset").value = ex.preset; } }, ex.label)));
  $("#run-name").value = st.default_run_name;
  applyPreset("default");
  $("#confidence").value = 0.05;
  setQcInput(S.qcInput);
  await loadRuns();

  if (st.job) {
    S.job = st.job;
    S.lastJobStatus = st.job.status;
    resetConsole(st.job);
    pollLog();
  }
  show(localGet("screen") || "databases");
}
boot();
