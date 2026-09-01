#!/usr/bin/env bash
# test-ship-gate-profiles.sh
# Exercises the REAL ship-gate.sh hook (PreToolUse on git push) end to end, per profile, in
# the docs/verification/<slug>/ directory layout. For each of eval / tool-build / feature:
#   - proof present (test-design + green run + negative-control run) -> the hook ALLOWS (exit 0)
#   - the negative-control run removed                               -> the hook BLOCKS (exit 2)
# Proves Done(b): the gate recognizes the slug-dir layout for all three profiles, blocked-then-
# allowed, via the actual hook (not just the lib). The hook runs with CLAUDE_PLUGIN_ROOT set
# to this repo, exactly how the plugin harness invokes it, so this is the same code path a
# real `git push` hits (the marketplace's source directory IS this repo).
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$KIT_DIR/hooks/ship-gate.sh"
LOGDIR="$(mktemp -d)"; trap 'rm -rf "$LOGDIR"' EXIT
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }
[ -f "$HOOK" ] || { echo "[NO EXECUTABLE CHECK: ship-gate hook not found at $HOOK]"; exit 1; }

run_hook() { # $1 = fixture dir ; prints nothing, returns the hook's exit code
  ( cd "$1" && printf '{"tool_input":{"command":"git push origin feat/x"}}' \
    | CLAUDE_PLUGIN_ROOT="$KIT_DIR" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$HOOK" >/dev/null 2>&1 )
}

build() { # $1 dir ; $2 profile ; $3 include-negctl (1/0)
  local d="$1" profile="$2" negctl="$3"
  rm -rf "$d"; mkdir -p "$d/docs/verification" "$d/src"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo "# Verification log (proof of done)" > "$d/docs/verification/README.md"  # opt-in marker
  echo "baseline" > "$d/src/code.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  git -C "$d" checkout -qb feat/x
  echo "behavior change" >> "$d/src/code.sh"                                    # behavioral diff
  mkdir -p "$d/docs/verification/$profile/runs"
  cat > "$d/docs/verification/$profile/test-design.md" <<EOF
# Test design -- $profile
Profile: $profile
Proof class: behavioral
## Hypothesis / assumptions
- demo: the $profile proof in the slug-dir layout is gate-visible.
EOF
  cat > "$d/docs/verification/$profile/runs/green.md" <<EOF
## 2026-06-08 18:00 PASS -- $profile [green]
- Command: \`bash src/code.sh\`
- Exit: 0
- Verdict: PASS
EOF
  if [ "$negctl" = "1" ]; then
    cat > "$d/docs/verification/$profile/runs/negctl.md" <<EOF
## 2026-06-08 18:01 RED-as-expected -- $profile [negative-control]
- Command: \`bash src/code.sh\`
- Exit: 1
- Verdict: RED-as-expected
- Note: NEGATIVE CONTROL
EOF
  fi
  # COMMIT on feat/x so HEAD diverges from merge-base(main) -- ship-gate's proof check only
  # engages when BASE != HEAD (an actual branch of work to ship).
  git -C "$d" add -A; git -C "$d" commit -qm "feat: behavior change + $profile proof"
}

for profile in eval tool-build feature; do
  A="/tmp/vf-shipgate-$profile-allow"; build "$A" "$profile" 1   # complete proof
  if run_hook "$A"; then pass "[$profile] proof present -> ship-gate ALLOWS the push"; else fail "[$profile] complete proof should ALLOW but the hook BLOCKED"; fi
  B="/tmp/vf-shipgate-$profile-block"; build "$B" "$profile" 0   # no negative-control run
  if run_hook "$B"; then fail "[$profile] missing negative control should BLOCK but the hook ALLOWED"; else pass "[$profile] negative-control run missing -> ship-gate BLOCKS the push"; fi
done

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS (3 profiles x allow+block)"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
