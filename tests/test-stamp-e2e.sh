#!/usr/bin/env bash
# test-stamp-e2e.sh -- every group stamped together: the file set, a kit-free pass over every
# generated test, the named scripts, the owners check, a fixture PR through the stamped checks,
# the scan-safe digests, and the privacy scan of the whole branch.
#   STAMP_DENYLIST_FILE=<file, one string per line, kept outside the repo> bash tests/test-stamp-e2e.sh
# The generic leak scan always runs. The denylist scan runs when STAMP_DENYLIST_FILE is set and
# prints one SKIP line otherwise; the release check sets it.
# shellcheck disable=SC2054,SC2046
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-e2e.XXXXXX")" || exit 1
MANIFESTS="$ROOT/templates/team-stamp/manifest.d"
VALUES=(--default-branch master --owner testowner --tags app,lib --product-paths app/,pkg/
  --door-paths 'docs/legal/*' --door-approver reviewer --decision-tag decision --board-file docs/BOARD.md)

# manifest targets, one per line
manifest_targets() { cat "$MANIFESTS"/*.tsv | awk -F'\t' '/^#/ || NF < 5 {next} {print $3}' | LC_ALL=C sort; }
manifest_targets > "$WORK/manifest.txt"

# ---- 1. full stamp, idempotence, check, defaults from origin/HEAD ----
D="$WORK/default"; mkdir -p "$D"; git -C "$D" init -q -b main 2>/dev/null
git -C "$D" remote add origin https://example.invalid/x.git
git -C "$D" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
out="$(bash lib/stamp.sh --owner alice "$D" 2>&1)"; rc=$?
expect "a full stamp with only --owner exits 0 (the branch comes from origin/HEAD)" [ "$rc" -eq 0 ]
created="$(printf '%s\n' "$out" | grep -c '^created: ')"
expect "every manifest row is written (created + merged = rows)" bash -c "[ $((created + $(printf '%s\n' "$out" | grep -c '^merged: '))) -eq $(wc -l < "$WORK/manifest.txt" | tr -d ' ') ]"
out2="$(bash lib/stamp.sh "$D" 2>&1)"
expect "a second run prints only unchanged" bash -c "[ \$(printf '%s\n' \"\$1\" | grep -vc '^unchanged: ') -eq 0 ]" _ "$out2"
bash lib/stamp.sh --check "$D" >/dev/null 2>&1; expect "--check exits 0 right after" [ "$?" -eq 0 ]
expect "the default branch reached the guard" grep -q 'default_branch="main"' "$D/scripts/agent-guard.sh"

# ---- 2. the non-default stamp used by everything below ----
S="$WORK/repo"; mkdir -p "$S"; git -C "$S" init -q -b master 2>/dev/null
git -C "$S" config user.name tester; git -C "$S" config user.email tester@example.invalid
bash lib/stamp.sh "${VALUES[@]}" "$S" >/dev/null 2>&1
expect "the non-default stamp exits 0" [ -f "$S/.claude/team-stamp.lock" ]

if command -v actionlint >/dev/null 2>&1; then
  expect "actionlint accepts the rendered workflow" bash -c "cd '$S' && actionlint .github/workflows/ci.yml"
else
  ok "actionlint not installed: skipped"
fi
expect "the workflow runs on [self-hosted] and names no hosted runner" bash -c "grep -q 'runs-on: \\[self-hosted\\]' '$S/.github/workflows/ci.yml' && ! grep -Eq 'ubuntu-|macos-|windows-' '$S/.github/workflows/ci.yml'"
# AC1: the file set equals the manifest, the lock, and the spec's table
awk '$1=="file"{print $2}' "$S/.claude/team-stamp.lock" | LC_ALL=C sort > "$WORK/lock.txt"
expect "the lock lists exactly the manifest targets" cmp -s "$WORK/manifest.txt" "$WORK/lock.txt"
missing=0
while IFS= read -r t; do [ -e "$S/$t" ] || { missing=1; echo "    missing $t"; }; done < "$WORK/manifest.txt"
expect "every manifest target exists in the stamped repo" [ "$missing" -eq 0 ]
extra="$(cd "$S" && find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort | grep -vxF -f "$WORK/manifest.txt" | grep -v '^\.claude/team-stamp\.lock$')"
expect "the stamp writes nothing beyond the manifest and the lock" [ -z "$extra" ]
# spec table: the first backticked path of the target column
SPEC=docs/specs/SPEC-425-team-stamp.md
awk -F'|' '/^\| [0-9]+ \|/ {print $4}' "$SPEC" | grep -o '`[^`]*`' | head -n 200 | tr -d '`' | grep -E '^[A-Za-z0-9_.@/-]+$' | grep -vE '^\.claude/memory/\*|^\*' > "$WORK/spec-targets.txt"
spec_missing=""
while IFS= read -r t; do
  case "$t" in */\*) continue;; esac
  grep -qxF "$t" "$WORK/manifest.txt" || spec_missing="$spec_missing $t"
done < "$WORK/spec-targets.txt"
expect "every path in the spec's file table is a manifest target" bash -c "[ -z \"\$1\" ]" _ "$spec_missing"
[ -z "$spec_missing" ] || echo "    not in the manifest:$spec_missing"
outside="$(grep -vxF -f "$WORK/spec-targets.txt" "$WORK/manifest.txt" | grep -vE '^scripts/test-[a-z-]+\.sh$|^\.claude/memory/[A-Za-z-]+\.md$')"
expect "the manifest holds nothing the spec's table does not name (tests and lesson notes aside)" bash -c "[ -z \"\$1\" ]" _ "$outside"
[ -z "$outside" ] || echo "    not in the spec table: $(printf '%s' "$outside" | tr '\n' ' ')"
modes_bad=0
for t in $(grep -E '^scripts/.*\.sh$' "$WORK/manifest.txt"); do [ -x "$S/$t" ] || { modes_bad=1; echo "    not executable: $t"; }; done
expect "every generated script is executable" [ "$modes_bad" -eq 0 ]

# AC2, AC3: every generated test, kit absent, non-default values (the harness stamps and runs them)
bash tests/test-stamp-kitfree.sh all > "$WORK/kitfree.out" 2>&1; krc=$?
ntests="$(grep -c '^scripts/test-' "$WORK/manifest.txt")"
nran="$(grep -c '^ok - kit-free run: scripts/test-' "$WORK/kitfree.out")"
expect "the kit-free harness exits 0" [ "$krc" -eq 0 ]
[ "$krc" -eq 0 ] || sed 's/^/    /' "$WORK/kitfree.out" | grep -iE 'not ok|FAIL' | head -n 8
expect "it ran every generated scripts/test-*.sh ($ntests)" [ "$nran" -eq "$ntests" ]
expect "it found no kit path in any generated file" grep -q 'names a kit path' "$WORK/kitfree.out"

# named scripts in the three rule docs exist in the stamp
names_bad=0
for doc in AGENTS.md docs/TEAM-WORKFLOW.md .claude/skills/ship-pr/SKILL.md; do
  for p in $(grep -oE 'scripts/[A-Za-z0-9_-]+\.sh' "$S/$doc" | sort -u); do
    [ -f "$S/$p" ] || { names_bad=1; echo "    $doc names $p, which does not exist"; }
  done
done
expect "every script the rule docs and the playbook name exists in the stamp" [ "$names_bad" -eq 0 ]
expect "every script a Fix: line in the guard names exists" bash -c "cd '$S' && for p in \$(grep -oE 'scripts/[A-Za-z0-9_-]+\\.sh' scripts/agent-guard.sh | sort -u); do [ -f \"\$p\" ] || exit 1; done"

# ---- 3. owners, on the tracked files of the full stamp ----
git -C "$S" add -A >/dev/null 2>&1
own="$(cd "$S" && bash scripts/check-owners.sh 2>&1)"; orc=$?
expect "check-owners passes on the full stamp" [ "$orc" -eq 0 ]
expect "and it counted every script, test and the workflow" bash -c "[ \$(printf '%s' \"\$1\" | grep -oE '^check-owners: [0-9]+' | grep -oE '[0-9]+') -eq $(grep -cE '^(scripts/.*\.sh|\.github/workflows/.*)$' "$WORK/manifest.txt") ]" _ "$own"

# ---- 4. scan-safe digests and no home path in the staged stamp ----
git -C "$S" diff --cached > "$WORK/staged.diff"
# leaks <file>: lines with a bare hex run, a home path, a secret reference or an email. Allowed:
# a 40-hex pin in `uses: owner/repo@<sha> # v...`, a 64-hex run right after a sha256 marker.
# hexleaks <file>: only the hex shapes; pathleaks <file>: home path, secret reference, email.
hexleaks() {
  sed -E 's/(uses: [A-Za-z0-9._\/-]+@)[0-9a-f]{40}( # v[0-9A-Za-z._-]+)/\1\2/; s/(sha256: |sha256:|sha256=|sha256-|sha256 "|sha256 '"'"')[0-9a-f]{64}//g' "$1" \
    | grep -nE '[0-9a-f]{64}|[0-9a-f]{40}'
}
pathleaks() {
  grep -nE '/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|op://|[A-Za-z0-9._+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}' "$1" \
    | grep -vE '@example\.(invalid|com)|noreply\.github\.com|@v[0-9]'
}
leaks() { hexleaks "$1"; pathleaks "$1"; }
expect "the staged stamp is not empty" [ -s "$WORK/staged.diff" ]
leak_out="$(leaks "$WORK/staged.diff" | cut -c1-120 | head -n 5)"
expect "the staged stamp has no bare hex run, home path, secret reference or email" bash -c "[ -z \"\$1\" ]" _ "$leak_out"
[ -z "$leak_out" ] || printf '    %s\n' "$leak_out"
printf 'x %s\n' "$(printf 'b%.0s' $(seq 1 64))" > "$WORK/bare.txt"
expect "the leak scan flags a bare 64-hex run (self-test)" bash -c "$(declare -f hexleaks); hexleaks '$WORK/bare.txt' >/dev/null"

# ---- 5. a fixture PR built per the stamped rules passes the stamped checks ----
git -C "$S" commit -q -m "chore: stamp the harness"
git -C "$S" update-ref refs/remotes/origin/master HEAD
git -C "$S" checkout -q -b feat/greet
mkdir -p "$S/app"
printf '#!/usr/bin/env bash\ngreet() { echo "hello $1"; }\n' > "$S/app/greet.sh"
printf '#!/usr/bin/env bash\n# shellcheck source=app/greet.sh\ncd "$(dirname "$0")/.." || exit 1\nsource app/greet.sh\n[ "$(greet bob)" = "hello bob" ] || { echo "FAIL greet"; exit 1; }\necho "ok greet"\n' > "$S/app/test-greet.sh"
git -C "$S" add app && git -C "$S" commit -q -m "feat(app): add greet"
nc="$(cd "$S" && bash scripts/negctl.sh "bash app/test-greet.sh" "printf '#!/usr/bin/env bash\ngreet() { echo bye; }\n' > app/greet.sh" 2>&1)"; nrc=$?
expect "the stamped negctl runs green, break, red, restore, green" [ "$nrc" -eq 0 ]
expect "and prints a NEGATIVE CONTROL block with a Verdict: RED line" bash -c "printf '%s\n' \"\$1\" | grep -q '^NEGATIVE CONTROL' && printf '%s\n' \"\$1\" | grep -q '^Verdict: RED'" _ "$nc"
mkdir -p "$S/docs/verification"
{ printf '# Proof: greet\n\nCommand: bash app/test-greet.sh\nExit: 0\nOutput:\nok greet\nVerdict: PASS\n\n'; printf '%s\n' "$nc"; } > "$S/docs/verification/greet.md"
printf '\n- app: add greet\n' >> "$S/CHANGELOG.md"
git -C "$S" add -A && git -C "$S" commit -q -m "docs: proof and changelog for greet"
pr_out="$(cd "$S" && PR_TITLE='feat(app): add greet' PR_BODY='Closes #1' BASE_SHA="$(git rev-parse origin/master)" HEAD_SHA="$(git rev-parse HEAD)" bash scripts/pr-shape.sh 2>&1)"; prc=$?
expect "pr-shape passes the fixture PR" [ "$prc" -eq 0 ]
[ "$prc" -eq 0 ] || printf '%s\n' "$pr_out" | head -n 8 | sed 's/^/    /'
expect "the stamped negctl block is accepted by the stamped proof check" bash -c "printf '%s\n' \"\$1\" | grep -q 'NEGATIVE CONTROL block'" _ "$pr_out"
chk="$(cd "$S" && bash scripts/check.sh --title 'feat(app): add greet' --body 'Closes #1' 2>&1)"; crc=$?
expect "check.sh passes the fixture PR (owners, pr-shape, every script test)" [ "$crc" -eq 0 ]
[ "$crc" -eq 0 ] || printf '%s\n' "$chk" | grep -E 'FAIL|check:|Fix' | head -n 8 | sed 's/^/    /'
# the same PR without its changelog line is refused with the two-line shape
git -C "$S" revert --no-edit HEAD >/dev/null 2>&1 && true
bad="$(cd "$S" && PR_TITLE='feat(app): add greet' PR_BODY='Closes #1' BASE_SHA="$(git rev-parse origin/master)" HEAD_SHA="$(git rev-parse HEAD)" bash scripts/pr-shape.sh 2>&1 >/dev/null)"; brc=$?
expect "without the proof and changelog commit the same PR fails" [ "$brc" -eq 1 ]
expect "and the refusal ends with the rule line then a Fix: line" bash -c "printf '%s\n' \"\$1\" | tail -n 2 | sed -n 2p | grep -q '^Fix: '" _ "$bad"

# ---- 6. privacy: the whole branch, the fixtures, the proof ----
# The generic leak-shape scan always runs and can always fail. The denylist scan runs when
# STAMP_DENYLIST_FILE names a list kept outside the repo; unset, it prints one SKIP line and passes.
base="$(git rev-parse --verify -q origin/master || true)"
# what ships in the templates, the fixtures, the gauntlet fixtures, the proof and this ticket's records
{ cat $(find templates/team-stamp tests/fixtures/team-stamp tests/gauntlet/team-stamp -type f 2>/dev/null)
  [ -f docs/verification/team-stamp.md ] && cat docs/verification/team-stamp.md
  for d in docs/verification/gauntlet/*team-stamp*; do [ -d "$d" ] && cat $(find "$d" -type f 2>/dev/null); done
} > "$WORK/shipped.txt" 2>/dev/null
expect "the shipped files (templates, fixtures, proof, gauntlet record) are not empty" [ -s "$WORK/shipped.txt" ]
leak_ship="$(leaks "$WORK/shipped.txt" | cut -c1-100 | head -n 5)"
expect "the templates, fixtures and proof have no bare hex run, home path, secret reference or email" bash -c "[ -z \"\$1\" ]" _ "$leak_ship"
[ -z "$leak_ship" ] || printf '    %s\n' "$leak_ship"
if [ -n "$base" ]; then
  { git diff -U0 "$base" -- . ':!docs/reference/FEATURES.md' | grep '^+' | grep -v '^+++'
    git log "$base"..HEAD --format='%B'
    for f in $(git ls-files --others --exclude-standard); do cat "$f"; done
  } > "$WORK/branch.txt" 2>/dev/null
  leak_branch="$(hexleaks "$WORK/branch.txt" | cut -c1-100 | head -n 5)"
  expect "the branch diff has no bare hex run" bash -c "[ -z \"\$1\" ]" _ "$leak_branch"
  [ -z "$leak_branch" ] || printf '    %s\n' "$leak_branch"
else
  echo "SKIP - no origin/master to diff the branch against: the branch-diff hex scan did not run"
fi
if [ -z "${STAMP_DENYLIST_FILE:-}" ]; then
  echo "SKIP - STAMP_DENYLIST_FILE is unset: the denylist scan did not run (the release check sets it)"
elif [ ! -f "$STAMP_DENYLIST_FILE" ]; then
  no "STAMP_DENYLIST_FILE does not name a file"
else
  if [ -n "$base" ]; then
    hits="$(grep -cF -f "$STAMP_DENYLIST_FILE" "$WORK/branch.txt")"
    expect "no denylist string appears in the branch ($hits hits)" [ "$hits" -eq 0 ]
  fi
  gen_hits="$(grep -rlF -f "$STAMP_DENYLIST_FILE" "$S" --exclude-dir=.git 2>/dev/null | wc -l | tr -d ' ')"
  expect "no denylist string appears in a stamped repo ($gen_hits files)" [ "$gen_hits" -eq 0 ]
  ship_hits="$(grep -cF -f "$STAMP_DENYLIST_FILE" "$WORK/shipped.txt")"
  expect "no denylist string appears in the templates, fixtures, proof or gauntlet record ($ship_hits hits)" [ "$ship_hits" -eq 0 ]
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
