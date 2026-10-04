#!/usr/bin/env bash
# test-registry-one-pass.sh -- the one-pass reference matcher of lib/registry/feature-registry.sh.
# The generator answers every feature's Specs, Tests and Dispatched-by cell from one awk pass
# over the corpus. These cases pin the exact-token semantics that pass must keep (hyphen is a
# token character, case matters, the boundary is the line start or any non-token character),
# the cell formatting (alphabetical, `+N` past three, SPEC numbers in version order), and that
# a regex-bearing token (`foo.sh`, `foo run`) still matches. Each case drives a COPY of the
# generator in a throwaway tree, so the whole suite stays well under a second.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
REG="lib/registry/feature-registry.sh"

D="$(mktemp -d)"
mkdir -p "$D/lib/registry" "$D/lib/x/tests" "$D/commands" "$D/agents" "$D/skills/sk" "$D/hooks" "$D/docs/specs" "$D/tests"
cp "$KIT/$REG" "$D/$REG"
stub() { printf -- '---\ndescription: a stub\n---\nbody\n'; }
stub > "$D/commands/review.md"; stub > "$D/commands/review-team.md"
stub > "$D/agents/scanner.md"
stub > "$D/skills/sk/SKILL.md"
printf '#!/bin/bash\n# hk.sh -- a stub hook\nbash lib/x/foo.sh\n' > "$D/hooks/hk.sh"
printf '{"hooks":{}}\n' > "$D/hooks/hooks.json"
printf '{}\n' > "$D/settings.json"
printf '#!/usr/bin/env bash\n# kit-verb: foo run | runs foo\n' > "$D/lib/x/foo.sh"

gen() { ( cd "$D" && bash "$REG" generate "$D/out.md" ); }
row() { grep -F "$1" "$D/out.md"; } # the table row carrying the given label

# 1. hyphen is a token character: `review` never matches inside `review-team`
printf 'only review-team is named here.\n' > "$D/docs/specs/SPEC-5-a.md"
gen
[ "$(row '`/kit:review` ')" = '| `/kit:review` | `[H/I]` | a stub | - | - |' ] \
  && ok "1 review does not match inside review-team" || { no "1 hyphen boundary"; row '`/kit:review` '; }
row '`/kit:review-team` ' | grep -qF '| SPEC-5 | - |' \
  && ok "1b review-team matches itself" || no "1b review-team matches itself"

# 2. boundaries: line start/end and punctuation match; a letter, digit, underscore or hyphen neighbour does not
printf 'xreview\nreview_x\nreview9\nREVIEW\n' > "$D/docs/specs/SPEC-6-near.md"
gen
row '`/kit:review` ' | grep -qF '| - | - |' \
  && ok "2 near-misses and wrong case do not match" || { no "2 near-misses"; row '`/kit:review` '; }
printf 'review\n(review)\n' > "$D/docs/specs/SPEC-6-near.md"
gen
row '`/kit:review` ' | grep -qF '| SPEC-6 | - |' \
  && ok "2b line-start and parenthesis neighbours match" || no "2b line-start and parenthesis neighbours"

# 3. SPEC numbers sort as versions and cap at three
for n in 100 2 10 9; do printf 'review\n' > "$D/docs/specs/SPEC-$n-v.md"; done
gen
row '`/kit:review` ' | grep -qF '| SPEC-2, SPEC-6, SPEC-9 +2 | - |' \
  && ok "3 specs sort by number, three shown, +N for the rest" || { no "3 spec ordering"; row '`/kit:review` '; }

# 4. tests: bytewise order (uppercase first), basename dedupe across dirs, +N cap
for f in test-b.sh test-a.sh test-Z.sh test-c.sh; do printf 'review\n' > "$D/tests/$f"; done
printf 'review\n' > "$D/lib/x/tests/test-a.sh"
gen
row '`/kit:review` ' | grep -qF '| test-Z.sh, test-a.sh, test-b.sh +1 |' \
  && ok "4 tests sorted bytewise, deduped by basename, +N" || { no "4 tests cell"; row '`/kit:review` '; }

# 5. agent Dispatched-by: command and skill names, skills marked, sorted bytewise
printf 'dispatches scanner\n' > "$D/commands/review.md"
printf 'uses scanner\n' > "$D/skills/sk/SKILL.md"
gen
row '`scanner` ' | grep -qF '| review, sk (skill) |' \
  && ok "5 dispatched-by lists commands and skills" || { no "5 dispatched-by"; row '`scanner` '; }

# 6. verb: regex-bearing tokens (foo.sh, "foo run") match; a hook that calls the script counts its tests
printf 'foo.sh here\n' > "$D/tests/test-d.sh"
printf 'the foo run verb\n' > "$D/docs/specs/SPEC-7-v.md"
printf 'foo.shx is a different word\n' > "$D/tests/test-e.sh"
printf 'hk.sh is wired\n' > "$D/tests/test-f.sh"
gen
V="$(row '`foo run` ')"
case "$V" in
  *'| SPEC-7 | test-d.sh, test-f.sh |') ok "6 verb matches by script name, verb name and calling hook; foo.shx does not" ;;
  *) no "6 verb cells"; echo "$V" ;;
esac

# 7. determinism: a second run is byte-identical
cp "$D/out.md" "$D/out1.md"; gen
cmp -s "$D/out.md" "$D/out1.md" && ok "7 double run byte-identical" || no "7 double run"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
