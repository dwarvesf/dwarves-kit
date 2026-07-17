"""Apple Reminders spoke: osascript JXA, two bulk calls per sync.

Status is binary here (open/completed): completed reads as a `shipped`
proposal; any inactive board state maps to completed=true; reopening a board
row un-completes the reminder.

#tags ride at the END of the reminder TITLE (Han's call: visible where the
Reminders UI styles typed hashtags; the API cannot create native tags at
all). read() strips tag tokens off titles so the planner compares clean
titles; apply() re-appends the tags derived from the row's notes, and
self-heals any title whose tag suffix drifted from its body.
"""

import json
import subprocess
import sys

from sync_core import ACTIVE_STATUSES, extract_tags, strip_tags, title_for


def title_with_tags(title: str, body: str) -> str:
    tags = extract_tags(body or "")
    return f"{title} {' '.join('#' + t for t in tags)}" if tags else title

JXA_READ = """
function run(argv) {
  const app = Application('Reminders');
  const name = argv[0];
  const names = app.lists.name();
  if (names.indexOf(name) === -1) {
    app.lists.push(app.List({name: name}));
  }
  const list = app.lists.byName(name);
  const rems = list.reminders;
  const ids = rems.id(), titles = rems.name(), done = rems.completed(),
        bodies = rems.body();
  const out = [];
  for (let i = 0; i < ids.length; i++)
    out.push({rid: ids[i], title: titles[i], completed: done[i],
              body: bodies[i]});
  return JSON.stringify(out);
}
"""

JXA_APPLY = """
function run(argv) {
  const app = Application('Reminders');
  const plan = JSON.parse(argv[1]);
  const list = app.lists.byName(argv[0]);
  const rems = list.reminders;
  const ids = rems.id();
  const idx = {};
  for (let i = 0; i < ids.length; i++) idx[ids[i]] = i;
  for (const s of plan.setdone)
    if (s.rid in idx) rems[idx[s.rid]].completed = s.done;
  for (const r of plan.rename)
    if (r.rid in idx) rems[idx[r.rid]].name = r.title;
  for (const b of plan.setbody)
    if (b.rid in idx) rems[idx[b.rid]].body = b.body;
  const created = {};
  for (const c of plan.create) {
    const rem = app.Reminder({name: c.title, body: c.body});
    list.reminders.push(rem);
    created[c.key] = rem.id();
  }
  return JSON.stringify({created: created});
}
"""


def _osascript(script: str, *args: str) -> str:
    r = subprocess.run(["osascript", "-l", "JavaScript", "-e", script, *args],
                       capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        err = r.stderr.strip()
        if "-1743" in err or "not allowed" in err.lower():
            sys.exit("osascript is not authorized to control Reminders. "
                     "Grant it in System Settings > Privacy & Security > "
                     "Automation, then re-run.")
        sys.exit(f"osascript failed: {err}")
    return r.stdout.strip()


class RemindersSource:
    name = "reminders"
    sync_fields = True

    def __init__(self, list_name: str = "Backlog", runner=_osascript):
        self.list_name = list_name
        self.runner = runner

    def read(self) -> list[dict]:
        raw = json.loads(self.runner(JXA_READ, self.list_name))
        items = []
        self._read = {}   # rid -> (clean title, body) for apply-time renames
        self._drift = []  # rids whose title tag-suffix != tags in their body
        for r in raw:
            body = r.get("body") or ""
            clean = strip_tags(r["title"]).strip()
            self._read[r["rid"]] = (clean, body)
            if not r["completed"] and r["title"] != title_with_tags(clean, body):
                self._drift.append(r["rid"])
            items.append({"rid": r["rid"], "title": clean,
                          "done": r["completed"], "body": body,
                          "status": None})
        return items

    def apply(self, plan, assigned: dict, rows_after: dict) -> dict:
        adopted = [(rid, assigned[rid]) for rid, _t, _b, _kw in plan.board_add
                   if rid in assigned and assigned[rid] in rows_after]
        read = getattr(self, "_read", {})
        bodies = dict(plan.src_set_body)  # freshest body wins for tag suffix
        # renames: explicit retitles + tag refresh for body changes + drift
        renames: dict[str, str] = {}
        for rid, t in plan.src_set_title:
            renames[rid] = title_with_tags(
                t, bodies.get(rid, read.get(rid, ("", ""))[1]))
        for rid, b in bodies.items():
            if rid not in renames:
                clean = read.get(rid, ("", ""))[0]
                if clean:
                    renames[rid] = title_with_tags(clean, b)
        for rid in getattr(self, "_drift", []):
            if rid not in renames and rid in read:
                renames[rid] = title_with_tags(*read[rid])
        for rid, bid in adopted:
            row = rows_after[bid]
            renames[rid] = title_with_tags(title_for(bid, row.item), row.notes)
        payload = {
            "setdone": [{"rid": rid, "done": kw not in ACTIVE_STATUSES}
                        for rid, kw in plan.src_set_status]
                       + [{"rid": rid, "done": True}
                          for _bid, rid in plan.src_scope_exit],
            "rename": [{"rid": rid, "title": t} for rid, t in renames.items()],
            "setbody": [{"rid": rid, "body": b} for rid, b in plan.src_set_body]
                       + [{"rid": rid, "body": rows_after[bid].notes}
                          for rid, bid in adopted],
            "create": [{"key": bid, "title": title_with_tags(t, b), "body": b}
                       for bid, t, b, _kw in plan.src_create],
        }
        if not any(payload.values()):
            return {}
        drifted = [r for r in getattr(self, "_drift", []) if r in renames]
        if drifted:
            print(f"  · note      reminders: refreshed tag suffix on "
                  f"{len(drifted)} titles")
        out = json.loads(self.runner(JXA_APPLY, self.list_name,
                                     json.dumps(payload)))
        return out.get("created", {})
