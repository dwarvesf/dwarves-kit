#!/usr/bin/env bash
# node-fixture.sh -- a tiered mega-goal repo for tests/test-known-failures.sh and
# tests/test-orchestrate-tiered.sh. Source it; it defines functions only.
#
#   nf_init <dir>                 bare origin + a work clone on main. Main carries .kit.toml (verify = tiered),
#                                 a stub suite, a known-failures list and an empty mega dir.
#   nf_node <dir> <branch> <file> <content>
#                                 a branch cut from origin/main that adds <file>; pushed, and fetched into work
#   nf_mega <dir> <id>:<branch>:<pr> ...
#                                 writes work/mega/ROADMAP.md and the goal files for the given sub-goals
#   nf_heads <dir> <pr>:<branch> ...
#                                 records each branch tip as the PR head the gh stub reports
#   nf_env <dir>                  exports the stubs (gh, WAVE_MERGE_CMD recorder) and the config fences
#
# The stub suite (tests/suite.sh in the repo) is driven by env:
#   STUB_FAIL="a,b"   failures to print as `  FAIL: <name>`
#   STUB_COUNT=<n>    passed count in the summary (default 10)
#   STUB_COUNT_SEQ=<file>  one count per line, one consumed per invocation (then STUB_COUNT)
#   STUB_CRASH=1      print a crash and exit 1 with no failure line
#   STUB_LOG=<file>   append one line per invocation (args and cwd)
# and fails on its own when a.txt and b.txt both exist (the semantic-conflict pair: each node alone is green).

NF_STUB_SUITE='#!/usr/bin/env bash
[ -n "${STUB_LOG:-}" ] && echo "suite $* cwd=$(pwd -P)" >> "$STUB_LOG"
[ -n "${STUB_LOG:-}" ] && echo "env cfg=${KIT_CONFIG_ROOT:-} op=${KIT_CONFIG_OPERATOR:-} proj=${KIT_PROJECT_ROOT:-} ledger=${KIT_LEDGER_DIR:-} logdir=${DWARVES_KIT_LOG_DIR:-}" >> "$STUB_LOG"
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
if [ "${STUB_CRASH:-0}" = 1 ]; then echo "boom: segfault"; exit 1; fi
fails=0
while IFS= read -r f; do [ -n "$f" ] && { echo "  FAIL: $f"; fails=$((fails + 1)); }; done <<EOT
$(printf "%s" "${STUB_FAIL:-}" | tr "," "\n")
EOT
if [ -f a.txt ] && [ -f b.txt ]; then echo "  FAIL: a and b conflict"; fails=$((fails + 1)); fi
count="${STUB_COUNT:-10}"
case "$(pwd -P)" in */merged) count="${STUB_COUNT_MERGED:-$count}" ;; esac
if [ -n "${STUB_COUNT_SEQ:-}" ] && [ -s "$STUB_COUNT_SEQ" ]; then count="$(head -n 1 "$STUB_COUNT_SEQ")"; tail -n +2 "$STUB_COUNT_SEQ" > "$STUB_COUNT_SEQ.n"; mv -f "$STUB_COUNT_SEQ.n" "$STUB_COUNT_SEQ"; fi
echo "suite: $count passed, $fails FAILED"
[ "$fails" = 0 ]
'

NF_KIT_TOML="[mega]
verify = \"tiered\"

[test]
join_cmd = \"bash tests/suite.sh\"
known_failures = \"tests/known-failures.txt\"
failure_line = '^  FAIL: (.*)\$'
count_line = '^suite: ([0-9]+) passed, ([0-9]+) FAILED\$'
"

nf_git() { local d="$1"; shift; git -C "$d" -c user.email=t@example.com -c user.name=test "$@"; }

nf_init() {
  local d="$1" g
  mkdir -p "$d"
  git init -q --bare "$d/origin.git" 2>/dev/null
  git clone -q "$d/origin.git" "$d/work" 2>/dev/null
  git clone -q "$d/origin.git" "$d/push" 2>/dev/null
  git -C "$d/push" checkout -q -b main 2>/dev/null
  mkdir -p "$d/push/tests"
  printf '%s' "$NF_KIT_TOML" > "$d/push/.kit.toml"
  printf '%s' "$NF_STUB_SUITE" > "$d/push/tests/suite.sh"
  printf '# one name per line\nSkim settings panel wrong\n' > "$d/push/tests/known-failures.txt"
  nf_git "$d/push" add -A
  nf_git "$d/push" commit -q -m "chore: base"
  git -C "$d/push" push -q origin main 2>/dev/null
  git -C "$d/origin.git" symbolic-ref HEAD refs/heads/main
  git -C "$d/work" fetch -q origin 2>/dev/null
  git -C "$d/work" checkout -q -b chore/run origin/main 2>/dev/null
  for g in work push; do git -C "$d/$g" config user.email t@example.com; git -C "$d/$g" config user.name test; done
  mkdir -p "$d/work/mega/goals"
}

nf_node() {
  local d="$1" branch="$2" file="$3" content="$4"
  git -C "$d/push" checkout -q main 2>/dev/null
  git -C "$d/push" pull -q origin main 2>/dev/null
  git -C "$d/push" checkout -q -b "$branch" 2>/dev/null
  mkdir -p "$d/push/$(dirname "$file")"
  printf '%s\n' "$content" > "$d/push/$file"
  nf_git "$d/push" add -A
  nf_git "$d/push" commit -q -m "feat: $branch"
  git -C "$d/push" push -q origin "$branch" 2>/dev/null
  git -C "$d/work" fetch -q origin "$branch:$branch" 2>/dev/null
  git -C "$d/push" checkout -q main 2>/dev/null
}

# nf_pullref <dir> <pr> <file> <content>: a PR head that exists only as refs/pull/<pr>/head on origin, so the
# join must fetch it; the sha lands in heads/<pr>.
nf_pullref() {
  local d="$1" pr="$2" file="$3" content="$4"
  git -C "$d/push" checkout -q -b "pull-$pr" main 2>/dev/null
  printf '%s\n' "$content" > "$d/push/$file"
  nf_git "$d/push" add -A
  nf_git "$d/push" commit -q -m "feat: pull $pr"
  git -C "$d/push" push -q origin "HEAD:refs/pull/$pr/head" 2>/dev/null
  mkdir -p "$d/heads"
  git -C "$d/push" rev-parse HEAD > "$d/heads/$pr"
  git -C "$d/push" checkout -q main 2>/dev/null
}

nf_mega() {
  local d="$1" spec id branch pr n=0
  shift
  { printf '# Mega-goal: tiered fixture\n## Sub-goals\n'
    for spec in "$@"; do
      id="${spec%%:*}"; pr="${spec##*:}"
      printf -- '- [ ] %s node , auto , PR #%s\n' "$id" "$pr"
    done; } > "$d/work/mega/ROADMAP.md"
  for spec in "$@"; do
    id="${spec%%:*}"; pr="${spec##*:}"; branch="${spec#*:}"; branch="${branch%:*}"
    n=$((n + 1))
    printf '# %s: node\n**Branch:** %s\n\n## Touches\n- %s.txt\n' "$id" "$branch" "$n" > "$d/work/mega/goals/0$n-$id.md"
  done
}

nf_heads() {
  local d="$1" spec pr branch
  shift
  mkdir -p "$d/heads"
  for spec in "$@"; do
    pr="${spec%%:*}"; branch="${spec#*:}"
    git -C "$d/work" rev-parse "$branch" > "$d/heads/$pr"
  done
}

nf_env() {
  local d="$1"
  cat > "$d/gh" <<'EOF'
#!/usr/bin/env bash
# gh stub: `pr view <n> --json headRefOid|state -q ...`
n="$3"
case "$*" in
  *headRefOid*) cat "$NF_HEADS/$n" 2>/dev/null || exit 1 ;;
  *state*) echo "${GH_STATE:-OPEN}" ;;
  *) exit 1 ;;
esac
EOF
  cat > "$d/hook" <<'EOF'
#!/usr/bin/env bash
# merge hook recorder: logs argv; refuses with 75 when --expect-head differs from the head file now
echo "$*" >> "$HOOK_LOG"
pr="$1"; exp=""
while [ $# -gt 0 ]; do [ "$1" = "--expect-head" ] && exp="$2"; shift; done
if [ -n "$exp" ] && [ -f "$NF_HEADS/$pr" ] && [ "$(cat "$NF_HEADS/$pr")" != "$exp" ]; then exit 75; fi
exit "${MOCK_RC:-0}"
EOF
  chmod +x "$d/gh" "$d/hook"
  : > "$d/hook.log"
  export NF_HEADS="$d/heads" HOOK_LOG="$d/hook.log" MEGA_MERGE_GH="$d/gh" WAVE_MERGE_CMD="$d/hook"
  mkdir -p "$d/cfg-root" "$d/cfg-op"
  : > "$d/cfg-root/kit.toml"
  export KIT_CONFIG_ROOT="$d/cfg-root" KIT_CONFIG_OPERATOR="$d/cfg-op" KIT_PROJECT_ROOT="$d/cfg-proj"
}
