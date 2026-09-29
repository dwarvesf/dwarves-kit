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
# Safety net: no test can reach a real model, even one that forgets to set its own stub.
export HARVEST_EXTRACTOR="$KIT_DIR/tests/fixtures/harvest-sweep/stub-extractor.sh"

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

# ---- run-wide cap: one budget across sources, global last_activity order ----
state, root = scenario(devin=True)
os.environ["HARVEST_SWEEP_MIN_MESSAGES"] = "2"
os.environ["HARVEST_SWEEP_LAUNCH_RECORD"] = os.path.join(TD, "nonexistent-launch.jsonl")
for sid, off in (("c1", 19000), ("c2", 16000), ("c3", 12000), ("c4", 9000)):
    mk(root, sid, NOW - off)
log = []
res = hs.run_selection(lambda t, text: log.append(t["session_id"]) or True, schedule_hours=6, max_sessions=4)
P("cap_run1_order", ",".join(log))
P("cap_run1_per_source", "%s|%s" % (",".join(res["claude"]["processed"]), ",".join(res["devin"]["processed"])))
P("cap_run1_deferred", "%d|%d" % (len(res["claude"]["deferred"]), len(res["devin"]["deferred"])))
log[:] = []
hs.run_selection(lambda t, text: log.append(t["session_id"]) or True, schedule_hours=6, max_sessions=4)
P("cap_run2_order", ",".join(log))
del os.environ["HARVEST_SWEEP_MIN_MESSAGES"]

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

assert_eq "AC6: one cap covers all sources, taken in global last_activity order" "c1,s-main,c2,s-null" "$(t5 cap_run1_order)"
assert_eq "AC6: each source's processed list keeps its own sessions" "c1,c2|s-main,s-null" "$(t5 cap_run1_per_source)"
assert_eq "AC6: deferred stays per source (hidden devin is unclassified past the cap)" "2|1" "$(t5 cap_run1_deferred)"
assert_eq "AC6: the next run takes the rest; the hidden session is free" "c3,c4" "$(t5 cap_run2_order)"

assert_eq "cursor: a crash between sessions leaves a parseable file with the earlier session" "True" "$(t5 atomic_crash_between)"
assert_eq "cursor: the crashed session is not marked done" "True" "$(t5 atomic_a2_not_done)"
assert_eq "cursor: a crash inside the replace leaves the previous file intact" "True" "$(t5 atomic_file_intact)"
assert_eq "cursor: the file always parses" "True" "$(t5 atomic_parses)"
assert_eq "clock: HARVEST_SWEEP_NOW pins _now()" "True" "$(t5 clock_env)"

# ============================================================
echo ""
echo "=== T5b lag, drift, and --since ==="

T5B_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import datetime, importlib.util, json, os
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD, NOW = os.environ["TD"], int(os.environ["T5_NOW"])
P = lambda k, v: print("%s=%s" % (k, v))
n_scn = [0]

def scenario(devin_db=None, now=NOW):
    n_scn[0] += 1
    base = os.path.join(TD, "t5b-s%d" % n_scn[0])
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base, "claude")
    os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = devin_db or os.path.join(base, "none.db")
    os.environ["HARVEST_SWEEP_NOW"] = str(now)
    return os.environ["HARVEST_SWEEP_CLAUDE_ROOT"]

iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def mk(root, sid, la, n=6):
    d = os.path.join(root, "p")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": "/w/x",
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s msg %d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))
    return path

def cursor():
    with open(hs._cursor_path()) as fh:
        return json.load(fh)

ok = lambda t, text: True
sweep = lambda **kw: hs.run_selection(ok, schedule_hours=48, **kw)
rows = lambda res, src: " | ".join(res[src]["state_rows"])

# ---- AC20: 12 all-trivial claude sessions per run is drift ----
root = scenario()
runs = []
for r in range(3):
    for k in range(12):
        mk(root, "t%d-%02d" % (r, k), NOW - 7200 + r * 600 + k, n=2)
    res = sweep()
    runs.append((res, cursor()))
P("ac20_row", "drift" in rows(runs[0][0], "claude") and "claude" in rows(runs[0][0], "claude"))
P("ac20_counts", ",".join(str(c["source_fail"]["claude"]) for _, c in runs))
P("ac20_tripped", ",".join(str(hs.source_fail_tripped(c, "claude")) for _, c in runs))
# a run that reads a real session is a good read
mk(root, "real1", NOW - 3600)
res = sweep()
P("ac20_reset", "%s|%s|%s" % (cursor()["source_fail"]["claude"], hs.source_fail_tripped(cursor(), "claude"), rows(res, "claude") == ""))
# 12 trivial mixed with one real session: not drift
root = scenario()
for k in range(12):
    mk(root, "mt%02d" % k, NOW - 7200 - k, n=2)
mk(root, "mreal", NOW - 3600)
res = sweep()
P("ac20_mixed_not_drift", "%s|%s" % (cursor()["source_fail"]["claude"], rows(res, "claude") == ""))
# 9 trivial sessions: under the floor
root = scenario()
for k in range(9):
    mk(root, "u%02d" % k, NOW - 7200 - k, n=2)
res = sweep()
P("ac20_under_floor", "%s|%s" % (cursor()["source_fail"]["claude"], rows(res, "claude") == ""))
os.environ["HARVEST_SWEEP_DRIFT_MIN_SCANNED"] = "5"
root = scenario()
for k in range(9):
    mk(root, "v%02d" % k, NOW - 7200 - k, n=2)
sweep()
P("ac20_floor_knob", cursor()["source_fail"]["claude"])
del os.environ["HARVEST_SWEEP_DRIFT_MIN_SCANNED"]

# ---- AC21: lag alarm, oldest eligible unread 30h old (cap 0 takes nothing) ----
root = scenario()
path = mk(root, "old30", NOW - 30 * 3600)
res = sweep(max_sessions=0)
c = cursor()
P("ac21_run1", "%s|%s|%s" % (res["claude"]["lag"], c["lag_runs"], hs.lag_tripped(c)))
P("ac21_run1_row", "lag" in rows(res, "claude") and "30.0h" in rows(res, "claude"))
res = sweep(max_sessions=0)
c = cursor()
P("ac21_run2", "%s|%s" % (c["lag_runs"], hs.lag_tripped(c)))
os.utime(path, (NOW - 10 * 3600, NOW - 10 * 3600))  # the oldest unread is now 10h old
res = sweep(max_sessions=0)
c = cursor()
P("ac21_run3", "%s|%s|%s" % (c["lag_runs"], hs.lag_tripped(c), res["claude"]["lag"]["oldest_age_s"]))
res = sweep(max_sessions=20)
P("ac21_drained", "%s|%s" % (res["claude"]["lag"], cursor()["lag_runs"]))
# the limit is env-tunable
os.environ["HARVEST_SWEEP_LAG_HOURS"] = "5"
mk(root, "later", NOW - 8 * 3600)
sweep(max_sessions=0)
P("ac21_lag_hours_knob", cursor()["lag_runs"])
del os.environ["HARVEST_SWEEP_LAG_HOURS"]

# ---- AC14 end to end: drifted devin db, three runs; claude still processes ----
drift_db = os.path.join(TD, "drift.db")
good_db = os.path.join(TD, "t5-devin.db")
root = scenario(devin_db=drift_db)
counts, tripped, claude_done = [], [], []
for r in range(3):
    mk(root, "e2e%d" % r, NOW - 7200 + r * 60)
    log = []
    res = hs.run_selection(lambda t, text: log.append(t["session_id"]) or True, schedule_hours=24)
    c = cursor()
    counts.append(c["source_fail"]["devin"])
    tripped.append(hs.source_fail_tripped(c, "devin"))
    claude_done.append(",".join(log))
P("ac14_counts", ",".join(map(str, counts)))
P("ac14_tripped", ",".join(map(str, tripped)))
P("ac14_claude_each_run", "|".join(claude_done))
P("ac14_row", res["devin"]["state_rows"][0].startswith("STATE devin:"))
P("ac14_claude_clean", cursor()["source_fail"]["claude"])
os.environ["HARVEST_SWEEP_DEVIN_DB"] = good_db
hs.run_selection(ok, schedule_hours=24)
c = cursor()
P("ac14_reset", "%s|%s" % (c["source_fail"]["devin"], hs.source_fail_tripped(c, "devin")))

# ---- --since: a one-off backfill ----
root = scenario()
mk(root, "a", NOW - 3 * 3600)
hs.run_selection(ok, schedule_hours=6)
mk(root, "b", NOW - 5 * 3600)  # older than the hwm: never read without --since
hwm = cursor()["claude"]["hwm"]
log = []
take = lambda t, text: log.append(t["session_id"]) or True
hs.run_selection(take, schedule_hours=6)
P("since_off", ",".join(log))
hs.run_selection(take, schedule_hours=6, since=NOW + 100)  # newer than the hwm: ignored
P("since_newer_ignored", "%s|%s" % (",".join(log), cursor()["claude"]["hwm"] == hwm))
hs.run_selection(take, schedule_hours=6, since=iso(NOW - 6 * 3600))
P("since_iso_backfill", ",".join(log))
P("since_hwm_back_up", cursor()["claude"]["hwm"] == hwm)
# first run: --since replaces the schedule_hours window
root = scenario()
mk(root, "far", NOW - 20 * 3600)
log = []
hs.run_selection(take, schedule_hours=6)
P("since_first_run_default", ",".join(log))
root = scenario()
mk(root, "far", NOW - 20 * 3600)
log = []
hs.run_selection(take, schedule_hours=6, since=str(NOW - 24 * 3600))
P("since_first_run_epoch", ",".join(log))
try:
    hs.run_selection(take, since="last tuesday")
    P("since_bad", "no error")
except ValueError:
    P("since_bad", "ValueError")
PY
)
t5b() { printf '%s\n' "$T5B_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC20: 12 all-trivial sessions yield a drift STATE row" "True" "$(t5b ac20_row)"
assert_eq "AC20: each all-trivial run adds one source failure" "1,2,3" "$(t5b ac20_counts)"
assert_eq "AC20: three all-trivial runs trip the source failure (rc 5)" "False,False,True" "$(t5b ac20_tripped)"
assert_eq "AC20: a run with a real session resets the count" "0|False|True" "$(t5b ac20_reset)"
assert_eq "AC20: trivial sessions mixed with a real one are not drift" "0|True" "$(t5b ac20_mixed_not_drift)"
assert_eq "AC20: fewer than 10 scanned trivial sessions is not drift" "0|True" "$(t5b ac20_under_floor)"
assert_eq "AC20: HARVEST_SWEEP_DRIFT_MIN_SCANNED moves the floor" "1" "$(t5b ac20_floor_knob)"
assert_eq "AC21: a 30h-old unread session reports lag, lag_runs 1, not tripped" "{'eligible': 1, 'oldest_age_s': 108000}|1|False" "$(t5b ac21_run1)"
assert_eq "AC21: the lag STATE row names the source, count, and age" "True" "$(t5b ac21_run1_row)"
assert_eq "AC21: a second run over 24h trips lag" "2|True" "$(t5b ac21_run2)"
assert_eq "AC21: a following run under 24h resets lag_runs" "0|False|36000" "$(t5b ac21_run3)"
assert_eq "AC21: a drained backlog reports no lag" "{'eligible': 0, 'oldest_age_s': 0}|0" "$(t5b ac21_drained)"
assert_eq "AC21: HARVEST_SWEEP_LAG_HOURS moves the limit" "1" "$(t5b ac21_lag_hours_knob)"
assert_eq "AC14: a drifted devin db adds one source failure per run" "1,2,3" "$(t5b ac14_counts)"
assert_eq "AC14: devin trips on the third run only" "False,False,True" "$(t5b ac14_tripped)"
assert_eq "AC14: the claude source still processes every run" "e2e0|e2e1|e2e2" "$(t5b ac14_claude_each_run)"
assert_eq "AC14: the drifted source carries a STATE row" "True" "$(t5b ac14_row)"
assert_eq "AC14: claude counts no failure meanwhile" "0" "$(t5b ac14_claude_clean)"
assert_eq "AC14: one good devin read resets the count" "0|False" "$(t5b ac14_reset)"
assert_eq "since: without it a session older than the hwm stays unread" "" "$(t5b since_off)"
assert_eq "since: a value newer than the hwm is ignored, never skips sessions" "|True" "$(t5b since_newer_ignored)"
assert_eq "since: an ISO value backfills a session older than the hwm" "b" "$(t5b since_iso_backfill)"
assert_eq "since: the hwm returns to its old place once the backfill settles" "True" "$(t5b since_hwm_back_up)"
assert_eq "since: the first run reads only the schedule window by default" "" "$(t5b since_first_run_default)"
assert_eq "since: the first run starts at an epoch --since instead" "far" "$(t5b since_first_run_epoch)"
assert_eq "since: an unparseable value is an error" "ValueError" "$(t5b since_bad)"

# ============================================================
echo ""
echo "=== T6 extractor call and raw output cache ==="

T6_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import datetime, importlib.util, json, os, shlex, stat
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD, NOW = os.environ["TD"], int(os.environ["T5_NOW"])
STUB = os.path.join(os.environ["KIT_DIR"], "tests", "fixtures", "harvest-sweep", "stub-extractor.sh")
P = lambda k, v: print("%s=%s" % (k, v))
# A permissive umask, so a directory made without the explicit 0700 comes out 0755 and
# the AC24 control is never vacuous whatever the caller's umask is.
os.umask(0o022)
n_scn = [0]

def scenario(now=NOW):
    n_scn[0] += 1
    base = os.path.join(TD, "t6-s%d" % n_scn[0])
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base, "claude")
    os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(base, "none.db")
    os.environ["HARVEST_SWEEP_NOW"] = str(now)
    os.environ["HARVEST_EXTRACTOR"] = shlex.quote(STUB)
    os.environ["STUB_CALLS"] = os.path.join(base, "calls")
    for k in ("STUB_MODE", "STUB_OUT", "STUB_RECORD"):
        os.environ.pop(k, None)
    return base, os.environ["HARVEST_SWEEP_CLAUDE_ROOT"]

iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def mk(root, sid, la, n=6):
    d = os.path.join(root, "p")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": "/w/x",
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s msg %d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))

def calls():
    try:
        with open(os.environ["STUB_CALLS"]) as fh:
            return len(fh.readlines())
    except OSError:
        return 0

def cursor():
    with open(hs._cursor_path()) as fh:
        return json.load(fh)

mode = lambda p: oct(stat.S_IMODE(os.stat(p).st_mode))
extract_dir = lambda: os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "extract")
run = lambda **kw: hs.run_selection(schedule_hours=48, **kw)["claude"]
OUT = '{"learnings": [{"item": "cache-me", "kind": "insight", "home": "til", "why": "w", "evidence": "e"}], "sightings": []}'

# ---- AC22 / AC8: the default command's argv, cwd, and child env ----
base, root = scenario()
mk(root, "argv1", NOW - 7200)
bindir = os.path.join(base, "bin")
os.makedirs(bindir)
os.symlink(STUB, os.path.join(bindir, "claude"))
saved_path = os.environ["PATH"]
os.environ["PATH"] = bindir + os.pathsep + saved_path
del os.environ["HARVEST_EXTRACTOR"]
os.environ["STUB_RECORD"] = os.path.join(base, "rec")
r = run()
os.environ["PATH"] = saved_path
argv = open(os.path.join(base, "rec", "argv")).read().split("\n")[:-1]
P("argv_processed", ",".join(r["processed"]))
i = argv.index("--tools") if "--tools" in argv else -1
P("argv_tools_empty", i >= 0 and i + 1 < len(argv) and argv[i + 1] == "")
P("argv_strict_mcp", "--strict-mcp-config" in argv)
P("argv_no_persist", "--no-session-persistence" in argv)
j = argv.index("--setting-sources") if "--setting-sources" in argv else -1
P("argv_setting_sources", j >= 0 and argv[j + 1:j + 2] == ["project"])
P("argv_no_bare", "--bare" not in argv)
P("argv_cwd", open(os.path.join(base, "rec", "cwd")).read().strip()
  == os.path.realpath(os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "extract-cwd")))
P("argv_child", open(os.path.join(base, "rec", "child")).read().strip())
P("argv_prompt_has_transcript", "argv1 msg 5" in open(os.path.join(base, "rec", "prompt")).read())

# ---- AC24: modes. extract/ and extract/<source> 0700, cache files 0600 ----
base, root = scenario()
for k in range(3):
    mk(root, "m%d" % k, NOW - 7200 + k)
run()
files = [os.path.join(extract_dir(), "claude", f) for f in os.listdir(os.path.join(extract_dir(), "claude"))]
P("modes_dirs", "%s,%s" % (mode(extract_dir()), mode(os.path.join(extract_dir(), "claude"))))
P("modes_files", ",".join(sorted({mode(f) for f in files})) + ":%d" % len(files))
os.makedirs(os.path.join(base, "umask-probe"))
P("modes_umask_bites", mode(os.path.join(base, "umask-probe")))

# ---- replay reuses the cache: no extractor call ----
base, root = scenario()
mk(root, "rp", NOW - 7200)
os.environ["STUB_OUT"] = OUT
run()
cache = os.path.join(extract_dir(), "claude", "rp@%d.json" % (NOW - 7200))
P("replay_first_calls", calls())
P("replay_cache_name", os.path.exists(cache))
os.replace(hs._cursor_path(), hs._cursor_path() + ".bak")  # a crash before the cursor write
t = hs.load_claude(hs.list_claude_sessions()[0])
ok, obj, _, _ = hs.extract_session(t, "anything")
r = run()
P("replay_calls_after", calls())
P("replay_processed", ",".join(r["processed"]))
P("replay_obj", ok and obj["learnings"][0]["item"])

# ---- AC30: a truncated cache file is removed and re-extracted, no fail count ----
full = open(cache).read()
with open(cache, "w") as fh:
    fh.write(full[: len(full) // 2])
os.replace(hs._cursor_path(), hs._cursor_path() + ".bak")
r = run()
P("trunc_calls", calls())
P("trunc_processed", ",".join(r["processed"]) + "|" + ",".join(r["failed"]))
P("trunc_restored", open(cache).read() == full)
P("trunc_no_fail", cursor()["claude"]["fail"])

# ---- AC30: a crash mid-write leaves no partial cache file; a stray temp file is never read ----
base, root = scenario()
mk(root, "cw", NOW - 7200)
os.environ["STUB_OUT"] = OUT
real_replace = hs.os.replace
def boom(src, dst):
    raise OSError("simulated crash in os.replace")
hs.os.replace = boom
try:
    run()
    P("crash_raised", False)
except OSError:
    P("crash_raised", True)
hs.os.replace = real_replace
cdir = os.path.join(extract_dir(), "claude")
P("crash_left", ",".join(sorted(os.listdir(cdir))))
with open(os.path.join(cdir, ".tmp-stray"), "w") as fh:
    fh.write('{"learnings": [{"item": "from-a-temp-file"}], "sightings": []}')
n0 = calls()
r = run()
cache = os.path.join(cdir, "cw@%d.json" % (NOW - 7200))
P("crash_reextracted", "%d|%s" % (calls() - n0, ",".join(r["processed"])))
P("crash_cache_whole", json.loads(open(cache).read())["learnings"][0]["item"])

# ---- ok contract: non-JSON, failure, timeout, missing binary, prose-wrapped, empty arrays ----
base, root = scenario()
def ok_of(mode_, out=None):
    os.environ["STUB_MODE"] = mode_
    os.environ.pop("STUB_OUT", None)
    if out is not None:
        os.environ["STUB_OUT"] = out
    return hs.run_sweep_extractor("prompt")
P("ok_nonjson", ok_of("nonjson")[0])
res = ok_of("fail")
P("ok_fail", "%s|%s" % (res[0], res[2].strip()))
P("ok_empty_arrays", ok_of("ok", '{"learnings": [], "sightings": []}')[0])
P("ok_prose_wrapped", ok_of("prose", OUT)[0])
P("ok_array_only", ok_of("ok", "[1, 2]")[0])
hs.EXTRACT_TIMEOUT = 1
res = ok_of("sleep")
hs.EXTRACT_TIMEOUT = 120
P("ok_timeout", "%s|%s" % (res[0], res[2]))
os.environ["HARVEST_EXTRACTOR"] = os.path.join(base, "no-such-extractor")
res = hs.run_sweep_extractor("prompt")
P("ok_missing_binary", res[0])
os.environ["HARVEST_EXTRACTOR"] = shlex.quote(STUB)

# a non-JSON answer is a failed session: not done, no cache file
os.environ["STUB_MODE"] = "nonjson"
mk(root, "nj", NOW - 7200)
r = run()
P("nonjson_session", "%s|%s|%s" % (",".join(r["processed"]), ",".join(r["failed"]),
                                   os.path.exists(os.path.join(extract_dir(), "claude", "nj@%d.json" % (NOW - 7200)))))

# ---- extract_json_object ----
E = hs.extract_json_object
P("ejo_fenced", E('prose\n```json\n{"a": 1}\n```\n') == {"a": 1})
P("ejo_brace_in_string", E('{"a": "} not the end {", "b": [{"c": 1}]}') == {"a": "} not the end {", "b": [{"c": 1}]})
P("ejo_escaped_quote", E(r'{"a": "say \"}\" twice"}') == {"a": 'say "}" twice'})
P("ejo_inner_array_first", E('[{"x": 1}] then {"learnings": []}') == {"x": 1})
P("ejo_skips_non_json_braces", E('use {braces} here: {"a": 2}') == {"a": 2})
P("ejo_truncated_is_none", E('{"learnings": [{"item": "a"}, {"item": "b"') is None)
P("ejo_none", E("nothing here") is None)

# ---- hostile session id: the cache file stays inside extract/<source>, no collision ----
base, root = scenario()
hostile = "../../../escaped"
p1 = hs._cache_path("devin", hostile, 5)
inside = os.path.realpath(os.path.join(extract_dir(), "devin")) + os.sep
P("hostile_inside", os.path.realpath(p1).startswith(inside))
P("hostile_no_collision", p1 != hs._cache_path("devin", "_.._.._escaped", 5)
  and hs._cache_path("devin", "a/b", 5) != hs._cache_path("devin", "a_b", 5))
P("hostile_plain_kept", os.path.basename(hs._cache_path("claude", "abc-123", 7)))
t = {"source": "devin", "session_id": hostile, "last_activity": 5, "messages": []}
hs.extract_session(t, "text")
P("hostile_written_inside", os.path.exists(p1) and not os.path.exists(os.path.join(base, "escaped@5.json")))

# ---- AC6: 300 pattern slugs + 300 proposed slugs, the prompt carries exactly 100 ----
base, root = scenario()
sweep = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep")
os.makedirs(sweep)
slug = lambda tag, k: ("%s-%03d-" % (tag, k)).ljust(60, "x")
with open(os.path.join(sweep, "patterns.jsonl"), "w") as fh:
    for k in range(300):
        fh.write(json.dumps({"pattern": slug("p", k), "canonical": slug("p", k), "ts": 1000 + k}) + "\n")
    fh.write(json.dumps({"canonical": "NOT A SLUG " + "y" * 80, "ts": 99999}) + "\n")
with open(os.path.join(sweep, "proposed.jsonl"), "w") as fh:
    for k in range(300):
        fh.write(json.dumps({"pattern": slug("q", k), "outcome": "REPORTED", "ts": 1000 + k}) + "\n")
big = "z" * 20000
t = {"source": "claude", "session_id": "big", "last_activity": 1, "messages": [
    {"role": "user", "text": big, "ts": 1, "sub": False},
    {"role": "assistant", "text": big, "ts": 2, "sub": True}]}
text = hs.render(t, 0, 12000)
prompt = hs.build_prompt(text)
listed = prompt.split("Known slugs:\n", 1)[1].split("Transcript follows:", 1)[0].split("\n")[:-1]
P("cap_slugs", len(listed))
P("cap_most_recent", slug("p", 299) in listed and slug("p", 250) in listed and slug("p", 249) not in listed
  and slug("q", 299) in listed and slug("q", 249) not in listed)
P("cap_charset_skip", not any("NOT A SLUG" in s for s in listed))
P("cap_render_len", len(text) >= 12000)
P("cap_prompt_len", "%s|%d" % (len(prompt) <= 19400, len(prompt)))
P("cap_prompt_over_maxchars", len(hs.build_prompt(big)) <= 19400)

# ---- AC25: the outage scenario with the real processor; every session has a cache file ----
base, root = scenario()
las = {}
for k in range(50):
    sid = "out%02d" % k
    las[sid] = NOW - 172800 + k * 3400
    mk(root, sid, las[sid])
sizes, done_without_cache = [], 0
for _ in range(3):
    r = hs.run_selection(schedule_hours=50, max_sessions=20)["claude"]
    sizes.append(len(r["processed"]))
    done_without_cache += sum(1 for sid in cursor()["claude"]["done"]
                              if not os.path.exists(os.path.join(extract_dir(), "claude", "%s@%d.json" % (sid, las[sid]))))
P("ac25_sizes", ",".join(map(str, sizes)))
P("ac25_all_cached", sum(1 for sid in las if os.path.exists(os.path.join(extract_dir(), "claude", "%s@%d.json" % (sid, las[sid])))))
P("ac25_done_without_cache", done_without_cache)
P("ac25_calls", calls())
PY
)
t6() { printf '%s\n' "$T6_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC22: the default command runs with no HARVEST_EXTRACTOR set" "argv1" "$(t6 argv_processed)"
assert_eq "AC22: argv carries --tools followed by an empty-string element" "True" "$(t6 argv_tools_empty)"
assert_eq "AC22: argv carries --strict-mcp-config" "True" "$(t6 argv_strict_mcp)"
assert_eq "AC22: argv carries --no-session-persistence" "True" "$(t6 argv_no_persist)"
assert_eq "AC8: argv carries --setting-sources project" "True" "$(t6 argv_setting_sources)"
assert_eq "AC8: argv never carries --bare" "True" "$(t6 argv_no_bare)"
assert_eq "AC22: the extractor runs in the state dir's sweep/extract-cwd" "True" "$(t6 argv_cwd)"
assert_eq "AC22: the extractor's env carries HARVEST_SWEEP_CHILD=1" "1" "$(t6 argv_child)"
assert_eq "AC22: the rendered transcript reaches the extractor on stdin" "True" "$(t6 argv_prompt_has_transcript)"
assert_eq "AC24: extract/ and extract/claude are 0700" "0o700,0o700" "$(t6 modes_dirs)"
assert_eq "AC24: every cache file is 0600" "0o600:3" "$(t6 modes_files)"
assert_eq "AC24: the test umask gives 0755 without an explicit mode" "0o755" "$(t6 modes_umask_bites)"
assert_eq "AC30: the first run calls the extractor once" "1" "$(t6 replay_first_calls)"
assert_eq "AC30: the cache file is extract/claude/<id>@<last_activity>.json" "True" "$(t6 replay_cache_name)"
assert_eq "AC30: a replay of the same key makes no extractor call" "1" "$(t6 replay_calls_after)"
assert_eq "AC30: the replayed session still completes" "rp" "$(t6 replay_processed)"
assert_eq "AC30: the replay returns the cached object" "cache-me" "$(t6 replay_obj)"
assert_eq "AC30: a truncated cache file is re-extracted" "2" "$(t6 trunc_calls)"
assert_eq "AC30: the re-extracted session completes, not failed" "rp|" "$(t6 trunc_processed)"
assert_eq "AC30: the truncated file is replaced by a whole one" "True" "$(t6 trunc_restored)"
assert_eq "AC30: a truncated cache file raises no fail count" "{}" "$(t6 trunc_no_fail)"
assert_eq "AC30: a crash in os.replace propagates" "True" "$(t6 crash_raised)"
assert_eq "AC30: a crash mid-write leaves no cache or temp file" "" "$(t6 crash_left)"
assert_eq "AC30: a stray temp file is never read; the session is extracted" "1|cw" "$(t6 crash_reextracted)"
assert_eq "AC30: the cache file written after the crash is whole" "cache-me" "$(t6 crash_cache_whole)"
assert_eq "extractor: non-JSON stdout is ok false" "False" "$(t6 ok_nonjson)"
assert_eq "extractor: a non-zero exit is ok false with its stderr" "False|stub extractor failure" "$(t6 ok_fail)"
assert_eq "extractor: empty learnings and sightings are ok true" "True" "$(t6 ok_empty_arrays)"
assert_eq "extractor: prose-wrapped JSON is ok true" "True" "$(t6 ok_prose_wrapped)"
assert_eq "extractor: a JSON array with no object is ok false" "False" "$(t6 ok_array_only)"
assert_eq "extractor: a timeout is ok false" "False|timeout after 1s" "$(t6 ok_timeout)"
assert_eq "extractor: a missing binary is ok false" "False" "$(t6 ok_missing_binary)"
assert_eq "extractor: a non-JSON answer fails the session and caches nothing" "|nj|False" "$(t6 nonjson_session)"
assert_eq "extract_json_object: fenced JSON" "True" "$(t6 ejo_fenced)"
assert_eq "extract_json_object: braces inside strings do not count" "True" "$(t6 ejo_brace_in_string)"
assert_eq "extract_json_object: escaped quotes inside strings" "True" "$(t6 ejo_escaped_quote)"
assert_eq "extract_json_object: an object inside a leading array is still found" "True" "$(t6 ejo_inner_array_first)"
assert_eq "extract_json_object: skips braces that are not JSON" "True" "$(t6 ejo_skips_non_json_braces)"
assert_eq "extract_json_object: a truncated object is None, not an inner object" "True" "$(t6 ejo_truncated_is_none)"
assert_eq "extract_json_object: no object is None" "True" "$(t6 ejo_none)"
assert_eq "cache: a hostile session id stays inside extract/<source>" "True" "$(t6 hostile_inside)"
assert_eq "cache: sanitized ids never collide with a plain id" "True" "$(t6 hostile_no_collision)"
assert_eq "cache: a plain id keeps its name" "abc-123@7.json" "$(t6 hostile_plain_kept)"
assert_eq "cache: a hostile id is written inside, nothing outside" "True" "$(t6 hostile_written_inside)"
assert_eq "AC6: 300 pattern plus 300 proposed slugs give exactly 100 in the prompt" "100" "$(t6 cap_slugs)"
assert_eq "AC6: the prompt takes the 50 most recent of each file" "True" "$(t6 cap_most_recent)"
assert_eq "AC6: a stored value off the slug charset never reaches the prompt" "True" "$(t6 cap_charset_skip)"
assert_eq "AC6: the render under test is max size" "True" "$(t6 cap_render_len)"
assert_eq "AC6: the prompt is at most 19,400 chars" "True" "$(t6 cap_prompt_len | cut -d'|' -f1)"
assert_eq "AC6: an over-long transcript is cut to HARVEST_MAXCHARS" "True" "$(t6 cap_prompt_over_maxchars)"
assert_eq "AC25: 3 capped runs with the real processor extract 20, 20, 10" "20,20,10" "$(t6 ac25_sizes)"
assert_eq "AC25: every one of the 50 has a raw output cache file" "50" "$(t6 ac25_all_cached)"
assert_eq "AC25: no session is marked done without a cache file" "0" "$(t6 ac25_done_without_cache)"
assert_eq "AC25: one extractor call per session" "50" "$(t6 ac25_calls)"
echo "  (T6 max prompt length: $(t6 cap_prompt_len | cut -d'|' -f2))"

# ============================================================
echo "=== T7a failure classes ==="

T7A_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import datetime, importlib.util, json, os, shlex
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD, NOW = os.environ["TD"], int(os.environ["T5_NOW"])
STUB = os.path.join(os.environ["KIT_DIR"], "tests", "fixtures", "harvest-sweep", "stub-extractor.sh")
P = lambda k, v: print("%s=%s" % (k, v))
n_scn = [0]

def scenario(now=NOW):
    n_scn[0] += 1
    base = os.path.join(TD, "t7a-s%d" % n_scn[0])
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base, "claude")
    os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(base, "none.db")
    os.environ["HARVEST_SWEEP_NOW"] = str(now)
    os.environ["HARVEST_EXTRACTOR"] = shlex.quote(STUB)
    os.environ["STUB_CALLS"] = os.path.join(base, "calls")
    for k in ("STUB_MODE", "STUB_OUT", "STUB_ERR", "STUB_RECORD", "STUB_FAIL_MATCH"):
        os.environ.pop(k, None)
    return base, os.environ["HARVEST_SWEEP_CLAUDE_ROOT"]

iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def mk(root, sid, la, n=6):
    d = os.path.join(root, "p")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": "/w/x",
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s msg %d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))

def calls():
    try:
        with open(os.environ["STUB_CALLS"]) as fh:
            return len(fh.readlines())
    except OSError:
        return 0

def cursor():
    with open(hs._cursor_path()) as fh:
        return json.load(fh)

run = lambda **kw: hs.run_selection(schedule_hours=48, **kw)
rows = lambda res, src: " | ".join(res[src]["state_rows"])
initial_hwm = NOW - 48 * 3600

# ---- AC27: a limit-shaped failure is a hold, not a failure ----
base, root = scenario()
mk(root, "la", NOW - 7200)
mk(root, "lb", NOW - 7000)
os.environ["STUB_MODE"] = "limit"
r = run()
P("limit_stop", r["run"]["stop"])
P("limit_state_row", "extractor-limit" in rows(r, "claude"))
P("limit_no_fail", cursor()["claude"]["fail"])
P("limit_hwm_held", cursor()["claude"]["hwm"] == initial_hwm)
P("limit_processed", ",".join(r["claude"]["processed"]))
P("limit_calls", calls())  # one extraction, no probe on a limit failure
del os.environ["STUB_MODE"]
r = run()
P("limit_resume", ",".join(r["claude"]["processed"]))

# ---- AC4: every call fails, the probe fails too -> auth stop, hwm untouched ----
base, root = scenario()
mk(root, "fa", NOW - 7200)
mk(root, "fb", NOW - 7000)
os.environ["STUB_MODE"] = "fail"
r = run()
P("auth_stop", r["run"]["stop"])
P("auth_incident", ",".join(r["run"]["incidents"]))
P("auth_state_row", "extractor-auth" in rows(r, "claude"))
P("auth_fail_count", cursor()["claude"]["fail"].get("fa"))
P("auth_hwm_held", cursor()["claude"]["hwm"] == initial_hwm)
P("auth_deferred", ",".join(i["session_id"] for i in r["claude"]["deferred"]))
P("auth_calls", calls())  # one extraction plus one probe

# ---- a single failure continues; a second failure this run is auth-shaped ----
base, root = scenario()
mk(root, "bad-a", NOW - 7400)
mk(root, "ok-mid", NOW - 7200)
mk(root, "bad-b", NOW - 7000)
mk(root, "ok-last", NOW - 6800)
os.environ["STUB_FAIL_MATCH"] = "bad-"   # the probe prompt never carries it
r = run()
P("two_stop", r["run"]["stop"])
P("two_processed", ",".join(r["claude"]["processed"]))
P("two_failed", ",".join(r["claude"]["failed"]))
P("two_deferred", ",".join(i["session_id"] for i in r["claude"]["deferred"]))
P("two_fail_counts", json.dumps(cursor()["claude"]["fail"], sort_keys=True))
P("two_calls", calls())  # bad-a, probe, ok-mid, bad-b
P("two_state_row", "a second session failed" in rows(r, "claude"))

# ---- the probe passes: one failure keeps the run going ----
base, root = scenario()
mk(root, "bad-1", NOW - 7200)
mk(root, "ok-1", NOW - 7000)
os.environ["STUB_FAIL_MATCH"] = "bad-"
r = run()
P("one_stop", r["run"]["stop"] is None)
P("one_processed", ",".join(r["claude"]["processed"]))
P("one_failed", ",".join(r["claude"]["failed"]))
P("one_fail_count", cursor()["claude"]["fail"].get("bad-1"))
P("one_calls", calls())  # bad-1, probe, ok-1

# ---- operator: a reply counts only with a learnings or sightings key ----
os.environ["STUB_MODE"] = "ok"
def ok_of(out):
    os.environ["STUB_OUT"] = out
    return hs.run_sweep_extractor("p")
P("keyless_unrelated", ok_of('{"unrelated": 1}')[0])
P("keyless_learnings_only", ok_of('{"learnings": []}')[0])
P("keyless_sightings_only", ok_of('{"sightings": []}')[0])
P("keyless_both_empty", ok_of('{"learnings": [], "sightings": []}')[0])
os.environ.pop("STUB_OUT")
# a keyless reply is a failed session that counts, and is never cached
base, root = scenario()
mk(root, "kl", NOW - 7200)
os.environ["STUB_OUT"] = '{"unrelated": 1}'
r = run()
P("keyless_failed", ",".join(r["claude"]["failed"]))
P("keyless_fail_count", cursor()["claude"]["fail"].get("kl"))
P("keyless_no_cache", os.path.exists(os.path.join(
    os.environ["HARVEST_STATE_DIR"], "sweep", "extract", "claude", "kl@%d.json" % (NOW - 7200))))
# a cached reply without the keys is dead and re-extracted, not a failure
cache_path = hs._cache_path("claude", "kl", NOW - 7200)
os.makedirs(os.path.dirname(cache_path), exist_ok=True)
with open(cache_path, "w") as fh:
    fh.write('{"unrelated": 1}')
os.environ["STUB_OUT"] = '{"learnings": [{"item": "fresh", "kind": "insight", "home": "til", "why": "w", "evidence": "e"}]}'
n0 = calls()
ok, obj, _, _ = hs.extract_session(
    {"source": "claude", "session_id": "kl", "last_activity": NOW - 7200, "messages": []}, "x")
with open(cache_path) as fh:
    P("keyless_reextract", "%s|%s|%s" % (calls() - n0, ok and obj["learnings"][0]["item"],
                                       "fresh" in fh.read()))

# ---- operator: HARVEST_EXTRACTOR override wires a STATE row into the run data ----
P("override_row", "extractor override active, safety flags not enforced" in " | ".join(r["run"]["state_rows"]))
base, root = scenario()
mk(root, "ov", NOW - 7200)
bindir = os.path.join(base, "bin")
os.makedirs(bindir)
os.symlink(STUB, os.path.join(bindir, "claude"))
saved_path = os.environ["PATH"]
os.environ["PATH"] = bindir + os.pathsep + saved_path
del os.environ["HARVEST_EXTRACTOR"]
r = run()
os.environ["PATH"] = saved_path
P("override_absent", " | ".join(r["run"]["state_rows"]))

# ---- ExtractFailure classes ----
P("falsy_failure", bool(hs.ExtractFailure("", "")))
P("limit_class", hs.ExtractFailure("", "usage limit reached").limit)
P("limit_class_stdout", hs.ExtractFailure("RATE LIMIT tripped", "").limit)
P("limit_class_five_hour", hs.ExtractFailure("", "Hit your 5-hour cap").limit)
P("limit_class_plain_fail", hs.ExtractFailure("", "boom").limit)
PY
)
t7a() { printf '%s\n' "$T7A_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC27: a limit-shaped failure stops the run as a hold" "limit" "$(t7a limit_stop)"
assert_eq "AC27: the hold carries a STATE row" "True" "$(t7a limit_state_row)"
assert_eq "AC27: no fail count rises on a limit hold" "{}" "$(t7a limit_no_fail)"
assert_eq "AC27: the hwm does not move on a limit hold" "True" "$(t7a limit_hwm_held)"
assert_eq "AC27: nothing is processed on a limit hold" "" "$(t7a limit_processed)"
assert_eq "AC27: a limit hold runs no probe" "1" "$(t7a limit_calls)"
assert_eq "AC27: the next run resumes at the same session" "la,lb" "$(t7a limit_resume)"

assert_eq "AC4: a failing extractor plus a failing probe stops the run" "auth" "$(t7a auth_stop)"
assert_eq "AC4: a failed probe records an INCIDENT row" "INCIDENT extractor: probe failed: stub extractor failure" "$(t7a auth_incident)"
assert_eq "AC4: the auth stop carries a STATE row" "True" "$(t7a auth_state_row)"
assert_eq "AC4: the failed session's count still rises on the stop path" "1" "$(t7a auth_fail_count)"
assert_eq "AC4: the hwm stays at the initial value" "True" "$(t7a auth_hwm_held)"
assert_eq "AC4: untouched sessions are deferred" "fb" "$(t7a auth_deferred)"
assert_eq "AC4: one extraction plus one probe" "2" "$(t7a auth_calls)"

assert_eq "AC5b: a second failing session in one run is auth-shaped" "auth" "$(t7a two_stop)"
assert_eq "AC5b: the passing session between two failures completes" "ok-mid" "$(t7a two_processed)"
assert_eq "AC5b: both failures are counted" "bad-a,bad-b" "$(t7a two_failed)"
assert_eq "AC5b: sessions past the stop are deferred" "ok-last" "$(t7a two_deferred)"
assert_eq "AC5b: each failed session's count rises" '{"bad-a": 1, "bad-b": 1}' "$(t7a two_fail_counts)"
assert_eq "AC5b: two failures plus one probe plus one success" "4" "$(t7a two_calls)"
assert_eq "AC5b: the second-failure stop carries a STATE row" "True" "$(t7a two_state_row)"

assert_eq "extractor: one failure with a passing probe does not stop the run" "True" "$(t7a one_stop)"
assert_eq "extractor: the run continues past a single failure" "ok-1" "$(t7a one_processed)"
assert_eq "extractor: the failure is reported" "bad-1" "$(t7a one_failed)"
assert_eq "extractor: the fail count rises" "1" "$(t7a one_fail_count)"
assert_eq "extractor: one extraction, one probe, one success" "3" "$(t7a one_calls)"

assert_eq "extractor: a JSON object without learnings or sightings fails" "False" "$(t7a keyless_unrelated)"
assert_eq "extractor: a learnings-only object counts" "True" "$(t7a keyless_learnings_only)"
assert_eq "extractor: a sightings-only object counts" "True" "$(t7a keyless_sightings_only)"
assert_eq "extractor: an empty result with both keys counts" "True" "$(t7a keyless_both_empty)"
assert_eq "extractor: a keyless reply fails the session" "kl" "$(t7a keyless_failed)"
assert_eq "extractor: a keyless reply feeds the fail count" "1" "$(t7a keyless_fail_count)"
assert_eq "extractor: a keyless reply is never cached" "False" "$(t7a keyless_no_cache)"
assert_eq "extractor: a cached keyless reply is re-extracted, not a failure" "1|fresh|True" "$(t7a keyless_reextract)"

assert_eq "extractor: an operator-set HARVEST_EXTRACTOR wires the override STATE row" "True" "$(t7a override_row)"
assert_eq "extractor: no override env, no row" "" "$(t7a override_absent)"

assert_eq "ExtractFailure is falsy for the ok check" "False" "$(t7a falsy_failure)"
assert_eq "ExtractFailure.limit reads stderr" "True" "$(t7a limit_class)"
assert_eq "ExtractFailure.limit reads stdout, case-insensitive" "True" "$(t7a limit_class_stdout)"
assert_eq "ExtractFailure.limit catches the 5-hour shape" "True" "$(t7a limit_class_five_hour)"
assert_eq "ExtractFailure.limit is False on a plain failure" "False" "$(t7a limit_class_plain_fail)"

# ============================================================
echo "=== T7b quarantine and lift ==="

T7B_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import datetime, importlib.util, json, os, shlex
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD, NOW = os.environ["TD"], int(os.environ["T5_NOW"])
STUB = os.path.join(os.environ["KIT_DIR"], "tests", "fixtures", "harvest-sweep", "stub-extractor.sh")
P = lambda k, v: print("%s=%s" % (k, v))
n_scn = [0]

def scenario(now=NOW):
    n_scn[0] += 1
    base = os.path.join(TD, "t7b-s%d" % n_scn[0])
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base, "claude")
    os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(base, "none.db")
    os.environ["HARVEST_SWEEP_NOW"] = str(now)
    os.environ["HARVEST_EXTRACTOR"] = shlex.quote(STUB)
    for k in ("STUB_MODE", "STUB_OUT", "STUB_ERR", "STUB_RECORD", "STUB_FAIL_MATCH",
              "HARVEST_SWEEP_QUARANTINE_AFTER"):
        os.environ.pop(k, None)
    return base, os.environ["HARVEST_SWEEP_CLAUDE_ROOT"]

iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def mk(root, sid, la, n=6):
    d = os.path.join(root, "p")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": "/w/x",
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s msg %d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))

def cursor():
    with open(hs._cursor_path()) as fh:
        return json.load(fh)

run = lambda: hs.run_selection(schedule_hours=48)
rows = lambda res: " | ".join(res["claude"]["state_rows"])
LA_A, LA_B, LA_C = NOW - 7400, NOW - 7200, NOW - 7000
initial_hwm = NOW - 48 * 3600

# ---- AC5: the middle session quarantines on run 3, then lifts on new activity ----
base, root = scenario()
mk(root, "a", LA_A)
mk(root, "bad-b", LA_B)
mk(root, "c", LA_C)
os.environ["STUB_FAIL_MATCH"] = "bad-b"
r = run()
P("m_r1_processed", ",".join(r["claude"]["processed"]))
P("m_r1_fail", json.dumps(cursor()["claude"]["fail"]))
P("m_r1_hwm", cursor()["claude"]["hwm"] == LA_A)
run()
P("m_r2_fail", cursor()["claude"]["fail"].get("bad-b"))
P("m_r2_hwm", cursor()["claude"]["hwm"] == LA_A)
r = run()
P("m_r3_state_row", "quarantined" in rows(r))
P("m_r3_quar", cursor()["claude"]["quarantined"])
P("m_r3_done", hs._settled(cursor()["claude"], {"session_id": "bad-b", "last_activity": LA_B}))
P("m_r3_hwm", cursor()["claude"]["hwm"] == LA_C)
P("m_r3_processed", ",".join(r["claude"]["processed"]))
# an unchanged session stays quarantined
r = run()
P("m_r4_processed", ",".join(r["claude"]["processed"]))
P("m_r4_still", "bad-b" in cursor()["claude"]["quarantined"])
# new activity lifts it and the run extracts it
mk(root, "bad-b", NOW - 6900, n=8)
del os.environ["STUB_FAIL_MATCH"]
r = run()
P("m_lift_row", "quarantine lifted" in rows(r))
P("m_lift_processed", ",".join(r["claude"]["processed"]))
P("m_lift_quar", cursor()["claude"]["quarantined"])
P("m_lift_fail", cursor()["claude"]["fail"])
P("m_lift_done", cursor()["claude"]["done"].get("bad-b") == NOW - 6900)

# ---- AC5b: the oldest session quarantines on run 3 and the hwm moves past it ----
base, root = scenario()
mk(root, "bad-a", LA_A)
mk(root, "b", LA_B)
mk(root, "c", LA_C)
os.environ["STUB_FAIL_MATCH"] = "bad-a"
r = run()
P("o_r1_processed", ",".join(r["claude"]["processed"]))
P("o_r1_fail", cursor()["claude"]["fail"].get("bad-a"))
P("o_r1_hwm_held", cursor()["claude"]["hwm"] == initial_hwm)
run()
P("o_r2_fail", cursor()["claude"]["fail"].get("bad-a"))
r = run()
P("o_r3_fail", cursor()["claude"]["fail"].get("bad-a"))
P("o_r3_quar", "bad-a" in cursor()["claude"]["quarantined"])
P("o_r3_state_row", "quarantined" in rows(r))
P("o_r3_hwm", cursor()["claude"]["hwm"] == LA_C)
mk(root, "bad-a", NOW - 6900, n=8)
del os.environ["STUB_FAIL_MATCH"]
r = run()
P("o_lift_processed", ",".join(r["claude"]["processed"]))
P("o_lift_row", "quarantine lifted" in rows(r))
P("o_lift_fail", cursor()["claude"]["fail"])

# ---- AC5b: a failing probe on the oldest still quarantines on the third run ----
base, root = scenario()
mk(root, "bad-x", LA_A)
mk(root, "y", LA_B)
os.environ["STUB_MODE"] = "fail"
run()
P("p_r1_fail", cursor()["claude"]["fail"].get("bad-x"))
run()
r = run()
P("p_r3_stop", r["run"]["stop"])
P("p_r3_fail", cursor()["claude"]["fail"].get("bad-x"))
P("p_r3_quar", "bad-x" in cursor()["claude"]["quarantined"])
P("p_r3_state_row", "quarantined" in rows(r))
os.environ["STUB_MODE"] = "ok"
r = run()
P("p_r4_processed", ",".join(r["claude"]["processed"]))
P("p_r4_still", "bad-x" in cursor()["claude"]["quarantined"])
P("p_r4_hwm", cursor()["claude"]["hwm"] == LA_B)

# ---- the threshold is env-overridable ----
base, root = scenario()
mk(root, "bad-e", LA_A)
os.environ["HARVEST_SWEEP_QUARANTINE_AFTER"] = "1"
os.environ["STUB_MODE"] = "fail"
r = run()
P("e_quar", "bad-e" in cursor()["claude"]["quarantined"])
PY
)
t7b() { printf '%s\n' "$T7B_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC5: a failing middle session's run still completes A and C" "a,c" "$(t7b m_r1_processed)"
assert_eq "AC5: the middle session's fail count rises" '{"bad-b": 1}' "$(t7b m_r1_fail)"
assert_eq "AC5: the hwm never passes the failing middle session" "True" "$(t7b m_r1_hwm)"
assert_eq "AC5: run 2 increments the fail count again" "2" "$(t7b m_r2_fail)"
assert_eq "AC5: the hwm is still held after run 2" "True" "$(t7b m_r2_hwm)"
assert_eq "AC5: run 3 quarantines with a STATE row" "True" "$(t7b m_r3_state_row)"
assert_eq "AC5: quarantine stores the session's last_activity" "{'bad-b': {'last_activity': $((T5_NOW - 7200)), 'ts': $T5_NOW}}" "$(t7b m_r3_quar)"
assert_eq "AC5: the quarantined session counts as settled" "True" "$(t7b m_r3_done)"
assert_eq "AC5: the hwm moves past a quarantined session" "True" "$(t7b m_r3_hwm)"
assert_eq "AC5: an unchanged session stays quarantined" "" "$(t7b m_r4_processed)"
assert_eq "AC5: the quarantine persists without new activity" "True" "$(t7b m_r4_still)"
assert_eq "AC5: new activity lifts the quarantine with a STATE row" "True" "$(t7b m_lift_row)"
assert_eq "AC5: the lifted session is extracted" "bad-b" "$(t7b m_lift_processed)"
assert_eq "AC5: the lift clears the quarantine entry" "{}" "$(t7b m_lift_quar)"
assert_eq "AC5: the lift resets the fail count" "{}" "$(t7b m_lift_fail)"
assert_eq "AC5: the lifted session settles at its new activity" "True" "$(t7b m_lift_done)"

assert_eq "AC5b: the run continues past a failing oldest session" "b,c" "$(t7b o_r1_processed)"
assert_eq "AC5b: the oldest session's fail count rises" "1" "$(t7b o_r1_fail)"
assert_eq "AC5b: the hwm stays at the initial value while the oldest fails" "True" "$(t7b o_r1_hwm_held)"
assert_eq "AC5b: run 2 increments the oldest session's count" "2" "$(t7b o_r2_fail)"
assert_eq "AC5b: run 3 increments to the threshold" "3" "$(t7b o_r3_fail)"
assert_eq "AC5b: the oldest session is quarantined on run 3" "True" "$(t7b o_r3_quar)"
assert_eq "AC5b: the quarantine carries a STATE row" "True" "$(t7b o_r3_state_row)"
assert_eq "AC5b: the hwm then moves past the oldest session" "True" "$(t7b o_r3_hwm)"
assert_eq "AC5b: new activity lifts and extracts the oldest session" "bad-a" "$(t7b o_lift_processed)"
assert_eq "AC5b: the lift carries a STATE row" "True" "$(t7b o_lift_row)"
assert_eq "AC5b: the lift resets the oldest session's fail count" "{}" "$(t7b o_lift_fail)"

assert_eq "AC5b: a failing probe still increments the fail count" "1" "$(t7b p_r1_fail)"
assert_eq "AC5b: the run stops auth-shaped with the probe failing" "auth" "$(t7b p_r3_stop)"
assert_eq "AC5b: the count reaches the threshold on the stop path" "3" "$(t7b p_r3_fail)"
assert_eq "AC5b: the quarantine still lands on the stop path" "True" "$(t7b p_r3_quar)"
assert_eq "AC5b: the quarantine STATE row lands on the stop path" "True" "$(t7b p_r3_state_row)"
assert_eq "AC5b: the next run resumes past the quarantined session" "y" "$(t7b p_r4_processed)"
assert_eq "AC5b: an unchanged quarantine stays put" "True" "$(t7b p_r4_still)"
assert_eq "AC5b: the hwm passes the quarantined oldest session" "True" "$(t7b p_r4_hwm)"
assert_eq "AC5b: HARVEST_SWEEP_QUARANTINE_AFTER overrides the threshold" "True" "$(t7b e_quar)"

# ============================================================
echo "=== T8 sanitizing ==="

T8_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import datetime, importlib.util, json, os, shlex, stat
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD, NOW = os.environ["TD"], int(os.environ["T5_NOW"])
STUB = os.path.join(os.environ["KIT_DIR"], "tests", "fixtures", "harvest-sweep", "stub-extractor.sh")
FIX = os.path.join(os.environ["KIT_DIR"], "tests", "fixtures", "harvest-sweep")
P = lambda k, v: print("%s=%s" % (k, v))

base = os.path.join(TD, "t8")
os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base, "claude")
os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(base, "none.db")
os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
os.environ["HARVEST_EXTRACTOR"] = shlex.quote(STUB)

inj = open(os.path.join(FIX, "injection-evidence.txt")).read()
cred_lines = [l for l in open(os.path.join(FIX, "credential-evidence.txt")).read()
              .splitlines() if l.strip()]

# ---- every credential-shaped line redacts; the safe line is untouched ----
cred_tokens = {
    "hex": "0123456789abcdef0123456789abcdef01234567", "jwt": "eyJmYWtldG9rZW4",
    "pem": "PRIVATE KEY", "xoxb": "xoxb-fk"}
bad = []
for line in cred_lines:
    got = hs.redact(line)
    if line.startswith("safe words:"):
        if got != line:
            bad.append("safe line changed")
        continue
    if "[redacted]" not in got:
        bad.append("no redaction: " + line[:20])
        continue
    key = line.split()[0]
    token = cred_tokens.get(key, line.split()[1])
    if token in got:
        bad.append("token survived: " + line[:20])
P("redact_all", not bad and len(cred_lines) == 15)
P("redact_bad", ",".join(bad))
P("redact_31hex", hs.redact("f" * 31) == "f" * 31)
P("redact_32hex", hs.redact("b" * 32))
P("redact_word_boundary", hs.redact("task-list disk-usage") == "task-list disk-usage")

# ---- sanitize_text: redact first, then printable-only and the 200-char cut ----
s = hs.sanitize_text(inj)
P("inj_len_le200", len(s) <= 200)
P("inj_printable", all(32 <= ord(c) < 127 for c in s))
P("inj_no_chars", not any(c in s for c in "`<>$\n"))
P("inj_canary_survives", "INJECTION-CANARY" in s)   # the text stays, inert, charset-only
P("inj_not_raw", "$(rm -rf /)" not in s and "<script>" not in s)
P("san_long", len(hs.sanitize_text("x" * 300)))
P("san_unicode_gone", hs.sanitize_text("café snow ☃ ok") == "caf snow  ok")

# ---- a credential split by a stripped char still redacts (the strip joins it) ----
hex20 = "0a1b2c3d4e5f60718293"  # 20 hex chars, built at runtime
P("san_split_all", all("[redacted]" in hs.sanitize_text(hex20 + s + hex20)
                       for s in ("\n", "`", "<", ">", "$")))
P("san_split_no_join", (hex20 + hex20) not in hs.sanitize_text(hex20 + "\n" + hex20))

# ---- sanitize_extraction: bad slugs drop, evidence and why are cleaned ----
obj = hs.sanitize_extraction({
    "learnings": [
        {"item": "ok-slug", "kind": "insight", "home": "til", "why": "w `code` <b>$x</b>",
         "evidence": inj},
        {"item": "Bad Slug!", "kind": "insight", "home": "til", "why": "w", "evidence": "e"},
        {"item": "", "kind": "insight", "home": "til", "why": "w", "evidence": "e"}],
    "sightings": [
        {"pattern": "good-pattern", "kind": "repeat", "count": 3,
         "evidence": cred_lines[0]},
        {"pattern": "UPPER_case!", "kind": "repeat", "count": 1, "evidence": "e"}]})
P("obj_learn_n", len(obj["learnings"]))
P("obj_sight_n", len(obj["sightings"]))
P("obj_why_clean", obj["learnings"][0]["why"])
P("obj_ev_clean", all(c not in "`<>$\n" and 32 <= ord(c) < 127
                      for c in obj["learnings"][0]["evidence"]))
P("obj_sight_redacted", "[redacted]" in obj["sightings"][0]["evidence"]
                      and "0123456789" not in obj["sightings"][0]["evidence"])

# ---- sweep_process returns the sanitized object ----
t = {"source": "claude", "session_id": "sx", "last_activity": NOW - 7200, "messages": []}
os.environ["STUB_OUT"] = json.dumps({"learnings": [
    {"item": "ok-slug", "kind": "insight", "home": "til", "why": "w", "evidence": inj}],
    "sightings": [{"pattern": "p", "kind": "repeat", "count": 1,
                   "evidence": cred_lines[9]}]})
res = hs.sweep_process(t, "x")
P("proc_truthy", bool(res))
P("proc_sanitized", all(c not in "`<>$\n" for c in res["learnings"][0]["evidence"])
                    and "[redacted]" in res["sightings"][0]["evidence"])
del os.environ["STUB_OUT"]

# ---- stage1.log: ids and classes only, mode 0600, no transcript/extractor text ----
iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
d = os.path.join(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"], "p")
os.makedirs(d, exist_ok=True)
canary_tr = "TRANSCRIPT-CANARY-1"
canary_ex = "EXTRACTOR-CANARY-2"
with open(os.path.join(d, "s1.jsonl"), "w") as fh:
    for k in range(6):
        fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": "/w/x",
                             "timestamp": iso(NOW - 7200 - (6 - k) * 10),
                             "message": {"content": [{"type": "text",
                                          "text": "msg %d %s" % (k, canary_tr)}]}}) + "\n")
os.utime(os.path.join(d, "s1.jsonl"), (NOW - 7200, NOW - 7200))
os.environ["STUB_OUT"] = json.dumps({"learnings": [{"item": "ok", "kind": "insight",
    "home": "til", "why": "w", "evidence": "e %s" % canary_ex}], "sightings": []})
r = hs.run_selection(schedule_hours=48)
lp = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "runs",
                  r["run"]["run_id"], "stage1.log")
logtext = open(lp).read()
P("log_exists", True)
P("log_mode", oct(stat.S_IMODE(os.stat(lp).st_mode)))
P("log_processed_line", "processed claude s1" in logtext)
P("log_counts_line", "counts claude" in logtext)
P("log_no_transcript_text", canary_tr not in logtext)
P("log_no_extractor_text", canary_ex not in logtext)
P("log_no_json", '{"learnings"' not in logtext)

# ---- an idle run writes no runs/<run-id>/ directory ----
base2 = os.path.join(TD, "t8-idle")
os.environ["HARVEST_STATE_DIR"] = os.path.join(base2, "state")
os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base2, "claude")
os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
# an empty-but-valid devin db, so the idle run has no source failure either
import sqlite3
dbp = os.path.join(base2, "sessions.db")
conn = sqlite3.connect(dbp)
conn.execute("CREATE TABLE sessions (id TEXT PRIMARY KEY, working_directory TEXT NOT NULL,"
             " backend_type TEXT NOT NULL, model TEXT NOT NULL, agent_mode TEXT NOT NULL,"
             " created_at INTEGER NOT NULL, last_activity_at INTEGER NOT NULL,"
             " title TEXT, main_chain_id INTEGER, hidden INTEGER NOT NULL DEFAULT 0)")
conn.execute("CREATE TABLE message_nodes (row_id INTEGER PRIMARY KEY, session_id TEXT"
             " NOT NULL, node_id INTEGER NOT NULL, parent_node_id INTEGER,"
             " chat_message TEXT NOT NULL, created_at INTEGER NOT NULL)")
conn.commit(); conn.close()
os.environ["HARVEST_SWEEP_DEVIN_DB"] = dbp
del os.environ["STUB_OUT"]
r = hs.run_selection(schedule_hours=48)
P("idle_no_runs_dir", not os.path.exists(os.path.join(
    os.environ["HARVEST_STATE_DIR"], "sweep", "runs")))
PY
)
t8() { printf '%s\n' "$T8_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC22: every credential-shape fixture line redacts" "True" "$(t8 redact_all)"
assert_eq "AC22: redaction leaves no residue (empty = none leaked)" "" "$(t8 redact_bad)"
assert_eq "AC22: a 31-hex run is not a credential" "True" "$(t8 redact_31hex)"
assert_eq "AC22: a 32-hex run becomes [redacted]" "[redacted]" "$(t8 redact_32hex)"
assert_eq "AC22: words merely containing sk- or xox-shaped fragments stay" "True" "$(t8 redact_word_boundary)"

assert_eq "AC9: injection evidence is cut to at most 200 characters" "True" "$(t8 inj_len_le200)"
assert_eq "AC9: injection evidence is printable ASCII only" "True" "$(t8 inj_printable)"
assert_eq "AC9: injection evidence drops backticks, angles, \$, newlines" "True" "$(t8 inj_no_chars)"
assert_eq "AC9: the injection text stays inert, not executed" "True" "$(t8 inj_canary_survives)"
assert_eq "AC9: no raw metachar sequence survives" "True" "$(t8 inj_not_raw)"
assert_eq "AC9: the 200-character cut applies" "200" "$(t8 san_long)"
assert_eq "AC9: non-ASCII is dropped" "True" "$(t8 san_unicode_gone)"
assert_eq "AC9: a credential split by a stripped char still redacts" "True" "$(t8 san_split_all)"
assert_eq "AC9: the joined credential never reaches storage" "True" "$(t8 san_split_no_join)"

assert_eq "AC9: a learning with a bad slug is dropped, good ones kept" "1" "$(t8 obj_learn_n)"
assert_eq "AC9: a sighting with a bad pattern is dropped" "1" "$(t8 obj_sight_n)"
assert_eq "AC9: why is cleaned" "w code bx/b" "$(t8 obj_why_clean)"
assert_eq "AC9: evidence is cleaned" "True" "$(t8 obj_ev_clean)"
assert_eq "AC22: a credential in evidence becomes [redacted]" "True" "$(t8 obj_sight_redacted)"

assert_eq "sweep_process returns the sanitized object" "True" "$(t8 proc_truthy)"
assert_eq "sweep_process output is already redacted and cut" "True" "$(t8 proc_sanitized)"

assert_eq "stage1.log exists after a run that did work" "True" "$(t8 log_exists)"
assert_eq "stage1.log is mode 0600" "0o600" "$(t8 log_mode)"
assert_eq "stage1.log logs processed ids" "True" "$(t8 log_processed_line)"
assert_eq "stage1.log logs per-source counts" "True" "$(t8 log_counts_line)"
assert_eq "stage1.log never holds transcript text" "True" "$(t8 log_no_transcript_text)"
assert_eq "stage1.log never holds extractor text" "True" "$(t8 log_no_extractor_text)"
assert_eq "stage1.log holds no extractor JSON" "True" "$(t8 log_no_json)"
assert_eq "an idle run leaves no runs/ directory" "True" "$(t8 idle_no_runs_dir)"

# ============================================================
echo "=== T9 sweep ledgers ==="

T9_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import datetime, hashlib, importlib.util, json, os, shlex, shutil, sqlite3, subprocess
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD, NOW = os.environ["TD"], int(os.environ["T5_NOW"])
STUB = os.path.join(os.environ["KIT_DIR"], "tests", "fixtures", "harvest-sweep", "stub-extractor.sh")
P = lambda k, v: print("%s=%s" % (k, v))
base = os.path.join(TD, "t9")
repos = os.path.join(base, "repos")
iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def git(path, *args):
    return subprocess.run(["git", "-C", path] + list(args), capture_output=True,
                          text=True, check=True).stdout.strip()

LEDGER_HEAD = "| date | item | kind | home | status |\n|---|---|---|---|---|\n"
def lrow(item, status="queued"):
    return "| 2026-09-01 | %s | insight | til | %s |\n" % (item, status)

def mkgit(path, origin=None, extra_files=None):
    os.makedirs(path)
    subprocess.run(["git", "init", "-q", path], check=True)
    git(path, "config", "user.email", "t@t.test")
    git(path, "config", "user.name", "t")
    for rel, text in (extra_files or {}).items():
        fp = os.path.join(path, rel)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        with open(fp, "w") as fh:
            fh.write(text)
        git(path, "add", rel)
    with open(os.path.join(path, "seed"), "w") as fh:
        fh.write("x")
    git(path, "add", "seed")
    git(path, "commit", "-qm", "init")
    if origin:
        git(path, "remote", "add", "origin", origin)

# ---- fixture repos: two same-basename repos, one with origin, one without ----
repoO = os.path.join(repos, "o", "app")
repoP = os.path.join(repos, "p", "app")
mkgit(repoO, origin="git@github.com:dwarvesf/app.git", extra_files={
    "_meta/learned-ledger.md": LEDGER_HEAD + lrow("known-repo-row"),
    "_meta/learned-ledger.archive.md": LEDGER_HEAD + lrow("archived-repo-row"),
    "learning/x/GLOSSARY.md": "# gloss\n\n## gloss-row\n\nbody text\n"})
mkgit(repoP, extra_files={
    "_meta/learned-ledger.md": LEDGER_HEAD + lrow("p-known-row"),
    "_meta/learned-ledger.md.lock": ""})
# git's --path-format=absolute resolves symlinks (/var -> /private/var on macOS),
# so the hash slug is over the REAL path, matching the code under test.
slugO = "dwarvesf__app"
slugP = "app-" + hashlib.sha256(os.path.realpath(repoP).encode()).hexdigest()[:12]

# ---- fixture repo with a deleted .claude/worktrees worktree ----
mainr = os.path.join(repos, "mainr")
mkgit(mainr, origin="https://github.com/acme/mainr.git")
wt = os.path.join(mainr, ".claude", "worktrees", "wt1")
git(mainr, "worktree", "add", "--detach", wt)
shutil.rmtree(wt)
git(mainr, "worktree", "prune")

def empty_db(b):
    dbp = os.path.join(b, "sessions.db")
    conn = sqlite3.connect(dbp)
    conn.execute("CREATE TABLE sessions (id TEXT PRIMARY KEY, working_directory TEXT NOT NULL,"
                 " backend_type TEXT NOT NULL, model TEXT NOT NULL, agent_mode TEXT NOT NULL,"
                 " created_at INTEGER NOT NULL, last_activity_at INTEGER NOT NULL,"
                 " title TEXT, main_chain_id INTEGER, hidden INTEGER NOT NULL DEFAULT 0)")
    conn.execute("CREATE TABLE message_nodes (row_id INTEGER PRIMARY KEY, session_id TEXT"
                 " NOT NULL, node_id INTEGER NOT NULL, parent_node_id INTEGER,"
                 " chat_message TEXT NOT NULL, created_at INTEGER NOT NULL)")
    conn.commit(); conn.close()
    return dbp

root = os.path.join(base, "claude")
os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = root
os.makedirs(root)
os.environ["HARVEST_SWEEP_DEVIN_DB"] = empty_db(base)
os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
os.environ["HARVEST_EXTRACTOR"] = shlex.quote(STUB)

def mk(sid, la, cwd):
    d = os.path.join(root, "p")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(6):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": cwd,
                                 "timestamp": iso(la - (6 - k) * 10),
                                 "message": {"content": [{"type": "text",
                                              "text": "%s msg %d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))

def learn(item):
    return {"item": item, "kind": "insight", "home": "til",
            "why": "why %s" % item, "evidence": "evidence for %s" % item}

# pre-seed the repoO sweep ledger: a queued row with no sidecar (the crash repair
# case) plus an archive sibling (the DEC-70 dedup case)
leddir = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "ledger")
os.makedirs(leddir)
with open(os.path.join(leddir, slugO + ".md"), "w") as fh:
    fh.write(LEDGER_HEAD + lrow("crash-row"))
with open(os.path.join(leddir, slugO + ".archive.md"), "w") as fh:
    fh.write(LEDGER_HEAD + lrow("sweep-arch-row", status="flushed:abc"))

mk("s-a", NOW - 7200, repoO)
mk("s-b", NOW - 7200, repoP)
mk("s-wt", NOW - 7200, wt)
mk("s-nr", NOW - 7200, "/nonexistent/deep/path")
os.environ["STUB_OUT"] = json.dumps({"learnings": [
    learn(x) for x in ("shared-item", "known-repo-row", "archived-repo-row",
                       "gloss-row", "sweep-arch-row", "crash-row", "fresh-row",
                       "p-known-row")],
    "sightings": []})

# ---- AC11 snapshots before the run ----
def snapshot(r):
    return {"head": git(r, "rev-parse", "HEAD"),
            "branch": git(r, "rev-parse", "--abbrev-ref", "HEAD"),
            "config": open(os.path.join(r, ".git", "config")).read(),
            "worktrees": git(r, "worktree", "list"),
            "status": git(r, "status", "--porcelain"),
            "meta": open(os.path.join(r, "_meta", "learned-ledger.md")).read()
                    if os.path.exists(os.path.join(r, "_meta", "learned-ledger.md")) else None}
before = {r: snapshot(r) for r in (repoO, repoP, mainr)}

r = hs.run_selection(schedule_hours=48)
sweep_led = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "ledger")

def ledger_items(slug):
    """Sorted col-2 items of a sweep ledger, None when the file does not exist."""
    p = os.path.join(sweep_led, slug + ".md")
    if not os.path.exists(p):
        return None
    items = []
    for line in open(p):
        cells = [c.strip() for c in line.split("|")]
        if len(cells) >= 4 and cells[1].startswith("202"):
            items.append(cells[2])
    return sorted(items)

P("processed", ",".join(sorted(r["claude"]["processed"])))
P("ledO_items", ",".join(ledger_items(slugO) or []))
P("ledP_exists", os.path.exists(os.path.join(sweep_led, slugP + ".md")))
P("ledP_has_shared", "shared-item" in (ledger_items(slugP) or []))
P("ledP_has_pknown", "p-known-row" in (ledger_items(slugP) or []))
P("ledWT_exists", os.path.exists(os.path.join(sweep_led, "acme__mainr.md")))
P("ledWT_items", ",".join(ledger_items("acme__mainr") or []))
P("ledNR_exists", os.path.exists(os.path.join(sweep_led, "_no-repo.md")))

# ---- sidecar rows ----
side = [json.loads(l) for l in open(os.path.join(sweep_led, slugO + ".rows.jsonl"))]
by_id = {s["row_id"]: s for s in side}
fr = by_id.get(slugO + ":fresh-row", {})
P("side_fresh", "%s|%s|%s|%s" % (fr.get("why"), fr.get("evidence"),
                                 fr.get("source"), fr.get("lead_session_id")))
P("side_crash", slugO + ":crash-row" in by_id)
P("side_no_dupes", len(side) == len(by_id))
P("side_no_known", slugO + ":known-repo-row" not in by_id)
sideP = {s["row_id"] for s in (json.loads(l) for l in
         open(os.path.join(sweep_led, slugP + ".rows.jsonl")))}
P("sideP_shared", slugP + ":shared-item" in sideP and slugO + ":shared-item" in by_id)

# ---- AC11: the repos are byte-identical after the run ----
after = {r: snapshot(r) for r in (repoO, repoP, mainr)}
P("repo_same", before == after)
P("repoO_no_lock", not os.path.exists(os.path.join(repoO, "_meta", "learned-ledger.md.lock")))
P("repoP_lock_kept", os.path.exists(os.path.join(repoP, "_meta", "learned-ledger.md.lock")))

# ---- second run is a no-op for the ledgers and sidecars ----
led_state = {f: open(os.path.join(sweep_led, f)).read() for f in os.listdir(sweep_led)}
hs.run_selection(schedule_hours=48)
led_state2 = {f: open(os.path.join(sweep_led, f)).read() for f in os.listdir(sweep_led)}
P("second_run_same", led_state == led_state2)

# ---- slug resolution edges ----
P("slug_norepo", hs.repo_slug("/nonexistent/deep/path")[0])
P("slug_wt", hs.repo_slug(wt)[0])
P("slug_deep_in_wt_parent", hs.repo_slug(os.path.join(wt, "src", "pkg"))[0])
P("slugP_shape", hs.repo_slug(repoP)[0] == slugP)
P("slugO_shape", hs.repo_slug(repoO)[0])
PY
)
t9() { printf '%s\n' "$T9_OUT" | sed -n "s/^$1=//p"; }

assert_eq "T9: all four sessions processed" "s-a,s-b,s-nr,s-wt" "$(t9 processed)"
assert_eq "AC26: repoO ledger has only the fresh, shared, and pre-seeded rows" "crash-row,fresh-row,p-known-row,shared-item" "$(t9 ledO_items)"
assert_eq "AC26: the same-basename repo gets its own hash-slug ledger" "True" "$(t9 ledP_exists)"
assert_eq "AC26: shared-item lands in both ledgers" "True" "$(t9 ledP_has_shared)"
assert_eq "AC26: repoP's _meta row dedups too" "False" "$(t9 ledP_has_pknown)"
assert_eq "AC1: a deleted-worktree cwd resolves to its main repo's slug" "True" "$(t9 ledWT_exists)"
assert_eq "AC1: the deleted-worktree session staged into the main slug" "archived-repo-row,crash-row,fresh-row,gloss-row,known-repo-row,p-known-row,shared-item,sweep-arch-row" "$(t9 ledWT_items)"
assert_eq "AC26: a cwd outside any repo lands in _no-repo.md" "True" "$(t9 ledNR_exists)"
assert_eq "AC29: sidecar entry carries why, evidence, source, lead" "why fresh-row|evidence for fresh-row|claude/s-a|None" "$(t9 side_fresh)"
assert_eq "AC29: the pre-seeded row's missing sidecar entry is repaired" "True" "$(t9 side_crash)"
assert_eq "AC29: sidecar has no duplicate row ids" "True" "$(t9 side_no_dupes)"
assert_eq "AC29: a deduped row gets no sidecar entry" "True" "$(t9 side_no_known)"
assert_eq "AC26: row ids never collide across same-basename repos" "True" "$(t9 sideP_shared)"
assert_eq "AC11: every fixture repo is byte-identical after the run" "True" "$(t9 repo_same)"
assert_eq "AC11: no .lock file appears in a repo that had none" "True" "$(t9 repoO_no_lock)"
assert_eq "AC11: an existing repo .lock survives and the read still works" "True" "$(t9 repoP_lock_kept)"
assert_eq "AC2: a second run leaves ledgers and sidecars byte-identical" "True" "$(t9 second_run_same)"
assert_eq "AC26: a nonexistent cwd slugs _no-repo" "_no-repo" "$(t9 slug_norepo)"
assert_eq "AC1: the deleted worktree path slugs to its main repo" "acme__mainr" "$(t9 slug_wt)"
assert_eq "AC1: a path under the deleted worktree slugs to its main repo" "acme__mainr" "$(t9 slug_deep_in_wt_parent)"
assert_eq "AC26: a no-origin repo slugs <basename>-<12 hex of its path hash>" "True" "$(t9 slugP_shape)"
assert_eq "AC26: an origin repo slugs <owner>__<name>" "dwarvesf__app" "$(t9 slugO_shape)"

# ============================================================
echo "=== T10 pattern aggregation ==="

T10_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import importlib.util, json, os, shlex
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD, NOW = os.environ["TD"], int(os.environ["T5_NOW"])
STUB = os.path.join(os.environ["KIT_DIR"], "tests", "fixtures", "harvest-sweep", "stub-extractor.sh")
P = lambda k, v: print("%s=%s" % (k, v))
DAY = 86400
os.environ["HARVEST_STATE_DIR"] = os.path.join(TD, "t10", "state")
os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
patterns_p = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "patterns.jsonl")
proposed_p = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "proposed.jsonl")

def t(sid, lead=None, la=None, source="claude", cwd="/work/app"):
    return {"source": source, "session_id": sid, "lead_session_id": lead,
            "cwd": cwd, "last_activity": la if la is not None else NOW}

def sight(pattern, count=1, kind="repeat", evidence=None):
    return {"pattern": pattern, "kind": kind, "count": count,
            "evidence": evidence or ("ev " + pattern)}

def rows():
    return [json.loads(l) for l in open(patterns_p)] if os.path.exists(patterns_p) else []

def occ(c, now=None):
    return hs.pattern_stats(now or NOW).get(c, {}).get("occurrences", 0)

def candset(now=None):
    return {c["pattern"] for c in hs.candidates(now or NOW)}

# ---- AC7: two lead groups at count 1 do not qualify; a third does ----
hs._record_sightings(t("s1", lead="L1"), [sight("watch-retry-loop")])
hs._record_sightings(t("s2", lead="L2"), [sight("watch-retry-loop")])
P("cand_two_groups", ",".join(sorted(candset())))
hs._record_sightings(t("s3", lead="L3"), [sight("watch-retry-loop")])
P("occ_three", occ("watch-retry-loop"))
P("cand_three_groups", "watch-retry-loop" in candset())

# ---- AC7: one session sighting count 3 qualifies ----
hs._record_sightings(t("s4"), [sight("solo-thrice", count=3)])
P("cand_count3", "solo-thrice" in candset())

# ---- AC7: two delta windows of count 2 sum to 4; a replay adds nothing ----
t5 = t("s5")
hs._record_sightings(t5, [sight("delta-sum", count=2)])
hs._record_sightings(dict(t5, last_activity=NOW + 100), [sight("delta-sum", count=2)])
dump = open(patterns_p).read()
P("occ_delta", occ("delta-sum"))
# the replay lands at a later NOW: byte-identity requires the kept ts
os.environ["HARVEST_SWEEP_NOW"] = str(NOW + 5000)
hs._record_sightings(dict(t5, last_activity=NOW + 100), [sight("delta-sum", count=2)])
os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
P("delta_replay_bytes", open(patterns_p).read() == dump)
P("occ_delta_replay", occ("delta-sum"))

# ---- AC7: seven devin workers on one lead count as 1 group, 7 sessions ----
for i in range(7):
    hs._record_sightings(t("w%d" % i, lead="lead-9", source="devin"),
                         [sight("shared-hand-work")])
st = hs.pattern_stats(NOW)["shared-hand-work"]
P("occ_workers", st["occurrences"])
P("sess_workers", st["sessions"])
P("leads_workers", st["leads"])
P("cand_workers", "shared-hand-work" in candset())

# ---- AC7: an ask qualifies at count 1; one repeat sighting does not ----
hs._record_sightings(t("s6"), [sight("handoff-button-pls", kind="ask")])
hs._record_sightings(t("s6b"), [sight("single-repeat-sighting")])
P("cand_ask", "handoff-button-pls" in candset())
P("cand_single1", "single-repeat-sighting" in candset())

# ---- AC7: fuzzy clusters ----
hs._record_sightings(t("s7"), [sight("commit-hook-false-block")])
hs._record_sightings(t("s8"), [sight("commit-hok-false-block")])
P("canon_cluster", ",".join(sorted({r["canonical"] for r in rows()
                           if r["pattern"].endswith("false-block")})))
P("occ_cluster", occ("commit-hook-false-block"))
hs._record_sightings(t("s9"), [sight("fix-lint")])
hs._record_sightings(t("sA"), [sight("fix-link")])
P("canon_short", ",".join(sorted({r["canonical"] for r in rows()
                         if r["pattern"] in ("fix-lint", "fix-link")})))
# length-diff 3 stays two even when the distance threshold would cover it
os.environ["HARVEST_SWEEP_FUZZY"] = "4"
hs._record_sightings(t("sB"), [sight("nightly-retry-runs-ok")])
hs._record_sightings(t("sC"), [sight("nightly-retry-runs")])
P("canon_lendiff", ",".join(sorted({r["canonical"] for r in rows()
                           if r["pattern"].startswith("nightly-retry")})))
del os.environ["HARVEST_SWEEP_FUZZY"]

# ---- window: a sighting older than 14 days falls out of the stats ----
os.environ["HARVEST_SWEEP_NOW"] = str(NOW - 20 * DAY)
for sid in ("o1", "o2", "o3"):
    hs._record_sightings(t(sid), [sight("stale-window-pat")])
os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
P("occ_stale_window", occ("stale-window-pat"))

# ---- re-propose rule over a 30-day window ----
os.environ["HARVEST_SWEEP_PATTERN_WINDOW_DAYS"] = "30"
os.environ["HARVEST_SWEEP_NOW"] = str(NOW - 20 * DAY)
for sid in ("b1", "b2", "b3"):
    hs._record_sightings(t(sid), [sight("blocked-pat")])
hs._record_sightings(t("u0"), [sight("unblocked-pat")])
os.environ["HARVEST_SWEEP_NOW"] = str(NOW - DAY)
hs._record_sightings(t("b4"), [sight("blocked-pat")])
for sid in ("u1", "u2", "u3", "f1", "f2", "f3"):
    hs._record_sightings(t(sid), [sight("unblocked-pat")])
for sid in ("n1", "n2", "n3"):
    hs._record_sightings(t(sid), [sight("fresh-rep-pat")])
    hs._record_sightings(t(sid), [sight("nonrep-pat")])
os.makedirs(os.path.dirname(proposed_p), exist_ok=True)
with open(proposed_p, "w") as fh:
    for pat, outcome, ts in (("blocked-pat", "REPORTED", NOW - 15 * DAY),
                             ("unblocked-pat", "REPORTED", NOW - 15 * DAY),
                             ("fresh-rep-pat", "REPORTED", NOW - 10 * DAY),
                             ("nonrep-pat", "BUILT", NOW - DAY)):
        fh.write(json.dumps({"pattern": pat, "run_id": "run-1",
                             "outcome": outcome, "ts": ts}) + "\n")
os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
cands = candset()
P("reprop_fresh", "fresh-rep-pat" in cands)          # REPORTED 10d ago: blocked
P("reprop_stale_growth", "unblocked-pat" in cands)   # 15d + 3 new: re-qualifies
P("reprop_stale_low", "blocked-pat" in cands)        # 15d + only 1 new: blocked
P("reprop_nonrep", "nonrep-pat" in cands)            # a BUILT entry never blocks
del os.environ["HARVEST_SWEEP_PATTERN_WINDOW_DAYS"]

# ---- wiring: sweep_process records the sanitized sighting row ----
os.environ["HARVEST_EXTRACTOR"] = shlex.quote(STUB)
os.environ["STUB_OUT"] = json.dumps({"learnings": [], "sightings": [
    {"pattern": "wired-sighting", "kind": "repeat", "count": 2,
     "evidence": "raw <tag> `tick` $var"}]})
ok = hs.sweep_process(t("sw1", cwd="/nonexistent/deep"), "transcript text")
wired = [r for r in rows() if r["pattern"] == "wired-sighting"][0]
P("wired_ok", bool(ok))
P("wired_row", "%s|%s|%s|%s|%s" % (wired["canonical"], wired["count"],
                                   wired["extract_key"], wired["source"],
                                   wired["lead_session_id"]))
P("wired_evidence", wired["evidence"])
P("wired_keys", ",".join(sorted(wired.keys())))
PY
)
t10() { printf '%s\n' "$T10_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC7: two lead groups sighting once produce no candidate" "" "$(t10 cand_two_groups)"
assert_eq "AC7: a third lead group reaches the threshold" "3" "$(t10 occ_three)"
assert_eq "AC7: the third group produces a candidate" "True" "$(t10 cand_three_groups)"
assert_eq "AC7: one session at count 3 produces a candidate" "True" "$(t10 cand_count3)"
assert_eq "AC7: two delta windows of one session sum to 4" "4" "$(t10 occ_delta)"
assert_eq "AC7: replaying a window leaves the file byte-identical" "True" "$(t10 delta_replay_bytes)"
assert_eq "AC7: a replayed window does not raise the total" "4" "$(t10 occ_delta_replay)"
assert_eq "AC7: seven workers on one lead count as one group" "1" "$(t10 occ_workers)"
assert_eq "AC7: the raw session count beside the group count is 7" "7" "$(t10 sess_workers)"
assert_eq "AC7: the lead-group count is 1" "1" "$(t10 leads_workers)"
assert_eq "AC7: one group at count 1 is no candidate" "False" "$(t10 cand_workers)"
assert_eq "AC7: an ask qualifies at count 1" "True" "$(t10 cand_ask)"
assert_eq "AC7: one repeat sighting of count 1 never qualifies" "False" "$(t10 cand_single1)"
assert_eq "AC7: commit-hook-false-block and commit-hok-false-block share one canonical" "commit-hook-false-block" "$(t10 canon_cluster)"
assert_eq "AC7: the cluster sums both sightings" "2" "$(t10 occ_cluster)"
assert_eq "AC7: fix-lint and fix-link stay two slugs under the 12-char floor" "fix-link,fix-lint" "$(t10 canon_short)"
assert_eq "AC7: a length gap of 3 never clusters even at FUZZY=4" "nightly-retry-runs,nightly-retry-runs-ok" "$(t10 canon_lendiff)"
assert_eq "AC7: sightings older than the window fall out" "0" "$(t10 occ_stale_window)"
assert_eq "AC7: a REPORTED entry under 14 days blocks re-proposing" "False" "$(t10 reprop_fresh)"
assert_eq "AC7: a stale REPORTED re-proposes once occurrences grew by the threshold" "True" "$(t10 reprop_stale_growth)"
assert_eq "AC7: a stale REPORTED keeps blocking on growth under the threshold" "False" "$(t10 reprop_stale_low)"
assert_eq "AC7: a non-REPORTED proposed entry never blocks" "True" "$(t10 reprop_nonrep)"
assert_eq "T10: sweep_process records the sanitized sighting" "True" "$(t10 wired_ok)"
assert_eq "T10: the recorded row carries canonical, count, extract key, source, lead" "wired-sighting|2|sw1@$((T5_NOW))|claude|None" "$(t10 wired_row)"
assert_eq "T10: sighting evidence is stored sanitized" "raw tag tick var" "$(t10 wired_evidence)"
assert_eq "T10: the sighting row has the spec's keys" "canonical,count,cwd,evidence,extract_key,kind,lead_session_id,pattern,session_id,source,ts" "$(t10 wired_keys)"

# ============================================================
echo "=== T11 annotator ==="

T11_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import importlib.util, json, os, subprocess
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
KIT, TD, NOW = (os.environ["KIT_DIR"], os.environ["TD"], int(os.environ["T5_NOW"]))
FIX = os.path.join(KIT, "tests", "fixtures", "harvest-sweep")
P = lambda k, v: print("%s=%s" % (k, v))
DAY = 86400
base = os.path.join(TD, "t11")
os.makedirs(base, exist_ok=True)
os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
os.environ["HARVEST_SWEEP_PRECEDENT"] = os.path.join(FIX, "stub-precedent.sh")
os.environ["HARVEST_SWEEP_LANE_CLASSIFY"] = os.path.join(FIX, "stub-lane-classify.sh")
os.environ["STUB_PRECEDENT_RECORD"] = os.path.join(base, "prec-rec")
os.environ["STUB_LANE_RECORD"] = os.path.join(base, "lane-rec")
os.environ["STUB_LANE"] = "backfill"
HITS_FILE = os.path.join(base, "hits.json")
os.environ["STUB_PRECEDENT_HITS_FILE"] = HITS_FILE

def t(sid, lead=None):
    return {"source": "claude", "session_id": sid, "lead_session_id": lead,
            "cwd": "/work/app", "last_activity": NOW}

def sight(pattern, kind="repeat", count=1, evidence=None):
    return {"pattern": pattern, "kind": kind, "count": count,
            "evidence": evidence or ("ev " + pattern)}

def write_hits(arr):
    with open(HITS_FILE, "w") as fh:
        json.dump(arr, fh)

def rec(name):
    return open(os.path.join(os.environ["STUB_%s_RECORD" % name], "argv")).read().splitlines()

def cands_for(pattern, n=3, evidence=None):
    for i in range(n):
        hs._record_sightings(t("%s-%d" % (pattern[:6], i)),
                             [sight(pattern, evidence=evidence)])
    return [c for c in hs.candidates(NOW) if c["pattern"] == pattern]

# ---- AC18: a code home beats a prose home in one hit list ----
write_hits(["memory/notes/retry-proc.md  , the hand procedure",
            "tools/retry/bin/retry.sh  , retries flaky jobs"])
mc = cands_for("mixed-home-pat", evidence="did it by hand")[0]
annotated, prose = hs.annotate_candidates([mc], "run-t1", NOW)
mc = annotated[0]
P("mixed_home", mc["home"])
P("mixed_prec", mc["precedent"])
P("mixed_prose", "mixed-home-pat" in prose)
P("mixed_line", hs.reported_line(mc))
P("argv_prec", "|".join(rec("PRECEDENT")))
P("argv_lane", "|".join(rec("LANE")))
P("lane_used", mc["lane"])

# ---- AC18: an all-prose hit list lands one PROSE-ONLY bullet and lint rc 0 ----
ap = cands_for("all-prose-pat", evidence="notes say do it")[0]
write_hits(["memory/notes/proc-a.md  , hand procedure",
            "research/2026-09-10-proc.md  , research note"])
annotated2, prose2 = hs.annotate_candidates([ap], "run-t2", NOW)
ap = annotated2[0]
P("prose_home", ap["home"])
P("prose_flag", "all-prose-pat" in prose2)
P("prose_line", hs.prose_only_line(prose2))
bullets = [hs.reported_line(ap)] + ([hs.prose_only_line(prose2)] if prose2 else [])
report = "\n".join(["## Harvest sweep: run-t2", "",
                    "**Needs you:** NOTHING", "",
                    "**Built:**"] + bullets + [
                    "", "**Seam:** SKIPPED: the sweep runs no seams in phase 1",
                    "", "**What happened**", "- body"])
rp = os.path.join(base, "report.md")
with open(rp, "w") as fh:
    fh.write(report)
lint = subprocess.run(["bash", os.path.join(KIT, "lib", "wrap", "report-lint.sh"), rp],
                      capture_output=True, text=True)
P("prose_lint_rc", lint.returncode)
P("prose_lint_err", lint.stderr.strip().splitlines()[0] if lint.stderr.strip() else "")

# ---- AC15: a precedent miss records NEW ----
nm = cands_for("no-match-pat")[0]
write_hits([])
annotated3, _ = hs.annotate_candidates([nm], "run-t3", NOW)
nm = annotated3[0]
P("new_prec", nm["precedent"])
P("new_line", hs.reported_line(nm))

# ---- AC15: proposed.jsonl rows are REPORTED, and a rerun reports nothing again ----
prows = [json.loads(l) for l in open(os.path.join(
    os.environ["HARVEST_STATE_DIR"], "sweep", "proposed.jsonl"))]
prow = [r for r in prows if r["pattern"] == "mixed-home-pat"][0]
P("prow", "%s|%s|%s|%s" % (prow["outcome"], prow["run_id"], prow["precedent"], prow["lane"]))
P("prow_keys", ",".join(sorted(prow.keys())))
rest = [c["pattern"] for c in hs.candidates(NOW)
        if c["pattern"] in ("mixed-home-pat", "all-prose-pat", "no-match-pat")]
P("rerun_blocked", ",".join(rest))

# ---- AC23: metachar evidence is one argv element, never shell-split ----
marker = os.path.join(base, "pwned")
evil = "ok ; mkdir %s |& ' \"q\" ;" % marker
pc = cands_for("pwn-evidence-pat", evidence=evil)[0]
write_hits([])
hs.annotate_candidates([pc], "run-t4", NOW)
lane_argv = rec("LANE")
P("pwn_marker", os.path.exists(marker))
P("pwn_argv_one", lane_argv[-1] == "pwn evidence pat: %s" % evil)
P("pwn_argv_head", "|".join(lane_argv[:-1]))
PY
)
t11() { printf '%s\n' "$T11_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC18: the code hit beats an earlier prose hit" "tools/retry/bin/retry.sh" "$(t11 mixed_home)"
assert_eq "AC15: a hit records ENHANCE <home>" "ENHANCE tools/retry/bin/retry.sh" "$(t11 mixed_prec)"
assert_eq "AC18: a code-homed candidate is not prose-only" "False" "$(t11 mixed_prose)"
assert_eq "T11: the REPORTED bullet carries home, hit, lane, and the phase-1 closure" "- REPORTED mixed-home-pat ENHANCE tools/retry/bin/retry.sh: retries flaky jobs (lane=backfill, reported: phase 1 reports only)" "$(t11 mixed_line)"
assert_eq "AC23: precedent runs argv-style with the slug words as one arg" "find|--surface|inventory|--json|mixed home pat" "$(t11 argv_prec)"
assert_eq "AC23: lane-classify gets '<slug words>: <first evidence line>' as one arg" "classify|mixed home pat: did it by hand" "$(t11 argv_lane)"
assert_eq "AC15: the lane comes from lane-classify" "backfill" "$(t11 lane_used)"
assert_eq "AC18: an all-prose list homes the top prose hit" "memory/notes/proc-a.md" "$(t11 prose_home)"
assert_eq "AC18: the all-prose candidate is flagged prose-only" "True" "$(t11 prose_flag)"
assert_eq "AC18: the one PROSE-ONLY bullet names the slug and the phase-1 rule" "- PROSE-ONLY: all-prose-pat: only prose homes matched; phase 1 reports and builds nothing" "$(t11 prose_line)"
assert_eq "AC18: an all-prose report with the PROSE-ONLY bullet lints rc 0" "0" "$(t11 prose_lint_rc)"
assert_eq "AC15: a precedent miss records NEW (precedent: nothing matched)" "NEW (precedent: nothing matched)" "$(t11 new_prec)"
assert_eq "T11: the NEW bullet names the slug after the colon" "- REPORTED no-match-pat NEW (precedent: nothing matched): no-match-pat (lane=backfill, reported: phase 1 reports only)" "$(t11 new_line)"
assert_eq "AC15: the proposed.jsonl row is REPORTED with precedent and lane" "REPORTED|run-t1|ENHANCE tools/retry/bin/retry.sh|backfill" "$(t11 prow)"
assert_eq "AC15: the proposed row has the spec's keys" "lane,outcome,pattern,precedent,run_id,ts" "$(t11 prow_keys)"
assert_eq "AC15: a REPORTED candidate is not reported again next run" "" "$(t11 rerun_blocked)"
assert_eq "AC23: a shell-interpreted ';' would have made a marker; none exists" "False" "$(t11 pwn_marker)"
assert_eq "AC23: the metachar evidence arrives as one argv element, byte for byte" "True" "$(t11 pwn_argv_one)"
assert_eq "AC23: the lane call itself is classify plus the one query arg" "classify" "$(t11 pwn_argv_head)"

# ============================================================
echo ""
echo "=== T12 sweep_report lint flag ==="

# AC10: a `## Harvest sweep:` report is its own report kind in report-lint.sh
# (sweep_report, separate from follow_report so the Seam rule survives): every
# Built item opens with REPORTED, Seam stays required, and a wrap-mode report
# with the harvest SKIPPED lines still passes.
LINT="$KIT_DIR/lib/wrap/report-lint.sh"
FX="$KIT_DIR/tests/fixtures/harvest-sweep"

out="$(bash "$LINT" "$FX/report-reported-ok.md" 2>&1)"; rc=$?
assert_eq "AC10: an all-REPORTED sweep report passes" "0" "$rc"
assert_eq "AC10: the pass reports clean" "report-lint: clean (0 warn(s))" "$out"

out="$(bash "$LINT" "$FX/report-sweep-built.md" 2>&1)"; rc=$?
assert_eq "AC10: a BUILT item in a sweep report fails" "1" "$rc"
assert_eq "AC10: the finding names the phase-1 REPORTED rule" "line 0: '**Built:**' item 1 claims a build in a sweep report; the sweep builds nothing in phase 1, so every item opens with REPORTED" "$(printf '%s\n' "$out" | sed -n '1p')"
assert_eq "AC10: a NOTE item in a sweep report fails too" "line 0: '**Built:**' item 2 claims a build in a sweep report; the sweep builds nothing in phase 1, so every item opens with REPORTED" "$(printf '%s\n' "$out" | sed -n '3p')"

out="$(bash "$LINT" "$FX/report-sweep-no-seam.md" 2>&1)"; rc=$?
assert_eq "AC10: a sweep report without Seam still fails (the Seam rule is kept)" "1" "$rc"
assert_eq "AC10: the finding is the missing Seam line" "line 0: no '**Seam:**' line; step -1 (the before/after seams) owes an outcome" "$(printf '%s\n' "$out" | sed -n '1p')"

out="$(bash "$LINT" "$FX/report-wrap-harvest-skip.md" 2>&1)"; rc=$?
assert_eq "AC10: a wrap report with both 'SKIPPED: distill runs in the harvest sweep' lines passes" "0" "$rc"

# the sweep heading keys on the first `## ` line only; a report that opens with a
# different heading keeps the ordinary rules
out="$(sed '1s/^## Harvest sweep:.*/## Wrap: plain/' "$FX/report-sweep-built.md" | bash "$LINT" 2>&1)"; rc=$?
assert_eq "AC10: the same Built list passes when the heading is not a sweep heading" "0" "$rc"

# ============================================================
echo ""
echo "=== T13b pruning ==="

# AC31: every age rule in one run -- patterns past the window, proposed past 90d,
# quarantine and seen{} past 30d, extract/ files and runs/ dirs past 30d -- and an
# eligible unread session is never touched whatever its age. The run is an empty
# scan (no sessions): pruning is per-run bookkeeping in _finish_run.
T13B_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" python3 - <<'PY'
import importlib.util, json, os
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
TD = os.environ["TD"]
NOW = 2_000_000_000
D = 86400
P = lambda k, v: print("%s=%s" % (k, v))

base = os.path.join(TD, "t13b")
state_dir = os.path.join(base, "state")
sweep = os.path.join(state_dir, "sweep")
os.environ["HARVEST_STATE_DIR"] = state_dir
os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base, "claude")
os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(base, "none.db")
os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
os.makedirs(sweep)

def wj(name, rows):
    with open(os.path.join(sweep, name), "w") as fh:
        for r in rows:
            fh.write(json.dumps(r, sort_keys=True) + "\n")

wj("patterns.jsonl", [{"pattern": "p-old", "canonical": "p-old", "kind": "rule",
                       "session_id": "s", "extract_key": "s@1", "count": 1, "ts": NOW - 15 * D},
                      {"pattern": "p-edge", "canonical": "p-edge", "kind": "rule",
                       "session_id": "s", "extract_key": "s@1", "count": 1, "ts": NOW - 14 * D},
                      {"pattern": "p-new", "canonical": "p-new", "kind": "rule",
                       "session_id": "s", "extract_key": "s@2", "count": 1, "ts": NOW - D}])
wj("proposed.jsonl", [{"pattern": "x-old", "outcome": "REPORTED", "ts": NOW - 91 * D},
                      {"pattern": "x-new", "outcome": "REPORTED", "ts": NOW - 10 * D}])

cursor = {"claude": {"hwm": 5000,
                     "done": {"olddone": 4000, "newdone": 6000, "q-new": 8000,
                              "freshs": NOW - 5 * D},
                     "seen": {"s-old": {"last_ts": 1, "ts": NOW - 31 * D},
                              "s-edge": {"last_ts": 1, "ts": NOW - 30 * D},
                              "s-new": {"last_ts": 1, "ts": NOW - D}},
                     "fail": {},
                     "quarantined": {"q-old": {"last_activity": 7000, "ts": NOW - 31 * D},
                                     "q-new": {"last_activity": 8000, "ts": NOW - 2 * D}}}}
with open(hs._cursor_path(), "w") as fh:
    json.dump(cursor, fh)

# Cache-file age is the key's last_activity, the sweep's clock domain: the planted
# keys sit at epoch ~5000-9500, far past the 30-day cutoff under NOW=2e9.
ed = os.path.join(sweep, "extract", "claude")
os.makedirs(ed)
def exf(name, age_days=40):
    p = os.path.join(ed, name)
    with open(p, "w") as fh:
        fh.write("{}")
    os.utime(p, (NOW - age_days * D, NOW - age_days * D))
exf("olddone@4000.json")               # settled history (la < hwm): prune
exf("q-new@8000.json")                 # settled via the fresh quarantine: prune
exf("newdone@6000.json")               # settled via done{} at la >= hwm: prune
exf("pend@9500.json")                  # la >= hwm, never settled: unread, keep
exf("q-old@7000.json")                 # quarantine expires this run -> eligible again: keep
exf("freshs@%d.json" % (NOW - 5 * D))  # settled but inside 30 days: keep
exf(".tmp-stray")                      # residue of a killed write, old mtime: prune

rd = os.path.join(sweep, "runs")
os.makedirs(os.path.join(rd, "run-%d" % (NOW - 40 * D)))
with open(os.path.join(rd, "run-%d" % (NOW - 40 * D), "stage1.log"), "w") as fh:
    fh.write("x\n")
os.makedirs(os.path.join(rd, "run-%d" % (NOW - D)))
os.makedirs(os.path.join(rd, "not-a-run"))

r = hs.run_selection(process=lambda t, text: True)

c = hs.load_cursor()["claude"]
P("seen_left", ",".join(sorted(c["seen"])))
P("quar_left", ",".join(sorted(c["quarantined"])))
P("patterns", ",".join(r["pattern"] for r in hs._jsonl_rows(hs._sweep_file("patterns.jsonl"))))
P("proposed", ",".join(r["pattern"] for r in hs._jsonl_rows(hs._sweep_file("proposed.jsonl"))))
P("extract_left", ",".join(sorted(os.listdir(ed))))
P("runs_left", ",".join(sorted(n for n in os.listdir(rd))))
PY
)
t13b() { printf '%s\n' "$T13B_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC31: patterns.jsonl rows outside the window are pruned" "p-new" "$(t13b patterns)"
assert_eq "AC31: proposed.jsonl entries past 90 days are pruned" "x-new" "$(t13b proposed)"
assert_eq "AC31/AC20: seen{} entries past 30 days are pruned (edge ts pruned too)" "s-new" "$(t13b seen_left)"
assert_eq "AC31: quarantine entries past 30 days are pruned" "q-new" "$(t13b quar_left)"
assert_eq "AC31: extract/ drops settled files and residue, keeps unread and fresh" "freshs@1999568000.json,pend@9500.json,q-old@7000.json" "$(t13b extract_left)"
assert_eq "AC31: runs/ dirs past 30 days are pruned, other entries stay" "not-a-run,run-1999913600,run-2000000000" "$(t13b runs_left)"

# ============================================================
echo ""
echo "=== T13 report, lint, gate ledger, rc ==="

# AC12: a fixture run's report passes report-lint.sh, carries the step-9 grammar
# under `## Harvest sweep: <run-id>`, lists each staged learning in the overlay,
# and writes one gate-ledger line under harvest-sweep-<run-id>. The rc contract:
# 1 auth stop, 3 lint failure (findings appended, no retry), 5 a source at its
# consecutive-failure limit, 6 lag over the limit on two runs running, 0 else.
T13_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import datetime, importlib.util, json, os, shlex, sqlite3, subprocess
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)
KIT, TD, NOW = (os.environ["KIT_DIR"], os.environ["TD"], int(os.environ["T5_NOW"]))
FIX = os.path.join(KIT, "tests", "fixtures", "harvest-sweep")
STUB = os.path.join(FIX, "stub-extractor.sh")
P = lambda k, v: print("%s=%s" % (k, v))
n_scn = [0]

iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def scenario():
    """Fresh state dir, claude root, EMPTY devin db, stub extractor and annotators."""
    n_scn[0] += 1
    base = os.path.join(TD, "t13-s%d" % n_scn[0])
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = os.path.join(base, "claude")
    os.makedirs(os.environ["HARVEST_SWEEP_CLAUDE_ROOT"])
    db = os.path.join(base, "devin.db")
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE sessions(id TEXT, working_directory TEXT, created_at REAL,"
                " last_activity_at REAL, hidden INTEGER, main_chain_id TEXT)")
    con.commit(); con.close()
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = db
    os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
    os.environ["HARVEST_EXTRACTOR"] = shlex.quote(STUB)
    os.environ["STUB_CALLS"] = os.path.join(base, "calls")
    os.environ["STUB_PRECEDENT_HITS_FILE"] = os.path.join(base, "hits.json")
    os.environ["STUB_LANE"] = "normal"
    os.environ["HARVEST_SWEEP_PRECEDENT"] = os.path.join(FIX, "stub-precedent.sh")
    os.environ["HARVEST_SWEEP_LANE_CLASSIFY"] = os.path.join(FIX, "stub-lane-classify.sh")
    os.environ["KIT_LEDGER_DIR"] = os.path.join(base, "ledger")
    return base, os.environ["HARVEST_SWEEP_CLAUDE_ROOT"]

def mk(root, sid, la, n=6):
    d = os.path.join(root, "p")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": TD,
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s msg %d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))

OUT = json.dumps({"learnings": [{"item": "cache-alpha", "kind": "insight", "home": "til",
                                 "why": "w", "evidence": "e"}],
                  "sightings": [{"pattern": "fix-lint-rule", "kind": "repeat",
                                 "count": 1, "evidence": "ran it"}]})
LINT = os.path.join(KIT, "lib", "wrap", "report-lint.sh")

# ---- S1: a clean run renders, lints clean, writes the manifest and the ledger ----
base, root = scenario()
for i, sid in enumerate(("s1", "s2", "s3")):
    mk(root, sid, NOW - 3600 - i * 60)
os.environ["STUB_OUT"] = OUT
with open(os.environ["STUB_PRECEDENT_HITS_FILE"], "w") as fh:
    json.dump(["tools/lint/bin/fix.sh  , fixes the lint"], fh)
result = hs.run_selection(schedule_hours=48)
rc, path = hs.run_report(result)
P("s1_rc", rc)
report = open(path).read()
P("s1_lint", subprocess.run(["bash", LINT, path], capture_output=True).returncode)
P("s1_heading", "## Harvest sweep: run-%d" % NOW in report)
P("s1_needs", "**Needs you:** NOTHING" in report)
P("s1_built", "- REPORTED fix-lint-rule ENHANCE tools/lint/bin/fix.sh" in report)
P("s1_seam", "**Seam:** SKIPPED: the sweep runs no seams in phase 1" in report)
P("s1_override", "- STATE run: extractor override active, safety flags not enforced" in report)
P("s1_queued", "- STATE run: 1 learnings queued in sweep ledgers; flush path:" in report)
P("s1_overlay", "- cache-alpha (insight, til) -> ledger/" in report)
man = json.load(open(os.path.join(os.path.dirname(path), "manifest.json")))
P("s1_manifest_keys", ",".join(sorted(man)))
P("s1_manifest_cand", "%s|%s|%s" % (man["candidates"][0]["pattern"],
                                   man["candidates"][0]["precedent"],
                                   man["candidates"][0]["lane"]))
P("s1_manifest_sessions", len(man["sessions"]))
llog = os.path.join(os.environ["KIT_LEDGER_DIR"], "runs", "harvest-sweep-run-%d.log" % NOW)
P("s1_ledger", "| GATE | harvest | ran |" in open(llog).read())
P("s1_ledger_summary", "3 sessions, 1 learnings, 1 candidates reported, lag 0.0h"
  in open(llog).read())

# ---- S2: an idle run writes no runs/ dir, no manifest, and returns rc 0 ----
base, root = scenario()
rc2, path2 = hs.run_report(hs.run_selection(schedule_hours=48))
P("s2_rc", rc2)
P("s2_path", path2)
P("s2_no_runs", os.path.exists(os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "runs")))

# ---- S3: an auth-shaped stop is rc 1, and the probe INCIDENT is in the report ----
base, root = scenario()
mk(root, "a1", NOW - 3600)
os.environ["STUB_MODE"] = "fail"
rc3, path3 = hs.run_report(hs.run_selection(schedule_hours=48))
os.environ["STUB_MODE"] = "ok"
P("s3_rc", rc3)
P("s3_incident", "- INCIDENT extractor: probe failed:" in open(path3).read())

# ---- S4: a renderer that drops the Seam line is rc 3 with findings appended ----
base, root = scenario()
mk(root, "b1", NOW - 3600)
os.environ["STUB_OUT"] = '{"learnings": [], "sightings": []}'
result = hs.run_selection(schedule_hours=48)
orig = hs._report_text
def _drop_seam(*a, **k):
    return "\n".join(l for l in orig(*a, **k).splitlines()
                     if not l.startswith("**Seam:**")) + "\n"
hs._report_text = _drop_seam
rc4, path4 = hs.run_report(result)
hs._report_text = orig
body4 = open(path4).read()
P("s4_rc", rc4)
P("s4_findings_appended", "lint findings:" in body4 and "**Seam:**" in body4.split("lint findings:")[1])

# ---- S5: a devin source unreadable three runs running is rc 5 + UNBLOCK ----
base, root = scenario()
os.environ["HARVEST_SWEEP_DEVIN_DB"] = os.path.join(base, "gone.db")
rcs = []
for _ in range(3):
    r_, p_ = hs.run_report(hs.run_selection(schedule_hours=48))
    rcs.append(r_)
P("s5_rcs", ",".join(map(str, rcs)))
P("s5_unblock", "a. UNBLOCK devin: OperationalError" in open(p_).read())
P("s5_needs_red", "**Needs you:**" in open(p_).read())

# ---- S6: lag above 24h on two consecutive runs is rc 6 + DECIDE ----
base, root = scenario()
mk(root, "laggy", NOW - 30 * 3600)
rcs = []
for _ in range(2):
    r_, p_ = hs.run_report(hs.run_selection(schedule_hours=48, max_sessions=0))
    rcs.append(r_)
P("s6_rcs", ",".join(map(str, rcs)))
P("s6_decide", "DECIDE raise harvest.max_sessions_per_run or lower schedule_hours: "
  "claude lag above 24h two runs running" in open(p_).read())
P("s6_lag_row", "- STATE claude: lag: 1 eligible unread, oldest 30.0h" in open(p_).read())

# ---- S7: a limit hold is rc 0 with its STATE row ----
base, root = scenario()
mk(root, "lim", NOW - 3600)
os.environ["STUB_MODE"] = "limit"
rc7, path7 = hs.run_report(hs.run_selection(schedule_hours=48))
os.environ["STUB_MODE"] = "ok"
P("s7_rc", rc7)
P("s7_limit_row", "- STATE claude: extractor-limit: usage limit" in open(path7).read())

# ---- S8: an all-prose candidate lands the PROSE-ONLY bullet and still lints ----
base, root = scenario()
for i, sid in enumerate(("p1", "p2", "p3")):
    mk(root, sid, NOW - 3600 - i * 60)
os.environ["STUB_OUT"] = OUT
with open(os.environ["STUB_PRECEDENT_HITS_FILE"], "w") as fh:
    json.dump(["memory/notes/fix-proc.md  , the fix procedure"], fh)
rc8, path8 = hs.run_report(hs.run_selection(schedule_hours=48))
body8 = open(path8).read()
P("s8_rc", rc8)
P("s8_prose_bullet", "- PROSE-ONLY: fix-lint-rule: only prose homes matched; "
  "phase 1 reports and builds nothing" in body8)
P("s8_lint", subprocess.run(["bash", LINT, path8], capture_output=True).returncode)
PY
)
t13() { printf '%s\n' "$T13_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC12: a clean fixture run exits rc 0" "0" "$(t13 s1_rc)"
assert_eq "AC12: the report passes report-lint.sh" "0" "$(t13 s1_lint)"
assert_eq "AC12: the heading is ## Harvest sweep: <run-id>" "True" "$(t13 s1_heading)"
assert_eq "AC12: Needs you is NOTHING on a clean run" "True" "$(t13 s1_needs)"
assert_eq "AC12: the Built bullet is REPORTED with the precedent home" "True" "$(t13 s1_built)"
assert_eq "AC12: the Seam line reports the phase-1 skip" "True" "$(t13 s1_seam)"
assert_eq "AC12: the extractor-override safety STATE row renders" "True" "$(t13 s1_override)"
assert_eq "AC12: the queued-learnings STATE row renders with the flush path" "True" "$(t13 s1_queued)"
assert_eq "AC12: the learnings overlay lists the staged row" "True" "$(t13 s1_overlay)"
assert_eq "AC12: the manifest carries the spec's keys" "candidates,lag,learnings_queued,learnings_staged,run_id,sessions" "$(t13 s1_manifest_keys)"
assert_eq "AC12: the manifest candidate carries precedent and lane" "fix-lint-rule|ENHANCE tools/lint/bin/fix.sh|normal" "$(t13 s1_manifest_cand)"
assert_eq "AC12: the manifest lists the processed sessions" "3" "$(t13 s1_manifest_sessions)"
assert_eq "AC12: the gate ledger records harvest-sweep-<run-id>" "True" "$(t13 s1_ledger)"
assert_eq "AC12: the ledger summary carries sessions, learnings, candidates, lag" "True" "$(t13 s1_ledger_summary)"
assert_eq "AC11: an idle run returns rc 0" "0" "$(t13 s2_rc)"
assert_eq "AC11: an idle run writes no runs/ directory" "False" "$(t13 s2_no_runs)"
assert_eq "AC12: an auth-shaped stop is rc 1" "1" "$(t13 s3_rc)"
assert_eq "AC12: the failed probe lands an INCIDENT row" "True" "$(t13 s3_incident)"
assert_eq "AC12: a renderer that drops Seam is rc 3" "3" "$(t13 s4_rc)"
assert_eq "AC12: lint findings are appended to the report" "True" "$(t13 s4_findings_appended)"
assert_eq "AC12: a source failing three runs is rc 5" "0,0,5" "$(t13 s5_rcs)"
assert_eq "AC12: rc 5 carries a Needs-you UNBLOCK item" "True" "$(t13 s5_unblock)"
assert_eq "AC21: lag above 24h on two runs running is rc 6" "0,6" "$(t13 s6_rcs)"
assert_eq "AC12: rc 6 carries the DECIDE item naming the source" "True" "$(t13 s6_decide)"
assert_eq "AC12: the lag STATE row names count and oldest age" "True" "$(t13 s6_lag_row)"
assert_eq "AC27: a limit hold stays rc 0 with its STATE row" "0" "$(t13 s7_rc)"
assert_eq "AC12: the limit hold STATE row renders" "True" "$(t13 s7_limit_row)"
assert_eq "AC18: an all-prose candidate renders its PROSE-ONLY bullet" "True" "$(t13 s8_prose_bullet)"
assert_eq "AC18: the rendered all-prose report lints rc 0" "0" "$(t13 s8_lint)"

# ============================================================
echo ""
echo "=== T14 entry: --sweep, --dry-run, --status, sweep.lock, _dispatch ==="

# AC2/AC3/AC4/AC28 + the After-state dry run: --sweep needs an active host
# (harvest.enable through the root-only config read AND the installed marker),
# takes sweep.lock for the whole run, and exits 0 with no work when disabled,
# unmarked, or lock-held. --dry-run prints the manifest and writes nothing real
# but the extract cache. --status prints the newest report line or 'none'.
T14_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import contextlib, datetime, fcntl, importlib.util, io, json, os, shlex, sqlite3, sys
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
sys.modules["hs"] = hs
spec.loader.exec_module(hs)
sys.path.insert(0, os.path.join(os.environ["KIT_DIR"], "hooks"))
import harvest
KIT, TD, NOW = (os.environ["KIT_DIR"], os.environ["TD"], int(os.environ["T5_NOW"]))
FIX = os.path.join(KIT, "tests", "fixtures", "harvest-sweep")
P = lambda k, v: print("%s=%s" % (k, v))
n_scn = [0]
iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def scenario(active=True, sources="claude"):
    """Fresh host: state dir, claude root, empty devin db, kit config, marker."""
    n_scn[0] += 1
    base = os.path.join(TD, "t14-s%d" % n_scn[0])
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    root = os.path.join(base, "claude"); os.makedirs(root)
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = root
    db = os.path.join(base, "devin.db")
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE sessions(id TEXT, working_directory TEXT, created_at REAL,"
                " last_activity_at REAL, hidden INTEGER, main_chain_id TEXT)")
    con.commit(); con.close()
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = db
    os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
    os.environ["HARVEST_EXTRACTOR"] = shlex.quote(os.path.join(FIX, "stub-extractor.sh"))
    os.environ["STUB_CALLS"] = os.path.join(base, "calls")
    os.environ["STUB_OUT"] = json.dumps({"learnings": [{"item": "dry-%d" % n_scn[0], "kind": "insight",
                                                       "home": "til", "why": "w", "evidence": "e"}],
                                        "sightings": []})
    os.environ["STUB_MODE"] = "ok"
    os.environ["STUB_PRECEDENT_HITS_FILE"] = os.path.join(base, "hits.json")
    os.environ["STUB_LANE"] = "normal"
    os.environ["HARVEST_SWEEP_PRECEDENT"] = os.path.join(FIX, "stub-precedent.sh")
    os.environ["HARVEST_SWEEP_LANE_CLASSIFY"] = os.path.join(FIX, "stub-lane-classify.sh")
    os.environ["KIT_LEDGER_DIR"] = os.path.join(base, "ledger")
    kroot = os.path.join(base, "kitroot"); os.makedirs(kroot)
    with open(os.path.join(kroot, "kit.toml"), "w") as fh:
        fh.write('[harvest]\nenable = %s\nschedule_hours = 48\n'
                 'max_sessions_per_run = 20\nsources = "%s"\n'
                 % ("true" if active else "false", sources))
    os.environ["KIT_CONFIG_ROOT"] = kroot
    os.environ["KIT_CONFIG_OPERATOR"] = os.path.join(base, "no-operator")
    if active:
        sd = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep")
        os.makedirs(sd)
        with open(os.path.join(sd, "installed"), "w") as fh:
            json.dump({"label": "harvest-sweep", "host": "t", "kit": KIT, "ts": NOW}, fh)
    return base, root

def mk(root, sid, la, n=6):
    d = os.path.join(root, "p"); os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": TD,
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s m%d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))

def calls():
    try:
        return sum(1 for _ in open(os.environ["STUB_CALLS"]))
    except OSError:
        return 0

def sweep_files(state):
    d = os.path.join(state, "sweep")
    out = {}
    for name in ("cursor.json", "patterns.jsonl", "proposed.jsonl"):
        p = os.path.join(d, name)
        out[name] = open(p, "rb").read() if os.path.exists(p) else None
    led = os.path.join(d, "ledger")
    out["ledger"] = {}
    if os.path.isdir(led):
        for n in sorted(os.listdir(led)):
            out["ledger"][n] = open(os.path.join(led, n), "rb").read()
    return out

# ---- status on an empty state dir ----
base, root = scenario()
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = hs.main(["--status"])
P("status_none", "%s|%s" % (rc, buf.getvalue().strip()))

# ---- a live --sweep end to end, then a second run is a no-op ----
mk(root, "e1", NOW - 3600); mk(root, "e2", NOW - 3700); mk(root, "e3", NOW - 3800)
rc = hs.main(["--sweep"])
P("sweep_rc", rc)
P("sweep_calls", calls())
state = os.environ["HARVEST_STATE_DIR"]
runs = os.path.join(state, "sweep", "runs")
P("sweep_report", os.path.exists(os.path.join(runs, "run-%d" % NOW, "report.md")))
P("sweep_manifest", os.path.exists(os.path.join(runs, "run-%d" % NOW, "manifest.json")))
snap = sweep_files(state)
rc = hs.main(["--sweep"])
P("rerun_rc", rc)
P("rerun_calls", calls())                        # AC2: no extractor call
P("rerun_identical", sweep_files(state) == snap) # AC2: byte-identical state
P("rerun_runs", ",".join(sorted(os.listdir(runs))))        # no new runs/<id>/ dir
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = hs.main(["--status"])
P("status_line", buf.getvalue().strip().endswith(
    "run-%d/report.md candidates=0 queued=1" % NOW))
P("status_rc", rc)

# ---- --dry-run: prints a manifest, writes nothing real but the extract cache ----
base, root = scenario()
mk(root, "d1", NOW - 3600); mk(root, "d2", NOW - 3700)
state = os.environ["HARVEST_STATE_DIR"]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = hs.main(["--sweep", "--dry-run", "--since", str(NOW - 86400)])
man = json.loads(buf.getvalue())
P("dry_rc", rc)
P("dry_calls", calls())
P("dry_manifest_sessions", len(man["sessions"]))
P("dry_manifest_staged", man["learnings_staged"])
sw = os.path.join(state, "sweep")
P("dry_extract_cache", ",".join(sorted(os.listdir(os.path.join(sw, "extract", "claude")))))
P("dry_no_state", ",".join(sorted(n for n in os.listdir(sw) if n != "extract" and n != "installed")))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    hs.main(["--sweep", "--dry-run"])
P("dry_replay_calls", calls())   # the cache lands the second dry run for free

# ---- lock held: --sweep exits 0 without work, --dry-run refuses ----
lockfd = os.open(os.path.join(sw, "sweep.lock"), os.O_CREAT | os.O_RDWR, 0o600)
fcntl.flock(lockfd, fcntl.LOCK_EX)
err = io.StringIO()
with contextlib.redirect_stderr(err):
    P("lock_sweep_rc", hs.main(["--sweep"]))
P("lock_marker", "harvest-sweep: sweep.lock held" in err.getvalue())
P("lock_dry_rc", hs.main(["--sweep", "--dry-run"]))
P("lock_calls", calls())
fcntl.flock(lockfd, fcntl.LOCK_UN); os.close(lockfd)

# ---- disabled and unmarked hosts exit 0 and call nothing ----
base, root = scenario(active=False)
mk(root, "x1", NOW - 3600)
P("disabled_rc", hs.main(["--sweep"]))
P("disabled_calls", calls())
P("disabled_cursor", os.path.exists(os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "cursor.json")))
base, root = scenario()   # enable=true in toml; drop the marker to fake an unmarked host
os.unlink(os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "installed"))
mk(root, "x2", NOW - 3600)
P("unmarked_rc", hs.main(["--sweep"]))
P("unmarked_calls", calls())

# ---- harvest.py's _dispatch routes --sweep before the payload fall-through ----
base, root = scenario()
mk(root, "r1", NOW - 3600)
rc = harvest._dispatch(["--sweep"])
P("dispatch_rc", rc)
P("dispatch_report", os.path.exists(os.path.join(
    os.environ["HARVEST_STATE_DIR"], "sweep", "runs", "run-%d" % NOW, "report.md")))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = harvest._dispatch(["--sweep", "--dry-run"])
P("dispatch_dry_rc", rc)
P("dispatch_dry_manifest", '"run_id"' in buf.getvalue())
PY
)
t14() { printf '%s\n' "$T14_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC28: --status on a state with no run prints none" "0|none" "$(t14 status_none)"
# The documented entry is hooks/harvest.py --status; the dispatcher must route it
# to the sweep, not fall through to the hook path and exit 0 silently.
status_state=$(mktemp -d)
status_out=$(HARVEST_STATE_DIR="$status_state" python3 "$KIT_DIR/hooks/harvest.py" --status </dev/null 2>/dev/null; echo "|$?")
assert_eq "AC28: harvest.py --status routes to the sweep" "none|0" "$(printf '%s' "$status_out" | tr -d '\n')"
assert_eq "AC4: an active --sweep runs end to end at rc 0" "0" "$(t14 sweep_rc)"
assert_eq "AC4: the run extracted all three sessions" "3" "$(t14 sweep_calls)"
assert_eq "AC12: --sweep wrote report.md under runs/<run-id>/" "True" "$(t14 sweep_report)"
assert_eq "AC12: --sweep wrote manifest.json beside it" "True" "$(t14 sweep_manifest)"
assert_eq "AC2: a second --sweep exits 0" "0" "$(t14 rerun_rc)"
assert_eq "AC2: the second run makes no extractor call" "3" "$(t14 rerun_calls)"
assert_eq "AC2: the second run leaves sweep state byte-identical" "True" "$(t14 rerun_identical)"
assert_eq "AC2: the second run writes no new runs/ dir" "run-2000000000" "$(t14 rerun_runs)"
assert_eq "AC28: --status prints the newest report path and counts" "True" "$(t14 status_line)"
assert_eq "AC28: --status exits 0" "0" "$(t14 status_rc)"
assert_eq "After state: --dry-run exits 0 and prints the manifest" "0" "$(t14 dry_rc)"
assert_eq "After state: the dry run did extract (cache is permitted)" "2" "$(t14 dry_calls)"
assert_eq "After state: the manifest covers both sessions" "2" "$(t14 dry_manifest_sessions)"
assert_eq "After state: the dry run's manifest carries the staged count" "1" "$(t14 dry_manifest_staged)"
assert_eq "After state: the raw output cache landed in real state" "d1@1999996400.json,d2@1999996300.json" "$(t14 dry_extract_cache)"
assert_eq "After state: no cursor, ledgers, patterns, proposed, or runs in real state" "sweep.lock" "$(t14 dry_no_state)"
assert_eq "After state: a second dry run reuses the cache" "2" "$(t14 dry_replay_calls)"
assert_eq "AC4: a lock-held --sweep exits 0" "0" "$(t14 lock_sweep_rc)"
assert_eq "AC4: a lock-held --sweep prints the bridge-skip marker" "True" "$(t14 lock_marker)"
assert_eq "AC4: a lock-held --dry-run refuses to start" "1" "$(t14 lock_dry_rc)"
assert_eq "AC4: the lock-held runs called no extractor" "2" "$(t14 lock_calls)"
assert_eq "AC4: a disabled host exits 0" "0" "$(t14 disabled_rc)"
assert_eq "AC4: a disabled host calls no extractor" "0" "$(t14 disabled_calls)"
assert_eq "AC4: a disabled host writes no cursor" "False" "$(t14 disabled_cursor)"
assert_eq "AC4: an unmarked host exits 0 and calls nothing" "0|0" "$(t14 unmarked_rc)|$(t14 unmarked_calls)"
assert_eq "AC4: _dispatch routes --sweep to the entry" "0" "$(t14 dispatch_rc)"
assert_eq "AC4: the dispatched run wrote the report" "True" "$(t14 dispatch_report)"
assert_eq "After state: _dispatch also carries --dry-run" "0|True" "$(t14 dispatch_dry_rc)|$(t14 dispatch_dry_manifest)"

# ============================================================
echo ""
echo "=== T14b: crash safety (AC3), dry-run guards, overlay cleanup ==="

# AC3: a run killed after a session's staging but before its cursor write must
# replay clean -- the ledger row and the sighting are written once, the raw
# extraction is replayed from the cache (the stub is never re-called for that
# session), and no session between the old and new hwm is skipped. Two crash
# shapes are exercised: the write itself failing (cursor unchanged, the session
# replays through dedup) and a kill just after the write landed (the session is
# settled and stays settled). The _DRY_RUN guards in _prune_extract and
# _gate_record keep real state untouched under --dry-run, and a dry run that
# raises mid-selection still removes its overlay.
T14B_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import contextlib, datetime, glob, importlib.util, io, json, os, shlex, sqlite3, sys, tempfile
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
sys.modules["hs"] = hs
spec.loader.exec_module(hs)
sys.path.insert(0, os.path.join(os.environ["KIT_DIR"], "hooks"))
import harvest
KIT, TD, NOW = (os.environ["KIT_DIR"], os.environ["TD"], int(os.environ["T5_NOW"]))
FIX = os.path.join(KIT, "tests", "fixtures", "harvest-sweep")
P = lambda k, v: print("%s=%s" % (k, v))
n_scn = [0]
iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def scenario(active=True, sources="claude"):
    """Fresh host: state dir, claude root, empty devin db, kit config, marker."""
    n_scn[0] += 1
    base = os.path.join(TD, "t14b-s%d" % n_scn[0])
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    root = os.path.join(base, "claude"); os.makedirs(root)
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = root
    db = os.path.join(base, "devin.db")
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE sessions(id TEXT, working_directory TEXT, created_at REAL,"
                " last_activity_at REAL, hidden INTEGER, main_chain_id TEXT)")
    con.commit(); con.close()
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = db
    os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
    os.environ["HARVEST_EXTRACTOR"] = shlex.quote(os.path.join(FIX, "stub-extractor.sh"))
    os.environ["STUB_CALLS"] = os.path.join(base, "calls")
    os.environ["STUB_OUT"] = json.dumps(
        {"learnings": [{"item": "crash-%d" % n_scn[0], "kind": "insight",
                        "home": "til", "why": "w", "evidence": "e"}],
         "sightings": [{"pattern": "crash-sig-%d" % n_scn[0], "kind": "insight",
                        "count": 1, "evidence": "e"}]})
    os.environ["STUB_MODE"] = "ok"
    os.environ["STUB_PRECEDENT_HITS_FILE"] = os.path.join(base, "hits.json")
    os.environ["STUB_LANE"] = "normal"
    os.environ["HARVEST_SWEEP_PRECEDENT"] = os.path.join(FIX, "stub-precedent.sh")
    os.environ["HARVEST_SWEEP_LANE_CLASSIFY"] = os.path.join(FIX, "stub-lane-classify.sh")
    os.environ["KIT_LEDGER_DIR"] = os.path.join(base, "ledger")
    kroot = os.path.join(base, "kitroot"); os.makedirs(kroot)
    with open(os.path.join(kroot, "kit.toml"), "w") as fh:
        fh.write('[harvest]\nenable = %s\nschedule_hours = 48\n'
                 'max_sessions_per_run = 20\nsources = "%s"\n'
                 % ("true" if active else "false", sources))
    os.environ["KIT_CONFIG_ROOT"] = kroot
    os.environ["KIT_CONFIG_OPERATOR"] = os.path.join(base, "no-operator")
    if active:
        sd = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep")
        os.makedirs(sd)
        with open(os.path.join(sd, "installed"), "w") as fh:
            json.dump({"label": "harvest-sweep", "host": "t", "kit": KIT, "ts": NOW}, fh)
    return base, root

def mk(root, sid, la, n=6):
    d = os.path.join(root, "p"); os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": TD,
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s m%d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))

def calls():
    try:
        return sum(1 for _ in open(os.environ["STUB_CALLS"]))
    except OSError:
        return 0

def read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError:
        return None

def ledger_items(state):
    d = os.path.join(state, "sweep", "ledger")
    if not os.path.isdir(d):
        return ""
    items = []
    for n in sorted(os.listdir(d)):
        if not n.endswith(".md") or n.endswith(".archive.md"):
            continue
        for line in open(os.path.join(d, n), encoding="utf-8"):
            cells = [c.strip() for c in line.split("|")]
            if len(cells) >= 6 and cells[1].count("-") == 2:
                items.append("%s:%s" % (n[:-3], cells[2]))
    return ",".join(items)

# ---- AC3a: the cursor write fails after staging -- the replay must dedup ----
base, root = scenario()
mk(root, "ca", NOW - 3700); mk(root, "cb", NOW - 3600)
state = os.environ["HARVEST_STATE_DIR"]
orig_save = hs.save_cursor
def boom(cursor):
    raise OSError("simulated kill ahead of the cursor write")
hs.save_cursor = boom
try:
    hs.main(["--sweep"])
    raise AssertionError("the injected crash did not fire")
except OSError:
    pass
finally:
    hs.save_cursor = orig_save
P("a_r1_cursor", os.path.exists(os.path.join(state, "sweep", "cursor.json")))
P("a_r1_items", ledger_items(state))
P("a_r1_calls", calls())
def pat_count(state, sid):
    p = os.path.join(state, "sweep", "patterns.jsonl")
    if not os.path.exists(p):
        return 0
    return sum(1 for r in (json.loads(l) for l in open(p) if l.strip())
               if r.get("session_id") == sid)

snap_ca_sig = pat_count(state, "ca")
snap_led = {}
for n in os.listdir(os.path.join(state, "sweep", "ledger")):
    snap_led[n] = read(os.path.join(state, "sweep", "ledger", n))
rc2 = hs.main(["--sweep"])
P("a_r2_rc", rc2)
P("a_r2_items", ledger_items(state))
P("a_r2_calls", calls())           # ca replays from extract/, only cb pays the call
P("a_r2_ca_sig", pat_count(state, "ca") == snap_ca_sig)
P("a_r2_cb_sig", pat_count(state, "cb"))
P("a_r2_led_same", all(read(os.path.join(state, "sweep", "ledger", n)) == b
                       for n, b in snap_led.items()))
cur = json.load(open(os.path.join(state, "sweep", "cursor.json")))
P("a_done", ",".join(sorted(cur["claude"]["done"])))
P("a_hwm", cur["claude"]["hwm"])

# ---- AC3b: the kill lands just after the cursor write -- the session stays done ----
base, root = scenario()
mk(root, "pd", NOW - 3600)
state = os.environ["HARVEST_STATE_DIR"]
def persisted_then_dead(cursor):
    orig_save(cursor)
    raise OSError("simulated kill just after the cursor write")
hs.save_cursor = persisted_then_dead
try:
    hs.main(["--sweep"])
    raise AssertionError("the injected crash did not fire")
except OSError:
    pass
finally:
    hs.save_cursor = orig_save
P("b_r1_items", ledger_items(state))
P("b_r1_cursor", os.path.exists(os.path.join(state, "sweep", "cursor.json")))
rc2 = hs.main(["--sweep"])
P("b_r2_rc", rc2)
P("b_r2_items", ledger_items(state))
P("b_r2_calls", calls())

# ---- AC30/AC31: a dry run never prunes real extract/ and never writes the gate ledger ----
base, root = scenario()
state = os.environ["HARVEST_STATE_DIR"]
sw = os.path.join(state, "sweep")
with open(os.path.join(sw, "cursor.json"), "w") as fh:
    json.dump({"claude": {"hwm": 2000, "done": {}, "seen": {}, "fail": {},
                          "quarantined": {}}}, fh)
ext = os.path.join(sw, "extract", "claude")
os.makedirs(ext)
stale = os.path.join(ext, "stale-session@1000.json")
with open(stale, "w") as fh:
    fh.write('{"stale": true}')
gate_dir = os.path.join(base, "gate-ledger")
os.makedirs(gate_dir)
os.environ["KIT_LEDGER_DIR"] = gate_dir
mk(root, "g1", NOW - 3600)
cur_snap = read(os.path.join(sw, "cursor.json"))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = hs.main(["--sweep", "--dry-run"])
P("g_rc", rc)
P("g_stale_survives", os.path.exists(stale))
P("g_gate_dir", ",".join(sorted(os.listdir(gate_dir))))
P("g_cache_real", os.path.exists(os.path.join(ext, "g1@%d.json" % (NOW - 3600))))
P("g_no_ledger", os.path.exists(os.path.join(sw, "ledger")))
P("g_no_runs", os.path.exists(os.path.join(sw, "runs")))
P("g_cursor_same", read(os.path.join(sw, "cursor.json")) == cur_snap)

# ---- a dry run that raises mid-selection still removes its overlay ----
pre = set(glob.glob(os.path.join(tempfile.gettempdir(), "harvest-sweep-dry-*")))
orig_rs = hs.run_selection
hs.run_selection = lambda **kw: (_ for _ in ()).throw(RuntimeError("abort mid-selection"))
try:
    hs.main(["--sweep", "--dry-run"])
    raise AssertionError("the injected abort did not fire")
except RuntimeError:
    pass
finally:
    hs.run_selection = orig_rs
post = set(glob.glob(os.path.join(tempfile.gettempdir(), "harvest-sweep-dry-*")))
P("o_leaked", ",".join(sorted(post - pre)))
P("o_env_restored", os.environ["HARVEST_STATE_DIR"] == state)
PY
)
t14b() { printf '%s\n' "$T14B_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC3: the crashed run left the staged row" "_no-repo:crash-1" "$(t14b a_r1_items)"
assert_eq "AC3: the crashed run left no cursor behind" "False" "$(t14b a_r1_cursor)"
assert_eq "AC3: one extractor call before the crash" "1" "$(t14b a_r1_calls)"
assert_eq "AC3: the re-run exits clean" "0" "$(t14b a_r2_rc)"
assert_eq "AC3: the replay staged no duplicate row" "_no-repo:crash-1" "$(t14b a_r2_items)"
assert_eq "AC3: cb was not skipped between the old and new hwm" "cb" "$(t14b a_done)"
assert_eq "AC3: the hwm reached the newest session" "1999996400" "$(t14b a_hwm)"
assert_eq "AC3: the stub ran once per session across both runs" "2" "$(t14b a_r2_calls)"
assert_eq "AC3: ca's sighting was not double-counted" "True" "$(t14b a_r2_ca_sig)"
assert_eq "AC3: cb's sighting landed exactly once" "1" "$(t14b a_r2_cb_sig)"
assert_eq "AC3: the ledger stayed byte-identical on replay" "True" "$(t14b a_r2_led_same)"
assert_eq "AC3: a kill just after the cursor write still stages once" "_no-repo:crash-2" "$(t14b b_r1_items)"
assert_eq "AC3: the post-write crash persisted its cursor" "True" "$(t14b b_r1_cursor)"
assert_eq "AC3: the settled session stays settled on re-run" "0" "$(t14b b_r2_rc)"
assert_eq "AC3: no duplicate row after the post-write crash" "_no-repo:crash-2" "$(t14b b_r2_items)"
assert_eq "AC3: the extractor is not re-run for a settled session" "1" "$(t14b b_r2_calls)"
assert_eq "AC31: a dry run does not prune the real extract cache" "True" "$(t14b g_stale_survives)"
assert_eq "AC30: a dry run writes nothing to the real gate ledger" "" "$(t14b g_gate_dir)"
assert_eq "AC30: the raw cache is the one permitted real write" "True" "$(t14b g_cache_real)"
assert_eq "AC30: a dry run writes no real sweep ledger" "False" "$(t14b g_no_ledger)"
assert_eq "AC30: a dry run writes no real runs/ dir" "False" "$(t14b g_no_runs)"
assert_eq "AC30: a dry run leaves the real cursor byte-identical" "True" "$(t14b g_cursor_same)"
assert_eq "AC30: a failed dry run leaves no overlay behind" "" "$(t14b o_leaked)"
assert_eq "AC30: a failed dry run restores HARVEST_STATE_DIR" "True" "$(t14b o_env_restored)"

# ============================================================================
# T22 flush lifecycle: --flush-list joins queued rows with the sidecar under each
# ledger's .lock; --mark-flushed flips queued -> flushed:<ref> once and refuses a
# repeat or an unknown id with no write; each run drains flushed rows into the
# ledger's .archive.md sibling via cmd_cleanup holding that lock (DEC-58, DEC-69,
# DEC-70, DEC-73); a dry run leaves the real ledgers and archives untouched.
# ============================================================================
echo
echo "T22 flush lifecycle (list, mark, archive, concurrency)"
T22_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" T5_NOW="$T5_NOW" python3 - <<'PY'
import contextlib, datetime, fcntl, importlib.util, io, json, os, shlex, sqlite3, sys, threading, time
spec = importlib.util.spec_from_file_location("hs", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest_sweep.py"))
hs = importlib.util.module_from_spec(spec)
sys.modules["hs"] = hs
spec.loader.exec_module(hs)
sys.path.insert(0, os.path.join(os.environ["KIT_DIR"], "hooks"))
import harvest
KIT, TD, NOW = (os.environ["KIT_DIR"], os.environ["TD"], int(os.environ["T5_NOW"]))
FIX = os.path.join(KIT, "tests", "fixtures", "harvest-sweep")
P = lambda k, v: print("%s=%s" % (k, v))
n_scn = [0]
iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
HEAD = "| date | item | kind | home | status |\n|---|---|---|---|---|\n"

def scenario(active=True, sources="claude", tag="t22", item="flush-1"):
    n_scn[0] += 1
    base = os.path.join(TD, "%s-s%d" % (tag, n_scn[0]))
    os.environ["HARVEST_STATE_DIR"] = os.path.join(base, "state")
    root = os.path.join(base, "claude"); os.makedirs(root)
    os.environ["HARVEST_SWEEP_CLAUDE_ROOT"] = root
    db = os.path.join(base, "devin.db")
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE sessions(id TEXT, working_directory TEXT, created_at REAL,"
                " last_activity_at REAL, hidden INTEGER, main_chain_id TEXT)")
    con.commit(); con.close()
    os.environ["HARVEST_SWEEP_DEVIN_DB"] = db
    os.environ["HARVEST_SWEEP_NOW"] = str(NOW)
    os.environ["HARVEST_EXTRACTOR"] = shlex.quote(os.path.join(FIX, "stub-extractor.sh"))
    os.environ["STUB_CALLS"] = os.path.join(base, "calls")
    os.environ["STUB_OUT"] = json.dumps({"learnings": [{"item": item, "kind": "insight",
                                                       "home": "til", "why": "w", "evidence": "e"}],
                                        "sightings": []})
    os.environ["STUB_MODE"] = "ok"
    os.environ["STUB_PRECEDENT_HITS_FILE"] = os.path.join(base, "hits.json")
    os.environ["STUB_LANE"] = "normal"
    os.environ["HARVEST_SWEEP_PRECEDENT"] = os.path.join(FIX, "stub-precedent.sh")
    os.environ["HARVEST_SWEEP_LANE_CLASSIFY"] = os.path.join(FIX, "stub-lane-classify.sh")
    os.environ["KIT_LEDGER_DIR"] = os.path.join(base, "ledger")
    kroot = os.path.join(base, "kitroot"); os.makedirs(kroot)
    with open(os.path.join(kroot, "kit.toml"), "w") as fh:
        fh.write('[harvest]\nenable = %s\nschedule_hours = 48\n'
                 'max_sessions_per_run = 20\nsources = "%s"\n'
                 % ("true" if active else "false", sources))
    os.environ["KIT_CONFIG_ROOT"] = kroot
    os.environ["KIT_CONFIG_OPERATOR"] = os.path.join(base, "no-operator")
    if active:
        sd = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep")
        os.makedirs(sd)
        with open(os.path.join(sd, "installed"), "w") as fh:
            json.dump({"label": "harvest-sweep", "host": "t", "kit": KIT, "ts": NOW}, fh)
    return base, root

def mk(root, sid, la, n=6):
    d = os.path.join(root, "p"); os.makedirs(d, exist_ok=True)
    path = os.path.join(d, sid + ".jsonl")
    with open(path, "w") as fh:
        for k in range(n):
            fh.write(json.dumps({"type": "user" if k % 2 == 0 else "assistant", "cwd": TD,
                                 "timestamp": iso(la - (n - k) * 10),
                                 "message": {"content": [{"type": "text", "text": "%s m%d" % (sid, k)}]}}) + "\n")
    os.utime(path, (la, la))

def flush_list():
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = harvest._dispatch(["--flush-list"])
    return rc, json.loads(buf.getvalue() or "[]")

def rows(path):
    out = {}
    if os.path.exists(path):
        for line in open(path):
            cells = [c.strip() for c in line.split("|")]
            if len(cells) >= 7 and cells[1].startswith("2"):
                out.setdefault(cells[2], []).append(cells[5])
    return out

def cell(path, item):
    return ",".join(rows(path).get(item) or [])

# -- scenario A: stage one learning, exercise the list/mark/archive cycle ------
base, root = scenario()
mk(root, "f1", NOW - 3600)
with contextlib.redirect_stderr(io.StringIO()):
    hs.main(["--sweep"])
leddir = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "ledger")
led = os.path.join(leddir, "_no-repo.md")
arch = os.path.join(leddir, "_no-repo.archive.md")
with open(led, "a") as fh:
    fh.write("| 2026-01-01 | gone-already | insight | til | flushed:old |\n")
    fh.write("| 2026-01-01 | sidelined | insight | til | parked |\n")
with open(os.path.join(leddir, "other.md"), "w") as fh:
    fh.write(HEAD + "| 2026-01-02 | lone-item | insight | til | queued |\n")

rc, listing = flush_list()
by_id = {r["row_id"]: r for r in listing}
rid = "_no-repo:flush-1"
P("fl_rc", rc)
P("fl_queued_only", ",".join(sorted(by_id)))
P("fl_join", json.dumps({k: by_id[rid].get(k) for k in ("why", "evidence", "source", "lead_session_id")}, sort_keys=True))
P("fl_noctx_nulls", json.dumps({k: by_id["other:lone-item"].get(k)
                                for k in ("why", "lead_session_id")}, sort_keys=True)
  if "other:lone-item" in by_id else "missing")

with contextlib.redirect_stderr(io.StringIO()):
    m1 = harvest._dispatch(["--mark-flushed", rid, "LAB_LOG-9"])
    after_mark = open(led).read()
    m2 = harvest._dispatch(["--mark-flushed", rid, "again"])
    m3 = harvest._dispatch(["--mark-flushed", "_no-repo:no-such", "x"])
    m4 = harvest._dispatch(["--mark-flushed", "no-colon-here", "x"])
    m5 = harvest._dispatch(["--mark-flushed", "nosuchslug:i", "x"])
P("mark_first", m1)
P("mark_repeat", m2)
P("mark_unknown", m3)
P("mark_malformed", m4)
P("mark_missing_ledger", m5)
P("mark_failures_noop", open(led).read() == after_mark)
P("marked_status", cell(led, "flush-1"))

# a run with nothing new still drains the flushed rows into the archive sibling
with contextlib.redirect_stderr(io.StringIO()):
    hs.main(["--sweep"])
P("archive_row", cell(arch, "flush-1"))
P("archive_seeded", cell(arch, "gone-already"))
P("active_after_archive", ",".join(sorted(rows(led))))
rc, listing = flush_list()
P("fl_after_archive", ",".join(sorted(r["row_id"] for r in listing)))

# DEC-69: a fresh sighting of the archived learning is not restaged
mk(root, "f2", NOW - 1800)
with contextlib.redirect_stderr(io.StringIO()):
    hs.main(["--sweep"])
P("archived_not_restaged", "flush-1" not in rows(led))

# -- scenario B: 20-row concurrent mark-versus-archive --------------------------
base2, root2 = scenario(item="conc-x")
leddir2 = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "ledger")
os.makedirs(leddir2, exist_ok=True)
conc = os.path.join(leddir2, "conc.md")
carch = os.path.join(leddir2, "conc.archive.md")
items = ["c%02d" % i for i in range(20)]
conc_errs = []
with contextlib.redirect_stderr(io.StringIO()):
    for rnd in range(15):
        with open(conc, "w") as fh:
            fh.write(HEAD + "".join("| 2026-01-03 | %s | insight | til | queued |\n" % i for i in items))
        if os.path.exists(carch):
            os.remove(carch)
        done = threading.Event()
        def marker():
            for i in items:
                if harvest._dispatch(["--mark-flushed", "conc:" + i, "ref-" + i]) != 0:
                    conc_errs.append("mark rc!=0 " + i)
        def cleaner():
            while not done.is_set():
                harvest.cmd_cleanup(conc)
        t1 = threading.Thread(target=marker); t2 = threading.Thread(target=cleaner)
        t1.start(); t2.start(); t1.join(); done.set(); t2.join()
        seen = {}
        for p_ in (conc, carch):
            for k, sts in rows(p_).items():
                seen.setdefault(k, []).extend(sts)
        for i in items:
            if seen.get(i) != ["flushed:ref-" + i]:
                conc_errs.append("round %d %s -> %s" % (rnd, i, seen.get(i)))
P("conc_errors", len(conc_errs))

# -- scenario C: a dry run drains only its overlay, never the real ledgers ------
base3, root3 = scenario(item="dry-x")
mk(root3, "d1", NOW - 3600)
leddir3 = os.path.join(os.environ["HARVEST_STATE_DIR"], "sweep", "ledger")
dled = os.path.join(leddir3, "_no-repo.md")
os.makedirs(leddir3, exist_ok=True)
with open(dled, "w") as fh:
    fh.write(HEAD + "| 2026-01-04 | stale-flush | insight | til | flushed:ref1 |\n")
before = open(dled).read()
with contextlib.redirect_stderr(io.StringIO()):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        drc = hs.main(["--sweep", "--dry-run"])
P("dry_rc", drc)
P("dry_ledger_untouched", open(dled).read() == before)
P("dry_no_archive", not os.path.exists(os.path.join(leddir3, "_no-repo.archive.md")))
P("dry_row_kept", cell(dled, "stale-flush"))
PY
)
t22() { printf '%s\n' "$T22_OUT" | sed -n "s/^$1=//p"; }

assert_eq "AC17: --flush-list exits 0" "0" "$(t22 fl_rc)"
assert_eq "AC17: --flush-list lists queued rows only" "_no-repo:flush-1,other:lone-item" "$(t22 fl_queued_only)"
assert_eq "AC29: --flush-list joins the sidecar context" '{"evidence": "e", "lead_session_id": null, "source": "claude/f1", "why": "w"}' "$(t22 fl_join)"
assert_eq "AC29: a row with no sidecar entry carries nulls" '{"lead_session_id": null, "why": null}' "$(t22 fl_noctx_nulls)"
assert_eq "AC17: --mark-flushed exits 0 once" "0" "$(t22 mark_first)"
assert_eq "AC17: a repeat mark exits 1" "1" "$(t22 mark_repeat)"
assert_eq "AC17: an unknown row id exits 1" "1" "$(t22 mark_unknown)"
assert_eq "AC17: a malformed row id exits 1" "1" "$(t22 mark_malformed)"
assert_eq "AC17: an unknown slug exits 1" "1" "$(t22 mark_missing_ledger)"
assert_eq "AC17: failed marks change nothing" "True" "$(t22 mark_failures_noop)"
assert_eq "AC17: the row flipped to flushed:<ref>" "flushed:LAB_LOG-9" "$(t22 marked_status)"
assert_eq "DEC-58: a run archives the flushed row" "flushed:LAB_LOG-9" "$(t22 archive_row)"
assert_eq "DEC-58: the seeded flushed row drained too" "flushed:old" "$(t22 archive_seeded)"
assert_eq "DEC-58: only non-flushed rows stay active" "sidelined" "$(t22 active_after_archive)"
assert_eq "AC17: archived rows leave --flush-list" "other:lone-item" "$(t22 fl_after_archive)"
assert_eq "DEC-69: an archived learning is not restaged" "True" "$(t22 archived_not_restaged)"
assert_eq "AC17: concurrent mark and archive lose no rows" "0" "$(t22 conc_errors)"
assert_eq "AC30: a dry run leaves the real ledger untouched" "True" "$(t22 dry_ledger_untouched)"
assert_eq "AC30: a dry run writes no real archive" "True" "$(t22 dry_no_archive)"
assert_eq "AC30: the real flushed row survives a dry run" "flushed:ref1" "$(t22 dry_row_kept)"

# ============================================================================
# T15 harvest.sh gate + [harvest] root-only config (AC8, DEC-3, DEC-9, DEC-27):
# the auto modes exit 0 without spawning harvest.py when HARVEST_SWEEP_CHILD=1,
# or when the host is sweep-active (installed marker + harvest.enable) and
# harvest.hook_when_sweep_on is false. kit_config_get_root resolution means a
# project .kit.toml can neither activate the gate nor reopen the hook.
# ============================================================================
echo
echo "T15 harvest.sh gate (child marker, sweep-active suppression, root-only)"

T15D="$TD/t15"; mkdir -p "$T15D/repo" "$T15D/proj" "$T15D/noop"
git -C "$T15D/repo" init -q
cat > "$T15D/transcript.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"t15 gate probe text"}]}}
EOF
cat > "$T15D/ext.sh" <<'EOF'
#!/usr/bin/env bash
echo call >> "$STUB_CALLS"
cat <<'JSON'
[{"item":"t15-item","kind":"insight","home":"til","why":"w","evidence":"e"}]
JSON
EOF
chmod +x "$T15D/ext.sh"

t15_kroot() { # $1 enable, $2 hook_when_sweep_on
  mkdir -p "$T15D/kroot"
  printf '[harvest]\nenable = %s\nhook_when_sweep_on = %s\n' "$1" "$2" > "$T15D/kroot/kit.toml"
}
# t15_run <marker 0|1> <mode> [env pairs...] -> "rc=N calls=M turns=0|1"
t15_run() {
  local marker="$1" mode="$2"; shift 2
  rm -rf "$T15D/state"; rm -f "$T15D/calls"
  if [ "$marker" = 1 ]; then mkdir -p "$T15D/state/sweep"; : > "$T15D/state/sweep/installed"; fi
  local rc=0
  env -i PATH="$PATH" HOME="$HOME" \
    REPO_ROOT="$T15D/repo" \
    HARVEST_EXTRACTOR="$T15D/ext.sh" \
    HARVEST_SYNC=1 HARVEST_MIN_INTERVAL=0 \
    HARVEST_STATE_DIR="$T15D/state" \
    STUB_CALLS="$T15D/calls" \
    KIT_CONFIG_ROOT="$T15D/kroot" \
    KIT_CONFIG_OPERATOR="$T15D/noop" \
    KIT_PROJECT_ROOT="$T15D/proj" \
    "$@" \
    bash -c "echo '{\"transcript_path\":\"$T15D/transcript.jsonl\",\"session_id\":\"t15\"}' | bash '$KIT_DIR/hooks/harvest.sh' $mode" \
    >/dev/null 2>&1 || rc=$?
  local calls=0 turns=0
  [ -f "$T15D/calls" ] && calls=$(wc -l < "$T15D/calls" | tr -d ' ')
  [ -d "$T15D/state/turns" ] && turns=1
  echo "rc=$rc calls=$calls turns=$turns"
}
tf() { printf '%s' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

# child-marker cases run with NO marker and enable=false, so only the
# HARVEST_SWEEP_CHILD guard can be doing the suppressing
t15_kroot false false
rm -f "$T15D/proj/.kit.toml"

R="$(t15_run 0 "" HARVEST_SWEEP_CHILD=1)"
assert_eq "AC8: child marker suppresses the no-arg mode" "0" "$(tf "$R" calls)"
R="$(t15_run 0 "--lab-log" HARVEST_SWEEP_CHILD=1)"
assert_eq "AC8: child marker suppresses --lab-log" "0" "$(tf "$R" calls)"
R="$(t15_run 0 "--stop-trigger" HARVEST_SWEEP_CHILD=1 HARVEST_STOP_TRIGGER=1 HARVEST_STOP_N=1 HARVEST_STOP_SYNC=1)"
assert_eq "AC8: child marker suppresses --stop-trigger" "0" "$(tf "$R" turns)"

# base config: sweep enabled, hook suppressed -- the active host
t15_kroot true false
R="$(t15_run 1 "")"
assert_eq "AC8: an active host suppresses the no-arg mode" "0" "$(tf "$R" calls)"
assert_eq "AC8: the suppressed fire still exits 0" "0" "$(tf "$R" rc)"
R="$(t15_run 1 "--lab-log")"
assert_eq "AC8: an active host suppresses --lab-log" "0" "$(tf "$R" calls)"
R="$(t15_run 1 "--stop-trigger" HARVEST_STOP_TRIGGER=1 HARVEST_STOP_N=1 HARVEST_STOP_SYNC=1)"
assert_eq "AC8: an active host suppresses --stop-trigger" "0" "$(tf "$R" turns)"

t15_kroot true true
R="$(t15_run 1 "")"
assert_eq "AC8: hook_when_sweep_on=true keeps the hook running" "1" "$(tf "$R" calls)"

t15_kroot false false
R="$(t15_run 1 "")"
assert_eq "AC8: enable=false keeps today's behavior" "1" "$(tf "$R" calls)"

t15_kroot true false
R="$(t15_run 0 "")"
assert_eq "AC8: an unmarked host keeps today's behavior" "1" "$(tf "$R" calls)"

# root-only resolution: a project .kit.toml can neither reopen the hook...
printf '[harvest]\nhook_when_sweep_on = true\n' > "$T15D/proj/.kit.toml"
R="$(t15_run 1 "")"
assert_eq "AC8: a project toml cannot reopen the hook" "0" "$(tf "$R" calls)"

# ...nor activate the gate (project enable=true, root enable=false, marker present)
t15_kroot false false
printf '[harvest]\nenable = true\n' > "$T15D/proj/.kit.toml"
R="$(t15_run 1 "")"
assert_eq "AC8: a project toml cannot activate the gate" "1" "$(tf "$R" calls)"
rm -f "$T15D/proj/.kit.toml"

# --cleanup is an operator verb: never gated even on an active host
t15_kroot true false
printf '| date | item | kind | home | status |\n|---|---|---|---|---|\n| 2026-01-05 | done-row | insight | til | flushed:r1 |\n' > "$T15D/led.md"
rm -rf "$T15D/state"; mkdir -p "$T15D/state/sweep"; : > "$T15D/state/sweep/installed"
env -i PATH="$PATH" HOME="$HOME" \
  HARVEST_LEDGER="$T15D/led.md" \
  HARVEST_STATE_DIR="$T15D/state" \
  KIT_CONFIG_ROOT="$T15D/kroot" KIT_CONFIG_OPERATOR="$T15D/noop" KIT_PROJECT_ROOT="$T15D/proj" \
  bash "$KIT_DIR/hooks/harvest.sh" --cleanup >/dev/null 2>&1 || true
assert_eq "AC8: --cleanup is unaffected by the gate" "yes" "$([ -f "$T15D/led.archive.md" ] && echo yes || echo no)"

# the shipped kit.toml's [harvest] table parses and defaults the switch off
T15_HV="$(KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$T15D/noop" KIT_PROJECT_ROOT="$T15D/proj" \
  bash -c "source '$KIT_DIR/lib/config/kit-config.sh'; printf '%s|%s|%s|%s' \
    \"\$(kit_config_get_root harvest.enable X)\" \
    \"\$(kit_config_get_root harvest.schedule_hours X)\" \
    \"\$(kit_config_get_root harvest.sources X)\" \
    \"\$(kit_config_get_root harvest.hook_when_sweep_on X)\"")"
assert_eq "kit.toml ships the [harvest] table with safe defaults" "false|6|claude|false" "$T15_HV"

# ============================================================================
# T16 launchd launcher + plist template (the launcher part of AC4, AC19):
# the launcher re-checks the host is active (installed marker + root-only
# harvest.enable), calls harvest_sweep.py --sweep directly so the rc reaches
# the bridge, and calls the bridge on every outcome except a lock-held run.
# Tests run it with a temp HOME, a stub python3 on the launcher's own PATH
# prepend ($HOME/.local/bin), and a stub bridge under ~/.config/harvest-sweep.
# ============================================================================
echo
echo "T16 launcher and plist template"

T16D="$TD/t16"; T16_HOME="$T16D/home"; T16_LAUNCH="$KIT_DIR/deploy/macos/harvest-sweep/harvest-sweep"
mkdir -p "$T16_HOME/.local/bin" "$T16_HOME/.config/harvest-sweep" \
  "$T16_HOME/Library/Logs/dwarves-kit" "$T16D/kroot" "$T16D/noop" "$T16D/proj"

# stub python3: $1 is the script path, $2 the verb. --status reports the newest
# recorded report (or none); --sweep records the call, "produces" a run report
# unless STUB_SWEEP_RUN=0 (idle/lock-held stand-in), and exits STUB_SWEEP_RC.
cat > "$T16_HOME/.local/bin/python3" <<EOF
#!/usr/bin/env bash
verb="\$2"
sdir="\${HARVEST_STATE_DIR:-/nonexistent}"
case "\$verb" in
  --status)
    if [ -f "$T16D/newest" ]; then printf '%s candidates=0 queued=0\n' "\$(cat "$T16D/newest")"; else echo none; fi
    ;;
  --sweep)
    echo call >> "$T16D/sweep-calls"
    if [ "\${STUB_SWEEP_LOCKHELD:-0}" = "1" ]; then
      echo 'harvest-sweep: sweep.lock held; skipping run' >&2
      exit 0
    fi
    if [ "\${STUB_SWEEP_RUN:-1}" = "1" ]; then
      n=\$(( \$(cat "$T16D/seq" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$T16D/seq"
      rep="\$sdir/sweep/runs/run-\$n/report.md"
      mkdir -p "\$(dirname "\$rep")"; echo report > "\$rep"
      printf '%s' "\$rep" > "$T16D/newest"
    fi
    exit "\${STUB_SWEEP_RC:-0}"
    ;;
esac
EOF
chmod +x "$T16_HOME/.local/bin/python3"
cat > "$T16_HOME/.config/harvest-sweep/bridge" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "\$1" "\$2" >> "$T16D/bridge-calls"
EOF
chmod +x "$T16_HOME/.config/harvest-sweep/bridge"
printf '[harvest]\nenable = true\n' > "$T16D/kroot/kit.toml"

# t16_run [env pairs...] -> "rc=N sweep=N bridge=<args|none>"
t16_run() {
  rm -rf "$T16_HOME/state"
  mkdir -p "$T16_HOME/state/sweep"; : > "$T16_HOME/state/sweep/installed"
  case " $* " in *"STUB_SWEEP_LOCKHELD=1"*) : > "$T16_HOME/state/sweep/sweep.lock" ;; esac
  if [ "${1:-}" = "--no-marker" ]; then shift; rm -f "$T16_HOME/state/sweep/installed"; fi
  rm -f "$T16D/sweep-calls" "$T16D/bridge-calls" "$T16D/newest" "$T16D/seq"
  rm -f "$T16_HOME/Library/Logs/dwarves-kit"/*.log
  # T16_STALE=1: an older run's report is already the newest one on disk
  case " $* " in *"T16_STALE=1"*)
    mkdir -p "$T16_HOME/state/sweep/runs/run-old"; echo old > "$T16_HOME/state/sweep/runs/run-old/report.md"
    touch -t 200001010000 "$T16_HOME/state/sweep/runs/run-old/report.md"
    printf '%s' "$T16_HOME/state/sweep/runs/run-old/report.md" > "$T16D/newest" ;;
  esac
  local rc=0
  env -i HOME="$T16_HOME" PATH=/usr/bin:/bin TERM=dumb \
    HARVEST_STATE_DIR="$T16_HOME/state" \
    KIT_CONFIG_ROOT="$T16D/kroot" KIT_CONFIG_OPERATOR="$T16D/noop" KIT_PROJECT_ROOT="$T16D/proj" \
    "$@" bash "$T16_LAUNCH" >/dev/null 2>&1 || rc=$?
  local sw=0 br=none
  [ -f "$T16D/sweep-calls" ] && sw=$(wc -l < "$T16D/sweep-calls" | tr -d ' ')
  [ -f "$T16D/bridge-calls" ] && br="$(cat "$T16D/bridge-calls")"
  printf 'rc=%s sweep=%s\nbridge=%s\n' "$rc" "$sw" "$br"
}
t16_log() { cat "$T16_HOME/Library/Logs/dwarves-kit/harvest-sweep.log" 2>/dev/null; }
t16b() { printf '%s' "$1" | sed -n 's/^bridge=//p'; }

R="$(t16_run --no-marker)"
assert_eq "AC4: an unmarked host exits 0 and never runs the sweep" "0" "$(tf "$R" rc)"
assert_eq "AC4: an unmarked host never calls the sweep" "0" "$(tf "$R" sweep)"
assert_eq "AC4: an unmarked host never calls the bridge" "none" "$(t16b "$R")"
assert_eq "AC19: the skip lands a log line" "yes" "$([ -n "$(t16_log)" ] && echo yes || echo no)"

printf '[harvest]\nenable = false\n' > "$T16D/kroot/kit.toml"
R="$(t16_run)"
assert_eq "AC4: a disabled host exits 0 and never calls the sweep" "0" "$(tf "$R" sweep)"
assert_eq "AC4: a disabled host never calls the bridge" "none" "$(t16b "$R")"

printf '[harvest]\nenable = true\n' > "$T16D/kroot/kit.toml"
R="$(t16_run)"
assert_eq "AC4: an active run calls the sweep once" "1" "$(tf "$R" sweep)"
assert_eq "AC4: a clean run calls the bridge with rc 0 and the report" "0 $T16_HOME/state/sweep/runs/run-1/report.md" "$(t16b "$R")"
assert_eq "AC19: the log opens with a start line" "yes" "$(t16_log | grep -c 'start harvest-sweep' | sed 's/^0$/no/;s/^[1-9].*/yes/')"
assert_eq "AC19: the log records end rc=0" "1" "$(t16_log | grep -c 'end rc=0')"

R="$(t16_run STUB_SWEEP_RC=1)"
assert_eq "AC4: the launcher passes rc 1 to the bridge" "1 $T16_HOME/state/sweep/runs/run-1/report.md" "$(t16b "$R")"

R="$(t16_run STUB_SWEEP_RC=1 STUB_SWEEP_RUN=0)"
assert_eq "AC4: a crash before the report sends '-' as the path" "1 -" "$(t16b "$R")"

R="$(t16_run STUB_SWEEP_RUN=0)"
assert_eq "AC4: an idle run pings the bridge with '-'" "0 -" "$(t16b "$R")"
assert_eq "AC19: the no-report run still logs end rc" "1" "$(t16_log | grep -c 'end rc=0')"

# a run that writes no report never passes an older run's report path
R="$(t16_run STUB_SWEEP_RUN=0 T16_STALE=1)"
assert_eq "AC4: a stale report is never passed to the bridge" "0 -" "$(t16b "$R")"

R="$(t16_run STUB_SWEEP_LOCKHELD=1)"
assert_eq "AC4: a lock-held run still reaches the sweep call" "1" "$(tf "$R" sweep)"
assert_eq "AC4: a lock-held run exits 0" "0" "$(tf "$R" rc)"
assert_eq "AC4: a lock-held run never calls the bridge" "none" "$(t16b "$R")"

# optional env file: per-machine settings load before the sweep runs
printf 'export STUB_SWEEP_RC=3\n' > "$T16_HOME/.config/harvest-sweep/env"
R="$(t16_run)"
rm -f "$T16_HOME/.config/harvest-sweep/env"
assert_eq "AC19: the optional env file is sourced" "3 $T16_HOME/state/sweep/runs/run-1/report.md" "$(t16b "$R")"

R="$(t16_run HARVEST_SWEEP_LABEL=mini.harvest-sweep)"
assert_eq "the label names the log file" "yes" "$([ -f "$T16_HOME/Library/Logs/dwarves-kit/mini.harvest-sweep.log" ] && echo yes || echo no)"

# plist template renders to a valid plist with the launcher as ProgramArguments[0]
sed -e "s|__LABEL__|mini.harvest-sweep|g" -e "s|__KIT__|$KIT_DIR|g" \
    -e "s|__HOME__|$T16_HOME|g" -e "s|__INTERVAL__|21600|g" \
    "$T16_LAUNCH.plist.tmpl" > "$T16D/rendered.plist"
assert_eq "AC19: the rendered plist lints" "OK" "$(plutil -lint "$T16D/rendered.plist" 2>/dev/null | awk '{print $2}')"
assert_eq "AC19: ProgramArguments[0] is the launcher's absolute path" "$T16_LAUNCH" \
  "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$T16D/rendered.plist" 2>/dev/null)"
assert_eq "AC19: StartInterval renders the seconds" "21600" \
  "$(/usr/libexec/PlistBuddy -c 'Print :StartInterval' "$T16D/rendered.plist" 2>/dev/null)"
assert_eq "AC19: no placeholder survives rendering" "0" "$(grep -c '__[A-Z]*__' "$T16D/rendered.plist")"
assert_eq "AC19: the launcher is a shebang script without .sh" "yes" \
  "$(head -1 "$T16_LAUNCH" | grep -q '^#!/bin/bash' && echo yes || echo no)"

# ============================================================================
# T17 installer (AC13, DEC-9, DEC-13, DEC-27, DEC-47, DEC-69): install renders
# the plist, gates on root-only harvest.enable, --apply writes the plist +
# installed marker and bootstraps, --uninstall removes only what --apply
# wrote. Tests stub launchctl on PATH and point HOME/state at temp dirs;
# nothing touches real launchd, ~/Library, or real state.
echo
echo "T17 installer"

T17D="$TD/t17"; T17_HOME="$T17D/home"; T17_INSTALL="$KIT_DIR/deploy/macos/harvest-sweep/install"
mkdir -p "$T17_HOME" "$T17D/bin" "$T17D/kroot" "$T17D/noop" "$T17D/proj"

cat > "$T17D/bin/launchctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T17D/launchctl-calls"
EOF
chmod +x "$T17D/bin/launchctl"
printf '[harvest]\nenable = true\n' > "$T17D/kroot/kit.toml"

# t17_install [ENV=X ...] -- [install args] -> "rc=N"; installer stdout+stderr
# lands in $T17D/out, launchctl argv in $T17D/launchctl-calls.
t17_install() {
  local envs=() args=() seen=0 a
  for a in "$@"; do
    if [ "$a" = "--" ] && [ "$seen" = "0" ]; then seen=1; continue; fi
    if [ "$seen" = "0" ]; then envs+=("$a"); else args+=("$a"); fi
  done
  rm -f "$T17D/launchctl-calls"; : > "$T17D/out"
  local rc=0
  env -i HOME="$T17_HOME" PATH="$T17D/bin:/usr/bin:/bin" TERM=dumb \
    HARVEST_STATE_DIR="$T17D/state" \
    KIT_CONFIG_ROOT="$T17D/kroot" KIT_CONFIG_OPERATOR="$T17D/noop" KIT_PROJECT_ROOT="$T17D/proj" \
    ${envs[@]+"${envs[@]}"} bash "$T17_INSTALL" ${args[@]+"${args[@]}"} > "$T17D/out" 2>&1 || rc=$?
  printf 'rc=%s\n' "$rc"
}
t17_out() { cat "$T17D/out"; }
t17_lc()  { cat "$T17D/launchctl-calls" 2>/dev/null; }

printf '[harvest]\nenable = false\n' > "$T17D/kroot/kit.toml"
R="$(t17_install --)"
assert_eq "AC13: install refuses when harvest.enable is false" "2" "$(tf "$R" rc)"
assert_eq "AC13: the refusal names the knob to set" "yes" \
  "$(t17_out | grep -q 'harvest.enable' && echo yes || echo no)"

printf '[harvest]\nenable = false\n' > "$T17D/kroot/kit.toml"
printf '[harvest]\nenable = true\n' > "$T17D/proj/.kit.toml"
R="$(t17_install --)"
assert_eq "DEC-9: a project .kit.toml cannot switch the install on" "2" "$(tf "$R" rc)"
rm -f "$T17D/proj/.kit.toml"
printf '[harvest]\nenable = true\n' > "$T17D/kroot/kit.toml"

R="$(t17_install -- --label '../evil')"
assert_eq "a path-shaped label is refused" "2" "$(tf "$R" rc)"

R="$(t17_install --)"
assert_eq "AC13: the dry run exits 0" "0" "$(tf "$R" rc)"
assert_eq "AC13: the render's ProgramArguments[0] is the launcher path" "yes" \
  "$(t17_out | grep -q "<string>$KIT_DIR/deploy/macos/harvest-sweep/harvest-sweep</string>" && echo yes || echo no)"
assert_eq "AC13: the dry run writes no plist" "no" \
  "$([ -f "$T17_HOME/Library/LaunchAgents/harvest-sweep.plist" ] && echo yes || echo no)"
assert_eq "AC13: the dry run writes no marker" "no" \
  "$([ -f "$T17D/state/sweep/installed" ] && echo yes || echo no)"
assert_eq "AC13: the dry run never calls launchctl" "0" "$(t17_lc | wc -l | tr -d ' ')"
assert_eq "AC13: the dry run prints the bootstrap it would run" "yes" \
  "$(t17_out | grep -q 'launchctl bootstrap' && echo yes || echo no)"
assert_eq "AC13: the dry run renders the default 6h interval" "yes" \
  "$(t17_out | grep -q '<integer>21600</integer>' && echo yes || echo no)"

R="$(t17_install -- --label mini.harvest-sweep)"
assert_eq "DEC-13: --label renders the Mini label" "yes" \
  "$(t17_out | grep -q '<string>mini.harvest-sweep</string>' && echo yes || echo no)"
assert_eq "AC13: the label reaches the plist's environment" "yes" \
  "$(t17_out | grep -q 'HARVEST_SWEEP_LABEL' && echo yes || echo no)"

printf '[harvest]\nenable = true\nschedule_hours = 4\n' > "$T17D/kroot/kit.toml"
R="$(t17_install --)"
assert_eq "AC13: schedule_hours renders StartInterval in seconds" "yes" \
  "$(t17_out | grep -q '<integer>14400</integer>' && echo yes || echo no)"
printf '[harvest]\nenable = true\n' > "$T17D/kroot/kit.toml"

# --apply: plist + marker written, launchctl bootstrap invoked (stub records)
R="$(t17_install -- --apply --label mini.harvest-sweep)"
assert_eq "AC13: --apply exits 0" "0" "$(tf "$R" rc)"
assert_eq "AC13: --apply writes the plist under LaunchAgents" "yes" \
  "$([ -f "$T17_HOME/Library/LaunchAgents/mini.harvest-sweep.plist" ] && echo yes || echo no)"
assert_eq "AC13: the written plist lints" "OK" \
  "$(plutil -lint "$T17_HOME/Library/LaunchAgents/mini.harvest-sweep.plist" 2>/dev/null | awk '{print $2}')"
assert_eq "AC13: the written plist's ProgramArguments[0] is the launcher" \
  "$KIT_DIR/deploy/macos/harvest-sweep/harvest-sweep" \
  "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$T17_HOME/Library/LaunchAgents/mini.harvest-sweep.plist" 2>/dev/null)"
assert_eq "AC13: --apply bootstraps the label" "yes" \
  "$(t17_lc | grep -q "bootstrap gui/[0-9]* .*mini.harvest-sweep.plist" && echo yes || echo no)"
assert_eq "AC13: --apply writes the installed marker" "yes" \
  "$([ -f "$T17D/state/sweep/installed" ] && echo yes || echo no)"
assert_eq "AC13: the marker carries label, host, kit, ts" \
  "host,kit,label,ts mini.harvest-sweep $KIT_DIR True" \
  "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(",".join(sorted(d)), d["label"], d["kit"], isinstance(d["ts"], int))' "$T17D/state/sweep/installed")"

# --uninstall: removes only what --apply wrote; sweep state survives
mkdir -p "$T17D/state/sweep/ledger" "$T17D/state/sweep/extract/claude" "$T17D/state/sweep/runs/run-1"
printf 'x\n' > "$T17D/state/sweep/cursor.json"
printf 'x\n' > "$T17D/state/sweep/patterns.jsonl"
printf 'x\n' > "$T17D/state/sweep/proposed.jsonl"
printf 'cached\n' > "$T17D/state/sweep/extract/claude/sess@1000.json"
printf 'report\n' > "$T17D/state/sweep/runs/run-1/report.md"
cat > "$T17D/state/sweep/ledger/test.md" <<'EOF'
| date | item | kind | home | status |
|---|---|---|---|---|
| 2026-09-30 | Item A | insight | til | queued |
| 2026-09-30 | Item B | insight | til | queued |
| 2026-09-30 | Item C | insight | til | flushed:wrap-1 |
EOF
R="$(t17_install -- --uninstall --label mini.harvest-sweep)"
assert_eq "AC13: --uninstall exits 0" "0" "$(tf "$R" rc)"
assert_eq "AC13: --uninstall boots out the label" "yes" \
  "$(t17_lc | grep -q 'bootout gui/[0-9]*/mini.harvest-sweep' && echo yes || echo no)"
assert_eq "AC13: --uninstall removes the plist" "no" \
  "$([ -f "$T17_HOME/Library/LaunchAgents/mini.harvest-sweep.plist" ] && echo yes || echo no)"
assert_eq "AC13: --uninstall removes the marker" "no" \
  "$([ -f "$T17D/state/sweep/installed" ] && echo yes || echo no)"
for kept in cursor.json patterns.jsonl proposed.jsonl ledger/test.md extract/claude/sess@1000.json runs/run-1/report.md; do
  assert_eq "AC13: --uninstall leaves sweep/$kept" "yes" \
    "$([ -f "$T17D/state/sweep/$kept" ] && echo yes || echo no)"
done
assert_eq "AC13: --uninstall prints the state path" "yes" \
  "$(t17_out | grep -q "$T17D/state/sweep" && echo yes || echo no)"
assert_eq "AC13: --uninstall prints the queued-learning count" "yes" \
  "$(t17_out | grep -q 'queued learnings: 2' && echo yes || echo no)"
assert_eq "AC13: --uninstall prints the extract/ size" "yes" \
  "$(t17_out | grep -q 'extract/ size' && echo yes || echo no)"
assert_eq "DEC-69: --uninstall prints the purge command it never runs" "yes" \
  "$(t17_out | grep -qF "rm -rf '$T17D/state/sweep/extract'" && echo yes || echo no)"
assert_eq "DEC-69: the purge is printed, not run" "yes" \
  "$([ -d "$T17D/state/sweep/extract" ] && echo yes || echo no)"

# AC13 chain: install (marker present, hook gated) -> uninstall -> hook runs again.
# Reuses the T15 hook harness (stub extractor, transcript) against the T17 state dir.
printf '[harvest]\nenable = true\nhook_when_sweep_on = false\n' > "$T17D/kroot/kit.toml"
t17_hook_calls() {
  rm -f "$T15D/calls"
  env -i PATH="$PATH" HOME="$HOME" REPO_ROOT="$T15D/repo" HARVEST_EXTRACTOR="$T15D/ext.sh"     HARVEST_SYNC=1 HARVEST_MIN_INTERVAL=0 HARVEST_STATE_DIR="$T17D/state" STUB_CALLS="$T15D/calls"     KIT_CONFIG_ROOT="$T17D/kroot" KIT_CONFIG_OPERATOR="$T17D/noop" KIT_PROJECT_ROOT="$T17D/proj"     bash -c "echo '{\"transcript_path\":\"$T15D/transcript.jsonl\",\"session_id\":\"t17chain\"}' | bash '$KIT_DIR/hooks/harvest.sh'" \
    >/dev/null 2>&1 || true
  [ -f "$T15D/calls" ] && wc -l < "$T15D/calls" | tr -d ' ' || echo 0
}
t17_install -- --apply --label mini.harvest-sweep >/dev/null
assert_eq "AC13 chain: after install the hook is gated off" "0" "$(t17_hook_calls)"
t17_install -- --uninstall --label mini.harvest-sweep >/dev/null
assert_eq "AC13 chain: after uninstall the hook runs again" "1" "$(t17_hook_calls)"

# ============================================================
echo ""
echo "=== Results ==="
echo "Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}$FAIL test(s) failed.${NC}"
  exit 1
fi
echo -e "${GREEN}All harvest sweep tests passed.${NC}"
