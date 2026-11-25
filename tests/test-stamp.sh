#!/usr/bin/env bash
# test-stamp.sh -- lib/stamp.sh engine: write, idempotence, never overwrite, drift, refresh, take,
# the kit-path scan, the settings merge, values and refusals. Runs against the fixture tree.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { # expect <label> <command...>
  local label="$1"; shift
  if "$@"; then ok "$label"; else no "$label"; fi
}

export STAMP_TEMPLATES="$ROOT/tests/fixtures/team-stamp"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp.XXXXXX")" || exit 1
STAMP="bash $ROOT/lib/stamp.sh"
FLAGS="--default-branch main --owner alice"

newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
# run <repo> <args...>: stdout+stderr in $OUT, status in $RC
run() { local repo="$1"; shift; OUT="$($STAMP "$@" "$repo" 2>&1)"; RC=$?; }
tree_sum() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while read -r f; do printf '%s ' "$f"; cat "$f" | cksum; done) | cksum; }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
hasre() { printf '%s\n' "$OUT" | grep -qE -- "$1"; }
line_after() { # line_after <rule-prefix> <next-prefix>: the line right after a rule line starts with <next-prefix>
  printf '%s\n' "$OUT" | awk -v a="$1" -v b="$2" 'index($0,a)==1 {getline nx; if (index(nx,b)==1) f=1} END{exit !f}'
}
fixture_copy() { local d="$WORK/tpl.$RANDOM"; cp -R "$ROOT/tests/fixtures/team-stamp" "$d"; echo "$d"; }

# 1. fresh stamp
R="$(newrepo)"
run "$R" $FLAGS
expect "fresh stamp exits 0" [ "$RC" -eq 0 ]
expect "fresh stamp prints created for each file" bash -c "[ \$(printf '%s\n' \"\$1\" | grep -c '^created: ') -eq 8 ]" _ "$OUT"
expect "settings.json is merged, not created" has "merged: .claude/settings.json"
expect "all manifest groups are written (second group too)" [ -f "$R/docs/second.txt" ]
expect "a 0755 row is executable" [ -x "$R/scripts/hello.sh" ]
expect "a 0644 row is not executable" [ ! -x "$R/README.md" ]
expect "values render" grep -q "Default branch: main" "$R/README.md"
expect "the owner renders" grep -q "Owner: alice" "$R/README.md"
expect "no {{KEY}} is left in any file" bash -c "! grep -rE '\{\{[A-Z_]+\}\}' '$R' --exclude-dir=.git"
expect "the kit marker is line 1 of the pointer" bash -c "[ \"\$(head -n 1 '$R/AGENTS.md')\" = \"\$(head -n 1 '$ROOT/lib/adopt/AGENTS.pointer.md')\" ]"
expect "a hook row writes the merged target list" grep -q -- "- docs/second.txt" "$R/TARGETS.md"
expect "derived ERE renders" grep -q '^product: \^(src/)$' "$R/docs/second.txt"
expect "an empty door list renders an empty array body" grep -qxF 'door array: ()' "$R/docs/second.txt"
expect "the decision tag defaults" grep -qxF 'decision tag: #decision' "$R/docs/second.txt"
expect "the lock records values and one hash per file" bash -c "grep -q '^value OWNER alice' '$R/.claude/team-stamp.lock' && [ \$(grep -c '^file ' '$R/.claude/team-stamp.lock') -eq 9 ]"

# 2. second run is a no-op
before="$(tree_sum "$R")"
run "$R"
expect "second run (no flags) exits 0" [ "$RC" -eq 0 ]
expect "second run prints only unchanged" bash -c "[ \$(printf '%s\n' \"\$1\" | grep -Evc '^(unchanged|using): ') -eq 0 ]" _ "$OUT"
expect "second run changes no byte" [ "$before" = "$(tree_sum "$R")" ]

# 2b. seed-once and hook rows are repo-owned after the first write
printf 'my owner table\n' > "$R/OWNERS.md"; printf 'my targets\n' > "$R/TARGETS.md"
run "$R"
expect "an edited seed file is unchanged, never drift-checked" has "unchanged: OWNERS.md"
expect "an edited hook file is unchanged too" has "unchanged: TARGETS.md"
expect "and the edit stays" bash -c "[ \"\$(cat '$R/OWNERS.md')\" = 'my owner table' ]"
run "$R" --check; expect "check is clean with edited repo-owned files" [ "$RC" -eq 0 ]
mv "$R/OWNERS.md" "$WORK/OWNERS.md.moved"; run "$R"
expect "a deleted seed file is created again" has "created: OWNERS.md"
run "$R" --take OWNERS.md
expect "take refuses a seeded file" has "seeded once and then belongs to the repo"
R2b="$(newrepo)"; run "$R2b" --only fixture $FLAGS
expect "--only keeps the merged target list for a hook" grep -q -- "- docs/second.txt" "$R2b/TARGETS.md"

# 3. dry run and check
R2="$(newrepo)"
run "$R2" --dry-run $FLAGS
expect "dry run prints would create" has "would create: README.md"
expect "dry run writes nothing" bash -c "[ -z \"\$(ls -A '$R2' | grep -v '^.git\$')\" ]"
run "$R2" --check $FLAGS
expect "check on an unstamped repo exits 1" [ "$RC" -eq 1 ]
run "$R" --check
expect "check on a clean stamp exits 0" [ "$RC" -eq 0 ]

# 4. never overwrites an edited file
printf 'my own words\n' >> "$R/README.md"
sum_readme="$(cksum < "$R/README.md")"
run "$R"
expect "an edited file is reported" hasre '^edited \(left alone\): README.md \([0-9]+ lines differ\)'
expect "an edited file is left byte for byte" [ "$sum_readme" = "$(cksum < "$R/README.md")" ]
run "$R"; expect "still left alone on the next run" has "edited (left alone): README.md"
run "$R" --check; expect "check exits 1 with an edited file" [ "$RC" -eq 1 ]

# 5. a pre-existing file the stamp never wrote
R3="$(newrepo)"
printf 'repo rules\n' > "$R3/AGENTS.md"
run "$R3" $FLAGS
expect "a pre-existing different file is left alone" bash -c "[ \"\$(cat '$R3/AGENTS.md')\" = 'repo rules' ]"
expect "it is reported as not written by stamp" has "not written by stamp"
R3b="$(newrepo)"
cp "$R/scripts/hello.sh" /dev/null
mkdir -p "$R3b/scripts"; printf '#!/usr/bin/env bash\necho hello\n' > "$R3b/scripts/hello.sh"
run "$R3b" $FLAGS
expect "a pre-existing identical file counts as unchanged and enters the lock" bash -c "grep -q '^file scripts/hello.sh ' '$R3b/.claude/team-stamp.lock'"

# 6. a symlink at a target is refused, nothing written
R4="$(newrepo)"; OUTSIDE="$WORK/outside.txt"; echo outside > "$OUTSIDE"
ln -s "$OUTSIDE" "$R4/README.md"
run "$R4" $FLAGS
expect "a symlinked target refuses the run" [ "$RC" -eq 1 ]
expect "the refusal is two lines, rule then Fix" line_after "stamp: refusing" "Fix:"
expect "nothing was written" bash -c "[ ! -e '$R4/AGENTS.md' ] && [ ! -e '$R4/.claude' ] && [ \"\$(cat '$OUTSIDE')\" = outside ]"

# 7. a file the lock lists is gone: missing, not re-created
rm_target="$R/docs/second.txt"; mv "$rm_target" "$WORK/second.txt.moved"
run "$R"
expect "a deleted stamped file is reported missing" has "missing: docs/second.txt"
expect "and is not re-created" [ ! -e "$rm_target" ]
run "$R" --check; expect "check exits 1 on a missing file" [ "$RC" -eq 1 ]
mv "$WORK/second.txt.moved" "$rm_target"

# 8. an older stamp: template changed, repo did not edit
TPL="$(fixture_copy)"
R5="$(newrepo)"
STAMP_TEMPLATES="$TPL" run "$R5" $FLAGS
printf 'Added by a newer template\n' >> "$TPL/files/second.txt"
before="$(tree_sum "$R5")"
STAMP_TEMPLATES="$TPL" run "$R5"
expect "a changed template over an unedited file is an older stamp" has "older stamp (run --refresh): docs/second.txt"
expect "a default run does not touch it" [ "$before" = "$(tree_sum "$R5")" ]
STAMP_TEMPLATES="$TPL" run "$R5" --refresh
expect "refresh prints one diff with the added line" has "+Added by a newer template"
expect "refresh names the --take fix" has "Fix: bash lib/stamp.sh --take docs/second.txt"
expect "refresh writes nothing" [ "$before" = "$(tree_sum "$R5")" ]

# 9. take: an unedited older file is replaced and the old copy is kept
STAMP_TEMPLATES="$TPL" run "$R5" --take docs/second.txt
expect "take exits 0" [ "$RC" -eq 0 ]
expect "take replaced the file" grep -q "Added by a newer template" "$R5/docs/second.txt"
expect "take kept the old copy as .orig" bash -c "grep -q '^door:' '$R5/docs/second.txt.orig' && ! grep -q 'Added by a newer' '$R5/docs/second.txt.orig'"
STAMP_TEMPLATES="$TPL" run "$R5"
expect "after take the file is unchanged again" has "unchanged: docs/second.txt"

# 10. take on an edited file is refused, diff printed, file untouched
printf 'Added by a newer template\nand more\n' >> "$TPL/files/README.md.tpl"
printf 'edited line\n' >> "$R5/README.md"
sum5="$(cksum < "$R5/README.md")"
STAMP_TEMPLATES="$TPL" run "$R5" --take README.md
expect "take on an edited file exits 1" [ "$RC" -eq 1 ]
expect "take prints the diff to apply" has "+and more"
expect "take refuses with the apply-by-hand fix" line_after "stamp: README.md was edited" "Fix: apply the diff above by hand"
expect "take left the edited file alone" [ "$sum5" = "$(cksum < "$R5/README.md")" ]
STAMP_TEMPLATES="$TPL" run "$R5" --take scripts/nope.sh
expect "take on a path outside the manifest is refused" [ "$RC" -eq 1 ]

# 11. take swaps adopt's kit pointer for the stamp's file, and only that
R6="$(newrepo)"
cp "$ROOT/lib/adopt/AGENTS.pointer.md" "$R6/AGENTS.md"
run "$R6" $FLAGS
expect "an adopt pointer in AGENTS.md is left by a default run" cmp -s "$ROOT/lib/adopt/AGENTS.pointer.md" "$R6/AGENTS.md"
run "$R6" --take AGENTS.md
expect "take replaces a known kit pointer" bash -c "grep -q 'Fixture rules' '$R6/AGENTS.md' && cmp -s '$ROOT/lib/adopt/AGENTS.pointer.md' '$R6/AGENTS.md.orig'"

# 11b. adopt interplay: .kit.toml drift line, foreign kit hooks, adopt's proof marker
R6b="$(newrepo)"
printf '[gate]\nlane_gates = true\n' > "$R6b/.kit.toml"
run "$R6b" $FLAGS
expect "a .kit.toml with lane_gates = true is left alone" bash -c "grep -q 'lane_gates = true' '$R6b/.kit.toml'"
expect "and gets a two-line drift report" line_after "stamp: .kit.toml sets lane_gates = true" "Fix: set lane_gates = false in .kit.toml"
run "$R6b" --check; expect "check exits 1 on that drift" [ "$RC" -eq 1 ]
R6c="$(newrepo)"; mkdir -p "$R6c/.claude"
echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash $HOME/.claude/dwarves-kit/hooks/x.sh"}]}]}}' > "$R6c/.claude/settings.json"
run "$R6c" $FLAGS
expect "foreign kit hook entries are reported" has "note: .claude/settings.json holds 1 kit hook command(s)"
expect "and left in place" bash -c "jq -e '.hooks.Stop[0].hooks[0].command | contains(\"dwarves-kit\")' '$R6c/.claude/settings.json' >/dev/null"
R6d="$(newrepo)"
printf '# Verification (proof-of-done marker)\n\nPresence of this file opts this repo in.\n' > "$R6d/README.md"
run "$R6d" $FLAGS
expect "adopt's proof marker is left by a default run" has "edited (left alone): README.md"
run "$R6d" --take README.md
expect "take replaces adopt's proof marker" bash -c "grep -q 'Default branch: main' '$R6d/README.md' && grep -q 'proof-of-done marker' '$R6d/README.md.orig'"

# 12. a kit path in a template aborts the whole run before any write
TPL2="$(fixture_copy)"
printf 'see ~/.claude/dwarves-kit/AGENTS.md\n' >> "$TPL2/files/second.txt"
R7="$(newrepo)"
STAMP_TEMPLATES="$TPL2" run "$R7" $FLAGS
expect "a kit path in a template refuses the run" [ "$RC" -eq 1 ]
expect "the refusal names the file and the Fix" line_after "stamp: docs/second.txt would carry a path under the kit" "Fix: remove that text"
expect "nothing was written, not even the lock" bash -c "[ -z \"\$(ls -A '$R7' | grep -v '^.git\$')\" ]"
TPL3="$(fixture_copy)"; printf 'home /Users/someone/x\n' >> "$TPL3/files/second.txt"
STAMP_TEMPLATES="$TPL3" run "$(newrepo)" $FLAGS
expect "an absolute home path is refused too" [ "$RC" -eq 1 ]

# 13. key contract
TPL4="$(fixture_copy)"; printf 'x {{TAGS}}\n' >> "$TPL4/files/second.txt"
STAMP_TEMPLATES="$TPL4" run "$(newrepo)" $FLAGS
expect "a template using an undeclared key is refused" has "uses {{TAGS}} but its manifest row does not declare it"
TPL5="$(fixture_copy)"; printf 'x {{NOPE}}\n' >> "$TPL5/files/second.txt"; sed -i.bak 's/PRODUCT_ERE,/PRODUCT_ERE,NOPE,/' "$TPL5/manifest.d/10-second.tsv"
STAMP_TEMPLATES="$TPL5" run "$(newrepo)" $FLAGS
expect "an unknown declared key is refused" has "the unknown key NOPE"
TPL6="$(fixture_copy)"; printf 'copy\tfiles/second.txt\tdocs/second.txt\t0644\n' > "$TPL6/manifest.d/10-second.tsv"
STAMP_TEMPLATES="$TPL6" run "$(newrepo)" $FLAGS
expect "a manifest row with four columns is refused" has "empty keys column"
TPL7="$(fixture_copy)"; printf 'copy\tfiles/second.txt\tREADME.md\t0644\t-\n' >> "$TPL7/manifest.d/10-second.tsv"
STAMP_TEMPLATES="$TPL7" run "$(newrepo)" $FLAGS
expect "a target listed twice is refused" has "listed twice"

# 14. settings merge
R8="$(newrepo)"; mkdir -p "$R8/.claude"
cat > "$R8/.claude/settings.json" <<'EOF'
{"theme":"dark","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"foreign-hook.sh"}]}],"Stop":[{"hooks":[{"type":"command","command":"stop.sh"}]}]}}
EOF
run "$R8" $FLAGS
S="$R8/.claude/settings.json"
expect "merge keeps a foreign top-level key" bash -c "[ \"\$(jq -r .theme '$S')\" = dark ]"
expect "merge keeps a foreign hook in the same matcher group" bash -c "jq -e '.hooks.PreToolUse[0].hooks | map(.command) | index(\"foreign-hook.sh\") != null' '$S' >/dev/null"
expect "merge adds the stamp's hook to that group" bash -c "[ \$(jq '.hooks.PreToolUse[0].hooks | length' '$S') -eq 2 ]"
expect "merge keeps an unrelated event" bash -c "[ \"\$(jq -r '.hooks.Stop[0].hooks[0].command' '$S')\" = stop.sh ]"
expect "merge adds the SessionStart event" bash -c "jq -e '.hooks.SessionStart | length == 1' '$S' >/dev/null"
before="$(cksum < "$S")"; run "$R8"
expect "a second merge adds no duplicate" [ "$before" = "$(cksum < "$S")" ]
R8b="$(newrepo)"; mkdir -p "$R8b/.claude"
cat > "$R8b/.claude/settings.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"foreign-a.sh"}]},{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/scripts/hello.sh\""}]}],"SessionStart":[{"hooks":[{"type":"command","command":"foreign-b.sh"}]},{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/scripts/hello.sh\""}]}]}}
EOF
before="$(cksum < "$R8b/.claude/settings.json")"; run "$R8b" $FLAGS
expect "our entry found in a second group of the same matcher adds nothing" [ "$before" = "$(cksum < "$R8b/.claude/settings.json")" ]
expect "and the file reads unchanged" has "unchanged: .claude/settings.json"
R9="$(newrepo)"; mkdir -p "$R9/.claude"; echo '{ not json' > "$R9/.claude/settings.json"
run "$R9" $FLAGS
expect "invalid settings.json refuses the run" [ "$RC" -eq 1 ]
expect "and nothing else was written" bash -c "[ ! -e '$R9/README.md' ] && [ ! -e '$R9/.claude/team-stamp.lock' ] && [ \"\$(cat '$R9/.claude/settings.json')\" = '{ not json' ]"

# 15. values: flags, lock, defaults, refusals
R10="$(newrepo)"
run "$R10" --default-branch trunk --owner bob --tags app,lib --product-paths src/,lib/ --door-paths 'docs/legal/*,protocol/*' --door-approver carol --decision-tag needs-human
expect "the decision tag flag renders" grep -qxF 'decision tag: #needs-human' "$R10/docs/second.txt"
expect "tags always include dev" bash -c "grep -q '^value TAGS app,lib,dev' '$R10/.claude/team-stamp.lock'"
expect "product paths become an array body" grep -qxF 'product array: ("src/" "lib/")' "$R10/docs/second.txt"
expect "door paths become an array body" grep -qxF 'door array: ("docs/legal/*" "protocol/*")' "$R10/docs/second.txt"
expect "tags become an awk list" grep -qxF 'tags awk: "app", "lib", "dev"' "$R10/docs/second.txt"
expect "tags become colon words" grep -qxF 'tags colon: app: lib: dev:' "$R10/docs/second.txt"
expect "tags become an ERE" grep -qxF 'tags ere: app|lib|dev' "$R10/docs/second.txt"
expect "product paths become a regex" grep -q '^product: \^(src/|lib/)$' "$R10/docs/second.txt"
expect "door paths become case alternatives" grep -q '^door: docs/legal/\*|protocol/\*$' "$R10/docs/second.txt"
run "$R10"
expect "a no-flag re-run reuses the lock's values" bash -c "[ \$(printf '%s\n' \"\$1\" | grep -Evc '^(unchanged|using): ') -eq 0 ]" _ "$OUT"
R11="$(newrepo)"
run "$R11" --default-branch main
expect "a missing owner refuses with the Fix line" line_after "stamp: no owner" "Fix: bash lib/stamp.sh --owner"
run "$R11" --owner alice
expect "a missing default branch (no origin) refuses with the Fix line" line_after "stamp: no default branch" "Fix: bash lib/stamp.sh --default-branch main"
run "$R11" --owner "@alice" --default-branch main
expect "an owner with @ is refused" has "bad --owner"
run "$R11" --owner alice --default-branch main --tags "Bad Tag"
expect "a bad tag list is refused" has "bad --tags"
R12="$(newrepo)"; git -C "$R12" remote add origin https://example.invalid/x.git
git -C "$R12" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop 2>/dev/null
run "$R12" --owner alice
expect "the default branch is read from origin/HEAD" bash -c "grep -q '^Default branch: develop' '$R12/README.md'"

# 16. target refusals
NG="$(mktemp -d "$WORK/ng.XXXXXX")"; NG="$(cd "$NG" && pwd)"
run "$NG" $FLAGS
expect "a non-git target is refused with the git init fix" line_after "stamp: $NG is not a git repo" "Fix: git init"
run "$ROOT" $FLAGS
expect "the kit's own tree is refused" has "refusing to stamp the kit's own tree"
run "$WORK/missing-dir" $FLAGS
expect "a missing target dir is refused" [ "$RC" -eq 1 ]
OUT="$($STAMP --bogus 2>&1)"; RC=$?
expect "an unknown flag is a usage error (64)" [ "$RC" -eq 64 ]
OUT="$($STAMP --check --dry-run "$R" 2>&1)"; RC=$?
expect "two modes are a usage error (64)" [ "$RC" -eq 64 ]

# 17. --only
R13="$(newrepo)"
run "$R13" --only second $FLAGS
expect "--only writes just the named group" bash -c "[ -f '$R13/docs/second.txt' ] && [ ! -e '$R13/README.md' ]"
run "$R13" --only nope $FLAGS
expect "--only with an unknown group is refused" has "no manifest group named 'nope'"
run "$R13" $FLAGS
expect "a later full run keeps the group's file and adds the rest" bash -c "[ -f '$R13/README.md' ] && grep -q '^file docs/second.txt ' '$R13/.claude/team-stamp.lock'"

# 17b. the owners seed hook: one row per script and workflow of the merged manifest
TPLO="$WORK/tpl-owners"; mkdir -p "$TPLO/manifest.d" "$TPLO/files/scripts" "$TPLO/files/.github/workflows"
printf '#!/usr/bin/env bash\n' > "$TPLO/files/scripts/a.sh"; printf '#!/usr/bin/env bash\n' > "$TPLO/files/scripts/test-a.sh"; printf 'name: CI\n' > "$TPLO/files/.github/workflows/ci.yml"
printf 'copy\tfiles/scripts/a.sh\tscripts/a.sh\t0755\t-\ncopy\tfiles/scripts/test-a.sh\tscripts/test-a.sh\t0755\t-\n' > "$TPLO/manifest.d/10-scripts.tsv"
printf 'copy\tfiles/.github/workflows/ci.yml\t.github/workflows/ci.yml\t0644\t-\n' > "$TPLO/manifest.d/20-ci.tsv"
printf 'hook\tlib/stamp/owners-seed.sh\tOWNERS.md\t0644\tOWNER\n' > "$TPLO/manifest.d/30-owners.tsv"
R14="$(newrepo)"
STAMP_TEMPLATES="$TPLO" run "$R14" --only owners $FLAGS
expect "the owners seed lists every script of every group, even under --only" bash -c "grep -q '^| \`scripts/a.sh\` ' '$R14/OWNERS.md' && grep -q '^| \`scripts/test-a.sh\` | Test for scripts/a.sh | @alice | |' '$R14/OWNERS.md' && grep -q '^| \`.github/workflows/ci.yml\` ' '$R14/OWNERS.md'"
expect "the owners seed lists no row for itself" bash -c "! grep -q '^| \`OWNERS.md\`' '$R14/OWNERS.md'"

# 17c. nothing a stamp writes trips a bare-hex secret scan
hexscan() { # hexscan <file>: print any 64-hex run not directly after a digest marker
  sed -E "s/(sha256:|sha256: |sha256=|sha256-|sha256 \"|sha256 ')[0-9a-f]{64}//g" "$1" | grep -E '[0-9a-f]{64}'
}
R15="$(newrepo)"; run "$R15" $FLAGS
git -C "$R15" add -A >/dev/null 2>&1; git -C "$R15" diff --cached > "$WORK/staged.diff"
expect "the staged stamp output is not empty" [ -s "$WORK/staged.diff" ]
none_hex() { ! hexscan "$1" >/dev/null; }
expect "the staged diff holds no bare 64-hex run" none_hex "$WORK/staged.diff"
expect "the lock writes every hash as sha256:<hex>" bash -c "[ \$(grep -c '^file .* sha256:[0-9a-f]\{64\}\$' '$R15/.claude/team-stamp.lock') -eq \$(grep -c '^file ' '$R15/.claude/team-stamp.lock') ]"
bare="$(printf 'a%.0s' $(seq 1 64))"; printf 'digest %s\n' "$bare" > "$WORK/bare.txt"; printf 'sha256:%s\n' "$bare" > "$WORK/marked.txt"
catch_hex() { hexscan "$1" >/dev/null; }
expect "the scan catches a bare hex (self-test)" catch_hex "$WORK/bare.txt"
expect "the scan allows a marked digest (self-test)" none_hex "$WORK/marked.txt"
# an older lock with bare hex still reads: rewrite R15's lock the old way and expect a clean run
sed -E 's/ sha256:([0-9a-f]{64})$/ \1/' "$R15/.claude/team-stamp.lock" > "$WORK/old.lock"; cp "$WORK/old.lock" "$R15/.claude/team-stamp.lock"
run "$R15"; expect "a lock with bare hex still reads as unedited" bash -c "[ \$(printf '%s\n' \"\$1\" | grep -Evc '^(unchanged|using): ') -eq 0 ]" _ "$OUT"

# 17d. values: control characters, dot-dot paths, and the values-in-use report
for flagname in default-branch owner tags product-paths door-paths door-approver board-file decision-tag; do
  for bad in "$(printf 'a\nb')" "$(printf 'a\rb')" "$(printf 'a\tb')"; do
    RX="$(newrepo)"; OUT="$($STAMP --default-branch main --owner alice "--$flagname" "$bad" "$RX" 2>&1)"; RC=$?
    refused_ctl=1; [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^stamp: the value of --$flagname holds a newline, a carriage return or a tab" && refused_ctl=0
    [ "$refused_ctl" -eq 0 ] || echo "    $flagname: rc=$RC"
    expect "a $flagname value with a newline, CR or tab is refused first" [ "$refused_ctl" -eq 0 ]
  done
done
RX="$(newrepo)"; OUT="$($STAMP --default-branch main --owner alice --product-paths "$(printf 'src/\nx"; touch PWNED; "')" "$RX" 2>&1)"; RC=$?
expect "a product path with a newline and a quote is refused, nothing written" bash -c "[ $RC -eq 1 ] && [ ! -e '$RX/.claude' ] && [ ! -e '$RX/PWNED' ]"
RX="$(newrepo)"
for badv in "--board-file ../../x" "--board-file /etc/x" "--product-paths ../src/" "--product-paths /abs/" "--door-paths a/../b" "--door-paths /x"; do
  # shellcheck disable=SC2086
  OUT="$($STAMP --default-branch main --owner alice $badv "$RX" 2>&1)"; RC=$?
  expect "$badv is refused ($RC)" bash -c "[ $RC -eq 1 ] && printf '%s\n' \"\$1\" | tail -n 2 | sed -n 2p | grep -q '^Fix: '" _ "$OUT"
done
RX="$(newrepo)"; run "$RX" --default-branch main --owner alice --board-file docs/BOARD.md --door-approver carol
expect "every run prints the values in use" has "using: OWNER=alice (flag)"
expect "a default value says it is a default" has "using: DECISION_TAG=decision (default)"
run "$RX"
expect "a no-flag re-run says the values came from the lock" has "using: BOARD_FILE=docs/BOARD.md (lock)"
# a planted lock: its values are used, seen, and checked
sed -i.bak 's|^value BOARD_FILE .*|value BOARD_FILE ../../x|' "$RX/.claude/team-stamp.lock" && rm -f "$RX/.claude/team-stamp.lock.bak"
run "$RX"
expect "a planted lock with a dot-dot board file is refused" bash -c "[ $RC -eq 1 ]" 
expect "and the refusal names the value" has "--board-file starts with / or has a .. component"
sed -i.bak 's|^value BOARD_FILE .*|value BOARD_FILE docs/BOARD.md|; s|^value DOOR_APPROVER .*|value DOOR_APPROVER mallory|' "$RX/.claude/team-stamp.lock" && rm -f "$RX/.claude/team-stamp.lock.bak"
run "$RX"
expect "a planted approver is used but shown, with its source" has "using: DOOR_APPROVER=mallory (lock)"

# 17e. take: the backup never goes through a symlink
TPLB="$(fixture_copy)"; RB="$(newrepo)"
STAMP_TEMPLATES="$TPLB" run "$RB" $FLAGS
printf 'Newer line\n' >> "$TPLB/files/second.txt"
printf 'plain old backup\n' > "$RB/docs/second.txt.orig"
OUTSIDE_B="$WORK/outside-backup-target"
ln -s "$OUTSIDE_B" "$RB/docs/second.txt.orig.1"
STAMP_TEMPLATES="$TPLB" run "$RB" --take docs/second.txt
expect "take with a dangling symlink at .orig.1 exits 0" [ "$RC" -eq 0 ]
expect "nothing was written through the dangling link" [ ! -e "$OUTSIDE_B" ]
expect "the link itself is untouched" [ -L "$RB/docs/second.txt.orig.1" ]
expect "the backup went to the next free name" [ -f "$RB/docs/second.txt.orig.2" ]
expect "and holds the old text" bash -c "grep -q '^door:' '$RB/docs/second.txt.orig.2' && ! grep -q 'Newer line' '$RB/docs/second.txt.orig.2'"
expect "the plain .orig was not overwritten" bash -c "[ \"\$(cat '$RB/docs/second.txt.orig')\" = 'plain old backup' ]"

# 18. an empty manifest dir
TPL8="$WORK/empty-tpl"; mkdir -p "$TPL8/manifest.d"
STAMP_TEMPLATES="$TPL8" run "$(newrepo)" $FLAGS
expect "no manifest rows is refused" has "no manifest rows"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
