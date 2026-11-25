#!/usr/bin/env bash
# test-stamp-rules.sh -- the rules docs group of the team stamp: AGENTS.md, docs/TEAM-WORKFLOW.md,
# docs/verification/README.md and .kit.toml, stamped into a scratch repo and read back.
#
# Parity rule (the one scripts/pr-shape.sh in a stamped repo also applies): every heading of
# AGENTS.md, at any level, has a link to its anchor in docs/TEAM-WORKFLOW.md. The anchor is the
# heading lowercased, every character outside a-z 0-9 space hyphen dropped, spaces turned into
# hyphens, and the link reads [<heading text>](../AGENTS.md#<anchor>). Keep AGENTS.md headings
# plain words so this rule stays a simple list comparison.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-rules.XXXXXX")" || exit 1
KIT_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'
KIT_URL='https://github.com/dwarvesf/dwarves-kit'
LIMIT='A person who merges from the GitHub site passes everything, on a plan without branch protection.'
TRUST='Claude Code uses a hook from `.claude/settings.json` even in a folder not yet trusted'
EM="$(printf '\342\200\224')"; EN="$(printf '\342\200\223')"

newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9 -' | tr ' ' '-'; }
headings() { # headings <file>: every heading text outside a code fence, one per line
  awk '/^```/ {f = !f; next} !f && /^#+ / {sub(/^#+ +/, ""); print}' "$1"
}

# 1. stamp with default-looking values and with non-default values
R1="$(newrepo)"
bash lib/stamp.sh --only rules --default-branch main "$R1" >"$WORK/s1.out" 2>&1
expect "stamp the rules group, defaults" [ $? -eq 0 ]
R2="$(newrepo)"
bash lib/stamp.sh --only rules --default-branch master --tags app,lib --product-paths app/,pkg/ \
  --door-paths 'docs/legal/*,protocol/*' --door-approver reviewer "$R2" >"$WORK/s2.out" 2>&1
expect "stamp the rules group, custom values" [ $? -eq 0 ]

for f in AGENTS.md docs/TEAM-WORKFLOW.md docs/verification/README.md .kit.toml; do
  expect "$f is written" [ -f "$R1/$f" ]
done
expect "the lock lists the four files" bash -c "[ \$(awk '\$1==\"file\"' '$R1/.claude/team-stamp.lock' | wc -l | tr -d ' ') -eq 4 ]"

A="$R2/AGENTS.md"; T="$R2/docs/TEAM-WORKFLOW.md"; P="$R2/docs/verification/README.md"; K="$R2/.kit.toml"

# 2. AGENTS.md shape
expect "AGENTS.md line 1 is the kit marker, read from the adopt pointer" \
  bash -c "[ \"\$(head -n 1 '$A')\" = \"\$(head -n 1 '$ROOT/lib/adopt/AGENTS.pointer.md')\" ] && head -n 1 '$A' | grep -q '^<!-- kit:agents-pointer'"
for h in Commands Playbooks Lessons "Team rules" Never "Optional kit"; do
  expect "AGENTS.md has the section: $h" grep -qx "## $h" "$A"
done
for h in "Work queue" "What a PR carries" Proof Changelog "One-way doors" Merge Checks Limits; do
  expect "AGENTS.md has the team rule: $h" grep -qx "### $h" "$A"
done
expect "the closing section is Optional kit" bash -c "[ \"\$(grep '^## ' '$A' | tail -n 1)\" = '## Optional kit' ]"
expect "the public URL appears once, in the closing section" \
  bash -c "[ \$(grep -cF '$KIT_URL' '$A') -eq 1 ] && awk '/^## Optional kit\$/ {f=1} f && index(\$0, \"$KIT_URL\") {found=1} END {exit !found}' '$A'"
expect "the kit is named nowhere in AGENTS.md outside line 1 and the closing section" \
  bash -c "! awk 'NR>1 && /^## Optional kit\$/ {exit} NR>1 {print}' '$A' | grep -qi 'dwarves-kit\|kit:'"
for s in scripts/pr-merge.sh scripts/check.sh scripts/negctl.sh scripts/pr-shape.sh scripts/check-owners.sh scripts/issues-from-rows.sh scripts/release-notes.sh scripts/team-digest.sh scripts/agent-guard.sh scripts/agent-lessons.sh; do
  expect "AGENTS.md names $s" grep -qF "$s" "$A"
done
expect "AGENTS.md names the ship-pr playbook" grep -qF '.claude/skills/ship-pr/SKILL.md' "$A"
expect "the Never section is not empty" bash -c "[ \$(awk '/^## Never\$/ {f=1; next} /^## / {f=0} f && /^- /' '$A' | wc -l | tr -d ' ') -ge 3 ]"

# 3. both docs: the limit sentence, the trust step, the optional-kit section
for f in "$A" "$T"; do
  b="${f#"$R2"/}"
  expect "$b carries the limit sentence" grep -qF "$LIMIT" "$f"
  expect "$b carries the trust-the-folder step" grep -qF "$TRUST" "$f"
  expect "$b has an Optional kit section" grep -qx '## Optional kit' "$f"
  expect "$b says nothing in it needs the kit" grep -Eq 'Nothing (above|here) needs' "$f"
done
expect "TEAM-WORKFLOW.md names no kit URL and no kit path" bash -c "! grep -qF '$KIT_URL' '$T'"

# 4. parity: every AGENTS.md heading has its anchor link in TEAM-WORKFLOW.md, and no link points nowhere
nh=0; missing=0
while IFS= read -r h; do
  [ -n "$h" ] || continue
  nh=$((nh + 1))
  s="$(slug "$h")"
  grep -qF "[$h](../AGENTS.md#$s)" "$T" || { missing=$((missing + 1)); echo "    no anchor link for heading: $h"; }
done < <(headings "$A")
expect "AGENTS.md has headings to compare ($nh)" [ "$nh" -ge 12 ]
expect "every AGENTS.md heading has its anchor in TEAM-WORKFLOW.md" [ "$missing" -eq 0 ]
dups="$(headings "$A" | while IFS= read -r h; do slug "$h"; echo; done | grep -v '^$' | sort | uniq -d)"
expect "no two AGENTS.md headings share an anchor" [ -z "$dups" ]
stale=0
slugs="$(headings "$A" | while IFS= read -r h; do slug "$h"; echo; done)"
for a in $(grep -o '(\.\./AGENTS\.md#[a-z0-9-]*)' "$T" | sed 's/.*#//; s/)//' | sort -u); do
  printf '%s\n' "$slugs" | grep -qx "$a" || { stale=$((stale + 1)); echo "    TEAM-WORKFLOW.md links to a missing AGENTS.md anchor: $a"; }
done
expect "TEAM-WORKFLOW.md links no AGENTS.md anchor that does not exist" [ "$stale" -eq 0 ]
expect "the parity rule is stated in this test's header" grep -q '^# Parity rule' "$ROOT/tests/test-stamp-rules.sh"

# 5. relative links in the generated docs resolve
badlinks=0
for f in "$A" "$T" "$P"; do
  d="$(dirname "$f")"
  for l in $(grep -o '](\([^)#]*\)' "$f" | sed 's/^](//' | grep -v '^[a-z]*:' | grep -v '^$' | sort -u); do
    [ -e "$d/$l" ] || { badlinks=$((badlinks + 1)); echo "    ${f#"$R2"/}: dead link $l"; }
  done
done
expect "every relative link in the three docs reaches a file this group writes" [ "$badlinks" -eq 0 ]

# 6. the proof guide
expect "the proof guide says one file per PR" grep -q '^## One file per PR' "$P"
for w in 'Command:' 'Output:' 'Exit:' 'NEGATIVE CONTROL' 'Verdict:'; do
  expect "the proof guide states $w" grep -qF "$w" "$P"
done
expect "the proof guide shape block runs Command, Output, Exit, Verdict in order" \
  bash -c "awk '/^\`\`\`/ {n++; next} n==1 {print}' '$P' | awk '/^Command:/ {a=NR} /^Output:/ {b=NR} /^Exit:/ {c=NR} /^Verdict:/ {d=NR} END {exit !(a && b>a && c>b && d>c)}'"
expect "the proof guide shape block has a line right after Output:" \
  bash -c "awk '/^\`\`\`/ {n++; next} n==1 {print}' '$P' | awk 'f && NF {ok=1} /^Output:/ {f=1} END {exit !ok}'"
expect "the proof guide names the red verdict form" grep -qF 'Verdict: RED, as expected' "$P"
expect "the proof guide says scripts/negctl.sh prints the block" grep -qF 'scripts/negctl.sh' "$P"
expect "the proof guide says the README is never a proof" grep -qF 'never a proof' "$P"

# 7. .kit.toml
expect ".kit.toml sets proof_of_done = true" grep -qx 'proof_of_done = true' "$K"
expect ".kit.toml sets lane_gates = false" grep -qx 'lane_gates = false' "$K"
expect ".kit.toml has a [gate] table" grep -qx '\[gate\]' "$K"
expect ".kit.toml comments name no kit path" bash -c "! grep -Eq '$KIT_PATTERN|~/|/lib/' '$K'"
expect ".kit.toml keeps no other gate key on" bash -c "[ \$(grep -Ec '^[a-z_]+ = ' '$K') -eq 2 ]"

# 7b. the review rules for the harness's own files, the workflow limit and the runner advice
for f in "$A" "$T"; do
  b="${f#"$R2"/}"
  expect "$b lists the harness's own files as doors" bash -c "for p in '.github/workflows/' 'scripts/' '.claude/' 'OWNERS.md' 'AGENTS.md' 'docs/TEAM-WORKFLOW.md' '.kit.toml'; do grep -qF \"\$p\" '$f' || exit 1; done; grep -qF 'always doors' '$f'"
  expect "$b warns that hook settings, the lessons index and agent scripts run in every teammate's next session" bash -c "grep -qF 'hook settings' '$f' && grep -qF 'lessons index' '$f' && grep -qF 'agent-*' '$f' && grep -qF 'next session' '$f'"
  expect "$b says the first stamp pull request is read by a second person and merged by hand" bash -c "grep -qF 'merged by hand' '$f' && grep -qF 'second person reads it' '$f'"
  expect "$b says a pull request can edit the workflow file and the merge guard binds it" bash -c "grep -qF 'edit' '$f' && grep -qF 'ci.yml' '$f' || grep -qF 'workflow file' '$f'"
  expect "$b says to use an ephemeral runner or a container job, not for public repos" bash -c "grep -qF 'ephemeral runner or a container job' '$f' && grep -qF 'Not for public repos' '$f'"
done
expect "AGENTS.md says never to run a pull request's copy of a script" grep -qF "never run a pull request's copy of a script" "$A"
expect "AGENTS.md names the conflict fix gh pr update-branch" grep -qF 'gh pr update-branch' "$A"

# 8. values render, nothing is left over
expect "custom default branch reaches AGENTS.md" grep -qF '`master`' "$A"
expect "custom tags reach AGENTS.md" grep -qF 'app: lib: dev:' "$A"
expect "custom tags reach TEAM-WORKFLOW.md" grep -qF 'app,lib,dev' "$T"
expect "custom product paths reach both docs" bash -c "grep -qF 'app/,pkg/' '$A' && grep -qF 'app/,pkg/' '$T'"
expect "door paths reach both docs" bash -c "grep -qF 'docs/legal/*,protocol/*' '$A' && grep -qF 'docs/legal/*,protocol/*' '$T'"
expect "the door approver reaches both docs" bash -c "grep -qF '| reviewer |' '$A' && grep -qF '| reviewer |' '$T'"
expect "the default branch word 'main' appears nowhere with custom values" bash -c "! grep -qw 'main' '$A' '$T' '$P'"
expect "default values render too" bash -c "grep -qF '\`main\`' '$R1/AGENTS.md' && grep -qF 'product,dev' '$R1/docs/TEAM-WORKFLOW.md'"
expect "an empty door list still renders the door table" bash -c "grep -qF 'Paths the merge guard checks' '$R1/AGENTS.md' && grep -qF 'Who says the second yes' '$R1/AGENTS.md'"
for r in "$R1" "$R2"; do
  expect "no {{KEY}} is left in $(basename "$r")" bash -c "! grep -rqE '\{\{[A-Za-z_]+\}\}' '$r/AGENTS.md' '$r/docs' '$r/.kit.toml'"
done

# 9. hygiene of the generated text
for f in "$A" "$T" "$P" "$K"; do
  b="${f#"$R2"/}"
  expect "$b has no em or en dash" bash -c "! grep -qF -e '$EM' -e '$EN' '$f'"
  expect "$b names no kit path or home path" bash -c "! grep -En '$KIT_PATTERN' '$f' | grep -v '^1:<!-- kit:agents-pointer' | grep -q ."
  expect "$b has no bare 40 or 64 digit hex string" bash -c "! grep -Eq '(^|[^0-9a-fA-F])([0-9a-fA-F]{40}|[0-9a-fA-F]{64})([^0-9a-fA-F]|$)' '$f'"
done
for t in AGENTS.md.tpl docs/TEAM-WORKFLOW.md.tpl docs/verification/README.md.tpl .kit.toml; do
  expect "template $t has no em or en dash" bash -c "! grep -qF -e '$EM' -e '$EN' '$ROOT/templates/team-stamp/files/$t'"
done

# 10. idempotent, and a repo edit is left alone
out="$(bash lib/stamp.sh --only rules "$R2" 2>&1)"
expect "a second run prints only unchanged" bash -c "! printf '%s\n' \"\$1\" | grep -Evq '^(unchanged|using): ' " _ "$out"
printf '\nA repo line.\n' >> "$A"
out="$(bash lib/stamp.sh --only rules "$R2" 2>&1)"
expect "an edited AGENTS.md is left alone" bash -c "printf '%s\n' \"\$1\" | grep -q 'edited (left alone): AGENTS.md' && tail -n 1 '$A' | grep -q 'A repo line.'" _ "$out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
