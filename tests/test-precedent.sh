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

  mkdir -p "$FIX_HOME/eta-repo" "$FIX_LEDGER"
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

echo
echo "== summary =="
echo "  $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
