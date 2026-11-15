#!/usr/bin/env bash
# test-orchestrate-redact-inode.sh -- `_redact_secrets_file` must keep the stream file's inode and
# must not touch a path a newer run owns.
#
# Incident: an operator restarted the orchestrator mid-wave. The OLD run's watchdog outlived the kill,
# saw its child die, and redacted `.orchestrate/<id>.stream.jsonl` after the NEW run had truncated
# that path and started a new `claude -p` on it. The old `mv -f` swapped in a new inode, so the live
# session kept writing to the unlinked old inode (lost transcript, lost token telemetry, and a false
# stall warning since the watchdog reads the path's mtime).
#
#   (a) a live writer keeps writing to the SAME inode across a redaction; content is redacted
#   (b) the ownership guard skips redaction when the path was re-truncated or replaced by a newer run
#   (c) the redaction patterns still redact (the end-to-end pin is tests/test-orchestrate-hardening.sh)
#
# Negative control: KIT_REDACT_OLD_MV=1 swaps in the pre-fix `mv -f` body, and (a) must fail.
#
# Fixtures are assembled from fragments at runtime so no credential-shaped literal sits in the file.
#
# Run: bash tests/test-orchestrate-redact-inode.sh   (exit 0 = pass, 1 = fail)

set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
WPID=""
trap '[ -n "$WPID" ] && kill "$WPID" 2>/dev/null; rm -rf "$TMP"' EXIT
export DWARVES_KIT_LOG_DIR="$TMP/kitlogs"

# shellcheck source=../lib/queue/orchestrate.sh
source "$ORCH"

if [ "${KIT_REDACT_OLD_MV:-0}" = 1 ]; then
  # The pre-fix body, verbatim apart from the pattern list: write a copy, `mv -f` it over the path.
  _redact_secrets_file() {
    local f="$1" tmp
    [ -n "$f" ] && [ -s "$f" ] || return 0
    tmp=$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX" 2>/dev/null) || return 0
    if sed -E -e 's/(sk|gho|ghp|ghu|ghs|ghr|glpat)[_-][A-Za-z0-9_-]{8,}/[REDACTED]/g' "$f" > "$tmp" 2>/dev/null; then
      mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp"
    else
      rm -f "$tmp"
    fi
  }
fi

SECRET="sk""-ant-api03-ABCDEFGH12345678"

# ---- (a) a live writer keeps its inode across a redaction ----
F="$TMP/a.stream.jsonl"
printf 'line1 %s\n' "$SECRET" > "$F"
claim=$(_stream_claim "$F")
ino_before=$(_inode "$F")
( while :; do printf 'tick\n'; sleep 0.05; done >> "$F" ) &
WPID=$!
sleep 0.3
_redact_secrets_file "$F" "$claim" 2>/dev/null
sleep 0.3
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; WPID=""
ino_after=$(_inode "$F")
[ "$ino_before" = "$ino_after" ] && pass "(a) inode unchanged across redaction ($ino_before)" \
  || fail "(a) inode changed $ino_before -> $ino_after (a live writer is now detached)"
if grep -q "$SECRET" "$F" || ! grep -q '^line1 \[REDACTED\]$' "$F"; then
  fail "(a) redacted content wrong: $(head -1 "$F")"
else
  pass "(a) secret redacted in place"
fi
# The writer's appends after the redaction must still land in the file the path names.
n_ticks=$(grep -c '^tick$' "$F")
[ "$n_ticks" -ge 4 ] && pass "(a) the live writer's appends all reached the path ($n_ticks ticks)" \
  || fail "(a) live writer's output lost: only $n_ticks ticks in the path"

# ---- (b) ownership guard ----
# b1: re-truncated by a newer run (same inode, new owner token) -> skipped, content untouched.
F="$TMP/b1.stream.jsonl"
: > "$F"; old_claim=$(_stream_claim "$F")
: > "$F"; new_claim=$(_stream_claim "$F")           # the NEW run truncates + claims
printf 'new run %s\n' "$SECRET" > "$F"
err=$(_redact_secrets_file "$F" "$old_claim" 2>&1 >/dev/null)
grep -q "$SECRET" "$F" && pass "(b1) re-truncated path left alone by the old run" || fail "(b1) old run redacted a path the new run owns"
case "$err" in *"no longer owned"*) pass "(b1) one-line stderr note emitted" ;; *) fail "(b1) no skip note: '$err'" ;; esac
_redact_secrets_file "$F" "$new_claim" 2>/dev/null
grep -q "$SECRET" "$F" && fail "(b1) the real owner could not redact" || pass "(b1) the current owner still redacts"

# b2: path replaced by a different inode (new file via rename) -> skipped.
F="$TMP/b2.stream.jsonl"
printf 'old %s\n' "$SECRET" > "$F"; claim=$(_stream_claim "$F")
printf 'replaced %s\n' "$SECRET" > "$F.new"; mv -f "$F.new" "$F"
err=$(_redact_secrets_file "$F" "$claim" 2>&1 >/dev/null)
if grep -q "$SECRET" "$F"; then
  case "$err" in *"no longer owned"*) pass "(b2) replaced inode skipped with a note" ;; *) fail "(b2) no skip note" ;; esac
else
  fail "(b2) a replaced path was redacted by a non-owner"
fi

# b3: no claim given -> unguarded, behaves as before.
F="$TMP/b3.stream.jsonl"; printf 'x %s\n' "$SECRET" > "$F"
_redact_secrets_file "$F"
grep -q "$SECRET" "$F" && fail "(b3) unclaimed call did not redact" || pass "(b3) unclaimed call still redacts"

# ---- (c) pattern coverage ----
F="$TMP/c.stream.jsonl"
gh_tok="gh""p_abcdefgh12345678"
slack_tok="xo""xb-12345678-abcdef"
aws_key="AK""IAABCDEFGHIJKLMNOP"
bearer="Authorization: Bear""er abcdefghij1234"
printf '%s\n' "$gh_tok" "$slack_tok" "$aws_key" "$bearer" "plain line" > "$F"
claim=$(_stream_claim "$F")
_redact_secrets_file "$F" "$claim"
leaks=$(grep -cE "$gh_tok|$slack_tok|$aws_key|abcdefghij1234" "$F")
if [ "$leaks" = 0 ] && grep -q '^plain line$' "$F" && grep -q 'Bearer \[REDACTED\]' "$F"; then
  pass "(c) token, slack, AWS and bearer shapes redacted; plain line kept"
else
  fail "(c) pattern coverage: $(cat "$F")"
fi

# ---- clean file: left byte-identical ----
F="$TMP/d.stream.jsonl"; printf 'nothing secret\n' > "$F"; claim=$(_stream_claim "$F")
_redact_secrets_file "$F" "$claim"
[ "$(cat "$F")" = "nothing secret" ] && pass "clean file left byte-identical" || fail "clean file altered"

echo "=== $fails failure(s) ==="
[ "$fails" = 0 ]
