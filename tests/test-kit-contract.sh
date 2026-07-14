#!/usr/bin/env bash
# test-kit-contract.sh -- SPEC-200: the standing contract EVERY kit module must satisfy.
#
# The rules in docs/kit-contract.md, executable. Not style policing: each rule below exists
# because its violation already shipped and cost something (the cite is in the rule's header).
#
# C1  NAMING     no kit-owned name carries the host-agent prefix (`cc-` / `CC_*`).
# C2  WIRING     every lib/<mod>/bin/<exe> is reachable from an operator surface (a bin/
#                dispatcher case, a bin/ shim, or an explicit exempt list) -- an unreachable
#                tool is a tool nobody runs (session-audit shipped unwired, 2026-07-14).
# C3  DOCS       every module dir carries README.md + SPEC.md + docs/proof-of-done.md.
# C4  TESTS      every module dir carries at least one tests/*.sh.
# C5  CURRENCY   every proposer writes `## [staged]` blocks through lib/learn/staging-format.py
#                and NEVER writes a board directly (ADR-0034 decision 1 / SPEC-200 I1).
# C6  ROOT       every module that persists state resolves it through lib/telemetry/kit-log-dir.sh
#                (SPEC-097), never a hardcoded ~/.claude/dwarves-kit/logs.
# C7  PORTABLE   no test reaches for a tool CI does not have (rg/fd/sd/jq...): a missing binary
#                turns a lint into a VACUOUS PASS (this exact bug shipped, 2026-07-14).
#
# Every rule has a NEGATIVE CONTROL: a planted violation must be caught. A lint nobody can
# see fail is a lint nobody should trust.
#
# Run: bash tests/test-kit-contract.sh
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KIT" || exit 1

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok()  { printf "  ${GREEN}PASS${NC} %s\n" "$1"; PASS=$((PASS+1)); }
bad() { printf "  ${RED}FAIL${NC} %s %s\n" "$1" "${2:-}"; FAIL=$((FAIL+1)); }
chk() { if [ -z "$2" ]; then ok "$1"; else bad "$1" "(offenders: $(echo "$2" | tr '\n' ' '))"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Modules = lib/<name>/ dirs that carry a tool.toml (the kit's own definition of a module).
modules() { find lib -maxdepth 2 -name tool.toml -exec dirname {} \; | sort; }

# ---------------------------------------------------------------- C1 naming
echo "== C1 naming: no kit-owned cc-/CC_ prefix =="
# Grandfathered deprecated aliases (each warns and dies one release after SPEC-200), plus
# CC_PLUGINS_DIR which the HOST provides (we read it, we do not own its spelling).
CC_OK='CC_SI_|CC_BACKLOG_STAGING|CC_BACKLOG_BACKLOG|CC_BACKLOG_BACKLOG_FIX|CC_PLUGINS_DIR'
cc_env() {  # POSIX grep only (see C7: `rg` is absent on CI and returns nothing = vacuous pass)
  grep -rhoE --exclude='*.md' --exclude='*.toml' \
    '\$\{?CC_[A-Z_]+|os\.environ\.get\("CC_[A-Z_]+"|getenv\("CC_[A-Z_]+"' "$@" 2>/dev/null \
    | grep -oE 'CC_[A-Z_]+' | sort -u | grep -vE "^($CC_OK)" || true
}
chk "no un-grandfathered CC_* env in lib/hooks/bin" "$(cc_env lib hooks bin)"

# a cc-* executable on an operator surface (bin/ or a module bin/) is the same fossil
cc_exe="$(find bin lib -type f -perm -u+x -name 'cc-*' 2>/dev/null | grep -v '/cc-improve$' || true)"
chk "no cc-* executable (except the deprecated cc-improve shim)" "$cc_exe"

printf 'x=${CC_PLANTED_VIOLATION}\n' > "$TMP/plant.sh"
if [ -n "$(cc_env "$TMP")" ]; then ok "NEGATIVE CONTROL: a planted CC_* IS caught"; else bad "NEGATIVE CONTROL: planted CC_* slipped through"; fi

# ---------------------------------------------------------------- C2 wiring
echo "== C2 wiring: every module executable is reachable from an operator surface =="
# Exempt: helpers a dispatcher/hook calls internally, and the deprecated shims.
WIRING_EXEMPT='cc-improve|session-observe|session-report|session-semantic|session-intel|session-recall|session-audit|add-backlog|skill-review|skill-improve|prose-rag-rs'
unwired=""
while IFS= read -r exe; do
  base="$(basename "$exe")"
  echo "$base" | grep -qE "^($WIRING_EXEMPT)$" && continue
  # reachable if a bin/ entry mentions it, a lib/*/*.sh dispatcher execs it, or a hook calls it
  if ! grep -rqF "$base" bin lib/*/*.sh hooks 2>/dev/null; then unwired="$unwired$exe\n"; fi
done < <(find lib -path '*/bin/*' -type f -perm -u+x -not -path '*/.venv/*' 2>/dev/null | sort)
chk "no module executable is unreachable from bin/ or a dispatcher" "$(printf "%b" "$unwired")"

# The exempt list is not a free pass: each exempt name must be dispatched by lib/<mod>/<mod>.sh
# (that IS its operator surface). session-audit was exempt-shaped and NOT dispatched: the bug.
undispatched=""
for v in observe report semantic intel recall audit; do
  grep -qE "^\s+$v\)" lib/session/session.sh || undispatched="$undispatched session:$v"
done
chk "every session verb has a dispatcher case (the session-audit bug)" "$undispatched"

# ---------------------------------------------------------------- C3 docs
echo "== C3 docs: README + SPEC + proof-of-done per module =="
missing=""
for m in $(modules); do
  [ -f "$m/README.md" ] || missing="$missing$m/README.md\n"
  # A spec is either the module-root SPEC.md (session tools' shape) or a numbered spec under
  # docs/specs/ (the repo-layout shape). Demanding ONE filename would be the lint inventing a
  # convention the kit does not have -- and a false failure teaches people to ignore the lint.
  [ -f "$m/SPEC.md" ] || ls "$m"/docs/specs/SPEC-*.md >/dev/null 2>&1 || missing="$missing$m/(SPEC.md|docs/specs/SPEC-*.md)\n"
  [ -f "$m/docs/proof-of-done.md" ] || missing="$missing$m/docs/proof-of-done.md\n"
done
chk "every module has README + a spec + docs/proof-of-done.md" "$(printf "%b" "$missing")"

# ---------------------------------------------------------------- C4 tests
echo "== C4 tests: every module has at least one test =="
untested=""
for m in $(modules); do
  ls "$m"/tests/*.sh >/dev/null 2>&1 || untested="$untested$m\n"
done
chk "every module has tests/*.sh" "$(printf "%b" "$untested")"

# ---------------------------------------------------------------- C5 proposal currency
echo "== C5 currency: proposers stage blocks, never write a board =="
# Anything that writes a `## [staged]` block must get it from the ONE renderer.
bespoke=""
while IFS= read -r f; do
  case "$f" in */tests/*) continue ;; esac   # a test ASSERTS on the block; it does not render one
  grep -q 'staging.format\|staging_format\|render_block\|render_candidate' "$f" || bespoke="$bespoke$f\n"
done < <(grep -rl '## \[staged\]' lib hooks --include='*.py' --include='*.sh' 2>/dev/null \
         | grep -v 'staging-format.py' | sort)
chk "every staged-block writer goes through the one renderer" "$(printf "%b" "$bespoke")"

# No proposer appends to a BACKLOG.md (the human gate `board promote` owns that write).
autofile="$(grep -rlE '>>[[:space:]]*"?\$?\{?BACKLOG|open\([^)]*BACKLOG[^)]*,[[:space:]]*"a' lib hooks 2>/dev/null | grep -v '/board/' || true)"
chk "no proposer appends to a board directly (propose-don't-dispose)" "$autofile"

# ---------------------------------------------------------------- C6 durable root
echo "== C6 root: persistence resolves through kit-log-dir.sh =="
# Code lines only: a COMMENT naming the old path (e.g. the one in queue.sh explaining why it
# moved) is documentation, not a hardcode. Grepping prose here would punish the fix.
hardcoded="$(grep -rn --include='*.sh' --include='*.py' '\.claude/dwarves-kit/logs' lib 2>/dev/null \
             | grep -v 'kit-log-dir.sh' | grep -vE ':[0-9]+:[[:space:]]*#' | cut -d: -f1 | sort -u || true)"
chk "no module hardcodes the pre-SPEC-097 log root" "$hardcoded"

# ---------------------------------------------------------------- C7 portable tests
echo "== C7 portable: tests use no tool CI lacks =="
# A test that shells out to a missing binary produces EMPTY output, and an emptiness-asserting
# lint then passes vacuously. This is not hypothetical: it shipped on 2026-07-14 (`rg` in the
# C1 lint), and only the negative control caught it.
NONPORTABLE='rg|fd|sd|bat|eza|jaq|delta|dust|procs'
# Command position only: start of line, after a pipe, `$(`, `&&`, `;`, or `!`. Matching the
# bare word anywhere flags prose ("Coverage delta") and is how a lint earns a reputation for
# crying wolf.
# This file is excluded from its own sweep: its negative control PLANTS an `rg` line on
# purpose, and a lint that flags its own fixture is a lint that cannot be green.
offenders="$(grep -rhoE --exclude='test-kit-contract.sh' \
             "(^|\\\$\(|\||&&|;|!)[[:space:]]*($NONPORTABLE)[[:space:]]+-" tests lib/*/tests 2>/dev/null \
             | grep -oE "($NONPORTABLE)[[:space:]]+-" | grep -oE "^($NONPORTABLE)" | sort -u || true)"
chk "no test invokes a non-CI tool (rg/fd/sd/...)" "$offenders"

# ---------------------------------------------------------------- negative controls
# Each rule above asserts an ABSENCE. An absence-assertion that cannot fail is worse than no
# test at all (see the C7 header: that is exactly how the first cut of C1 shipped green on CI
# while checking nothing). Every rule gets a planted violation here.
echo "== NEGATIVE CONTROLS: each rule catches a planted violation =="
mkdir -p "$TMP/nc/bin" "$TMP/nc/tests"

printf 'x=${CC_PLANTED}\n' > "$TMP/nc/plant.sh"
[ -n "$(cc_env "$TMP/nc")" ] && ok "C1 catches a planted CC_* env" || bad "C1 is vacuous"

printf '## [staged] planted\n' > "$TMP/nc/bespoke.py"
if grep -rl '## \[staged\]' "$TMP/nc" 2>/dev/null | grep -q bespoke && \
   ! grep -q 'render_block' "$TMP/nc/bespoke.py"; then
  ok "C5 catches a bespoke staged-block writer"
else bad "C5 is vacuous"; fi

printf 'LOG=$HOME/.claude/dwarves-kit/logs/x.log\n' > "$TMP/nc/hardcoded.sh"
[ -n "$(grep -rlF '.claude/dwarves-kit/logs' "$TMP/nc" 2>/dev/null)" ] && ok "C6 catches a hardcoded log root" || bad "C6 is vacuous"

printf 'out=$(rg -o foo bar)\n' > "$TMP/nc/tests/nonportable.sh"
nc7="$(grep -rhoE "(^|\\\$\(|\||&&|;|!)[[:space:]]*($NONPORTABLE)[[:space:]]+-" "$TMP/nc/tests" 2>/dev/null || true)"
[ -n "$nc7" ] && ok "C7 catches a planted rg in a test" || bad "C7 is vacuous"

echo ""
echo "=== kit-contract: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
