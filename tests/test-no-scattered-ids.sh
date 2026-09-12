#!/usr/bin/env bash
# test-no-scattered-ids.sh -- the provenance rule, enforced where the repo is already clean.
#
# THE RULE (CONTRIBUTING.md "Where an ID may appear"): a spec, task, ADR or ticket id belongs
# in exactly one of three places. The record that IS it. A row keyed by it. One provenance
# footer at the bottom of a doc. Everywhere else, state the thing plainly.
#
# THIS LINT IS A RATCHET, NOT A FULL AUDIT. The repo carries roughly 2,600 scattered ids that
# predate the rule, so a lint over all of them would fail on day one and be disabled by
# Tuesday. It enforces the zones that are already clean, so they cannot regrow, and gains a
# zone each time a cleanup batch lands. Widening it is the point; a zone list that never
# grows means the cleanup stopped.
#
#   Zone 1  no id inside a string the code PRINTS (hooks/, lib/, excluding nested tests/)
#   Zone 2  no instruction telling the model to EMIT an id into its own output (commands/)
#   Zone 3  no id anywhere in hooks/*.sh (comments included, not just printed strings)
#   Zone 4  no id anywhere in bin/* (help text and comments)
#   Zone 5  no id in skills/*/SKILL.md prose (frontmatter keys excepted)
#   Zone 6  no id anywhere in agents/*.md (frontmatter, prose, Source lines)
#   Zone 7  no id anywhere in commands/*.md (prose, headings, Source lines)
#
# Zones 1 and 2 predate lib/lint/scattered-ids.sh and keep their own narrow inline greps on
# purpose: Zone 1 only cares whether an id reaches the terminal (echo/printf), Zone 2 only
# cares whether a command tells the MODEL to mint an id token; both are stricter shapes than
# "any id in the file," so lib/ still carries plenty of comment-only ids Zone 1
# does not see (lib/ is a future batch). Zones 3
# onward are the general "any non-exempt id" check and are driven by the shared enumerator
# (`lib/lint/scattered-ids.sh`) so a new zone is one line here, not a new grep.
#
# Run: bash tests/test-no-scattered-ids.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_DIR" || exit 1

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok()  { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); }
no()  { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); }

ID_RE='(SPEC|TASK|ADR|SG|DEC|ID)-[0-9]+'

# Documented exemptions, each a real one rather than a convenience:
#   SPEC-%s          a printf substitution; the VALUE is the reserved number a worker acts on
#   lib/*/tests/     test-progress echoes, not operator-facing
#   ID-[0-9]+"       a quoted data key the code reads (tool.toml board rows)
_exempt() {
  case "$1" in
    *'SPEC-%s'*|*'ID-%s'*)        return 0 ;;
    */tests/*)                    return 0 ;;
  esac
  return 1
}

echo "=== Zone 1: no id inside a printed string ==="
hits=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  _exempt "$line" && continue
  echo "     $line" >&2
  hits=$((hits+1))
done < <(grep -rnE "(echo|printf)[^|]*\"[^\"]*${ID_RE}|(echo|printf)[^|]*'[^']*${ID_RE}" \
           hooks lib --include='*.sh' --include='cc-improve' 2>/dev/null || true)
if [ "$hits" -eq 0 ]; then
  ok "no spec id reaches the operator's terminal through echo or printf"
else
  no "$hits printed string(s) carry a spec id; the reader cannot open a spec, so state the thing plainly"
fi

echo ""
echo "=== Zone 2: no instruction tells the model to emit an id ==="
# The shape that matters: a command telling the model to WRITE a bracketed id token into an
# artifact it produces. commands/next.md did exactly this, manufacturing the banned tag on
# every run, which is how a rule about prose became a rule the tooling itself broke.
emit=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  echo "     $line" >&2
  emit=$((emit+1))
done < <(grep -rnE '(append|write|add|emit).{0,40}`?(TASK|SPEC|ID)-\[' commands 2>/dev/null || true)
if [ "$emit" -eq 0 ]; then
  ok "no command instructs the model to write an id token into its own output"
else
  no "$emit instruction(s) emit an id; remove the token, keep the instruction"
fi

ENUM="lib/lint/scattered-ids.sh"
clean_zone() {  # clean_zone <zone-name> <zone-number> <label>
  z="$1"; n="$2"; label="$3"
  echo ""
  echo "=== Zone $n: $label ==="
  hits="$(bash "$ENUM" --zone "$z" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    ok "no scattered id in $z"
  else
    printf '%s\n' "$hits" | while IFS= read -r l; do [ -n "$l" ] && echo "     $l" >&2; done
    no "$(printf '%s\n' "$hits" | grep -c .) hit(s) in $z; see lib/lint/README.md for the exemption list"
  fi
}
clean_zone hooks    3 "no id anywhere in hooks/*.sh"
clean_zone bin      4 "no id anywhere in bin/*"
clean_zone skills   5 "no id in skills/*/SKILL.md prose"
clean_zone agents   6 "no id anywhere in agents/*.md"
clean_zone commands 7 "no id anywhere in commands/*.md"

echo ""
echo "=== Ratchet: the zone list is meant to grow ==="
# A reminder with teeth: this asserts the rule is written down, so the lint cannot outlive
# its own documentation.
if grep -q "Where an ID may appear" CONTRIBUTING.md 2>/dev/null; then
  ok "CONTRIBUTING.md carries the rule this lint enforces"
else
  no "CONTRIBUTING.md has no 'Where an ID may appear' section; the lint would be enforcing an unwritten rule"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then echo "test-no-scattered-ids: $PASS passed, $FAIL FAILED" >&2; exit 1; fi
echo "test-no-scattered-ids: all $PASS passed"
