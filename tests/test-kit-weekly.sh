#!/usr/bin/env bash
# test-kit-weekly.sh -- the ONE weekly scheduler (ADR-0034 decision 9, harness-loop SG-10).
# Behavior: the dispatcher walks the declarative jobs list; a good job runs with its args,
# an unknown/malformed entry logs + skips, a failing job logs + continues (never crashes
# the week). Structure: BTM rules on the launcher, the default jobs list resolves against
# the live tree, and the retired per-job session-intel plist stays gone.
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$KIT_DIR/deploy/macos/kit-weekly"
PASS=0; FAIL=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok(){ echo -e "  ${GREEN}PASS${NC} $*"; PASS=$((PASS+1)); }
no(){ echo -e "  ${RED}FAIL${NC} $*"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "=== kit-weekly dispatcher behavior ==="

printf '#!/bin/bash\necho GOOD:"$@"\n' > "$TMP/good"; chmod +x "$TMP/good"
printf '#!/bin/bash\nexit 3\n' > "$TMP/bad"; chmod +x "$TMP/bad"
cat > "$TMP/jobs.txt" <<EOF
# comment

alpha $TMP/good --flag v
ghost bin/does-not-exist run
malformed-name-only
beta $TMP/bad
omega $TMP/good after-failure
EOF

OUT="$(KIT_WEEKLY_JOBS="$TMP/jobs.txt" bash "$DISPATCH" 2>&1)"; RC=$?

[ $RC -eq 0 ] && ok "dispatcher exits 0 despite unknown+malformed+failing entries" \
             || no "dispatcher exited $RC (a bad jobs line crashed the week)"
grep -q 'GOOD:--flag v' <<<"$OUT" && ok "good job ran with its args" || no "good job did not run: $OUT"
grep -q "unknown job 'ghost'.*skipped" <<<"$OUT" && ok "unknown entry logs + skips (NC)" || no "unknown entry not skipped: $OUT"
grep -q "malformed jobs line.*malformed-name-only" <<<"$OUT" && ok "malformed line logs + skips (NC)" || no "malformed line not skipped: $OUT"
grep -q "'beta' FAILED (exit 3), continuing" <<<"$OUT" && ok "failing job logs + continues" || no "failing job not contained: $OUT"
grep -q 'GOOD:after-failure' <<<"$OUT" && ok "job AFTER the failure still ran" || no "failure aborted the week: $OUT"
grep -q 'done (ran=2 skipped=2 failed=1)' <<<"$OUT" && ok "summary counts ran=2 skipped=2 failed=1" || no "summary wrong: $(tail -1 <<<"$OUT")"

echo "=== missing jobs list is a hard error (misconfigured install must be loud) ==="
KIT_WEEKLY_JOBS="$TMP/nope.txt" bash "$DISPATCH" >/dev/null 2>&1 \
  && no "missing jobs list exited 0" || ok "missing jobs list exits nonzero"

echo "=== structure: BTM rules + default jobs resolve + per-job plist retired ==="
[ -x "$DISPATCH" ] && ok "dispatcher is executable" || no "dispatcher not executable"
case "$DISPATCH" in *.sh) no "launcher has a .sh extension (BTM rule)";; *) ok "launcher has no extension (BTM rule)";; esac
grep -A2 '<key>ProgramArguments</key>' "$KIT_DIR/deploy/macos/kit-weekly.plist.tmpl" \
  | grep -q '<string>__KIT__/deploy/macos/kit-weekly</string>' \
  && ok "plist ProgramArguments[0] is the dispatcher itself (BTM rule)" \
  || no "plist ProgramArguments[0] is not the bare dispatcher"

# Every default jobs.txt entry must resolve to a live executable in the tree.
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  name="${line%%[[:space:]]*}"; cmd="${line#"$name"}"; cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  exe="${cmd%%[[:space:]]*}"
  [ "${exe#/}" = "$exe" ] && exe="$KIT_DIR/$exe"
  [ -x "$exe" ] && ok "default job '$name' resolves ($exe)" || no "default job '$name' does NOT resolve ($exe)"
done < "$KIT_DIR/deploy/macos/jobs.txt"

[ -e "$KIT_DIR/lib/session/intel/deploy/macos/session-intel-weekly.plist.tmpl" ] \
  && no "retired per-job session-intel plist re-appeared (ADR-0034 decision 9)" \
  || ok "per-job session-intel plist stays retired (ADR-0034 decision 9)"

echo
echo "TOTAL: $((PASS+FAIL))   PASS: $PASS   FAIL: $FAIL"
[ $FAIL -eq 0 ] || exit 1
