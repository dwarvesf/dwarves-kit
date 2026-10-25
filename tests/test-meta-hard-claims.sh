#!/bin/bash
# always: a doc edit anywhere can add a HARD mark with no code behind it
# test-meta-hard-claims.sh -- a HARD claim exists only when code enforces it.
# Run: bash tests/test-meta-hard-claims.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh
#
# docs/reference/hard-rules.tsv lists the rules the kit's code really blocks on, each with a proving test.
# This suite pins two things:
#   1. Every registry row is real: its enforcing file exists and contains the rule's literal call
#      or message, a lib rule is wired into hooks/ship-gate.sh, its test file contains the literal
#      needle that proves the block, and its gate column agrees with lib/gate/gate-policy.sh (a
#      default-on key, an off-by-default key, or no key) and with the hook that reads the key.
#   2. Every doc that marks something HARD names a registry rule (a doc_terms entry on the same
#      line). A doc claim with no code behind it must say "warns" or "advisory" instead.
# Both checks run again on planted bad input (negative controls), so a green run is not vacuous.

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

REG="$KIT_DIR/docs/reference/hard-rules.tsv"
POLICY="$KIT_DIR/lib/gate/gate-policy.sh"
TAB="$(printf '\t')"

# check_registry <registry-file>: prints one problem per line, nothing when the registry is sound.
check_registry() {
  local reg="$1" n=0 id enforcer rule wired gate test needle terms seen="" key kind
  local policy_keys default_on
  policy_keys=" $(sed -n 's/^KEYS="\(.*\)"$/\1/p' "$POLICY") "
  default_on=" $(sed -n 's/^DEFAULT_ON="\([^"]*\)".*$/\1/p' "$POLICY") "
  [ "$(head -1 "$reg")" = "id${TAB}enforcer${TAB}rule${TAB}wired${TAB}gate${TAB}test${TAB}needle${TAB}doc_terms" ] \
    || { echo "header: not id/enforcer/rule/wired/gate/test/needle/doc_terms"; return; }
  while IFS="$TAB" read -r id enforcer rule wired gate test needle terms; do
    n=$((n + 1))
    if [ -z "$id" ] || [ -z "$terms" ]; then echo "row $n: a column is empty"; continue; fi
    case "$seen" in *" $id "*) echo "$id: duplicate id" ;; esac
    seen="$seen $id "
    [ -f "$KIT_DIR/$enforcer" ] || { echo "$id: enforcer $enforcer does not exist"; }
    if [ -f "$KIT_DIR/$enforcer" ] && ! grep -qF -- "$rule" "$KIT_DIR/$enforcer"; then
      echo "$id: rule '$rule' not found in $enforcer"
    fi
    if [ "$wired" != "-" ] && ! grep -qF -- "$wired" "$KIT_DIR/hooks/ship-gate.sh"; then
      echo "$id: call '$wired' not found in hooks/ship-gate.sh (the rule is defined but never wired)"
    fi
    [ -f "$KIT_DIR/$test" ] || { echo "$id: test $test does not exist"; }
    if [ -f "$KIT_DIR/$test" ] && ! grep -qF -- "$needle" "$KIT_DIR/$test"; then
      echo "$id: needle '$needle' not found in $test"
    fi
    kind="${gate%%:*}"; key="${gate#*:}"
    case "$enforcer" in
      hooks/ship-gate.sh|lib/*) ;;
      hooks/*)
        [ -f "$KIT_DIR/$enforcer" ] || continue
        # A hook that reads a [gate] key through gate-policy.sh is not "always"; one that does not
        # read it cannot be on:/off:<key>.
        if [ "$kind" = always ] && grep -q 'gate-policy.sh' "$KIT_DIR/$enforcer"; then
          echo "$id: gate says always but $enforcer reads gate-policy.sh"
        fi
        if { [ "$kind" = on ] || [ "$kind" = off ]; } && ! grep -qF "enabled $key" "$KIT_DIR/$enforcer"; then
          echo "$id: gate says $kind:$key but $enforcer never asks gate-policy.sh 'enabled $key'"
        fi ;;
    esac
    case "$kind" in
      always) [ "$gate" = always ] || echo "$id: gate 'always' takes no key" ;;
      on)  case "$policy_keys" in *" $key "*) ;; *) echo "$id: gate key '$key' is not a gate-policy key" ;; esac
           case "$default_on" in *" $key "*) ;; *) echo "$id: gate says on:$key but gate-policy does not default it ON" ;; esac ;;
      off) case "$policy_keys" in *" $key "*) ;; *) echo "$id: gate key '$key' is not a gate-policy key" ;; esac
           case "$default_on" in *" $key "*) echo "$id: gate says off:$key but gate-policy defaults it ON" ;; esac ;;
      opt-in) [ -n "$key" ] && [ "$key" != "$gate" ] || echo "$id: gate 'opt-in:' needs a description" ;;
      *) echo "$id: unknown gate '$gate' (always | on:<key> | off:<key> | opt-in:<what>)" ;;
    esac
  done < <(tail -n +2 "$reg")
}

# registry_terms <registry-file>: every doc_terms entry, one per line.
registry_terms() { tail -n +2 "$1" | cut -f8 | tr ',' '\n' | sort -u; }

# A line that DEFINES the HARD label (a legend: `[HARD] = ...` or `HARD` = ... pointing at the
# registry) or the placement test (`-> HARD hook:`) is not a claim about a rule.
is_definition() {
  case "$1" in
    *docs/reference/hard-rules.tsv*)
      case "$1" in *'HARD] = '*|*'HARD` = '*) return 0 ;; esac ;;
    *"-> HARD hook:"*) return 0 ;;
  esac
  return 1
}

# scan_file <file> <registry-file>: prints "file:line: text" for each HARD mention naming no registry rule.
scan_file() {
  local f="$1" reg="$2" terms line num hit term
  terms="$(registry_terms "$reg")"
  while IFS= read -r hit; do
    num="${hit%%:*}"; line="${hit#*:}"
    is_definition "$line" && continue
    local ok=1
    while IFS= read -r term; do
      case "$line" in *"$term"*) ok=0; break ;; esac
    done <<EOF
$terms
EOF
    [ "$ok" = 0 ] || echo "${f#"$KIT_DIR"/}:$num:$(printf '%s' "$line" | cut -c1-110)"
  done < <(grep -nw 'HARD' "$f" 2>/dev/null)
}

# doc_files: the live docs. Dated records (specs, verification runs, research, retros, decisions,
# implementation notes, handoffs, releases, briefs, absorption notes, audits, the changelog, and the
# generated design record) say what was true on their day and are not claims about today.
doc_files() {
  ( cd "$KIT_DIR" && {
      ls ./*.md 2>/dev/null
      find docs commands skills examples agents -type f \( -name '*.md' -o -name '*.txt' -o -name '*.svg' \) \
        -not -path 'docs/specs/*' -not -path 'docs/verification/*' -not -path 'docs/research/*' \
        -not -path 'docs/retro/*' -not -path 'docs/decisions/*' -not -path 'docs/implementation-notes/*' \
        -not -path 'docs/handoff/*' -not -path 'docs/releases/*' -not -path 'docs/briefs/*' \
        -not -path 'docs/absorption/*' -not -path 'docs/audits/*' -not -path 'docs/design/*' \
        -not -path 'docs/incidents/*' -not -name CHANGELOG.md -not -name SYSTEM-DESIGN.md
    } | sed 's|^\./||' | sort -u )
}

# ============================================================
echo ""
echo "=== Hard-rule registry (docs/reference/hard-rules.tsv) ==="
# ============================================================

assert_true "registry exists" "$([ -f "$REG" ]; echo $?)"
ROWS=$(tail -n +2 "$REG" | grep -c .)
assert_true "registry has rows ($ROWS)" "$([ "$ROWS" -gt 0 ]; echo $?)"
PROBLEMS="$(check_registry "$REG")"
assert_eq "every registry row is real (enforcer, rule, test, needle, gate)" "" "$PROBLEMS"
[ -z "$PROBLEMS" ] || printf '%s\n' "$PROBLEMS" | sed 's/^/    /'

# The five enforcers the docs lean on hardest must be present.
for hook in safety-gate ship-gate board-row-gate commit-format secrets-guard anti-rationalization tool-policy-guard; do
  assert_true "registry names the $hook rule family" "$(cut -f1 "$REG" | grep -q "^$hook\." ; echo $?)"
done
assert_true "registry carries the ship-gate review_verdict rule" "$(cut -f1 "$REG" | grep -q '^ship-gate.review-verdict$'; echo $?)"

# NEGATIVE CONTROL 1: a planted row naming a missing enforcer, a missing rule literal, a missing test,
# a missing needle, and a bad gate is flagged for each.
BAD="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
head -1 "$REG" > "$BAD"
printf 'x.nofile\thooks/does-not-exist.sh\tr\t-\talways\ttests/test-hooks.sh\tblocks rm -rf\tx\n' >> "$BAD"
printf 'x.norule\thooks/safety-gate.sh\tNO-SUCH-RULE-LITERAL\t-\talways\ttests/test-hooks.sh\tblocks rm -rf\tx\n' >> "$BAD"
printf 'x.notest\thooks/safety-gate.sh\tblock "rm-rf"\t-\talways\ttests/no-such-test.sh\tn\tx\n' >> "$BAD"
printf 'x.noneedle\thooks/safety-gate.sh\tblock "rm-rf"\t-\talways\ttests/test-hooks.sh\tNO-SUCH-NEEDLE\tx\n' >> "$BAD"
printf 'x.badgate\thooks/safety-gate.sh\tblock "rm-rf"\t-\toff:no_such_key\ttests/test-hooks.sh\tblocks rm -rf\tx\n' >> "$BAD"
printf 'x.wrongdefault\thooks/safety-gate.sh\tblock "rm-rf"\t-\toff:board_row_gate\ttests/test-hooks.sh\tblocks rm -rf\tx\n' >> "$BAD"
printf 'x.notwired\tlib/gate/ship-rules.sh\tship_rule_identities()\tNO-SUCH-CALL-IN-THE-HOOK\ton:fixture_identities\ttests/test-hooks.sh\tblocks rm -rf\tx\n' >> "$BAD"
printf 'x.alwayswrong\thooks/commit-format.sh\t|| block "subject is not a Conventional\t-\talways\ttests/test-hooks.sh\tblocks rm -rf\tx\n' >> "$BAD"
printf 'x.keynotread\thooks/secrets-guard.sh\tsecret-file path\t-\toff:commit_format\ttests/test-hooks.sh\tblocks rm -rf\tx\n' >> "$BAD"
BADOUT="$(check_registry "$BAD")"
for id in x.nofile x.norule x.notest x.noneedle x.badgate x.wrongdefault x.notwired x.alwayswrong x.keynotread; do
  assert_true "NC: planted row $id is flagged" "$(printf '%s\n' "$BADOUT" | grep -q "^$id:"; echo $?)"
done
rm -f "$BAD"

# ============================================================
echo ""
echo "=== HARD marks in live docs name a registry rule ==="
# ============================================================

UNMAPPED=""; FILES=0; MARKS=0
while IFS= read -r f; do
  FILES=$((FILES + 1))
  MARKS=$((MARKS + $(grep -cw 'HARD' "$KIT_DIR/$f" 2>/dev/null || true)))
  out="$(scan_file "$KIT_DIR/$f" "$REG")"
  [ -z "$out" ] || UNMAPPED="${UNMAPPED}${out}"$'\n'
done < <(doc_files)
UNMAPPED="${UNMAPPED%$'\n'}"
assert_true "the scan reached the live docs ($FILES files, $MARKS HARD mentions)" "$([ "$FILES" -gt 20 ] && [ "$MARKS" -gt 0 ]; echo $?)"
assert_eq "every HARD mark names a registry rule (a HARD with no code behind it must say warns or advisory)" "" "$UNMAPPED"
[ -z "$UNMAPPED" ] || printf '%s\n' "$UNMAPPED" | sed 's/^/    /'

# NEGATIVE CONTROL 2: a planted HARD claim naming no rule is flagged; one naming a rule passes.
PLANT="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
printf '%s\n' \
  'Spec ------> spec exists  ------>  spec-drift-guard   [HARD]' \
  'push ------> ship-gate + push-to-main blocker  [HARD]' \
  'see docs/reference/hard-rules.tsv: [HARD] = enforced blocker' \
  'spec-drift-guard [HARD] (docs/reference/hard-rules.tsv)' \
  'a plain sentence about a hard problem' > "$PLANT"
PLANTOUT="$(scan_file "$PLANT" "$REG")"
assert_true "NC: a HARD mark naming no rule (spec-drift-guard) is flagged" "$(printf '%s\n' "$PLANTOUT" | grep -q 'spec-drift-guard'; echo $?)"
assert_eq "NC: only the two unnamed marks are flagged; ship-gate and the legend pass" "2" "$(printf '%s\n' "$PLANTOUT" | grep -c .)"
rm -f "$PLANT"

# The spec-drift guard really only warns, which is why no doc may call it HARD.
assert_true "spec-drift-guard never exits 2 (it warns)" "$(grep -q 'exit 2' "$KIT_DIR/hooks/spec-drift-guard.sh"; [ $? -ne 0 ]; echo $?)"

# ============================================================
echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All hard-claim tests passed.${NC}"
  exit 0
fi
