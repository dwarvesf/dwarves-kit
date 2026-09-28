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
echo ""
echo "=== Results ==="
echo "Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}$FAIL test(s) failed.${NC}"
  exit 1
fi
echo -e "${GREEN}All harvest sweep tests passed.${NC}"
