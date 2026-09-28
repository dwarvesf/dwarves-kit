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
echo "=== Results ==="
echo "Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}$FAIL test(s) failed.${NC}"
  exit 1
fi
echo -e "${GREEN}All harvest sweep tests passed.${NC}"
