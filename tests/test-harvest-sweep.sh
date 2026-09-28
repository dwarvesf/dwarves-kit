#!/bin/bash
# test-harvest-sweep.sh -- tests for the harvest sweep (SPEC-357) and the shared
# stager it reuses from hooks/harvest.py. The extractor is always a stub; nothing
# here touches real transcripts, real launchd, or a real model.
#
# Run: bash tests/test-harvest-sweep.sh
# Exit 0 = all tests pass. Exit 1 = failures found.

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TD="$(mktemp -d "${TMPDIR:-/tmp}/harvest-sweep-test.XXXXXX")"
trap 'rm -rf "${TD:?}"' EXIT

export HARVEST_STATE_DIR="$TD/state"
export HARVEST_SWEEP_CLAUDE_ROOT="$TD/claude-root"
export HARVEST_SWEEP_DEVIN_DB="$TD/devin.db"
export HARVEST_SWEEP_LAUNCH_RECORD="$TD/launch-record"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local NAME="$1" EXPECTED="$2" ACTUAL="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo -e "  ${GREEN}PASS${NC} $NAME"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $NAME (expected '$EXPECTED', got '$ACTUAL')"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
echo "=== T1 shared stager ==="

# One in-process run prints one KEY=VALUE line per check; the bash side asserts each.
T1_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" python3 - <<'PY'
import importlib.util, os
spec = importlib.util.spec_from_file_location("harvest", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest.py"))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

ledger = os.path.join(os.environ["TD"], "t1", "ledger.md")
lines = lambda: open(ledger).read().splitlines() if os.path.exists(ledger) else []

fresh = h._stage_candidates(ledger, [], [
    {"item": "Alpha Thing", "kind": "insight", "home": "til"},
    {"item": "alpha thing", "kind": "insight", "home": "til"},
    {"item": "Beta", "kind": "bogus-kind", "home": "bogus-home"},
    "not a dict",
])
print("fresh_items=" + ",".join(r["item"] for r in fresh))
print("batch_dedup=" + str(len(fresh)))
beta = [r for r in fresh if r["item"] == "beta"][0]
print("beta_map=%s/%s" % (beta["kind"], beta["home"]))
print("header_count=" + str(sum(1 for l in lines() if l.startswith("| date |"))))
print("row_count=" + str(sum(1 for l in lines() if l.endswith("| queued |"))))

again = h._stage_candidates(ledger, [], [{"item": "Alpha Thing"}, {"item": "Gamma"}])
print("ledger_dedup=" + ",".join(r["item"] for r in again))
print("header_count_after=" + str(sum(1 for l in lines() if l.startswith("| date |"))))

before = open(ledger).read()
none = h._stage_candidates(ledger, [], [{"item": "Alpha Thing"}, {"item": "Gamma"}])
print("all_known=" + repr(none))
print("all_known_unchanged=" + str(open(ledger).read() == before))
PY
)
get() { printf '%s\n' "$T1_OUT" | sed -n "s/^$1=//p"; }

assert_eq "T1: returns only the fresh rows" "alpha-thing,beta" "$(get fresh_items)"
assert_eq "T1: dedups exact slugs within the batch" "2" "$(get batch_dedup)"
assert_eq "T1: unknown kind/home map to insight/drop" "insight/drop" "$(get beta_map)"
assert_eq "T1: writes the ledger header once" "1" "$(get header_count)"
assert_eq "T1: appends one queued row per fresh item" "2" "$(get row_count)"
assert_eq "T1: dedups against the existing ledger" "gamma" "$(get ledger_dedup)"
assert_eq "T1: header stays single after a second append" "1" "$(get header_count_after)"
assert_eq "T1: all-known batch returns []" "[]" "$(get all_known)"
assert_eq "T1: all-known batch writes nothing" "True" "$(get all_known_unchanged)"

# ============================================================
echo ""
echo "=== T2 claude adapter ==="

# Build the claude root from the fixture tree; the self-harvest fixture's cwd is
# pointed under this run's state dir. Mtimes are set here so the fixtures stay static.
mkdir -p "$HARVEST_SWEEP_CLAUDE_ROOT"
command cp -R "$KIT_DIR/tests/fixtures/harvest-sweep/claude-projects/." "$HARVEST_SWEEP_CLAUDE_ROOT/"
sed -i.bak "s#__STATE__#$HARVEST_STATE_DIR#" "$HARVEST_SWEEP_CLAUDE_ROOT/proj-b/selfharvest-1.jsonl"
mv -f "$HARVEST_SWEEP_CLAUDE_ROOT/proj-b/selfharvest-1.jsonl.bak" "$TD/selfharvest.bak"

T2_OUT=$(KIT_DIR="$KIT_DIR" python3 - <<'PY'
import importlib.util, os
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
root = os.environ["HARVEST_SWEEP_CLAUDE_ROOT"]
P = lambda k, v: print("%s=%s" % (k, v))

# mtimes: the subagent file is the newest thing under lead-1
lead = os.path.join(root, "proj-a", "lead-1.jsonl")
sub = os.path.join(root, "proj-a", "lead-1", "subagents", "agent-b2.jsonl")
os.utime(lead, (1000, 1000))
os.utime(os.path.join(root, "proj-a", "lead-1", "subagents", "agent-a1.jsonl"), (1500, 1500))
os.utime(sub, (2000, 2000))
os.utime(os.path.join(root, "proj-a", "trivial-1.jsonl"), (500, 500))
os.utime(os.path.join(root, "proj-b", "selfharvest-1.jsonl"), (300, 300))

items = hs.list_claude_sessions()
P("enum_ids", ",".join(i["session_id"] for i in items))
by = {i["session_id"]: i for i in items}
P("enum_last_activity", by["lead-1"]["last_activity"])
P("enum_subs", len(by["lead-1"]["subagent_paths"]))
P("enum_plain_subs", len(by["trivial-1"]["subagent_paths"]))

t = hs.load_claude(by["lead-1"])
P("shape_keys", ",".join(sorted(t)))
P("shape_source", t["source"])
P("shape_lead_null", t["lead_session_id"] is None)
P("shape_cwd", t["cwd"])
P("shape_ts_numeric", all(isinstance(m["ts"], float) for m in t["messages"]))
P("shape_msg_keys", ",".join(sorted(t["messages"][0])))
P("shape_started", t["started"] == t["messages"][0]["ts"])
P("shape_last_activity", t["last_activity"])
P("shape_roles", ",".join(sorted({m["role"] for m in t["messages"]})))

# order of entries: L 00, a1 05, L 10 x2 (text, tool), a1 15, b2 25, L 30, a1 35 (tool), L 40, b2 45, L 50
P("order", "|".join(m["text"][:12] for m in t["messages"]))
P("ts_sorted", [m["ts"] for m in t["messages"]] == sorted(m["ts"] for m in t["messages"]))
P("sub_flags", "".join("S" if m["sub"] else "L" for m in t["messages"]))
P("sub_prefix_all", all(m["text"].startswith("subagent: ") == m["sub"] for m in t["messages"]))
tools = [m for m in t["messages"] if m["role"] == "tool"]
P("tool_texts", "|".join(m["text"] for m in tools))
P("tool_result_dropped", not any("def test_login" in m["text"] for m in t["messages"]))
P("string_prompt_kept", any(m["text"] == "Fix the flaky login test" for m in t["messages"]))

full = hs.render(t, 0, 12000)
P("render_first", full.splitlines()[0])
P("render_lines", len(full.splitlines()))
P("render_sub_line", "assistant: subagent: Found 3 fixtures." in full.splitlines())
P("render_tool_line", "tool: Read {\"file_path\": \"/work/app/login_test.py\"}" in full.splitlines())

# delta: a subagent entry appended later renders alone once after_ts is the old newest ts
old_newest = hs.newest_ts(t)
P("newest_is_last", old_newest == t["messages"][-1]["ts"])
with open(sub, "a") as f:
    f.write('{"type":"assistant","timestamp":"2026-09-01T10:05:00.000Z","cwd":"/work/app","message":{"role":"assistant","content":[{"type":"text","text":"Late subagent note."}]}}\n')
os.utime(sub, (3000, 3000))
t2 = hs.load_claude({i["session_id"]: i for i in hs.list_claude_sessions()}["lead-1"])
P("delta_render", hs.render(t2, old_newest, 12000))
P("delta_last_activity", t2["last_activity"])
P("delta_empty_when_caught_up", hs.render(t2, hs.newest_ts(t2), 12000) == "")

# 60/40: a huge newest subagent message must not push the lead out
def msg(i, sub, n):
    return {"role": "assistant", "text": ("x" * n), "ts": float(i), "sub": sub}
big = {"messages": [msg(i, False, 100) for i in range(5)] + [msg(10, True, 5000)]}
r = hs.render(big, -1, 1000)
P("share_lead_kept", sum(1 for l in r.splitlines() if len(l) == 111))
P("share_total_capped", len(r) <= 1000)
P("share_sub_tail", len(r.splitlines()[-1]) == 400)
# and the reverse: lead text huge, subagent still keeps its 40%
big2 = {"messages": [msg(0, True, 100), msg(1, True, 100), msg(10, False, 5000)]}
r2 = hs.render(big2, -1, 1000)
P("share_sub_kept_vs_huge_lead", sum(1 for l in r2.splitlines() if len(l) == 111))

# predicates
tri = hs.load_claude(by["trivial-1"])
P("trivial_small", hs.is_trivial(tri))
P("trivial_lead1", hs.is_trivial(t))
os.environ["HARVEST_SWEEP_MIN_MESSAGES"] = "2"
P("trivial_knob", hs.is_trivial(tri))
del os.environ["HARVEST_SWEEP_MIN_MESSAGES"]
sh = hs.load_claude(by["selfharvest-1"])
P("selfharvest_state", hs.is_self_harvest(sh))
P("selfharvest_other", hs.is_self_harvest(t))
P("selfharvest_sibling_prefix", hs.is_self_harvest(dict(t, cwd=os.environ["HARVEST_STATE_DIR"] + "-other")))
PY
)
g() { printf '%s\n' "$T2_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC1: enumerates lead sessions only, oldest activity first" "selfharvest-1,trivial-1,lead-1" "$(g enum_ids)"
assert_eq "AC1: last_activity is the max mtime over lead and subagent files" "2000" "$(g enum_last_activity)"
assert_eq "AC1: folds in every subagent file" "2" "$(g enum_subs)"
assert_eq "AC1: a lead without subagents lists none" "0" "$(g enum_plain_subs)"
assert_eq "AC1: normalized transcript keys" "cwd,last_activity,lead_session_id,messages,session_id,source,started" "$(g shape_keys)"
assert_eq "AC1: source is claude" "claude" "$(g shape_source)"
assert_eq "AC1: lead_session_id is null for claude" "True" "$(g shape_lead_null)"
assert_eq "AC1: cwd comes from the transcript entries" "/work/app" "$(g shape_cwd)"
assert_eq "AC1: ts is epoch seconds" "True" "$(g shape_ts_numeric)"
assert_eq "AC1: message keys" "role,sub,text,ts" "$(g shape_msg_keys)"
assert_eq "AC1: started is the first message ts" "True" "$(g shape_started)"
assert_eq "AC1: transcript last_activity is the stat max" "2000" "$(g shape_last_activity)"
assert_eq "AC1: roles kept are user, assistant, tool" "assistant,tool,user" "$(g shape_roles)"
assert_eq "AC1: lead and subagent entries interleave by ts" "Fix the flak|subagent: Se|Looking at t|Read {\"file_|subagent: Fo|subagent: Ch|Found a race|subagent: Gr|Go ahead and|subagent: CI|Fixed with a" "$(g order)"
assert_eq "AC1: messages are in ts order" "True" "$(g ts_sorted)"
assert_eq "AC1: sub marks follow the subagent files" "LSLLSSLSLSL" "$(g sub_flags)"
assert_eq "AC1: the subagent: prefix appears exactly on sub messages" "True" "$(g sub_prefix_all)"
assert_eq "AC1: tool_use renders as name plus input, subagent tool prefixed" 'Read {"file_path": "/work/app/login_test.py"}|subagent: Grep {"pattern": "login"}' "$(g tool_texts)"
assert_eq "AC1: tool_result blocks are dropped" "True" "$(g tool_result_dropped)"
assert_eq "AC1: a string-content user prompt is kept" "True" "$(g string_prompt_kept)"
assert_eq "AC1: render starts with the oldest message as role: text" "user: Fix the flaky login test" "$(g render_first)"
assert_eq "AC1: render emits one line per kept message" "11" "$(g render_lines)"
assert_eq "AC1: a subagent line is role: subagent: text" "True" "$(g render_sub_line)"
assert_eq "AC1: a tool line is tool: name input" "True" "$(g render_tool_line)"
assert_eq "AC1: newest_ts is the newest kept entry" "True" "$(g newest_is_last)"
assert_eq "AC1: a later subagent entry renders alone after the old last_ts" "assistant: subagent: Late subagent note." "$(g delta_render)"
assert_eq "AC1: the appended subagent file moves last_activity" "3000" "$(g delta_last_activity)"
assert_eq "AC1: a render caught up to newest_ts is empty" "True" "$(g delta_empty_when_caught_up)"
assert_eq "AC1: the lead keeps its 60% share when subagent text is huge" "5" "$(g share_lead_kept)"
assert_eq "AC1: the render stays within max_chars" "True" "$(g share_total_capped)"
assert_eq "AC1: the subagent share keeps a tail of the huge message" "True" "$(g share_sub_tail)"
assert_eq "AC1: subagents keep their 40% share when the lead text is huge" "2" "$(g share_sub_kept_vs_huge_lead)"
assert_eq "AC1: a 2-message session is trivial" "True" "$(g trivial_small)"
assert_eq "AC1: a lead with subagents past the minimum is not trivial" "False" "$(g trivial_lead1)"
assert_eq "AC1: HARVEST_SWEEP_MIN_MESSAGES moves the trivial line" "False" "$(g trivial_knob)"
assert_eq "AC1: cwd under the state dir is self-harvest" "True" "$(g selfharvest_state)"
assert_eq "AC1: an ordinary cwd is not self-harvest" "False" "$(g selfharvest_other)"
assert_eq "AC1: a sibling dir sharing the state dir's prefix is not self-harvest" "False" "$(g selfharvest_sibling_prefix)"

# ============================================================
echo ""
echo "=== T3 devin adapter ==="

bash "$KIT_DIR/tests/fixtures/harvest-sweep/make-devin-db.sh" "$HARVEST_SWEEP_DEVIN_DB"
bash "$KIT_DIR/tests/fixtures/harvest-sweep/make-devin-db.sh" "$TD/drift.db" --rename-column

T3_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" python3 - <<'PY'
import importlib.util, os
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
P = lambda k, v: print("%s=%s" % (k, v))

items = hs.list_devin_sessions()
by = {i["session_id"]: i for i in items}
P("enum_ids", ",".join(i["session_id"] for i in items))
P("enum_last_activity", by["s-main"]["last_activity"])
P("hidden_flags", ",".join("%s:%s" % (i["session_id"], hs.is_hidden(i)) for i in items))

t = hs.load_devin(by["s-main"])
P("shape_keys", ",".join(sorted(t)))
P("shape_source", t["source"])
P("shape_lead_null", t["lead_session_id"] is None)
P("shape_cwd", t["cwd"])
P("shape_started", t["started"])
P("shape_last_activity", t["last_activity"])
P("shape_msg_keys", ",".join(sorted(t["messages"][0])))
P("roles", ",".join(m["role"] for m in t["messages"]))
P("system_absent", not any("INJECTED" in m["text"] for m in t["messages"]))
P("chain_order", "|".join(m["text"][:12] for m in t["messages"]))
P("branch_absent", not any("ABANDONED" in m["text"] for m in t["messages"]))
P("ts_sorted", [m["ts"] for m in t["messages"]] == sorted(m["ts"] for m in t["messages"]))
P("newest", hs.newest_ts(t))
P("render", hs.render(t, 1002, 1000).replace("\n", "|"))

n = hs.load_devin(by["s-null"])
P("null_order", "|".join(m["text"] for m in n["messages"]))
P("null_cwd", n["cwd"])
P("null_system_absent", not any("INJECTED" in m["text"] for m in n["messages"]))
P("null_trivial", hs.is_trivial(n))

# a dangling main_chain_id falls back like a null one
dangling = dict(by["s-null"], main_chain_id=99)
P("dangling_fallback", len(hs.load_devin(dangling)["messages"]))

# drift and missing file: failure objects, no exception, claude adapter unaffected
os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(os.environ["TD"], "drift.db")
f = hs.list_devin_sessions()
P("drift_type", type(f).__name__)
P("drift_class", f.error_class)
P("drift_state_row", f.state_row().startswith("STATE devin: OperationalError: ") and "last_activity_at" in f.state_row())
P("drift_claude_ok", isinstance(hs.list_claude_sessions(), list) and len(hs.list_claude_sessions()) == 3)
os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(os.environ["TD"], "missing.db")
m = hs.list_devin_sessions()
P("missing_type", type(m).__name__)
P("missing_no_create", not os.path.exists(os.environ["HARVEST_SWEEP_DEVIN_DB"]))
P("load_fail_type", type(hs.load_devin(by["s-main"])).__name__)

# source_fail bookkeeping
c = {}
P("fail_counts", ",".join(str(hs.source_fail_update(c, "devin", True)) for _ in range(3)))
P("tripped_at_three", hs.source_fail_tripped(c, "devin"))
P("other_source_untouched", hs.source_fail_tripped(c, "claude"))
hs.source_fail_update(c, "devin", False)
P("reset_by_good_read", c["source_fail"]["devin"] == 0 and not hs.source_fail_tripped(c, "devin"))
c2 = {}
hs.source_fail_update(c2, "devin", True); hs.source_fail_update(c2, "devin", True)
P("two_not_tripped", hs.source_fail_tripped(c2, "devin"))
os.environ["HARVEST_SWEEP_SOURCE_FAIL_RUNS"] = "2"
P("knob_trips_at_two", hs.source_fail_tripped(c2, "devin"))
PY
)
d() { printf '%s\n' "$T3_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC1: devin lists every session, oldest activity first" "s-main,s-null,s-hidden" "$(d enum_ids)"
assert_eq "AC1: last_activity comes from last_activity_at" "1900" "$(d enum_last_activity)"
assert_eq "AC26: hidden = 1 is flagged, visible sessions are not" "s-main:False,s-null:False,s-hidden:True" "$(d hidden_flags)"
assert_eq "AC1: devin transcript keys match the claude shape" "cwd,last_activity,lead_session_id,messages,session_id,source,started" "$(d shape_keys)"
assert_eq "AC1: source is devin" "devin" "$(d shape_source)"
assert_eq "AC1: lead_session_id starts null" "True" "$(d shape_lead_null)"
assert_eq "AC26: cwd comes from working_directory" "/work/app" "$(d shape_cwd)"
assert_eq "AC1: started is sessions.created_at" "1000.0" "$(d shape_started)"
assert_eq "AC1: transcript last_activity is last_activity_at" "1900" "$(d shape_last_activity)"
assert_eq "AC1: message keys" "role,sub,text,ts" "$(d shape_msg_keys)"
assert_eq "AC1: roles kept are user, assistant, tool (a tool call adds a tool line)" "user,assistant,tool,tool,assistant" "$(d roles)"
assert_eq "AC1: system rows are absent from messages" "True" "$(d system_absent)"
assert_eq "AC1: the main chain walks root first and lists tool_calls names" "Fix the flak|Reading the |read_file|def test_log|Fixed with a" "$(d chain_order)"
assert_eq "AC1: nodes off the main chain are excluded" "True" "$(d branch_absent)"
assert_eq "AC1: messages are in ts order" "True" "$(d ts_sorted)"
assert_eq "AC1: newest_ts is the newest kept message" "1007.0" "$(d newest)"
assert_eq "AC1: render takes only messages after last_ts" "assistant: Reading the test.|tool: read_file|tool: def test_login(): pass|assistant: Fixed with a retry." "$(d render)"
assert_eq "AC1: a null main_chain_id falls back to all nodes by node_id" "Summarize the repo|It is a CLI.|Thanks|Done." "$(d null_order)"
assert_eq "AC26: fallback session cwd from working_directory" "/work/other" "$(d null_cwd)"
assert_eq "AC1: system rows absent in the fallback too" "True" "$(d null_system_absent)"
assert_eq "AC1: a 4-message devin session is trivial at the default line" "True" "$(d null_trivial)"
assert_eq "AC1: a dangling main_chain_id falls back like null" "4" "$(d dangling_fallback)"
assert_eq "AC14: a renamed column yields a failure object, not an exception" "SourceFailure" "$(d drift_type)"
assert_eq "AC14: the failure carries the sqlite error class" "OperationalError" "$(d drift_class)"
assert_eq "AC14: the STATE row names the source, the class and the missing column" "True" "$(d drift_state_row)"
assert_eq "AC14: the claude source still lists its sessions" "True" "$(d drift_claude_ok)"
assert_eq "AC14: a missing db is a failure object" "SourceFailure" "$(d missing_type)"
assert_eq "AC14: opening a missing db read-only does not create it" "True" "$(d missing_no_create)"
assert_eq "AC14: a failed session load is a failure object" "SourceFailure" "$(d load_fail_type)"
assert_eq "AC14: source_fail counts consecutive failed reads" "1,2,3" "$(d fail_counts)"
assert_eq "AC14: three consecutive failures trip the helper" "True" "$(d tripped_at_three)"
assert_eq "AC14: another source is untouched" "False" "$(d other_source_untouched)"
assert_eq "AC14: one good read resets the count" "True" "$(d reset_by_good_read)"
assert_eq "AC14: two failures do not trip the default" "False" "$(d two_not_tripped)"
assert_eq "AC14: HARVEST_SWEEP_SOURCE_FAIL_RUNS moves the line" "True" "$(d knob_trips_at_two)"

# ============================================================
echo ""
echo "=== T4 launch-record attribution ==="

T4_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" python3 - 2>/dev/null <<'PY'
import datetime, importlib.util, os
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
P = lambda k, v: print("%s=%s" % (k, v))

fixture = os.path.join(os.environ["KIT_DIR"], "tests", "fixtures", "harvest-sweep", "launches.jsonl")
os.environ["HARVEST_SWEEP_LAUNCH_RECORD"] = fixture
records = hs.load_launch_records()
P("records_loaded", len(records))

def session(first, started="2026-09-20T10:05:30Z", source="devin"):
    return {"source": source, "session_id": "s1", "lead_session_id": None, "cwd": "/work/app",
            "started": datetime.datetime.fromisoformat(started.replace("Z", "+00:00")).timestamp(),
            "last_activity": 0,
            "messages": [{"role": "assistant", "text": "hi", "ts": 0, "sub": False},
                         {"role": "user", "text": first, "ts": 0, "sub": False}]}

t = session("Read the brief at /w/briefs/beta.md and go.")
P("brief_match", hs.attribute(t, records))
P("brief_match_set", t["lead_session_id"])
P("brief_copy_match", hs.attribute(session("Task: /w/copies/beta-1.md"), records))
# alpha.md is named by three records (old, near, claude): nearest ts to started wins
P("nearest_ts", hs.attribute(session("see /w/briefs/alpha.md"), records))
P("nearest_ts_early", hs.attribute(session("see /w/briefs/alpha.md", "2026-09-20T09:59:00Z"), records))
# the claude record has the exact ts 10:04 for this start, and must still lose
P("non_devin_ignored", hs.attribute(session("see /w/briefs/alpha.md", "2026-09-20T10:04:00Z"), records))
P("claude_session_untouched", hs.attribute(session("see /w/briefs/alpha.md", source="claude"), records))
P("no_match_null", hs.attribute(session("no brief path here"), records))
P("no_match_field", session("x")["lead_session_id"])
P("no_user_message", hs.attribute(dict(session("x"), messages=[]), records))
P("empty_records", hs.attribute(session("see /w/briefs/alpha.md"), []))

os.environ["HARVEST_SWEEP_LAUNCH_RECORD"] = os.path.join(os.environ["TD"], "no-such-launches.jsonl")
P("missing_file", hs.load_launch_records())
P("missing_file_null", hs.attribute(session("see /w/briefs/alpha.md"), hs.load_launch_records()))

bad = os.path.join(os.environ["TD"], "mixed.jsonl")
open(bad, "w").write('{oops\n\n[1, 2]\n{"ts": "2026-09-20T10:00:00Z", "agent": "devin", "brief": "/w/x.md", "lead_session": "lead-x"}\n')
os.environ["HARVEST_SWEEP_LAUNCH_RECORD"] = bad
P("malformed_skipped", hs.attribute(session("run /w/x.md"), hs.load_launch_records()))
PY
)
a() { printf '%s\n' "$T4_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC1 attribution: the malformed line is skipped, four records load" "4" "$(a records_loaded)"
assert_eq "AC1 attribution: a brief path in the first user message gives the lead session" "lead-beta" "$(a brief_match)"
assert_eq "AC1 attribution: the session's lead_session_id takes it" "lead-beta" "$(a brief_match_set)"
assert_eq "AC1 attribution: a brief_copy path matches too" "lead-beta" "$(a brief_copy_match)"
assert_eq "AC1 attribution: nearest ts to started wins among several matches" "lead-near" "$(a nearest_ts)"
assert_eq "AC1 attribution: nearest ts picks the older record when started is early" "lead-old" "$(a nearest_ts_early)"
assert_eq "AC1 attribution: a non-devin record with the same brief is ignored" "lead-near" "$(a non_devin_ignored)"
assert_eq "AC1 attribution: a claude session is never attributed" "None" "$(a claude_session_untouched)"
assert_eq "AC1 attribution: no match stays null" "None" "$(a no_match_null)"
assert_eq "AC1 attribution: no match leaves the field null" "None" "$(a no_match_field)"
assert_eq "AC1 attribution: a session with no user message stays null" "None" "$(a no_user_message)"
assert_eq "AC1 attribution: no records stays null" "None" "$(a empty_records)"
assert_eq "AC1 attribution: a missing record file loads as no records" "[]" "$(a missing_file)"
assert_eq "AC1 attribution: a missing record file leaves null" "None" "$(a missing_file_null)"
assert_eq "AC1 attribution: a malformed line skips that line only" "lead-x" "$(a malformed_skipped)"

# ============================================================
echo ""
echo "=== T5a selection and cursor ==="

# Devin fixture for the sweep scenarios: last_activity_at is set relative to the pinned clock.
T5_NOW=2000000000
bash "$KIT_DIR/tests/fixtures/harvest-sweep/make-devin-db.sh" "$TD/t5-devin.db"
sqlite3 "$TD/t5-devin.db" "UPDATE sessions SET last_activity_at = $((T5_NOW - 18000)) WHERE id = 's-main'; UPDATE sessions SET last_activity_at = $((T5_NOW - 14400)) WHERE id = 's-null'; UPDATE sessions SET last_activity_at = $((T5_NOW - 10800)) WHERE id = 's-hidden';"
printf '%s\n' '{"agent":"devin","brief":"Fix the flaky login test","lead_session":"lead-z","ts":"2033-05-18T03:00:00Z"}' > "$TD/t5-launch.jsonl"

T5_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import datetime, importlib.util, json, os, shutil
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD, NOW = os.environ["TD"], int(os.environ["T5_NOW"])
P = lambda k, v: print("%s=%s" % (k, v))
scenario_n = [0]

def scenario(devin=False, now=NOW):
    """Fresh state dir and claude root per scenario; returns (state dir, claude root)."""
    scenario_n[0] += 1
    base = os.path.join(TD, "t5-s%d" % scenario_n[0])
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base, "claude")
    os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(TD, "t5-devin.db") if devin else os.path.join(base, "none.db")
    os.environ["HARVEST_SWEEP_NOW"] = str(now)
    return os.environ["HARVEST_STATE_DIR"], os.environ["HARVEST_SWEEP_CLAUDE_ROOT"]

iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def mk(root, sid, la, n=6, cwd="/w/x", tag=""):
    """A claude lead session of n messages ending just before `la`, mtime = la."""
    d = os.path.join(root, "p")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": cwd,
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s%s msg %d" % (sid, tag, k)}]}}) + "\n")
    os.utime(path, (la, la))
    return path

def cursor():
    with open(hs._cursor_path()) as fh:
        return json.load(fh)

def stub(log, fail=()):
    def process(t, text):
        log.append((t["session_id"], text))
        return t["session_id"] not in fail
    return process

# ---- AC6: bounds. 25 leads plus 10 trivial, cap 20 ----
state, root = scenario()
for k in range(25):
    mk(root, "lead%02d" % k, NOW - 36000 + k * 60)
for k in range(10):
    mk(root, "triv%02d" % k, NOW - 36000 + k * 60 + 30, n=2)
log = []
r1 = hs.run_selection(stub(log), schedule_hours=24, max_sessions=20)["claude"]
P("ac6_run1_processed", len(r1["processed"]))
P("ac6_run1_trivial_done", len(r1["filtered"]))
P("ac6_run1_deferred", len(r1["deferred"]))
r2 = hs.run_selection(stub(log), schedule_hours=24, max_sessions=20)["claude"]
P("ac6_run2_processed", len(r2["processed"]))
r3 = hs.run_selection(stub(log), schedule_hours=24, max_sessions=20)["claude"]
P("ac6_run3_processed", len(r3["processed"]))
P("ac6_trivial_never_processed", not any(s.startswith("triv") for s, _ in log))
P("ac6_keys", ",".join(sorted(cursor()["claude"])))

# ---- AC25: 50 leads across a 48h outage, three runs capped at 20 ----
state, root = scenario()
las = {}
for k in range(50):
    sid = "out%02d" % k
    las[sid] = NOW - 172800 + k * 3400
    mk(root, sid, las[sid])
log, sizes, marked_unprocessed = [], [], 0
for _ in range(3):
    n0 = len(log)
    hs.run_selection(stub(log), schedule_hours=50, max_sessions=20)
    sizes.append(len(log) - n0)
    seen_so_far = {s for s, _ in log}
    marked_unprocessed += len(set(cursor()["claude"]["done"]) - seen_so_far)
ids = [s for s, _ in log]
P("ac25_sizes", ",".join(map(str, sizes)))
P("ac25_oldest_first", ids == sorted(las, key=lambda s: las[s]))
P("ac25_each_once", len(ids) == len(set(ids)) == 50)
P("ac25_none_done_unprocessed", marked_unprocessed)
P("ac25_hwm_at_newest", cursor()["claude"]["hwm"] == max(las.values()))

# ---- quiet window ----
state, root = scenario()
mk(root, "old", NOW - 7200)
mk(root, "busy", NOW - 600)
log = []
r = hs.run_selection(stub(log), schedule_hours=6)["claude"]
P("quiet_first_run", ",".join(r["processed"]))
P("quiet_hwm_holds", cursor()["claude"]["hwm"] == NOW - 7200)
os.environ["HARVEST_SWEEP_NOW"] = str(NOW + 1800)
r = hs.run_selection(stub(log), schedule_hours=6)["claude"]
P("quiet_second_run", ",".join(r["processed"]))

# ---- tie on last_activity: (last_activity, id) order, cap splits the tie ----
state, root = scenario()
for sid in ("tie-b", "tie-a", "tie-c"):
    mk(root, sid, NOW - 7200)
log = []
r = hs.run_selection(stub(log), schedule_hours=6, max_sessions=2)["claude"]
P("tie_run1", ",".join(r["processed"]))
r = hs.run_selection(stub(log), schedule_hours=6, max_sessions=2)["claude"]
P("tie_run2", ",".join(r["processed"]))

# ---- a failing session blocks the hwm; later sessions still complete ----
state, root = scenario()
for k, sid in enumerate(("f1", "f2", "f3")):
    mk(root, sid, NOW - 9000 + k * 600)
log = []
r = hs.run_selection(stub(log, fail={"f1"}), schedule_hours=6)["claude"]
c = cursor()["claude"]
P("fail_processed", ",".join(r["processed"]))
P("fail_failed", ",".join(r["failed"]))
P("fail_hwm_held", c["hwm"] == NOW - 21600)
P("fail_not_done", "f1" not in c["done"])
P("fail_later_done", ",".join(sorted(c["done"])))
r = hs.run_selection(stub(log), schedule_hours=6)["claude"]
P("fail_retry", ",".join(r["processed"]))
P("fail_hwm_after", cursor()["claude"]["hwm"] == NOW - 9000 + 1200)

# ---- AC20: seen{} survives the done{} prune by hwm ----
state, root = scenario()
for k, sid in enumerate(("s1", "s2", "s3")):
    mk(root, sid, NOW - 9000 + k * 600)
hs.run_selection(stub([]), schedule_hours=6)
c = cursor()["claude"]
P("ac20_done_pruned", "s1" not in c["done"] and "s2" not in c["done"])
P("ac20_seen_kept", ",".join(sorted(c["seen"])))
P("ac20_seen_shape", sorted(c["seen"]["s1"]) == ["last_ts", "ts"] and c["seen"]["s1"]["ts"] == NOW)

# ---- resumed session: re-selected, rendered as a delta from seen{id}.last_ts ----
state, root = scenario()
mk(root, "res", NOW - 14400)
log = []
hs.run_selection(stub(log), schedule_hours=6)
first_text = log[0][1]
old_last = cursor()["claude"]["seen"]["res"]["last_ts"]
mk_path = os.path.join(root, "p", "res.jsonl")
with open(mk_path, "a") as fh:
    for k in range(2):
        fh.write(json.dumps({"type": "user", "cwd": "/w/x", "timestamp": iso(NOW - 3600 + k * 10),
                             "message": {"content": [{"type": "text", "text": "resumed new %d" % k}]}}) + "\n")
os.utime(mk_path, (NOW - 3500, NOW - 3500))
log = []
r = hs.run_selection(stub(log), schedule_hours=6)["claude"]
P("resume_first_full", "res msg 0" in first_text)
P("resume_reselected", ",".join(r["processed"]))
P("resume_delta_only", log[0][1] == "user: resumed new 0\nuser: resumed new 1")
P("resume_seen_moved", cursor()["claude"]["seen"]["res"]["last_ts"] > old_last)

# ---- AC1: a self-harvest cwd is never processed, is marked done, and the hwm passes it ----
state, root = scenario()
mk(root, "normal", NOW - 9000)
mk(root, "selfh", NOW - 7200, cwd=os.path.join(state, "sweep"))
log = []
r = hs.run_selection(stub(log), schedule_hours=6)["claude"]
c = cursor()["claude"]
P("ac1_selfh_processed", ",".join(s for s, _ in log))
P("ac1_selfh_filtered", ",".join(r["filtered"]))
P("ac1_selfh_hwm_passed", c["hwm"] == NOW - 7200)

# ---- AC26: devin hidden = 1 is never processed, is marked done, and the hwm passes it ----
state, root = scenario(devin=True)
os.environ["HARVEST_SWEEP_MIN_MESSAGES"] = "2"
os.environ["HARVEST_SWEEP_LAUNCH_RECORD"] = os.path.join(TD, "t5-launch.jsonl")
log, leads = [], {}
def devin_stub(t, text):
    log.append(t["session_id"])
    leads[t["session_id"]] = t["lead_session_id"]
    return True
r = hs.run_selection(devin_stub, schedule_hours=6)["devin"]
c = cursor()["devin"]
del os.environ["HARVEST_SWEEP_MIN_MESSAGES"]
P("ac26_processed", ",".join(log))
P("ac26_hidden_not_processed", "s-hidden" not in log)
P("ac26_hidden_done", c["done"].get("s-hidden") == NOW - 10800)
P("ac26_hwm_passed", c["hwm"] == NOW - 10800)
P("ac26_attributed", leads.get("s-main"))
P("ac26_unattributed", leads.get("s-null"))

# ---- cursor.json is atomic ----
state, root = scenario()
for k, sid in enumerate(("a1", "a2", "a3")):
    mk(root, sid, NOW - 9000 + k * 600)
def crashing(t, text):
    if t["session_id"] == "a2":
        raise RuntimeError("simulated crash")
    return True
try:
    hs.run_selection(crashing, schedule_hours=6)
except RuntimeError:
    pass
c = cursor()["claude"]
P("atomic_crash_between", "a1" in c["done"] or c["hwm"] == NOW - 9000)
P("atomic_a2_not_done", "a2" not in c["done"])
before = open(hs._cursor_path()).read()
real_replace = os.replace
def broken_replace(a, b):
    raise OSError("simulated crash mid-write")
os.replace = broken_replace
try:
    hs.run_selection(stub([]), schedule_hours=6)
except OSError:
    pass
finally:
    os.replace = real_replace
P("atomic_file_intact", open(hs._cursor_path()).read() == before)
P("atomic_parses", isinstance(json.loads(before), dict))
P("clock_env", hs._now() == float(os.environ["HARVEST_SWEEP_NOW"]))
PY
)
t5() { printf '%s\n' "$T5_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC6: run 1 processes 20 of 25 leads" "20" "$(t5 ac6_run1_processed)"
assert_eq "AC6: run 1 marks the 10 trivial sessions done outside the cap" "10" "$(t5 ac6_run1_trivial_done)"
assert_eq "AC6: run 1 leaves 5 leads eligible" "5" "$(t5 ac6_run1_deferred)"
assert_eq "AC6: run 2 processes the remaining 5" "5" "$(t5 ac6_run2_processed)"
assert_eq "AC6: run 3 has nothing to process" "0" "$(t5 ac6_run3_processed)"
assert_eq "AC6: a trivial session is never processed" "True" "$(t5 ac6_trivial_never_processed)"
assert_eq "AC6: the cursor entry carries every stored key" "done,fail,hwm,quarantined,seen" "$(t5 ac6_keys)"

assert_eq "AC25: 3 capped runs process 20, 20, 10" "20,20,10" "$(t5 ac25_sizes)"
assert_eq "AC25: sessions come out in last_activity order, oldest first" "True" "$(t5 ac25_oldest_first)"
assert_eq "AC25: all 50 are processed exactly once" "True" "$(t5 ac25_each_once)"
assert_eq "AC25: no session is marked done without being processed" "0" "$(t5 ac25_none_done_unprocessed)"
assert_eq "AC25: the hwm ends at the newest session" "True" "$(t5 ac25_hwm_at_newest)"

assert_eq "AC6: a session inside the quiet window is not selected" "old" "$(t5 quiet_first_run)"
assert_eq "AC6: the hwm holds behind a session still in the quiet window" "True" "$(t5 quiet_hwm_holds)"
assert_eq "AC6: the session is selected once it goes quiet" "busy" "$(t5 quiet_second_run)"
assert_eq "AC6: a tie on last_activity orders by id and the cap splits it" "tie-a,tie-b" "$(t5 tie_run1)"
assert_eq "AC6: the rest of the tie is picked up next run" "tie-c" "$(t5 tie_run2)"

assert_eq "AC25: a failing session does not stop later sessions" "f2,f3" "$(t5 fail_processed)"
assert_eq "AC25: the failing session is reported failed" "f1" "$(t5 fail_failed)"
assert_eq "AC25: the hwm does not pass a failing session" "True" "$(t5 fail_hwm_held)"
assert_eq "AC25: the failing session is not marked done" "True" "$(t5 fail_not_done)"
assert_eq "AC25: later sessions are done" "f2,f3" "$(t5 fail_later_done)"
assert_eq "AC25: the next run retries only the failed session" "f1" "$(t5 fail_retry)"
assert_eq "AC25: the hwm passes the whole prefix once it clears" "True" "$(t5 fail_hwm_after)"

assert_eq "AC20: done{} entries below the hwm are pruned" "True" "$(t5 ac20_done_pruned)"
assert_eq "AC20: seen{} survives the done{} prune by hwm" "s1,s2,s3" "$(t5 ac20_seen_kept)"
assert_eq "AC20: a seen{} entry holds last_ts and ts" "True" "$(t5 ac20_seen_shape)"

assert_eq "AC6: the first read of a session renders it whole" "True" "$(t5 resume_first_full)"
assert_eq "AC6: a resumed session is selected again" "res" "$(t5 resume_reselected)"
assert_eq "AC6: a resumed session renders only entries after seen last_ts" "True" "$(t5 resume_delta_only)"
assert_eq "AC6: a resumed session moves seen last_ts forward" "True" "$(t5 resume_seen_moved)"

assert_eq "AC1: a self-harvest-cwd session is never processed" "normal" "$(t5 ac1_selfh_processed)"
assert_eq "AC1: a self-harvest-cwd session is marked done" "selfh" "$(t5 ac1_selfh_filtered)"
assert_eq "AC1: the hwm moves past a self-harvest-cwd session" "True" "$(t5 ac1_selfh_hwm_passed)"
assert_eq "AC26: a devin hidden = 1 session is never processed" "s-main,s-null" "$(t5 ac26_processed)"
assert_eq "AC26: a hidden session is not handed to the extractor" "True" "$(t5 ac26_hidden_not_processed)"
assert_eq "AC26: a hidden session is marked done" "True" "$(t5 ac26_hidden_done)"
assert_eq "AC26: the hwm moves past a hidden session" "True" "$(t5 ac26_hwm_passed)"
assert_eq "AC1: a devin session is attributed before processing" "lead-z" "$(t5 ac26_attributed)"
assert_eq "AC1: an unmatched devin session stays unattributed" "None" "$(t5 ac26_unattributed)"

assert_eq "cursor: a crash between sessions leaves a parseable file with the earlier session" "True" "$(t5 atomic_crash_between)"
assert_eq "cursor: the crashed session is not marked done" "True" "$(t5 atomic_a2_not_done)"
assert_eq "cursor: a crash inside the replace leaves the previous file intact" "True" "$(t5 atomic_file_intact)"
assert_eq "cursor: the file always parses" "True" "$(t5 atomic_parses)"
assert_eq "clock: HARVEST_SWEEP_NOW pins _now()" "True" "$(t5 clock_env)"

# ============================================================
echo ""
echo "=== Results ==="
echo "Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}$FAIL test(s) failed.${NC}"
  exit 1
fi
echo -e "${GREEN}All harvest sweep tests passed.${NC}"
