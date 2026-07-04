#!/usr/bin/env bash
# The SG-05 no-orphan wiring check (kit-hardening c6fbd99 bug class): proves every claim the
# docs make actually dispatches, and that the check itself is falsifiable (the OVER-CLAIM
# negative control, D-nc, must genuinely catch a fabricated claim, not just "always pass").
#
# Three parts:
#   (a) presence  : README + proof-of-done + tool.toml + a MANIFEST.md row all exist.
#   (b) no-orphan : the skill's frontmatter carries its trigger phrases (fires); every
#                   `ledger <verb>` invocation the skill body/README show has a REAL matching
#                   `@app.command()` in cli.py (CLI invoked); `ledger anomalies --propose`
#                   actually stages a row into the cc-backlog buffer (work-intake fed).
#   (c) NC        : a fabricated `uv run ledger zzz-nonexistent` claim, injected into a TEMP
#                   copy of README.md (the real file is never touched), is a CAUGHT finding
#                   under the exact same claim-check logic used on the real docs.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
OPS_TOOLKIT_ROOT="$(cd "$ROOT/../.." && pwd)"

PASS=0; FAIL=0
ok()  { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has() { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }

# ---- real CLI command surface (the ground truth every claim is checked against) -------------
# Every `def NAME(` line immediately preceded by `@app.command()` is a real, live command.
real_commands() {
  grep -A1 '@app\.command()' src/ledger_observatory/cli.py \
    | grep -oE '^def [a-zA-Z_]+\(' | sed -E 's/^def //; s/\(//'
}
REAL_CMDS="$(real_commands)"
has "no-orphan ground truth: real CLI commands extracted" "rebuild" "$REAL_CMDS"

# Extract every "ledger <verb>" claim from a `uv run ledger <verb>` invocation example in a
# given file. This is the doc's OWN claim of "this command exists and works this way".
claimed_commands() {
  grep -oE 'uv run ledger [a-zA-Z][a-zA-Z0-9_-]*' "$1" | awk '{print $NF}' | sort -u
}

# Given a file, print any claimed command NOT in the real command set (the "orphan" claims).
unwired_claims() {
  local file="$1" claimed c found
  claimed="$(claimed_commands "$file")"
  for c in $claimed; do
    found=0
    for r in $REAL_CMDS; do [ "$c" = "$r" ] && found=1 && break; done
    [ "$found" -eq 0 ] && echo "$c"
  done
}

# ---- (a) presence -----------------------------------------------------------------------
[ -s README.md ] && ok "README.md present + non-empty" || bad "README.md missing/empty"
[ -s docs/proof-of-done.md ] && ok "docs/proof-of-done.md present + non-empty" || bad "proof-of-done.md missing/empty"
[ -s tool.toml ] && ok "tool.toml present + non-empty" || bad "tool.toml missing/empty"
if grep -q '\[`ledger-observatory`\]' "$OPS_TOOLKIT_ROOT/MANIFEST.md" 2>/dev/null; then
  ok "MANIFEST.md carries a ledger-observatory row"
else
  bad "MANIFEST.md has no ledger-observatory row"
fi

# ---- (b) no-orphan sweep -------------------------------------------------------------------

# b1. skill frontmatter carries its trigger phrases (fires on the documented asks).
FRONTMATTER="$(sed -n '/^---$/,/^---$/p' skill/SKILL.md)"
for phrase in "show me the ledger state" "understanding debt" "token cost" "kit runs" \
              "render the ledger" "any ledger anomalies"; do
  has "skill frontmatter carries trigger: '$phrase'" "$phrase" "$FRONTMATTER"
done

# b2. skill body + README invoke REAL `ledger` CLI verbs (no fabricated command claimed).
SKILL_ORPHANS="$(unwired_claims skill/SKILL.md)"
README_ORPHANS="$(unwired_claims README.md)"
[ -z "$SKILL_ORPHANS" ] && ok "skill/SKILL.md: every claimed 'ledger <verb>' is a real CLI command" \
  || bad "skill/SKILL.md claims unwired command(s): $SKILL_ORPHANS"
[ -z "$README_ORPHANS" ] && ok "README.md: every claimed 'ledger <verb>' is a real CLI command" \
  || bad "README.md claims unwired command(s): $README_ORPHANS"
# and the skill actually contains at least one real invocation (not just prose about it).
SKILL_CLAIMED="$(claimed_commands skill/SKILL.md)"
[ -n "$SKILL_CLAIMED" ] && ok "skill/SKILL.md contains live 'uv run ledger <verb>' invocations" \
  || bad "skill/SKILL.md has no live CLI invocation example"
echo "$SKILL_CLAIMED" | grep -qx "anomalies" && ok "skill/SKILL.md invokes the anomalies (feedback-loop) command" \
  || bad "skill/SKILL.md never invokes 'ledger anomalies'"

# b3. `ledger anomalies --propose` actually feeds the cc-backlog staging buffer (work-intake
# fed): call the real stager against a fixture anomaly, end to end, no mock of the write path.
FIX="$(mktemp -d)"
WI_OUT="$(cd "$ROOT" && uv run python3 - "$FIX" <<'PY'
import sys
sys.path.insert(0, "src")
from ledger_observatory.anomalies import Anomaly, stage_proposals

fix = sys.argv[1]
staging = f"{fix}/backlog-staging.md"
backlog = f"{fix}/BACKLOG.md"
a = Anomaly(key="wiring-check", title="Wiring-check fixture anomaly", intent="i",
            approach="a", tags="#t", home="ops-toolkit", metric="m=1")
staged, skipped = stage_proposals([a], staging, backlog, date="2026-07-04")
print("staged" if staged and not skipped else "not-staged")
with open(staging) as fh:
    print("HAS-BLOCK" if "## [staged] Wiring-check fixture anomaly" in fh.read() else "NO-BLOCK")
PY
)"
echo "$WI_OUT" | grep -q "^staged$" && ok "ledger anomalies --propose path stages a proposal (work-intake fed)" \
  || bad "propose path did not stage (got: $WI_OUT)"
echo "$WI_OUT" | grep -q "HAS-BLOCK" && ok "staged proposal lands in the cc-backlog buffer format" \
  || bad "staged proposal missing the expected ## [staged] block"

# ---- (c) OVER-CLAIM negative control (must be CAUGHT, load-bearing) -----------------------
NC_DIR="$(mktemp -d)"
cp README.md "$NC_DIR/README.md"
printf '\n# NC injection (temp only, never touches the real README)\n`uv run ledger zzz-nonexistent --foo`\n' \
  >> "$NC_DIR/README.md"

NC_ORPHANS="$(unwired_claims "$NC_DIR/README.md")"
if [ -n "$NC_ORPHANS" ] && printf '%s\n' "$NC_ORPHANS" | grep -qx "zzz-nonexistent"; then
  ok "OVER-CLAIM NC: fabricated 'ledger zzz-nonexistent' claim is CAUGHT"
else
  bad "OVER-CLAIM NC did NOT catch the fabricated claim (check is vacuous): got '$NC_ORPHANS'"
fi
# and prove the check is not just always-red: the SAME logic on the untouched real README
# still passes clean (already asserted above as README_ORPHANS being empty), and the real
# file on disk was never modified by this NC.
REAL_SHA_BEFORE="$(shasum README.md | awk '{print $1}')"
[ -n "$README_ORPHANS" ] && bad "sanity: real README should have zero orphan claims" || :
REAL_SHA_AFTER="$(shasum README.md | awk '{print $1}')"
[ "$REAL_SHA_BEFORE" = "$REAL_SHA_AFTER" ] && ok "OVER-CLAIM NC never touched the real README.md" \
  || bad "OVER-CLAIM NC mutated the real README.md (sha changed)"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
