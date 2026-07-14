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

# Modules = the kit's DECLARED module list (install.sh KIT_KNOWN_MODULES, the same list
# lib/config/module-registry.md is completeness-checked against) mapped to their lib/ dirs,
# UNION any lib/ dir carrying a tool.toml.
#
# The first cut used tool.toml alone, which matched THREE dirs (plugin-check, stats,
# skill-curator) out of twelve declared modules: C3/C4 were green while never looking at
# board, queue, session, gate, learn... including the module this very PR edits. A lint whose
# scope silently excludes 3/4 of its subject is the vacuous-pass failure mode wearing a
# different hat (advisor finding 1).
modules() {
  {
    grep -o '^KIT_KNOWN_MODULES="[^"]*"' install.sh | sed 's/.*"\(.*\)"/\1/' | tr ' ' '\n' \
      | sed 's/_/-/g' | while read -r m; do
          [ -n "$m" ] || continue
          for d in "lib/$m" "lib/${m//-/_}"; do [ -d "$d" ] && echo "$d"; done
        done
    find lib -maxdepth 2 -name tool.toml -exec dirname {} \;
  } | sort -u
}

# Existing, KNOWN doc/test debt: modules that predate the contract and do not yet satisfy C3/C4.
# The lint fails on anything NOT in this file, so no NEW debt can land; each line here is a
# visible IOU, not a silent exemption. Shrinking it is the work; growing it is a decision a
# human has to make in a diff.
GAPS="tests/kit-contract-known-gaps.txt"
known_gap() { grep -qxF "$1" "$GAPS" 2>/dev/null; }

# ---------------------------------------------------------------- C1 naming
echo "== C1 naming: no kit-owned cc-/CC_ prefix =="
# Grandfathered deprecated aliases (each warns and dies one release after SPEC-200), plus
# CC_PLUGINS_DIR which the HOST provides (we read it, we do not own its spelling).
# Grandfathered names are listed IN FULL and anchored with $. A bare `CC_SI_` prefix would
# permanently exempt the whole namespace, including a CC_SI_* var added tomorrow: the rule's
# stated job is to stop exactly that (review finding).
# `CC_SI_` (bare, trailing underscore) is the DERIVATION STEM in skill-curator's cfg(): the
# resolver builds the legacy name from the key, so the stem is the only literal in the source.
# Every other grandfathered name is spelled in full.
CC_OK='CC_SI_|CC_BACKLOG_(STAGING|BACKLOG|BACKLOG_FIX)|CC_PLUGINS_DIR'
cc_env() {  # POSIX grep only (see C7: `rg` is absent on CI and returns nothing = vacuous pass)
  # Match every shape a real regression arrives in, not just the one the first cut imagined:
  # ${VAR} / $VAR, os.environ.get("VAR") AND ('VAR'), os.environ["VAR"], getenv, and a bare
  # `CC_FOO=` assignment or `export CC_FOO`. The narrow first cut missed four of these; a NC
  # that plants only the shape the regex expects proves nothing (review finding).
  # -I skips BINARIES (a Rust/Python build tree is full of C-compiler macros like CC_OPT_,
  # CC_PROFILE: not our env vars, and a lint that reports them is a lint people mute).
  # tests/ are excluded because a back-compat test must NAME the deprecated var to prove the
  # alias still works; banning that would ban testing the ban.
  # Comment lines are stripped BEFORE matching: a comment explaining the retired name (the ones
  # in anomalies.py and common.sh document exactly this bug) is documentation, not a reader.
  # Same reasoning as C6; a lint that punishes its own fix trains people to delete the comment.
  grep -rhIE --exclude='*.md' --exclude='*.toml' --exclude-dir=.venv --exclude-dir=target \
    --exclude-dir=__pycache__ --exclude-dir=tests \
    'CC_[A-Z_]{2,}' "$@" 2>/dev/null \
    | grep -vE '^[[:space:]]*(#|//|\*)' \
    | grep -oE 'CC_[A-Z_]{2,}' | sort -u | grep -vE "^($CC_OK)$" || true
}
chk "no un-grandfathered CC_* env in lib/hooks/bin" "$(cc_env lib hooks bin)"

# a cc-* executable on an operator surface (bin/ or a module bin/) is the same fossil
cc_exe="$(find bin lib -type f -perm -u+x -name 'cc-*' 2>/dev/null | grep -v '/cc-improve$' || true)"
chk "no cc-* executable (except the deprecated cc-improve shim)" "$cc_exe"

printf 'x=${CC_PLANTED_VIOLATION}\n' > "$TMP/plant.sh"
if [ -n "$(cc_env "$TMP")" ]; then ok "NEGATIVE CONTROL: a planted CC_* IS caught"; else bad "NEGATIVE CONTROL: planted CC_* slipped through"; fi

# ---------------------------------------------------------------- C2 wiring
echo "== C2 wiring: every module executable is reachable from an operator surface =="
# Exempt = reached through a DISPATCHER, not directly (the dispatcher itself is the operator
# surface, and the C2b check below proves each one is really dispatched). The first cut also
# listed skill-improve, skill-review and cc-improve here, and they were reachable from NOTHING:
# the exempt list had become a laundering mechanism for the exact bug C2 exists to catch
# (advisor finding 2). They now have bin/ shims and are gone from this list. What remains is
# only the session family (dispatched by lib/session/session.sh, asserted below), add-backlog
# (called by board.sh), and prose-rag-rs (the Rust binary bin/prose-rag wraps).
WIRING_EXEMPT='session-observe|session-report|session-semantic|session-intel|session-recall|session-audit|add-backlog|prose-rag-rs'
unwired=""
while IFS= read -r exe; do
  base="$(basename "$exe")"
  echo "$base" | grep -qE "^($WIRING_EXEMPT)$" && continue
  # A deprecated-alias shim (it warns and execs the canonical name) is reachable BY DEFINITION:
  # it exists so an old call-site keeps working. Requiring a bin/ shim for the shim is silly.
  grep -q 'is deprecated, use' "$exe" 2>/dev/null && continue
  # reachable if a bin/ entry mentions it, a lib/*/*.sh dispatcher execs it, or a hook calls it
  if ! grep -rqF "$base" bin lib/*/*.sh hooks 2>/dev/null; then unwired="$unwired$exe\n"; fi
done < <(find lib -path '*/bin/*' -type f -perm -u+x -not -path '*/.venv/*' -not -path '*/target/*' 2>/dev/null | sort)
chk "no module executable is unreachable from bin/ or a dispatcher" "$(printf "%b" "$unwired")"

# C2b: the exempt list is not a free pass. Every exempt name must be provably reached by a
# dispatcher case or a wrapper, or it is unwired and merely hiding behind the exemption.
undispatched=""
# Derive the verb list from the dispatcher itself. Hardcoding it pinned `report`, a verb
# SPEC-200 I4 retires: the lint would have failed its own roadmap and forced the implementer
# to edit the test to obey the spec (review finding).
for exe in lib/session/*/bin/session-*; do
  [ -f "$exe" ] || continue
  v="${exe##*/session-}"
  grep -qE "^[[:space:]]+$v\)" lib/session/session.sh || undispatched="$undispatched session:$v"
done
grep -q 'add-backlog' lib/board/board.sh 2>/dev/null || undispatched="$undispatched board:add-backlog"
grep -rq 'prose-rag-rs' bin/prose-rag lib/prose-rag/*.sh 2>/dev/null || undispatched="$undispatched prose-rag:prose-rag-rs"
chk "every EXEMPT executable is really dispatched (no laundering)" "$undispatched"

# ---------------------------------------------------------------- C3 docs
echo "== C3 docs: README + SPEC + proof-of-done per module =="
missing=""; gapped=0
for m in $(modules); do
  # A spec is either the module-root SPEC.md (session tools' shape) or a numbered spec under
  # docs/specs/ (the repo-layout shape). Demanding ONE filename would be the lint inventing a
  # convention the kit does not have -- and a false failure teaches people to ignore the lint.
  # A spanner module (lib/session/ = observe + intel + audit + recall) documents each sub-tool,
  # not the umbrella dir. Accept the artifact in the module dir OR in any immediate sub-tool
  # dir; demanding a module-root copy would push people to write a stub nobody reads.
  for want in README.md SPEC docs/proof-of-done.md; do
    case "$want" in
      SPEC) [ -f "$m/SPEC.md" ] && continue
            ls "$m"/docs/specs/SPEC-*.md >/dev/null 2>&1 && continue
            ls "$m"/*/SPEC.md >/dev/null 2>&1 && continue
            ls "$m"/*/docs/specs/SPEC-*.md >/dev/null 2>&1 && continue ;;
      *)    [ -f "$m/$want" ] && continue
            ls "$m"/*/"$want" >/dev/null 2>&1 && continue ;;
    esac
    if known_gap "$m/$want"; then gapped=$((gapped+1)); else missing="$missing$m/$want\n"; fi
  done
done
chk "every module has README + a spec + docs/proof-of-done.md (no NEW gaps)" "$(printf "%b" "$missing")"
[ "$gapped" -gt 0 ] && printf "  DEBT %s known doc gaps (see %s)\n" "$gapped" "$GAPS"

# ---------------------------------------------------------------- C4 tests
echo "== C4 tests: every module has at least one test =="
untested=""; t_gapped=0
for m in $(modules); do
  mod="$(basename "$m")"
  # Tests live either in the module (lib/<m>/tests/) or at the repo root (tests/test-<m>.*),
  # both are real homes in this kit; a lint that only knew one would report a false gap.
  ls "$m"/tests/*.sh >/dev/null 2>&1 && continue
  ls tests/test-"$mod".* >/dev/null 2>&1 && continue
  ls tests/test-"${mod//-/_}".* >/dev/null 2>&1 && continue
  if known_gap "$m/tests"; then t_gapped=$((t_gapped+1)); else untested="$untested$m\n"; fi
done
chk "every module has a test (module-local or repo-root)" "$(printf "%b" "$untested")"
[ "$t_gapped" -gt 0 ] && printf "  DEBT %s known test gaps (see %s)\n" "$t_gapped" "$GAPS"

# ---------------------------------------------------------------- C5 proposal currency
echo "== C5 currency: proposers stage blocks, never write a board =="
# Anything that writes a `## [staged]` block must get it from the ONE renderer.
bespoke=""
while IFS= read -r f; do
  case "$f" in */tests/*) continue ;; esac   # a test ASSERTS on the block; it does not render one
  # A CODE reference to the renderer, not a comment mentioning it: a file that writes its own
  # block and name-drops staging-format.py in a comment used to pass (review finding).
  grep -vE '^[[:space:]]*#' "$f" \
    | grep -q 'staging.format\|staging_format\|render_block\|render_candidate' \
    || bespoke="$bespoke$f\n"
done < <(grep -rl '## \[staged\]' lib hooks --include='*.py' --include='*.sh' 2>/dev/null \
         | grep -v 'staging-format.py' | sort)
chk "every staged-block writer goes through the one renderer" "$(printf "%b" "$bespoke")"

# No proposer appends to a BACKLOG.md (the human gate `board promote` owns that write).
# Three append shapes, not one: `>> $BACKLOG`, python `open(..., "a")`, and `tee -a` (the last
# evaded the first cut). sed -i insertion remains out of reach of a grep; C5's real guarantee
# is the renderer, this is the belt.
autofile="$(grep -rlE '>>[[:space:]]*"?\$?\{?BACKLOG|open\([^)]*BACKLOG[^)]*,[[:space:]]*"a|tee[[:space:]]+-a[^|]*BACKLOG' \
            lib hooks 2>/dev/null | grep -v '/board/' || true)"
chk "no proposer appends to a board directly (propose-don't-dispose)" "$autofile"

# ---------------------------------------------------------------- C6 durable root
echo "== C6 root: persistence resolves through kit-log-dir.sh =="
# Code lines only: a COMMENT naming the old path (e.g. the one in queue.sh explaining why it
# moved) is documentation, not a hardcode. Grepping prose here would punish the fix.
# No --include filter: the kit's executables are EXTENSIONLESS by house rule (the BTM plist
# convention), so filtering to *.sh/*.py skipped 10 of them, including two this PR touches
# (review finding). Exclude only docs.
hardcoded="$(grep -rn --exclude='*.md' --exclude-dir=.venv --exclude-dir=tests \
             '\.claude/dwarves-kit/logs' lib 2>/dev/null \
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
# The trailing `-` (a dash-flag) is NOT required: `rg "pat" file` and `fd . | head` carry no
# flag and slipped through the first cut (review finding). Require only that the tool sits in
# command position followed by whitespace.
offenders="$(grep -rhoE --exclude='test-kit-contract.sh' \
             "(^|\\\$\(|\||&&|;|!)[[:space:]]*($NONPORTABLE)[[:space:]]" tests lib/*/tests 2>/dev/null \
             | grep -oE "($NONPORTABLE)[[:space:]]" | grep -oE "^($NONPORTABLE)" | sort -u || true)"
chk "no test invokes a non-CI tool (rg/fd/sd/...)" "$offenders"

# ---------------------------------------------------------------- negative controls
# Each rule above asserts an ABSENCE. An absence-assertion that cannot fail is worse than no
# test at all (see the C7 header: that is exactly how the first cut of C1 shipped green on CI
# while checking nothing). Every rule gets a planted violation here.
echo "== NEGATIVE CONTROLS: each rule catches a violation planted in an UNEXPECTED shape =="
# The first cut planted each violation in the exact syntactic form its own regex was written
# against, which proves only that the regex matches itself. A review re-planted them in the
# forms a real regression actually arrives in, and FOUR rules turned out to be vacuous. Every
# NC below therefore uses a shape the rule's author did NOT have in mind.
mkdir -p "$TMP/nc/bin" "$TMP/nc/tests" "$TMP/nc/lib"

# C1: single-quoted environ.get, subscript form, and a bare assignment (not ${...})
printf "x = os.environ.get('CC_SNEAKY_ONE')\ny = os.environ[\"CC_SNEAKY_TWO\"]\n" > "$TMP/nc/plant.py"
printf 'export CC_SNEAKY_THREE=1\n' > "$TMP/nc/plant.sh"
nc1="$(cc_env "$TMP/nc")"
[ "$(echo "$nc1" | grep -c CC_SNEAKY)" -eq 3 ] && ok "C1 catches all three unexpected CC_* shapes" || bad "C1 vacuous on unexpected shapes" "(caught: $nc1)"
# and a NEW CC_SI_* must NOT be grandfathered by the stem
printf 'z=${CC_SI_BRAND_NEW_FOSSIL}\n' > "$TMP/nc/plant2.sh"
echo "$(cc_env "$TMP/nc")" | grep -q CC_SI_BRAND_NEW_FOSSIL && ok "C1 does not blanket-exempt the CC_SI_ namespace" || bad "C1 grandfathers a NEW CC_SI_ var"
rm -f "$TMP/nc/plant.py" "$TMP/nc/plant.sh" "$TMP/nc/plant2.sh"

# C2: an unwired executable in a module bin/ (the session-audit / skill-improve shape)
printf '#!/usr/bin/env bash\necho hi\n' > "$TMP/nc/bin/totally-unwired"; chmod +x "$TMP/nc/bin/totally-unwired"
if ! grep -rqF "totally-unwired" bin lib/*/*.sh hooks 2>/dev/null; then ok "C2 would catch an unwired module executable"; else bad "C2 is vacuous"; fi

# C5: a bespoke writer that name-drops the renderer IN A COMMENT (the evasion that passed)
printf '# uses staging-format.py conventions\nprint("## [staged] forged")\n' > "$TMP/nc/lib/bespoke.py"
if ! grep -vE '^[[:space:]]*#' "$TMP/nc/lib/bespoke.py" | grep -q 'staging_format\|render_block'; then
  ok "C5 catches a writer that only MENTIONS the renderer in a comment"
else bad "C5 vacuous on the comment-mention evasion"; fi

# C5b: a direct board append via tee -a (not the >> shape the rule was written for)
printf 'echo row | tee -a "$BACKLOG_FILE"\n' > "$TMP/nc/lib/autofile.sh"
grep -qE 'tee[[:space:]]+-a[^|]*BACKLOG' "$TMP/nc/lib/autofile.sh" && ok "C5b: the tee -a board-append shape is detectable" || bad "C5b vacuous"

# C6: hardcoded log root in an EXTENSIONLESS executable (the kit's own house style)
printf '#!/usr/bin/env bash\nLOG=$HOME/.claude/dwarves-kit/logs/x.log\n' > "$TMP/nc/bin/extensionless"; chmod +x "$TMP/nc/bin/extensionless"
[ -n "$(grep -rn --exclude='*.md' '\.claude/dwarves-kit/logs' "$TMP/nc" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')" ] \
  && ok "C6 catches a hardcode in an extensionless executable" || bad "C6 vacuous on extensionless files"

# C7: a non-portable tool with NO dash-flag (the form the first cut missed)
printf 'out=$(rg "pattern" file)\n' > "$TMP/nc/tests/nonportable.sh"
nc7="$(grep -rhoE "(^|\\\$\(|\||&&|;|!)[[:space:]]*($NONPORTABLE)[[:space:]]" "$TMP/nc/tests" 2>/dev/null || true)"
[ -n "$nc7" ] && ok "C7 catches a flagless rg in a test" || bad "C7 vacuous on the flagless form"

echo ""
echo "=== kit-contract: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
