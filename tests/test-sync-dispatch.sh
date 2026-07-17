#!/usr/bin/env bash
# cmd_sync dispatcher tests: config resolution from .kit.toml for BOTH board
# conventions (_meta/BACKLOG.md and root-level BACKLOG.md), user-flag-wins
# forwarding, and the unconfigured / missing-backlog error paths. The python
# engine is stubbed with a fake python3 on PATH that prints its argv.
set -uo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1 -- got: $3"; fi; }

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
mkdir -p "$d/bin"
cat > "$d/bin/python3" <<'STUB'
#!/usr/bin/env bash
printf 'ARGV:%s\n' "$*"
STUB
chmod +x "$d/bin/python3"
export PATH="$d/bin:$PATH"
export KIT_CONFIG_ROOT="$d/kitroot"; mkdir -p "$d/kitroot"
printf '[sync]\nsources = ""\n' > "$d/kitroot/kit.toml"

# repo A: _meta/BACKLOG.md convention
mkdir -p "$d/repoA/_meta"; touch "$d/repoA/_meta/BACKLOG.md"
git -C "$d/repoA" init -q
printf '[sync]\napps = "reminders"\nreminders_list = "ListA"\n' > "$d/repoA/.kit.toml"
out="$(bash "$KIT_ROOT/bin/board" sync --backlog-file "$d/repoA/_meta/BACKLOG.md" 2>&1)"
check "nested _meta board resolves its repo .kit.toml" \
  '[[ "$out" == *"--apps reminders"* && "$out" == *"--list ListA"* ]]' "$out"

# repo B: root-level BACKLOG.md convention (the fleet-majority case)
mkdir -p "$d/repoB"; touch "$d/repoB/BACKLOG.md"
git -C "$d/repoB" init -q
printf '[sync]\nsources = "hermes"\nhermes_home = "/h"\nhermes_target = "t"\n' > "$d/repoB/.kit.toml"
out="$(bash "$KIT_ROOT/bin/board" sync --backlog-file "$d/repoB/BACKLOG.md" 2>&1)"
check "root-level board resolves .kit.toml via the LEGACY sources alias" \
  '[[ "$out" == *"--apps hermes"* && "$out" == *"--hermes-home /h"* ]]' "$out"

# user flag lands after config-derived flags (argparse last-wins)
out="$(bash "$KIT_ROOT/bin/board" sync --apps notion \
        --backlog-file "$d/repoA/_meta/BACKLOG.md" 2>&1)"
check "user --apps forwarded after config flags (user wins)" \
  '[[ "$out" == *"--apps reminders"*"--apps notion"* ]]' "$out"

# unconfigured repo: clean exit 2 naming the right .kit.toml path
mkdir -p "$d/repoC/_meta"; touch "$d/repoC/_meta/BACKLOG.md"
git -C "$d/repoC" init -q
out="$(bash "$KIT_ROOT/bin/board" sync --backlog-file "$d/repoC/_meta/BACKLOG.md" 2>&1)"; rc=$?
check "unconfigured repo exits 2 with the repo's own .kit.toml path" \
  '[[ $rc -eq 2 && "$out" == *"$d/repoC/.kit.toml"* ]]' "rc=$rc $out"

# missing backlog: clean exit 2, no raw cd error
out="$(bash "$KIT_ROOT/bin/board" sync --backlog-file "$d/nope/BACKLOG.md" 2>&1)"; rc=$?
check "missing backlog exits 2 cleanly" \
  '[[ $rc -eq 2 && "$out" == *"no backlog at"* ]]' "rc=$rc $out"

printf '=== %d/%d passed ===\n' "$PASS" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
