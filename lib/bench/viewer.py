#!/usr/bin/env python3
"""bench viewer: self-contained web diagram player for workflow-run event streams.

The web twin of tui.py, same JSONL event protocol, rendered as a flow diagram:
stages are nodes, the pointer advances as the run plays, hover shows a tooltip,
click pins a detail panel (items, fingerprints, cost). Controls: scenario
picker, play/pause, speed, scrub.

  build [--events name=path ...] [--out viewer.html]

With no --events, embeds the built-in demo scenarios (task-type and workflow
variants + one fault-injection failure). Stdlib only; output is one HTML file
with zero external requests.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tui import demo_events  # noqa: E402


def _run(scenario, layer, config, stages, script, status="pass", totals=None):
    evs = [{"dt": 0, "ev": "run_start", "run_id": scenario.replace(" ", "-")[:24],
            "scenario": scenario, "layer": layer, "config": config, "stages": stages}]
    evs += script
    evs.append({"dt": .3, "ev": "run_end", "status": status, "totals": totals or {}})
    return evs


def _st(dt, stage):
    return {"dt": dt, "ev": "stage_start", "stage": stage}


def _end(dt, stage, detail="", dur=None, cost=None, status="pass"):
    e = {"dt": dt, "ev": "stage_end", "stage": stage, "status": status, "detail": detail}
    if dur is not None:
        e["duration_s"] = dur
    if cost is not None:
        e["cost_usd"] = cost
    return e


def _it(dt, stage, name, status="pass", detail="", fingerprint=None):
    e = {"dt": dt, "ev": "item", "stage": stage, "name": name, "status": status, "detail": detail}
    if fingerprint:
        e["fingerprint"] = fingerprint
    return e


def demo_scenarios():
    s = {"feature · full lane": demo_events()}

    st = ["classify", "execute", "ship-gate"]
    s["feature · tiny lane"] = _run(
        "tiny lane", "L1", {"model": "haiku", "lane": "tiny"}, st,
        [_st(.3, "classify"), _end(.5, "classify", "typo-class change · tiny lane", .5),
         _st(.2, "execute"),
         _it(.6, "execute", "worker", "pass", "diff 4 lines"),
         _it(.4, "execute", "self-check", "pass"),
         _end(.2, "execute", "1 task, no ceremony", 1.2, .01),
         _st(.2, "ship-gate"), _end(.5, "ship-gate", "de-escalated: no proof owed", .5)],
        totals={"cost_usd": .01, "duration_s": 3, "reproduce": "risk buys ceremony: small diff, small loop"})

    st = ["classify", "source-sweep", "claim-matrix", "skeptic-panel", "synthesis", "route"]
    s["research · claim-verify loop"] = _run(
        "research loop", "L2", {"model": "sonnet", "type": "research"}, st,
        [_st(.3, "classify"), _end(.5, "classify", "research task · claim-verify loop", .5),
         _st(.2, "source-sweep"),
         _it(.5, "source-sweep", "primary sources", "pass", "7 found"),
         _it(.4, "source-sweep", "recency check", "pass", "newest 2026-06"),
         _end(.3, "source-sweep", "7 sources, 2 primary", 1.2, .06),
         _st(.2, "claim-matrix"), _end(.9, "claim-matrix", "5 claims extracted", .9, .03),
         _st(.2, "skeptic-panel"),
         _it(.5, "skeptic-panel", "skeptic 1", "pass", "holds"),
         _it(.5, "skeptic-panel", "skeptic 2", "fail", "refutes claim 4",
             fingerprint="claim 4 'X is 3x faster' cites a 2023 benchmark; upstream rewrote in 2025"),
         _it(.5, "skeptic-panel", "skeptic 3", "pass", "holds"),
         _end(.3, "skeptic-panel", "4/5 claims hold · claim 4 refuted", 1.8, .09),
         _st(.2, "synthesis"), _end(1.0, "synthesis", "note drafted, refuted claim dropped", 1.0, .05),
         _st(.2, "route"), _end(.4, "route", "ledger row + research/ snapshot", .4)],
        totals={"cost_usd": .23, "duration_s": 7, "reproduce": "claims are guilty until verified"})

    st = ["frame", "metrics-contract", "seed-data", "run-matrix", "lab-report"]
    s["eval · tool comparison"] = _run(
        "eval loop", "L2", {"model": "haiku workers", "type": "eval"}, st,
        [_st(.3, "frame"), _end(.6, "frame", "A-vs-B, 3 criteria", .6),
         _st(.2, "metrics-contract"), _end(.6, "metrics-contract", "yield + $/task + flake", .6),
         _st(.2, "seed-data"),
         _it(.6, "seed-data", "hand-verify 12 seeds", "pass", "human-checked"),
         _end(.2, "seed-data", "12 seeds, hand-verified", .8),
         _st(.2, "run-matrix"),
         _it(.5, "run-matrix", "tool-A x 12", "pass", "10/12"),
         _it(.5, "run-matrix", "tool-B x 12", "pass", "11/12"),
         _it(.5, "run-matrix", "flake probe x3", "pass", "stable"),
         _end(.3, "run-matrix", "36 cells", 1.8, .19),
         _st(.2, "lab-report"), _end(.8, "lab-report", "B wins on yield, A on cost", .8, .02)],
        totals={"cost_usd": .21, "duration_s": 6, "reproduce": "numbers over vibes"})

    st = ["classify", "grill", "spec", "execute", "ship-gate"]
    s["fault injection · retry exhausted"] = _run(
        "retry exhausted (M-04)", "L1", {"model": "scripted", "fault": "worker always broken"}, st,
        [_st(.3, "classify"), _end(.5, "classify", "feature · normal lane", .5),
         _st(.2, "grill"), _end(.6, "grill", "1 question resolved", .6),
         _st(.2, "spec"), _end(.9, "spec", "spec + criteria", .9, .04),
         _st(.2, "execute"),
         _it(.6, "execute", "task-1 worker", "pass", "diff 30 lines"),
         _it(.5, "execute", "task-1 verifier", "fail",
             fingerprint="FAIL criterion 2: migration has no rollback"),
         {"dt": .3, "ev": "retry", "stage": "execute", "attempt": 2},
         _it(.7, "execute", "task-1 fix-agent", "pass", "rollback added"),
         _it(.5, "execute", "task-1 verifier", "fail",
             fingerprint="FAIL criterion 2: rollback drops the wrong table"),
         {"dt": .3, "ev": "retry", "stage": "execute", "attempt": 3},
         _it(.5, "execute", "retry budget", "fail", "max retries reached"),
         _end(.3, "execute", "retries exhausted -> honest failure, no loop", 3.4, .22, status="fail"),
         _it(.2, "ship-gate", "skipped", "skip", "never reached"),
         _end(.1, "ship-gate", "not reached", status="skip")],
        status="fail",
        totals={"cost_usd": .26, "duration_s": 7, "retries": 2,
                "reproduce": "the designed failure: stop, report, never hang"})
    return s


TEMPLATE = """<title>bench · workflow run viewer</title>
<style>
:root{--bg:#fafafa;--fg:#111827;--line:#37415155;--muted:#6b7280;--accent:#4f46e5;
--card:#ffffff;--pass:#16a34a;--fail:#dc2626;--warn:#d97706;--passbg:#dcfce7;
--failbg:#fee2e2;--skipbg:#f3f4f6}
@media(prefers-color-scheme:dark){:root{--bg:#111827;--fg:#f3f4f6;--line:#9ca3af44;
--muted:#9ca3af;--accent:#818cf8;--card:#1f2937;--pass:#4ade80;--fail:#f87171;
--warn:#fbbf24;--passbg:#14532d;--failbg:#7f1d1d;--skipbg:#1f2937}}
:root[data-theme=dark]{--bg:#111827;--fg:#f3f4f6;--line:#9ca3af44;--muted:#9ca3af;
--accent:#818cf8;--card:#1f2937;--pass:#4ade80;--fail:#f87171;--warn:#fbbf24;
--passbg:#14532d;--failbg:#7f1d1d;--skipbg:#1f2937}
:root[data-theme=light]{--bg:#fafafa;--fg:#111827;--line:#37415155;--muted:#6b7280;
--accent:#4f46e5;--card:#ffffff;--pass:#16a34a;--fail:#dc2626;--warn:#d97706;
--passbg:#dcfce7;--failbg:#fee2e2;--skipbg:#f3f4f6}
body{font-family:system-ui,sans-serif;background:var(--bg);color:var(--fg);
max-width:1080px;margin:1.5rem auto;padding:0 1rem;line-height:1.5}
h1{font-size:1.2rem}
.bar{display:flex;flex-wrap:wrap;gap:.6rem;align-items:center;margin:1rem 0;
font-size:.9rem}
.bar select,.bar button{font:inherit;background:var(--card);color:var(--fg);
border:1px solid var(--line);border-radius:6px;padding:.3rem .6rem;cursor:pointer}
.bar button.primary{border-color:var(--accent);color:var(--accent);font-weight:600}
.bar input[type=range]{flex:1;min-width:140px;accent-color:var(--accent)}
.readout{color:var(--muted);font-variant-numeric:tabular-nums;font-size:.85rem}
.meta{color:var(--muted);font-size:.85rem;margin:.2rem 0 .8rem}
.flow{display:flex;flex-wrap:wrap;gap:0;align-items:stretch;margin:1rem 0}
.node{position:relative;background:var(--card);border:2px solid var(--line);
border-radius:8px;padding:.5rem .8rem;min-width:8.5rem;cursor:pointer;
font-size:.85rem;margin:.4rem 0}
.node b{display:block;font-weight:600}
.node small{color:var(--muted);font-variant-numeric:tabular-nums}
.node .glyph{position:absolute;top:-.65rem;left:.6rem;background:var(--card);
padding:0 .25rem;font-size:.9rem;line-height:1}
.node.pending{opacity:.55}
.node.running{border-color:var(--accent)}
@media(prefers-reduced-motion:no-preference){
.node.running{animation:pulse 1.2s ease-in-out infinite}}
@keyframes pulse{0%,100%{box-shadow:0 0 0 0 transparent}
50%{box-shadow:0 0 0 5px color-mix(in srgb,var(--accent) 30%,transparent)}}
.node.pass{border-color:var(--pass);background:
color-mix(in srgb,var(--passbg) 55%,var(--card))}
.node.fail,.node.error{border-color:var(--fail);background:
color-mix(in srgb,var(--failbg) 55%,var(--card))}
.node.retry{border-color:var(--warn)}
.node.skip{border-style:dashed;opacity:.6}
.node.pinned{outline:2px dashed var(--accent);outline-offset:3px}
.edge{display:flex;align-items:center;padding:0 .35rem;color:var(--muted)}
.badge{display:inline-block;border-radius:99px;border:1px solid var(--warn);
color:var(--warn);padding:0 .45rem;font-size:.72rem;margin-left:.3rem}
#tip{position:fixed;pointer-events:none;background:var(--card);color:var(--fg);
border:1px solid var(--line);border-radius:8px;padding:.5rem .7rem;font-size:.8rem;
max-width:24rem;box-shadow:0 4px 14px #0003;display:none;z-index:9}
#tip .fp{font-family:ui-monospace,monospace;font-size:.72rem;display:block;
white-space:pre-wrap;border-top:1px dashed var(--line);margin-top:.3rem;padding-top:.3rem}
#panel{border:1px solid var(--line);border-radius:8px;background:var(--card);
padding: .8rem 1rem;margin:1rem 0;font-size:.87rem;min-height:3rem}
#panel h3{margin:.1rem 0 .4rem;font-size:.95rem}
#panel table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}
#panel td,#panel th{border:1px solid var(--line);padding:.3rem .5rem;text-align:left;
font-size:.82rem}
#panel .fp{font-family:ui-monospace,monospace;font-size:.75rem;color:var(--fail);
white-space:pre-wrap}
.chip{display:inline-block;border-radius:99px;padding:.05rem .7rem;font-weight:600;
font-size:.8rem}
.chip.pass{background:var(--passbg)}.chip.fail{background:var(--failbg)}
.note{color:var(--muted);font-size:.8rem}
</style>
<h1>bench · workflow run viewer</h1>
<p class="meta">Plays a recorded run event stream as a flow diagram. Hover a step for
its numbers; click to pin details; scrub freely. These runs are <b>scripted demo
streams</b> (no model was called) showing the interaction across task types,
workflow shapes, and a fault injection.</p>
<div class="bar">
<select id="scen"></select>
<button id="play" class="primary">Pause</button>
<select id="speed"><option>0.5</option><option selected>1</option><option>2</option>
<option>4</option></select>
<input type="range" id="scrub" min="0" max="1000" value="0">
<span class="readout" id="readout"></span>
</div>
<div class="meta" id="runmeta"></div>
<div class="flow" id="flow"></div>
<div id="panel"><span class="note">Click a step to pin its detail here. The run
summary appears when the run finishes.</span></div>
<div id="tip"></div>
<script>
const SCENARIOS = __DATA__;
const GLYPH = {pending:"○",running:"◉",pass:"✓",fail:"✗",error:"!",retry:"↻",skip:"⊘"};
let events=[], cum=[], total=0, t=0, playing=true, pinned=null, timer=null;

function loadScenario(name){
  events = SCENARIOS[name];
  cum = []; let acc=0;
  for(const ev of events){ acc += (ev.dt||0); cum.push(acc); }
  total = acc; t = 0; pinned = null; playing = true;
  document.getElementById("play").textContent = "Pause";
}
function stateAt(time){
  const st = {meta:{}, stages:[], by:{}, done:false, result:null, totals:{}};
  const stage = n => { if(!st.by[n]){ st.by[n]={name:n,status:"pending",detail:"",
    items:[],duration_s:null,cost_usd:null,attempt:1}; st.stages.push(st.by[n]); }
    return st.by[n]; };
  for(let i=0;i<events.length;i++){
    if(cum[i] > time) break;
    const ev = events[i];
    if(ev.ev==="run_start"){ st.meta = ev; (ev.stages||[]).forEach(stage); }
    else if(ev.ev==="stage_start") stage(ev.stage).status="running";
    else if(ev.ev==="item") stage(ev.stage).items.push(ev);
    else if(ev.ev==="retry"){ const s=stage(ev.stage); s.status="retry";
      s.attempt=ev.attempt||s.attempt+1; }
    else if(ev.ev==="stage_end"){ const s=stage(ev.stage);
      s.status=ev.status||"pass"; s.detail=ev.detail||"";
      s.duration_s=ev.duration_s??null; s.cost_usd=ev.cost_usd??null; }
    else if(ev.ev==="run_end"){ st.done=true; st.result=ev.status;
      st.totals=ev.totals||{}; }
  }
  return st;
}
function nodeHtml(s,i){
  const att = s.attempt>1 ? `<span class="badge">attempt ${s.attempt}</span>` : "";
  const nums = [s.duration_s!=null?`${s.duration_s}s`:"",
    s.cost_usd?`$${s.cost_usd.toFixed(2)}`:""].filter(Boolean).join(" · ");
  return `<div class="node ${s.status}${pinned===s.name?" pinned":""}" data-stage="${s.name}"
    role="button" tabindex="0" aria-label="${s.name}: ${s.status}">
    <span class="glyph">${GLYPH[s.status]||""}</span><b>${s.name}${att}</b>
    <small>${s.detail || (s.status==="running" ? s.items.slice(-1).map(x=>x.name).join("") : "&nbsp;")}</small>
    <small>${nums||"&nbsp;"}</small></div>`;
}
function render(){
  const st = stateAt(t);
  const flow = document.getElementById("flow");
  flow.innerHTML = st.stages.map((s,i)=>
    (i?'<div class="edge">→</div>':"") + nodeHtml(s,i)).join("");
  const m = st.meta;
  document.getElementById("runmeta").textContent =
    `${m.scenario||""} · ${m.layer||""} · config ${JSON.stringify(m.config||{})}`;
  const cost = st.stages.reduce((a,s)=>a+(s.cost_usd||0),0);
  const nd = st.stages.filter(s=>["pass","fail","error","skip"].includes(s.status)).length;
  document.getElementById("readout").textContent =
    `${nd}/${st.stages.length} stages · $${cost.toFixed(2)} · ${t.toFixed(1)}s/${total.toFixed(1)}s`;
  document.getElementById("scrub").value = total? Math.round(1000*t/total) : 0;
  renderPanel(st);
}
function renderPanel(st){
  const p = document.getElementById("panel");
  if(pinned && st.by[pinned]){
    const s = st.by[pinned];
    const rows = s.items.map(it=>`<tr><td>${GLYPH[it.status]||""} ${it.name}</td>
      <td>${it.detail||""}${it.fingerprint?`<div class="fp">${it.fingerprint}</div>`:""}</td></tr>`).join("");
    p.innerHTML = `<h3>${s.name} · <span class="chip ${s.status==="fail"?"fail":"pass"}">${s.status}</span>
      ${s.attempt>1?` · attempt ${s.attempt}`:""}</h3>
      <div>${s.detail||""} ${s.duration_s!=null?` · ${s.duration_s}s`:""}${s.cost_usd?` · $${s.cost_usd.toFixed(2)}`:""}</div>
      ${rows?`<table><tr><th>step</th><th>detail</th></tr>${rows}</table>`:'<span class="note">no sub-steps recorded</span>'}`;
    return;
  }
  if(st.done){
    const rows = st.stages.map(s=>`<tr><td>${GLYPH[s.status]} ${s.name}</td>
      <td>${s.status}</td><td>${s.duration_s??"-"}s</td>
      <td>${s.cost_usd?`$${s.cost_usd.toFixed(2)}`:""}</td><td>${s.detail||""}</td></tr>`).join("");
    const tt = st.totals;
    p.innerHTML = `<h3>Run summary · <span class="chip ${st.result==="fail"?"fail":"pass"}">${st.result}</span></h3>
      <table><tr><th>stage</th><th>status</th><th>time</th><th>cost</th><th>detail</th></tr>${rows}</table>
      <div class="note">total $${(tt.cost_usd||0).toFixed(2)} · ${tt.duration_s||0}s
      ${tt.retries?` · ${tt.retries} retries`:""}${tt.reproduce?` · ${tt.reproduce}`:""}</div>`;
    return;
  }
  p.innerHTML = '<span class="note">Click a step to pin its detail here. The run summary appears when the run finishes.</span>';
}
const tip = document.getElementById("tip");
document.addEventListener("mousemove", e=>{
  const n = e.target.closest(".node");
  if(!n){ tip.style.display="none"; return; }
  const s = stateAt(t).by[n.dataset.stage]; if(!s) return;
  const items = s.items.map(it=>`${GLYPH[it.status]||""} ${it.name} ${it.detail||""}`).join("<br>");
  const fp = s.items.filter(it=>it.fingerprint).map(it=>`<span class="fp">${it.fingerprint}</span>`).join("");
  tip.innerHTML = `<b>${s.name}</b> · ${s.status}${s.attempt>1?` · attempt ${s.attempt}`:""}
    ${s.duration_s!=null?` · ${s.duration_s}s`:""}${s.cost_usd?` · $${s.cost_usd.toFixed(2)}`:""}
    ${s.detail?`<br>${s.detail}`:""}${items?`<br>${items}`:""}${fp}`;
  tip.style.display="block";
  tip.style.left = Math.min(e.clientX+14, innerWidth-tip.offsetWidth-8)+"px";
  tip.style.top = Math.min(e.clientY+14, innerHeight-tip.offsetHeight-8)+"px";
});
document.addEventListener("click", e=>{
  const n = e.target.closest(".node");
  if(n){ pinned = pinned===n.dataset.stage ? null : n.dataset.stage; render(); }
});
document.addEventListener("keydown", e=>{
  const n = e.target.closest?.(".node");
  if(n && (e.key==="Enter"||e.key===" ")){ e.preventDefault();
    pinned = pinned===n.dataset.stage ? null : n.dataset.stage; render(); }
});
document.getElementById("play").onclick = ()=>{
  if(!playing && t>=total) t=0;
  playing = !playing;
  document.getElementById("play").textContent = playing ? "Pause" : (t>=total?"Replay":"Play");
};
document.getElementById("scrub").oninput = e=>{
  t = total * e.target.value/1000; playing=false;
  document.getElementById("play").textContent = t>=total?"Replay":"Play"; render();
};
document.getElementById("scen").onchange = e=>{ loadScenario(e.target.value); render(); };
const sel = document.getElementById("scen");
for(const name of Object.keys(SCENARIOS)){
  const o = document.createElement("option"); o.textContent = name; sel.appendChild(o);
}
loadScenario(Object.keys(SCENARIOS)[0]);
setInterval(()=>{
  if(playing && t < total){
    t = Math.min(total, t + 0.1*parseFloat(document.getElementById("speed").value));
    if(t>=total){ playing=false; document.getElementById("play").textContent="Replay"; }
    render();
  }
}, 100);
render();
</script>"""


def build(pairs, out):
    if pairs:
        scen = {}
        for p in pairs:
            name, _, path = p.partition("=")
            scen[name] = [json.loads(l) for l in Path(path).read_text().splitlines() if l.strip()]
    else:
        scen = demo_scenarios()
    for name, evs in scen.items():  # every stream must terminate or the player never ends
        assert any(e.get("ev") == "run_end" for e in evs), f"{name}: no run_end event"
    data = json.dumps(scen, ensure_ascii=False).replace("</", "<\\/")
    Path(out).write_text(TEMPLATE.replace("__DATA__", data))
    print(f"viewer written to {out} ({len(scen)} scenarios)", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(prog="bench-viewer", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="emit the self-contained viewer HTML")
    b.add_argument("--events", nargs="*", default=[], metavar="NAME=PATH",
                   help="embed recorded event files; default: built-in demo scenarios")
    b.add_argument("--out", default="viewer.html")
    b.set_defaults(fn=lambda a: build(a.events, a.out))
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
