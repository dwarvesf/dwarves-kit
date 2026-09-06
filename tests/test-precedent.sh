#!/usr/bin/env bash
# test-precedent.sh -- SPEC-245 (precedent-inventory TASK-002): records-surface tests for
# `bin/precedent` / `lib/precedent/precedent.sh`, plus the shared fixture the TASK-003
# inventory-surface cases will reuse.
#
# Proves, records-only (green at e07bc30, before lib/precedent/inventory.py exists):
#   AC1 `find --surface records` byte-parity with the pre-move `lib/precedent.sh` (TASK-001)
#   AC2 a stopword-only query prints the no-keywords line, exit 0
#   AC3 an out-of-range positional [max] exits 64
#   AC4 an unknown --surface exits 64
#   AC5 default surface (`all`) with inventory.py absent ends on the 0-inventory summary line
#   AC6 --help exits 0 and documents --surface
#
# Run: bash tests/test-precedent.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRECEDENT_BIN="$KIT_DIR/bin/precedent"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}

TMPDIR_T="$(mktemp -d "${TMPDIR:-/tmp}/dk-precedent-test.XXXXXX")"
TMPDIR_T="$(cd "$TMPDIR_T" && pwd)"   # normalize a double slash, same reason as test-board.sh
trap 'rm -rf "$TMPDIR_T"' EXIT

# ---------------------------------------------------------------------------
# Fixture builder, reusable by TASK-003. Lays down a real git repo covering both surfaces
# (records: docs/specs + docs/decisions; inventory: tools/scripts/memory/skills/FEATURES/
# experiments) plus a registry file whose `scripts`/`crons`/`memory` rows point at three more
# dirs, one missing path, and one `~`-relative path. Every path is exported so a later case
# (this file's own, or a TASK-003 addition) can reach it without rebuilding.
#
# The `.claude/memory/gamma.md` fixture body carries a fake GitHub-token-shaped string (the
# TASK-003 redaction case scans for it). Assembled from two halves at fixture-build time, each
# well under the pattern's 36-char threshold on its own, so the token never appears contiguous
# in this script's own source.
# ---------------------------------------------------------------------------
make_fixture() {
  FIX_HOME="$TMPDIR_T/home"
  FIX_REPO="$TMPDIR_T/repo"
  FIX_SCRIPTS="$TMPDIR_T/scripts"
  FIX_CRONS="$TMPDIR_T/crons"
  FIX_MEMORY="$TMPDIR_T/memory"
  FIX_LEDGER="$TMPDIR_T/ledger"
  FIX_REGISTRY="$TMPDIR_T/registry.txt"
  export FIX_HOME FIX_REPO FIX_SCRIPTS FIX_CRONS FIX_MEMORY FIX_LEDGER FIX_REGISTRY

  mkdir -p "$FIX_HOME/eta-repo/scripts" "$FIX_LEDGER"
  mkdir -p "$FIX_REPO/tools/alpha/bin" "$FIX_REPO/scripts" "$FIX_REPO/.claude/memory" \
           "$FIX_REPO/.claude/skills/delta" "$FIX_REPO/docs/specs" "$FIX_REPO/docs/decisions" \
           "$FIX_REPO/experiments/eps"

  cat > "$FIX_REPO/tools/alpha/tool.toml" <<'FIX'
name = "alpha"
description = "notion sync for the payroll desk"
systems = ["notion"]
FIX

  cat > "$FIX_REPO/tools/alpha/bin/alpha-run" <<'FIX'
#!/usr/bin/env bash
# alpha-run: pushes notion rows
FIX
  chmod +x "$FIX_REPO/tools/alpha/bin/alpha-run"

  cat > "$FIX_REPO/scripts/beta.sh" <<'FIX'
#!/usr/bin/env bash
# beta: backup the ledger
FIX

  local fake_token_a="ghp_abcdefghij" fake_token_b="klmnopqrstuvwxyz0123456789"
  cat > "$FIX_REPO/.claude/memory/gamma.md" <<FIX
---
description: notion token rotation
---
# gamma

Rotate the token after a leak. Sample shape: ${fake_token_a}${fake_token_b}
FIX

  cat > "$FIX_REPO/.claude/skills/delta/SKILL.md" <<'FIX'
---
name: delta
description: sync notion pages
---
Body mentions the payroll desk this skill supports.
FIX

  cat > "$FIX_REPO/docs/FEATURES.md" <<'FIX'
# Features

| Command | Icon | Trigger | Description | Since | Owner |
|---|---|---|---|---|---|
| `epsilon.sh` | `[E]` | SessionEnd | stages notion rows | - | - |
FIX

  cat > "$FIX_REPO/experiments/eps/README.md" <<'FIX'
---
title: notion export experiment
---
# notion export experiment
FIX

  cat > "$FIX_REPO/docs/specs/SPEC-001-notion-sync.md" <<'FIX'
# Spec: notion sync
FIX

  cat > "$FIX_REPO/docs/decisions/0001-notion.md" <<'FIX'
# ADR: notion
FIX

  git -C "$FIX_REPO" init -q
  git -C "$FIX_REPO" config user.email t@t
  git -C "$FIX_REPO" config user.name t
  git -C "$FIX_REPO" add -A
  git -C "$FIX_REPO" commit -qm init

  # registry-only sources (TASK-003 inventory rows; not scanned until inventory.py lands)
  mkdir -p "$FIX_SCRIPTS" "$FIX_CRONS/sub" "$FIX_MEMORY"
  cat > "$FIX_SCRIPTS/zeta.sh" <<'FIX'
#!/usr/bin/env bash
# zeta: rotate notion keys
FIX

  cat > "$FIX_CRONS/sub/wrangler.jsonc" <<'FIX'
{"name":"notion-cron","triggers":{"crons":["0 * * * *","30 2 * * *"]}}
FIX

  cat > "$FIX_MEMORY/theta.md" <<'FIX'
# theta

A memory note with no notion mention, used only by the TASK-003 iterator tests.
FIX

  # ~-expansion case (TASK-003): a second `repo` registry row under $HOME, distinct from
  # $FIX_REPO. "zorbington" is a unique word this row's own scripts/ dir carries, so a hit
  # here proves the `~` row actually got scanned.
  cat > "$FIX_HOME/eta-repo/scripts/eta.sh" <<'FIX'
#!/usr/bin/env bash
# eta: zorbington rotation helper
FIX

  cat > "$FIX_REGISTRY" <<FIX
repo $FIX_REPO
scripts $FIX_SCRIPTS
crons $FIX_CRONS
memory $FIX_MEMORY
repo /nonexistent/path/for/test
repo ~/eta-repo
# comment
FIX
}

make_fixture

# Every invocation below runs isolated from the real machine: a scratch HOME, a scratch
# ledger root, the fixture registry, REPO_ROOT pinned to the fixture repo, `bin/precedent`
# invoked by absolute path.
export HOME="$FIX_HOME"
export KIT_LEDGER_DIR="$FIX_LEDGER"
export PRECEDENT_REGISTRY="$FIX_REGISTRY"
export REPO_ROOT="$FIX_REPO"

# ---------------------------------------------------------------------------
# AC1: records-surface parity against the pre-move script (SPEC-245 TASK-001 acceptance).
# The old script resolves ROOT via `git rev-parse --show-toplevel` only (no REPO_ROOT
# support), so both calls run with REPO_ROOT unset and cwd = the fixture repo.
# ---------------------------------------------------------------------------
OLD_SCRIPT="$KIT_DIR/lib/precedent-old.sh"
git -C "$KIT_DIR" show e7f5fee:lib/precedent.sh > "$OLD_SCRIPT"

NEW_OUT="$(cd "$FIX_REPO" && env -u REPO_ROOT "$PRECEDENT_BIN" find "notion sync" --surface records 2>&1)"
OLD_OUT="$(cd "$FIX_REPO" && env -u REPO_ROOT bash "$OLD_SCRIPT" find "notion sync" 2>&1)"
PARITY_DIFF="$(command diff <(printf '%s\n' "$NEW_OUT") <(printf '%s\n' "$OLD_OUT") 2>&1)"
if [ -z "$PARITY_DIFF" ]; then assert "records surface byte-parity with the pre-move script" 0
else
  assert "records surface byte-parity with the pre-move script" 1
  printf '%s\n' "$PARITY_DIFF" | head -20 | sed 's/^/      /'
fi
mv "$OLD_SCRIPT" "$TMPDIR_T/precedent-old.sh"   # never leave the extracted copy in the tree

# ---------------------------------------------------------------------------
# AC2: stopword-only query
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find "the and for" --surface records 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "(no searchable keywords in the description)" ]; then
  assert "stopword-only query prints the no-keywords line, exit 0" 0
else
  assert "stopword-only query prints the no-keywords line, exit 0" 1
  echo "rc=$RC out=$OUT" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# AC3: out-of-range positional [max]
# ---------------------------------------------------------------------------
"$PRECEDENT_BIN" find "notion" abc --surface records >/dev/null 2>&1
assert "a non-numeric positional [max] exits 64" "$([ $? -eq 64 ]; echo $?)"

# ---------------------------------------------------------------------------
# AC4: unknown --surface
# ---------------------------------------------------------------------------
"$PRECEDENT_BIN" find notion --surface bogus >/dev/null 2>&1
assert "an unknown --surface exits 64" "$([ $? -eq 64 ]; echo $?)"

# ---------------------------------------------------------------------------
# AC5: default surface (all), inventory.py absent at this HEAD
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find "notion sync" 2>&1)"; RC=$?
LAST_LINE="$(printf '%s\n' "$OUT" | tail -n1)"
if [ "$RC" -eq 0 ] && printf '%s' "$LAST_LINE" | grep -qE '^precedent: [0-9]+ record matches, 0 inventory hits in 0 sections; top: -$'; then
  assert "default (all) surface ends on the 0-inventory summary line" 0
else
  assert "default (all) surface ends on the 0-inventory summary line" 1
  echo "rc=$RC last=$LAST_LINE" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# AC6: --help
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" --help 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q -- '--surface'; then
  assert "--help exits 0 and documents --surface" 0
else
  assert "--help exits 0 and documents --surface" 1
fi

# TASK-003 cases land here (inventory surface: AND semantics, name-over-body ranking,
# adjacent-phrase bonus, registry skip note, ~ expansion, secret redaction, --json keys,
# --quiet collapse, --explain, precedent.log line, exit 64 on a bogus registry kind).

# ---------------------------------------------------------------------------
# TASK-003 AC1: AND semantics -- a two-term query where one term is absent scores 0
# everywhere, so nothing_matched is true.
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find "notion zzzqqq" --surface inventory --json 2>&1)"; RC=$?
NOTHING="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["nothing_matched"])' 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ "$NOTHING" = "True" ]; then
  assert "AND semantics: an absent term zeroes every inventory hit" 0
else
  assert "AND semantics: an absent term zeroes every inventory hit" 1
  echo "rc=$RC nothing_matched=$NOTHING" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# TASK-003 AC2: name-over-body ranking -- "alpha" hits tools/alpha/ by name (tool.toml),
# first in the tools section.
# ---------------------------------------------------------------------------
FIRST_TOOLS_HIT="$("$PRECEDENT_BIN" find alpha --surface inventory --json 2>&1 \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["tools"]["hits"][0])' 2>/dev/null)"
if printf '%s' "$FIRST_TOOLS_HIT" | grep -q 'tools/alpha/'; then
  assert "name-over-body: the tools section's first hit names tools/alpha/" 0
else
  assert "name-over-body: the tools section's first hit names tools/alpha/" 1
  echo "first=$FIRST_TOOLS_HIT" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# TASK-003 AC3: adjacent-phrase bonus -- tools/alpha's description carries the literal
# phrase "notion sync" (adjacent, in order); delta's skill description has both words
# apart/reversed ("sync notion pages"). The phrase bonus puts the tools section's top
# score above the skills section's, so tools ranks first in section order.
# ---------------------------------------------------------------------------
SECTION_ORDER="$("$PRECEDENT_BIN" find "notion sync" --surface inventory --json 2>&1 \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(list(d.keys()))' 2>/dev/null)"
TOOLS_IDX="$(printf '%s' "$SECTION_ORDER" | grep -bo "'tools'" | head -1 | cut -d: -f1)"
SKILLS_IDX="$(printf '%s' "$SECTION_ORDER" | grep -bo "'skills'" | head -1 | cut -d: -f1)"
if [ -n "$TOOLS_IDX" ] && [ -n "$SKILLS_IDX" ] && [ "$TOOLS_IDX" -lt "$SKILLS_IDX" ]; then
  assert "adjacent-phrase bonus: tools (phrase match) outranks skills (words apart)" 0
else
  assert "adjacent-phrase bonus: tools (phrase match) outranks skills (words apart)" 1
  echo "order=$SECTION_ORDER" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# TASK-003 AC4: registry skip note for the missing `repo /nonexistent/path/for/test` row.
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find notion --surface inventory 2>&1)"
if printf '%s' "$OUT" | grep -q 'skipped: no dir at /nonexistent/path/for/test'; then
  assert "registry skip note for a missing repo path" 0
else
  assert "registry skip note for a missing repo path" 1
fi

# ---------------------------------------------------------------------------
# TASK-003 AC5: ~ expansion -- the `repo ~/eta-repo` row is scanned; its scripts/eta.sh
# (a unique word, "zorbington") shows up as a hit.
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find zorbington --surface inventory 2>&1)"
if printf '%s' "$OUT" | grep -q 'eta-repo/scripts/eta.sh'; then
  assert "~ expansion: the eta-repo registry row is scanned" 0
else
  assert "~ expansion: the eta-repo registry row is scanned" 1
fi

# ---------------------------------------------------------------------------
# TASK-003 AC6: secret redaction -- the ghp_ token in .claude/memory/gamma.md prints as
# [redacted], never in the clear.
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find "token rotation" --surface inventory 2>&1)"
if printf '%s' "$OUT" | grep -q '\[redacted\]' && ! printf '%s' "$OUT" | grep -q 'ghp_abcdefghij'; then
  assert "secret redaction: a ghp_ token prints as [redacted]" 0
else
  assert "secret redaction: a ghp_ token prints as [redacted]" 1
fi

# ---------------------------------------------------------------------------
# TASK-003 AC7: --json carries the required top-level keys.
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find notion --surface inventory --json 2>&1)"
KEYS_OK="$(printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
need = ("data_marker", "total_hits", "sections_with_hits", "nothing_matched")
print("yes" if all(k in d for k in need) else "no")
' 2>/dev/null)"
if [ "$KEYS_OK" = "yes" ]; then
  assert "--json carries data_marker/total_hits/sections_with_hits/nothing_matched" 0
else
  assert "--json carries data_marker/total_hits/sections_with_hits/nothing_matched" 1
fi

# ---------------------------------------------------------------------------
# TASK-003 AC8: --quiet collapses every empty/skipped section to one count line.
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find "notion zzzqqq" --surface inventory --quiet 2>&1)"
if printf '%s' "$OUT" | grep -q 'sections with no match or skipped)'; then
  assert "--quiet collapses empty/skipped sections to one line" 0
else
  assert "--quiet collapses empty/skipped sections to one line" 1
fi

# ---------------------------------------------------------------------------
# TASK-003 AC9: --explain resolves a hit label as printed; a label that resolves nowhere
# exits 1.
# ---------------------------------------------------------------------------
OUT="$("$PRECEDENT_BIN" find --explain "skill delta" --surface inventory 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'name: delta'; then
  assert "--explain \"skill delta\" prints the SKILL.md header, exit 0" 0
else
  assert "--explain \"skill delta\" prints the SKILL.md header, exit 0" 1
fi

"$PRECEDENT_BIN" find --explain "skill nope" --surface inventory >/dev/null 2>&1
assert "--explain \"skill nope\" (no file) exits 1" "$([ $? -eq 1 ]; echo $?)"

# ---------------------------------------------------------------------------
# TASK-003 AC10: precedent.log gains exactly one tab-separated, 4-field line per query.
# ---------------------------------------------------------------------------
LOG_FILE="$FIX_LEDGER/precedent.log"
BEFORE=0
[ -f "$LOG_FILE" ] && BEFORE="$(wc -l < "$LOG_FILE" | tr -d ' ')"
"$PRECEDENT_BIN" find "notion" --surface inventory >/dev/null 2>&1
AFTER="$(wc -l < "$LOG_FILE" | tr -d ' ')"
LAST_LINE="$(tail -n1 "$LOG_FILE")"
FIELD_COUNT="$(printf '%s' "$LAST_LINE" | awk -F'\t' '{print NF}')"
if [ "$AFTER" -eq "$((BEFORE + 1))" ] && [ "$FIELD_COUNT" -eq 4 ]; then
  assert "precedent.log gains one tab-separated, 4-field line per query" 0
else
  assert "precedent.log gains one tab-separated, 4-field line per query" 1
  echo "before=$BEFORE after=$AFTER fields=$FIELD_COUNT" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# TASK-003 AC11: an unknown registry kind exits 64 before any scanning starts.
# ---------------------------------------------------------------------------
BAD_REGISTRY="$TMPDIR_T/bad-registry.txt"
cp "$FIX_REGISTRY" "$BAD_REGISTRY"
echo "bogus /tmp" >> "$BAD_REGISTRY"
PRECEDENT_REGISTRY="$BAD_REGISTRY" "$PRECEDENT_BIN" find notion --surface inventory >/dev/null 2>&1
assert "an unknown registry kind exits 64" "$([ $? -eq 64 ]; echo $?)"

# ---------------------------------------------------------------------------
# TASK-003 AC12: the crons registry row surfaces both cron expressions for a worker hit.
# ---------------------------------------------------------------------------
CRON_HITS="$("$PRECEDENT_BIN" find "notion-cron" --surface inventory --json 2>&1 \
  | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["crons"]["hits"]))' 2>/dev/null)"
if [ "$CRON_HITS" = "2" ]; then
  assert "crons section lists both cron expressions for a matching worker" 0
else
  assert "crons section lists both cron expressions for a matching worker" 1
  echo "cron_hits=$CRON_HITS" | sed 's/^/      /'
fi

echo
echo "== summary =="
echo "  $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
