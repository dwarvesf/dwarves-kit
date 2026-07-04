#!/usr/bin/env bash
# Golden-fixture + over-test + NEVER-DELETE NC for `memory_lens`/`memories`/`ledger
# memory-sweep`/`_detect_memory_hygiene` (SPEC-136 test plan).
#
# Two fixture stores, generated at test-time in $(mktemp -d):
#   - a REAL git repo (the 'repo' store, `LEDGER_OBS_MEMORY_REPO_DIR`) with controlled commit
#     dates, same precedent as test-defect-correlation.sh/test-sessions-digest.sh's own
#     generated-git-repo fixtures.
#   - a plain (non-git) directory tree (the 'builtin' store,
#     `LEDGER_OBS_MEMORY_PROJECTS_ROOT`), one `<project-slug>/memory/` subdir, mtime-backdated
#     for the staleness-via-mtime-fallback case.
#
# The NEVER-DELETE NC (N-nc) is load-bearing and ABSOLUTE (Han's own never-delete rule): every
# memory file's sha256 across BOTH fixture stores must be byte-identical before and after
# running memory-sweep + rebuild + show memories + anomalies. N-nc-deliberate-break proves the
# shasum comparison itself is falsifiable (a real mutation flips it), not vacuous.
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
PROJROOT="$FIX/projects"

# ---- build the repo store: a real git repo, .claude/memory/ notes + index -------------------
mkdir -p "$GITREPO/.claude/memory" "$GITREPO/docs"
git -C "$GITREPO" init -q -b main --template=
git -C "$GITREPO" config user.name "Fixture Bot"
git -C "$GITREPO" config user.email "fixture@example.com"
git -C "$GITREPO" config commit.gpgsign false

commit_now() {
  # commit_now <subject> -- stages everything currently written, commits at the REAL current
  # time (no backdate): correct regardless of which real day this test runs.
  git -C "$GITREPO" add -A >/dev/null
  git -C "$GITREPO" commit -q -m "$1" >/dev/null
}

# the LIVE target for live-path-note.md's reference
printf 'a real file, referenced by live-path-note.md\n' > "$GITREPO/docs/real-file.md"

cat > "$GITREPO/.claude/memory/dead-path-note.md" <<'EOF'
---
name: dead-path-note
---

See `/tmp/nonexistent-xyz-321-should-not-exist.txt` for background (this path does not exist
on this host; `/tmp/` is a recognized real filesystem root, so it IS live-tested).
EOF

cat > "$GITREPO/.claude/memory/live-path-note.md" <<EOF
---
name: live-path-note
---

See \`$GITREPO/docs/real-file.md\` for background (an absolute path under a recognized real
filesystem root -- \`docs/real-file.md\` alone, a bare relative path, is NOT tested in v1,
see builtin-relative-skip-note.md for that case).
EOF

cat > "$GITREPO/.claude/memory/flag-fence-note.md" <<'EOF'
---
name: flag-fence-note
---

Run it with `--dry-run` first to preview; a flag alone in a code span must never crash the
sweep or be mistested as a path.
EOF

cat > "$GITREPO/.claude/memory/prose-path-note.md" <<'EOF'
---
name: prose-path-note
---

This note mentions tools/nonexistent-thing/README.md in plain prose (no backticks), which must
never be extracted as a reference.
EOF

cat > "$GITREPO/.claude/memory/repo-relative-skip-note.md" <<'EOF'
---
name: repo-relative-skip-note
---

See `tools/hermes/does-not-exist-here.sh` in code-span form; v1 does not test ANY bare
relative path (not even in the repo store, which has a known root) -- a real-corpus finding
that even repo-store notes routinely reference OTHER projects' source trees, so "resolve
against this repo's root" is not a safe assumption. Must be SKIPPED, not flagged dead.
EOF

cat > "$GITREPO/.claude/memory/unresolvable-tilde-user-note.md" <<'EOF'
---
name: unresolvable-tilde-user-note
---

See `~nonexistent-fixture-user-xyz/some/path` for background; a `~<username>` for a username
that does not resolve on this host must be flagged dead (not crash the whole sweep with a
RuntimeError, a real bug found via the first real-corpus run against `~server/...`-shaped
notes).
EOF

cat > "$GITREPO/.claude/memory/MEMORY.md" <<'EOF'
# fixture memory index

- [Live path note](live-path-note.md), points at a real file, must not be flagged dead.
- [Missing note reference](missing-note.md), points at a note that was never created, must be
  flagged dead.
- MIGRATED to repo memory: this tombstone bullet has no link and must be flagged as an orphan
  index entry.
EOF

commit_now "feat(fixture): repo store notes (current, not stale)"

# old-note.md: committed far in the past (2020, safely >180d before any plausible test-run
# date) -- proves the staleness signal via the git-commit path.
cat > "$GITREPO/.claude/memory/old-note.md" <<'EOF'
---
name: old-note
---

This note has no path/command references; it exists only to test the staleness (written date)
signal.
EOF
GIT_AUTHOR_DATE="2020-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00+00:00" \
  git -C "$GITREPO" add "$GITREPO/.claude/memory/old-note.md" >/dev/null
GIT_AUTHOR_DATE="2020-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00+00:00" \
  git -C "$GITREPO" commit -q -m "feat(fixture): old-note, backdated 2020" >/dev/null

# ---- build the builtin store: plain (non-git) directory tree --------------------------------
mkdir -p "$PROJROOT/-fixture-project/memory"
printf 'anchor content\n' > "$FIX/anchor-file.txt"

cat > "$PROJROOT/-fixture-project/memory/builtin-abs-note.md" <<EOF
---
name: builtin-abs-note
---

See \`$FIX/anchor-file.txt\` for the live absolute reference used in this fixture.
EOF

cat > "$PROJROOT/-fixture-project/memory/builtin-relative-skip-note.md" <<'EOF'
---
name: builtin-relative-skip-note
---

See `tools/hermes/does-not-exist-here.sh` in code-span form; a bare relative path is never
tested in v1 (see repo-relative-skip-note.md for the same rule in the OTHER store), so this
must be SKIPPED (not verified, not flagged dead).
EOF

cat > "$PROJROOT/-fixture-project/memory/builtin-stale-note.md" <<'EOF'
---
name: builtin-stale-note
---

Trivial content, no refs; this file's mtime is backdated to test the mtime-fallback staleness
path (the builtin store is not version controlled).
EOF
touch -t 202001010000 "$PROJROOT/-fixture-project/memory/builtin-stale-note.md"

cat > "$PROJROOT/-fixture-project/memory/MEMORY.md" <<'EOF'
- MIGRATED to repo memory: the fixture tombstone note now lives elsewhere (no link, orphan).
- [Builtin abs note](builtin-abs-note.md), points at a real sibling file, must not be flagged
  dead.
EOF

# a SECOND builtin store whose MEMORY.md is a free-PROSE scratchpad (zero markdown-link
# bullets) -- the IS-IT-AN-INDEX gate (DEC-010) must flag NONE of its bullets, or every
# prose-style MEMORY.md (e.g. the real claude-guardrails one, 39 prose bullets) floods the
# sweep with false orphans.
mkdir -p "$PROJROOT/-prose-project/memory"
cat > "$PROJROOT/-prose-project/memory/MEMORY.md" <<'EOF'
# free-prose scratchpad, NOT a link index

## Project state (some date)
- shipped v1.2, tagged, published to the registry
- maintainer list: alice + bob, either can publish
- scope rename considered and reverted (see PR discussion)
EOF

# ---- env: point the tool at these fixtures; isolate every OTHER source, per the HANDOFF
#      cross-suite-pollution lesson (a real host source must never leak into this suite) -----
export DWARVES_KIT_LOG_DIR="$FIX/nonexistent-kit-logs"
export LEDGER_OBS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"
export LEDGER_OBS_TIDE_DB="$FIX/nonexistent-tide.sqlite"
export LEDGER_OBS_TGCLEANUP_DIR="$FIX/nonexistent-tg"
export LEDGER_OBS_LEARNED_MD="$FIX/nonexistent-learned.md"
export LEDGER_OBS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"
export LEDGER_OBS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"
export LEDGER_OBS_MEMORY_REPO_DIR="$GITREPO"
export LEDGER_OBS_MEMORY_PROJECTS_ROOT="$PROJROOT"
export LEDGER_OBSERVATORY_DB="$FIX/lens.duckdb"
export CC_BACKLOG_STAGING="$FIX/backlog-staging.md"
export CC_BACKLOG_BACKLOG="$FIX/BACKLOG.md"

R() { uv run ledger "$@" 2>&1; }

ALL_MEM_FILES() { find "$GITREPO/.claude/memory" "$PROJROOT" -type f | sort; }

echo "== M-fixtures: exact dead_ref_count/stale per unit, via memory_lens.scan() directly =="
GITREPO="$GITREPO" PROJROOT="$PROJROOT" uv run python3 - > "$FIX/scan.out" 2>&1 <<'PY'
import os
from pathlib import Path
from ledger_observatory import memory_lens as ml

units = ml.scan(Path(os.environ["GITREPO"]), Path(os.environ["PROJROOT"]))
by_key = {(u.store, u.slug): u for u in units}
print(f"TOTAL={len(units)}")
for (store, slug), u in sorted(by_key.items()):
    print(f"{store}|{slug}|{u.kind}|dead={u.dead_ref_count}|stale={ml.is_stale(u.written)}")
PY
SCAN_OUT="$(cat "$FIX/scan.out")"
echo "$SCAN_OUT"

has "M-total 13 units (8 repo + 4 builtin + 1 prose-store MEMORY.md)" "TOTAL=13" "$SCAN_OUT"
has "M-dead-path-note dead=1, not stale" "|dead-path-note|note|dead=1|stale=False" "$SCAN_OUT"
has "M-live-path-note dead=0 (absolute path under a real root, live)" "|live-path-note|note|dead=0|stale=False" "$SCAN_OUT"
has "M-old-note dead=0, STALE=True (git-commit path)" "|old-note|note|dead=0|stale=True" "$SCAN_OUT"
has "M-flag-fence-note dead=0 (flag skipped, no crash)" "|flag-fence-note|note|dead=0|stale=False" "$SCAN_OUT"
has "M-prose-path-note dead=0 (no backticks, not extracted)" "|prose-path-note|note|dead=0|stale=False" "$SCAN_OUT"
has "M-repo-relative-skip-note dead=0 (bare relative path SKIPPED, repo store)" "|repo-relative-skip-note|note|dead=0|stale=False" "$SCAN_OUT"
has "M-unresolvable-tilde-user-note dead=2 (two unresolvable ~user refs, RuntimeError caught, flagged dead, no crash)" "|unresolvable-tilde-user-note|note|dead=2|stale=False" "$SCAN_OUT"
REPO_NAME="$(basename "$GITREPO")"
has "M-repo MEMORY.md dead=2 (missing-note link + orphan tombstone)" "repo:${REPO_NAME}|MEMORY|index|dead=2" "$SCAN_OUT"
has "M-builtin-abs-note dead=0 (absolute path under a real root, live)" "|builtin-abs-note|note|dead=0|stale=False" "$SCAN_OUT"
has "M-builtin-relative-skip-note dead=0 (bare relative path SKIPPED, builtin store)" "|builtin-relative-skip-note|note|dead=0|stale=False" "$SCAN_OUT"
has "M-builtin-stale-note dead=0, STALE=True (mtime-fallback path)" "|builtin-stale-note|note|dead=0|stale=True" "$SCAN_OUT"
has "M-builtin MEMORY.md dead=1 (orphan tombstone only)" "builtin:-fixture-project|MEMORY|index|dead=1" "$SCAN_OUT"
has "M-prose MEMORY.md dead=0 (prose scratchpad, IS-IT-AN-INDEX gate, DEC-010)" "builtin:-prose-project|MEMORY|index|dead=0" "$SCAN_OUT"

echo
echo "== M-cli: ledger memory-sweep --json surfaces the same findings =="
SWEEP="$(R memory-sweep --json)"
has "M-cli dead-path-note carries its dead ref token" '"slug": "dead-path-note",
    "kind": "note",' "$SWEEP"
has "M-cli dead_refs lists the extracted path" "path:/tmp/nonexistent-xyz-321-should-not-exist.txt" "$SWEEP"
has "M-cli orphan index entries surface as index-link" "index-link:(no linked file)" "$SWEEP"

echo
echo "== M-lens: ledger rebuild + ledger show memories materializes the compact 5-column table =="
REBUILD_OUT="$(R rebuild)"
has "M-lens memories=13 in rebuild counts" '"memories": 13' "$REBUILD_OUT"
SHOW_OUT="$(R show memories --json)"
has "M-lens show memories has store/slug/written/last_verified/dead_ref_count columns" '"store":' "$SHOW_OUT"
has "M-lens show memories dead-path-note row present" '"slug": "dead-path-note",' "$SHOW_OUT"
N_ROWS="$(printf '%s' "$SHOW_OUT" | grep -c '"slug":' || true)"
if [ "$N_ROWS" -eq 13 ]; then ok "M-lens exactly 13 rows in memories table"; else bad "M-lens want 13 rows, got $N_ROWS"; fi

echo
echo "== M-anomaly: _detect_memory_hygiene fires (fixture dead-ref rate over the 15% threshold + min-sample) =="
ANOM_OUT="$(R anomalies --json)"
has "M-anomaly memory_hygiene fires" '"key": "memory_hygiene"' "$ANOM_OUT"
has "M-anomaly --help lists both new threshold keys" "memory_min_notes" "$(R anomalies --help)"
has "M-anomaly --help lists rate threshold key" "memory_dead_ref_rate_max" "$(R anomalies --help)"

echo
echo "== M-propose: --propose stages memory_hygiene into the cc-backlog staging buffer =="
PROPOSE_OUT="$(R anomalies --propose --json)"
has "M-propose memory_hygiene staged" '"key": "memory_hygiene",
    "title": "Feedback: memory dead-reference rate over threshold",
    "action": "staged"' "$PROPOSE_OUT"
STAGED_FILE="$(cat "$CC_BACKLOG_STAGING" 2>/dev/null || true)"
has "M-propose staged block lands in the cc-backlog buffer" "## [staged] Feedback: memory dead-reference rate over threshold" "$STAGED_FILE"
DEDUP_OUT="$(R anomalies --propose --json)"
has "M-propose re-run marks duplicate (idempotent)" '"action": "duplicate"' "$DEDUP_OUT"

echo
echo "== N-nc: NEVER-DELETE negative control (load-bearing, absolute) =="
BEFORE_SHA="$(ALL_MEM_FILES | xargs shasum -a 256 | sort)"
R memory-sweep >/dev/null
R rebuild >/dev/null
R show memories >/dev/null
R anomalies >/dev/null
R anomalies --propose >/dev/null
AFTER_SHA="$(ALL_MEM_FILES | xargs shasum -a 256 | sort)"
if [ "$BEFORE_SHA" = "$AFTER_SHA" ]; then
  ok "N-nc every memory file byte-identical after memory-sweep+rebuild+show+anomalies+propose"
else
  bad "N-nc a memory file changed across the sweep/rebuild/anomaly run"
fi

echo
echo "== N-nc-deliberate-break: prove the shasum comparison is falsifiable, not vacuous =="
TARGET="$GITREPO/.claude/memory/dead-path-note.md"
ORIG_SHA="$(shasum -a 256 "$TARGET")"
printf '\nDELIBERATE BREAK: simulating a write this tool must never perform\n' >> "$TARGET"
MUTATED_SHA="$(shasum -a 256 "$TARGET")"
if [ "$ORIG_SHA" != "$MUTATED_SHA" ]; then
  ok "N-nc-deliberate-break the SAME comparison mechanism DOES catch a real mutation (red on a genuine change)"
else
  bad "N-nc-deliberate-break mutation did not change the shasum (test itself is broken)"
fi
git -C "$GITREPO" checkout -q -- .claude/memory/dead-path-note.md
RESTORED_SHA="$(shasum -a 256 "$TARGET")"
if [ "$RESTORED_SHA" = "$ORIG_SHA" ]; then
  ok "N-nc-deliberate-break fixture restored to its original committed content"
else
  bad "N-nc-deliberate-break restore failed"
fi

echo
echo "== O-plan: over-test edge cases beyond the golden fixture =="
OVER="$(uv run python3 - <<'PY' 2>&1
from pathlib import Path
from ledger_observatory import memory_lens as ml

results = []

# O1: missing repo/projects roots -> empty list, no exception.
units = ml.scan(Path("/nonexistent-o1-repo-xyz"), Path("/nonexistent-o1-projects-xyz"))
results.append(("O1-missing-roots", units == []))

# O2: a file that fails to decode (non-UTF-8 bytes) is treated as empty text, never raises.
import tempfile
with tempfile.TemporaryDirectory() as td:
    tdp = Path(td)
    (tdp / ".claude").mkdir()
    (tdp / ".claude" / "memory").mkdir()
    bad_file = tdp / ".claude" / "memory" / "bad-encoding.md"
    bad_file.write_bytes(b"\xff\xfe not valid utf-8 \x80\x81")
    units2 = ml.scan(tdp, Path("/nonexistent-o2-projects-xyz"))
    ok2 = len(units2) == 1 and units2[0].slug == "bad-encoding" and units2[0].dead_ref_count == 0
    results.append(("O2-undecodable-file-no-crash", ok2))

# O3: a URL-shaped code span (op://...) is never tested (the :// URL guard).
refs = ml.extract_refs("see `op://Toolkit/xyz/credential` for the token")
results.append(("O3-url-shaped-skipped", refs == []))

# O4: a bare word (a prose noun in backticks, e.g. `README.md`, `main`, `parents`) is NEVER
# tested in v1 -- the real-corpus precision fix (DEC-008). This is THE load-bearing
# conservative-extraction rule; a regression to command-testing would light up dozens of
# false dead-refs on the live stores.
refs4 = ml.extract_refs("run `README.md` and check `main` and `parents`")
results.append(("O4-bare-word-not-tested", refs4 == []))

# O5: a Claude Code slash-command / REST path fragment (leading / but NOT under a real
# filesystem root) is NOT tested (DEC-009: the dominant leading-/ false-positive source).
refs5 = ml.extract_refs("run `/kit:spec` then hit `/v1/chat/completions`")
results.append(("O5-slashcommand-not-tested", refs5 == []))

# O6: a real-root absolute path IS classified + tested (the positive control for the
# _REAL_PATH_PREFIXES allowlist -- /etc/ exists, /etc/nonexistent-xyz-zzz does not).
refs6 = ml.extract_refs("edit `/etc/hosts` and `/etc/nonexistent-xyz-zzz-321`")
by_tok = {r.token: r.live for r in refs6}
ok6 = (by_tok.get("/etc/hosts") is True
       and by_tok.get("/etc/nonexistent-xyz-zzz-321") is False
       and len(refs6) == 2)
results.append(("O6-real-root-path-tested", ok6))

# O7: a template placeholder / glob shape is never a literal path, even under a real root.
refs7 = ml.extract_refs("see `/Users/<name>/x` and `/etc/*.conf` and `~/x/{a,b}`")
results.append(("O7-placeholder-glob-skipped", refs7 == []))

# O8: the IS-IT-AN-INDEX gate (DEC-010) -- a MEMORY.md with zero link bullets flags nothing;
# ONE real link bullet turns a sibling no-link bullet into a genuine orphan.
import tempfile as _tf
with _tf.TemporaryDirectory() as td2:
    d = Path(td2)
    prose = "# scratchpad\n- shipped v1\n- maintainers: a + b\n- no links here at all\n"
    idx = "- [real](note.md) a real link\n- MIGRATED: tombstone, no link\n"
    refs_prose = ml._extract_index_refs(prose, d)
    refs_idx = ml._extract_index_refs(idx, d)
    n_dead_prose = sum(1 for r in refs_prose if not r.live)
    n_dead_idx = sum(1 for r in refs_idx if not r.live)
    results.append(("O8-prose-scratchpad-flags-nothing", refs_prose == []))
    results.append(("O8-real-index-flags-orphan", n_dead_idx == 2))  # tombstone + missing note.md

for name, passed in results:
    print(f"{name}={'OK' if passed else 'FAIL'}")
PY
)"
has "O1-missing-roots OK (empty list, no exception)" "O1-missing-roots=OK" "$OVER"
has "O2-undecodable-file-no-crash OK (empty refs, unit still produced)" "O2-undecodable-file-no-crash=OK" "$OVER"
has "O3-url-shaped-skipped OK (:// URL guard, never tested)" "O3-url-shaped-skipped=OK" "$OVER"
has "O4-bare-word-not-tested OK (the load-bearing precision rule, DEC-008)" "O4-bare-word-not-tested=OK" "$OVER"
has "O5-slashcommand-not-tested OK (leading / but no real root, DEC-009)" "O5-slashcommand-not-tested=OK" "$OVER"
has "O6-real-root-path-tested OK (positive control: /etc/hosts live, bogus dead)" "O6-real-root-path-tested=OK" "$OVER"
has "O7-placeholder-glob-skipped OK (<name>/*.conf/{a,b} never a literal path)" "O7-placeholder-glob-skipped=OK" "$OVER"
has "O8-prose-scratchpad-flags-nothing OK (no-link MEMORY.md flags 0, DEC-010)" "O8-prose-scratchpad-flags-nothing=OK" "$OVER"
has "O8-real-index-flags-orphan OK (a real link index still flags its orphan + missing link)" "O8-real-index-flags-orphan=OK" "$OVER"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
