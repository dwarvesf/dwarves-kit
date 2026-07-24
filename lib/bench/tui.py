#!/usr/bin/env python3
"""bench tui: live terminal renderer for a workflow run's event stream.

The runner and the frontend are decoupled by a JSONL event protocol (see
README "Event protocol"): any runner that emits events gets this UI for free,
and the UI can replay any recorded run. Verbs:

  demo            play a synthesized kit full-lane run (fail -> fix -> retry included)
  replay FILE     re-play a recorded .events.jsonl at recorded pacing
  watch FILE      follow a live events file being appended by a real runner

Stdlib only, plain ANSI. When stdout is not a TTY (CI logs), falls back to
one line per event, no cursor tricks.
"""

import argparse
import json
import sys
import threading
import time
from pathlib import Path

SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
TTY = sys.stdout.isatty()


def c(code, s):
    import os
    if not TTY or os.environ.get("NO_COLOR"):
        return s
    return f"\x1b[{code}m{s}\x1b[0m"


GLYPH = {
    "pending": lambda t: c("2", "○"),
    "running": lambda t: c("36", SPIN[t % len(SPIN)]),
    "pass": lambda t: c("32", "✓"),
    "fail": lambda t: c("31", "✗"),
    "error": lambda t: c("33", "!"),
    "retry": lambda t: c("33", "↻"),
    "skip": lambda t: c("2", "⊘"),
}


class RunState:
    """Pure state machine over the event stream; renderers read it."""

    def __init__(self):
        self.meta = {}
        self.stages = []          # [{name, status, detail, items, duration_s, cost_usd, attempt}]
        self.by_name = {}
        self.done = False
        self.result = None
        self.totals = {}
        self.started = time.time()

    def _stage(self, name):
        if name not in self.by_name:
            s = {"name": name, "status": "pending", "detail": "", "items": [],
                 "duration_s": None, "cost_usd": None, "attempt": 1}
            self.stages.append(s)
            self.by_name[name] = s
        return self.by_name[name]

    def apply(self, ev):
        k = ev.get("ev")
        if k == "run_start":
            self.meta = ev
            for name in ev.get("stages", []):
                self._stage(name)
        elif k == "stage_start":
            self._stage(ev["stage"])["status"] = "running"
        elif k == "item":
            s = self._stage(ev["stage"])
            s["items"].append(ev)
            s["items"] = s["items"][-6:]  # live window: last few items per stage
        elif k == "retry":
            s = self._stage(ev["stage"])
            s["status"], s["attempt"] = "retry", ev.get("attempt", s["attempt"] + 1)
        elif k == "stage_end":
            s = self._stage(ev["stage"])
            s["status"] = ev.get("status", "pass")
            s["detail"] = ev.get("detail", "")
            s["duration_s"] = ev.get("duration_s")
            s["cost_usd"] = ev.get("cost_usd")
        elif k == "run_end":
            self.done, self.result, self.totals = True, ev.get("status"), ev.get("totals", {})


def render_frame(st, tick):
    m = st.meta
    lines = []
    title = f"{m.get('scenario', '?')} · {m.get('layer', '?')} · {m.get('config', {})}"
    lines.append(c("1", f"bench run {m.get('run_id', '')}") + f"  {title}")
    ndone = sum(1 for s in st.stages if s["status"] in ("pass", "fail", "error", "skip"))
    cost = sum(s["cost_usd"] or 0 for s in st.stages)
    lines.append(c("2", f"  {ndone}/{len(st.stages)} stages · ${cost:.3f} · "
                       f"{time.time() - st.started:.0f}s elapsed"))
    lines.append("")
    for s in st.stages:
        g = GLYPH[s["status"]](tick)
        att = c("33", f" (attempt {s['attempt']})") if s["attempt"] > 1 else ""
        dur = c("2", f"  {s['duration_s']}s") if s["duration_s"] is not None else ""
        det = c("2", f"  {s['detail']}") if s["detail"] else ""
        lines.append(f"  {g} {s['name']}{att}{dur}{det}")
        if s["status"] in ("running", "retry"):
            for it in s["items"]:
                ig = GLYPH.get(it.get("status", "running"), GLYPH["running"])(tick)
                lines.append(c("2", f"      {ig} {it.get('name', '')} {it.get('detail', '')}"))
    return lines


def final_report(st):
    ok = st.result == "pass"
    bar = c("42;30", " PASS ") if ok else c("41;97", " FAIL ")
    w = 62
    print("\n" + "─" * w)
    print(f"{bar}  {st.meta.get('scenario', '?')} · run {st.meta.get('run_id', '')}")
    print("─" * w)
    for s in st.stages:
        g = GLYPH[s["status"]](0)
        dur = f"{s['duration_s']}s" if s["duration_s"] is not None else "-"
        cost = f"${s['cost_usd']:.3f}" if s["cost_usd"] else ""
        att = f" x{s['attempt']}" if s["attempt"] > 1 else ""
        print(f"  {g} {s['name']:<14}{dur:>8}{cost:>9}{att}  {s['detail']}")
    fails = [s for s in st.stages if s["status"] in ("fail", "error")]
    for s in fails:
        print(c("31", f"\n  ✗ {s['name']}: {s['detail'] or 'no detail recorded'}"))
        for it in s["items"]:
            if it.get("status") in ("fail", "error") and it.get("fingerprint"):
                print(c("2", f"      {it['fingerprint']}"))
    t = st.totals
    print("─" * w)
    print(f"  stages {sum(1 for s in st.stages if s['status'] == 'pass')}/{len(st.stages)} passed"
          f" · ${t.get('cost_usd', 0):.3f} · {t.get('duration_s', 0)}s"
          + (f" · {t.get('retries', 0)} retr{'y' if t.get('retries', 0) == 1 else 'ies'}" if t.get("retries") else ""))
    if t.get("reproduce"):
        print(c("2", f"  reproduce: {t['reproduce']}"))
    print("─" * w)


def live_render(st, stop):
    if not TTY:
        return  # non-TTY: event lines are printed by the consumer instead
    tick, prev = 0, 0
    sys.stdout.write("\x1b[?25l")  # hide cursor
    try:
        while not stop.is_set():
            lines = render_frame(st, tick)
            out = ""
            if prev:
                out += f"\x1b[{prev}A"
            out += "".join("\x1b[2K" + l + "\n" for l in lines)
            if prev > len(lines):
                out += ("\x1b[2K\n" * (prev - len(lines))) + f"\x1b[{prev - len(lines)}A"
            sys.stdout.write(out)
            sys.stdout.flush()
            prev = len(lines)
            tick += 1
            time.sleep(0.1)
    finally:
        sys.stdout.write("\x1b[?25h")
        sys.stdout.flush()


def consume(events, st):
    """Apply events; in non-TTY mode also print one line per event."""
    for ev in events:
        st.apply(ev)
        if not TTY:
            k = ev.get("ev")
            if k == "stage_end":
                print(f"{ev.get('status', '?'):>5}  {ev['stage']}  {ev.get('detail', '')}")
            elif k == "run_end":
                print(f"run_end: {ev.get('status')}")
        if st.done:
            break


def run_ui(events):
    st = RunState()
    stop = threading.Event()
    t = threading.Thread(target=live_render, args=(st, stop), daemon=True)
    t.start()
    try:
        consume(events, st)
    finally:
        time.sleep(0.15)
        stop.set()
        t.join(timeout=1)
    final_report(st)
    return 0 if st.result == "pass" else 1


def paced(raw_events, speed):
    """Yield events honoring inter-event `dt` seconds (recorded or synthetic)."""
    for ev in raw_events:
        time.sleep(max(0, ev.get("dt", 0)) / speed)
        yield ev


def demo_events():
    """A synthesized kit full-lane run: the L1 scripted-replay shape, including
    a verifier failure -> fix-agent -> retry, so the interaction is visible
    without running anything real."""
    E = []

    def e(dt, **kw):
        E.append({"dt": dt, **kw})

    stages = ["classify", "grill", "spec", "test-plan", "execute",
              "review-team", "verify", "ship-gate"]
    e(0, ev="run_start", run_id="demo-001", scenario="full-lane (scripted)",
      layer="L1", config={"model": "scripted", "modules": "all"}, stages=stages)
    e(.3, ev="stage_start", stage="classify")
    e(.7, ev="stage_end", stage="classify", status="pass", detail="feature · normal lane", duration_s=0.7)
    e(.2, ev="stage_start", stage="grill")
    e(.5, ev="item", stage="grill", name="scope question", status="pass", detail="answered from brief")
    e(.6, ev="stage_end", stage="grill", status="pass", detail="2 questions resolved", duration_s=1.1)
    e(.2, ev="stage_start", stage="spec")
    e(1.6, ev="stage_end", stage="spec", status="pass", detail="spec + acceptance criteria", duration_s=1.6, cost_usd=.04)
    e(.2, ev="stage_start", stage="test-plan")
    e(1.0, ev="stage_end", stage="test-plan", status="pass", detail="9-case matrix", duration_s=1.0, cost_usd=.02)
    e(.2, ev="stage_start", stage="execute")
    e(.4, ev="item", stage="execute", name="task-1 worker", status="running")
    e(.9, ev="item", stage="execute", name="task-1 worker", status="pass", detail="diff 42 lines")
    e(.3, ev="item", stage="execute", name="task-1 verifier", status="pass", detail="4/4 criteria")
    e(.4, ev="item", stage="execute", name="task-2 worker", status="pass", detail="diff 18 lines")
    e(.5, ev="item", stage="execute", name="task-2 verifier", status="fail",
      fingerprint="FAIL criterion 3: empty input returns 500, expected 400")
    e(.3, ev="retry", stage="execute", attempt=2)
    e(.8, ev="item", stage="execute", name="task-2 fix-agent", status="pass", detail="guard added")
    e(.5, ev="item", stage="execute", name="task-2 verifier", status="pass", detail="4/4 criteria")
    e(.3, ev="stage_end", stage="execute", status="pass",
      detail="2 tasks · 1 retry", duration_s=4.4, cost_usd=.31)
    e(.2, ev="stage_start", stage="review-team")
    e(.6, ev="item", stage="review-team", name="security lens", status="pass", detail="0 findings")
    e(.5, ev="item", stage="review-team", name="architecture lens", status="pass", detail="1 advisory")
    e(.5, ev="item", stage="review-team", name="test-coverage lens", status="pass", detail="0 findings")
    e(.3, ev="stage_end", stage="review-team", status="pass", detail="1 advisory, 0 blocking", duration_s=1.9, cost_usd=.09)
    e(.2, ev="stage_start", stage="verify")
    e(.5, ev="item", stage="verify", name="task-verifier", status="pass")
    e(.5, ev="item", stage="verify", name="integration-verifier", status="pass")
    e(.5, ev="item", stage="verify", name="acceptance-verifier", status="pass", detail="spec criteria met")
    e(.4, ev="stage_end", stage="verify", status="pass", detail="right arm green", duration_s=1.9, cost_usd=.11)
    e(.2, ev="stage_start", stage="ship-gate")
    e(.8, ev="stage_end", stage="ship-gate", status="pass", detail="proof-of-done recorded", duration_s=0.8)
    e(.3, ev="run_end", status="pass",
      totals={"cost_usd": .57, "duration_s": 14, "retries": 1,
              "reproduce": "python3 tui.py demo"})
    return E


def read_jsonl(path):
    return [json.loads(l) for l in Path(path).read_text().splitlines() if l.strip()]


def follow(path, poll=0.2):
    """Tail an events file a real runner is appending to; ends on run_end."""
    pos = 0
    while True:
        p = Path(path)
        if p.exists():
            with p.open() as f:
                f.seek(pos)
                for line in f:
                    if line.strip():
                        ev = json.loads(line)
                        yield ev
                        if ev.get("ev") == "run_end":
                            return
                pos = f.tell()
        time.sleep(poll)


def main():
    ap = argparse.ArgumentParser(prog="bench-tui", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("demo", help="play a synthesized full-lane run")
    d.add_argument("--speed", type=float, default=1.0)
    d.add_argument("--record", help="also write the event stream to this file")
    r = sub.add_parser("replay", help="re-play a recorded events file")
    r.add_argument("file")
    r.add_argument("--speed", type=float, default=1.0)
    w = sub.add_parser("watch", help="follow a live events file")
    w.add_argument("file")
    a = ap.parse_args()

    if a.cmd == "demo":
        evs = demo_events()
        if a.record:
            Path(a.record).write_text("".join(json.dumps(e) + "\n" for e in evs))
        sys.exit(run_ui(paced(evs, a.speed)))
    if a.cmd == "replay":
        sys.exit(run_ui(paced(read_jsonl(a.file), a.speed)))
    if a.cmd == "watch":
        sys.exit(run_ui(follow(a.file)))


if __name__ == "__main__":
    main()
