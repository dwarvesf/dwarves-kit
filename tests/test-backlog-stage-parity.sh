#!/usr/bin/env bash
# test-backlog-stage-parity.sh -- hooks/backlog-stage.sh reproduces the Python backlog-stage on
# every case in tests/fixtures/backlog-stage-parity/cases.jsonl. The expected results were
# generated from the Python hook behind its shim (gen-expected.sh) before the bash port replaced
# it: exit code, stdout, stderr, the files left behind, the staging file, and the exact prompt the
# model was sent. A detached run is awaited through the harness's `settle` field.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/backlog-stage-parity"
HOOK="$KIT_DIR/hooks/backlog-stage.sh"
# shellcheck source=lib/hook-parity.sh
source "$KIT_DIR/tests/lib/hook-parity.sh"

out=$(hp_check "$FIX/cases.jsonl" "$FIX/expected.jsonl" bash "$HOOK")
rc=$?
printf '%s\n' "$out" | sed 's/^\([0-9]* passed, [0-9]* failed\)$/backlog-stage parity: \1/'
fail=0; [ "$rc" -eq 0 ] || fail=1

# Large payload: a 2 MB transcript text goes through the hook whole, inline and detached. The Python
# held it in memory; a bash port that passed it as an argument would hit the OS argument limit
# (about 1 MB on macOS) and stage nothing, so the payload must travel by file.
T="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
mkdir -p "$T/cwd/_meta" "$T/home"
printf '# Backlog\n' > "$T/cwd/_meta/BACKLOG.md"
head -c 2097152 /dev/zero | tr '\0' 'a' > "$T/filler"
printf ' we should add a retry to the uploader later' >> "$T/filler"
jq -n -c --rawfile t "$T/filler" '{type: "user", message: {content: [{type: "text", text: $t}]}}' > "$T/cwd/t.jsonl"
cat > "$T/home/ext.sh" <<'EXT'
#!/bin/sh
cat > "$HOME/prompt.txt"
wc -c < "$HOME/prompt.txt" | tr -d " " > "$HOME/prompt.size"
printf '[{"title":"Add retry to uploader","intent":"robust uploads","approach":"backoff","u":"hi","f":"mid","home":"uploader"}]'
EXT
printf '{"transcript_path":"%s/cwd/t.jsonl"}' "$T" > "$T/payload"
for mode in inline detached; do
  rm -f "$T/cwd/_meta/backlog-staging.md" "$T/home/prompt.size"
  [ "$mode" = inline ] && sync=1 || sync=0
  env -i PATH="$PATH" HOME="$T/home" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 REPO_ROOT="$T/cwd" \
    BACKLOG_STAGE_STATE_DIR="$T/home/bs" BACKLOG_STAGE_AUTO=1 BACKLOG_STAGE_SYNC=$sync BACKLOG_STAGE_MIN_INTERVAL=0 \
    BACKLOG_STAGE_MAXCHARS=3000000 BACKLOG_STAGE_EXTRACTOR="bash $T/home/ext.sh" \
    bash "$HOOK" < "$T/payload" >/dev/null 2>&1
  for _ in $(seq 1 100); do [ -s "$T/cwd/_meta/backlog-staging.md" ] && [ -s "$T/home/prompt.size" ] && break; sleep 0.3; done
  size=$(cat "$T/home/prompt.size" 2>/dev/null || echo 0)
  if [ "$size" -gt 2097152 ] && grep -q '^## \[staged\] Add retry to uploader' "$T/cwd/_meta/backlog-staging.md" 2>/dev/null; then
    echo "  PASS 2 MB transcript, $mode: prompt of $size bytes, candidate staged"
  else
    fail=1; echo "  FAIL 2 MB transcript, $mode: prompt of $size bytes"
  fi
done
mv -f "$T" "$T.discard" 2>/dev/null
[ "$fail" -eq 0 ]
