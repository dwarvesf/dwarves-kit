#!/usr/bin/env bash
# Golden-fixture + over-test for `git_fixes` / `ledger defect-correlation` (SPEC-132 test plan).
#
# Unlike test-gate-yield.sh (which points at a COMMITTED fixture ledger dir), this fixture is
# generated at test-time in $(mktemp -d): a real git repo is created with `git init` + a small
# set of commits at CONTROLLED author/committer dates (the SG-02 goal file allows "a committed
# mini git-history fixture (OR a fixture table)"; a nested .git tree does not commit cleanly
# inside this repo, so a deterministic generated repo is the fixture, same precedent as
# test-ledger-cli.sh/test-feedback.sh/test-render-skill.sh's own mktemp-per-run fixtures).
#
# The FP-NC (F-nc) is load-bearing: `clean-feature` ships and NO commit ever fixes its file
# (`clean.py`); defect-correlation MUST report it `clean`, never `fix-followed`.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }

FIX="$(mktemp -d)"
GITREPO="$FIX/repo"
KITLOG="$FIX/kit-runs"

# ---- build the git fixture: a real repo, controlled dates, no interactive prompts ----------
mkdir -p "$GITREPO"
# --template= disables copying this machine's global commit-msg hook (Conventional-Commit
# enforcement via ~/.git_template, wired for real repos) into the throwaway fixture repo.
git -C "$GITREPO" init -q -b main --template=
git -C "$GITREPO" config user.name "Fixture Bot"
git -C "$GITREPO" config user.email "fixture@example.com"
git -C "$GITREPO" config commit.gpgsign false

commit() {
  # commit <relpath> <content> <subject> <iso8601-date>
  local rel="$1" content="$2" subject="$3" date="$4"
  mkdir -p "$(dirname "$GITREPO/$rel")"
  printf '%s\n' "$content" > "$GITREPO/$rel"
  git -C "$GITREPO" add "$rel" >/dev/null
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$GITREPO" commit -q -m "$subject" >/dev/null
}

# widget-parser: shipped, then a fix on the SAME file within the default 30d window -> MISS.
commit parser.py "v1"           "feat(widget-parser): add parser"            "2026-01-01T00:00:00+00:00"
commit parser.py "v2"           "fix(widget-parser): handle empty input"     "2026-01-06T00:00:00+00:00"
# a second, later fix on the SAME file+window -> "multiple fixes same file" over-test.
commit parser.py "v3"           "fix(widget-parser): handle unicode input"   "2026-01-10T00:00:00+00:00"

# clean-feature: shipped, NEVER fixed -- the FP negative control.
commit clean.py  "v1"           "feat(clean-feature): add clean thing"       "2026-02-01T00:00:00+00:00"

# windowed-out: shipped, fixed but 90 days later (beyond the default 30d window) -> clean
# at the default window, fix-followed once --window-days is widened -> proves the tunable is
# real, not a buried constant.
commit win.py    "v1"           "feat(windowed-out): add windowed thing"     "2026-03-01T00:00:00+00:00"
commit win.py    "v2"           "fix(windowed-out): patch late"              "2026-05-30T00:00:00+00:00"

# renamer: a rename inside the ship commit itself (old.py + new.py both touched, no -M
# detection assumed); a later fix touches only the NEW name -> proves the rename boundary
# doesn't crash and each filename is tracked independently (file-level only, v1; no
# rename-following).
mkdir -p "$GITREPO"
printf 'v1\n' > "$GITREPO/old.py"
git -C "$GITREPO" add old.py >/dev/null
GIT_AUTHOR_DATE="2026-04-01T00:00:00+00:00" GIT_COMMITTER_DATE="2026-04-01T00:00:00+00:00" \
  git -C "$GITREPO" commit -q -m "feat(renamer): add module" >/dev/null
git -C "$GITREPO" mv old.py new.py
GIT_AUTHOR_DATE="2026-04-02T00:00:00+00:00" GIT_COMMITTER_DATE="2026-04-02T00:00:00+00:00" \
  git -C "$GITREPO" commit -q -m "feat(renamer): rename old.py to new.py" >/dev/null
commit new.py "v2" "fix(renamer): handle edge case in renamed module" "2026-04-05T00:00:00+00:00"

# an UNRELATED fix commit, touching neither clean.py nor any other fixture file -- proves a
# fix() commit that touches only unrelated files never contaminates an unrelated rid's row.
commit unrelated.py "v1" "fix(something-else): unrelated patch" "2026-02-15T00:00:00+00:00"

# mergetest: a genuine 2-parent merge commit whose subject would otherwise match AND look like
# a fix -- proves --no-merges excludes it from git_fixes entirely (not filtered on content).
commit a.py "v1" "feat(mergetest): base work" "2026-06-01T00:00:00+00:00"
git -C "$GITREPO" branch side >/dev/null
git -C "$GITREPO" checkout -q side
commit b.py "v1" "chore(mergetest): side branch change" "2026-06-02T00:00:00+00:00"
git -C "$GITREPO" checkout -q main
GIT_AUTHOR_DATE="2026-06-03T00:00:00+00:00" GIT_COMMITTER_DATE="2026-06-03T00:00:00+00:00" \
  git -C "$GITREPO" merge -q --no-ff -m "fix(mergetest): merge should not count" side >/dev/null
MERGE_SHA="$(git -C "$GITREPO" rev-parse HEAD)"

# ---- build the kit_gates fixture: one committed "ship ran" rid per git-fixture rid ---------
mkdir -p "$KITLOG/runs"
mkship() {
  local rid="$1" ts="$2"
  cat > "$KITLOG/runs/$rid.log" <<EOF
${ts} | START | lane=normal classified=normal type=feat ctype=feat repo=fixrepo
${ts} | GATE | ship | ran | shipped
EOF
}
mkship widget-parser  "2026-01-01T00:00:00Z"
mkship clean-feature  "2026-02-01T00:00:00Z"
mkship windowed-out   "2026-03-01T00:00:00Z"
mkship renamer        "2026-04-01T00:00:00Z"
mkship mergetest       "2026-06-01T00:00:00Z"

export DWARVES_KIT_LOG_DIR="$KITLOG"
export LEDGER_OBS_GIT_REPO_DIR="$GITREPO"
export LEDGER_OBS_TIDE_DB="$FIX/state.sqlite"          # absent -> skip-safe empty table
export LEDGER_OBS_TGCLEANUP_DIR="$FIX/tg"              # empty -> skip-safe
export LEDGER_OBS_LEARNED_MD="$FIX/learned.md"         # absent -> skip-safe
export LEDGER_OBS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"     # absent -> skip-safe empty sessions
export LEDGER_OBS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"   # absent -> skip-safe empty safety
export LEDGER_OBS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"      # absent -> skip-safe empty memories (repo store)
export LEDGER_OBS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"  # absent -> skip-safe empty memories (builtin store)
export LEDGER_OBSERVATORY_DB="$FIX/lens.duckdb"
mkdir -p "$LEDGER_OBS_TGCLEANUP_DIR"

R() { uv run ledger "$@" 2>&1; }

echo "== D-rebuild: git_fixes + kit_gates materialize from the generated fixtures =="
OUT="$(R rebuild)"
has "D-rebuild kit_gates=5" '"kit_gates": 5' "$OUT"
# 12 non-merge fixture commits (parser x3, clean x1, win x2, renamer-add x1, renamer-rename x1,
# renamer-fix x1, unrelated x1, mergetest base x1, mergetest side x1), one file each = 12 rows.
# The 13th commit (the merge) is excluded by --no-merges (see D-nc-merge below).
has "D-rebuild git_fixes=12 (merge commit excluded)" '"git_fixes": 12' "$OUT"

echo "== D-nc-merge: the merge commit itself never appears in git_fixes (--no-merges) =="
ROWS_SHA="$(R show git_fixes --json | python3 -c 'import json,sys; print(" ".join(r["sha"] for r in json.load(sys.stdin)))')"
case " $ROWS_SHA " in
  *" $MERGE_SHA "*) bad "D-nc-merge merge sha $MERGE_SHA leaked into git_fixes";;
  *) ok "D-nc-merge merge commit sha absent from git_fixes";;
esac

echo "== D-miss: widget-parser is fix-followed on parser.py (default 30d window) =="
DC="$(R defect-correlation --json)"
has "D-miss widget-parser/parser.py fix-followed (fix #1)" '"rid": "widget-parser",
    "ship_ts": "2026-01-01T00:00:00Z",
    "file": "parser.py",
    "label": "fix-followed",' "$DC"
N_WP="$(printf '%s' "$DC" | python3 -c 'import json,sys; print(sum(1 for r in json.load(sys.stdin) if r["rid"]=="widget-parser" and r["label"]=="fix-followed"))')"
if [ "$N_WP" -eq 2 ]; then ok "D-multi widget-parser/parser.py has BOTH later fixes as separate rows (not collapsed)"; else bad "D-multi want 2 fix-followed rows for widget-parser, got $N_WP"; fi

echo "== F-nc: FALSE-POSITIVE negative control (load-bearing) =="
CLEAN_ROW="$(printf '%s' "$DC" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
for r in rows:
    if r["rid"] == "clean-feature":
        print(json.dumps(r)); sys.exit(0)
print("MISSING")
')"
if [ "$CLEAN_ROW" = "MISSING" ]; then
  bad "F-nc clean-feature row missing entirely (should be present and labeled clean)"
else
  has "F-nc clean-feature labeled clean, no fix_sha" '"label": "clean"' "$CLEAN_ROW"
  hasnt "F-nc clean-feature never fix-followed" '"label": "fix-followed"' "$CLEAN_ROW"
  ok "F-nc clean-feature reported honestly: clean, never fix-followed"
fi
hasnt "F-nc-unrelated the unrelated fix() commit never contaminates clean-feature's row" '"something-else"' "$CLEAN_ROW"

echo "== D-window: windowed-out is clean at the default window, fix-followed at a wider one =="
has "D-window windowed-out clean by default (fix is 90d later, past the 30d window)" '"rid": "windowed-out",
    "ship_ts": "2026-03-01T00:00:00Z",
    "file": "win.py",
    "label": "clean"' "$DC"
DC_WIDE="$(R defect-correlation --window-days 120 --json)"
has "D-window --window-days 120 flips windowed-out to fix-followed (the tunable is real)" '"rid": "windowed-out",
    "ship_ts": "2026-03-01T00:00:00Z",
    "file": "win.py",
    "label": "fix-followed",' "$DC_WIDE"

echo "== D-rename: rename boundary tracked per-filename, no crash, no false pairing =="
# ship_first anchors on the EARLIEST commit whose subject mentions the rid: the "add module"
# commit (2026-04-01, touches old.py), not the later rename commit -- so `old.py` is the only
# file this rid's row ever tracks. This is the documented v1 limitation the goal file calls out
# ("renames: file-level only, v1", no rename-following): a fix landing on the POST-rename name
# is invisible to a run whose anchor predates the rename. Proven here, not silently assumed.
has "D-rename old.py (the anchor commit's own file) is tracked, stays clean" '"rid": "renamer",
    "ship_ts": "2026-04-01T00:00:00Z",
    "file": "old.py",
    "label": "clean"' "$DC"
hasnt "D-rename no renamer/new.py row exists at all (the rename is NOT followed, v1 limitation)" '"rid": "renamer",
    "ship_ts": "2026-04-01T00:00:00Z",
    "file": "new.py"' "$DC"

echo "== F-nc-deliberate-break: prove the file-overlap join is load-bearing, not vacuous =="
# Simulate the bug this design guards against: a naive rid+time correlation with NO file-
# equality condition would flag ANY shipped rid that has ANY later fix() commit at all,
# including clean-feature (which has none of its OWN files fixed, but co-exists in a history
# that has plenty of unrelated fix() commits after it).
BROKEN="$(uv run python3 - <<'PY' 2>&1
from ledger_observatory import materialize
cols, rows = materialize.query("""
    WITH shipped AS (
        SELECT DISTINCT rid FROM kit_gates WHERE gate = 'ship' AND outcome IN ('ran', 'override')
    ),
    mentions AS (
        SELECT DISTINCT s.rid, min(g.ts) AS ship_ts
        FROM shipped s JOIN git_fixes g ON contains(lower(g.subject), lower(s.rid))
        GROUP BY s.rid
    )
    SELECT m.rid, count(*) AS any_later_fix
    FROM mentions m
    JOIN git_fixes g ON regexp_matches(g.subject, '^fix(\\(.*\\))?!?:')
        AND CAST(g.ts AS TIMESTAMPTZ) > CAST(m.ship_ts AS TIMESTAMPTZ)
    GROUP BY m.rid ORDER BY m.rid
""")
import json
print(json.dumps([dict(zip(cols, r)) for r in rows]))
PY
)"
has "F-nc-deliberate-break a file-blind (rid+time only) join WOULD flag clean-feature (the bug the real query avoids)" '"rid": "clean-feature"' "$BROKEN"

echo "== O-plan: over-test pass on read_git_fixes() directly (edge cases beyond the fixture) =="
OVER="$(uv run python3 - <<PY 2>&1
from pathlib import Path
from ledger_observatory import adapters

results = []

# O1: repo path does not exist at all -> empty columns + empty rows, no exception.
cols, rows = adapters.read_git_fixes(Path("/nonexistent-o1-repo-xyz"))
results.append(("O1-missing-repo", cols == adapters.GIT_FIXES_COLUMNS and rows == []))

# O2: a real directory that is NOT a git repo (no .git) -> empty, no exception.
import tempfile
with tempfile.TemporaryDirectory() as td:
    cols2, rows2 = adapters.read_git_fixes(Path(td))
    results.append(("O2-not-a-repo", rows2 == []))

# O3: the merge commit is excluded, its two linear parents are present.
cols3, rows3 = adapters.read_git_fixes(Path("$GITREPO"))
shas = {r[0] for r in rows3}
results.append(("O3-merge-excluded", "$MERGE_SHA" not in shas))
results.append(("O3-linear-commits-present", len(shas) > 0))

for name, passed in results:
    print(f"{name}={'OK' if passed else 'FAIL'}")
PY
)"
has "O1-missing-repo OK (empty columns+rows, no exception)" "O1-missing-repo=OK" "$OVER"
has "O2-not-a-repo OK (no .git -> empty, no crash)" "O2-not-a-repo=OK" "$OVER"
has "O3-merge-excluded OK (merge sha absent)" "O3-merge-excluded=OK" "$OVER"
has "O3-linear-commits-present OK (real commits still read)" "O3-linear-commits-present=OK" "$OVER"

echo "== D-remat: delete-and-rematerialize is byte-identical (git fixture is canonical) =="
BEFORE="$(R show git_fixes --json)"
rm -f "$LEDGER_OBSERVATORY_DB" "$LEDGER_OBSERVATORY_DB.wal"
AFTER="$(R show git_fixes --json)"
if [ "$BEFORE" = "$AFTER" ] && [ -n "$BEFORE" ]; then ok "D-remat identical output"; else bad "D-remat output differs after delete+rebuild"; fi

echo "== D-nc: read-only negative control (the fixture git repo is never mutated) =="
BEFORE_LOG="$(git -C "$GITREPO" log --format=%H --all)"
R query "SELECT count(*) FROM git_fixes" >/dev/null
AFTER_LOG="$(git -C "$GITREPO" log --format=%H --all)"
if [ "$BEFORE_LOG" = "$AFTER_LOG" ]; then ok "D-nc fixture git history unchanged after rebuild+queries"; else bad "D-nc fixture git history changed"; fi

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
