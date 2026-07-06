#!/usr/bin/env bash
# Golden-fixture + over-test for `impl_notes` / `ledger deviation-rate` / the `unknown-density`
# anomaly (SPEC-133 test plan). The upstream-unknowns half of the benchmark.
#
# Like test-defect-correlation.sh, the git-history side of this fixture is generated at
# test-time (`git init` in `mktemp -d` + controlled `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`
# commits), not a committed nested repo (same precedent, SPEC-132 DEC-005). The
# implementation-notes files are plain (untracked) files under the fixture repo's
# `docs/implementation-notes/` -- `read_impl_notes` is a filesystem walk, not a git read, so
# git-tracking them is not required.
#
# The HONEST-ZERO NC (I-classify clean-notes) is load-bearing: a zero-marker file with NO
# later fix ever touching its anchor's own files must classify CLEAN, never SUSPECT.
# Flagging honest zeros would teach people to stop writing the marker -- a benchmark that
# lies is worse than none. F-nc-deliberate-break proves it is falsifiable, not decorative.
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

# ---- build the git fixture: a real repo, controlled dates, no interactive prompts ----------
mkdir -p "$GITREPO"
# --template= disables copying this machine's global commit-msg hook (Conventional-Commit
# enforcement via ~/.git_template) into the throwaway fixture repo (SPEC-132 DEC-006 precedent).
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

# ---- impl-notes fixtures: one file per classification (SPEC-133 test plan) -----------------
NOTES="$GITREPO/docs/implementation-notes"
mkdir -p "$NOTES"

# clean-notes: honest zero, no later fix anywhere touches its anchor's own file -> CLEAN
# (the load-bearing honest-zero NC).
cat > "$NOTES/clean-notes.md" <<'EOF'
# Implementation notes clean-notes

No deviations; matches SPEC-CLEAN verbatim.
EOF

# suspect-notes: honest zero-marker, but a LATER fix() commit DOES touch the bridge-anchor's
# own file within the default window -> SUSPECT.
cat > "$NOTES/suspect-notes.md" <<'EOF'
# Implementation notes suspect-notes

No deviations; matches SPEC-SUSPECT verbatim.
EOF

# windowed-out-notes: honest zero-marker, a later fix exists but ~90d later (past the default
# 30d window) -> CLEAN at default, SUSPECT once --window-days is widened (proves the tunable
# is real, not a buried constant; mirrors SPEC-132's D-window case).
cat > "$NOTES/windowed-out-notes.md" <<'EOF'
# Implementation notes windowed-out-notes

No deviations; matches SPEC-WINDOW verbatim.
EOF

# underspecced-notes: 4 real entries (>= the default --under-specced-min 3) -> UNDER-SPECCED,
# independent of any git bridge/fix correlation.
cat > "$NOTES/underspecced-notes.md" <<'EOF'
# Implementation notes underspecced-notes

## 2026-05-01 First deviation
Context/Decision/Why/Alternatives/Impact.

## 2026-05-02 Second deviation
Context/Decision/Why/Alternatives/Impact.

## 2026-05-03 Third deviation
Context/Decision/Why/Alternatives/Impact.

## 2026-05-04 Fourth deviation
Context/Decision/Why/Alternatives/Impact.
EOF

# malformed-notes: BOTH a zero-marker line AND real entries (a self-contradiction). Over-test
# policy (SPEC-133 DEC-003): counted as entries (n_deviations=2), zero_marker forced False,
# a stderr warning logged (asserted in O-plan below).
cat > "$NOTES/malformed-notes.md" <<'EOF'
# Implementation notes malformed-notes

No deviations; matches SPEC-MALFORMED verbatim.

## 2026-05-05 Actually there was a deviation
Context/Decision/Why/Alternatives/Impact.

## 2026-05-06 14:00 A second one, with a time component
Context/Decision/Why/Alternatives/Impact.
EOF

# legacy-notes: predates the hook's dated-entry-header/zero-marker convention entirely
# (free-form prose sections, no "## YYYY-MM-DD" header at all) -- a REAL shape confirmed
# present in the corpus at design time. Neither CLEAN nor UNDER-SPECCED nor SUSPECT: OTHER,
# stated honestly rather than misclassified.
cat > "$NOTES/legacy-notes.md" <<'EOF'
# Implementation notes legacy-notes (delta from sub-goal spec)

Sub-goal: some pre-convention note with free-form prose sections.

## Why / safety
Some old-style subheading, not a dated entry header at all.
EOF

# multi-same-day: 2 entries dated the SAME day -- over-test: not deduped, n_deviations=2.
cat > "$NOTES/multi-same-day.md" <<'EOF'
# Implementation notes multi-same-day

## 2026-05-10 First entry today
Context/Decision/Why/Alternatives/Impact.

## 2026-05-10 Second entry same day
Context/Decision/Why/Alternatives/Impact.
EOF

# ---- git history: bridges (feat commits mentioning each slug) + later fixes ----------------
commit clean.py     "v1" "feat(clean-notes): add clean thing"           "2026-02-01T00:00:00+00:00"
commit suspect.py   "v1" "feat(suspect-notes): add suspect thing"       "2026-03-01T00:00:00+00:00"
commit suspect.py   "v2" "fix(suspect-notes): patch it"                 "2026-03-06T00:00:00+00:00"
commit windowed.py  "v1" "feat(windowed-out-notes): add windowed thing" "2026-04-01T00:00:00+00:00"
commit windowed.py  "v2" "fix(windowed-out-notes): patch late"          "2026-06-30T00:00:00+00:00"
# an UNRELATED fix commit, touching neither clean.py nor any other fixture file -- proves a
# fix() commit never contaminates an unrelated slug's row (mirrors SPEC-132's F-nc-unrelated).
commit unrelated.py "v1" "fix(something-else): unrelated patch"         "2026-02-15T00:00:00+00:00"

export DWARVES_KIT_LOG_DIR="$FIX/kit-runs"             # absent -> skip-safe empty kit_gates
export STATS_GIT_REPO_DIR="$GITREPO"
export STATS_TIDE_DB="$FIX/state.sqlite"          # absent -> skip-safe empty table
export STATS_TGCLEANUP_DIR="$FIX/tg"              # empty -> skip-safe
export STATS_LEARNED_MD="$FIX/learned.md"         # absent -> skip-safe
export STATS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"     # absent -> skip-safe empty sessions
export STATS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"   # absent -> skip-safe empty safety
export STATS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"      # absent -> skip-safe empty memories (repo store)
export STATS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"  # absent -> skip-safe empty memories (builtin store)
export STATS_DB_REMOVED="$FIX/lens.duckdb"
mkdir -p "$STATS_TGCLEANUP_DIR"

R() { uv run stats "$@" 2>&1; }

echo "== I-rebuild: impl_notes + git_fixes materialize from the generated fixtures =="
OUT="$(R rebuild)"
has "I-rebuild impl_notes=7" '"impl_notes": 7' "$OUT"
has "I-rebuild git_fixes=6 (one file per commit, 6 commits)" '"git_fixes": 6' "$OUT"

echo "== I-classify: exact classification per slug (golden fixture, all 4 named classes) =="
DR="$(R deviation-rate --json)"
has "I-classify clean-notes -> CLEAN (the honest-zero NC)" '"slug": "clean-notes",
    "file": "docs/implementation-notes/clean-notes.md",
    "n_deviations": 0,
    "zero_marker": true,
    "first_ts": null,
    "last_ts": null,
    "class": "CLEAN"' "$DR"
has "I-classify suspect-notes -> SUSPECT (a later fix() touches the anchor's own file)" '"slug": "suspect-notes",
    "file": "docs/implementation-notes/suspect-notes.md",
    "n_deviations": 0,
    "zero_marker": true,
    "first_ts": null,
    "last_ts": null,
    "class": "SUSPECT"' "$DR"
has "I-classify windowed-out-notes -> CLEAN at the default 30d window" '"slug": "windowed-out-notes",
    "file": "docs/implementation-notes/windowed-out-notes.md",
    "n_deviations": 0,
    "zero_marker": true,
    "first_ts": null,
    "last_ts": null,
    "class": "CLEAN"' "$DR"
has "I-classify underspecced-notes -> UNDER-SPECCED (4 >= 3), first/last_ts real" '"slug": "underspecced-notes",
    "file": "docs/implementation-notes/underspecced-notes.md",
    "n_deviations": 4,
    "zero_marker": false,
    "first_ts": "2026-05-01 00:00",
    "last_ts": "2026-05-04 00:00",
    "class": "UNDER-SPECCED"' "$DR"
has "I-classify malformed-notes -> counted as entries (n=2), zero_marker forced false, class OTHER" '"slug": "malformed-notes",
    "file": "docs/implementation-notes/malformed-notes.md",
    "n_deviations": 2,
    "zero_marker": false,
    "first_ts": "2026-05-05 00:00",
    "last_ts": "2026-05-06 14:00",
    "class": "OTHER"' "$DR"
has "I-classify legacy-notes -> pre-convention file, n=0 zero_marker=false, class OTHER" '"slug": "legacy-notes",
    "file": "docs/implementation-notes/legacy-notes.md",
    "n_deviations": 0,
    "zero_marker": false,
    "first_ts": null,
    "last_ts": null,
    "class": "OTHER"' "$DR"
has "I-classify multi-same-day -> n_deviations=2 (not deduped), class OTHER" '"slug": "multi-same-day",
    "file": "docs/implementation-notes/multi-same-day.md",
    "n_deviations": 2,
    "zero_marker": false,
    "first_ts": "2026-05-10 00:00",
    "last_ts": "2026-05-10 00:00",
    "class": "OTHER"' "$DR"

echo "== I-window: windowed-out-notes flips CLEAN -> SUSPECT once --window-days widens =="
DR_WIDE="$(R deviation-rate --window-days 150 --json)"
has "I-window --window-days 150 flips windowed-out-notes to SUSPECT (the tunable is real)" '"slug": "windowed-out-notes",
    "file": "docs/implementation-notes/windowed-out-notes.md",
    "n_deviations": 0,
    "zero_marker": true,
    "first_ts": null,
    "last_ts": null,
    "class": "SUSPECT"' "$DR_WIDE"

echo "== I-tunable: --under-specced-min changes the UNDER-SPECCED cutoff =="
DR_LOOSE="$(R deviation-rate --under-specced-min 5 --json)"
has "I-tunable --under-specced-min 5 demotes underspecced-notes (4 < 5) off UNDER-SPECCED" '"slug": "underspecced-notes",
    "file": "docs/implementation-notes/underspecced-notes.md",
    "n_deviations": 4,
    "zero_marker": false,
    "first_ts": "2026-05-01 00:00",
    "last_ts": "2026-05-04 00:00",
    "class": "OTHER"' "$DR_LOOSE"

echo "== F-nc-deliberate-break: prove the file-overlap bridge is load-bearing, not vacuous =="
# Simulate the bug this design guards against: a naive slug+time-only correlation with NO
# file-equality condition would flag ANY zero-marker slug that has ANY later fix() commit at
# all -- including clean-notes, whose anchor (2026-02-01) is followed by the UNRELATED fix
# commit (2026-02-15, within any reasonable window) that never touches clean.py.
BROKEN="$(uv run python3 - <<'PY' 2>&1
from stats import materialize
cols, rows = materialize.query("""
    WITH bridge AS (
        SELECT i.slug, min(g.ts) AS anchor_ts
        FROM impl_notes i
        JOIN git_fixes g ON contains(lower(g.subject), lower(i.slug))
        WHERE i.zero_marker
        GROUP BY i.slug
    )
    SELECT b.slug, count(*) AS any_later_fix
    FROM bridge b
    JOIN git_fixes g ON regexp_matches(g.subject, '^fix(\\(.*\\))?!?:')
        AND CAST(g.ts AS TIMESTAMPTZ) > CAST(b.anchor_ts AS TIMESTAMPTZ)
    GROUP BY b.slug ORDER BY b.slug
""")
import json
print(json.dumps([dict(zip(cols, r)) for r in rows]))
PY
)"
has "F-nc-deliberate-break a file-blind (slug+time only) join WOULD flag clean-notes (the bug the real query avoids)" '"slug": "clean-notes"' "$BROKEN"

echo "== O-plan: over-test pass on read_impl_notes() directly (edge cases beyond the fixture) =="
OVER="$(uv run python3 - <<PY 2>&1
import tempfile
from pathlib import Path
from stats import adapters

results = []

# O1: repo path does not exist at all -> empty columns + empty rows, no exception.
cols, rows = adapters.read_impl_notes(Path("/nonexistent-o1-repo-xyz"))
results.append(("O1-missing-repo", cols == adapters.IMPL_NOTES_COLUMNS and rows == []))

with tempfile.TemporaryDirectory() as td:
    root = Path(td)

    # O2: a real directory with no docs/implementation-notes anywhere -> empty, no crash.
    (root / "some" / "other" / "dir").mkdir(parents=True)
    (root / "some" / "other" / "dir" / "notes.md").write_text("not an impl-note\n")
    cols2, rows2 = adapters.read_impl_notes(root)
    results.append(("O2-no-impl-notes-dir", rows2 == []))

    # O3: an empty impl-notes file -> n_deviations=0, zero_marker=False, no crash.
    d3 = root / "docs" / "implementation-notes"
    d3.mkdir(parents=True)
    (d3 / "empty-file.md").write_text("")
    cols3, rows3 = adapters.read_impl_notes(root)
    row3 = next(r for r in rows3 if r[1] == "empty-file")
    results.append(("O3-empty-file", row3[3] == 0 and row3[4] is False))

    # O4: nested .claude/worktrees/<x> copy of the SAME repo must NOT double-count a file
    # (the real risk confirmed in dwarves-kit at design time: a nested worktree directory
    # duplicates every docs/implementation-notes/*.md file physically on disk).
    (root / ".claude" / "worktrees" / "fake" / "docs" / "implementation-notes").mkdir(parents=True)
    (root / ".claude" / "worktrees" / "fake" / "docs" / "implementation-notes" / "empty-file.md").write_text("")
    cols4, rows4 = adapters.read_impl_notes(root)
    n_empty = sum(1 for r in rows4 if r[1] == "empty-file")
    results.append(("O4-nested-worktree-not-double-counted", n_empty == 1))

for name, passed in results:
    print(f"{name}={'OK' if passed else 'FAIL'}")
PY
)"
has "O1-missing-repo OK (empty columns+rows, no exception)" "O1-missing-repo=OK" "$OVER"
has "O2-no-impl-notes-dir OK (no docs/implementation-notes anywhere -> empty, no crash)" "O2-no-impl-notes-dir=OK" "$OVER"
has "O3-empty-file OK (n_deviations=0, zero_marker=False, no crash)" "O3-empty-file=OK" "$OVER"
has "O4-nested-worktree-not-double-counted OK (hidden-dir pruning works)" "O4-nested-worktree-not-double-counted=OK" "$OVER"

echo "== O-malformed: the malformed-file stderr warning is actually logged (not silently eaten) =="
WARN="$(uv run python3 -c "
from pathlib import Path
from stats import adapters
adapters.read_impl_notes(Path('$GITREPO'))
" 2>&1 >/dev/null)"
has "O-malformed stderr warning names the malformed file" "malformed impl-notes file" "$WARN"
has "O-malformed stderr warning names malformed-notes.md specifically" "malformed-notes.md" "$WARN"

echo "== I-remat: delete-and-rematerialize is byte-identical (fixture files canonical) =="
# stdout only (not 2>&1): a lazy rebuild re-parses malformed-notes.md and logs its stderr
# warning again, which would spuriously differ from the BEFORE capture if merged in.
BEFORE="$(uv run stats show impl_notes --json 2>/dev/null)"
rm -f "$STATS_DB_REMOVED" "$STATS_DB_REMOVED.wal"
AFTER="$(uv run stats show impl_notes --json 2>/dev/null)"
if [ "$BEFORE" = "$AFTER" ] && [ -n "$BEFORE" ]; then ok "I-remat identical output"; else bad "I-remat output differs after delete+rebuild"; fi

echo "== I-nc: read-only negative control (fixture files never mutated) =="
BEFORE_SHA="$(find "$GITREPO/docs/implementation-notes" -type f -exec shasum -a 256 {} \; | sort)"
R query "SELECT count(*) FROM impl_notes" >/dev/null
AFTER_SHA="$(find "$GITREPO/docs/implementation-notes" -type f -exec shasum -a 256 {} \; | sort)"
if [ "$BEFORE_SHA" = "$AFTER_SHA" ]; then ok "I-nc fixture impl-notes files byte-identical after rebuild+queries"; else bad "I-nc a fixture file changed"; fi

# =============================================================================================
# unknown-density anomaly: a SEPARATE, isolated pair of fixtures (density is a whole-table
# aggregate; keeping it independent of the classification fixture above avoids entangling two
# unrelated assertions in one shared db).
# =============================================================================================

ADENSE="$FIX/adense"
ASPARSE="$FIX/asparse"
mkdir -p "$ADENSE/docs/implementation-notes" "$ASPARSE/docs/implementation-notes"

mkentries() {  # mkentries <dir> <slug> <n>
  local dir="$1" slug="$2" n="$3" f i
  f="$dir/docs/implementation-notes/$slug.md"
  i=1
  : > "$f"
  echo "# Implementation notes $slug" >> "$f"
  echo >> "$f"
  while [ "$i" -le "$n" ]; do
    printf '## 2026-05-%02d Deviation %d\nContext/Decision/Why/Alternatives/Impact.\n\n' "$i" "$i" >> "$f"
    i=$((i + 1))
  done
}
mkzero() {  # mkzero <dir> <slug>
  local dir="$1" slug="$2" f
  f="$dir/docs/implementation-notes/$slug.md"
  {
    echo "# Implementation notes $slug"
    echo
    echo "No deviations; matches SPEC-$slug verbatim."
  } > "$f"
}

for i in 1 2 3 4 5; do mkentries "$ADENSE" "dense-$i" 4; done
for i in 1 2 3 4 5; do mkzero "$ASPARSE" "sparse-$i"; done

export DWARVES_KIT_LOG_DIR="$FIX/kit-runs-empty"
export STATS_TIDE_DB="$FIX/state-empty.sqlite"
export STATS_TGCLEANUP_DIR="$FIX/tg-empty"
export STATS_LEARNED_MD="$FIX/learned-empty.md"
mkdir -p "$STATS_TGCLEANUP_DIR"

CC_BACKLOG_BACKLOG_FIX="$FIX/BACKLOG.md"
{
  echo "# Backlog"
  echo "| ID | Item | Notes & source | Status |"
  echo "|---|---|---|---|"
} > "$CC_BACKLOG_BACKLOG_FIX"
export CC_BACKLOG_BACKLOG="$CC_BACKLOG_BACKLOG_FIX"

staged_n() { [ -f "$CC_BACKLOG_STAGING" ] && grep -c '^## \[staged\]' "$CC_BACKLOG_STAGING" || echo 0; }

echo "== A-dense: rolling median n_deviations over threshold stages ONE unknown-density proposal =="
export STATS_GIT_REPO_DIR="$ADENSE"
export STATS_DB_REMOVED="$FIX/lens-adense.duckdb"
export CC_BACKLOG_STAGING="$FIX/staging-adense.md"
R rebuild >/dev/null
PROPOSE_OUT="$(R anomalies --propose --json)"
has "A-dense unknown_density staged" '"key": "unknown_density",
    "title": "Feedback: implementation-notes deviation density over threshold",
    "action": "staged"' "$PROPOSE_OUT"
N_STAGED="$(staged_n)"
if [ "$N_STAGED" -eq 1 ]; then ok "A-dense exactly ONE proposal staged"; else bad "A-dense want 1 staged, got $N_STAGED"; fi

echo "== A-sparse: below-threshold density stages NOTHING =="
export STATS_GIT_REPO_DIR="$ASPARSE"
export STATS_DB_REMOVED="$FIX/lens-asparse.duckdb"
export CC_BACKLOG_STAGING="$FIX/staging-asparse.md"
R rebuild >/dev/null
PROPOSE_OUT2="$(R anomalies --propose --json)"
hasnt "A-sparse unknown_density NOT fired" '"key": "unknown_density"' "$PROPOSE_OUT2"
N_STAGED2="$(staged_n)"
if [ "$N_STAGED2" -eq 0 ]; then ok "A-sparse nothing staged"; else bad "A-sparse want 0 staged, got $N_STAGED2"; fi

echo "== A-dedup: --propose twice on the same dense state stages ONCE (idempotent) =="
export STATS_GIT_REPO_DIR="$ADENSE"
export STATS_DB_REMOVED="$FIX/lens-adense.duckdb"
export CC_BACKLOG_STAGING="$FIX/staging-adense.md"
PROPOSE_OUT3="$(R anomalies --propose --json)"
N_STAGED3="$(staged_n)"
if [ "$N_STAGED3" -eq 1 ]; then ok "A-dedup re-propose does not duplicate"; else bad "A-dedup want 1 staged after re-propose, got $N_STAGED3"; fi

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
